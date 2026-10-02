# Scripts

The three scripts that run SAGE day to day. Used in this order:

~~~
./sage.sh up                  # 1. start every stack
./scripts/init-platform.sh    # 2. create what lives inside volumes
./scripts/verify.sh           # 3. prove it all works
~~~

## `sage.sh` (repo root)

Starts, stops and inspects every stack, always with the shared root `.env`.

| Command | What it does |
|---|---|
| `./sage.sh up` | Creates `sage-network` if missing, starts all four stacks, shows status |
| `./sage.sh down` | Stops and removes containers. **Volumes are kept**, so data survives |
| `./sage.sh status` | Container status and ports for every stack |
| `./sage.sh logs <stack> [service]` | Follows the last 50 log lines |

- Checks first that Docker is running and `.env` exists, and stops with one clear message if not.
- Reports a failed stack with ✘ and exits non-zero, instead of claiming success.
- Never run `docker compose` directly in a stack folder: without `--env-file` the credentials would be blank.
- Written for macOS's bash 3 (no associative arrays).

## `scripts/init-platform.sh`

Creates the things that live **inside volumes**, which no compose file can describe (ADR-005):

- Redpanda cluster settings (community defaults; Enterprise balancing off)
- Redpanda topics `sage.events`, `sage.alerts`, `sage.actions`
- SeaweedFS buckets `sage-artifacts`, `sage-datasets`, `sage-archives`

**Idempotent**: safe to run any number of times. It waits for each service to be healthy, creates only what is missing, and verifies the buckets afterwards. No credentials pass through it; everything runs inside the containers.

## `scripts/verify.sh`

**Read-only** health and security check: 26 checks in five groups.

| Group | Checks |
|---|---|
| Basics | Docker running, `.env` present |
| Containers | Every stack fully running; nothing unhealthy |
| Observability | All Prometheus targets up; `pg_up` and `redis_up`; no alerts firing; a memory limit on every container; Grafana provisioned from git; alert-rule unit tests pass |
| Security | Redis and S3 reject anonymous access; only ports 3000 and 9443 on the LAN; no secret values in tracked files |
| Data layer | Redpanda healthy with no Enterprise features; all topics and buckets present |

- Prints ✔ or ✘ per check and names the culprit (e.g. `alertname:ContainerDown,name:<container>`).
- Exit code **0** if every check passes, **1** otherwise, so it can gate other commands: `./scripts/verify.sh && git push`.
- Run it at the start of every session and before every push.
