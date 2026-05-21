# blog 单镜像应用装配 Dockerfile
# 1. 直接消费 jiaopengzi/blog-client 与 jiaopengzi/blog-server 的已发布镜像.

ARG CLIENT_IMAGE=jiaopengzi/blog-client:latest
ARG SERVER_IMAGE=jiaopengzi/blog-server:latest
ARG BLOG_ENV_IMAGE=blog:env

FROM ${CLIENT_IMAGE} AS client-artifacts

FROM ${SERVER_IMAGE} AS server-artifacts

FROM ${BLOG_ENV_IMAGE}

COPY --chown=blog-server:blog-server --from=server-artifacts /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --chown=blog-server:blog-server --from=server-artifacts /usr/local/bin/ffprobe /usr/local/bin/ffprobe

COPY --chown=blog-server:blog-server --from=server-artifacts /home/blog-server /home/blog-server

COPY --chown=blog-server:blog-server --from=client-artifacts /usr/share/nginx/html /usr/share/nginx/html
COPY --chown=blog-server:blog-server --from=client-artifacts /etc/nginx /etc/nginx

# rootfs 按容器绝对路径组织, 这里直接复制到 / 后, rootfs/usr/local/bin/blog-entrypoint.sh 会落到镜像内 /usr/local/bin/blog-entrypoint.sh.
COPY single/docker/rootfs/ /

RUN mkdir -p /opt/blog-client \
    && cp -a /etc/nginx /opt/blog-client/nginx-template \
    && chmod +x /usr/local/bin/blog-entrypoint.sh /home/blog-server/blog-server /home/blog-server/boot

VOLUME ["/data"]

EXPOSE 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD ["/bin/bash", "-lc", "curl -fsS --max-time 5 http://127.0.0.1:${BLOG_SERVER_PORT:-5426}/api/v1/is-setup | grep -q 'request_id' && curl -kfsS --max-time 5 https://127.0.0.1:${BLOG_HTTPS_PORT:-443}/nginx-health >/dev/null"]

ENTRYPOINT ["/usr/local/bin/blog-entrypoint.sh"]