---
description: Pass/fail governance scorecard — lint, persisted queries, launch stability
argument-hint: "[graph@variant ...]  (default: whatever the API key resolves to)"
allowed-tools: mcp__graphos-tools__GetMyIdentity, mcp__graphos-tools__GetLintResults, mcp__graphos-tools__GetPersistedQueryListStatus, mcp__graphos-tools__GetLatestLaunch, mcp__graphos-tools__GetLaunchHistory
---

Read `.claude/graphos-tool-constraints.md` before calling anything.

Targets: $ARGUMENTS — if empty, call `GetMyIdentity` and use the resolved graph
`id` plus its variants. Split any `graph@variant` argument into `graphId` and
`variant` before calling; no tool accepts the combined ref.

Score three dimensions, each **PASS** or **FAIL**:

| Dimension | Call | Fails when |
|---|---|---|
| Lint | `GetLintResults(graphId, limit: 5)` | any diagnostic at error severity |
| Persisted queries | `GetPersistedQueryListStatus(graphId, variant)` | no PQL, or mode is unenforced |
| Launch stability | `GetLatestLaunch(graphId, variant)` then `GetLaunchHistory(graphId, variant, limit: 20, offset: 0)` | latest failed, or repeated failures across history |

Two things to get right:

- **Lint is graph-scoped, not per-variant.** Report it once for the graph, not
  once per variant, and don't imply otherwise in the table.
- **Empty lint results mean no check workflows have run**, not a clean schema.
  Mark that case **UNKNOWN**, not PASS. Calling it a pass is the one mistake that
  would actually mislead someone.

On launch stability, walk the history rather than stopping at the latest launch —
one-off versus recurring is the whole point of the check.

Output one table per variant, then a single line naming which needs attention
first. Rank worst-first if several were passed.
