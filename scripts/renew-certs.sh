#!/usr/bin/env sh
# 续期（可配合 cron：0 3 * * * cd /path/apinginx && ./scripts/renew-certs.sh）
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

docker compose run --rm certbot renew \
  --webroot -w /var/www/certbot \
  --quiet

docker compose exec nginx nginx -s reload
