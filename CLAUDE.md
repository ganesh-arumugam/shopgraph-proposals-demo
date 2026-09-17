# ShopGraph — agent working rules

## Ground truth for Apollo questions

`WebSearch` and `WebFetch` are denied in `.claude/settings.json` — they are not in
your tool list. This is deliberate.

Anything you need to know about Apollo Router, Federation, Connectors, or GraphOS
comes from the `graphos-tools` MCP server:

- `ApolloDocsSearch` / `ApolloDocsRead` — product documentation, versioned
- `ApolloConnectorsSpec` — the Connectors spec, for authoring `@source` / `@connect`

Do not shell out to `curl` or `wget` to fetch documentation. The demo scripts in
`observability/` use `curl` against `localhost` — that is expected and unrelated.

If a question can't be answered from those tools, say so rather than answering
from memory.

## Default target

Call `GetMyIdentity` first rather than assuming a graph ref — a graph key
resolves both the graph `id` and its variants. No tool on this server accepts a
combined `graph@variant` string; split it.

The API key in `x-api-key` is Observer role — read-only. Never assume you can
publish, promote, or mutate through the MCP server.

`.claude/graphos-tool-constraints.md` documents the argument shapes, time-window
limits, and the questions these tools cannot answer. Read it before writing or
running anything that calls `graphos-tools`.

## Repo layout

- `subgraphs/` — `products` (Catalog Team), `orders` (Commerce Team)
- `operations/` — saved queries used in the Proposals demo narrative
- `observability/` — self-contained Jaeger/Prometheus/Grafana demo (`demo.sh`)
- `demo-guide/` — SE scripts, including `GRAPHOS_MCP_DEMO.md` (prompt library)
- `router/` — router binary + `router-config.yaml`

## Style

Terse. This repo is demoed live, so prefer short, readable output over
exhaustive reports. When a `graphos-tools` call returns nothing, say which tool
returned nothing and why that might be — a silent gap reads as a broken demo.

Self-hosted router versions return `null` / `CLOUD_ROUTER_EOL` from
`GetVariantDetails`. That is expected, not a failure.
