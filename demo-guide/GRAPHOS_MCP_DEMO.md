# GraphOS MCP Server - Live Demo Prompts

Read-only AI health checks against GraphOS, via `https://mcp.apollographql.com`.

Prompts are grouped by what the tools can actually do. Read
[Known limitations](#known-limitations)

## Setup

```bash
claude mcp add --transport http --scope project graphos-tools \
  https://mcp.apollographql.com --header "x-api-key: $GRAPHOS_API_KEY"
```

- Use an **Observer-role Graph API Key** (`service:...`)
- Client: Claude Code, Cursor, VS Code, Codex CLI, or Gemini CLI (not Claude Desktop - see below)
- Target: resolved by `GetMyIdentity` from the key; router running, traffic seeded
- Slash-command versions of the composite prompts live in `.claude/commands/`

**Tool coverage split:** `ApolloDocsSearch` / `ApolloDocsRead` /
`ApolloConnectorsSpec` need **no key**. Everything graph-scoped needs the
`x-api-key` header. A missing key fails as
`-32600 Missing x-api-key header`, not as an empty result.

---

## 1. Router & Variant Details

- "Show the federation version, subgraphs, and router status for this variant."
- "Explain what GraphOS can and can't see about this variant's router, and be specific about why."

The second one is the better opener. An agent that names its own blind spots
earns more trust than one that answers everything.

## 2. Launch Stability

- "Check whether the recent launches on this graph have been stable, or whether there were repeated failures."
- "Start from the latest launch, spot any composition error, then walk the launch history to determine whether it's a one-off or a recurring pattern."

## 3. Operation & Subgraph Metrics

- "Find the operations with the highest p99 latency over the last week."
- "Find which subgraphs have the highest error rates this month."
- "Pull the busiest operations, then their latency and error metrics, and flag any high-traffic operation that's slow or failing."

> Metrics are **per-day buckets** and the window must end at least a day ago.
> Ask for "last week", not "today".

## 4. Persisted Query Status

- "Check whether this variant has a persisted query list, and how many operations are in the current build."
- "Compare the operations in live traffic against the PQL, and identify which operations would be rejected if safelist-only were enabled."

The answer is a list of **operations**, not a traffic percentage and not a
per-client breakdown. Say that up front; it lands better than being asked.

## 5. Schema Lint

- "Pull the lint results from recent check workflows, and report what's failing and where."
- "Walk through each error-severity diagnostic: the coordinate, the rule, and what it would take to fix."

> Lint is **graph-scoped** and reads from past *check workflows*. It cannot
> evaluate a hypothetical change. Whether adding `estimatedDelivery` would pass
> lint is a `rover subgraph check` question - see `CONNECTORS_DEMO.md` for that loop.

## 6. Audit & Governance

- "Audit this graph for governance issues: lint diagnostics, persisted-query coverage, and launch stability."
- "Produce a governance checklist: lint status, PQ coverage, and launch stability, each marked pass/fail." → `/governance`

Watch for **empty lint results**. That means no checks have ever run, not a
clean schema. A good agent says UNKNOWN there; call it out when it does.

## 7. Closer

- "Assess whether this graph is healthy. Summarize as Attention Required, Review Recommended, or What's Working Well." → `/graph-health`
- "Investigate why the Clients and Insights pages show no data for a graph that's clearly receiving traffic." (real bug, not scripted)

## 8. Pre/Post-Migration Comparison

- "Compare launch stability before and after this migration, and determine whether it made things better or worse."

## 9. Deprecation / Safe-Removal Analysis

- "The last launch deprecated `legacyPricing`. Report which operations that launch flagged as affected, how much traffic they carry, and which clients would break." → `/change-impact`

> Reframed from the original. There is **no field-level usage index** on this
> server - you can't ask which operations reference a coordinate. The launch
> diff's affected-operations list is the real evidence, and only for changes
> that already landed. Pre-landing, that's `rover subgraph check`.
>
> The client-level part is answered by a step outside this MCP server -
> `/change-impact` calls the Apollo Platform GraphQL API directly
> (`me.statsWindow.queryStats`), since Observer role explicitly includes
> metrics read access. It states which key produced that data every time; see
> `.claude/graphos-tool-constraints.md`.

## 10. Contract Variant Readiness

- "Pull lint results and the latest launch for the contract variant, and determine whether a publish would compose cleanly right now."

> No tool exposes contract operation limits. Check that in Studio.

## 11. Multi-Team Governance Scorecard

- "Run the governance checklist against `team-a@prod` and `team-b@prod`, and report which one needs the most attention." → `/governance`

Note that lint is graph-scoped, so it's reported once per graph, not per team
variant. Worth saying out loud rather than letting someone spot it.

## 12. Incident Triage / Root-Cause Correlation

- "p99 on `checkout` regressed on <a completed day>. Compare it to the surrounding days, find which subgraph moved with it, and check whether a launch landed in that window." → `/triage`

> Reframed. Insights resolve to **whole days ending at least 24h ago**. An
> hour-scale spike from this afternoon is invisible here - that's a traces
> question. Being straight about this is a stronger moment than fudging it:
> it's the natural handoff to the observability demo.

## 13. Persisted-Query Rollout Planning

- "Identify what's in live traffic but missing from the PQL, and what's registered but no longer used." → `/pq-rollout`

> Operations, not clients. Owner assignment is a Studio Clients-page step.

## 14. Self-Service Pre-Ticket Diagnostics

- "Before filing a support ticket about this build failure, pull the lint results and latest launch details to attach to it." → `/pre-ticket`

Best ROI story in the deck - it's support deflection your CS counterpart can
put a number on.

## 15. Cost / Capacity Justification

- "Show traffic on the busiest operations over the last 30 days, and assess whether this graph is outgrowing its current router setup."

> `GetTopOperations` caps the window at 31 days and is rate limited. One call.

## 16. New-Engineer Onboarding Walkthrough

- "Walk through this graph's subgraphs, recent stability, and anything that looks unhealthy, for someone new to it."

## 17. Docs, Grounded (no key required)

- "Provide the correct `@connect` selection syntax for a nested REST field."
- "Identify which router version introduced <feature>, and what the config shape is."

Run these with `WebSearch`/`WebFetch` denied (see `.claude/settings.json`). The
answer can only have come from `ApolloDocsSearch`. That's the point: versioned,
grounded, no invented YAML.

---

## Known limitations

**Client dimension: absent from every MCP tool**, but not from GraphOS itself.
`GetOperationMetrics` returns start, end, operation name, request count, p50,
p99, and error count - no client name or version anywhere on this server. For a
one-off "which client is doing X" question, Studio's Clients page is still the
fastest path. For the deprecation/change-impact flow specifically, `/change-impact`
now gets it via a direct Platform API call (see item 9) rather than stopping at
"ask Studio."

**Field-level usage: absent.** No coordinate-to-operation index. Closest signal
is the affected-operations list in a launch's schema diff.

**Time floors.** `GetTopOperations` needs `to` at least 6 hours ago, window
≤ 31 days. `GetOperationMetrics` and `GetSubgraphMetrics` need `to` at least a
day ago and bucket per DAY. Nothing sees the last few hours.

**Lint scope.** `GetLintResults(graphId, limit)` takes no variant and sources
from recent check workflows. Empty means no checks ran.

**Argument shapes.** No tool accepts a `graph@variant` string - always split.
`GetOperationMetrics`/`GetSubgraphMetrics` use `variantName` as an **array**;
the rest use `variant` as a string. `GetLaunchHistory` requires `limit` and
`offset` explicitly.

**Claude Desktop:** built-in connector, can't send `x-api-key`. Health-check
tools fail with `-32600`; docs tools still work. Use a CLI-based client.

**Self-hosted router version:** returns `null` / `CLOUD_ROUTER_EOL` - expected,
not a bug.

Full detail in [`.claude/graphos-tool-constraints.md`](../.claude/graphos-tool-constraints.md).
