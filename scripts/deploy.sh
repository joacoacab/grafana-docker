#!/usr/bin/env bash
# deploy.sh — deploy the observability stack to the Lightsail production server
# Usage: ./scripts/deploy.sh [--dry-run]
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
REMOTE_USER="${REMOTE_USER:-ubuntu}"
REMOTE_HOST="${REMOTE_HOST:-54.173.124.1}"
REMOTE_DIR="${REMOTE_DIR:-/opt/grafana-obs}"
REPO_URL="${REPO_URL:-$(git -C "$(dirname "$0")/.." remote get-url origin 2>/dev/null || true)}"
COMPOSE_CMD="sudo docker compose"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()  { echo "==> $*"; }
warn() { echo "    [warn] $*" >&2; }

remote() {
  if $DRY_RUN; then
    echo "    [dry-run] ssh ${REMOTE_USER}@${REMOTE_HOST}: $*"
  else
    ssh $SSH_OPTS "${REMOTE_USER}@${REMOTE_HOST}" "$@"
  fi
}

upload() {
  if $DRY_RUN; then
    echo "    [dry-run] scp $1 → ${REMOTE_USER}@${REMOTE_HOST}:$2"
  else
    scp $SSH_OPTS "$1" "${REMOTE_USER}@${REMOTE_HOST}:$2"
  fi
}

# ─── Pre-flight checks ────────────────────────────────────────────────────────
log "Pre-flight checks"

if [[ -z "$REPO_URL" ]]; then
  echo "ERROR: No git remote 'origin' found. Set REPO_URL env var or: git remote add origin <url>"
  exit 1
fi
log "  Repo URL : $REPO_URL"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at ${ENV_FILE}"
  echo "       cp .env.example .env  then fill in all values before deploying."
  exit 1
fi
log "  .env     : OK"

if $DRY_RUN; then
  warn "Dry-run mode — no changes will be made on the server."
fi

# ─── 1. Install Docker ────────────────────────────────────────────────────────
log "Step 1 — Install Docker (skip if present)"
remote '
  if command -v docker &>/dev/null; then
    echo "    Docker already installed: $(docker --version)"
  else
    echo "    Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "    Docker installed."
  fi
'

# ─── 2. Clone or pull repo ────────────────────────────────────────────────────
log "Step 2 — Clone / pull repo to ${REMOTE_DIR}"
remote "
  if [ -d '${REMOTE_DIR}/.git' ]; then
    echo '    Pulling latest...'
    git -C '${REMOTE_DIR}' fetch origin
    git -C '${REMOTE_DIR}' reset --hard origin/main
  else
    echo '    Cloning...'
    sudo mkdir -p '${REMOTE_DIR}'
    sudo chown \"\${USER}:\${USER}\" '${REMOTE_DIR}'
    git clone '${REPO_URL}' '${REMOTE_DIR}'
  fi
"

# ─── 3. Copy .env ─────────────────────────────────────────────────────────────
log "Step 3 — Copy .env to server"
upload "$ENV_FILE" "${REMOTE_DIR}/.env"

# ─── 4. Generate .htpasswd for Traefik basicAuth ─────────────────────────────
log "Step 4 — Generate traefik/dynamic/.htpasswd from .env"
remote "
  cd '${REMOTE_DIR}'
  bash scripts/gen-htpasswd.sh '${REMOTE_DIR}/.env'
"

# ─── 5. Prepare acme.json (Traefik requires chmod 600) ───────────────────────
log "Step 5 — Ensure traefik/acme.json exists with chmod 600"
remote "
  ACME=\"${REMOTE_DIR}/traefik/acme.json\"
  if [ ! -f \"\$ACME\" ]; then
    touch \"\$ACME\"
    echo '    Created acme.json'
  fi
  chmod 600 \"\$ACME\"
  echo '    acme.json: OK (chmod 600)'
"

# ─── 6. Start the stack ───────────────────────────────────────────────────────
log "Step 6 — docker compose up -d"
remote "
  cd '${REMOTE_DIR}'
  ${COMPOSE_CMD} pull --quiet
  ${COMPOSE_CMD} up -d --remove-orphans
"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
log "Deploy complete"
echo "    Grafana : https://obs.siracnetwork.com"
echo "    Traefik : http://${REMOTE_HOST}:8080  (block port 8080 at firewall)"
echo "    Alloy   : http://${REMOTE_HOST}:12345 (block at firewall)"
echo ""
echo "    Ingest endpoints (Basic Auth required):"
echo "    Loki    : https://obs.siracnetwork.com/loki/api/v1/push"
echo "    Prom    : https://obs.siracnetwork.com/prometheus/"
echo "    Tempo   : https://obs.siracnetwork.com:4318  (OTLP HTTP)"
echo "    Tempo   : ${REMOTE_HOST}:4317               (OTLP gRPC, no auth)"
echo ""
echo "    Recommended firewall rules (Lightsail):"
echo "    ALLOW: 22 (SSH), 80 (HTTP→redirect), 443 (HTTPS), 4317 (OTLP gRPC), 4318 (OTLP HTTP)"
echo "    DENY:  3000, 3100, 3200, 9090, 8080, 12345 (internal / dashboard ports)"
