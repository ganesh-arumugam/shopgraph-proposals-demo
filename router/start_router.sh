#!/bin/bash
# Starts the Apollo Router using managed federation (GraphOS).
# Requires APOLLO_KEY and APOLLO_GRAPH_REF to be set in ../.env

set -euo pipefail

# Load environment variables
ENV_FILE="../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "Copy .env.example to .env and fill in your values."
  exit 1
fi

if [ -z "${APOLLO_KEY:-}" ] || [ -z "${APOLLO_GRAPH_REF:-}" ]; then
  echo "ERROR: APOLLO_KEY and APOLLO_GRAPH_REF must be set in .env"
  exit 1
fi

if [ ! -f "./router" ]; then
  echo "Router binary not found. Run ./download_router.sh first."
  exit 1
fi

echo "Starting Apollo Router..."
echo "  Graph: $APOLLO_GRAPH_REF"
echo "  Listening at: http://localhost:4000"

APOLLO_KEY="$APOLLO_KEY" \
APOLLO_GRAPH_REF="$APOLLO_GRAPH_REF" \
./router --config ./router-config.yaml
