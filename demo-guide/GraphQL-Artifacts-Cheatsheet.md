# Graph Artifacts

Version pinned supergraph delivery for the Apollo Router: what graph artifacts are, how to get a reference, how to deploy and roll back, and how to verify.

Verified against Apollo Router v2.15.0, Rover 0.40.0, and the official Apollo documentation. See "Current status and limitations" for status and version specific behavior.

## 1. Quick Summary

A graph artifact is an immutable, versioned package of your composed supergraph schema. GraphOS generates one automatically whenever a subgraph publish produces a successful composition. Each artifact has a unique SHA 256 digest and is stored in the GraphOS OCI compliant registry.

Use a graph artifact when you want a router to run an exact, pinned schema (production). Use a graph ref when you want the router to always pick up the latest composition (development and staging).

Graph artifacts are produced at the supergraph level. There is no separately referenceable "subgraph artifact". A subgraph publish triggers composition, and composition produces a supergraph artifact.

Requirements: Apollo Router v2.7 or later for digest references, v2.11 or later for tag reference hot reload, plus GraphOS with managed federation.

## 2. Graph Ref vs Graph Artifact

| | Graph ref | Graph artifact (digest) |
|---|---|---|
| Resolves to | The latest launch for a variant | One exact, immutable composition |
| Set via | `APOLLO_GRAPH_REF` env var | `APOLLO_GRAPH_ARTIFACT_REFERENCE` env var or `--graph-artifact-reference` flag |
| Version pinning | No | Yes |
| Rollback | Republish or recompose | Redeploy a prior digest |
| Recommended for | Development, staging | Production |

The schema source (graph ref, artifact reference, or a local `--supergraph` file) is configured only through CLI flags or environment variables. It is not a key inside `router.yaml`. There is no `schema.graphArtifactReference` or `schema.graphRef` block in the router config file.

Run the latest schema (development or staging):

```bash
export APOLLO_KEY=service:my-graph:xxxx
export APOLLO_GRAPH_REF=my-graph@staging
./router --config router.yaml
```

Run a pinned artifact (production):

```bash
export APOLLO_KEY=service:my-graph:xxxx
export APOLLO_GRAPH_ARTIFACT_REFERENCE="artifact.api.apollographql.com/my-graph@sha256:<DIGEST>"
./router --config router.yaml
# Equivalent flag form:
# ./router --graph-artifact-reference "artifact.api.apollographql.com/my-graph@sha256:<DIGEST>"
```

## 3. Artifact Reference Format

```
artifact.api.apollographql.com/<GRAPH_ID>@sha256:<DIGEST>
```

The host is `artifact.api.apollographql.com`. The reference is a supergraph artifact keyed by graph ID and an `@sha256:` digest. There is no variant path segment and no subgraph form. A tag reference (a name in place of `@sha256:<DIGEST>`) addresses a moving channel and supports hot reload on Router v2.11 or later.

A graph artifact contains the composed supergraph SDL, the query plan and routing information, the component subgraph routing URLs baked in at composition time, and composition metadata. The digest changes whenever a new composition is produced.

## 4. How to Get an Artifact Reference

### Studio Launches page (primary)

1. Open Studio, then your supergraph, then the Launches page.
2. Open the launch you want. The graph artifact is shown for that launch.
3. Click Copy to copy the artifact reference URI.
4. Use it as `APOLLO_GRAPH_ARTIFACT_REFERENCE` or `--graph-artifact-reference`.

There is no separate Artifacts view. Artifacts live on the Launches page.

### GraphOS Platform API (programmatic)

```bash
curl https://graphql.api.apollographql.com/api/graphql \
  -H "Content-Type: application/json" \
  -H "x-api-key: $APOLLO_KEY" \
  -d '{
    "query": "query ($id: ID!, $variant: String!) { graph(id: $id) { variant(name: $variant) { launchHistory(limit: 1) { graphArtifact { completedAt status location { uri } } } } } }",
    "variables": { "id": "my-graph", "variant": "production" }
  }'
```

The endpoint is `https://graphql.api.apollographql.com/api/graphql`. The field names follow the documented shape, but confirm them against the current Platform API schema for your account, since the feature is in preview.

Rover does not provide a graph artifact lookup or a launch listing command. There is no `rover graph list-launches`. Use the Studio Launches page or the Platform API above.

## 5. Deployment Patterns

### Non Kubernetes (manual or VM)

Set the artifact reference as an environment variable and start the router. Restart to change versions.

```bash
export APOLLO_KEY=service:my-graph:xxxx
export APOLLO_GRAPH_ARTIFACT_REFERENCE="artifact.api.apollographql.com/my-graph@sha256:<DIGEST>"
./router --config router.yaml
```

### GitOps (image baked)

Bake the digest into the image so the image and the schema version travel together. Supply the API key at runtime, never in the image.

