# Sea-Saw Gateway 部署指南

## 架构说明

Gateway 采用**纯反向代理架构**：

```
┌─────────────────────────────────────────────────────┐
│                  sea-saw-gateway                    │
│           (只包含 Nginx 反向代理)                    │
│                     :80                             │
└──────────────┬──────────────────────┬───────────────┘
               │                      │
       /api/, /admin/              所有其他请求
       /static/, /media/              │
               │                      │
               ▼                      ▼
     ┌──────────────────┐    ┌─────────────────┐
     │ sea-saw-backend  │    │ sea-saw-frontend│
     │  (Django + API)  │    │  (React Native) │
     │      :8000       │    │      :80        │
     └──────────────────┘    └─────────────────┘

所有服务通过共享 Docker network: sea-saw-network 互联
```

## 核心原则

1. ✅ **Gateway 只做反向代理** - 不运行任何业务服务
2. ✅ **服务独立部署** - Frontend, Backend, Gateway 各自独立
3. ✅ **共享 Docker Network** - 通过 `sea-saw-network` 互联
4. ✅ **配置文件分散** - 各服务配置在各自仓库

## 前置要求

### 1. 创建共享 Docker Network

**必须在任何服务启动前创建**：

```bash
# SSH 登录服务器
ssh appuser@your-server-ip

# 创建共享网络（只需执行一次）
docker network create sea-saw-network

# 验证网络已创建
docker network ls | grep sea-saw
```

### 2. 服务部署目录

```bash
# 创建部署目录
mkdir -p ~/sea-saw/{backend,frontend,gateway}

# 结构如下：
# ~/sea-saw/
# ├── backend/      # sea-saw-server 部署
# ├── frontend/     # sea-saw-app 部署
# └── gateway/      # sea-saw-gateway 部署
```

## 部署顺序

### ⚠️ 重要：必须按以下顺序部署

```
1. Backend (sea-saw-server)  ← 先部署后端服务
   ↓
2. Frontend (sea-saw-app)    ← 再部署前端服务
   ↓
3. Gateway (sea-saw-gateway) ← 最后部署网关
```

---

## 步骤 1: 部署后端服务

### 1.1 配置后端环境

```bash
cd ~/sea-saw/backend

# 创建配置文件
cat > .env/.prod << 'EOF'
DEBUG=0
SECRET_KEY=your-strong-random-secret-key-here
DJANGO_ALLOWED_HOSTS=your-domain.com your-ip localhost 127.0.0.1

SQL_ENGINE=django.db.backends.postgresql
SQL_DATABASE=sea_saw_prod
SQL_USER=sea_saw_prod_user
SQL_PASSWORD=your-secure-database-password
SQL_HOST=sea-saw-db
SQL_PORT=5432

REDIS_HOST=sea-saw-redis
REDIS_PORT=6379

CELERY_BROKER_URL=redis://sea-saw-redis:6379/0
CELERY_RESULT_BACKEND=redis://sea-saw-redis:6379/0
EOF

cat > .env/.prod.db << 'EOF'
POSTGRES_DB=sea_saw_prod
POSTGRES_USER=sea_saw_prod_user
POSTGRES_PASSWORD=your-secure-database-password
EOF

chmod 600 .env/.prod .env/.prod.db
```

### 1.2 启动后端服务

```bash
cd ~/sea-saw/backend

# 启动所有后端服务
docker compose -f docker-compose.prod.yml up -d

# 查看服务状态
docker compose -f docker-compose.prod.yml ps

# 应该看到以下容器运行：
# - sea-saw-backend
# - sea-saw-db
# - sea-saw-redis
# - sea-saw-celery-worker
# - sea-saw-celery-beat
# - sea-saw-flower

# 检查日志
docker compose -f docker-compose.prod.yml logs -f web
```

### 1.3 初始化数据库

```bash
cd ~/sea-saw/backend

# 运行数据库迁移
docker compose -f docker-compose.prod.yml exec web python manage.py migrate

# 创建管理员账号
docker compose -f docker-compose.prod.yml exec web python manage.py createsuperuser

# 收集静态文件
docker compose -f docker-compose.prod.yml exec web python manage.py collectstatic --noinput
```

