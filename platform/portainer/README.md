# Portainer stack

A web UI for managing SAGE's Docker containers, images, volumes and networks (Layer 1). Start it with `./sage.sh up` from the repo root.

## Service

| Service | Image | Address | Memory limit |
|---|---|---|---|
| portainer | `portainer/portainer-ce:2.39.2` | `https://<mac-mini>:9443` (LAN, login) and `http://localhost:9000` (Mac only) | 256 MB |

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Ports, Docker socket mount, data volume, memory limit |

## Why it is configured this way

- **HTTPS on the LAN, HTTP only on the Mac.** A login over plain HTTP would send the password across the network unencrypted, so port 9000 is bound to `127.0.0.1` (ADR-003).
- **The certificate is self-signed.** Browsers warn the first time; the traffic is still encrypted. Traefik with Vault as the certificate authority replaces it in Step 10.
- **Portainer mounts the Docker socket**, which means full control of Docker: it can start any container and read any volume, including PostgreSQL's data. **Portainer's admin password effectively controls the whole platform. Keep it strong.**
- **Its settings and admin account live in the `portainer_data` volume**, not in git.

## Common tasks

| Task | How |
|---|---|
| Open the UI | `https://<mac-mini>:9443` (accept the certificate warning once) |
| First start on a fresh machine | Create the admin account **straight away**: Portainer locks the setup page after a few minutes. If it does, run `docker restart portainer` and try again. |
| See its logs | `./sage.sh logs portainer` |
| Check everything | `./scripts/verify.sh` from the repo root |

## Known limitations

- **Docker socket access** gives Portainer (and anyone with its admin password) root-equivalent control of the platform.
- **No single sign-on yet**: Portainer has its own login until Keycloak (Step 11).
- **Configuration is not reproducible from git**: the admin account and settings exist only in the volume.
