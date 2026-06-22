# Apollo Router OTel Telemetry - What's Available and How It's Organized

There are **three distinct telemetry signal categories** in Apollo Router: trace span attributes, OpenTelemetry standard metric instruments, and Apollo Router standard metric instruments. All configured under `telemetry.instrumentation`, but in different subsections depending on whether you're configuring spans or metrics.

One important nuance: instrumentation is broken across `router`, `supergraph`, `subgraph`, and `connector` pipeline services. The internal `Execution` service does **not** support instrumentation.

---

## 1. TRACES - Standard Span Attributes

Configured under `telemetry.instrumentation.spans.*`. These enrich trace spans with standard metadata.

### Router service
- `error.type`
- `http.request.body.size`
- `http.request.method`
- `http.response.body.size`
- `http.response.status_code`
- `network.protocol.name`
- `network.protocol.version`
- `network.transport`
- `network.type`
- `user_agent.original`
- `http.route`
- `network.local.address`
- `network.local.port`
- `network.peer.address`
- `network.peer.port`
- `server.address`
- `server.port`
- `url.path`
- `url.query`
- `url.scheme`

> **Note:** `http.request.header.<key>` and `http.response.header.<key>` are **not** standard attributes. Use a custom selector instead: `request_header: "x-my-header"`.

### Supergraph service
- `graphql.operation.name`
- `graphql.operation.type`
- `graphql.document` Note: - see gotchas

### Subgraph service
- `subgraph.name`
- `subgraph.graphql.operation.name`
- `subgraph.graphql.operation.type`
- `subgraph.graphql.document` Note: - see gotchas
- `http.request.resend_count`

### Connector service
- `subgraph.name`
- `connector.source.name`
- `connector.http.method`
- `connector.url.template`

**Docs:** https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/enabling-telemetry/standard-attributes

---

## 2. METRICS - OTel Standard Instruments (`http.*`)

Configured under `telemetry.instrumentation.instruments.*`. These follow OTel semantic conventions and are **enabled by default** when `default_requirement_level: required`.

### Router service
- `http.server.active_requests`
- `http.server.request.duration`
- `http.server.request.body.size`
- `http.server.response.body.size`

### Subgraph service
- `http.client.request.duration`
- `http.client.request.body.size`
- `http.client.response.body.size`

### Connector service
- `http.client.request.duration`
- `http.client.request.body.size`
- `http.client.response.body.size`

These instruments can be customized by attaching or removing attributes. For example, `subgraph.name: true` on `http.client.request.duration`, or `connector.source.name: true` on connector duration.

> **`http.server.active_requests` special case:** This instrument only supports its own fixed set of standard attributes (`http.request.method`, `server.address`, `server.port`, `url.scheme`). Custom selector-based attributes are **not** available on it.

**Docs:** https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/enabling-telemetry/instruments

---

## 3. METRICS - Apollo Router Standard Instruments (`apollo.router.*`)

Also configured under `telemetry.instrumentation.instruments.*`. These are Apollo-specific lifecycle metrics, separate from the OTel `http.*` instruments above.

> **Naming note:** Most are prefixed `apollo.router.*`, but a few use `apollo_router_*` (underscore), and some Redis metrics are currently prefixed `experimental.apollo.router.*`.

### Core lifecycle and error
- `apollo.router.overhead` - router processing time *excluding* time waiting on downstream HTTP services (subgraphs/connectors). Includes parsing, validation, query planning, plugin execution. Filter on `subgraph.active_requests: false` for pure router overhead.
- `apollo.router.graphql_error` - count of GraphQL errors, including `extensions.valueCompletion` response validation errors. Attribute: `code`
- `apollo.router.session.count.active` - **deprecated**; use `http.server.active_requests` instead.

### Cache (APQ / query planner / introspection)
- `apollo.router.cache.size`
- `apollo.router.cache.hit.time` / `apollo.router.cache.hit.time.count`
- `apollo.router.cache.miss.time` / `apollo.router.cache.miss.time.count`
- `apollo.router.cache.storage.estimated_size` (in-memory only, query planner)

Common attributes: `kind` (`apq`, `query planner`, `introspection`), `storage` (`memory`, `redis`)

### Redis (when Redis is configured)
- `apollo.router.cache.redis.clients`
- `apollo.router.cache.redis.command_queue_length`
- `apollo.router.cache.redis.commands_executed`
- `apollo.router.cache.redis.redelivery_count`
- `apollo.router.cache.redis.errors` - attribute: `error_type`, `kind`
- `apollo.router.cache.redis.reconnection`
- `apollo.router.cache.redis.unresponsive`
- `experimental.apollo.router.cache.redis.latency_avg`
- `experimental.apollo.router.cache.redis.network_latency_avg`
- `experimental.apollo.router.cache.redis.request_size_avg`
- `experimental.apollo.router.cache.redis.response_size_avg`

### Coprocessor and Rhai
- `apollo.router.operations.coprocessor` - attributes: `coprocessor.succeeded`, `coprocessor.stage`
- `apollo.router.operations.coprocessor.duration` - attributes: `coprocessor.stage`
- `apollo.router.operations.rhai.duration` - attributes: `rhai.stage`, `rhai.succeeded`