### 1.4 验证后端运行

```bash
# 检查健康状态
docker compose -f docker-compose.prod.yml exec web curl http://localhost:8000/health/

# 或通过容器名访问
docker run --rm --network sea-saw-network curlimages/curl:latest \
  curl http://sea-saw-backend:8000/health/
```

---

## 步骤 2: 部署前端服务

### 2.1 启动前端服务

```bash
cd ~/sea-saw/frontend

# 启动前端容器
docker compose up -d

# 查看服务状态
docker compose ps

# 应该看到：
# - sea-saw-frontend

# 检查日志
docker compose logs -f
```

### 2.2 验证前端运行

```bash
# 测试前端服务
docker run --rm --network sea-saw-network curlimages/curl:latest \
  curl -I http://sea-saw-frontend/
```

---

## 步骤 3: 部署 Gateway

### 3.1 启动 Gateway

```bash
cd ~/sea-saw/gateway

# 启动 Gateway
docker compose up -d

# 查看服务状态
docker compose ps

# 应该看到：
# - sea-saw-gateway

# 检查日志
docker compose logs -f
```

### 3.2 验证 Gateway 运行

```bash
# 测试 Gateway 健康检查
curl http://localhost/health/

# 测试前端访问
curl -I http://localhost/

# 测试 API 访问
curl http://localhost/api/

# 测试 Admin 访问
curl -I http://localhost/admin/
```

---

## 服务管理

### 查看所有服务状态

```bash
# 查看所有 sea-saw 容器
docker ps -a --filter "name=sea-saw"

# 查看网络连接
docker network inspect sea-saw-network
```

### 重启单个服务

```bash
# 重启后端
cd ~/sea-saw/backend
docker compose -f docker-compose.prod.yml restart web

# 重启前端
cd ~/sea-saw/frontend
docker compose restart

# 重启 Gateway
cd ~/sea-saw/gateway
docker compose restart
```

### 更新服务

#### 更新后端

```bash
cd ~/sea-saw/backend

# Pull 最新镜像
docker compose -f docker-compose.prod.yml pull

# 重启服务
docker compose -f docker-compose.prod.yml up -d

# 运行迁移（如有需要）
docker compose -f docker-compose.prod.yml exec web python manage.py migrate
```

#### 更新前端

```bash
cd ~/sea-saw/frontend

# Pull 最新镜像
docker compose pull

# 重启服务
docker compose up -d
```

#### 更新 Gateway

```bash
cd ~/sea-saw/gateway

# Pull 最新镜像
docker compose pull

# 重启服务
docker compose up -d
```

### 查看日志

```bash
# 后端日志
cd ~/sea-saw/backend
docker compose -f docker-compose.prod.yml logs -f web

# 前端日志
cd ~/sea-saw/frontend
docker compose logs -f

# Gateway 日志
cd ~/sea-saw/gateway
docker compose logs -f

# Nginx 访问日志
docker exec sea-saw-gateway tail -f /var/log/nginx/gateway.access.log
```

---

## 故障排查

### Gateway 无法访问后端

```bash
# 检查 Gateway 是否在正确的网络中
docker network inspect sea-saw-network

# 测试 Gateway 到后端的连接
docker exec sea-saw-gateway wget -O- http://sea-saw-backend:8000/health/

# 检查后端容器是否运行
docker ps -a --filter "name=sea-saw-backend"
```

### Gateway 无法访问前端

```bash
# 测试 Gateway 到前端的连接
docker exec sea-saw-gateway wget -O- http://sea-saw-frontend/

# 检查前端容器是否运行
docker ps -a --filter "name=sea-saw-frontend"
```

### 静态文件 404

```bash
# 检查 backend static volume
docker volume inspect sea-saw-backend-static

# 检查 Gateway 是否挂载了 volume
docker inspect sea-saw-gateway | grep Mounts -A 20

# 重新收集静态文件
cd ~/sea-saw/backend
docker compose -f docker-compose.prod.yml exec web python manage.py collectstatic --noinput
```

