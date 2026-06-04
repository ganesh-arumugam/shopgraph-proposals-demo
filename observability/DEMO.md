# ShopGraph Observability Demo — One `trace_id` across Logs + Traces + Metrics

A local, self-contained demo showing how the **three pillars of observability connect
through a single `trace_id`** that the Apollo Router mints when a client sends no
`traceparent`.

> **The narrative:** *Metrics* tell you **something** is wrong → *Traces* tell you
> **where** → *Logs* tell you **why**. You never lose the thread, because it's the
> same `trace_id` end to end.

Verified against **Apollo Router v2.15.0**.

---

## Hands-free driver (recommended for live calls)

[`demo.sh`](./demo.sh) automates the whole flow — it starts everything, fires the
queries, and **prints the `trace_id` + a clickable Jaeger link** for each scenario.

```bash
./observability/demo.sh up        # backends + subgraphs + router (clean)
./observability/demo.sh status    # what's running + URLs + scrape health
./observability/demo.sh query     # one normal query → trace_id + links
./observability/demo.sh latency   # arm latency, drive traffic → trace_id + PromQL + links
./observability/demo.sh error     # arm error, trigger it → trace_id + links
./observability/demo.sh reset     # disarm scenarios (subgraphs back to clean)
./observability/demo.sh open      # open Jaeger + Prometheus UIs
./observability/demo.sh down      # stop everything
```

(Also wired as npm scripts: `npm run obs:up`, `npm run obs:down`, `npm run obs:status`.)

The sections below explain what each step does — useful for narrating the call or
running it manually.

---

## Architecture

```
                            ┌─────────────────────────────────────────┐
   client (Bruno/curl)      │  HOST                                    │
        │  no traceparent   │   Apollo Router :4000                    │
        ▼                   │     ├─ stdout JSON logs  (trace_id)      │
   Router MINTS trace_id ───┼──▶  ├─ OTLP traces  ──▶ localhost:4319   │
                            │     └─ /metrics      ◀── scraped :9091   │
                            └───────┬───────────────────┬─────────────┘
                                    │                    │
                       ┌────────────▼─────┐   ┌──────────▼──────────┐
                       │ Jaeger (Docker)  │   │ Prometheus (Docker) │
                       │  UI :16686       │   │  UI :9090           │
                       └──────────────────┘   └─────────────────────┘
```

| Service | URL | Purpose |
|---------|-----|---------|
| Router GraphQL | http://localhost:4000 | the supergraph |
| Router metrics | http://localhost:9091/metrics | Prometheus scrape target |
| **Jaeger UI** | http://localhost:16686 | trace waterfalls (traces pillar) |
| **Prometheus UI** | http://localhost:9090 | metrics queries (metrics pillar) |
| Router logs | terminal / `/tmp/shopgraph/router.log` | structured JSON w/ `trace_id` (logs pillar) |

> Host ports **4317/4318 are intentionally avoided** (used by another project's
> collector). Jaeger's OTLP is remapped: host **4319→**container 4317 (gRPC).

---

## One-time setup

```bash
# 1. Observability backends (Jaeger + Prometheus)
cd observability && docker compose up -d

# 2. Subgraphs (terminal A)  — from repo root
npm run start:subgraphs

# 3. Router (terminal B)
npm run router:start
```

**Pre-call sanity checks** (~30s):
```bash
curl -s localhost:9091/metrics | grep -c http_server_request_duration   # >0 after one query
curl -s "http://localhost:9090/api/v1/targets" | jq '.data.activeTargets[].health'  # "up"
open http://localhost:16686 http://localhost:9090
```

Metric names are the **OTel-spec** names on v2.15.0 (verified):
`http_server_request_duration_seconds_*` (overall) and
`http_client_request_duration_seconds_*` (router→subgraph hop, labelled `subgraph_name`).

---

## Use Case 1 — Latency investigation (headline)

> *"p95 just spiked. Which subgraph? Why?"*

### Arm the demo
Restart **subgraphs** with the latency flag (the committed code is clean; this env
var is the only switch):
```bash
# terminal A — Ctrl-C, then:
DEMO_SLOW_ORDERS_MS=800 npm run start:subgraphs
```

### Trigger (no `traceparent` → router mints the trace_id)
```bash
for i in $(seq 1 10); do
  curl -s http://localhost:4000/ -H 'content-type: application/json' \
    -d '{"query":"query Slow { order(id:\"order:2\"){ id status placedAt items{ quantity unitPrice } } }"}' >/dev/null
done
```

### Live script

