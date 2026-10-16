# syntax=docker/dockerfile:1

# nginx in front of Fontra and django-robo-cjk. It terminates TLS for both.
FROM nginx:1.30-alpine

# openssl creates the self-signed fallback certificate.
RUN apk add --no-cache openssl \
    && rm /etc/nginx/conf.d/default.conf

COPY fontra.conf.template /etc/nginx/templates/fontra.conf.template
COPY --chmod=755 40-fontra-certificate.sh /docker-entrypoint.d/40-fontra-certificate.sh

# Exposes the container's DNS server to the template as NGINX_LOCAL_RESOLVERS.
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1
