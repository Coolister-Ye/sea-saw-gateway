# Sea-Saw CRM Gateway

**纯反向代理网关**，为 Sea-Saw CRM 系统提供统一入口。

## 🏗️ 架构说明

这是 Sea-Saw CRM 的三个独立 Git 仓库之一：

```
GitHub 仓库架构:
├── sea-saw-app         前端仓库 (React Native/Expo)
├── sea-saw-server      后端仓库 (Django)
└── sea-saw-gateway     网关仓库 (Nginx) ← 当前仓库
```

### 核心原则：纯反向代理

```
┌─────────────────────────────────────────────────────┐
│              sea-saw-gateway                        │
│         (ONLY Nginx Reverse Proxy)                  │
│                    :80                              │
└─────────────┬───────────────────┬───────────────────┘
              │                   │
        /api/, /admin/        所有其他请求
        /static/, /media/        │
              │                   │
              ▼                   ▼
    ┌──────────────────┐  ┌─────────────────┐
    │ sea-saw-backend  │  │ sea-saw-frontend│
    │  (独立部署)      │  │  (独立部署)     │
    │      :8000       │  │      :80        │
    └──────────────────┘  └─────────────────┘

所有服务通过共享 Docker network 互联：sea-saw-network
```

### 服务器部署结构

```
~/sea-saw/
├── backend/            sea-saw-server 独立部署
│   └── docker-compose.prod.yml  (backend, db, redis, celery)
├── frontend/           sea-saw-app 独立部署
│   └── docker-compose.yml       (frontend only)
└── gateway/            sea-saw-gateway 独立部署
    ├── docker-compose.yml       (nginx only)
    └── nginx.conf               (routing config)
```

### 流量路由

```
Internet (80/443)
       ↓
   Gateway Nginx (sea-saw-gateway)
   ├── /              → proxy_pass http://sea-saw-frontend/
   ├── /api/          → proxy_pass http://sea-saw-backend:8000/
   ├── /admin/        → proxy_pass http://sea-saw-backend:8000/
   ├── /static/       → volume mount (backend static)
   └── /media/        → volume mount (backend media)
```

## 🚀 快速开始

### 前置要求

- Docker >= 20.10
- Docker Compose >= 2.0
- 访问腾讯云容器镜像服务 (TCR)

### 1. 初始化配置

```bash
# 克隆仓库
git clone https://github.com/your-org/sea-saw-gateway.git
cd sea-saw-gateway

# 创建配置文件
./deploy.sh init

# 编辑配置
vim config/backend.env      # 后端环境变量
vim config/postgres.env     # 数据库配置
```

### 2. 登录容器镜像服务

```bash
# 设置环境变量
export TCR_USERNAME=your-username
export TCR_PASSWORD=your-password

# 或者手动登录
docker login hkccr.ccs.tencentyun.com
```

### 3. 启动服务

```bash
# 拉取最新镜像
./deploy.sh pull

# 启动所有服务
./deploy.sh up

# 检查状态
./deploy.sh status
```

### 4. 访问应用

- **前端**: http://localhost
- **后端 API**: http://localhost/api/
- **管理后台**: http://localhost/admin/
- **Celery 监控**: http://localhost:5555

## 📋 命令参考

```bash
./deploy.sh init        # 初始化配置文件
./deploy.sh pull        # 拉取最新镜像
./deploy.sh up          # 启动服务
./deploy.sh down        # 停止服务
./deploy.sh restart     # 重启服务
./deploy.sh logs        # 查看日志
./deploy.sh status      # 检查状态
./deploy.sh backup      # 备份数据库
./deploy.sh restore     # 恢复数据库
./deploy.sh update      # 更新服务（拉取+重启+迁移）
./deploy.sh clean       # 清理旧资源
```

## 🔄 CI/CD 工作流

### 三仓库协作模式

每个仓库独立维护和部署：

1. **sea-saw-app** (前端仓库)
   - 构建前端应用
   - 打包到 Docker 镜像
   - 推送到 TCR: `hkccr.ccs.tencentyun.com/sea-saw/frontend:latest`

2. **sea-saw-server** (后端仓库)
   - 构建后端应用
   - 打包到 Docker 镜像
   - 推送到 TCR: `hkccr.ccs.tencentyun.com/sea-saw/backend:latest`

3. **sea-saw-gateway** (当前仓库)
   - 构建网关镜像
   - 推送到 TCR: `hkccr.ccs.tencentyun.com/sea-saw/gateway:latest`
   - 编排和启动所有服务

### 部署流程

```
前端推送代码 → 前端 CI/CD → 构建 frontend 镜像 → 推送到 TCR
后端推送代码 → 后端 CI/CD → 构建 backend 镜像 → 推送到 TCR
网关推送代码 → 网关 CI/CD → 构建 gateway 镜像 → 推送到 TCR → 更新服务器部署
```

### GitHub Secrets 配置

在 GitHub 仓库设置中添加以下 Secrets：

