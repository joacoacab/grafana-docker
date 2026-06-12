# Observability Stack

Self-hosted observability stack running on Docker Compose.
Grafana · Loki · Prometheus · Tempo · Alloy · Traefik

> **Fase 2 — AWS Lightsail:** TLS automático via Let's Encrypt, Basic Auth en endpoints de ingesta.

## Quick start (local)

```bash
cp .env.example .env        # ajustar DOMAIN=localhost + credenciales
make start                  # crea acme.json si no existe y levanta el stack
```

Grafana → http://localhost:3000 (admin / valor en .env)  
Traefik dashboard → http://localhost:8080  
Prometheus → http://localhost:9090  
Alloy UI → http://localhost:12345

## Deploy en producción

### Pre-requisitos

- SSH key cargada para `ubuntu@54.173.124.1`
- `.env` completo (copiar de `.env.example` y completar todos los valores)
- `htpasswd` disponible localmente (`apt install apache2-utils`)

### Generar credenciales de ingesta

```bash
htpasswd -nb sirac tu_password_seguro
# Salida ejemplo: sirac:$apr1$xyz12345$hashhashhashhash
# Pegar esa salida tal cual en .env → INGESTA_BASIC_AUTH=sirac:$apr1$...
```

### Ejecutar deploy

```bash
./scripts/deploy.sh
```

El script:
1. Instala Docker en el servidor si no está
2. Clona el repo (o hace pull si ya existe) en `/opt/grafana-obs`
3. Copia `.env` al servidor
4. Crea `traefik/acme.json` con `chmod 600`
5. Ejecuta `docker compose up -d`

### Post-deploy: reglas de firewall (Lightsail)

Abrir solo estos puertos en el panel de Lightsail → Networking:

| Puerto | Protocolo | Descripción |
|--------|-----------|-------------|
| 22 | TCP | SSH |
| 80 | TCP | HTTP → redirect a HTTPS (requerido para Let's Encrypt) |
| 443 | TCP | HTTPS — Grafana UI |
| 4317 | TCP | OTLP gRPC (Tempo) |
| 4318 | TCP | OTLP HTTP (Tempo, protegido por Basic Auth) |

Cerrar: 3000, 3100, 3200, 8080, 9090, 12345

### Endpoints de producción

| Servicio | URL |
|----------|-----|
| Grafana | `https://obs.siracnetwork.com` |
| Loki push | `https://obs.siracnetwork.com/loki/api/v1/push` + Basic Auth |
| Prometheus | `https://obs.siracnetwork.com/prometheus/` + Basic Auth |
| Tempo OTLP HTTP | `https://obs.siracnetwork.com:4318` + Basic Auth |
| Tempo OTLP gRPC | `obs.siracnetwork.com:4317` (sin TLS, proteger por firewall) |

### Variables de deploy personalizables

```bash
REMOTE_HOST=54.173.124.1 REMOTE_DIR=/opt/grafana-obs ./scripts/deploy.sh
REMOTE_HOST=54.173.124.1 ./scripts/deploy.sh --dry-run   # ver sin ejecutar
```

---

## Make targets

| Comando | Acción |
|---------|--------|
| `make start` | Crea `acme.json` si falta y levanta el stack |
| `make stop` | Para y elimina containers |
| `make restart` | Reinicia containers en ejecución |
| `make logs` | Streamer de logs de todos los containers |
| `make ps` | Estado de containers |
| `make status` | Tabla compacta (nombre / estado / puertos) |

## Service map

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| Traefik | `traefik:v3.3` | 80, 443, 4318, 8080 | Reverse proxy, TLS, Basic Auth |
| Grafana | `grafana/grafana:13.0.2` | 3000 | UI, dashboards, alertas |
| Loki | `grafana/loki:3.7.0` | 3100 | Agregación de logs |
| Prometheus | `prom/prometheus:v3.4.0` | 9090 | Métricas (15d retención) |
| Tempo | `grafana/tempo:2.8.1` | 3200, 4317, 4318 | Trazas distribuidas (OTLP) |
| Alloy | `grafana/alloy:v1.9.2` | 12345 | Docker logs → Loki |
| ~~Mimir~~ | ~~`grafana/mimir:3.1.0`~~ | ~~9009~~ | Comentado — reactivar en Fase 3 con 4 GB+ |

## Phase roadmap

- **Fase 1**: Stack local, Prometheus, HTTP, filesystem
- **Fase 2** ← current: Lightsail, TLS Let's Encrypt, Basic Auth ingesta
- **Fase 3**: EdgeForge (Raspberry Pi), Grafana Organizations, Mimir
- **Fase 4**: Observability as a Service
