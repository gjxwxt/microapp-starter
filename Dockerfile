# Phase 2/3 容器化入口（适配 Kamal 2 / Dokploy / Coolify / 任何支持 Docker 的云主机）
FROM node:22-alpine AS frontend
WORKDIR /app
RUN corepack enable pnpm
COPY package.json pnpm-lock.yaml* ./
RUN if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; else pnpm install; fi
COPY index.html vite.config.ts tsconfig.json ./
COPY src ./src
RUN pnpm build

FROM python:3.12-slim
WORKDIR /app
COPY server ./server
COPY --from=frontend /app/dist ./dist
ENV HOST=0.0.0.0 PORT=3000
EXPOSE 3000
CMD ["python3", "server/app.py"]
