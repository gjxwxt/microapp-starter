# microapp-starter

云无关（Cloud-Agnostic）多项目快速上线通用骨架。面向 **1 台（或多台）轻量 Linux VPS**，在极低内存占用的前提下实现「静态页 + 轻量 API」分钟级独立上线，并保留随时切换到 **Caddy / Kamal 2 / Dokploy** 的标准化逃生舱。

## 设计原则（站在巨人肩膀上）

1. **云无关契约**：不包含任何云厂商命名；切换云厂商只需修改本地 `.env.deploy` 中的 `DEPLOY_HOST`。
2. **三段式平滑演进**：
   - **Phase 1（1–2 GiB 低配小鸡）**：`ops/bootstrap-vps.sh` + `quickapp@.service` + Nginx（常驻额外内存 `< 5 MB`）。
   - **Phase 2（上独立域名 / 多容器混跑）**：使用 `ops/Caddyfile.example`（自动 HTTPS）或 `ops/kamal-deploy.example.yml`（Kamal 2 零停机 SSH 发布，代理仅 `~25 MB`）。
   - **Phase 3（4 GiB+ 专机 / 多人协作）**：直接凭借根目录自带的 `Dockerfile` 与 `app.manifest.json` 接入 Dokploy 或 Coolify。
3. **同仓按需扩展**：默认单包起步（`src/` + 可选 `server/`）；只有当**同一产品**出现 Web + 管理后台 + 小程序共用 TypeScript 逻辑时，再按 `pnpm-workspace.yaml` 拆分为 `apps/ + packages/`，避免跨技术栈大 Monorepo 相互锁死版本。

---

## 快速开始（1 分钟启动新项目）

### 方式 A：从模板创建新项目

```bash
# 1. 使用 GitHub Template 或克隆后初始化
git clone https://github.com/gjxwxt/microapp-starter.git my-new-app
cd my-new-app
bash ops/init-project.sh --slug my-new-app --name "我的新微应用" --port 3302
```

（若本机已安装 `copier`，也可直接执行 `copier copy gh:gjxwxt/microapp-starter my-new-app`，后续可随时用 `copier update` 拉取底座升级。）

### 方式 B：新买一台空白云主机初始化底座（只需跑 1 次）

支持 Rocky / Alma / Ubuntu / Debian（需具备 SSH root 权限）：

```bash
scp -i ~/.ssh/your_key.pem ops/bootstrap-vps.sh ops/quick-deploy-static ops/quick-deploy-api root@YOUR_SERVER_IP:/tmp/
ssh -i ~/.ssh/your_key.pem root@YOUR_SERVER_IP "bash /tmp/bootstrap-vps.sh"
```

### 方式 C：日常一键发布

```bash
cp .env.deploy.example .env.deploy
# 编辑 .env.deploy 填入服务器 IP、SSH 密钥与 slug

bash ops/deploy.sh          # 自动读取 app.manifest.json 并发布前端 (+ 后端)
bash ops/deploy.sh --static # 仅发布前端静态产物
bash ops/deploy.sh --api    # 仅发布 server/ 轻量后端
```

---

## 目录说明

```text
.
├── app.manifest.json          # 项目元契约：slug、部署类型、端口、健康检查路径
├── .env.deploy.example        # 本地发布配置模板（.env.deploy 不提交 Git）
├── Dockerfile                 # Phase 2/3 容器化与零停机部署入口
├── copier.yml                 # Copier 可更新模板声明
├── ops/
│   ├── bootstrap-vps.sh       # 任一 Linux 主机一键装好 /opt/apps 底座
│   ├── quick-deploy-static    # 远端原子发布静态/SPA 并自动重载 Nginx
│   ├── quick-deploy-api       # 远端原子发布 systemd 后端 + 代理 + 健康探针
│   ├── deploy.sh              # 本地统一构建与发布入口
│   ├── init-project.sh        # 零依赖新项目初始化脚本
│   ├── Caddyfile.example      # Phase 2 绑定域名 + 自动 HTTPS 示例
│   └── kamal-deploy.example.yml
├── src/                       # 前端应用源码（支持静态站 / React / Vite / Astro）
└── server/                    # 可选轻量后端（Python / Node / Go，提供 start.sh + /health）
```
