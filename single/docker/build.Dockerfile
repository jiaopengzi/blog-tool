# blog 单镜像应用装配 Dockerfile
# 1. 直接消费 blog-client 与 blog-server 输入镜像, 并兼容 SPA 和 Nuxt SSR 客户端产物.

ARG CLIENT_IMAGE=jiaopengzi/blog-client:latest
ARG SERVER_IMAGE=jiaopengzi/blog-server:latest
ARG BLOG_ENV_IMAGE=blog:env

FROM ${CLIENT_IMAGE} AS client-artifacts

# 将旧 SPA 和新版 Nuxt SSR 的产物整理为统一目录, 避免最终阶段依赖某一代客户端的镜像布局.
RUN set -eux; \
    mkdir -p /single-client; \
    cp -a /usr/share/nginx/html /single-client/html; \
    if [ -f /app/.output/server/index.mjs ]; then \
    cp -a /app/.output /single-client/.output; \
    client_runtime="nuxt"; \
    else \
    mkdir -p /single-client/.output; \
    client_runtime="spa"; \
    fi; \
    if [ -f /etc/nginx/nginx.conf.template ]; then \
    cp -a /etc/nginx/nginx.conf.template /single-client/nginx.conf.template; \
    else \
    test -f /etc/nginx/nginx.conf; \
    cp -a /etc/nginx/nginx.conf /single-client/nginx.conf.template; \
    fi; \
    if [ -f /etc/nginx/redirects.map ]; then \
    cp -a /etc/nginx/redirects.map /single-client/redirects.map; \
    else \
    : > /single-client/redirects.map; \
    fi; \
    test -f /etc/nginx/mime.types; \
    cp -a /etc/nginx/mime.types /single-client/mime.types; \
    printf '%s\n' "$client_runtime" > /single-client/runtime

FROM ${SERVER_IMAGE} AS server-artifacts

FROM ${BLOG_ENV_IMAGE}

COPY --chown=blog-server:blog-server --from=server-artifacts /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --chown=blog-server:blog-server --from=server-artifacts /usr/local/bin/ffprobe /usr/local/bin/ffprobe

COPY --chown=blog-server:blog-server --from=server-artifacts /home/blog-server /home/blog-server

COPY --chown=blog-server:blog-server --from=client-artifacts /single-client/html /usr/share/nginx/html
# SPA 使用空目录, Nuxt SSR 保留 Nitro 服务端产物; .output/public 是指向 html 的 symlink, 两端共用静态资源.
COPY --chown=blog-server:blog-server --from=client-artifacts /single-client/.output /app/.output
# 单镜像运行时按本机端口和域名渲染最终 nginx 配置; SPA 的 nginx.conf 已在上方归一化为模板.
COPY --from=client-artifacts /single-client/nginx.conf.template /opt/blog-client/nginx.conf.template
COPY --from=client-artifacts /single-client/redirects.map /opt/blog-client/redirects.map
# nginx.conf.template 通过相对路径引用 mime.types, 初始化持久化配置目录时必须一并带入.
COPY --from=client-artifacts /single-client/mime.types /opt/blog-client/mime.types
COPY --from=client-artifacts /single-client/runtime /opt/blog-client/runtime

# rootfs 按容器绝对路径组织, 这里直接复制到 / 后, rootfs/usr/local/bin/blog-entrypoint.sh 会落到镜像内 /usr/local/bin/blog-entrypoint.sh.
COPY single/docker/rootfs/ /

RUN chmod +x /usr/local/bin/blog-entrypoint.sh /home/blog-server/blog-server /home/blog-server/boot

VOLUME ["/data"]

EXPOSE 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD ["/bin/bash", "-lc", "curl -fsS --max-time 5 http://127.0.0.1:${BLOG_SERVER_PORT:-5426}/api/v1/is-setup | grep -q 'request_id' && curl -kfsS --max-time 5 https://127.0.0.1:${BLOG_HTTPS_PORT:-443}/nginx-health >/dev/null"]

ENTRYPOINT ["/usr/local/bin/blog-entrypoint.sh"]