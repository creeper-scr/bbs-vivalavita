#!/usr/bin/env bash
#
# bbs-go 远程部署脚本（服务器侧执行）
#
# 前提：
#   - CI（GitHub Actions）已将最新镜像推送到 GHCR：
#     ghcr.io/creeper-scr/bbs-vivalavita:latest
#   - 服务器已有 /opt/bbs-go/docker-compose.yml（首次部署时从仓库 deploy/docker-compose.yml 复制）
#   - GHCR 包已设为 Public 时可匿名拉取；仍为 Private 时先执行：
#     echo "$PAT" | docker login ghcr.io -u <github-user> --password-stdin
#
# 用法：
#   bash /opt/bbs-go/repo/deploy/remote-deploy.sh
#
# 回滚到某个已构建的 sha tag：
#   BBSGO_IMAGE=ghcr.io/creeper-scr/bbs-vivalavita:sha-<commit> \
#     bash /opt/bbs-go/repo/deploy/remote-deploy.sh
#
# 该脚本在服务器上执行（不在 CI 中），由部署者手动触发，保证可控可回滚。
# 只重建 bbs-go 容器，不触碰 PostgreSQL 容器、命名卷和宿主机数据目录。

set -euo pipefail

DEPLOY_DIR=${BBSGO_DEPLOY_DIR:-/opt/bbs-go}
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
SERVICE="${BBSGO_COMPOSE_SERVICE:-bbs-go}"
IMAGE=${BBSGO_IMAGE:-ghcr.io/creeper-scr/bbs-vivalavita:latest}
# 让 compose 文件里的 ${BBSGO_IMAGE:-...} 与本次部署使用同一个镜像，
# 这样校验、拉取、重建三步不会各自解析出不同 tag。
export BBSGO_IMAGE="${IMAGE}"

log() {
  echo "[deploy] $(date '+%Y-%m-%d %H:%M:%S') $*"
}

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "错误：未找到 ${COMPOSE_FILE}，请检查 BBSGO_DEPLOY_DIR" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "错误：未安装 docker" >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "错误：未安装 docker compose 插件" >&2
  exit 1
fi

cd "${DEPLOY_DIR}"

log "开始部署 bbs-go（${IMAGE}）"

# 1. 校验 compose 文件与镜像一致性（先校验，避免白拉镜像）
log "校验 docker compose 配置"
docker compose -f "${COMPOSE_FILE}" config --quiet
COMPOSE_IMAGES=$(docker compose -f "${COMPOSE_FILE}" config --images)
if ! grep -qxF "${IMAGE}" <<<"${COMPOSE_IMAGES}"; then
  echo "错误：${COMPOSE_FILE} 使用的镜像与本次部署镜像不一致。" >&2
  echo "  期望：${IMAGE}" >&2
  echo "  实际：${COMPOSE_IMAGES}" >&2
  echo "请确认 compose 中 bbs-go 服务写的是 \${BBSGO_IMAGE:-...}，或通过 BBSGO_IMAGE 指定相同镜像。" >&2
  exit 1
fi

# 2. 拉取镜像
log "拉取镜像：${IMAGE}"
if ! docker pull "${IMAGE}"; then
  echo "错误：拉取 ${IMAGE} 失败。若该 GHCR 包仍是 Private，请先执行：" >&2
  echo "  echo \"\$PAT\" | docker login ghcr.io -u <github-user> --password-stdin" >&2
  echo "或将该包可见性改为 Public（GitHub → Packages → 包设置 → Change visibility）。" >&2
  exit 1
fi

# 3. 重建 bbs-go 容器
# 首次部署（或 Caddy 尚未启动）时必须完整启动；之后只重建 bbs-go，
# 不触碰 PostgreSQL/Caddy 容器，数据卷和 bind mount 原样保留。
if [[ -n "$(docker compose -f "${COMPOSE_FILE}" ps -q postgresql)" && -n "$(docker compose -f "${COMPOSE_FILE}" ps -q caddy)" ]]; then
  log "重建容器（保留现有 PostgreSQL 与 Caddy）"
  docker compose -f "${COMPOSE_FILE}" up -d --no-deps "${SERVICE}"
else
  log "首次部署：启动 bbs-go、PostgreSQL 与 Caddy"
  docker compose -f "${COMPOSE_FILE}" up -d
fi

CONTAINER_ID=""
for _ in $(seq 1 10); do
  CONTAINER_ID=$(docker compose -f "${COMPOSE_FILE}" ps -q "${SERVICE}")
  [[ -n "${CONTAINER_ID}" ]] && break
  sleep 1
done
if [[ -z "${CONTAINER_ID}" ]]; then
  echo "错误：未找到 ${SERVICE} 容器，请执行：docker compose -f ${COMPOSE_FILE} ps" >&2
  exit 1
fi

# 4. 健康检查（最多等 90 秒）
log "等待健康检查（最多 90 秒）"
for _ in $(seq 1 45); do
  STATUS=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${CONTAINER_ID}" 2>/dev/null || echo "unknown")
  if [[ "${STATUS}" == "healthy" ]]; then
    log "部署完成，bbs-go 状态 healthy"
    exit 0
  fi
  if [[ "${STATUS}" != "starting" && "${STATUS}" != "running" && "${STATUS}" != "unknown" ]]; then
    log "bbs-go 状态异常：${STATUS}"
    docker logs "${CONTAINER_ID}" --tail 50 || true
    exit 1
  fi
  sleep 2
done

log "健康检查超时，请查看容器日志：docker logs ${CONTAINER_ID} --tail 200"
docker logs "${CONTAINER_ID}" --tail 50 || true
exit 1
