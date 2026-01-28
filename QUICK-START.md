# 快速开始指南

Sea-Saw Gateway 5分钟快速部署指南。

## 前置条件

- ✅ Docker 和 Docker Compose 已安装
- ✅ 有访问腾讯云容器镜像服务 (TCR) 的权限
- ✅ 前端和后端镜像已推送到 TCR

## 步骤 1: 克隆仓库

```bash
git clone https://github.com/your-org/sea-saw-gateway.git
cd sea-saw-gateway
```

## 步骤 2: 初始化配置

```bash
# 创建配置文件
./deploy.sh init

# 这将创建:
# - config/backend.env  (从 backend.env.example 复制)
# - config/postgres.env (从 postgres.env.example 复制)
```

## 步骤 3: 编辑配置

### 编辑后端配置

```bash
vim config/backend.env
```

**必须修改的配置项**:
```env
SECRET_KEY=<生成一个强随机密钥>
DJANGO_ALLOWED_HOSTS=localhost your-domain.com your-server-ip
SQL_PASSWORD=<设置数据库密码>
```

### 编辑数据库配置

```bash
vim config/postgres.env
```

**必须修改的配置项**:
```env
POSTGRES_PASSWORD=<与 backend.env 中的 SQL_PASSWORD 相同>
```

## 步骤 4: 登录容器镜像服务

```bash
# 方式 1: 使用环境变量
export TCR_USERNAME=your-username
export TCR_PASSWORD=your-password
./deploy.sh pull

# 方式 2: 手动登录
docker login hkccr.ccs.tencentyun.com -u your-username
./deploy.sh pull
```

## 步骤 5: 启动服务

```bash
./deploy.sh up
```

这将启动所有服务:
- Frontend (前端)
- Backend (后端)
- Gateway (网关)
- PostgreSQL (数据库)
- Redis (缓存)
- Celery Worker (任务队列)
- Celery Beat (定时任务)
- Flower (任务监控)

## 步骤 6: 创建管理员账户

```bash
docker compose exec backend python manage.py createsuperuser
```

按提示输入:
- 用户名
- 邮箱
- 密码

## 步骤 7: 访问应用

- **前端应用**: http://localhost 或 http://your-server-ip
- **后端 API**: http://localhost/api/
- **管理后台**: http://localhost/admin/
- **Celery 监控**: http://localhost:5555

## 验证部署

```bash
# 检查服务状态
./deploy.sh status

# 应该看到所有服务都是 "healthy" 或 "running"

# 检查日志
./deploy.sh logs

# 测试 API
curl http://localhost/health/
# 应该返回: healthy
```

## 常见问题

### 端口 80 被占用

```bash
# 查看占用进程
sudo lsof -i :80

# 停止占用的服务
sudo systemctl stop nginx  # 如果是系统 nginx
sudo systemctl stop apache2  # 如果是 Apache
```

### 镜像拉取失败

```bash
# 检查网络连接
ping hkccr.ccs.tencentyun.com

# 检查登录状态
docker login hkccr.ccs.tencentyun.com -u your-username

# 手动拉取测试
docker pull hkccr.ccs.tencentyun.com/sea-saw/frontend:latest
docker pull hkccr.ccs.tencentyun.com/sea-saw/backend:latest
docker pull hkccr.ccs.tencentyun.com/sea-saw/gateway:latest
```

### 数据库连接失败

确保 `config/backend.env` 和 `config/postgres.env` 中的密码一致:

```bash
# 检查配置
grep SQL_PASSWORD config/backend.env
grep POSTGRES_PASSWORD config/postgres.env

# 应该显示相同的密码
```

### 服务启动失败

```bash
# 查看详细日志
./deploy.sh logs backend
./deploy.sh logs db

# 重新启动
./deploy.sh restart
```

## 下一步

- 📖 阅读完整文档: [README.md](./README.md)
- 🔒 配置 HTTPS: 参考 SSL 配置章节
- 📊 设置监控和告警
- 💾 配置定期备份

## 获取帮助

- 查看日志: `./deploy.sh logs`
- 检查状态: `./deploy.sh status`
- 查看帮助: `./deploy.sh help`
- 提交 Issue: [GitHub Issues](https://github.com/your-org/sea-saw-gateway/issues)

---

**预计时间**: 5-10 分钟
**难度**: ⭐⭐ (中等)
