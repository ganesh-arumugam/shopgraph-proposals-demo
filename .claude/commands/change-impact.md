---
description: Blast radius of a schema change — affected operations, traffic, and client usage
argument-hint: "<Type.field>  e.g. Order.legacyPricing"
allowed-tools: mcp__graphos-tools__GetMyIdentity, mcp__graphos-tools__GetLatestLaunch, mcp__graphos-tools__GetTopOperations, mcp__graphos-tools__GetOperationMetrics, mcp__graphos-tools__GetLintResults, mcp__graphos-tools__GetVariantDetails, Bash(curl -s -X POST https://graphql.api.apollographql.com/api/graphql *)
---

Read `.claude/graphos-tool-constraints.md` before calling anything.

Field under consideration: $1

**Scope check, first, out loud.** These tools have no field-level usage index —
you cannot ask "which operations reference `$1`". Two honest paths:

- If the change has already landed, `GetLatestLaunch(graphId, variant)` returns a
  schema diff summary including **affected operations**. That is real evidence.
- If it hasn't landed, the field-to-operation mapping comes from
  `rover subgraph check` or Studio's field usage view, not from this server.

Say which path you're on before presenting numbers.

Then, for whichever operations you have named:

1. `GetTopOperations(graphId, variant, from, to, limit: 50)` — is each one in
   live traffic at all? (`to` ≥ 6h ago; window ≤ 31 days; rate limited.)
2. `GetOperationMetrics(graphId, variantName: [variant], from, to)` — request
   volume, summed across the per-day rows.
3. Express blast radius as a **share of variant traffic**, never a raw count. A
   raw count means nothing without the denominator.
4. `GetLintResults(graphId, limit: 5)` and the subgraph inventory from
   `GetVariantDetails` — would the change compose and lint clean?

## 5. Client usage

No MCP tool on this server carries a client dimension — not a design choice to
route around, a real gap in this tool's surface. The data still exists: the
Apollo Platform GraphQL API (`https://graphql.api.apollographql.com/api/graphql`)
exposes it via `me.statsWindow.queryStats`, and per
[Members, Roles, and Permissions](https://apollographql.com/docs/graphos/platform/access-management/member-roles),
**Observer role explicitly includes metrics read access** — this is not a
privilege escalation, it's the same key doing something the MCP server's
curated tool surface just doesn't expose yet.

Credential: prefer `$GRAPHOS_API_KEY` (the same Observer key every other step
here uses). Only if it's unset in the current shell — the MCP server can be
handed this key by the Claude Code host without it ever reaching a shell —
fall back to `$APOLLO_KEY` and **say so explicitly in the output**: which key
was actually used, and why. Never fall back silently.

```bash
set -a; [ -f .env ] && source .env; set +a
KEY="${GRAPHOS_API_KEY:-$APOLLO_KEY}"
[ -z "$GRAPHOS_API_KEY" ] && echo "NOTE: GRAPHOS_API_KEY not in shell env — falling back to APOLLO_KEY (Contributor+), read-only call"

curl -s -X POST https://graphql.api.apollographql.com/api/graphql \
  -H "x-api-key: $KEY" -H "Content-Type: application/json" \
  -d "$(jq -n --arg q '
    query($from: Timestamp!, $to: Timestamp!, $filter: ServiceQueryStatsFilter) {
      me {
        ... on Service {
          statsWindow(from: $from, to: $to, resolution: R1D) {
            queryStats(filter: $filter, limit: 500) {
              timestamp
              groupBy { clientName clientVersion queryName schemaTag }
              metrics { totalRequestCount requestsWithErrorsCount }
            }
          }
        }
      }
    }' --argjson v "$(jq -n --arg tag "$VARIANT" --argjson ops "$AFFECTED_OPS_JSON" \
      '{from: $FROM, to: $TO, filter: {schemaTag: $tag, in: {queryName: $ops}}}')" \
    '{query: $q, variables: $v}')"
```

Fill `$VARIANT`/`$FROM`/`$TO` from the window already used in steps 1–2, and
`$AFFECTED_OPS_JSON` from the operations named in the scope check (a JSON array
of operation names, e.g. `["GetOrderWithDelivery"]`). Group the response by
`groupBy.clientName` (missing/null name = **`(unnamed)`** — an untagged caller,
not a hidden client; never guess an owner for it), sum `totalRequestCount` and
`requestsWithErrorsCount` per client. A `queryName` of `# GraphQLValidationFailure`
means the operation never resolved to a name — that's the deprecated/removed
field itself being requested and rejected, which is direct evidence for the
verdict, not noise to filter out.

Verdict, one of:

- **Safe to remove** — no traffic, nothing depends on it
- **Deprecate first** — traffic exists; name operations, clients (with version),
  and a suggested window
- **Do not remove** — load-bearing; say what breaks and for which clients
- **Insufficient data** — usage window too short, no affected-operation
  evidence available, or the Platform API call above wasn't reachable (say why)

Always state which credential produced the client breakdown. That's the fact
that keeps this step honest: a demo where the agent quietly reaches for a
stronger key than the room was told about is worse than one that says "used
the fallback, here's why."
