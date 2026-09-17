---
description: Correlate a latency or error regression against launch history
argument-hint: "<operation> <day>  e.g. checkout 2026-09-08"
allowed-tools: mcp__graphos-tools__GetMyIdentity, mcp__graphos-tools__GetOperationMetrics, mcp__graphos-tools__GetSubgraphMetrics, mcp__graphos-tools__GetLaunchHistory, mcp__graphos-tools__GetLaunch
---

Read `.claude/graphos-tool-constraints.md` before calling anything.

Operation and day: $ARGUMENTS

**Check the window first.** These tools bucket by DAY and reject a `to` inside
the last 24 hours. If the user asked about today, or about a specific hour, say
plainly that GraphOS insights can't resolve it at that granularity and offer the
nearest complete day instead. Do not quietly answer a different question.

Once the window is valid:

1. `GetOperationMetrics(graphId, variantName: [variant], from, to, orderBy: "REQUEST_LATENCY_P99_MS")` —
   confirm the regression is real by comparing the target day against the
   surrounding days. One day's row alone shows nothing.
2. `GetSubgraphMetrics(graphId, variantName: [variant], from, to, orderBy: "FETCH_LATENCY_P99_MS")` —
   which subgraph moved with it.
3. `GetLaunchHistory(graphId, variant, limit: 20, offset: 0)` — launches landing
   in or before the window.
4. `GetLaunch(graphId, variant, launchId)` on candidates — did it touch the
   subgraph from step 2?

Conclude with exactly one:

- **Likely cause** — a launch touched the implicated subgraph in the window
- **Correlated, unconfirmed** — timing lines up, the launch didn't touch it
- **No launch correlation** — look outside GraphOS (infra, upstream, traffic mix)

Say which explicitly. The third is a real answer, and reaching it honestly beats
forcing a story onto the data. If you land there, name the next place to look —
day-resolution insights can't see an hour-long spike, so traces are usually it.
