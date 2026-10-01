#!/bin/bash

# SAGE Platform Control Script
# Usage: ./sage.sh [up|down|status|logs] [stack_name] [service_name]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$REPO_ROOT/.env"
NETWORK_NAME="sage-network"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Registered stacks ─────────────────────────────────────────────────────────
# Case statement, not an associative array: macOS ships bash 3 (no declare -A)
STACK_NAMES="portainer monitoring redpanda infrastructure"
stack_path() {
  case $1 in
    portainer)      echo "platform/portainer" ;;
    monitoring)     echo "platform/monitoring" ;;
    redpanda)       echo "platform/redpanda" ;;
    infrastructure) echo "infrastructure" ;;
    *)              echo "" ;;
  esac
}

# ── Helpers ───────────────────────────────────────────────────────────────────
print_header() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        SAGE Platform Control         ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}\n"
}

# Run docker compose for one stack, always with the shared root .env
compose() {
  local name=$1
  shift
  docker compose --env-file "$ENV_FILE" \
    -f "$REPO_ROOT/$(stack_path "$name")/docker-compose.yml" "$@"
}

# Stop early, with one clear message, if the basics are missing
preflight() {
  if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}✘ Docker is not running.${RESET} Start it with: open -a Docker"
    exit 1
  fi
  if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}✘ Missing .env file.${RESET} Create it with: cp .env.example .env"
    echo -e "  Then replace every change-me value (see comments in .env.example)."
    exit 1
  fi
}

# Every stack joins sage-network; create it on a fresh machine
ensure_network() {
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo -e "${CYAN}▶ Creating network: ${BOLD}$NETWORK_NAME${RESET}"
    if ! docker network create "$NETWORK_NAME" >/dev/null; then
      echo -e "${RED}✘ Could not create network $NETWORK_NAME${RESET}"
      exit 1
    fi
  fi
}

stack_up() {
  local name=$1
  echo -e "${CYAN}▶ Starting stack: ${BOLD}$name${RESET}"
  if compose "$name" up -d; then
    echo -e "${GREEN}✔ $name up${RESET}\n"
  else
    echo -e "${RED}✘ $name failed to start${RESET}\n"
    return 1
  fi
}

stack_down() {
  local name=$1
  echo -e "${YELLOW}▶ Stopping stack: ${BOLD}$name${RESET}"
  if compose "$name" down; then
    echo -e "${GREEN}✔ $name down${RESET}\n"
  else
    echo -e "${RED}✘ $name failed to stop${RESET}\n"
    return 1
  fi
}

stack_status() {
  local name=$1
  echo -e "${BOLD}── $name ──────────────────────────────────${RESET}"
  compose "$name" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
  echo ""
}

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_up() {
  print_header
  preflight
  ensure_network
  echo -e "${BOLD}Starting all SAGE stacks...${RESET}\n"
  local failed=""
  for name in $STACK_NAMES; do
    stack_up "$name" || failed="$failed $name"
  done
  if [ -n "$failed" ]; then
    echo -e "${RED}${BOLD}✘ Failed stacks:${failed}${RESET}"
    exit 1
  fi
  echo -e "${GREEN}${BOLD}✔ All stacks started.${RESET}"
  cmd_status
}

cmd_down() {
  print_header
  preflight
  echo -e "${BOLD}Stopping all SAGE stacks...${RESET}\n"
  local failed=""
  for name in $STACK_NAMES; do
    stack_down "$name" || failed="$failed $name"
  done
  if [ -n "$failed" ]; then
    echo -e "${RED}${BOLD}✘ Failed stacks:${failed}${RESET}"
    exit 1
  fi
  echo -e "${GREEN}${BOLD}✔ All stacks stopped.${RESET}\n"
}

cmd_status() {
  print_header
  preflight
  echo -e "${BOLD}Stack Status:${RESET}\n"
  for name in $STACK_NAMES; do
    stack_status "$name"
  done
}

cmd_logs() {
  local target=$1
  local service=$2
  if [ -z "$target" ] || [ -z "$(stack_path "$target")" ]; then
    echo -e "${RED}Usage: ./sage.sh logs <stack_name> [service_name]${RESET}"
    echo -e "Available stacks: $STACK_NAMES"
    exit 1
  fi
  preflight
  if [ -z "$service" ]; then
    compose "$target" logs --tail 50 -f
  else
    compose "$target" logs --tail 50 -f "$service"
  fi
}

cmd_help() {
  print_header
  echo -e "${BOLD}Usage:${RESET}"
  echo -e "  ./sage.sh up                       Start all stacks"
  echo -e "  ./sage.sh down                     Stop all stacks"
  echo -e "  ./sage.sh status                   Show status of all stacks"
  echo -e "  ./sage.sh logs <stack> [service]   Tail logs for a stack or service"
  echo -e ""
  echo -e "${BOLD}Available stacks:${RESET}"
  for name in $STACK_NAMES; do
    echo -e "  ${CYAN}$name${RESET} → $(stack_path "$name")"
  done
  echo ""
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
case "${1:-help}" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  logs)   cmd_logs "$2" "$3" ;;
  *)      cmd_help ;;
esac