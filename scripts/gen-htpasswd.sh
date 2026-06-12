#!/usr/bin/env bash
# Generate traefik/dynamic/.htpasswd from INGESTA_BASIC_AUTH in .env
# The .env file uses $$ escaping for docker-compose; this script converts it back to $.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-${REPO_ROOT}/.env}"
OUT="${REPO_ROOT}/traefik/dynamic/.htpasswd"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found" >&2
  exit 1
fi

line=$(grep '^INGESTA_BASIC_AUTH=' "$ENV_FILE" | head -1)
if [[ -z "$line" ]]; then
  echo "Error: INGESTA_BASIC_AUTH not found in $ENV_FILE" >&2
  exit 1
fi

# Strip key, convert $$ back to $
printf '%s\n' "${line#INGESTA_BASIC_AUTH=}" | sed 's/\$\$/$/g' > "$OUT"
echo "Generated $OUT"