| Secret 名称 | 说明 |
|------------|------|
| `TCR_USERNAME` | 腾讯云容器镜像服务用户名 |
| `TCR_PASSWORD` | 腾讯云容器镜像服务密码 |
| `TENCENT_SERVER_IP` | 服务器公网 IP |
| `TENCENT_SERVER_USER` | 服务器登录用户名 |
| `TENCENT_SSH_PRIVATE_KEY` | SSH 私钥 |
| `GATEWAY_DEPLOY_PATH` | Gateway 部署路径 (如 `/home/sea-saw/sea-saw-gateway`) |

## 📁 项目结构

```
sea-saw-gateway/
├── .github/
│   └── workflows/
│       └── deploy-gateway.yml    # CI/CD workflow
├── config/
│   ├── backend.env.example       # 后端配置示例
│   └── postgres.env.example      # 数据库配置示例
├── nginx.conf                    # Nginx 配置
├── Dockerfile                    # Gateway 镜像构建
├── docker-compose.yml            # 服务编排
├── deploy.sh                     # 部署脚本
└── README.md                     # 本文档
```

## 🔧 配置说明

### nginx.conf

定义流量路由规则：
- 前端路由 (`/`)
- API 路由 (`/api/`, `/admin/`)
- 静态文件 (`/static/`, `/media/`)
- 速率限制和安全头

### docker-compose.yml

编排所有服务：
- `frontend`: 前端容器（从 TCR 拉取）
- `backend`: 后端容器（从 TCR 拉取）
- `gateway`: 网关容器（从 TCR 拉取或本地构建）
- `db`: PostgreSQL 数据库
- `redis`: Redis 缓存
- `celery_worker`: Celery 工作进程
- `celery_beat`: Celery 调度器
- `flower`: Celery 监控

### 环境变量

**config/backend.env**:
- Django 配置（DEBUG, SECRET_KEY, ALLOWED_HOSTS）
- 数据库连接
- Redis 连接
- Celery 配置

**config/postgres.env**:
- 数据库名称、用户名、密码

## 🔒 安全最佳实践

1. **密钥管理**
   - 使用强随机密钥
   - 定期轮换密码
   - 不要将敏感信息提交到 Git

2. **网络安全**
   - 只暴露必要的端口（80, 443, 5555）
   - 后端服务完全内部化
   - 配置防火墙规则

3. **HTTPS 配置**
   - 生产环境必须使用 HTTPS
   - 参考下方 SSL 配置指南

## 🌐 SSL/HTTPS 配置

### 使用 Let's Encrypt

```bash
# 安装 Certbot
sudo apt-get install certbot

# 获取证书
sudo certbot certonly --standalone -d yourdomain.com

# 更新 nginx.conf 添加 SSL 配置
# 更新 docker-compose.yml 挂载证书
# 重启服务
./deploy.sh restart
```

详细步骤请参考文档。

## 🔍 故障排查

### Gateway 无法启动

```bash
# 检查端口占用
sudo lsof -i :80

# 查看日志
./deploy.sh logs gateway

# 重新构建
docker compose build gateway
./deploy.sh restart
```

### 后端无法连接

```bash
# 检查后端状态
./deploy.sh logs backend

# 检查网络
docker network ls
docker network inspect sea-saw-network

# 重启后端
docker compose restart backend
```

### 数据库连接失败

```bash
# 检查数据库
./deploy.sh logs db

# 检查配置
cat config/postgres.env
cat config/backend.env

# 确保密码匹配
```

## 📊 监控和日志

### 查看日志

```bash
# 所有服务
./deploy.sh logs

# 特定服务
./deploy.sh logs gateway
./deploy.sh logs backend
./deploy.sh logs db
```

### 检查健康状态

```bash
# 服务状态
./deploy.sh status

# 详细检查
docker compose ps
docker stats
```

### Celery 监控

访问 http://your-server:5555 查看 Flower 界面。

## 🔄 更新流程

### 更新前端

前端仓库推送代码后自动构建新镜像。在服务器上：

```bash
cd /home/sea-saw/sea-saw-gateway
./deploy.sh pull
docker compose up -d frontend
```

### 更新后端

后端仓库推送代码后自动构建新镜像。在服务器上：

```bash
cd /home/sea-saw/sea-saw-gateway
./deploy.sh update  # 包含备份、拉取、重启、迁移
```

### 更新网关

网关仓库推送代码后自动触发部署（通过 GitHub Actions）。

## 💾 备份和恢复

### 数据库备份

```bash
# 创建备份
./deploy.sh backup

# 备份文件保存在 backups/ 目录
ls -lh backups/
```

### 数据库恢复

```bash
# 从最新备份恢复
./deploy.sh restore
```

## 🤝 贡献指南

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 📚 相关仓库

- [sea-saw-app](https://github.com/your-org/sea-saw-app) - 前端应用
- [sea-saw-server](https://github.com/your-org/sea-saw-server) - 后端应用

## 📄 许可证

MIT License

## 📧 联系方式

- Issue: [GitHub Issues](https://github.com/your-org/sea-saw-gateway/issues)
- Email: support@yourdomain.com

---

**维护者**: Sea-Saw Team
**最后更新**: 2024-01-27
