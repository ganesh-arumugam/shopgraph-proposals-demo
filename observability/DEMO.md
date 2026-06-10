# ShopGraph Observability Demo

One `trace_id` across logs, traces, and metrics, on a local Apollo Router federated
supergraph (orders + products).

The narrative: metrics tell you something is wrong, traces tell you where, logs tell you
why, and it is the same `trace_id` end to end. Verified against Apollo Router v2.15.0.

## Architecture

The router emits all three signals. Traces flow through an OpenTelemetry Collector, which
decouples the router from the trace backend: swapping or adding a destination (Tempo, an
APM, a second backend) is a change in the collector, not in the router config.

```text
  Client ──GraphQL──▶  Apollo Router :4000  ──subgraph fetch──▶  products / orders :4001
                            │
                            └──OTLP traces──▶  OTel Collector :4327  ──▶  Jaeger :16686

  Prometheus :9090  ──scrapes /metrics :9091──▶  Apollo Router
  Grafana :3000     ──reads──▶  Prometheus

  HOST   : Apollo Router, products / orders subgraphs
  DOCKER : OTel Collector, Jaeger, Prometheus, Grafana

  Traces  : Router ▶ Collector ▶ Jaeger     (the collector decouples the trace backend)
  Metrics : Prometheus scrapes Router ▶ Grafana visualizes
  Logs    : Router stdout JSON, trace_id on every line
```

How the three pillars share one `trace_id`:

```text
                          Incoming request
                                 │
        no traceparent ──────────┤────────── traceparent present
                 │                                    │
                 ▼                                    ▼
       Router MINTS a trace_id             Router CONTINUES the client's trace_id
                 │                                    │
                 └──────────────┬─────────────────────┘
                                ▼
                          one trace_id
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
            LOGS              TRACES            METRICS
     trace_id on every   router + subgraph   request lifecycle
     line (display_      spans in Jaeger,    in Prometheus /
     trace_id)           one trace_id        Grafana
```

## Quick start (hands-free driver)

Everything runs through [`demo.sh`](./demo.sh). Make sure Docker is running first.

```bash
./observability/demo.sh up          # Jaeger + Prometheus + Grafana + subgraphs + router
./observability/demo.sh status      # what is running, URLs, scrape health
./observability/demo.sh open        # open the Grafana dashboard + Jaeger

# scenarios (each prints what to look at):
./observability/demo.sh query       # NO traceparent  -> router MINTS a trace_id
./observability/demo.sh propagate   # client traceparent -> router CONTINUES it
./observability/demo.sh load [secs]  # sustained traffic so Grafana panels fill in (default 20s)
./observability/demo.sh latency      # orders slowdown (~800ms), both subgraphs
./observability/demo.sh error        # subgraph error, populates the errors panel
./observability/demo.sh reset        # disarm latency/error, back to clean
./observability/demo.sh down         # stop everything
```

The driver starts the router and subgraphs as background processes and writes their logs to
`observability/.run/router.log` and `observability/.run/subgraphs.log`. That is where the
`grep` commands below read from. (Also available as `npm run obs:up` / `obs:down` / `obs:status`.)

## Endpoints

| Service | URL | Purpose |
|---|---|---|
| Grafana dashboard | http://localhost:3000/d/shopgraph-router | the metrics view to present (use this) |
| Jaeger | http://localhost:16686 | trace waterfalls |
| Router GraphQL | http://localhost:4000/ | the supergraph (default path is `/`) |
| Router metrics | http://localhost:9091/metrics | Prometheus scrape target |
| Prometheus | http://localhost:9090 | raw PromQL (Grafana is nicer) |

Grafana opens with no login (anonymous admin, dark theme). The dashboard **ShopGraph Router
Observability** is auto-provisioned: router p50/p95/p99, request rate by subgraph, p95 by
subgraph (orders red, products green), GraphQL errors by code, and stat tiles. It refreshes
every 5s over the last 30 minutes, so a full scenario run stays on screen while you talk.

Note: a single `query` or `propagate` is one request, which is invisible on rate-based
panels. Use `load` or `latency` to make Grafana light up.

## The `trace_id` story (logs)

This is the core idea, shown with two one-request commands.

**No inbound traceparent: the router mints the id.**
```bash
./observability/demo.sh query
tail -20 observability/.run/router.log | \
  jq -rR 'fromjson? | select(.kind=="router.request") | {trace_id, incoming: (.spans[]|select(.name=="router")|."debug.incoming.traceparent")}'
```
`incoming` is null, `trace_id` is a fresh router-generated id. The subgraph receives that same
id (`grep -A4 "Incoming trace headers" observability/.run/subgraphs.log | tail -8`).

