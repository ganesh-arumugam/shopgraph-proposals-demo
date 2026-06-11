# Connectors in traces

What happens when a field is backed by **Apollo Connectors** (a REST API via `@source`/
`@connect`) instead of a subgraph server: the **Router makes the HTTP call itself**, and
the trace shows dedicated **connector spans** for that outbound REST request. No subgraph
process is involved for the connector field.

```text
  Client ─▶ Router ─▶ supergraph ─▶ execution ─▶ fetch (customers) ─▶ connect ─▶ connect_request ─▶ http_request
                                                                                         │
                                                                                         └─▶ GET https://jsonplaceholder.typicode.com/users/{id}
```

Compare with a normal subgraph hop, which shows `subgraph` / `subgraph_request` spans
pointing at a subgraph server. A connector hop shows `connect` / `connect_request` spans
pointing at the REST source.

## What's in the demo

- A connector subgraph [`subgraphs/connectors/schema.graphql`](../subgraphs/connectors/schema.graphql)
  exposes `Query.customer(id)` / `Query.customers` backed by the public REST API
  `https://jsonplaceholder.typicode.com/users` (federation v2.12, connect v0.3).
- It is composed **locally** with products + orders into
  [`router/supergraph-connectors.graphql`](../router/supergraph-connectors.graphql) via
  [`router/supergraph-connectors.yaml`](../router/supergraph-connectors.yaml). This does
  not touch the GraphOS graph.
- The router runs with that local supergraph plus the normal telemetry config, so
  connector spans flow to Jaeger (and Dynatrace, if enabled) like everything else.

## Run it

```bash
./observability/demo.sh connectors
```

This composes (if needed), starts the backends + product/order subgraphs, runs the router
with the connector supergraph, fires a connector query, and prints the trace link. Then:

```bash
curl -s http://localhost:4000/ -H 'content-type: application/json' \
  -d '{"query":"{ customer(id:\"2\"){ id name email company city } }"}' | jq .
```

## What to look for in the trace

Open the trace in Jaeger (or Dynatrace). The connector hop appears as:

| Span | Meaning |
|------|---------|
| `fetch` (`apollo.subgraph.name=customers`) | query plan step for the connector subgraph |
| `connect` | the connector execution |
| `connect_request` | the outbound REST request (carries the attributes below) |
| `http_request` | the underlying HTTP client call |

The `connect_request` span is tagged (enabled via `instrumentation.spans.connector` in
`router-config.yaml`):

```
connector.source.name   = jsonplaceholder
connector.http.method   = GET
connector.url.template  = /users/{$args.id}
subgraph.name           = customers
```

So the trace tells you exactly which REST source, method, and URL template the Router
called for that field. Connector latency also shows on the `http.client.request.duration`
metric (the connector service), the same instrument used for subgraph hops.

## Notes

- The connector field has **no server**. The Router performs the REST call, which is why
  the latency and errors of that call are attributed to connector spans, not a subgraph.
- Connectors require Router v2 and federation v2.10+ (this demo uses v2.12 + connect
  v0.3). Re-compose after editing the connector schema:
  `cd router && rover supergraph compose --config ./supergraph-connectors.yaml > supergraph-connectors.graphql`
  (`./demo.sh connectors` does this automatically when the schema changes).
- This runs the router in **local-supergraph mode** (`--supergraph`), separate from the
  managed-federation path used by `./demo.sh up`.
