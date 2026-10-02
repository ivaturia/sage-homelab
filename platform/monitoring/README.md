# Monitoring stack

Metrics, logs, traces and alerting for SAGE (Layer 1). Start it with `./sage.sh up` from the repo root, never with `docker compose` directly (the shared `.env` would be missing).

## Services

| Service | Image | Address | Memory limit | Role |
|---|---|---|---|---|
| prometheus | `prom/prometheus:v3.11.3` | `localhost:9090` | 1 GB | Scrapes and stores metrics; evaluates alert rules |
| grafana | `grafana/grafana:13.0.1` | `<mac-mini>:3000` (LAN, login) | 768 MB | Dashboards |
| cadvisor | `gcr.io/cadvisor/cadvisor:v0.55.1` | `localhost:8080` | 512 MB | Per-container CPU and memory |
| loki | `grafana/loki:3.7.1` | `localhost:3100` | 512 MB | Log storage |
| promtail | `grafana/promtail:3.6.8` | internal | 256 MB | Ships Docker logs to Loki (end of life, ADR-006) |
| jaeger | `jaegertracing/all-in-one:1.76.0` | `localhost:16686` (UI) | 512 MB | Trace storage and UI (v1, end of life) |
| otel-collector | `otel/opentelemetry-collector-contrib:0.151.0` | `localhost:4317` gRPC, `:4318` HTTP | 768 MB | The single entry point for traces (OTLP) |
| alertmanager | `prom/alertmanager:v0.32.1` | `localhost:9093` | 128 MB | Routes alerts to Slack |

Only Grafana is reachable from the LAN; everything else is Mac-only (ADR-003). For remote access use an SSH tunnel, e.g. `ssh -L 9090:localhost:9090 <user>@<mac-mini>`.

## How data flows

~~~
containers ──► cAdvisor ─┐
exporters, services ─────┼─► Prometheus ──► alerts.yml ──► Alertmanager ──► Slack #sage-alerts
                         └─► Grafana (dashboards)
Docker logs ──► Promtail ──► Loki ──► Grafana
apps (OTLP) ──► OTel Collector :4317/:4318 ──► Jaeger ──► Grafana
~~~

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | The eight services, ports, mounts, memory limits |
| `prometheus.yml` | Scrape targets (12) and the alert rules file |
| `alerts.yml` | Five alert rules |
| `tests/alert-rules.test.yml` | Unit tests for the alert rules (`promtool test rules`) |
| `alertmanager/alertmanager.yml` | Routing, grouping, Slack receiver |
| `alertmanager/secrets/slack_webhook_url` | Slack webhook URL. **Gitignored**; create it locally |
| `loki/loki-config.yml` | Storage, 30-day retention, ruler → Alertmanager |
| `promtail/promtail-config.yml` | Docker log discovery and labels |
| `otelcollector/otel-collector-config.yml` | OTLP in → batch → Jaeger; own metrics on :8888 |
| `grafana/provisioning/` | Datasources and dashboard provider, loaded at start |
| `grafana/dashboards/*.json` | Dashboards, provisioned from git |

## Why it is configured this way

- **cAdvisor mounts `/var/run/docker.sock` and `/run/containerd/containerd.sock` directly.** On Docker Desktop, mounting the whole `/var/run` gives the *Mac's* folder, not the VM's, and containers then have no names.
- **ContainerDown** combines "last seen over 60 s ago" with "seen in the last hour, absent now", because cAdvisor timestamps its own samples and a stopped container stays visible for Prometheus's 5-minute lookback. Grouping by `name` means a recreate never looks like a death.
- **ContainerRestarting** uses `resets()` on the CPU counter. `container_start_time_seconds` is the *creation* time and never changes on restart.
- **Memory rules** only divide by limits greater than zero, and use `working_set` (what the kernel considers before killing a container).
- **Alertmanager** reads the Slack URL from a file (`api_url_file`) because it does not expand environment variables. The human route bypasses SAGE so alerts still arrive when SAGE itself is broken (ADR-004).
- **Grafana** datasources keep their original UIDs (dashboards reference UIDs) and are read-only; dashboards cannot be edited in the UI. Edit the JSON in git (ADR-005). The empty `plugins/` and `alerting/` folders stop Grafana logging errors.
- **The OTel Collector's** `memory_limiter` (512 MiB) sits below its container limit (768 MB), so the collector sheds load before the kernel kills it.
- **Jaeger** keeps traces in memory, capped at `MEMORY_MAX_TRACES=20000`; traces are lost on restart.

## Common tasks

| Task | How |
|---|---|
| Apply a change to `prometheus.yml` or `alerts.yml` | `docker restart prometheus`, then check what the **container** sees: `docker exec prometheus cat /etc/prometheus/prometheus.yml`. A plain `/-/reload` can read a stale or truncated copy of a single-file mount on Docker Desktop. |
| Test the alert rules | From the repo root: `docker run --rm -v "$PWD/platform/monitoring:/w:ro" --entrypoint promtool prom/prometheus:v3.11.3 test rules /w/tests/alert-rules.test.yml` |
| Change a dashboard | Edit the JSON in `grafana/dashboards/`; Grafana reloads it within about 10 seconds |
| Send a test alert to Slack | `docker exec alertmanager amtool alert add TestAlert severity=warning --annotation=summary="test" --alertmanager.url=http://localhost:9093` |
| Change the Slack webhook | Replace the file in `alertmanager/secrets/`, then `docker restart alertmanager` |
| Reset the Grafana admin password | `docker exec grafana grafana cli admin reset-admin-password <new>` (the env var applies only on first start) |
| Check everything | `./scripts/verify.sh` from the repo root |

## Known limitations

- **Promtail** reached end of life on 2026-03-02; migration to Grafana Alloy is proposed (ADR-006).
- **Jaeger v1** reached end of life on 2025-12-31; migrating to Jaeger v2 changes ports (the 14269 admin port goes away). To be decided together with ADR-006.
- **Traces** live only in Jaeger's memory and are lost when it restarts.
