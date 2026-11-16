#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/app.manifest.json"
ENV_FILE="${DEPLOY_ENV_FILE:-$ROOT_DIR/.env.deploy}"

ONLY_MODE="all"
DRY_RUN=0
NO_BUILD=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --static) ONLY_MODE="static" ;;
    --api) ONLY_MODE="api" ;;
    --all) ONLY_MODE="all" ;;
    --check) DRY_RUN=1 ;;
    --no-build) NO_BUILD=1 ;;
    *)
      echo "Usage: ops/deploy.sh [--all|--static|--api] [--check] [--no-build]" >&2
      exit 1
      ;;
  esac
  shift
done

[ -f "$MANIFEST" ] || { echo "Missing $MANIFEST" >&2; exit 1; }

# Parse app.manifest.json using python3 or node (zero jq dependency)
eval "$(
  python3 - "$MANIFEST" <<'PY' 2>/dev/null || node - "$MANIFEST" <<'NODE'
import json, shlex, sys
m = json.load(open(sys.argv[1]))
fe = m.get("frontend") or {}
be = m.get("backend") or {}
vals = {
    "M_SLUG": m.get("slug", ""),
    "M_MODE": m.get("mode", "static"),
    "M_PUBLIC": "1" if m.get("public") else "0",
    "M_SPA": "1" if m.get("spa") else "0",
    "M_BUILD_CMD": fe.get("buildCommand", ""),
    "M_DIST_DIR": fe.get("distDir", "dist"),
    "M_API_SERVICE": be.get("serviceName", ""),
    "M_API_DIR": be.get("dir", "server"),
    "M_API_PORT": str(be.get("port", "")),
    "M_API_HEALTH": be.get("healthPath", "/health"),
    "M_API_SECRET_KEY": be.get("secretEnvKey", ""),
}
for k, v in vals.items():
    print(f"{k}={shlex.quote(v)}")
PY
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const fe = m.frontend || {};
const be = m.backend || {};
const q = (s) => "'" + String(s || "").replace(/'/g, "'\\''") + "'";
const vals = {
  M_SLUG: m.slug || "",
  M_MODE: m.mode || "static",
  M_PUBLIC: m.public ? "1" : "0",
  M_SPA: m.spa ? "1" : "0",
  M_BUILD_CMD: fe.buildCommand || "",
  M_DIST_DIR: fe.distDir || "dist",
  M_API_SERVICE: be.serviceName || "",
  M_API_DIR: be.dir || "server",
  M_API_PORT: be.port || "",
  M_API_HEALTH: be.healthPath || "/health",
  M_API_SECRET_KEY: be.secretEnvKey || "",
};
for (const [k, v] of Object.entries(vals)) {
  console.log(`${k}=${q(v)}`);
}
NODE
)"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
elif [ "$DRY_RUN" -ne 1 ]; then
  echo "Missing $ENV_FILE. Copy .env.deploy.example to .env.deploy first." >&2
  exit 1
fi

DEPLOY_SLUG="${DEPLOY_SLUG:-$M_SLUG}"
DEPLOY_PUBLIC="${DEPLOY_PUBLIC:-$M_PUBLIC}"
DEPLOY_SPA="${DEPLOY_SPA:-$M_SPA}"
API_SERVICE="${API_SERVICE:-$M_API_SERVICE}"
API_PORT="${API_PORT:-$M_API_PORT}"
DEPLOY_SSH_PORT="${DEPLOY_SSH_PORT:-22}"
DEPLOY_USER="${DEPLOY_USER:-root}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[CHECK] slug=$DEPLOY_SLUG mode=$M_MODE only=$ONLY_MODE host=${DEPLOY_HOST:-unset} dist=$M_DIST_DIR api=${API_SERVICE:-none}:${API_PORT:-none}"
  exit 0
fi

: "${DEPLOY_HOST:?DEPLOY_HOST is required}"
: "${DEPLOY_SSH_KEY:?DEPLOY_SSH_KEY is required}"
: "${DEPLOY_SLUG:?DEPLOY_SLUG is required}"

SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_SSH_PORT" -o StrictHostKeyChecking=no)
REMOTE="${DEPLOY_USER}@${DEPLOY_HOST}"

deploy_api() {
  [ -n "$API_SERVICE" ] || return 0
  local api_dir="$ROOT_DIR/${M_API_DIR:-server}"
  [ -d "$api_dir" ] || { echo "Backend dir not found: $api_dir" >&2; exit 1; }

  local tmp="/tmp/quick-api-${API_SERVICE}-$$"
  local extra_flags=()
  [ -n "$M_API_HEALTH" ] && extra_flags+=(--health "$M_API_HEALTH")
  [ -n "$M_API_SECRET_KEY" ] && extra_flags+=(--secret-env "$M_API_SECRET_KEY")

  echo "==> Deploying API service '$API_SERVICE' to $REMOTE:$API_PORT..."
  ssh "${SSH_OPTS[@]}" "$REMOTE" "rm -rf '$tmp' && mkdir -p '$tmp'"
  COPYFILE_DISABLE=1 tar --exclude='__pycache__' --exclude='*.pyc' --exclude='data' --exclude='.env' \
    -czf - -C "$api_dir" . | ssh "${SSH_OPTS[@]}" "$REMOTE" "tar -xzf - -C '$tmp'"
  ssh "${SSH_OPTS[@]}" "$REMOTE" \
    "/opt/apps/bin/quick-deploy-api '$API_SERVICE' '$tmp' '$DEPLOY_SLUG' '$API_PORT' ${extra_flags[*]:-} && rm -rf '$tmp'"
}

deploy_static() {
  if [ "$NO_BUILD" -ne 1 ] && [ -n "$M_BUILD_CMD" ]; then
    echo "==> Running build: $M_BUILD_CMD"
    (cd "$ROOT_DIR" && eval "$M_BUILD_CMD")
  fi

  local dist_dir="$ROOT_DIR/${M_DIST_DIR:-dist}"
  [ -d "$dist_dir" ] || { echo "Build dir not found: $dist_dir" >&2; exit 1; }

  local tmp="/tmp/quick-static-${DEPLOY_SLUG}-$$"
  local flags=()
  [ "$DEPLOY_PUBLIC" = "1" ] && flags+=(--public)
  [ "$DEPLOY_SPA" = "1" ] && flags+=(--spa)

  echo "==> Deploying static bundle '$DEPLOY_SLUG' to $REMOTE..."
  ssh "${SSH_OPTS[@]}" "$REMOTE" "rm -rf '$tmp' && mkdir -p '$tmp'"
  COPYFILE_DISABLE=1 tar -czf - -C "$dist_dir" . | ssh "${SSH_OPTS[@]}" "$REMOTE" "tar -xzf - -C '$tmp'"
  ssh "${SSH_OPTS[@]}" "$REMOTE" \
    "/opt/apps/bin/quick-deploy-static '$DEPLOY_SLUG' '$tmp' ${flags[*]:-} && rm -rf '$tmp'"
}

if [ "$ONLY_MODE" = "api" ]; then
  deploy_api
elif [ "$ONLY_MODE" = "static" ]; then
  deploy_static
else
  if [ "$M_MODE" = "fullstack" ] && [ -n "$API_SERVICE" ]; then
    deploy_api
  fi
  deploy_static
fi

if [ -n "${PUBLIC_ORIGIN:-}" ]; then
  echo "Live URL: ${PUBLIC_ORIGIN%/}/${DEPLOY_SLUG}/"
else
  echo "Live URL: http://${DEPLOY_HOST}:443/${DEPLOY_SLUG}/"
fi
