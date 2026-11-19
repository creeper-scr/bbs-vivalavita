#!/usr/bin/env bash
#
# bbs-go 远程部署脚本（服务器侧执行）
#
# 前提：
#   - CI（GitHub Actions）已将最新镜像推送到 GHCR：
#     ghcr.io/creeper-scr/bbs-vivalavita:latest
#   - 服务器已有 /opt/bbs-go/docker-compose.yml（image 指向同一镜像）
#   - GHCR 包已设为 Public 时可匿名拉取；仍为 Private 时先执行：
#     echo "$PAT" | docker login ghcr.io -u <github-user> --password-stdin
#
# 用法：
#   bash /opt/bbs-go/repo/deploy/remote-deploy.sh
#
# 该脚本在服务器上执行（不在 CI 中），由部署者手动触发，保证可控可回滚。

set -euo pipefail

DEPLOY_DIR=${BBSGO_DEPLOY_DIR:-/opt/bbs-go}
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
IMAGE=${BBSGO_IMAGE:-ghcr.io/creeper-scr/bbs-vivalavita:latest}

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
  echo "请把 compose 中 bbs-go 服务的 image 改为 ${IMAGE}，或通过 BBSGO_IMAGE 指定相同镜像。" >&2
  exit 1
fi

# 2. 拉取最新镜像
log "拉取镜像：${IMAGE}"
if ! docker pull "${IMAGE}"; then
  echo "错误：拉取 ${IMAGE} 失败。若该 GHCR 包仍是 Private，请先执行：" >&2
  echo "  echo \"\$PAT\" | docker login ghcr.io -u <github-user> --password-stdin" >&2
  echo "或将该包可见性改为 Public（GitHub → Packages → 包设置 → Change visibility）。" >&2
  exit 1
fi

# 3. 滚动重建容器（仅当镜像变化时重建）
log "重建容器"
docker compose -f "${COMPOSE_FILE}" up -d --no-deps

# 4. 健康检查（最多等 90 秒）
log "等待健康检查（最多 90 秒）"
for _ in $(seq 1 45); do
  STATUS=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' bbs-go 2>/dev/null || echo "unknown")
  if [[ "${STATUS}" == "healthy" ]]; then
    log "部署完成，bbs-go 状态 healthy"
    exit 0
  fi
  if [[ "${STATUS}" != "starting" && "${STATUS}" != "running" && "${STATUS}" != "unknown" ]]; then
    log "bbs-go 状态异常：${STATUS}"
    docker logs bbs-go --tail 50 || true
    exit 1
  fi
  sleep 2
done

log "健康检查超时，请查看容器日志：docker logs bbs-go --tail 200"
exit 1
