#!/bin/sh
set -e

# 无证书：仅 80（ACME webroot + 反代），便于首次 certbot 签发。
# 有证书：80 跳转 HTTPS + 443 TLS。
# 上游地址用环境变量 APIS_UPSTREAM（不要用 127.0.0.1，那是容器「自己」）。

SSL_DIR=/etc/letsencrypt/live/api.zxai.app
HTTP_CONF=/etc/nginx/conf.d/10-api.zxai.app.http.conf
HTTPS_CONF=/etc/nginx/conf.d/20-api.zxai.app.https.conf

APIS_UPSTREAM="${APIS_UPSTREAM:-http://new-api:3000}"

if [ -r "$SSL_DIR/fullchain.pem" ] && [ -r "$SSL_DIR/privkey.pem" ]; then
  echo "apinginx: TLS cert found, enabling HTTPS. APIS_UPSTREAM=$APIS_UPSTREAM"
  cat >"$HTTP_CONF" <<'EOF'
server {
    listen 80;
    server_name api.zxai.app;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}
EOF
  sed "s|__APIS_UPSTREAM__|${APIS_UPSTREAM}|g" >"$HTTPS_CONF" <<'EOF'
server {
    listen 443 ssl;
    http2 on;
    server_name api.zxai.app;
    ssl_certificate     /etc/letsencrypt/live/api.zxai.app/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.zxai.app/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass __APIS_UPSTREAM__;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /health {
        access_log off;
        default_type text/plain;
        return 200 'ok';
    }
}
EOF
else
  echo "apinginx: no TLS cert yet; HTTP only. APIS_UPSTREAM=$APIS_UPSTREAM"
  rm -f "$HTTPS_CONF"
  sed "s|__APIS_UPSTREAM__|${APIS_UPSTREAM}|g" >"$HTTP_CONF" <<'EOF'
server {
    listen 80;
    server_name api.zxai.app;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }
    location / {
        proxy_pass __APIS_UPSTREAM__;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    location /health {
        access_log off;
        default_type text/plain;
        return 200 'ok';
    }
}
EOF
fi
