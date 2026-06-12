# SPEC: Observability Stack — grafana-docker

**Versión:** 1.2  
**Estado:** APROBADO  
**Repo:** `grafana-docker`  
**Metodología:** SDD (spec-first, implementación vía Claude Code)

---

## 1. Objetivo

Levantar un stack de observabilidad centralizado, multi-tenant, autohosteado en AWS Lightsail, que permita:

- Recolectar **métricas, logs y trazas** de múltiples fuentes (infra propia + clientes)
- Visualizar todo desde un único **Grafana** con autenticación básica
- Escalar a un modelo **Observability as a Service** para clientes SME

---

## 2. Stack de componentes

| Componente | Imagen Docker | Versión | Rol |
|---|---|---|---|
| **Grafana** | `grafana/grafana` | `13.0.2` | UI, dashboards, alertas |
| **Loki** | `grafana/loki` | `3.7.0` | Agregación de logs |
| **Prometheus** | `prom/prometheus` | `v3.4.0` | Métricas — Fase 1 (2 GB friendly) |
| ~~**Mimir**~~ | ~~`grafana/mimir`~~ | ~~`3.1.0`~~ | ~~Métricas long-term~~ — **desactivado, Fase 2** |
| **Tempo** | `grafana/tempo` | `2.8.1` | Trazas distribuidas (OpenTelemetry / Jaeger) |
| **Alloy** | `grafana/alloy` | `v1.9.2` | Agente unificado (logs → Loki) |
| **Traefik** | `traefik` | `v3.3` | Reverse proxy + TLS automático (Let's Encrypt) |

> **v1.2:** Mimir desactivado para validación en instancia de 2 GB. Prometheus reemplaza a Mimir en Fase 1.
> Reactivar Mimir y migrar Prometheus → Mimir en Fase 2 (instancia 4 vCPU / 8 GB).  
> No se incluye Alertmanager standalone — Grafana Alerting nativo cubre el caso inicial.  
> No se incluye PostgreSQL — Grafana usa SQLite en v1 (suficiente para uso single-instance).

---

## 3. Infraestructura target

- **Proveedor:** AWS Lightsail
- **Instancia mínima:** `2 vCPU / 4 GB RAM` para arrancar (escalar a `4 vCPU / 8 GB` con 3+ clientes)
- **OS:** Ubuntu 24.04 LTS
- **Dominio:** `obs.siracnetwork.com` (o subdominio a confirmar)
- **Puertos expuestos:**
  - `443` → Traefik (HTTPS, Grafana UI)
  - `80` → redirect a 443
  - `4317` / `4318` → OTLP gRPC / HTTP (Tempo, desde agentes externos)
  - `3100` → Loki push (desde agentes externos, detrás de Traefik auth)
  - `9009` → Mimir remote_write (desde agentes externos, detrás de Traefik auth)

---

## 4. Estructura del repositorio

```
grafana-docker/
├── docker-compose.yml
├── .env.example
├── .env                          # gitignored
├── Makefile
├── README.md
├── traefik/
│   ├── traefik.yml               # Config estática (entrypoints, ACME, Docker provider)
│   └── dynamic/
│       └── middlewares.yml       # BasicAuth middleware para endpoints de ingesta
├── grafana/
│   ├── grafana.ini
│   └── provisioning/
│       ├── datasources/
│       │   └── datasources.yml   # Loki + Mimir + Tempo auto-provisionados
│       └── dashboards/
│           └── dashboards.yml    # Carga automática de dashboards JSON
├── loki/
│   └── loki.yml
├── mimir/
│   └── mimir.yml
├── tempo/
│   └── tempo.yml
├── alloy/
│   └── config.alloy              # Self-monitoring del host (métricas + logs propios)
├── legacy/                       # Stack viejo archivado (no tocar)
└── docs/
    └── specs/
        └── spec_observability_stack.md
```

---

## 5. Multi-tenancy

**Estrategia v1 (header-based):**

- Loki, Mimir y Tempo soportan el header `X-Scope-OrgID` nativamente
- Cada fuente envía sus datos con un `tenant_id` único (ej. `sirac`, `edgeforge`, `cliente_genofa`)
- En Grafana se crea una **Grafana Organization por tenant** con sus propios datasources filtrados
- Traefik agrega `X-Scope-OrgID` automáticamente según el subdomain o la ruta si se necesita

**Tenant IDs iniciales:**
- `sirac-internal` → self-monitoring del stack y del host
- `edgeforge` → Raspberry Pi / EdgeForge
- `cliente_genofa` → primer cliente externo (cuando corresponda)

---

## 6. Autenticación

- **Grafana UI:** usuario/contraseña admin vía `GF_SECURITY_ADMIN_PASSWORD` en `.env`
- **Endpoints de ingesta** (Loki push, Mimir remote_write, Tempo OTLP): Basic Auth via middleware Traefik
- **Agente Alloy externo:** credenciales por cliente en su `config.alloy` local (no se commitean)
- **Sin OAuth/SSO en v1**

---

## 7. Self-monitoring

El propio stack se monitorea a sí mismo via Alloy en el mismo host:

- Scrape de métricas de todos los contenedores (`/metrics` endpoints)
- Logs del host vía Docker socket → Loki (tenant `sirac-internal`)
- Dashboard "Stack Health" provisionado por defecto

---

## 8. Ejemplo de config Alloy para cliente externo

```hcl
// config.alloy — instalado en el server del cliente
prometheus.scrape "node" {
  targets = [{"__address__" = "localhost:9100"}]
  forward_to = [prometheus.remote_write.central.receiver]
}

prometheus.remote_write "central" {
  endpoint {
    url = "https://obs.siracnetwork.com/mimir/api/v1/push"
    headers = { "X-Scope-OrgID" = "cliente_genofa" }
    basic_auth {
      username = "cliente_genofa"
      password = env("CENTRAL_PASSWORD")
    }
  }
}

loki.source.file "app_logs" {
  targets = [{ __path__ = "/var/log/app/*.log", job = "app" }]
  forward_to = [loki.write.central.receiver]
}

loki.write "central" {
  endpoint {
    url = "https://obs.siracnetwork.com/loki/loki/api/v1/push"
    headers = { "X-Scope-OrgID" = "cliente_genofa" }
    basic_auth {
      username = "cliente_genofa"
      password = env("CENTRAL_PASSWORD")
    }
  }
}
```

---

## 9. Variables de entorno (.env.example)

```env
# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=changeme_strong_password

# Traefik
TRAEFIK_ACME_EMAIL=joaco@siracnetwork.com
DOMAIN=obs.siracnetwork.com

# Basic Auth para endpoints de ingesta (htpasswd -nb user pass)
# Generar con: echo $(htpasswd -nb sirac yourpassword) | sed -e 's/\$/\$\$/g'
INGESTA_BASIC_AUTH=sirac:$$apr1$$xxxx
```

---

## 10. Fases de implementación

### Fase 1 — Stack base local ← IMPLEMENTAR AHORA
- [ ] Mover archivos legacy a `legacy/`
- [ ] `docker-compose.yml` con todos los servicios y tags fijos
- [ ] Configs mínimas funcionales de cada componente (single-binary, filesystem storage)
- [ ] Datasources auto-provisionados en Grafana (Loki + Mimir + Tempo)
- [ ] Alloy self-monitoring del host
- [ ] `.env.example` completo
- [ ] `Makefile` con targets: `start`, `stop`, `restart`, `logs`, `ps`, `status`
- [ ] `README.md` con instrucciones de arranque

### Fase 2 — Deploy en Lightsail
- [ ] Lightsail instance Ubuntu 24.04
- [ ] DNS `obs.siracnetwork.com` apuntando a la instancia
- [ ] TLS automático via Traefik + Let's Encrypt
- [ ] Basic Auth en endpoints de ingesta
- [ ] Primer tenant externo: EdgeForge (Raspberry Pi)

### Fase 3 — Primer cliente externo
- [ ] Config Alloy para cliente externo
- [ ] Grafana Organization para el cliente
- [ ] Dashboard de infra base (CPU, RAM, disco, logs del sistema)
- [ ] Alertas básicas (Grafana Alerting → email / Telegram)

### Fase 4 — Observability as a Service
- [ ] Documentación de onboarding para clientes
- [ ] Dashboard templates por tipo de app (Django, Node, etc.)
- [ ] Guía de integración OpenTelemetry SDK
- [ ] Modelo de precios / oferta de servicio

---

## 11. Decisiones técnicas

| Decisión | Justificación |
|---|---|
| **Grafana 13** en vez de 12.x | 12.2 llega a EOL el 23/06/2026; 13.0.2 tiene soporte hasta enero 2027 |
| **Mimir sobre Prometheus** | Long-term storage nativo, multi-tenancy out of the box, API compatible |
| **Alloy sobre Promtail/Agent** | Agente unificado actual de Grafana Labs; Grafana Agent llegó a EOL nov 2025 |
| **Single-binary mode** (Loki/Mimir/Tempo) | Simplifica el deploy inicial; escala a microservices si crece |
| **SQLite para Grafana** | Elimina dependencia de PostgreSQL en v1; migración a Postgres en v2 si necesario |
| **Filesystem storage** en v1 | Evita dependencia de S3 para arrancar; migración a S3 en v2 si necesario |
| **Traefik v3** sobre Nginx | Ya usado en La Balanza, TLS automático, Docker-native |

---

## 12. Out of scope (v1)

- S3/object storage para persistencia
- Grafana SSO / OAuth
- Grafana OnCall
- Pyroscope (continuous profiling)
- Alta disponibilidad / clustering
- PostgreSQL como backend de Grafana

---

*Spec v1.1 — listo para implementar Fase 1 con Claude Code.*