[中文](README.md) | [English](README.en-US.md)


> 感谢您的支持与鼓励！如果您喜欢这个开源项目，不妨给它点个⭐️⭐️⭐️，您的星星是我们前进的动力 🙏🙏🙏

`bbs-go` 是一个轻量级社区和问答平台，适合搭建论坛、知识库和讨论社区。

## 官网

- 官网：[https://bbs-go.com](https://bbs-go.com)
- 交流社区：[https://bbs.bbs-go.com](https://bbs.bbs-go.com)
- Github：[https://github.com/mlogclub/bbs-go](https://github.com/mlogclub/bbs-go)
- Gitee：[https://gitee.com/mlogclub/bbs-go](https://gitee.com/mlogclub/bbs-go)

## 演示

- 前台: https://bbs.bbs-go.com
- 后台: https://bbs.bbs-go.com/dashboard
- 后台账号密码: 联系我们获取，联系方式：<https://bbs-go.com/docs/contact>

## Docker Compose 快速开始

bbs-go 提供官方 Docker 镜像，并提供内置 MySQL 或 PostgreSQL 的 Docker Compose 部署方式。

MySQL：

```bash
curl -fsSL https://raw.githubusercontent.com/mlogclub/bbs-go/master/docker-compose.yml -o docker-compose.yml
docker compose up -d
```

PostgreSQL：

```bash
curl -fsSL https://raw.githubusercontent.com/mlogclub/bbs-go/master/docker-compose.postgresql.yml -o docker-compose.yml
docker compose up -d
```

启动后访问：

- 前台：<http://localhost:3000>
- 后台：<http://localhost:3000/dashboard>
- 安装向导：<http://localhost:3000/install>

## CI/CD 与自动化部署

构建在 GitHub Actions 云端完成，香港服务器只拉取镜像运行，不在服务器上编译（2核4G 上 `docker build` 容易资源不足）。

| 环节 | 说明 |
|------|------|
| 触发时机 | 推送代码到 `master` 分支、推送 `v*` 版本 tag，或手动 `workflow_dispatch` |
| 构建位置 | GitHub Actions（ubuntu-latest，复用根目录 `Dockerfile` 多阶段构建） |
| 产物去向 | GHCR `ghcr.io/creeper-scr/bbs-vivalavita`：分支构建生成 `latest` 和 `sha-<short-commit>`，版本 tag 另生成 `v4.4.5`、`4.4.5` |
| 服务器部署 | 不构建，拉取镜像后只重建 `bbs-go` 容器 |
| 数据 | PostgreSQL 命名卷 + `/opt/bbs-go/docker-data-postgresql/` 宿主机目录，更新时原样保留 |

### 1. 推送代码，自动构建镜像

```bash
git push origin master
```

在仓库 Actions 页等待构建绿勾，GHCR 中的 `latest` 即更新。工作流已启用 Buildx 的 GHA 层缓存：首次冷构建约 3 分钟（Public 仓库的 4 vCPU runner），之后只重建改动层。

仓库为 Private 时，GitHub 使用 **2 vCPU / 8 GB** 的标准 runner，并消耗套餐包含的 Actions 分钟数，构建会比 Public 仓库慢一些；CI 推送镜像使用 `GITHUB_TOKEN`，不需要额外 PAT。

镜像包与源码仓库的可见性相互独立：当前 GHCR 包是 **Public**，服务器仍可匿名拉取。若包被改为 Private，在服务器执行一次 `docker login ghcr.io`（PAT 勾选 `read:packages`）即可。

### 2. 服务器首次上线（只做一次）

仓库是 Private，推荐在服务器配置一个**只读 Deploy Key**，之后直接 `git clone` / `git pull`，不用反复传文件。服务器需已安装 Docker、`docker compose` 插件和 `git`。

在服务器执行：

```bash
sudo apt update && sudo apt install -y git
sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh
sudo ssh-keygen -t ed25519 -C "bbs-go-deploy" -f /root/.ssh/bbs_go_deploy -N ""
sudo cat /root/.ssh/bbs_go_deploy.pub
```

复制输出的公钥，到 GitHub 仓库 `Settings → Deploy keys → Add deploy key` 添加，保持只读（不要勾选 Allow write access）。

配置 root 的 SSH（`/root/.ssh/config` 已有内容时手动追加这段 Host）：

```bash
sudo tee -a /root/.ssh/config >/dev/null <<'EOF'

Host github.com
  HostName github.com
  User git
  IdentityFile /root/.ssh/bbs_go_deploy
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
sudo chmod 600 /root/.ssh/config
```

克隆并准备运行目录：

```bash
sudo mkdir -p /opt/bbs-go
sudo git clone git@github.com:creeper-scr/bbs-vivalavita.git /opt/bbs-go/repo
sudo cp /opt/bbs-go/repo/deploy/docker-compose.yml /opt/bbs-go/docker-compose.yml
sudo cp -r /opt/bbs-go/repo/deploy/caddy /opt/bbs-go/caddy
sudo cp /opt/bbs-go/repo/deploy/env.example /opt/bbs-go/.env
sudo nano /opt/bbs-go/.env   # 设置数据库强密码与 BBSGO_DOMAIN；数据库卷初始化后密码不可再改
sudo bash /opt/bbs-go/repo/deploy/remote-deploy.sh
```

如果服务器不是 root 用户（如 `ubuntu`），把上面的 `/root/.ssh` 换成 `~/.ssh`，并把 `/opt/bbs-go` 的写权限或文件属主调好。

GHCR 包当前是 Public，可直接拉取；若改为 Private：

```bash
echo "$PAT" | sudo docker login ghcr.io -u creeper-scr --password-stdin
```

前提：`BBSGO_DOMAIN` 的 A/AAAA 记录已指向服务器，安全组/防火墙放行 **80/tcp、443/tcp、443/udp**。脚本首次运行会启动 PostgreSQL、bbs-go 和 Caddy，并等待 bbs-go 健康检查通过；Caddy 随后自动申请 HTTPS 证书。然后访问 `https://<BBSGO_DOMAIN>/install` 完成安装向导（`3000` 只绑定服务器本机，公网不暴露）；安装令牌在：

```bash
sudo cat /opt/bbs-go/docker-data-postgresql/data/setup-token.txt
```

安装完成后 `installed: true` 会写入 `/opt/bbs-go/docker-data-postgresql/data/bbs-go.yaml`，此后不会再进入安装流程。数据目录（`data/`、`logs/`、`uploads/`）由容器首次启动时创建在 `/opt/bbs-go/docker-data-postgresql/` 下。

### 3. 日常更新（一行命令）

推送代码并等 Actions 构建完成后，在服务器执行：

```bash
sudo bash /opt/bbs-go/repo/deploy/remote-deploy.sh
```

脚本依次完成：校验 compose → 拉取 `${BBSGO_IMAGE:-latest}` → 只重建 `bbs-go` 容器（首次部署才连同 PostgreSQL 一起启动）→ 健康检查（最多 90 秒），失败时输出容器日志。PostgreSQL 容器、数据卷和宿主机目录都不会被改动，因此用户、帖子、上传文件与安装状态都保留，不会重新出现安装向导。

日常只更新镜像时不需要 `git pull`。只有 compose、Caddyfile 或部署脚本本身变化时才同步：

```bash
sudo git -C /opt/bbs-go/repo pull --ff-only
sudo cp /opt/bbs-go/repo/deploy/docker-compose.yml /opt/bbs-go/docker-compose.yml
sudo cp -r /opt/bbs-go/repo/deploy/caddy/. /opt/bbs-go/caddy/
```

Caddy 容器只在首次部署时启动，应用更新不会重启它。修改 `/opt/bbs-go/caddy/Caddyfile` 后应用配置：

```bash
sudo docker compose -f /opt/bbs-go/docker-compose.yml exec caddy \
  caddy reload --config /etc/caddy/Caddyfile
```

### 3.1 反向代理与 Brotli 压缩

`deploy/docker-compose.yml` 内置 Caddy，负责 HTTPS 与压缩，bbs-go 只监听容器网络和服务器本机的 `127.0.0.1:3000`：

- Caddy 镜像由 GitHub Actions 构建（`ghcr.io/creeper-scr/bbs-vivalavita:caddy`，与主镜像同一个 GHCR 包），官方 `caddy:2` 不含 Brotli，这里通过 `xcaddy` 打入 `github.com/ueffel/caddy-brotli`。
- Caddyfile 使用 `encode br zstd gzip`：支持 Brotli 的客户端优先 `br`，其余回退 `zstd`/`gzip`。
- 证书和 ACME 账户保存在 `bbs-go_caddy-data`、`bbs-go_caddy-config` 命名卷，重建容器不会重新签发。

验证响应确实使用 Brotli：

```bash
curl -sI -H 'Accept-Encoding: br' https://<BBSGO_DOMAIN>/ | grep -i '^content-encoding'
# 期望：content-encoding: br
```

### 4. 回滚

```bash
# 用上一个正常构建的镜像 tag 重新部署（tag 可在 GHCR 包版本或 Actions 记录中找到）
sudo BBSGO_IMAGE=ghcr.io/creeper-scr/bbs-vivalavita:sha-<short-commit> \
  bash /opt/bbs-go/repo/deploy/remote-deploy.sh

# 回到最新版本
sudo bash /opt/bbs-go/repo/deploy/remote-deploy.sh
```

### 5. 数据保存位置

| 数据 | 位置 | 更新/重建容器 |
|------|------|---------------|
| 用户、帖子、评论、系统配置 | Docker 卷 `bbs-go_postgresql-data` | 保留 |
| 安装状态、`idCodec` 密钥 | `/opt/bbs-go/docker-data-postgresql/data/bbs-go.yaml` | 保留 |
| 上传的图片/附件 | `/opt/bbs-go/docker-data-postgresql/uploads` | 保留 |
| 运行日志 | `/opt/bbs-go/docker-data-postgresql/logs` | 保留 |
| Caddy 证书/ACME 账户 | Docker 卷 `bbs-go_caddy-data`、`bbs-go_caddy-config` | 保留 |

`deploy/docker-compose.yml` 顶层写了 `name: bbs-go`，卷名不会因目录改名而漂移。

### 6. 会丢数据或重新触发安装的操作

- `docker compose down -v`、`docker volume rm bbs-go_postgresql-data`、`docker system prune --volumes`：删除数据库卷；同时会删掉 Caddy 证书卷，触发重新签发（Let's Encrypt 有频率限制）。
- 删除或替换 `/opt/bbs-go/docker-data-postgresql`：丢失安装配置和上传文件，下次启动会重新生成 `installed: false` 的配置并进入安装流程。
- 数据库卷初始化后再修改 `.env` 中的 `BBSGO_DOCKER_POSTGRESQL_*`：应用按新密码连库会失败；需先在 PostgreSQL 内改密码。
- 把 `docker-compose.yml` 移到另一个目录后重新 `up`：相对路径 `./docker-data-postgresql` 指向新目录，等于空安装。

备份数据库与文件：

```bash
# 用户名/库名按 /opt/bbs-go/.env 中的配置调整
sudo docker exec bbs-go-postgresql pg_dump -U bbsgo bbsgo | gzip > /opt/bbs-go/backup-db-$(date +%F).sql.gz
sudo tar czf /opt/bbs-go/backup-files-$(date +%F).tar.gz \
  -C /opt/bbs-go docker-data-postgresql/data docker-data-postgresql/uploads
```

## 为什么选择 bbs-go

- **开箱可用**：论坛、问答、文章、评论、点赞收藏、关注消息等核心社区能力可直接使用。
- **轻量完整**：适合搭建论坛、知识库、问答社区和讨论社区，不需要引入沉重的企业级系统。
- **增长闭环**：内置任务、积分、等级、勋章，支持用户活跃和长期留存。
- **运营友好**：提供内容治理、用户治理、权限治理与系统配置能力，方便持续运营。
- **双语支持**：内置 `en-US` / `zh-CN`，适合面向不同语言用户的社区场景。

## 功能地图

![bbs-go 功能概览](docs/images/features_zh.svg)

## 核心功能

### 用户侧

- 账号注册与登录（支持多种登录方式）
- 用户资料维护与个人主页展示
- 关注/粉丝关系管理
- 站内消息与互动提醒
- 积分记录与排行榜

### 内容侧

- 支持帖子、动态、文章发布与编辑
- 评论、回复、点赞、收藏等完整互动链路
- 标签与节点管理，便于内容组织和发现
- 支持投票、隐藏内容等互动玩法
- 站内搜索能力，提升内容检索效率

### 增长侧

- 每日签到，持续活跃激励
- 任务体系（新手、每日、成就）
- 积分与经验奖励机制
- 等级成长配置
- 勋章与荣誉体系

### 运营侧

- 用户、帖子、评论、文章等统一治理
- 举报处理与违禁词管理
- 角色、菜单、接口权限分配
- 系统参数与站点配置管理
- 运营日志与行为留痕

## 适用场景

- 技术交流社区
- 问答社区
- 知识库
- 兴趣爱好社群
- 产品用户社区
- 企业内部知识社区
- 内容型会员社区

## 和同类产品对比

以下对比基于公开产品定位和常见使用场景。实际选择仍取决于团队技术栈、部署方式、社区规模和运营目标。

| 产品 | 更适合 | 主要优势 | bbs-go 更适合的情况 |
| ---- | ------ | -------- | ------------------- |
| Discourse | 成熟大型社区和复杂治理流程 | 生态成熟、审核治理能力强、支持托管和自托管 | 希望使用更轻量的自托管平台、偏好 Go 技术栈，并需要论坛 + 问答 + 知识发布一体化能力 |
| Flarum | 简洁现代的论坛社区，尤其适合 PHP 技术栈团队 | 界面简洁、核心轻量、扩展生态灵活 | 需要更完整的后台运营、问答流程、文章知识沉淀和用户成长激励，不希望大量依赖扩展拼装 |
| NodeBB | 实时互动论坛，以及偏好 Node.js 技术栈的团队 | 实时互动体验、现代论坛界面、移动端体验较好 | 更偏好 Go 后端、轻量自托管部署和后台运营模型，而不是以实时互动作为核心卖点 |
| Question2Answer | 纯问答网站 | 问答模型聚焦、支持积分排行、PHP/MySQL 部署简单 | 除了问答，还需要论坛讨论、文章知识库、内容治理、成员运营和长期社区激励 |

## 联系我

### Discord

<https://discord.gg/TnzcSqKZyn>

### 邮箱

<mlog1@qq.com>

### QQ群

![BBS-GO用户交流群](docs/images/qq.png)

### 微信

![微信](docs/images/wechat.png)

## 付费服务

付费是为了项目能够更好的生存下去，请谅解。项目将一如既往的开源下去~

| 服务     | 价格   | 服务内容                                         |
| -------- | ------ | ------------------------------------------------ |
| 商用授权 | ￥1628 | 提供 bbs-go 商业使用授权                         |
| 功能定制 | 面议   | 接受各种功能定制，只有你想不到的没有我们做不到的 |

## bbs-go 是什么

`bbs-go` 是一个轻量级社区和问答平台，适合搭建论坛、知识库和讨论社区。

一句话概括：**轻量搭建论坛、问答、知识库和讨论社区**。
