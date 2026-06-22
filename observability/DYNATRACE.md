# Sending Router traces and logs to Dynatrace

This adds Dynatrace as a backend without changing the router. The OTel Collector fans
**traces** out to both Jaeger and Dynatrace, and ships the router's **logs** to Dynatrace
with `trace_id`/`span_id` so they correlate to the traces (the Logs tab on a trace).

```text
  Apollo Router :4000 --OTLP :4327--> OTel Collector --+--> Jaeger :16686  (traces, local)
                                                        +--> Dynatrace      (traces)
  Router stdout log -------filelog----> OTel Collector ----> Dynatrace      (logs, w/ trace_id)
```

The router config is identical to the base demo. Dynatrace is configured only in the
collector, which is the whole point of having a collector in the path. The router has no
OTLP log exporter, so logs are shipped by tailing its stdout log file (mounted into the
collector); each line's `trace_id`/`span_id` is lifted onto the log record for correlation.

## Prerequisites

1. A Dynatrace environment (SaaS or Managed).
2. An API token with **both** scopes:
   - **`openTelemetryTrace.ingest`** (traces)
   - **`logs.ingest`** (logs, for the Logs-on-a-trace correlation)
   Dynatrace console: Access Tokens > Generate new token > enable those scopes.
3. Your OTLP endpoint:
   - SaaS: `https://<env-id>.live.dynatrace.com/api/v2/otlp`
   - Managed: `https://<your-domain>/e/<env-id>/api/v2/otlp`
   - ActiveGate: `https://<activegate-host>:9999/e/<env-id>/api/v2/otlp`

The exporter posts to `<endpoint>/v1/traces`. Do not include `/v1/traces` in the value.

## Setup

```bash
cd observability
cp dynatrace.env.example .env          # .env is gitignored
# edit .env: set DT_OTLP_ENDPOINT and DT_API_TOKEN
```

## Run

With the driver (it auto-adds the Dynatrace overlay when `DT_API_TOKEN` is set):

```bash
# from the repo root, with the vars exported (or sourced from observability/.env)
export DT_OTLP_ENDPOINT="https://<env-id>.live.dynatrace.com/api/v2/otlp"
export DT_API_TOKEN="dt0c01.XXXX.YYYY"
./observability/demo.sh up
./observability/demo.sh load 20      # generate traffic
```

Or with plain compose (from `observability/`, vars in `.env`):

```bash
docker compose -f docker-compose.yml -f docker-compose.dynatrace.yml up -d
```

Without `DT_API_TOKEN`, `./demo.sh up` runs the normal Jaeger-only stack, so the base
demo is unaffected.

## Verify

1. Collector is exporting (no auth errors):
   ```bash
   docker logs shopgraph-otel-collector 2>&1 | grep -i "dynatrace\|error\|export" | tail
   ```
   A 401/403 means the token or its scope is wrong; a 404 usually means the endpoint
   has a trailing `/v1/traces` or a typo.
2. In Dynatrace: open **Distributed traces** (or Services). Filter by the service
   `apollo-router-local` (set via the router's `service.name` resource attribute).
3. Drive a request and look it up by `trace_id` (the same id printed by
   `./demo.sh query` / `propagate` and shown in Jaeger). The trace appears in both.
4. Run `./demo.sh error` and confirm the request shows as **failed** in Dynatrace. The
   router marks spans `otel.status_code=ERROR` on a GraphQL error even though the HTTP
   status is 200, so Dynatrace's error detection picks it up.

## Notes and caveats

- **Router config is unchanged.** Switching or adding a backend is a collector change.
- **trace_id is the query key in Dynatrace**, not the full `traceparent`. The router
  originates a trace_id when the client sends no `traceparent`, and continues the
  client's trace_id when one is present (see `./demo.sh query` vs `propagate`).
- **Service identity** comes from the router resource attributes (`service.name`,
  `service.namespace`, `deployment.environment.name`). Adjust them in
  `router/router-config.yaml` to match how you want the service to appear.
- **Sampling**: the demo uses `sampler: always_on` and `parent_based_sampler: false`.
  In production prefer a fractional sampler and `parent_based_sampler: true` so the
  router honors an upstream sampling decision (for example from OneAgent).
- **Dual instrumentation**: if the subgraphs are OneAgent-instrumented while the router
  exports via OTLP, align propagation and sampling to one source of truth, or you can
  get duplicated or disconnected traces.
- **Metrics/logs to Dynatrace** are out of scope here (traces only). To add them, give
  the token `metrics.ingest` / `logs.ingest` scopes and add the matching pipelines to
  `otel-collector-config.dynatrace.yml` (a `prometheus` receiver scraping the router for
  metrics, plus `otlphttp/dynatrace` on those pipelines).