```dockerfile
FROM ghcr.io/apollographql/router:v2.15.0
ENV APOLLO_GRAPH_ARTIFACT_REFERENCE=artifact.api.apollographql.com/my-graph@sha256:<DIGEST>
EXPOSE 4000
CMD ["--config", "/dist/config/router.yaml"]
```

```bash
docker run -e APOLLO_KEY=$APOLLO_KEY -p 4000:4000 my-router:<IMAGE_TAG>
```

CI example that pins the artifact at deploy time:

```yaml
on:
  workflow_dispatch:
    inputs:
      artifact_reference:
        description: "Graph artifact reference from the Studio Launches page"
        required: true
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy router with a pinned artifact
        run: |
          docker run \
            -e APOLLO_GRAPH_ARTIFACT_REFERENCE=${{ github.event.inputs.artifact_reference }} \
            -e APOLLO_KEY=${{ secrets.APOLLO_KEY }} \
            -p 4000:4000 \
            ghcr.io/apollographql/router:v2.15.0
```

### Kubernetes (GraphOS Operator)

The Operator manages composition and router deployment declaratively. See the appendix for CRDs, install, and full examples.

## 6. Verification Checklist

```bash
# 1. Composition and breaking change check before publishing
rover subgraph check my-graph@production \
  --name orders \
  --schema ./orders/schema.graphql

# 2. Artifact reference has the expected host and digest
echo "$APOLLO_GRAPH_ARTIFACT_REFERENCE"
# artifact.api.apollographql.com/<GRAPH_ID>@sha256:<DIGEST>

# 3. Router health. Served on the health check listener (default 127.0.0.1:8088), path /health
curl -s http://localhost:8088/health
# {"status":"UP"}

# 4. Router serves the schema. Default GraphQL path is "/", not "/graphql"
curl -s http://localhost:4000/ \
  -H "content-type: application/json" \
  -d '{"query":"{ __typename }"}'
# {"data":{"__typename":"Query"}}

# 5. A federated query resolves across subgraphs
curl -s http://localhost:4000/ \
  -H "content-type: application/json" \
  -d '{"query":"{ orders { id status } }"}'

# 6. Metrics, if the Prometheus exporter is enabled (default listen 127.0.0.1:9090, path /metrics)
curl -s http://localhost:9090/metrics | grep "http_server_request_duration_seconds_count"
```

Router v2.x emits OpenTelemetry spec metric names, for example `http_server_request_duration_seconds` and `http_client_request_duration_seconds` (the latter carries a `subgraph_name` label). Enable the exporter in `router.yaml`:

```yaml
telemetry:
  exporters:
    metrics:
      prometheus:
        enabled: true
        listen: 127.0.0.1:9090
        path: /metrics
```

To confirm which artifact a running process uses, inspect the environment on the process, since the reference is a flag or env var:

```bash
ps aux | grep "[r]outer" | grep -o "artifact.api.apollographql.com/[^ ]*"
```

## 7. Rollback

Manual or Docker: repoint to the previous good digest and redeploy.

```bash
export APOLLO_GRAPH_ARTIFACT_REFERENCE="artifact.api.apollographql.com/my-graph@sha256:<PREVIOUS_DIGEST>"
docker run -e APOLLO_GRAPH_ARTIFACT_REFERENCE=$APOLLO_GRAPH_ARTIFACT_REFERENCE \
           -e APOLLO_KEY=$APOLLO_KEY -p 4000:4000 ghcr.io/apollographql/router:v2.15.0
```

The old schema runs again in seconds. No recomposition is needed, because the artifact is prebuilt and immutable.

Operator: pin the Supergraph to a known good launch ID. Obtain the launch ID from the Studio Launches page or the Platform API.

```bash
kubectl patch supergraph my-supergraph-router --type merge \
  -p '{"spec":{"schema":{"studio":{"launchId":"<PREVIOUS_LAUNCH_ID>"}}}}'
```

For automated, safe rollouts and rollbacks the Operator integrates with Argo Rollouts through `spec.deployment`.

## 8. Current Status and Limitations

| Item | Detail |
|---|---|
| Preview | Graph Artifacts and the GraphOS Operator are in Public Preview. Field names and behavior may change. |
| Router version | v2.7 or later for digest references. v2.11 or later for tag reference hot reload. |
| Hot reload | Digest references do not hot reload; switching versions requires a restart or redeploy. Tag references hot reload on v2.11 or later. |
| Schema source | Set only through CLI flags or env vars, never a `router.yaml` key. |
| Scope | Supergraph level only. No separate subgraph artifact. |
| Rover | No launch listing or artifact lookup command. Use Studio or the Platform API. |
| Federation | Managed federation only. |

## 9. Quick Reference