### 数据库连接失败

```bash
# 检查数据库容器
docker ps -a --filter "name=sea-saw-db"

# 检查数据库日志
cd ~/sea-saw/backend
docker compose -f docker-compose.prod.yml logs db

# 测试数据库连接
docker compose -f docker-compose.prod.yml exec db psql -U sea_saw_prod_user -d sea_saw_prod -c "SELECT 1;"
```

---

## CI/CD 自动部署

### GitHub Actions Workflow

每个仓库的 GitHub Actions 应该：

1. **sea-saw-server**: 构建镜像 → 推送到 TCR → SSH 到服务器 → Pull 镜像 → 重启后端服务
2. **sea-saw-app**: 构建镜像 → 推送到 TCR → SSH 到服务器 → Pull 镜像 → 重启前端服务
3. **sea-saw-gateway**: 构建镜像 → 推送到 TCR → SSH 到服务器 → Pull 镜像 → 重启 Gateway

### 部署脚本示例

```bash
# 后端部署脚本
cd ~/sea-saw/backend
docker compose -f docker-compose.prod.yml pull web celery_worker celery_beat flower
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml exec web python manage.py migrate

# 前端部署脚本
cd ~/sea-saw/frontend
docker compose pull
docker compose up -d

# Gateway 部署脚本
cd ~/sea-saw/gateway
docker compose pull
docker compose up -d
```

---

## 安全建议

1. ✅ 所有 `.env` 文件使用 `chmod 600` 限制权限
2. ✅ 使用强密码和随机 SECRET_KEY (50+ 字符)
3. ✅ 数据库只暴露在 Docker network 内部，不开放端口
4. ✅ Redis 只暴露在 Docker network 内部
5. ✅ Flower 端口 (5555) 考虑使用防火墙限制访问
6. ✅ 在生产环境配置 SSL/TLS (Gateway 443 端口)

---

## 监控与维护

### 磁盘空间

```bash
# 查看 Docker 磁盘使用
docker system df

# 清理未使用的资源
docker system prune -a

# 查看 volume 大小
docker volume ls
```

### 性能监控

```bash
# 查看容器资源使用
docker stats

# 查看特定服务资源
docker stats sea-saw-backend sea-saw-frontend sea-saw-gateway
```

### 备份

```bash
# 备份数据库
cd ~/sea-saw/backend
docker compose -f docker-compose.prod.yml exec db pg_dump -U sea_saw_prod_user sea_saw_prod > backup_$(date +%Y%m%d).sql

# 备份 media 文件
tar -czf media_backup_$(date +%Y%m%d).tar.gz \
  -C /var/lib/docker/volumes/sea-saw-backend-media/_data .
```

---

## 总结

### 服务职责

| 服务 | 职责 | 端口 | 网络 |
|------|------|------|------|
| **sea-saw-backend** | Django API, Admin, Celery | 8000 (internal) | sea-saw-network |
| **sea-saw-db** | PostgreSQL 数据库 | 5432 (internal) | sea-saw-network |
| **sea-saw-redis** | Redis 缓存 & 消息队列 | 6379 (internal) | sea-saw-network |
| **sea-saw-frontend** | React Native Web 前端 | 80 (internal) | sea-saw-network |
| **sea-saw-gateway** | Nginx 反向代理 | **80 (public)** | sea-saw-network |

### 访问路由

| 路径 | 目标服务 | 说明 |
|------|---------|------|
| `/` | sea-saw-frontend | 前端应用 |
| `/api/` | sea-saw-backend | API 接口 |
| `/admin/` | sea-saw-backend | Django Admin |
| `/static/` | volume (backend static) | Django 静态文件 |
| `/media/` | volume (backend media) | 用户上传文件 |
| `/health/` | sea-saw-backend | 健康检查 |

---

**维护者**: DevOps Team
**最后更新**: 2026-01-28
