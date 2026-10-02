#!/bin/bash
# SAGE platform initialisation
# Creates what lives INSIDE volumes (Redpanda topics + settings, object-storage buckets),
# so a fresh clone ends up identical to the original.
# Idempotent: safe to run any number of times. Run after: ./sage.sh up
set -euo pipefail

TOPICS="sage.events sage.alerts sage.actions"
BUCKETS="sage-artifacts sage-datasets sage-archives"

step() { echo -e "\033[0;36m▶ $1\033[0m"; }
ok()   { echo -e "\033[0;32m  ✔ $1\033[0m"; }
fail() { echo -e "\033[0;31m✘ $1\033[0m"; exit 1; }

# Wait up to ~60s for a container's healthcheck to report healthy
wait_healthy() {
  local name=$1
  local tries=30
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null)" = "healthy" ]; do
    tries=$((tries - 1))
    [ "$tries" -le 0 ] && fail "$name is not healthy. Is the stack up? (./sage.sh up)"
    sleep 2
  done
}

# Run one command in SeaweedFS's admin shell (talks to the master; no S3 keys needed)
weed_shell() { echo "$1" | docker exec -i sage-seaweedfs weed shell 2>/dev/null; }

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

# ── Object storage (SeaweedFS, ADR-007) ───────────────────────────────────────
step "SeaweedFS: waiting for server"
wait_healthy sage-seaweedfs

step "SeaweedFS: buckets"
existing=$(weed_shell "s3.bucket.list")
for b in $BUCKETS; do
  if echo "$existing" | grep -qE "(^|[[:space:]])$b([[:space:]]|$)"; then
    ok "$b (exists)"
  else
    weed_shell "s3.bucket.create -name $b -owner sage" >/dev/null
    ok "$b (created)"
  fi
done

# weed shell does not always signal failure in its exit code: verify the outcome instead
final=$(weed_shell "s3.bucket.list")
for b in $BUCKETS; do
  echo "$final" | grep -qE "(^|[[:space:]])$b([[:space:]]|$)" || fail "bucket $b is missing after create"
done
ok "all buckets verified"

echo -e "\033[0;32m✔ Platform initialised.\033[0m"