### Performance and memory
- `apollo_router_schema_load_duration`
- `apollo.router.request.memory` - attributes: `allocation.type`, `context`
- `apollo.router.query_planner.memory` - attributes: `allocation.type`, `context`

### Query planning
- `apollo.router.query_planning.warmup.duration`
- `apollo.router.query_planning.plan.duration` - planning time only
- `apollo.router.query_planning.total.duration` - planning + queue wait
- `apollo.router.query_planning.plan.evaluated_plans`

### Compute jobs (parsing / validation / planning thread pool)
- `apollo.router.compute_jobs.queued`
- `apollo.router.compute_jobs.queue_is_full` - counter of rejected requests when queue is full
- `apollo.router.compute_jobs.duration` - attributes: `job.type`, `job.outcome`
- `apollo.router.compute_jobs.queue.wait.duration` - attributes: `job.type`
- `apollo.router.compute_jobs.execution.duration` - attributes: `job.type`
- `apollo.router.compute_jobs.active_jobs` - attributes: `job.type`

### Subscriptions, batching, and limits
- `apollo.router.opened.subscriptions`
- `apollo.router.skipped.event.count`
- `apollo.router.operations.subscriptions.rejected`
- `apollo.router.operations.subscriptions.terminated.client`
- `apollo.router.operations.subscriptions.terminated.subgraph`
- `apollo.router.operations.batching`
- `apollo.router.operations.batching.size`
- `apollo.router.limits.subgraph_response_size.exceeded`
- `apollo.router.limits.connector_response_size.exceeded`

### Uplink and graph artifacts
- `apollo.router.uplink.fetch.duration.seconds` - attributes: `url`, `query`, `kind`, `code`, `error`
- `apollo.router.uplink.fetch.count.total` - attributes: `status`, `query`
- `apollo.router.oci.manifest.requests` / `.duration` - attributes: `registry`, `kind`, `status`
- `apollo.router.oci.blob.requests` / `.duration` - attributes: `registry`, `kind`, `status`

### Connections
- `apollo.router.connection.acquire.duration` - TCP/Unix socket connection time to downstream; recorded only on new connections, not pool hits. Attributes: `network.transport`, `subgraph.name`

### Telemetry, server, and internal
- `apollo.router.telemetry.studio.reports`
- `apollo.router.telemetry.batch_processor.errors`
- `apollo.router.telemetry.metrics.cardinality_overflow`
- `apollo.router.pipelines`
- `apollo.router.open_connections`
- `apollo.router.operations.recursion`
- `apollo.router.operations.lexical_tokens`

**Docs:** https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/enabling-telemetry/standard-instruments

---

## Note: Important gotchas

- `graphql.document` and `subgraph.graphql.document` are available as span attributes but Apollo strongly recommends **against** using them in production: high cardinality, potential sensitive data in string literals, large payload overhead. Use `graphql.operation.name` instead.
- `default_requirement_level: recommended` on spans **or** instruments will pull in those experimental document attributes automatically. Stick with `required` (the default).
- `http.request.header.<key>` / `http.response.header.<key>` are **not** standard attributes. Use custom selectors: `request_header: "x-my-header"`.
- `apollo.router.session.count.active` is deprecated - use `http.server.active_requests` instead.
- `http.server.active_requests` does **not** support custom selector-based attributes - only its fixed set of standard attributes.
- For `apollo.router.overhead`, filter on `subgraph.active_requests: false` to isolate pure router processing time. When subgraph requests are active (streaming/deferred), the metric includes wait time and becomes less meaningful as a router overhead indicator.

---

## Quick config skeleton

```yaml
telemetry:
  instrumentation:
    spans:
      default_attribute_requirement_level: required   # "recommended" adds graphql.document - avoid in prod

      router:
        attributes:
          http.request.method: true
          http.response.status_code: true
          user_agent.original: true
          # Headers are NOT standard attrs - use custom selectors:
          "http.request.header.x-correlation-id":
            request_header: "x-correlation-id"

      supergraph:
        attributes:
          graphql.operation.name: true
          graphql.operation.type: true
          # graphql.document: true  # DO NOT enable in production

      subgraph:
        attributes:
          subgraph.name: true
          subgraph.graphql.operation.name: true
          subgraph.graphql.operation.type: true

      connector:
        attributes:
          subgraph.name: true
          connector.source.name: true
          connector.http.method: true
          connector.url.template: true

    instruments:
      default_requirement_level: required   # enables all http.* OTel instruments by default

      router:
        apollo.router.overhead: true
        apollo.router.graphql_error: true
        apollo.router.query_planning.plan.duration: true
        http.server.request.duration:
          attributes:
            http.request.method: true
            http.response.status_code: true
        http.server.active_requests:
          attributes:
            # NOTE: custom selectors NOT supported on this metric
            # Only these standard attrs are available:
            server.address: true
            server.port: true
            url.scheme: true

      subgraph:
        http.client.request.duration:
          attributes:
            subgraph.name: true

      connector:
        http.client.request.duration:
          attributes:
            connector.source.name: true
```

---

## Sources

- [Standard Attributes](https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/enabling-telemetry/standard-attributes)
- [Instruments](https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/enabling-telemetry/instruments)
- [Router Instruments (Standard)](https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/enabling-telemetry/standard-instruments)
