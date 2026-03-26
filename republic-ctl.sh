#!/bin/bash
# ============================================================
# RepublicAI Node Control Script
# Manage all services: node, sidecar, auto-compute, HTTP, tunnel
# Usage: republic-ctl.sh {start|stop|restart|status|logs} [service]
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# All RepublicAI systemd services (in startup order)
SERVICES=(
  "republicd"                  # Core blockchain node
  "republic-sidecar"           # Compute job sidecar (validator)
  "republic-autocompute"       # Auto-compute GPU inference
  "republic-http"              # HTTP file server (port 8081)
  "cloudflared"                # Cloudflare tunnel
)

SERVICE_LABELS=(
  "Republic Node (republicd)"
  "Job Sidecar"
  "Auto-Compute (GPU)"
  "HTTP Server (:8081)"
  "Cloudflare Tunnel"
)

# RepublicAI Docker containers
DOCKER_CONTAINERS=(
  "gateway"                    # Embedding/inference gateway
)

DOCKER_LABELS=(
  "Inference Gateway (Docker)"
)

# ============================================================
# Helper functions
# ============================================================

print_header() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  RepublicAI Node Control — $1${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
  echo ""
}

get_status_color() {
  local status=$1
  case "$status" in
    active)    echo "${GREEN}● RUNNING${NC}" ;;
    inactive)  echo "${RED}○ STOPPED${NC}" ;;
    failed)    echo "${RED}✗ FAILED${NC}" ;;
    not-found) echo "${YELLOW}? NOT FOUND${NC}" ;;
    *)         echo "${YELLOW}? $status${NC}" ;;
  esac
}

is_docker_target() {
  local input=$1
  case "$input" in
    gateway) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_service() {
  local input=$1
  case "$input" in
    node|republicd)         echo "republicd" ;;
    sidecar)                echo "republic-sidecar" ;;
    autocompute|compute|ac) echo "republic-autocompute" ;;
    http|server)            echo "republic-http" ;;
    tunnel|cloudflared|cf)  echo "cloudflared" ;;
    gateway)                echo "gateway" ;;
    *)                      echo "$input" ;;
  esac
}

# ============================================================
# Commands
# ============================================================

