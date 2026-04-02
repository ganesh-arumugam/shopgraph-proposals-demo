# Setup Guide

## Prerequisites

- Node.js 20+
- [Rover CLI](https://www.apollographql.com/docs/rover/getting-started) (`curl -sSL https://rover.apollo.dev/nix/latest | sh`)
- A GraphOS account with a supergraph (or create a new one)
- A **Personal API key** (not a service key — needed for the sync-reviewers script)

---

## 1. Clone and install

```bash
git clone https://github.com/your-org/shopgraph-proposals-demo
cd shopgraph-proposals-demo
npm install --prefix subgraphs
```

## 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:
- `APOLLO_KEY` — your **Personal API key** from Studio → User Settings → API Keys
- `APOLLO_GRAPH_ID` — your graph's ID (visible in Studio → Graph Settings)
- `APOLLO_GRAPH_REF` — `<graph-id>@<variant>` — use a dev/staging variant

## 3. Create a new graph (if needed)

If you don't have a dedicated graph for this demo:

1. In Studio → click **+ Create Graph** → **Supergraph**
2. Note the graph ID and create a `dev` variant
3. Update `.env` with the new values

## 4. Start subgraphs

```bash
npm run dev:subgraphs
# Subgraphs available at:
#   http://localhost:4001/products/graphql
#   http://localhost:4001/orders/graphql
```

## 5. Publish schemas to GraphOS

This registers the subgraph schemas so Studio knows about them:

```bash
npm run publish:schemas
```

## 6. Download and start the Router

```bash
npm run router:download   # one-time
npm run router:start
# Router available at http://localhost:4000
```

## 7. Configure Proposals in Studio

Go to **Graph Settings → Proposals**:

1. **Required approvals:** Set to `2` (or `1` for faster demos)
2. **Require default reviewer approval:** Enable
3. **Require reapprovals on revision:** Enable (optional, but great to show)
4. **Description template:** Optionally add a template so proposals have structure

Then go to **Graph Settings → Schema Checks → Checks Tasks**:
1. Find the **Proposals** task
2. Set severity to **Error**

This is the setting that makes CI block merges when changes lack an approved proposal.

## 8. Set up reviewer mapping

Edit `.github/contact-reviewer-map.json`:

```json
{
  "Catalog Team": ["your-email@company.com"],
  "Commerce Team": ["another-email@company.com"]
}
```

Use real email addresses of people in your GraphOS org.

## 9. Set up GitHub Secrets & Variables

In your GitHub repo → Settings → Secrets and variables → Actions:

**Secrets:**
- `APOLLO_KEY` — your Personal API key

**Variables:**
- `APOLLO_GRAPH_ID` — your graph ID
- `APOLLO_GRAPH_REF` — e.g. `my-graph@dev`
- `PRODUCTS_SUBGRAPH_URL` — public URL for the products subgraph (for CI publish)
- `ORDERS_SUBGRAPH_URL` — public URL for the orders subgraph (for CI publish)

## 10. Create the demo branch

```bash
git checkout -b feature/add-estimated-delivery
```

In `subgraphs/orders/schema.graphql`, uncomment the `estimatedDelivery` field
(see the comment block in the schema file). Also add a stub resolver in
`subgraphs/orders/resolvers.js`:

```js
Order: {
  // ... existing resolvers ...
  estimatedDelivery(parent) {
    // Stub: return a date 5 days from placedAt
    const placed = new Date(parent.placedAt);
    placed.setDate(placed.getDate() + 5);
    return placed.toISOString().split("T")[0];
  }
}
```

Push the branch and open a PR. The schema-check workflow will run and fail
until the Proposal is approved — that's the demo's governance gate moment.
