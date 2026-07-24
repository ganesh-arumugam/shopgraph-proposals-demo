#!/usr/bin/env bash
# test-queries.sh — sample queries for validating main.rhai (log redaction).
#
# Prereqs (from repo root, two terminals):
#   Terminal A:  npm run start:subgraphs
#   Terminal B:  npm run router:start 2>&1 \
#                  | grep --line-buffered -E '\[fields\]|\[redaction\]' \
#                  | jq -Rr 'fromjson? | .message'
#
# Then run this script in a third terminal. Compare each CLIENT RESPONSE below
# (full, unredacted) against the [fields]/[redaction] lines in Terminal B
# (sensitive values masked). Requires: curl, jq.
#
# If EADDRINUSE on restart: lsof -tiTCP:4001 | xargs kill

set -euo pipefail
ROUTER_URL="${ROUTER_URL:-http://localhost:4000/}"

post() { curl -s -X POST "$ROUTER_URL" -H 'content-type: application/json' -d "$1"; }
hr()   { printf '\n=== %s ===\n' "$1"; }

# 1. Response redaction — buyerId is on the sensitive list.
#    CLIENT sees real buyerId; LOG masks it to "[REDACTED]".
hr "1. Response redaction (orders.buyerId)"
post '{"query":"query GetOrders { orders { id buyerId status } }"}' | jq

# 2. Request logging — named operation + variables.
#    LOG [fields] shows op=GetOrder, the full selection set, and variables run
#    through redact() (here `id` is not sensitive, so it shows).
hr "2. Request logging (named op + variables)"
post '{"operationName":"GetOrder","variables":{"id":"order:2"},"query":"query GetOrder($id: ID!) { order(id: $id) { id buyerId status } }"}' | jq

# 3. Variable redaction — titleStartsWith is on the sensitive list (input-only).
#    CLIENT gets full search results; LOG masks the search term, even nested
#    inside the input object: #{"searchInput": #{"titleStartsWith": "[REDACTED]"}}.
hr "3. Variable redaction (search filter)"
post '{"operationName":"Search","variables":{"searchInput":{"titleStartsWith":"Tra"}},"query":"query Search($searchInput: ProductSearchInput!) { searchProducts(searchInput: $searchInput) { title category } }"}' | jq

# 4. Negative control — nothing sensitive requested.
#    LOG [redaction] line shows full product data with NO "[REDACTED]",
#    proving the script only masks names on the sensitive list.
hr "4. Negative control (no sensitive fields)"
post '{"query":"query Catalog { searchProducts { title category variants { price size } } }"}' | jq

hr "done"
echo "Now check Terminal B: sensitive values are masked in the logs while the"
echo "responses above returned the real data."
