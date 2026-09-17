---
description: Assemble diagnostics to attach to a support ticket before filing it
argument-hint: "[short description of the problem]"
allowed-tools: mcp__graphos-tools__GetLintResults, mcp__graphos-tools__GetLatestLaunch, mcp__graphos-tools__GetLaunch, mcp__graphos-tools__GetVariantDetails, mcp__graphos-tools__GetMyIdentity
---

Problem: $ARGUMENTS
Variant: `GA-Proposal@dev` unless stated otherwise.

Gather everything a support engineer would ask for on their first reply, so the
ticket doesn't need a round trip:

1. `GetMyIdentity` — org and graph context
2. `GetVariantDetails` — federation version, subgraph inventory, router status
3. `GetLatestLaunch`, then `GetLaunch` on that ID — full launch detail including
   composition errors and which subgraphs were involved
4. `GetLintResults` — current violations

Produce a paste-ready ticket body:

```
## Summary
<one sentence>

## Environment
Graph ref / federation version / router status

## What I observed
<the problem, with timestamps if known>

## Diagnostics
<launch detail, composition errors, lint violations — verbatim>

## What I already checked
<the tool calls above, and what they ruled out>
```

Keep the diagnostics section verbatim rather than summarised — support wants the
raw output. Everything else stays short.
