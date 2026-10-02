# Infrastructure stack

SAGE's data layer (Layer 1): a relational database, a cache, S3-compatible object storage, and exporters that let Prometheus watch them. Start it with `./sage.sh up` from the repo root, then run `./scripts/init-platform.sh` to create the buckets.

## Services

| Service | Image | Address | Memory limit | Role |
|---|---|---|---|---|
| postgres | `postgres:16.14-alpine` | `localhost:5432` | 512 MB | Relational data; database `sage`, owned by user `sage` |
| redis | `redis:7.4.9-alpine` | `localhost:6379` (password) | 768 MB | Cache and agent state: 512 MB max, LRU eviction, append-only persistence |
| seaweedfs | `chrislusf/seaweedfs:4.48` | S3 API `localhost:8333` | 1 GB | S3-compatible object storage (ADR-007) |
| postgres-exporter | `prometheuscommunity/postgres-exporter:v0.19.1` | internal `:9187` | 128 MB | PostgreSQL metrics for Prometheus |
| redis-exporter | `oliver006/redis_exporter:v1.84.0` | internal `:9121` | 128 MB | Redis metrics for Prometheus |

All ports are Mac-only or internal (ADR-003). Other containers on `sage-network` use the service names: `postgres:5432`, `redis:6379`, `http://seaweedfs:8333`.

## Credentials

All come from the root `.env` (template: `.env.example`), never from this folder.

| Variable | Used for |
|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | Superuser (`master`): administration only |
| `POSTGRES_SAGE_USER` / `POSTGRES_SAGE_PASSWORD` | Application user `sage`, owner of the `sage` database |
| `REDIS_PASSWORD` | Redis authentication |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | S3 access to SeaweedFS |

## Buckets

`sage-artifacts`, `sage-datasets`, `sage-archives`. Created (idempotently) by `scripts/init-platform.sh`.

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | The five services, ports, health checks, memory limits |
| `postgres-init.sh` | Creates the `sage` user and database on first start |

## Why it is configured this way

- **`postgres-init.sh` runs only once**, when the data volume is empty. It reads credentials from the environment and passes the password to SQL as a psql variable (`:'sage_password'`), which quotes it safely. The `sage` user owns its database, which (since PostgreSQL 15) also gives it the `public` schema.
- **PostgreSQL ignores a changed `POSTGRES_PASSWORD`** after first start: the password lives inside the database. Rotate it with `ALTER USER`.
- **`pg_isready` never logs in**, so a healthy PostgreSQL can still reject a wrong password. The real login check is the `pg_up` metric (1 = the exporter logged in).
- **Redis requires a password** (`--requirepass`). The health check uses `REDISCLI_AUTH` and looks for `PONG`, because an unauthenticated `redis-cli ping` prints `NOAUTH` but still exits successfully.
- **Exporters have no host ports**; Prometheus reaches them over `sage-network`. postgres-exporter takes its user and password as separate variables, so the password never appears in a URL.
- **SeaweedFS runs as a single process** (`weed server -s3`: master, volume server, filer and S3 gateway).
  - `-ip.bind=0.0.0.0` lets the in-container health check reach `localhost`.
  - `-master.volumeSizeLimitMB=1024` and `-volume.max=0` avoid "no free volumes" on a small node (defaults: 30 GB volumes, 8 slots).
  - The S3 identity file is generated at start-up from `S3_ACCESS_KEY` / `S3_SECRET_KEY`, because SeaweedFS does not expand environment variables. `exec` makes `weed` PID 1 so it shuts down cleanly.
- **Memory limits sit above each service's own setting** (Redis `maxmemory 512mb` → 768 MB limit), so the service's safeguard acts before the kernel kills it (ADR-008).

## Connecting an application to S3 (MLflow, Langfuse, …)

| Setting | Value |
|---|---|
| Endpoint | `http://seaweedfs:8333` (from containers) or `http://localhost:8333` (from the Mac) |
| Access key / secret key | `S3_ACCESS_KEY` / `S3_SECRET_KEY` from `.env` |
| Region | Any (e.g. `us-east-1`); SeaweedFS ignores it, but most clients require one |
| Addressing | **Path-style** (`http://host/bucket/key`), not virtual-hosted (`http://bucket.host/key`) |

## Common tasks

| Task | How |
|---|---|
| Open psql as the app user | `docker exec -it sage-postgres psql -U sage -d sage` (local socket inside the container: no password asked) |
| Rotate a PostgreSQL password | `docker exec sage-postgres psql -U master -d postgres -c "ALTER USER sage WITH PASSWORD '<new>';"`, update `.env`, then `./sage.sh up` |
| Open redis-cli | `docker exec -it sage-redis redis-cli` (authenticates via `REDISCLI_AUTH`) |
| List buckets (admin) | `echo "s3.bucket.list" \| docker exec -i sage-seaweedfs weed shell` |
| List buckets (S3, as an app would) | `docker run --rm --network sage-network -e AWS_DEFAULT_REGION=us-east-1 -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY amazon/aws-cli --endpoint-url http://seaweedfs:8333 s3 ls` (with the keys exported in your shell) |
| Recreate missing buckets | `./scripts/init-platform.sh` |
| Check everything | `./scripts/verify.sh` |

## Known limitations

- **No backups yet.** PostgreSQL and SeaweedFS data live only in Docker volumes on one Mac; `docker compose down -v` or a disk failure would lose them. Backups are needed before MLflow and Langfuse store real data.
- **postgres-exporter logs in as the superuser.** It only needs to read statistics: a dedicated user with the built-in `pg_monitor` role would follow least privilege.
- **SeaweedFS is a single node** with one copy of each object (no replication).
- **One S3 identity** with full rights. Read-only keys for some agents can come later.
