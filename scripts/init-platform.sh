#!/bin/bash
# SAGE platform initialisation
# Creates what lives INSIDE volumes (Redpanda topics + settings, MinIO buckets),
# so a fresh clone ends up identical to the original.
# Idempotent: safe to run any number of times. Run after: ./sage.sh up
set -euo pipefail

TOPICS="sage.events sage.alerts sage.actions"
BUCKETS="sage-artifacts sage-datasets sage-archives"

step() { echo -e "\033[0;36m▶ $1\033[0m"; }
ok()   { echo -e "\033[0;32m  ✔ $1\033[0m"; }

# Wait up to ~60s for a container's healthcheck to report healthy
wait_healthy() {
  local name=$1
  local tries=30
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null)" = "healthy" ]; do
    tries=$((tries - 1))
    if [ "$tries" -le 0 ]; then
      echo -e "\033[0;31m✘ $name is not healthy. Is the stack up? (./sage.sh up)\033[0m"
      exit 1
    fi
    sleep 2
  done
}

# ── Redpanda ──────────────────────────────────────────────────────────────────
step "Redpanda: waiting for broker"
wait_healthy redpanda

step "Redpanda: cluster settings (community defaults; continuous balancing is an Enterprise feature)"
docker exec redpanda rpk cluster config set partition_autobalancing_mode node_add >/dev/null
docker exec redpanda rpk cluster config set core_balancing_continuous false >/dev/null
ok "partition_autobalancing_mode=node_add, core_balancing_continuous=false"

step "Redpanda: topics"
for t in $TOPICS; do
  if docker exec redpanda rpk topic describe "$t" >/dev/null 2>&1; then
    ok "$t (exists)"
  else
    docker exec redpanda rpk topic create "$t" --partitions 3 --replicas 1 >/dev/null
    ok "$t (created)"
  fi
done

# ── MinIO ─────────────────────────────────────────────────────────────────────
step "MinIO: waiting for server"
wait_healthy sage-minio

step "MinIO: buckets"
# Single quotes: the credentials are expanded INSIDE the container, from its own environment
docker exec sage-minio sh -c 'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null'
for b in $BUCKETS; do
  docker exec sage-minio mc mb --ignore-existing "local/$b" >/dev/null
  ok "$b"
done

echo -e "\033[0;32m✔ Platform initialised.\033[0m"