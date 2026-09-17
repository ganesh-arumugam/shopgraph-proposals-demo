---
description: Persisted-query coverage and gap analysis toward safelist-only
argument-hint: "[graph@variant]  (default: whatever the API key resolves to)"
allowed-tools: mcp__graphos-tools__GetMyIdentity, mcp__graphos-tools__GetPersistedQueryListStatus, mcp__graphos-tools__GetTopOperations
---

Read `.claude/graphos-tool-constraints.md` before calling anything.

Variant: $1 — if empty, resolve via `GetMyIdentity`. Split `graph@variant`.

1. `GetPersistedQueryListStatus(graphId, variant)` — does a PQL exist, what's its
   revision, and how many operations are in the current build?
2. `GetTopOperations(graphId, variant, from, to, limit: 50)` — operations
   actually in live traffic. `to` must be at least 6 hours ago; window ≤ 31 days.

Compare the two sets by operation name and signature:

- **In traffic and in the PQL** — already covered
- **In traffic but not in the PQL** — would be rejected the day safelist-only is
  switched on. This list is the deliverable.
- **In the PQL but not in traffic** — stale registrations, candidates to prune

**Say this before the plan:** these tools carry no client dimension, so the list
is by operation, not by client. Attributing each unregistered operation to a
client team is a Studio Clients-page step, and it's the step that turns this list
into owner-assigned work. Don't guess owners from operation names.

Close with staged exit criteria, not dates:

- **Now** — operations already registered; enforcement is safe for them
- **Next** — unregistered operations in traffic; register these, then re-run
- **Blocked** — anything that can't be registered, and what it needs first