**① Prometheus — "something is slow"** ( http://localhost:9090 )
```promql
# overall router p95 (climbs toward 0.8s)
histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket[1m])))

# the money shot — p95 PER SUBGRAPH; orders stands out, products is flat
histogram_quantile(0.95, sum by (le, subgraph_name) (rate(http_client_request_duration_seconds_bucket[1m])))
```
> *Say:* "Metrics flagged the symptom and even point at the `orders` subgraph — but
> not which request or why. That's the trace's job."

**② Get the `trace_id` (the pivot)** — from the router log line:
```bash
tail -50 /tmp/shopgraph/router.log | \
  jq -rR 'fromjson? | select(.kind=="router.request") | .trace_id' | tail -1
```
> *Say:* "Same ID I'll paste into Jaeger and grep my logs with — one join key."

**③ Jaeger — "exactly where"** ( http://localhost:16686 )
- Paste the `trace_id` into the search (top-right "Lookup by Trace ID"), **or**
  pick service `apollo-router-local`, Find Traces, sort by **Duration**.
- Expand the waterfall: the `subgraph_request` / `subgraph` span for **orders** is
  ~**800ms**; the rest of the request is microseconds.
> *Say:* "Federation gives per-hop spans for free — the slow hop is unambiguous.
> Without it, the subgraph is a black box."

**④ Logs — "confirm, same id"**
```bash
TID=<paste>
grep "$TID" /tmp/shopgraph/router.log | jq -c '{kind, trace_id, subgraph: ."subgraph.name"}'
# and the subgraph's own inbound-trace log:
grep -A4 "Incoming trace headers" /tmp/shopgraph/subgraphs.log | tail -8
```
> *Say:* "Identical `trace_id` in the router log, the subgraph's inbound header, and
> the Jaeger span. One request, three tools, zero guesswork — a 4-hour incident
> becomes a 4-minute one."

### Disarm
```bash
# terminal A — Ctrl-C, then plain restart (drops the latency)
npm run start:subgraphs
```

---

## Use Case 2 — Error correlation (quick second act)

> *"Errors ticked up. Find the failing request and the failing hop."*

### Arm
```bash
# terminal A — Ctrl-C, then:
DEMO_FAIL_PRODUCT_ID=product:boom npm run start:subgraphs
```

### Trigger
```bash
curl -s http://localhost:4000/ -H 'content-type: application/json' \
  -d '{"query":"query Boom { product(id:\"product:boom\"){ id title } }"}' | jq .
# → response carries an `errors` array (include_subgraph_errors.all: true is on)
```

### Live script

**① Prometheus — error signal** ( http://localhost:9090 )
```promql
# GraphQL error rate, broken down by error code. Rises only when errors occur.
sum by (code) (rate(apollo_router_graphql_error_total[1m]))
```
> Verified on v2.15.0: `apollo_router_graphql_error_total{code="INTERNAL_SERVER_ERROR"}`
> is a dedicated counter — it fires even though the HTTP status stays `200` (GraphQL
> errors are 200 + an `errors` array). This is the clean metric signal; the trace
> below tells you *which* subgraph.

**② Jaeger — the errored span** ( http://localhost:16686 )
- Service `apollo-router-local` → filter **Tags: `error=true`** → open the trace.
- The **products** subgraph span is flagged; its tags/logs show
  `Catalog lookup failed: downstream inventory timeout`.
> *Say:* "The red span is `products` on the `product` field — federation attributes
> the failure to the owning team (the `@contact` Catalog Team in this schema)."

**③ Logs — confirm by `trace_id`**
```bash
TID=<paste>
grep "$TID" /tmp/shopgraph/router.log | jq -c 'select(.level=="ERROR" or (.message|test("error";"i"))) | {trace_id, kind, message}'
```
> *Say:* "Symptom flagged, location in the trace, root cause in the logs —
> correlated by the same id, not by luck."

### Disarm
```bash
npm run start:subgraphs
```

---

## Teardown

```bash
cd observability && docker compose down        # stop Jaeger + Prometheus
# subgraphs/router: Ctrl-C in their terminals
```
No `git` cleanup needed — the demo latency/error are env-flagged, so the committed
code is already in its clean state.

---

## Talking points / honest caveats

- **`trace_id` is the universal join key** — it's in logs (`display_trace_id`),
  it's the root span in Jaeger, and it labels the request lifecycle. The router
  mints it when the client sends no `traceparent`, so cross-request tracking works
  even for un-instrumented callers.
- **Metric exemplars (one-click metric→trace jump) are NOT supported in Router
  v2.15.0** (confirmed: no `exemplar` key in the config schema). The pivot here is
  the manual `trace_id` copy from logs → Jaeger, which is bulletproof. Exemplars /
  a Grafana single-pane can be a follow-up once supported.
- **Metric names are OTel-spec** on v2.15.0 (`http_server_request_duration_seconds`,
  `http_client_request_duration_seconds` with a `subgraph_name` label). Older
  routers / legacy instrumentation mode emit `apollo_router_http_request_duration_*`.
- **Jaeger all-in-one is in-memory** — traces reset on container restart. Perfect
  for a demo, not for persistence.
- **`localhost` is side-specific:** the router (on host) reaches Jaeger at
  `localhost:4319`; Prometheus (in a container) reaches the router at
  `host.docker.internal:9091`.
