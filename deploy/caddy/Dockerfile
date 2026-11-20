# syntax=docker/dockerfile:1.7
#
# 官方 caddy:2 不带 Brotli 编码器，这里用 xcaddy 打入纯 Go 实现
# github.com/ueffel/caddy-brotli，提供 `br` 编码。
#
# 由 .github/workflows/docker-image.yml 构建并推送到
# ghcr.io/creeper-scr/bbs-vivalavita:caddy（与主镜像同一个 GHCR 包）。

FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/ueffel/caddy-brotli@v1.7.0

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN caddy version && caddy list-modules | grep -q 'http.encoders.br'
