# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker Compose setup for a self-hosted observability stack: Grafana + PostgreSQL (backend DB) + Prometheus + Loki + Promtail, plus supporting containers (image renderer, blackbox exporter).

## Common commands

All operations go through `make` or `docker-compose` directly:

```bash
make start          # docker-compose up -d
make stop           # docker-compose down
make restart        # docker-compose restart
make psql           # open psql shell in the postgres container (uses .env vars)
make postgres       # open bash shell in the postgres container
make grafana-db     # open psql as grafana_user against the grafana DB
```

`make` reads `.env` for `DB_CONTAINER`, `DATABASE_USER`, `DATABASE_NAME`, `DATABASE_PASSWORD`.

## Architecture

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| `grafana` | grafana/grafana:10.0.10-ubuntu | 3000 | Main dashboard UI |
| `db` (postgres) | postgres:15 | 5432 | Grafana metadata/session store |
| `prometheus` | prom/prometheus:v2.47.0 | 9090 / 9100 | Metrics scraping & storage (1m retention) |
| `loki` | grafana/loki:latest | 3100 | Log aggregation |
| `renderer` | grafana/grafana-image-renderer:3.5.0 | 8081 | Panel image export |
| `blackbox` | bitnami/blackbox-exporter | 9115 | HTTP/TCP endpoint probing |

All services share the external Docker network `grafana` — this network must exist before `make start`:
```bash
docker network create grafana
```

## Configuration files

- `conf/grafana.ini` — Grafana server config (database connection, admin credentials, metrics toggle, storage retention).
- `conf/grafana-env.list` — env vars injected into the Grafana container (`GF_DATABASE_*`). Overrides `grafana.ini` for DB settings.
- `prometheus/prometheus.yml` — scrape jobs. The `node_exporter_local` job target (`ip-host-local:9100`) must be replaced with the actual host IP.
- `loki/loki-config.yaml.yml` — Loki config (note: the compose file mounts it as `loki-config.yml` but the file on disk is `loki-config.yaml.yml` — keep names in sync if renaming).
- `promptail/promtail-local-config.yaml` — Promtail config for shipping Odoo logs; the `clients.url` is commented out and must be set before use.

## Known issues / gotchas

- The postgres DB data volume is commented out in `docker-compose.yml` — data lives in a named volume (`grafana-data`), not on the host filesystem, so `docker-compose down -v` will destroy it.
- Prometheus retention is set to `1m` (one minute) — intentionally short, likely for dev/testing. Change `--storage.tsdb.retention.time` before using in production.
- The `grafana-db` make target connects as `grafana_user` but the actual postgres user is `grafana` — update if the DB user changes.
- Loki's compose `command` points to `/etc/loki/local-config.yaml` (the default), not the mounted `loki-config.yml` — fix the command if you want the custom config to apply.
