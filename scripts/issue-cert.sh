#!/usr/bin/env sh
# 首次申请 Let's Encrypt（HTTP-01，依赖已启动的 nginx + webroot）。
# 用法：export CERTBOT_EMAIL=你的邮箱 && ./scripts/issue-cert.sh
# 测试配额：export LE_STAGING=1
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EMAIL="${CERTBOT_EMAIL:?请设置环境变量 CERTBOT_EMAIL（Let's Encrypt 账户邮箱）}"
STAGING_ARGS=""
if [ "${LE_STAGING:-}" = "1" ] || [ "${LE_STAGING:-}" = "true" ]; then
  STAGING_ARGS="--staging"
  echo "Using Let's Encrypt STAGING (not publicly trusted)."
fi

docker compose run --rm certbot certonly \
  $STAGING_ARGS \
  --webroot -w /var/www/certbot \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  -d api.zxai.app

# 必须 restart：entrypoint 才会写入 443 配置（reload 不会重跑 entrypoint）
docker compose restart nginx
echo "Certificate issued. Nginx restarted with HTTPS."
