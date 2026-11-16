#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$APP_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$APP_DIR/.env"
  set +a
fi
export PORT="${PORT:-3302}"
export HOST="${HOST:-127.0.0.1}"
export APP_DB_PATH="${APP_DB_PATH:-$APP_DIR/data/app.db}"
exec python3 "$APP_DIR/app.py"