| Task | Command |
|---|---|
| Publish subgraph | `rover subgraph publish my-graph@prod --name orders --routing-url https://orders.example.com/graphql --schema ./orders/schema.graphql` |
| Check compatibility | `rover subgraph check my-graph@prod --name orders --schema ./orders/schema.graphql` |
| List subgraphs | `rover subgraph list my-graph@prod` |
| Fetch subgraph SDL | `rover subgraph fetch my-graph@prod --name orders` |
| Introspect a running subgraph | `rover subgraph introspect https://orders.example.com/graphql` |
| Fetch composed supergraph | `rover graph fetch my-graph@prod` |
| Get an artifact reference | Studio Launches page (Copy), or the Platform API |
| Run latest (dev or staging) | `APOLLO_GRAPH_REF=my-graph@prod ./router --config router.yaml` |
| Run a pinned artifact | `APOLLO_GRAPH_ARTIFACT_REFERENCE=artifact.api.apollographql.com/my-graph@sha256:<DIGEST> ./router --config router.yaml` |
| Operator deploy | `kubectl apply -f supergraph.yaml` |
| Operator pin or rollback | `kubectl patch supergraph my-supergraph-router --type merge -p '{"spec":{"schema":{"studio":{"launchId":"<LAUNCH_ID>"}}}}'` |

## Appendix A. GraphOS Operator (Kubernetes)

Kubernetes native schema management and GraphOS Router deployment. Requires an Operator API key and a GraphOS plan. It publishes and deploys existing graphs; it does not create graphs.

CRD versions differ per kind, so confirm against your installed CRDs. `Subgraph` and `SupergraphSchema` use `apollographql.com/v1alpha2`. `Supergraph` uses `apollographql.com/v1alpha4`.

| Kind | Role |
|---|---|
| `Subgraph` | Defines one subgraph: its endpoint and schema source |
| `SupergraphSchema` | Selects subgraphs by label and composes them, then publishes to GraphOS |
| `Supergraph` | Deploys the GraphOS Router for a composed schema; does not compose |

### Install

The Operator ships as an OCI Helm chart. The API key goes in a Kubernetes secret referenced from `values.yaml`, not a `--set` flag.

```bash
kubectl create namespace apollo-operator
kubectl create secret generic apollo-api-key \
  --namespace apollo-operator \
  --from-literal="APOLLO_KEY=$APOLLO_KEY"

helm upgrade --install --atomic apollo-operator \
  oci://registry-1.docker.io/apollograph/operator-chart \
  --namespace apollo-operator \
  -f values.yaml
```

```yaml
# values.yaml
apiKey:
  secretName: apollo-api-key
```

### Define a subgraph

```yaml
apiVersion: apollographql.com/v1alpha2
kind: Subgraph
metadata:
  name: orders
  labels:
    supergraph: my-supergraph
spec:
  endpoint: https://orders.example.com/graphql
  schema:
    sdl: |
      type Query { order(id: ID!): Order }
      type Order @key(fields: "id") { id: ID! }
```

### Compose the supergraph

```yaml
apiVersion: apollographql.com/v1alpha2
kind: SupergraphSchema
metadata:
  name: my-supergraph
spec:
  graphRef: my-graph@production
  subgraphSelector:
    matchLabels:
      supergraph: my-supergraph
```

### Deploy the router

```yaml
apiVersion: apollographql.com/v1alpha4
kind: Supergraph
metadata:
  name: my-supergraph-router
spec:
  schema:
    studio:
      graphRef: my-graph@production
      # launchId: <LAUNCH_ID>      # optional: pin a specific launch (blue/green)
    # Or pin an artifact directly:
    # oci:
    #   reference: artifact.api.apollographql.com/my-graph@sha256:<DIGEST>
  replicas: 3
  routerConfig:
    telemetry:
      exporters:
        metrics:
          prometheus:
            enabled: true
  deployment:
    podTemplate:
      routerVersion: "2.15.0"
      # image: <custom-router-image>     # optional override
      # additionalEnv:
      #   - name: ENVIRONMENT
      #     value: production
```

Router settings live under `spec.replicas`, `spec.routerConfig`, and `spec.deployment.podTemplate`. There is no `spec.router` block. The artifact field is `spec.schema.oci.reference`.

### Apply and monitor

```bash
kubectl apply -f subgraph-orders.yaml -f supergraphschema.yaml -f supergraph.yaml

kubectl get supergraphschema my-supergraph -o yaml
kubectl get supergraph my-supergraph-router -o yaml
kubectl get pods -l app.kubernetes.io/name=my-supergraph-router
```

Status conditions by resource:

| Resource | Conditions |
|---|---|
| `SupergraphSchema` | `SubgraphsDetected`, `CompositionPending`, `Available` |
| `Supergraph` | `SchemaLoaded`, `Progressing`, `Ready` |
| `Subgraph` | `SchemaLoaded` |

## Appendix B. Resources

| Topic | URL |
|---|---|
| Graph Artifacts | https://www.apollographql.com/docs/graphos/platform/schema-management/delivery/graph-artifacts |
| GraphOS Operator | https://www.apollographql.com/docs/apollo-operator |
| GraphOS Platform API | https://www.apollographql.com/docs/graphos/platform/platform-api |
| Apollo Router configuration | https://www.apollographql.com/docs/graphos/routing/configuration/overview |
| Rover CLI | https://www.apollographql.com/docs/rover |
