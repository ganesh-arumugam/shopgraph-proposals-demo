# ShopGraph — Apollo Schema Proposals Demo

A self-contained live demo showcasing [Apollo GraphOS Schema Proposals](https://apollographql.com/docs/graphos/platform/schema-management/proposals) with a realistic e-commerce supergraph.

## What this demonstrates

- **Full Proposal lifecycle** — Draft → Open for Feedback → Approved → Implemented, with each status transition tied to a concrete action in the demo story
- **CI governance gate** — `rover subgraph check` with Proposals severity set to `Error` blocks PR merges until a matching Proposal is Approved in Studio
- **`@contact`-driven reviewer automation** — a GitHub Actions script reads `@contact` directives from SDL files and automatically sets those team members as default reviewers in GraphOS, making the schema the source of truth for governance

## Supergraph

Two subgraphs, one e-commerce story:

| Subgraph | Owned by | Types |
|----------|----------|-------|
| `products` | Catalog Team | `Product`, `Variant` |
| `orders` | Commerce Team | `Order`, `OrderItem` |

**Demo narrative:** Adding `estimatedDelivery: String` to the `Order` type — proposed, reviewed, approved, then CI-gated on merge.

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

## Demo guide

See [`demo-guide/DEMO_GUIDE.md`](./demo-guide/DEMO_GUIDE.md) for the full SE script with talking points, objection handling, and the step-by-step demo flow.

Full setup instructions: [`demo-guide/SETUP.md`](./demo-guide/SETUP.md)
Studio configuration: [`demo-guide/studio-settings.md`](./demo-guide/studio-settings.md)

## Key files

```
subgraphs/
  products/schema.graphql    # @contact: Catalog Team
  orders/schema.graphql      # @contact: Commerce Team (estimatedDelivery intentionally absent)
.github/
  workflows/
    schema-check.yml         # Blocks PRs when changes lack an approved Proposal
    publish.yml              # Publishes schemas on merge → triggers Implemented status
    sync-reviewers.yml       # Runs @contact → default reviewer sync
  scripts/
    sync-proposal-reviewers.js   # Parses @contact, calls GraphOS Platform API
  contact-reviewer-map.json  # Maps team names → reviewer emails
operations/
  GetAllOrders.graphql           # Run before the proposal (no estimatedDelivery)
  GetOrderWithDelivery.graphql   # Run after Implemented (proves field is live)
demo-guide/DEMO_GUIDE.md         # Full SE script
```

## License

MIT