cmd_status() {
  print_header "Status"

  # Systemd services
  printf "  %-30s %s\n" "SERVICE" "STATUS"
  echo "  ────────────────────────────── ─────────────"
  for i in "${!SERVICES[@]}"; do
    local svc=${SERVICES[$i]}
    local label=${SERVICE_LABELS[$i]}
    local status=$(systemctl is-active "$svc" 2>/dev/null | head -1 | tr -d '[:space:]')
    [ -z "$status" ] && status="not-found"
    local status_str=$(get_status_color "$status")
    printf "  %-30s %b\n" "$label" "$status_str"
  done

  # Docker containers
  echo ""
  for i in "${!DOCKER_CONTAINERS[@]}"; do
    local cname=${DOCKER_CONTAINERS[$i]}
    local clabel=${DOCKER_LABELS[$i]}
    local cstatus=$(docker inspect --format '{{.State.Status}}' "$cname" 2>/dev/null || echo "not-found")
    if [ "$cstatus" = "running" ]; then
      printf "  %-30s %b\n" "$clabel" "${GREEN}● RUNNING${NC}"
    elif [ "$cstatus" = "exited" ]; then
      printf "  %-30s %b\n" "$clabel" "${RED}○ STOPPED${NC}"
    else
      printf "  %-30s %b\n" "$clabel" "${YELLOW}? $cstatus${NC}"
    fi
  done

  # Quick health checks
  echo ""
  echo -e "  ${BLUE}Health Checks:${NC}"

  # Node sync
  local catching_up=$(curl -s http://localhost:26657/status 2>/dev/null | jq -r '.result.sync_info.catching_up' 2>/dev/null)
  local latest_block=$(curl -s http://localhost:26657/status 2>/dev/null | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)
  if [ "$catching_up" = "false" ]; then
    echo -e "    Node Sync:       ${GREEN}✅ Synced${NC} (block $latest_block)"
  elif [ "$catching_up" = "true" ]; then
    echo -e "    Node Sync:       ${YELLOW}⏳ Catching up${NC} (block $latest_block)"
  else
    echo -e "    Node Sync:       ${RED}❌ Unreachable${NC}"
  fi

  # HTTP server
  local http_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/ 2>/dev/null)
  if [ "$http_status" = "200" ]; then
    echo -e "    HTTP Server:     ${GREEN}✅ OK${NC} (port 8081)"
  else
    echo -e "    HTTP Server:     ${RED}❌ Down${NC}"
  fi

  # Cloudflare tunnel
  local cf_status=$(curl -s -o /dev/null -w "%{http_code}" https://republicai.devn.cloud/ 2>/dev/null)
  if [ "$cf_status" = "200" ]; then
    echo -e "    CF Tunnel:       ${GREEN}✅ OK${NC} (republicai.devn.cloud)"
  else
    echo -e "    CF Tunnel:       ${RED}❌ Down${NC}"
  fi

  # Wallet balance
  local balance=$(republicd query bank balances rai1vgjpdewsmvnrdqlk75pmhhae397wghfkwe8lgu --node http://localhost:26657 -o json 2>/dev/null | jq -r '.balances[0].amount // "0"' 2>/dev/null)
  if [ -n "$balance" ] && [ "$balance" != "0" ] && [ "$balance" != "null" ]; then
    local rai=$(echo "scale=4; $balance / 1000000000000000000" | bc 2>/dev/null || echo "?")
    echo -e "    Wallet Balance:  ${GREEN}$rai RAI${NC}"
  fi

  echo ""
}

cmd_start() {
  local target=$1
  if [ -n "$target" ]; then
    local svc=$(resolve_service "$target")
    if is_docker_target "$target"; then
      echo -e "${GREEN}▶ Starting Docker: $svc...${NC}"
      docker start "$svc" 2>/dev/null || echo "  Failed to start $svc"
    else
      echo -e "${GREEN}▶ Starting $svc...${NC}"
      systemctl start "$svc"
      echo -e "  $(get_status_color $(systemctl is-active $svc))"
    fi
  else
    print_header "Start All"
    for svc in "${SERVICES[@]}"; do
      echo -e "${GREEN}▶ Starting $svc...${NC}"
      systemctl start "$svc" 2>/dev/null || true
      sleep 1
    done
    for cname in "${DOCKER_CONTAINERS[@]}"; do
      echo -e "${GREEN}▶ Starting Docker: $cname...${NC}"
      docker start "$cname" 2>/dev/null || true
    done
    echo -e "\n${GREEN}All services started!${NC}"
    cmd_status
  fi
}

cmd_stop() {
  local target=$1
  if [ -n "$target" ]; then
    local svc=$(resolve_service "$target")
    if is_docker_target "$target"; then
      echo -e "${RED}■ Stopping Docker: $svc...${NC}"
      docker stop "$svc" 2>/dev/null || true
    else
      echo -e "${RED}■ Stopping $svc...${NC}"
      systemctl stop "$svc"
    fi
    echo "  Stopped."
  else
    print_header "Stop All"
    for cname in "${DOCKER_CONTAINERS[@]}"; do
      echo -e "${RED}■ Stopping Docker: $cname...${NC}"
      docker stop "$cname" 2>/dev/null || true
    done
    for (( i=${#SERVICES[@]}-1; i>=0; i-- )); do
      local svc=${SERVICES[$i]}
      echo -e "${RED}■ Stopping $svc...${NC}"
      systemctl stop "$svc" 2>/dev/null || true
    done
    echo -e "\n${RED}All services stopped.${NC}"
  fi
}

cmd_restart() {
  local target=$1
  if [ -n "$target" ]; then
    local svc=$(resolve_service "$target")
    echo -e "${YELLOW}↻ Restarting $svc...${NC}"
    systemctl restart "$svc"
    echo -e "  $(get_status_color $(systemctl is-active $svc))"
  else
    print_header "Restart All"
    cmd_stop
    echo ""
    sleep 2
    cmd_start
  fi
}

cmd_logs() {
  local target=$1
  local lines=${2:-50}
  if [ -n "$target" ]; then
    local svc=$(resolve_service "$target")
    echo -e "${BLUE}📋 Logs for $svc (last $lines lines):${NC}"
    echo ""
    journalctl -u "$svc" --no-pager -n "$lines"
  else
    echo -e "${BLUE}📋 Recent logs for all services:${NC}"
    echo ""
    for svc in "${SERVICES[@]}"; do
      echo -e "${CYAN}── $svc ──${NC}"
      journalctl -u "$svc" --no-pager -n 5 2>/dev/null || echo "  (no logs)"
      echo ""
    done
  fi
}

cmd_help() {
  echo ""
  echo -e "${CYAN}RepublicAI Node Control${NC}"
  echo ""
  echo "Usage: $0 {command} [service] [options]"
  echo ""
  echo "Commands:"
  echo "  status              Show status of all services"
  echo "  start [service]     Start all or specific service"
  echo "  stop  [service]     Stop all or specific service"
  echo "  restart [service]   Restart all or specific service"
  echo "  logs [service] [n]  Show logs (default: last 50 lines)"
  echo ""
  echo "Service shortcuts:"
  echo "  node, republicd     → Republic blockchain node"
  echo "  sidecar             → Compute job sidecar"
  echo "  compute, ac         → Auto-compute GPU inference"
  echo "  http, server        → HTTP file server (:8081)"
  echo "  gateway             → Inference gateway (Docker)"
  echo "  tunnel, cf          → Cloudflare tunnel"
  echo ""
  echo "Examples:"
  echo "  $0 status           # Check everything"
  echo "  $0 restart compute  # Restart only auto-compute"
  echo "  $0 logs sidecar 100 # Last 100 lines of sidecar logs"
  echo "  $0 stop             # Stop everything"
  echo "  $0 start            # Start everything"
  echo ""
}

# ============================================================
# Main
# ============================================================

case "${1:-}" in
  status)   cmd_status ;;
  start)    cmd_start "$2" ;;
  stop)     cmd_stop "$2" ;;
  restart)  cmd_restart "$2" ;;
  logs)     cmd_logs "$2" "$3" ;;
  *)        cmd_help ;;
esac
