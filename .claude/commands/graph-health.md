---
description: Full health read on a variant — topology, traffic, latency, errors
argument-hint: "[graph@variant]  (default: whatever the API key resolves to)"
allowed-tools: mcp__graphos-tools__GetMyIdentity, mcp__graphos-tools__GetVariantDetails, mcp__graphos-tools__GetTopOperations, mcp__graphos-tools__GetOperationMetrics, mcp__graphos-tools__GetSubgraphMetrics
---

Read `.claude/graphos-tool-constraints.md` before calling anything.

Target: $1 — if empty, `GetMyIdentity` and use the resolved graph and variant.
Split `graph@variant` into separate `graphId` and `variant` arguments.

Window: `from` = 7 days ago, `to` = **yesterday at 00:00Z**. The metrics tools
reject a `to` less than a day in the past. Do not silently widen or narrow this
without saying so.

1. `GetVariantDetails(graphId, variant)` — federation version, subgraph
   inventory, router status, router config.
2. `GetTopOperations(graphId, variant, from, to, limit: 10)` — busiest
   operations. Rate limited; call it once.
3. `GetOperationMetrics(graphId, variantName: [variant], from, to, orderBy: "REQUEST_LATENCY_P99_MS")` —
   slowest operations. Rows are **per day**; sum per operation for window totals.
4. `GetSubgraphMetrics(graphId, variantName: [variant], from, to, orderBy: "FETCH_WITH_ERRORS_COUNT")` —
   which subgraph is carrying the errors.

Report in three buckets:

- **Attention required** — failing or trending badly
- **Review recommended** — working but worth a look
- **What's working well** — say it out loud

The finding is any operation that is both high-traffic *and* slow or failing.
The raw lists are not the finding.

Close by naming one thing GraphOS can't see from here — per-client breakdown and
anything inside the last 24 hours are the honest answers. Naming the boundary is
more convincing than pretending there isn't one.
