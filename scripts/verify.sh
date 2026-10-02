#!/bin/bash
# SAGE platform verification
# Checks that the running platform is healthy, observable and locked down, using the
# same tests performed by hand in Step 0. Read-only: it changes nothing.
# Usage: ./scripts/verify.sh   (after ./sage.sh up && ./scripts/init-platform.sh)
# Exit code: 0 if every check passes, 1 if any check fails.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PROM="http://localhost:9090"
STACKS="platform/portainer platform/monitoring platform/redpanda infrastructure"
TOPICS="sage.events sage.alerts sage.actions"
BUCKETS="sage-artifacts sage-datasets sage-archives"
LAN_PORTS="3000 9443"   # ADR-003: only services with their own login

PASSED=0; FAILED=0
pass()    { echo -e "\033[0;32m  ✔ $1\033[0m"; PASSED=$((PASSED + 1)); }
fail()    { echo -e "\033[0;31m  ✘ $1\033[0m"; FAILED=$((FAILED + 1)); }
section() { echo -e "\n\033[1m$1\033[0m"; }

# First value of a Prometheus instant query ("" if there is no result)
prom() {
  curl -sG "$PROM/api/v1/query" --data-urlencode "query=$1" 2>/dev/null \
    | grep -oE '"value":\[[^,]*,"[^"]*"' | head -1 | sed 's/.*,"//; s/"$//'
}

# ── Basics ────────────────────────────────────────────────────────────────────
section "Basics"
if docker info >/dev/null 2>&1; then pass "Docker is running"; else fail "Docker is not running (open -a Docker)"; exit 1; fi
if [ -f .env ]; then pass ".env present"; else fail ".env missing (cp .env.example .env)"; fi

# ── Containers ────────────────────────────────────────────────────────────────
section "Containers"
for s in $STACKS; do
  want=$(docker compose --env-file .env -f "$s/docker-compose.yml" config --services 2>/dev/null | wc -l | tr -d ' ')
  have=$(docker compose --env-file .env -f "$s/docker-compose.yml" ps --status running -q 2>/dev/null | wc -l | tr -d ' ')
  if [ "$want" -gt 0 ] && [ "$want" = "$have" ]; then pass "$s: $have/$want running"; else fail "$s: $have/$want running"; fi
done
bad=$(docker ps --filter health=unhealthy --filter health=starting --format '{{.Names}}' | tr '\n' ' ')
if [ -z "$bad" ]; then pass "no unhealthy containers"; else fail "unhealthy or still starting: $bad"; fi

# ── Observability ─────────────────────────────────────────────────────────────
section "Observability"
targets=$(curl -s "$PROM/api/v1/targets")
total=$(echo "$targets" | grep -oE '"health":"[^"]*"' | wc -l | tr -d ' ')
up=$(echo "$targets" | grep -oE '"health":"up"' | wc -l | tr -d ' ')
if [ "$total" -gt 0 ] && [ "$up" = "$total" ]; then pass "Prometheus targets: $up/$total up"; else fail "Prometheus targets: $up/$total up"; fi
if [ "$(prom 'pg_up')" = "1" ]; then pass "postgres-exporter can log in (pg_up=1)"; else fail "pg_up is not 1"; fi
if [ "$(prom 'redis_up')" = "1" ]; then pass "redis-exporter can log in (redis_up=1)"; else fail "redis_up is not 1"; fi
firing=$(curl -sG "$PROM/api/v1/query" --data-urlencode 'query=count by (alertname, name, job) (ALERTS{alertstate="firing"})' \
  | grep -oE '"metric":\{[^}]*\}' | sed 's/"metric":{//; s/}//; s/"//g' | tr '\n' ' ')
