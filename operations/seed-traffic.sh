#!/usr/bin/env bash
# Generate router traffic against the REAL products/orders schema so GraphOS
# Insights, the Studio Clients page, and error-rate metrics have real data
# instead of "no traffic in this window."
#
# Ported from apollo-dynatrace-telemetry/demo/load_clients.sh - that script
# targets a different demo schema (boom field, orders.total, addProduct
# mutation) that doesn't exist here. This is the same client-tagging pattern
# rebuilt against operations/*.graphql and this repo's actual Query fields.
#
# Requires the subgraphs + router already running:
#   npm run dev:subgraphs   (port 4001)
#   npm run router:start    (port 4000, managed federation -> reports to
#                             APOLLO_GRAPH_REF from .env)
#
# Clients (name / version), each with its own query mix - this is what gives
# Studio's Clients page real buckets instead of "unidentified client":
#   web-storefront@1.4.2       searchProducts, product(id)   (browsing)
#   mobile-app@3.0.0           orders                         (order history)
#   internal-ops-tool@0.9.1    order(id)                      (single lookup)
#
# Every 4th iteration also fires GetOrderWithDelivery, which asks for
# `estimatedDelivery` - a field that intentionally doesn't exist yet (see
# subgraphs/orders/schema.graphql). That's a real GraphQL validation error,
# not a scripted one, and it's what seeds a non-zero error-rate signal for
# GetSubgraphMetrics / GetOperationMetrics.
#
# Usage: ./operations/seed-traffic.sh [iterations-per-client]   (default 15)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
[ -f "$ROOT/.env" ] && { set -a; . "$ROOT/.env"; set +a; }

ROUTER="http://127.0.0.1:${ROUTER_PORT:-4000}/"
N="${1:-15}"

post() {  # client_name client_version query [variables_json] -> prints trace id
  local name="$1" version="$2" query="$3" vars="${4:-}"
  [ -z "$vars" ] && vars='{}'
  curl -s -D /tmp/shopgraph-seed-headers -o /tmp/shopgraph-seed-body \
    -X POST "$ROUTER" \
    -H 'Content-Type: application/json' \
    -H "apollographql-client-name: ${name}" \
    -H "apollographql-client-version: ${version}" \
    -d "$(python3 -c '
import json, sys
print(json.dumps({"query": sys.argv[1], "variables": json.loads(sys.argv[2])}))
' "$query" "$vars")"
  grep -i '^apollo-trace-id:' /tmp/shopgraph-seed-headers | tr -d '\r' | awk '{print $2}'
}

echo "Sending ${N} iterations per client (3 clients) to ${ROUTER}"
last_trace=""
for i in $(seq 1 "$N"); do
  # web-storefront: browsing
  post "web-storefront" "1.4.2" \
    'query SearchProducts { searchProducts { id title category variants { id colorway price size } } }' >/dev/null
  last_trace=$(post "web-storefront" "1.4.2" \
    'query ProductById($id: ID!) { product(id: $id) { id title description variants { id price } } }' \
    "{\"id\": \"product:$(( (i % 5) + 1 ))\"}")

  # mobile-app: order history listing
  post "mobile-app" "3.0.0" \
    'query GetAllOrders { orders { id buyerId status placedAt items { quantity unitPrice variant { id } } } }' >/dev/null

  # internal-ops-tool: single order lookup
  post "internal-ops-tool" "0.9.1" \
    'query GetOrder($id: ID!) { order(id: $id) { id status placedAt } }' \
    "{\"id\": \"order:$(( (i % 4) + 1 ))\"}" >/dev/null

  # Pre-Proposal field request - real validation error, not scripted
  if [ $((i % 4)) -eq 0 ]; then
    post "web-storefront" "1.4.2" \
      'query GetOrderWithDelivery($id: ID!) { order(id: $id) { id estimatedDelivery } }' \
      '{"id": "order:1"}' >/dev/null
  fi

  printf '.'
done
echo

cat <<SUMMARY

Traffic sent: ~$((N * 4)) requests across 3 clients (web-storefront@1.4.2,
mobile-app@3.0.0, internal-ops-tool@0.9.1) plus periodic validation errors.
Last trace id: ${last_trace:-<none>}

GetTopOperations needs \`to\` >= 6h ago - visible today. GetOperationMetrics /
GetSubgraphMetrics bucket per day and need \`to\` >= 1 day ago - visible
tomorrow. Target ${APOLLO_GRAPH_REF:-<graph>@<variant>} in graphos-tools calls.

Studio Insights: https://studio.apollographql.com/graph/${APOLLO_GRAPH_REF%%@*}/variant/${APOLLO_GRAPH_REF##*@}/insights
SUMMARY
