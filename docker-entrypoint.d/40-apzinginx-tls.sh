#!/bin/sh
set -e

# 无证书：仅 80（ACME webroot + 站点），便于首次 certbot 签发。
# 有证书：80 跳转 HTTPS + 443 TLS。

SSL_DIR=/etc/letsencrypt/live/api.zxai.app
HTTP_CONF=/etc/nginx/conf.d/10-api.zxai.app.http.conf
HTTPS_CONF=/etc/nginx/conf.d/20-api.zxai.app.https.conf

if [ -r "$SSL_DIR/fullchain.pem" ] && [ -r "$SSL_DIR/privkey.pem" ]; then
  echo "apinginx: TLS cert found, enabling HTTPS."
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
  cat >"$HTTPS_CONF" <<'EOF'
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
    root /usr/share/nginx/html;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    location /health {
        access_log off;
        default_type text/plain;
        return 200 'ok';
    }
}
EOF
else
  echo "apinginx: no TLS cert yet; HTTP only (use certbot, then reload nginx)."
  rm -f "$HTTPS_CONF"
  cat >"$HTTP_CONF" <<'EOF'
server {
    listen 80;
    server_name api.zxai.app;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }
    root /usr/share/nginx/html;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    location /health {
        access_log off;
        default_type text/plain;
        return 200 'ok';
    }
}
EOF
fi