if [ -z "$firing" ]; then pass "no alerts firing"; else fail "alerts firing: $firing"; fi
limits=$(prom 'count(max by (name) (container_spec_memory_limit_bytes{container_label_com_docker_compose_project!=""}) > 0)')
running=$(docker ps --filter label=com.docker.compose.project -q | wc -l | tr -d ' ')
if [ "${limits:-0}" = "$running" ]; then pass "memory limit on every container (${limits}/${running})"; else fail "memory limits on ${limits:-0}/${running} containers"; fi
grafana=$(set -a; . ./.env; set +a
  curl -s -u "$GRAFANA_ADMIN_USER:$GRAFANA_ADMIN_PASSWORD" http://localhost:3000/api/datasources | grep -o '"readOnly":true' | wc -l | tr -d ' ')
if [ "$grafana" = "3" ]; then pass "Grafana: 3 datasources provisioned from git"; else fail "Grafana: $grafana/3 datasources provisioned"; fi
promimg=$(grep -oE 'prom/prometheus:[^[:space:]]+' platform/monitoring/docker-compose.yml)
if docker run --rm -v "$REPO_ROOT/platform/monitoring:/w:ro" --entrypoint promtool "$promimg" \
     test rules /w/tests/alert-rules.test.yml >/dev/null 2>&1; then
  pass "alert rule unit tests pass ($promimg)"
else
  fail "alert rule unit tests fail (run promtool test rules for details)"
fi

# ── Security ──────────────────────────────────────────────────────────────────
section "Security"
if docker exec sage-redis env -u REDISCLI_AUTH redis-cli ping 2>/dev/null | grep -q NOAUTH; then
  pass "Redis rejects anonymous clients"; else fail "Redis answers anonymous clients"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8333/)
if [ "$code" = "403" ]; then pass "S3 rejects anonymous requests (HTTP 403)"; else fail "S3 anonymous request returned HTTP $code"; fi
lan=$(docker ps --format '{{.Ports}}' | tr ',' '\n' | grep -oE '0\.0\.0\.0:[0-9]+' | cut -d: -f2 | sort -un | tr '\n' ' ' | sed 's/ $//')
if [ "$lan" = "$LAN_PORTS" ]; then pass "only login-protected ports on the LAN ($lan)"; else fail "LAN ports: '$lan' (expected '$LAN_PORTS')"; fi
patterns=$( { grep -E '_PASSWORD=|S3_.*_KEY=' .env 2>/dev/null | cut -d= -f2
              cat platform/monitoring/alertmanager/secrets/slack_webhook_url 2>/dev/null; } | grep -v '^$')
if [ -z "$patterns" ]; then
  fail "no secret values found to check against"
elif git grep -q -F -f <(echo "$patterns"); then
  fail "a secret value appears in a tracked file (git grep for details)"
else
  pass "no secret values in tracked files"
fi

# ── Data layer ────────────────────────────────────────────────────────────────
section "Data layer"
health=$(docker exec redpanda rpk cluster health 2>&1)
if echo "$health" | grep -qE 'Healthy:.+true'; then pass "Redpanda cluster healthy"; else fail "Redpanda cluster not healthy"; fi
if echo "$health" | grep -q Enterprise; then fail "Redpanda Enterprise features enabled (run init-platform.sh)"; else pass "Redpanda: community features only"; fi
topics=$(docker exec redpanda rpk topic list 2>/dev/null)
for t in $TOPICS; do
  if echo "$topics" | grep -qE "^$t[[:space:]]"; then pass "topic $t"; else fail "topic $t missing (run init-platform.sh)"; fi
done
buckets=$(echo "s3.bucket.list" | docker exec -i sage-seaweedfs weed shell 2>/dev/null)
for b in $BUCKETS; do
  if echo "$buckets" | grep -qE "(^|[[:space:]])$b([[:space:]]|$)"; then pass "bucket $b"; else fail "bucket $b missing (run init-platform.sh)"; fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo
if [ "$FAILED" -eq 0 ]; then
  echo -e "\033[1;32m✔ All $PASSED checks passed.\033[0m"; exit 0
else
  echo -e "\033[1;31m✘ $FAILED of $((PASSED + FAILED)) checks failed.\033[0m"; exit 1
fi
