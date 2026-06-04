#!/usr/bin/env bash
#
# ShopGraph observability demo driver — hands-free control of the
# logs + traces + metrics correlation demo (see DEMO.md).
#
# Usage:
#   ./demo.sh up            # start Jaeger+Prometheus, subgraphs, router (clean)
#   ./demo.sh status        # show what's running + URLs + scrape health
#   ./demo.sh query         # fire one normal query, print trace_id + links
#   ./demo.sh latency       # arm latency scenario, drive traffic, print trace_id + links
#   ./demo.sh error         # arm error scenario, trigger it, print trace_id + links
#   ./demo.sh reset         # subgraphs back to clean baseline (disarm scenarios)
#   ./demo.sh down          # stop everything
#   ./demo.sh open          # open the Jaeger + Prometheus UIs
#
# The router/subgraphs run on the host as background processes managed here;
# logs + pids live in observability/.run/ (gitignored).

set -euo pipefail

# ── paths ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN="$SCRIPT_DIR/.run"
mkdir -p "$RUN"
SUBGRAPH_LOG="$RUN/subgraphs.log"
ROUTER_LOG="$RUN/router.log"

# ── ports / urls ───────────────────────────────────────────────────────
ROUTER_PORT=4000
SUBGRAPH_PORT=4001
METRICS_PORT=9091
JAEGER_UI="http://localhost:16686"
PROM_UI="http://localhost:9090"

# ── pretty output ──────────────────────────────────────────────────────
c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
say()  { printf "%s\n" "$*"; }
step() { printf "%s▸ %s%s\n" "$c_blue" "$*" "$c_off"; }
ok()   { printf "%s✓ %s%s\n" "$c_green" "$*" "$c_off"; }
warn() { printf "%s! %s%s\n" "$c_yellow" "$*" "$c_off"; }
err()  { printf "%s✗ %s%s\n" "$c_red" "$*" "$c_off"; }

# ── helpers ────────────────────────────────────────────────────────────
pid_on_port() { lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -1; }

kill_port() {
  local p; p="$(pid_on_port "$1")"
  if [ -n "$p" ]; then kill "$p" 2>/dev/null || true; sleep 1; fi
}

wait_for() {           # wait_for <logfile> <grep-pattern> <timeout-s> <label>
  local f="$1" pat="$2" t="${3:-30}" label="$4" i=0
  while ! grep -qE "$pat" "$f" 2>/dev/null; do
    sleep 0.5; i=$((i+1))
    if [ "$i" -gt $((t*2)) ]; then err "timed out waiting for $label"; tail -5 "$f"; return 1; fi
  done
}

ensure_router_binary() {
  local bin="$REPO/router/router"
  [ -f "$bin" ] || { err "router binary missing — run: npm run router:download"; exit 1; }
  # macOS Gatekeeper SIGKILLs freshly-copied unsigned binaries; re-sign defensively.
  if ! "$bin" --version >/dev/null 2>&1; then
    warn "router binary failed to exec — re-signing ad-hoc (macOS Gatekeeper)"
    xattr -c "$bin" 2>/dev/null || true
    codesign --force --sign - "$bin" >/dev/null 2>&1 || true
  fi
}

start_subgraphs() {    # start_subgraphs [ENV=VAL ...]
  kill_port "$SUBGRAPH_PORT"
  step "starting subgraphs ${*:+(${*})}"
  ( cd "$REPO" && env "$@" nohup npm run start:subgraphs >"$SUBGRAPH_LOG" 2>&1 & )
  wait_for "$SUBGRAPH_LOG" "All subgraphs running" 30 "subgraphs"
  ok "subgraphs up on :$SUBGRAPH_PORT"
}

start_router() {
  ensure_router_binary
  kill_port "$ROUTER_PORT"
  step "starting router"
  ( cd "$REPO" && nohup npm run router:start >"$ROUTER_LOG" 2>&1 & )
  wait_for "$ROUTER_LOG" 'GraphQL endpoint exposed|"level":"ERROR"' 45 "router"
  if grep -q "GraphQL endpoint exposed" "$ROUTER_LOG"; then ok "router up on :$ROUTER_PORT"
  else err "router failed to start:"; grep '"level":"ERROR"' "$ROUTER_LOG" | tail -3; return 1; fi
}

backends_up() {
  step "starting Jaeger + Prometheus (docker compose)"
  ( cd "$SCRIPT_DIR" && docker compose up -d >/dev/null )
  ok "backends up — Jaeger $JAEGER_UI · Prometheus $PROM_UI"
}

# Fire a query (no traceparent → router mints the trace_id), return last trace_id.
fire() {               # fire '<graphql query string>' [count]
  local q="$1" n="${2:-1}" i
  for ((i=0;i<n;i++)); do
    curl -s "http://localhost:$ROUTER_PORT/" -H 'content-type: application/json' \
      --data "$(printf '{"query":%s}' "$(json_str "$q")")" >/dev/null || true
  done
  sleep 1
  tail -60 "$ROUTER_LOG" | grep '"kind":"router.request"' | tail -1 \
    | sed -E 's/.*"trace_id":"([0-9a-f]+)".*/\1/'
}

