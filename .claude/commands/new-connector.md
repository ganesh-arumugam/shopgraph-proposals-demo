---
description: Author a new Apollo Connectors subgraph from a REST API, then check it
argument-hint: "<subgraph-name> <rest-base-url>  e.g. weather https://api.open-meteo.com"
allowed-tools: mcp__graphos-tools__ApolloConnectorsSpec, mcp__graphos-tools__ApolloDocsSearch, mcp__graphos-tools__ApolloDocsRead, mcp__graphos-tools__GetVariantDetails, Read, Edit, Bash(rover *)
---

Name and base URL: $ARGUMENTS

`WebSearch` and `WebFetch` are denied. Directive syntax comes from
`ApolloConnectorsSpec`, not from memory. Call it first, every time — the spec
version moves and a stale `@connect` shape is the most likely way this fails.

## 1. Ground the syntax

Call `ApolloConnectorsSpec`. Note the current `connect` spec version for the
`@link` URL. Cross-check the existing example in
`subgraphs/connectors/schema.graphql` — it's a working reference in this repo,
including a nested-field flatten (`company: company.name`).

## 2. Write the schema

Create `subgraphs/$1/schema.graphql` with:

- `@link` to the federation and connect specs, versions from step 1
- `@source` naming the API and its `baseURL`
- One or two `@connect` fields — a by-id lookup and a list, matching the shape of
  the existing connectors subgraph
- A `selection` block that flattens at least one nested field. Flat mappings
  don't show anything a REST proxy couldn't do

Keep it small. Two fields that work beat six that need debugging on camera.

## 3. Test the connector

```bash
rover connector test
```

Exercises the HTTP mapping, not just the SDL. Faster than a full compose.

## 4. Compose locally

```bash
rover dev --supergraph-config supergraph.yaml
```

Add the new subgraph to `supergraph.yaml` if it isn't there. Report the Sandbox
URL and a sample query for the user to run — don't claim it works without them
seeing a response.

## 5. Check against the graph

```bash
set -a; source .env; set +a
rover subgraph check "$APOLLO_GRAPH_REF" --name $1 --schema subgraphs/$1/schema.graphql
```

**Expect this to fail** on Proposals severity if no approved Proposal covers the
change. That is the governance gate working, not a problem to route around. Say
so plainly and stop — do not attempt to bypass, lower severity, or publish
anyway. Approving the Proposal is a human step in Studio.

## 6. Stop before publish

Report what's ready and what the check said. Publishing is the user's call, not
yours — `rover subgraph publish` is in `demo-guide/CONNECTORS_DEMO.md` when they
want it.
