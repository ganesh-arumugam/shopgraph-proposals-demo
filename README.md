# ShopGraph - Apollo Schema Proposals Demo

A self-contained live demo showcasing [Apollo GraphOS Schema Proposals](https://apollographql.com/docs/graphos/platform/schema-management/proposals) with a realistic e-commerce supergraph.

## What this demonstrates

- **Full Proposal lifecycle** - Draft -> Open for Feedback -> Approved -> Implemented, with each status transition tied to a concrete action in the demo story
- **CI governance gate** - `rover subgraph check` with Proposals severity set to `Error` blocks PR merges until a matching Proposal is Approved in Studio
- **`@contact`-driven reviewer automation** - a GitHub Actions script reads `@contact` directives from SDL files and automatically sets those team members as default reviewers in GraphOS, making the schema the source of truth for governance

## Supergraph

Two subgraphs, one e-commerce story:

| Subgraph | Owned by | Types |
|----------|----------|-------|
| `products` | Catalog Team | `Product`, `Variant` |
| `orders` | Commerce Team | `Order`, `OrderItem` |

**Demo narrative:** Adding `estimatedDelivery: String` to the `Order` type - proposed, reviewed, approved, then CI-gated on merge.

## Quick start

```bash
# Install
npm install --prefix subgraphs

# Copy and configure env
cp .env.example .env   # fill in APOLLO_KEY, APOLLO_GRAPH_ID, APOLLO_GRAPH_REF

# Start subgraphs (port 4001)
npm run dev:subgraphs

# Register schemas with GraphOS (first time only)
npm run publish:schemas

# Download and start the Router (port 4000)
npm run router:download
npm run router:start
```

Then open [GraphOS Studio](https://studio.apollographql.com) to your graph and start the demo.

## Observability demo

A separate, self-contained demo shows how **logs + traces + metrics correlate via a
single `trace_id`** (Jaeger + Prometheus, locally via Docker). One-liner:

```bash
npm run obs:up                    # Jaeger + Prometheus + Grafana + subgraphs + router
./observability/demo.sh latency   # arm a scenario; prints trace_id + clickable links
./observability/demo.sh connectors # run a REST connector and see its spans in the trace
```

Guides:

- [`observability/DEMO.md`](./observability/DEMO.md) - full runbook (latency + error use cases, talking points)
- [`observability/CONNECTORS.md`](./observability/CONNECTORS.md) - how Apollo Connectors appear in traces
- [`observability/DYNATRACE.md`](./observability/DYNATRACE.md) - send traces and correlated logs to Dynatrace
- [`observability/apollo-router-otel-telemetry-reference.md`](./observability/apollo-router-otel-telemetry-reference.md) - span/metric attribute reference

## Demo guide

See [`demo-guide/DEMO_GUIDE.md`](./demo-guide/DEMO_GUIDE.md) for the full SE script with talking points, objection handling, and the step-by-step demo flow.

Full setup instructions: [`demo-guide/SETUP.md`](./demo-guide/SETUP.md)
Studio configuration: [`demo-guide/studio-settings.md`](./demo-guide/studio-settings.md)

## GraphOS MCP Server demo

Quick-reference prompts for showing AI agents connecting directly to GraphOS for
read-only graph health checks.

See [`demo-guide/GRAPHOS_MCP_DEMO.md`](./demo-guide/GRAPHOS_MCP_DEMO.md) for the
prompt library and the tools' known limits.

## Connectors demo

Authoring a Connectors subgraph, checking it against the Proposals gate, and
publishing it — then verifying the launch back through the MCP server.

See [`demo-guide/CONNECTORS_DEMO.md`](./demo-guide/CONNECTORS_DEMO.md).

## Agent setup

`.mcp.json` registers the `graphos-tools` MCP server at project scope; it reads
`GRAPHOS_API_KEY` from the shell environment (not from `.env` automatically —
`set -a; source .env; set +a` first). `.claude/settings.json` denies web search
and fetch so Apollo answers come from the documentation tools rather than the
open web. `.claude/commands/` holds the demo slash commands, and
`.claude/graphos-tool-constraints.md` documents what the tools can and can't do.

## Key files

```
subgraphs/
  products/schema.graphql    # @contact: Catalog Team
  orders/schema.graphql      # @contact: Commerce Team (estimatedDelivery intentionally absent)
.github/
  workflows/
    schema-check.yml         # Blocks PRs when changes lack an approved Proposal
    publish.yml              # Publishes schemas on merge -> triggers Implemented status
    sync-reviewers.yml       # Runs @contact -> default reviewer sync
  scripts/
    sync-proposal-reviewers.js   # Parses @contact, calls GraphOS Platform API
  contact-reviewer-map.json  # Maps team names -> reviewer emails
operations/
  GetAllOrders.graphql           # Run before the proposal (no estimatedDelivery)
  GetOrderWithDelivery.graphql   # Run after Implemented (proves field is live)
demo-guide/DEMO_GUIDE.md         # Full SE script
```

## License

MIT
