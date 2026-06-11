#!/usr/bin/env bash
#
# ShopGraph observability demo driver — hands-free control of the
# logs + traces + metrics correlation demo (see DEMO.md).
#
# Usage:
#   ./demo.sh up            # start Jaeger+Prometheus, subgraphs, router (clean)
#   ./demo.sh status        # show what's running + URLs + scrape health
#   ./demo.sh query         # fire one query with NO traceparent -> router MINTS a trace_id (Jaeger pivot)
#   ./demo.sh propagate     # fire one query WITH a client traceparent -> router CONTINUES it
#   ./demo.sh load [secs]   # drive sustained traffic (default 20s) so the Grafana panels populate
#   ./demo.sh latency       # arm latency scenario, drive traffic, print trace_id + links
#   ./demo.sh error         # arm error scenario, trigger it, print trace_id + links
#   ./demo.sh reset         # subgraphs back to clean baseline (disarm scenarios)
#   ./demo.sh down          # stop everything
#   ./demo.sh open          # open the Grafana dashboard + Jaeger
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

# ── credentials ─────────────────────────────────────────────────────────
# Load ONLY DT_* vars from the repo-root .env. We deliberately do NOT source the
# whole file: it also holds APOLLO_GRAPH_ID + APOLLO_GRAPH_REF, and leaking both
# into the subgraphs makes Apollo Server fail ("Cannot specify both graph ref and
# graph ID"). The router reads APOLLO_* itself via start_router.sh.
if [ -f "$REPO/.env" ]; then
  while IFS= read -r _line; do
    case "$_line" in
      DT_*=*)
        _k=${_line%%=*}; _v=${_line#*=}
        _v=${_v#[\"\']}; _v=${_v%[\"\']}        # strip one layer of surrounding quotes
        export "$_k=$_v" ;;
    esac
  done < "$REPO/.env"
  unset _line _k _v 2>/dev/null || true
fi
# Derive the Dynatrace OTLP endpoint from the environment id (SaaS) when not set
# explicitly. For Managed/ActiveGate, set DT_OTLP_ENDPOINT in .env directly.
if [ -z "${DT_OTLP_ENDPOINT:-}" ] && [ -n "${DT_ENVIRONMENT_ID:-}" ]; then
  export DT_OTLP_ENDPOINT="https://${DT_ENVIRONMENT_ID}.live.dynatrace.com/api/v2/otlp"
fi

# ── ports / urls ───────────────────────────────────────────────────────
ROUTER_PORT=4000
SUBGRAPH_PORT=4001
METRICS_PORT=9091
JAEGER_UI="http://localhost:16686"
PROM_UI="http://localhost:9090"
GRAFANA_UI="http://localhost:3000/d/shopgraph-router"

# ── pretty output ──────────────────────────────────────────────────────
c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
say()  { printf "%s\n" "$*"; }
step() { printf "%s▸ %s%s\n" "$c_blue" "$*" "$c_off"; }
ok()   { printf "%s✓ %s%s\n" "$c_green" "$*" "$c_off"; }
warn() { printf "%s! %s%s\n" "$c_yellow" "$*" "$c_off"; }
err()  { printf "%s✗ %s%s\n" "$c_red" "$*" "$c_off"; }

# ── helpers ────────────────────────────────────────────────────────────
pid_on_port() { lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -1 || true; }

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

# Compose args. Add the Dynatrace overlay automatically when a token is set
# (bash 3.2 compatible — no mapfile).
COMPOSE_ARGS=(-f docker-compose.yml)
[ -n "${DT_API_TOKEN:-}" ] && COMPOSE_ARGS+=(-f docker-compose.dynatrace.yml)

backends_up() {
  if [ -n "${DT_API_TOKEN:-}" ]; then
    step "starting Jaeger + Prometheus + Grafana + Dynatrace export (docker compose)"
  else
    step "starting Jaeger + Prometheus + Grafana (docker compose)"
  fi
  ( cd "$SCRIPT_DIR" && docker compose "${COMPOSE_ARGS[@]}" up -d >/dev/null )
  ok "backends up — Jaeger $JAEGER_UI · Prometheus $PROM_UI${DT_API_TOKEN:+ · Dynatrace on}"
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
  ( cd "$SCRIPT_DIR" && docker compose "${COMPOSE_ARGS[@]}" down >/dev/null 2>&1 || true )
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
  printf "  Grafana:       %s   (dashboards, the Datadog-style view)\n" "$GRAFANA_UI"
  printf "  Jaeger UI:     %s\n  Prometheus UI: %s\n" "$JAEGER_UI" "$PROM_UI"
}

cmd_query() {
  step "firing one query (no traceparent → router mints trace_id)"
  local tid; tid="$(fire '{ orders { id status } }' 1)"
  ok "query sent"
  show_trace "$tid"
  echo
  say "  Note: ONE query barely registers on Grafana's rate-based panels. For the"
  say "  dashboard to light up, drive sustained traffic: './demo.sh load' or './demo.sh latency'."
}

cmd_load() {
  local secs="${1:-20}"
  step "generating ~${secs}s of traffic (both subgraphs) to populate Grafana"
  local end; end=$(( $(date +%s) + secs ))
  local count=0
  while [ "$(date +%s)" -lt "$end" ]; do
    curl -s -o /dev/null http://localhost:4000/ -H 'content-type: application/json' \
      -d '{"query":"{ order(id:\"order:2\"){ id status } searchProducts(searchInput:{}){ id title } }"}' || true
    count=$((count+1))
  done
  ok "sent $count requests over ${secs}s"
  say "  Open Grafana (give it ~10s to scrape): $GRAFANA_UI"
}

cmd_propagate() {
  # Client sends its OWN W3C traceparent; the router should CONTINUE that trace
  # (adopt the client's trace-id) rather than mint a new one. Contrast with `query`.
  local tid sid
  tid="$(openssl rand -hex 16)"   # 32 hex = client trace-id
  sid="$(openssl rand -hex 8)"    # 16 hex = client span-id
  step "client sends traceparent 00-$tid-$sid-01 (router should continue it)"
  curl -s -o /dev/null http://localhost:4000/ -H 'content-type: application/json' \
    -H "traceparent: 00-$tid-$sid-01" \
    -d '{"query":"{ order(id:\"order:2\"){ id status } searchProducts(searchInput:{}){ id title } }"}' || true
  sleep 1
  ok "router continued the client's trace (no new id minted)"
  echo
  printf "  %sclient trace_id%s  %s\n" "$c_bold" "$c_off" "$tid"
  printf "  %sJaeger%s          %s/trace/%s\n" "$c_bold" "$c_off" "$JAEGER_UI" "$tid"
  say "  The trace's root span is the router, filed under the CLIENT's trace-id above."
  say "  Compare './demo.sh query' (no header) where the router MINTS a fresh id instead."
}

cmd_latency() {
  start_subgraphs DEMO_SLOW_ORDERS_MS=800
  step "driving 10 queries that hit BOTH subgraphs (orders slow + products fast)"
  # Combined query so both subgraphs appear in metrics AND the trace shows a fast
  # products span next to the slow orders span.
  local tid; tid="$(fire '{ order(id:"order:2"){ id status } searchProducts(searchInput:{}){ id title } }' 10)"
  ok "latency scenario armed (orders ~800ms, products fast)"
  show_trace "$tid"
  echo
  say "  ${c_bold}Prometheus — p95 per subgraph (orders ~0.8s, products ~0.002s):${c_off}"
  say "    histogram_quantile(0.95, sum by (le, subgraph_name) (rate(http_client_request_duration_seconds_bucket[1m])))"
  say "  In Jaeger: parents (router/supergraph/execution) all show ~800ms because they enclose"
  say "  the slow child. The cause is the leaf 'subgraph [orders]' span; 'subgraph [products]' is ~2ms."
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
  command -v open >/dev/null && open "$GRAFANA_UI" "$JAEGER_UI" && ok "opened Grafana + Jaeger" || say "Grafana: $GRAFANA_UI   Jaeger: $JAEGER_UI   Prometheus: $PROM_UI"
}

# ── dispatch ───────────────────────────────────────────────────────────
case "${1:-}" in
  up|start)   cmd_up ;;
  down|stop)  cmd_down ;;
  status)     cmd_status ;;
  query)      cmd_query ;;
  propagate)  cmd_propagate ;;
  load)       cmd_load "${2:-20}" ;;
  latency)    cmd_latency ;;
  error)      cmd_error ;;
  reset)      cmd_reset ;;
  open)       cmd_open ;;
  *)
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
