#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLUG=""
NAME=""
PORT="3302"
MODE="fullstack"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --slug) SLUG="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --port) PORT="${2:-3302}"; shift 2 ;;
    --mode) MODE="${2:-fullstack}"; shift 2 ;;
    *)
      echo "Usage: bash ops/init-project.sh --slug <slug> [--name <title>] [--port <3300-3399>] [--mode fullstack|static]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$SLUG" ] || ! [[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]?$ ]]; then
  echo "Valid --slug required (lowercase letters, digits, hyphens)." >&2
  exit 1
fi

NAME="${NAME:-$SLUG}"

python3 - "$ROOT_DIR" "$SLUG" "$NAME" "$PORT" "$MODE" <<'PY'
import json, pathlib, sys

root = pathlib.Path(sys.argv[1])
slug, name, port, mode = sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]

manifest_path = root / "app.manifest.json"
m = json.loads(manifest_path.read_text(encoding="utf-8"))
m["slug"] = slug
m["name"] = name
m["mode"] = mode
if mode == "static":
    m.pop("backend", None)
else:
    m.setdefault("backend", {})
    m["backend"]["serviceName"] = f"{slug}-api"
    m["backend"]["port"] = port
manifest_path.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

pkg_path = root / "package.json"
if pkg_path.exists():
    pkg = json.loads(pkg_path.read_text(encoding="utf-8"))
    pkg["name"] = slug
    pkg_path.write_text(json.dumps(pkg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

index_path = root / "index.html"
if index_path.exists():
    html = index_path.read_text(encoding="utf-8")
    index_path.write_text(html.replace("MicroApp Starter", name), encoding="utf-8")
PY

echo "Initialized '$NAME' (slug=$SLUG, mode=$MODE, port=$PORT)."
echo "Next: cp .env.deploy.example .env.deploy && pnpm install && bash ops/deploy.sh"
