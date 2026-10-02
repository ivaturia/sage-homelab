# Redpanda stack

SAGE's event bus (Layer 1): a Kafka-compatible broker that lets components exchange messages without calling each other directly, plus a web console. Start it with `./sage.sh up` from the repo root, then run `./scripts/init-platform.sh` to create topics and apply cluster settings.

## Services

| Service | Image | Address | Memory limit | Role |
|---|---|---|---|---|
| redpanda | `redpandadata/redpanda:v26.1.9` | Kafka `localhost:19092` (see below) | 1.5 GB | The broker |
| redpanda-console | `redpandadata/console@sha256:72bd99bd…` | `localhost:8090` | 256 MB | Web UI for topics, messages, consumer groups |

Nothing here has authentication yet, so every port is Mac-only (ADR-003).

## Addresses: internal vs external

| Interface | From other containers (`sage-network`) | From the Mac |
|---|---|---|
| Kafka API | `redpanda:9092` | `localhost:19092` |
| Admin API (and metrics at `/public_metrics`) | `redpanda:9644` | `localhost:19644` |
| HTTP Proxy | `redpanda:8082` | `localhost:18082` |
| Schema Registry | `redpanda:8081` | `localhost:18081` |

A Kafka client connects once, then is *told* which address to use from then on (the **advertised** address). Each listener advertises the address that works from where its clients sit: `redpanda:9092` for containers, `localhost:19092` for the Mac. If a client uses the wrong one, the first connection succeeds and everything after it fails.

## Topics

| Topic | Partitions / replicas | Intended use (planned) |
|---|---|---|
| `sage.events` | 3 / 1 | Platform and NeuralOps-Core events (load generator, Step 12) |
| `sage.alerts` | 3 / 1 | Alerts handed to the agents (Phase 3), alongside the human Slack route (ADR-004) |
| `sage.actions` | 3 / 1 | Proposed and approved agent actions: the audit trail |

Three partitions allow up to three consumers to share a topic's work. A single broker can only hold one replica.

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Broker and console, listeners, ports, health check, memory limits |

Topics and cluster settings live inside the data volume, so they are recreated by `scripts/init-platform.sh`, not by this folder (ADR-005).

## Why it is configured this way

- **`--mode dev-container`** applies single-node development settings (for example, relaxed disk syncing). Fine for a homelab; not a production profile.
- **`--smp 2`** gives the broker two CPU cores; **`--memory 1G`** is its memory budget (512M ran out of memory at start-up). The container limit (1.5 GB) sits above it so Redpanda's own memory management acts before the kernel kills the container (ADR-008).
- **The health check** looks for `Healthy: true` in `rpk cluster health`, not just a running process.
- **The console is pinned by digest** (`@sha256:…`) because its image carries no readable version.
- **Enterprise features stay off.** Newer Redpanda versions enable continuous partition and core balancing by default; those require a licence and do nothing useful on one node. `init-platform.sh` sets the community defaults and `verify.sh` checks for any Enterprise warning.

## Common tasks

| Task | How |
|---|---|
| List topics | `docker exec redpanda rpk topic list` |
| Produce a test message | `echo "hello from SAGE" \| docker exec -i redpanda rpk topic produce sage.events` |
| Read one message | `docker exec redpanda rpk topic consume sage.events -n 1` |
| Cluster health | `docker exec redpanda rpk cluster health` |
| Consumer groups | `docker exec redpanda rpk group list` |
| Recreate topics and settings | `./scripts/init-platform.sh` |
| Browse in a UI | `http://localhost:8090` on the Mac |
| Check everything | `./scripts/verify.sh` |

## Known limitations

- **No authentication or encryption.** Anyone who can reach the ports can read and write every topic, which is why they are Mac-only. SASL and TLS come with Vault and Traefik (Steps 9–10).
- **Single broker, one replica.** Losing the volume loses the messages; there is no failover.
- **Retention uses Redpanda's defaults.** Per-topic retention will be set when real producers exist.
