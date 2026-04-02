#!/bin/bash
# Publishes both subgraph schemas to GraphOS using rover subgraph publish.
# Run this once after initial setup to register schemas in your GraphOS graph.
# In CI, this is handled by .github/workflows/publish.yml on merge to main.

set -euo pipefail

ENV_FILE="../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

if [ -z "${APOLLO_KEY:-}" ] || [ -z "${APOLLO_GRAPH_REF:-}" ]; then
  echo "ERROR: APOLLO_KEY and APOLLO_GRAPH_REF must be set in .env"
  exit 1
fi

SUBGRAPH_URL="${SUBGRAPH_URL:-http://localhost:4001}"

echo "Publishing subgraphs to GraphOS..."
echo "  Graph: $APOLLO_GRAPH_REF"
echo "  Subgraph URL: $SUBGRAPH_URL"

rover subgraph publish "$APOLLO_GRAPH_REF" \
  --name products \
  --schema ../subgraphs/products/schema.graphql \
  --routing-url "$SUBGRAPH_URL/products/graphql"

echo "  ✓ products subgraph published"

rover subgraph publish "$APOLLO_GRAPH_REF" \
  --name orders \
  --schema ../subgraphs/orders/schema.graphql \
  --routing-url "$SUBGRAPH_URL/orders/graphql"

echo "  ✓ orders subgraph published"
echo ""
echo "Done. Visit https://studio.apollographql.com to view your schema."
