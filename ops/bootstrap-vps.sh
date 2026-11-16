#!/usr/bin/env bash
set -euo pipefail

# 云无关 Linux VPS 底座初始化脚本（支持 Ubuntu/Debian/Rocky/AlmaLinux）
# 幂等运行：不覆盖已有站点配置，安全装好 /opt/apps/ + quickapp@.service + Nginx apps.d

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (or via sudo)." >&2
  exit 1
fi

echo "[1/5] Ensuring base packages (nginx, python3, curl, tar)..."
if command -v dnf >/dev/null 2>&1; then
  dnf install -y -q nginx python3 curl tar >/dev/null
elif command -v apt-get >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx python3 curl tar >/dev/null
fi

echo "[2/5] Creating /opt/apps directory layout..."
mkdir -p /opt/apps/{sites,services,bin,backups} /etc/nginx/apps.d

if [ ! -f /opt/apps/REGISTRY.md ]; then
  cat > /opt/apps/REGISTRY.md <<'REG'
# VPS MicroApps Registry

- `:3300-3399` reserved for `quickapp@<service>` backend services
- Static micro-apps live in `/opt/apps/sites/<slug>`
- Nginx per-app fragments live in `/etc/nginx/apps.d/*.conf`

## Services & Apps
REG
fi

echo "[3/5] Installing quick-deploy-static & quick-deploy-api..."
if [ -f "$SCRIPT_DIR/quick-deploy-static" ]; then
  install -m 755 "$SCRIPT_DIR/quick-deploy-static" /opt/apps/bin/quick-deploy-static
fi
if [ -f "$SCRIPT_DIR/quick-deploy-api" ]; then
  install -m 755 "$SCRIPT_DIR/quick-deploy-api" /opt/apps/bin/quick-deploy-api
fi

echo "[4/5] Installing quickapp@.service systemd unit..."
cat > /etc/systemd/system/quickapp@.service <<'UNIT'
[Unit]
Description=Quick-launch micro-app (%i)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/apps/services/%i
Environment=NODE_ENV=production
Environment=HOST=127.0.0.1
EnvironmentFile=-/opt/apps/services/%i/.env
ExecStart=/bin/bash /opt/apps/services/%i/start.sh
Restart=always
RestartSec=3
MemoryMax=256M
LimitNOFILE=16384

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

echo "[5/5] Ensuring Nginx includes /etc/nginx/apps.d/*.conf..."
if ! grep -Rqs "apps.d/\*.conf" /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/nginx/nginx.conf 2>/dev/null; then
  cat > /etc/nginx/conf.d/microapps-default.conf <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 24m;

    include /etc/nginx/apps.d/*.conf;

    location = / {
        return 200 "microapps-host ready\n";
        add_header Content-Type text/plain;
    }
}
NGINX
fi

nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "Bootstrap complete. Ready for ops/deploy.sh!"
