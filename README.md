# SAGE — Self-hosted Autonomous General-purpose Enterprise

An open-source AI Operations Platform built entirely on consumer hardware.

## What is SAGE?

SAGE monitors, operates, and continuously improves AI/ML systems and the infrastructure they run on. It detects model drift, diagnoses root causes autonomously, proposes remediations, and routes them through human approval before acting.

**In one sentence:** SAGE is an autonomous AI operations team — watching, reasoning, acting, and explaining itself — built entirely on open source running on consumer hardware.

## Architecture

SAGE is built in three layers:

- **Layer 1 — Platform Foundation:** Identity, secrets, observability, event bus, databases
- **Layer 2 — AI/ML Plane:** Model serving, RAG pipelines, agent orchestration
- **Layer 3 — Agentic Application:** Multi-agent system with human-in-the-loop control

## Hardware

SAGE runs on a **single Mac Mini M4 with 48 GB RAM** (see [ADR-001](docs/architecture-decisions.md)).

Note: on macOS, containers run inside Docker Desktop's Linux VM and share **only the memory assigned to that VM** (about 8 GB by default), not the Mac's full 48 GB. Adjust it in Docker Desktop → Settings → Resources.

## Status

🚧 **Phase 1 — Platform Foundation.** 16 services running: metrics, logs, traces, alerting, event bus, and data layer. Next: Qdrant + Gitea.

## Quick start

**Prerequisites:** Docker Desktop (set to start at login), git, openssl.

```bash
git clone https://github.com/ivaturia/sage-homelab.git
cd sage-homelab

# 1. Credentials: copy the template and generate a unique password for each service
cp .env.example .env
chmod 600 .env
for var in GRAFANA_ADMIN_PASSWORD POSTGRES_PASSWORD POSTGRES_SAGE_PASSWORD REDIS_PASSWORD MINIO_ROOT_PASSWORD; do
  sed -i '' "s/^${var}=change-me$/${var}=$(openssl rand -hex 20)/" .env   # macOS sed; on Linux use: sed -i
done

# 2. Alert delivery: save a Slack incoming-webhook URL (folder is gitignored)
mkdir -p platform/monitoring/alertmanager/secrets
echo 'https://hooks.slack.com/services/...' > platform/monitoring/alertmanager/secrets/slack_webhook_url

# 3. Start everything, then create topics, buckets, and Redpanda settings
./sage.sh up
./scripts/init-platform.sh
```

Always start stacks through `./sage.sh`: it supplies the shared `.env` to every stack.

## Services

| Service | Address | Reachable from |
|---|---|---|
| Grafana | `http://<mac-mini>:3000` | LAN (login) |
| Portainer | `https://<mac-mini>:9443` | LAN (login, self-signed cert) |
| MinIO Console | `http://<mac-mini>:9002` | LAN (login) |
| Prometheus | `http://localhost:9090` | Mac Mini only |
| Alertmanager | `http://localhost:9093` | Mac Mini only |
| Jaeger UI | `http://localhost:16686` | Mac Mini only |
| Redpanda Console | `http://localhost:8090` | Mac Mini only |
| cAdvisor | `http://localhost:8080` | Mac Mini only |
| PostgreSQL / Redis | `localhost:5432` / `localhost:6379` | Mac Mini only |
| OTLP (traces in) | `localhost:4317` (gRPC) / `localhost:4318` (HTTP) | Mac Mini only |

**Rule:** only services with a login are reachable on the network. Everything else is bound to `127.0.0.1` until Traefik and Keycloak arrive. For remote access, use an SSH tunnel, e.g. `ssh -L 9090:localhost:9090 <user>@<mac-mini>`.

## Repository structure

```
sage-homelab/
├── sage.sh                  # up / down / status / logs for all stacks
├── .env.example             # credential template (real .env is gitignored)
├── docs/                    # Architecture decision records (ADRs)
├── infrastructure/          # PostgreSQL, Redis, MinIO + exporters
├── platform/
│   ├── monitoring/          # Prometheus, Grafana, Loki, Promtail, Jaeger, OTel Collector, Alertmanager, cAdvisor
│   ├── redpanda/            # Event bus + console
│   └── portainer/           # Container management UI
├── scripts/                 # init-platform.sh and other utilities
├── ai-plane/                # Layer 2 (coming)
├── agents/                  # Layer 3 (coming)
├── synthetic-data/          # NeuralOps-Core load generator (coming)
└── control-plane-ui/        # Next.js dashboard (coming)
```

## License

MIT
