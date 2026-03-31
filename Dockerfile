FROM nginx:1.27-alpine

RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker-entrypoint.d/40-apzinginx-tls.sh /docker-entrypoint.d/40-apzinginx-tls.sh
RUN chmod +x /docker-entrypoint.d/40-apzinginx-tls.sh

COPY html/ /usr/share/nginx/html/

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
