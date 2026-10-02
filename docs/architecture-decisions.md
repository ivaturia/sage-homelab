# Architecture Decisions

## ADR-001: Single Node Deployment on Mac Mini M4

**Date:** 2026-05-08

**Decision:** SAGE runs entirely on a single Mac Mini M4 (48GB RAM).

**Reasoning:**
- 48GB unified memory is sufficient to run all platform services, AI models up to 32B parameters, and all agents simultaneously
- Simplifies networking, deployment, and reproducibility
- Makes the project accessible to anyone with a single powerful machine
- The Mac Mini M4 is purpose-built for sustained workloads — fanless, efficient, reliable

**What this means:**
- All Docker services run on 192.168.1.10
- Model serving (Ollama) runs on the same node
- No distributed networking complexity in Phase 1-3
- Worker nodes can be added later without architectural changes

**Trade-offs accepted:**
- No high availability — if the Mac Mini goes down, SAGE goes down
- This is a home lab, not a production system — acceptable

## ADR-001 addendum: Docker Desktop memory (2026-10-01)

On macOS, containers run inside Docker Desktop's Linux VM and share only that VM's memory: about 8 GB by default, as reported by cAdvisor. The "48 GB is sufficient" reasoning above applies only once the VM's allocation is raised, or to workloads running natively on macOS (e.g. Ollama with Metal acceleration). To be revisited before Phase 2.

## ADR-002: Credentials in a gitignored .env until Vault

**Date:** 2026-10-01
**Status:** Accepted (interim; superseded by Vault in Step 9)

**Context:** Passwords for Grafana, PostgreSQL, and MinIO were committed in compose files and pushed to the public repo.

**Decision:** All credentials live in a root `.env` (gitignored, mode 600). `.env.example` documents every variable. `sage.sh` passes `--env-file` to every stack. All exposed passwords were rotated; each value is unique, generated with `openssl rand -hex 20`.

**Trade-offs accepted:**
- Old passwords remain in git history; they are dead, so history was not rewritten.
- Stacks must be started via `sage.sh` (or with `--env-file` passed explicitly).
- PostgreSQL and Grafana read their env vars only on first start; later rotation needs `ALTER USER` and `grafana cli admin reset-admin-password`.

## ADR-003: Network exposure policy

**Date:** 2026-10-01
**Status:** Accepted (until Traefik + Keycloak, Steps 10–11)

**Decision:** Only services with their own login are published on the LAN: Grafana (3000), Portainer HTTPS (9443), MinIO Console (9002). Everything else binds to `127.0.0.1` or has no host port at all. Containers talk to each other over `sage-network`.

**Reasoning:** Docker publishes ports on all interfaces by default. Prometheus (lifecycle API), Alertmanager (silences), Redpanda (admin, topics), and Redis were reachable by any device on the network with no authentication.

**Trade-offs accepted:** Remote access to local-only services needs an SSH tunnel.

## ADR-004: Human alert route bypasses SAGE

**Date:** 2026-10-01
**Status:** Accepted

**Context:** In Phase 3, alerts will reach agents via Redpanda. If Redpanda or the agents fail, those alerts would never arrive.

**Decision:** Alertmanager sends every alert directly to Slack (#sage-alerts). The future Supervisor route is added alongside it, never instead of it. The webhook URL lives in a gitignored file read via `api_url_file`, because Alertmanager does not expand environment variables in its config.

## ADR-005: Volume-held state is reproduced from code

**Date:** 2026-10-01
**Status:** Accepted

**Decision:** Anything created by hand inside a volume must also exist as code: Grafana datasources and dashboards via provisioning (original UIDs preserved, UI edits locked); Redpanda topics, Redpanda cluster settings, and MinIO buckets via the idempotent `scripts/init-platform.sh`; the PostgreSQL `sage` user via `postgres-init.sh`.

**Reasoning:** "Clone and run" was not true: a fresh clone produced an empty Grafana, no topics, and no buckets.

## ADR-006: Replace Promtail with Grafana Alloy

**Date:** 2026-10-01
**Status:** Proposed

**Context:** Promtail reached end of life on 2026-03-02 and receives no fixes. Grafana Alloy is its official successor and can convert Promtail configs (`alloy convert --source-format=promtail`).

**Open question:** Alloy also speaks OTLP natively, so it could replace the OpenTelemetry Collector as well, giving one collection agent instead of two, at the cost of putting all telemetry collection in one component.

**Next step:** Decide scope, migrate, and verify labels in Loki before Phase 2.

## ADR-007: Replace MinIO with SeaweedFS for object storage

**Date:** 2026-10-02
**Status:** Accepted (supersedes the MinIO parts of ADR-003 and ADR-005)

**Context:** MinIO stopped publishing community images and binaries (October 2025), entered maintenance mode (December 2025) and archived its repository (2026). On 2026-10-02, `docker manifest inspect` confirmed that both `minio/minio:latest` and the release we ran are no longer available on Docker Hub: a fresh clone could not start the infrastructure stack.

**Decision:** SeaweedFS (`chrislusf/seaweedfs:4.48`, Apache-2.0) in single-process mode (`weed server -s3`) is SAGE's S3-compatible object store.

**Reasoning:**
- Apache-2.0; actively maintained (frequent releases, signed images); adopted by Kubeflow Pipelines as its default object store after MinIO's retreat.
- Covers what SAGE needs: buckets, upload/download, multipart. Verified with 20 MB round trips (checksums matched) in all three buckets.
- Native arm64 image; Prometheus metrics on :9327.
- Considered: Garage (lightweight, AGPL-3.0, fewer S3 features), RustFS (closest to MinIO, still alpha), pgsty/minio (community fork, single maintainer).

**Configuration notes:**
- `-ip.bind=0.0.0.0` so in-container health checks can reach localhost.
- `-master.volumeSizeLimitMB=1024` and `-volume.max=0` avoid "no free volumes" on a small node (defaults: 30 GB volumes, 8 slots).
- S3 keys come from `.env` (`S3_ACCESS_KEY`, `S3_SECRET_KEY`); the S3 identity file is generated at container start because SeaweedFS does not expand env vars.
- S3 API on `127.0.0.1:8333`; master and filer UIs internal only. Buckets are created by `init-platform.sh` via `weed shell`.

**Exit plan:** SAGE talks to object storage only through the standard S3 API (endpoint and keys in config, nothing SeaweedFS-specific). Replacing SeaweedFS means a config change and a data copy.

**Trade-offs accepted:** SeaweedFS development is led largely by its creator. There is no LAN web console (MinIO Console is replaced by S3 tools).
