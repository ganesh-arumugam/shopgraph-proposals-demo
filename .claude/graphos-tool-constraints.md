# GraphOS MCP tool constraints

Hard limits on the `graphos-tools` server. Read before writing any command that
calls it — several obvious-looking prompts are impossible.

## Identity and arguments

- Call `GetMyIdentity` first. With a graph/service key, `me` resolves to a Graph:
  use `id` as `graphId` and `variants[].name` as the variant. Don't make the user
  supply either.
- **Every tool takes `graphId` and a variant as separate parameters.** None of
  them accept a `graph@variant` ref string. Split on `@` before calling.
- `GetOperationMetrics` and `GetSubgraphMetrics` name the parameter
  `variantName`, and it is an **array**. `GetTopOperations`, `GetVariantDetails`,
  `GetLatestLaunch`, `GetLaunch`, `GetPersistedQueryListStatus` use `variant`, a
  string. They are not interchangeable.
- `GetLaunchHistory` requires `limit` and `offset` explicitly — they are not
  optional with defaults.

## Time windows

| Tool | `to` must be | Bucket |
|---|---|---|
| `GetTopOperations` | ≥ 6 hours before now | operation totals |
| `GetOperationMetrics` | ≥ 1 day in the past | per-DAY rows |
| `GetSubgraphMetrics` | ≥ 1 day in the past | per-DAY rows |

- `GetTopOperations`: window ≤ 31 days, `from` within the last 549 days, and the
  report is **rate limited** — don't call it in a loop.
- The metrics tools return CSV with one row per entity **per day**. For a
  multi-day window you must sum the column yourself. Reading a single row as the
  window total is wrong.

**You cannot query the last few hours.** Anything framed as "what happened at 2pm
today" is out of reach. Say so rather than returning stale data as if it were
current.

## What these tools do NOT expose

- **No client dimension.** `GetOperationMetrics` columns are: start, end,
  operation name, request count, latency p50, latency p99, requests with errors.
  There is no client name or version anywhere. Any question shaped "which client
  is doing X" cannot be answered here — send the user to Studio's Clients page.
- **No field-level usage.** You cannot ask which operations reference
  `Type.field`. The closest available signal is the schema diff in
  `GetLatestLaunch`, which lists operations affected by a change that already
  landed.
- **No live router telemetry.** `GetVariantDetails` returns router status and
  config; a self-hosted router reports `null` / `CLOUD_ROUTER_EOL`. Expected.

## Lint

`GetLintResults(graphId, limit)` — **graph-scoped, no variant parameter.** It
reads diagnostics from the most recent *check workflows*, so it returns nothing
on a graph where checks have never run. Empty results mean "no checks", not
"clean schema" — never report the second when you observed the first.

## Client dimension — not on this server, but not out of reach

No tool here carries a client name/version. That's a gap in this MCP server's
curated surface, not a GraphOS limitation: the Apollo Platform GraphQL API
(`https://graphql.api.apollographql.com/api/graphql`) exposes it via
`me.statsWindow.queryStats` (`me` resolves to a `Service` for a graph-scoped
key; filter `ServiceQueryStatsFilter` supports `schemaTag` and
`in: { queryName: [...] }` for a specific set of operations; `resolution` must
be a `Resolution` enum value like `R1D`, and `timestamp` must be selected
whenever a non-null resolution is used).

Per [Members, Roles, and Permissions](https://apollographql.com/docs/graphos/platform/access-management/member-roles),
**Observer role explicitly includes metrics read access** — `GRAPHOS_API_KEY`
should be able to make this call directly, same as every MCP tool here. It
just isn't reachable from a shell in every environment (the MCP host can hand
a key to the server's own header without ever exporting it to Bash) — if that
happens, `/change-impact` falls back to `APOLLO_KEY` and says so explicitly.
Never make this call silently with a stronger key than the rest of the
session is using.