json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

show_trace() {         # show_trace <trace_id> [extra note]
  local tid="$1"
  if [ -z "$tid" ]; then warn "no trace_id captured (is the router running?)"; return; fi
  echo
  printf "  %strace_id%s  %s\n" "$c_bold" "$c_off" "$tid"
  printf "  %sJaeger%s    %s/trace/%s\n" "$c_bold" "$c_off" "$JAEGER_UI" "$tid"
  printf "  %sLogs%s      grep %s %s\n" "$c_bold" "$c_off" "$tid" "$ROUTER_LOG"
}

# ── commands ───────────────────────────────────────────────────────────
cmd_up() {
  backends_up
  start_subgraphs
  start_router
  echo; cmd_status
}

cmd_down() {
  step "stopping router + subgraphs"
  kill_port "$ROUTER_PORT"; kill_port "$SUBGRAPH_PORT"
  step "stopping backends"
  ( cd "$SCRIPT_DIR" && docker compose down >/dev/null 2>&1 || true )
  ok "all stopped"
}

cmd_status() {
  printf "%s%sShopGraph demo status%s\n" "$c_bold" "$c_blue" "$c_off"
  local rp sp; rp="$(pid_on_port $ROUTER_PORT)"; sp="$(pid_on_port $SUBGRAPH_PORT)"
  [ -n "$rp" ] && ok "router    :$ROUTER_PORT (pid $rp)"      || err "router    :$ROUTER_PORT down"
  [ -n "$sp" ] && ok "subgraphs :$SUBGRAPH_PORT (pid $sp)"    || err "subgraphs :$SUBGRAPH_PORT down"
  if curl -s "http://localhost:$METRICS_PORT/metrics" >/dev/null 2>&1; then ok "metrics   :$METRICS_PORT/metrics"; else err "metrics   :$METRICS_PORT down"; fi
  docker ps --filter name=shopgraph --format '  {{.Names}}: {{.Status}}' 2>/dev/null || true
  local health; health="$(curl -s "$PROM_UI/api/v1/targets" 2>/dev/null | grep -o '"health":"[a-z]*"' | head -1 | cut -d'"' -f4 || true)"
  [ "$health" = "up" ] && ok "prometheus → router scrape: up" || warn "prometheus → router scrape: ${health:-unknown}"
  echo
  printf "  Jaeger UI:     %s\n  Prometheus UI: %s\n" "$JAEGER_UI" "$PROM_UI"
}

cmd_query() {
  step "firing one query (no traceparent → router mints trace_id)"
  local tid; tid="$(fire '{ orders { id status } }' 1)"
  ok "query sent"
  show_trace "$tid"
}

cmd_latency() {
  start_subgraphs DEMO_SLOW_ORDERS_MS=800
  step "driving 10 slow 'order' queries"
  local tid; tid="$(fire 'query Slow { order(id:"order:2"){ id status placedAt items{ quantity unitPrice } } }' 10)"
  ok "latency scenario armed (orders ~800ms)"
  show_trace "$tid"
  echo
  say "  ${c_bold}Prometheus — p95 per subgraph (orders should stand out):${c_off}"
  say "    histogram_quantile(0.95, sum by (le, subgraph_name) (rate(http_client_request_duration_seconds_bucket[1m])))"
  say "  In Jaeger, open the trace above → the orders 'subgraph_request' span is the slow hop."
  warn "run './demo.sh reset' when done to disarm"
}

cmd_error() {
  start_subgraphs DEMO_FAIL_PRODUCT_ID=product:boom
  step "triggering a failing 'product' query"
  local tid; tid="$(fire 'query Boom { product(id:"product:boom"){ id title } }' 1)"
  ok "error scenario armed + triggered"
  show_trace "$tid"
  echo
  say "  ${c_bold}Prometheus — GraphQL error rate by code (fires even though HTTP stays 200):${c_off}"
  say "    sum by (code) (rate(apollo_router_graphql_error_total[1m]))"
  say "  In Jaeger: service apollo-router-local → filter Tags 'error=true' → open the trace."
  say "  The products subgraph span is flagged with: 'Catalog lookup failed: downstream inventory timeout'"
  warn "run './demo.sh reset' when done to disarm"
}

cmd_reset() {
  start_subgraphs
  ok "subgraphs restored to clean baseline (scenarios disarmed)"
}

cmd_open() {
  command -v open >/dev/null && open "$JAEGER_UI" "$PROM_UI" && ok "opened UIs" || say "Jaeger: $JAEGER_UI   Prometheus: $PROM_UI"
}

# ── dispatch ───────────────────────────────────────────────────────────
case "${1:-}" in
  up|start)   cmd_up ;;
  down|stop)  cmd_down ;;
  status)     cmd_status ;;
  query)      cmd_query ;;
  latency)    cmd_latency ;;
  error)      cmd_error ;;
  reset)      cmd_reset ;;
  open)       cmd_open ;;
  *)
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