**Client sends a traceparent: the router continues it.**
```bash
./observability/demo.sh propagate
```
The command prints the client's `trace_id` and a Jaeger link. The router log line for that
request shows `incoming` set to the client's header and `trace_id` equal to the client's
trace-id. The trace-id is preserved end to end; only the parent span-id is rewritten on the
subgraph hop. Open the printed Jaeger link to see the trace filed under the client's id.

Say: the `trace_id` is the join key. With no header the router originates it, so cross-request
tracking works even for un-instrumented callers. With a header it continues the caller's trace.

## Use Case 1: latency investigation

"p95 just spiked. Which subgraph, and why?"

```bash
./observability/demo.sh latency        # arms ~800ms on orders, drives the combined query
# ... talk for a bit, then:
./observability/demo.sh reset          # disarm when done
```
The `latency` query hits BOTH subgraphs (`order(id:)` slow, `searchProducts` fast). That is
deliberate: it makes the per-subgraph contrast visible in Grafana and puts a fast span next
to the slow one in a single Jaeger trace.

**Grafana** ( http://localhost:3000/d/shopgraph-router ): the **p95 latency by subgraph** panel
shows orders (red) climbing to ~0.8s while products (green) stays flat. The **Router latency**
panel shows p95/p99 rising. Run `./observability/demo.sh load 30` alongside if you want denser
lines.

**Jaeger** ( http://localhost:16686 ): service `apollo-router-local`, Find Traces, sort by
Duration, open the slowest. Read the waterfall correctly: a parent span encloses its children,
so its duration includes them. The whole request took ~800ms, so the ancestors all show ~800ms.
That is expected. Localize the cause at the leaf spans and compare siblings:
```
query / supergraph / execution / parallel : ~806ms   parents enclose the slow child
fetch / subgraph [orders]                 : ~805ms   the slow hop (the cause)
fetch / subgraph [products]               : ~2ms     the fast hop, same trace
```
Say: every ancestor of the slow span shows ~800ms because it is waiting on it. The cause is the
deepest span that owns the time with no slow child beneath it, the orders subgraph hop.

**Logs** (confirm by the same id):
```bash
TID=<paste from Jaeger>
grep "$TID" observability/.run/router.log | jq -c '{kind, trace_id, subgraph: ."subgraph.name"}'
```

## Use Case 2: error correlation

"Errors ticked up. Find the failing request and the failing hop."

```bash
./observability/demo.sh error          # forces the products `product` query to throw
./observability/demo.sh reset          # disarm when done
```

**Grafana**: the **GraphQL errors by code** panel and the **GraphQL errors (total)** tile light
up with `INTERNAL_SERVER_ERROR`. This fires even though the HTTP status stays 200 (GraphQL
errors are 200 plus an `errors` array), so it is a real signal, not a status-code artifact.

**Jaeger**: service `apollo-router-local`, filter Tags `error=true`, open the trace. The
products subgraph span is flagged with `Catalog lookup failed: downstream inventory timeout`.
Federation attributes the failure to the owning team (the `@contact` Catalog Team in the schema).

**Logs**:
```bash
TID=<paste>
grep "$TID" observability/.run/router.log | jq -c 'select(.level=="ERROR" or (.message|test("error";"i"))) | {trace_id, kind, message}'
```

## Teardown

```bash
./observability/demo.sh down
```
No git cleanup needed. The latency and error scenarios are env-flagged, so the committed code
stays clean.

## Talking points and caveats

- `trace_id` is the universal join key: in logs (`display_trace_id`), as the root span in
  Jaeger, and labelling the request lifecycle.
- Metric exemplars (one-click metric to trace) are not supported in Router v2.15.0. The pivot
  here is the manual `trace_id` copy from logs or Jaeger, which always works.
- Metric names are OTel-spec on v2.15.0: `http_server_request_duration_seconds` and
  `http_client_request_duration_seconds` (the latter carries a `subgraph_name` label).
- Jaeger all-in-one is in-memory; traces reset on container restart. Fine for a demo.
- `localhost` is side-specific: the router (on the host) exports OTLP to the collector at
  `localhost:4327`; the collector forwards to `jaeger:4317` inside the docker network;
  Prometheus (in a container) scrapes the router at `host.docker.internal:9091`.
- Traces flow Router -> OTel Collector -> Jaeger. The collector is where you add or swap a
  trace backend without touching the router config.
- Spans are marked as errors when a GraphQL error is present even though the HTTP status is
  200, and traces are labelled by GraphQL operation name. So the error scenario shows failed
  spans in Jaeger, not just in the metrics.
