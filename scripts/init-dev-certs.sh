#!/usr/bin/env sh
# 生成本地自签证书，目录结构与 certbot 一致，供本地 HTTPS 调试。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE="$ROOT/dev-certs/live/api.zxai.app"
mkdir -p "$LIVE"
openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
  -keyout "$LIVE/privkey.pem" \
  -out "$LIVE/fullchain.pem" \
  -subj "/CN=api.zxai.app"
echo "Wrote $LIVE/{fullchain.pem,privkey.pem}"
