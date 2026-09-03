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
# Nuxt SSR 必须保留 Nitro 服务端产物; .output/public 是指向 html 的 symlink, 两端共用静态资源.
COPY --chown=blog-server:blog-server --from=client-artifacts /app/.output /app/.output
# 新版客户端只提供 nginx 模板, single 在运行时按本机端口和域名渲染最终配置.
COPY --from=client-artifacts /etc/nginx/nginx.conf.template /opt/blog-client/nginx.conf.template
COPY --from=client-artifacts /etc/nginx/redirects.map /opt/blog-client/redirects.map
# nginx.conf.template 通过相对路径引用 mime.types, 初始化持久化配置目录时必须一并带入.
COPY --from=client-artifacts /etc/nginx/mime.types /opt/blog-client/mime.types

# rootfs 按容器绝对路径组织, 这里直接复制到 / 后, rootfs/usr/local/bin/blog-entrypoint.sh 会落到镜像内 /usr/local/bin/blog-entrypoint.sh.
COPY single/docker/rootfs/ /

RUN chmod +x /usr/local/bin/blog-entrypoint.sh /home/blog-server/blog-server /home/blog-server/boot

VOLUME ["/data"]

EXPOSE 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD ["/bin/bash", "-lc", "curl -fsS --max-time 5 http://127.0.0.1:${BLOG_SERVER_PORT:-5426}/api/v1/is-setup | grep -q 'request_id' && curl -kfsS --max-time 5 https://127.0.0.1:${BLOG_HTTPS_PORT:-443}/nginx-health >/dev/null"]

ENTRYPOINT ["/usr/local/bin/blog-entrypoint.sh"]