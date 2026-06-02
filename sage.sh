#!/bin/bash

# SAGE Platform Control Script
# Usage: ./sage.sh [up|down|status|logs] [stack_name] [service_name]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Registered stacks (name:path pairs) ───────────────────────────────────────
STACK_NAMES="portainer monitoring redpanda"
stack_path() {
  case $1 in
    portainer)  echo "platform/portainer" ;;
    monitoring) echo "platform/monitoring" ;;
    redpanda)   echo "platform/redpanda" ;;
    *)          echo "" ;;
  esac
}

# ── Helpers ───────────────────────────────────────────────────────────────────
print_header() {
  echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        SAGE Platform Control         ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}\n"
}

stack_up() {
  local name=$1
  local path="$REPO_ROOT/$(stack_path $name)"
  echo -e "${CYAN}▶ Starting stack: ${BOLD}$name${RESET}"
  docker compose -f "$path/docker-compose.yml" up -d
  echo -e "${GREEN}✔ $name up${RESET}\n"
}

stack_down() {
  local name=$1
  local path="$REPO_ROOT/$(stack_path $name)"
  echo -e "${YELLOW}▶ Stopping stack: ${BOLD}$name${RESET}"
  docker compose -f "$path/docker-compose.yml" down
  echo -e "${GREEN}✔ $name down${RESET}\n"
}

stack_status() {
  local name=$1
  local path="$REPO_ROOT/$(stack_path $name)"
  echo -e "${BOLD}── $name ──────────────────────────────────${RESET}"
  docker compose -f "$path/docker-compose.yml" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
  echo ""
}

stack_logs() {
  local name=$1
  local service=$2
  local path="$REPO_ROOT/$(stack_path $name)"
  if [ -z "$service" ]; then
    docker compose -f "$path/docker-compose.yml" logs --tail 50 -f
  else
    docker compose -f "$path/docker-compose.yml" logs --tail 50 -f "$service"
  fi
}

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_up() {
  print_header
  echo -e "${BOLD}Starting all SAGE stacks...${RESET}\n"
  for name in $STACK_NAMES; do
    stack_up "$name"
  done
  echo -e "${GREEN}${BOLD}✔ All stacks started.${RESET}"
  cmd_status
}

cmd_down() {
  print_header
  echo -e "${BOLD}Stopping all SAGE stacks...${RESET}\n"
  for name in $STACK_NAMES; do
    stack_down "$name"
  done
  echo -e "${GREEN}${BOLD}✔ All stacks stopped.${RESET}\n"
}

cmd_status() {
  print_header
  echo -e "${BOLD}Stack Status:${RESET}\n"
  for name in $STACK_NAMES; do
    stack_status "$name"
  done
}

cmd_logs() {
  local target=$1
  local service=$2
  if [ -z "$target" ]; then
    echo -e "${RED}Usage: ./sage.sh logs <stack_name> [service_name]${RESET}"
    echo -e "Available stacks: $STACK_NAMES"
    exit 1
  fi
  if [ -z "$(stack_path $target)" ]; then
    echo -e "${RED}Unknown stack: $target${RESET}"
    echo -e "Available stacks: $STACK_NAMES"
    exit 1
  fi
  stack_logs "$target" "$service"
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
    echo -e "  ${CYAN}$name${RESET} → $(stack_path $name)"
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
