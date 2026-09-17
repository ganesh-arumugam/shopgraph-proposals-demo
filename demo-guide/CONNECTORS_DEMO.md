# Connectors: author → test → check → publish → verify

The developer-velocity half of the demo. Where `GRAPHOS_MCP_DEMO.md` is
read-only health checks, this one writes schema and pushes it through the
governance gate this repo already enforces.

## Credentials — two keys, and why that matters

| Path | Credential | Role | Publish access |
|---|---|---|---|
| `graphos-tools` MCP (`x-api-key` header) | `GRAPHOS_API_KEY` | Observer | **No** |
| `rover subgraph check` / `publish` | `APOLLO_KEY` | Contributor+ | Yes |

Both live in `.env`; nothing needs swapping mid-demo. Rover reads `APOLLO_KEY`
from the environment, the MCP server reads `GRAPHOS_API_KEY` from its header,
and the two never meet.

**This is a demo beat, not plumbing.** Three independent layers stop an agent
shipping bad schema, and none of them is a prompt instruction telling it not to:

1. **The MCP key is Observer.** The agent's read path is incapable of writing.
   Not restricted — incapable.
2. **`rover subgraph publish` is denied** in `.claude/settings.json`. Claude Code
   enforces that outside the model, so no prompt or instruction reverses it. The
   agent can run `check`, `dev`, and `connector test`; publish is a human step.
3. **The Proposals gate.** Even a human publish fails the check until an
   approved Proposal covers the change.

When someone asks "what stops the AI from publishing something bad" — and they
will — walk these three. Layer 2 is a permission rule matched on command text,
so treat it as demo integrity rather than a security boundary; layers 1 and 3
are the ones that actually hold.

## Why this repo is set up for it

`subgraphs/connectors/schema.graphql` already exists — a working `@source` /
`@connect` subgraph over `jsonplaceholder`, used by
`./observability/demo.sh connectors` to produce connector spans in traces.

But `router/publish_subgraphs.sh` publishes only `products` and `orders`. **The
connector subgraph has never been through check or publish.** So the demo isn't
contrived: you're closing a real gap in the repo, live.

Two ways to run it. Pick by audience.

| | Audience | Story |
|---|---|---|
| **Track A** — publish the existing connector | Platform / governance | A connector is a subgraph like any other. Same check, same gate, same launch. |
| **Track B** — author a new one from scratch | Developer productivity | Zero to federated REST-backed field in minutes, with the spec in the loop. |

---

## Track A — publish the existing connector

### 1. Compose locally first

```bash
rover dev --supergraph-config supergraph.yaml
```

Sandbox at `localhost:4000`. Run `{ customers { name city company } }`. The
router is making the HTTP call itself — there's no server behind this subgraph.
That's the thing to say out loud; it's what people don't expect.

### 2. Check against the published graph

```bash
set -a; source .env; set +a

rover subgraph check "$APOLLO_GRAPH_REF" \
  --name connectors \
  --schema subgraphs/connectors/schema.graphql
```

This is the moment. `.github/workflows/schema-check.yml` runs Proposals severity
at `Error`, so **the check fails unless an approved Proposal covers the change**.
Let it fail on camera. A governance gate you can't demonstrate failing isn't a
gate.

Then approve the Proposal in Studio and re-run. Same command, passes.

### 3. Publish

Run this **in your own terminal, not through Claude**. `rover subgraph publish`
is denied in `.claude/settings.json`, so the agent will refuse it — which is
worth showing rather than working around. Ask Claude to publish first, let it
hit the wall, then do it yourself.

```bash
rover subgraph publish "$APOLLO_GRAPH_REF" \
  --name connectors \
  --schema subgraphs/connectors/schema.graphql
```

> A connector subgraph has no service to route to, so there's no routing URL.
> Confirm your rover version's exact handling with
> `rover subgraph publish --help` before the demo — this is the one flag worth
> checking cold rather than discovering live.

### 4. Verify through the MCP server — the loop closes

Back in Claude Code, with `graphos-tools` connected:

> "Pull the latest launch. Confirm whether the connectors subgraph landed and
> composed cleanly."

`GetLatestLaunch` shows the launch, the subgraph change, and the schema diff. The
same MCP server you used for read-only health checks now confirms the write you
just made. Then:

> "Now run the governance checklist." → `/governance`

Lint and launch stability reflect a change made ninety seconds ago.

---

## Track B — author a new connector from scratch

Use `/new-connector` (see `.claude/commands/new-connector.md`), or drive it
manually:

1. **Ground the syntax.** Ask for the `@connect` selection shape. With
   `WebSearch` denied, `ApolloConnectorsSpec` and `ApolloDocsSearch` are the only
   sources — so the directives are spec-current, not training-data-current. Say
   this; it's the seam between "GraphOS hosts MCP" and "the agent writes correct
   schema."
2. **Write the schema** into `subgraphs/<name>/schema.graphql`.
3. **Test the connector** with the Connectors Testing Framework:
   ```bash
   rover connector test
   ```
   Faster feedback than a full compose, and it exercises the HTTP mapping rather
   than just the SDL.
4. **Compose** — `rover dev`, query it in Sandbox.
5. **Check and publish** — steps 2–4 of Track A.

Good candidate APIs when you need one live: any public REST endpoint with nested
objects, so the `selection` block has to flatten something
(`company: company.name` in the existing schema is exactly that shape).

---

## Talking points

- **A connector is not a special case.** Same publish, same check, same launch,
  same lint. That's the governance argument: teams adopting REST-backed fields
  don't get a parallel process.
- **No service to run.** Nothing to deploy, scale, page on, or patch. Compare
  against the alternative of a thin BFF wrapping the same REST call.
- **The spec is in the agent's context.** `ApolloConnectorsSpec` means the model
  isn't recalling directive syntax from training data. With web denied, that's
  demonstrable rather than asserted.
- **The gate holds for agents too.** An agent wrote the schema; it still failed
  the Proposals check until a human approved. That answers the "what stops the AI
  from publishing something bad" question before it's asked — and it will be
  asked.

## Sequencing with the MCP demo

Run health checks first (`/graph-health`, `/governance`), then this. The
read-only half establishes the tools are grounded and honest about their limits;
the write half then lands as trustworthy rather than reckless. Reversed, the
first thing the room sees an agent do is change a schema.
