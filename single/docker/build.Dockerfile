# blog 单镜像应用装配 Dockerfile
# 复用优先级:
# 1. 优先消费 blog-client/Dockerfile.dev 与 blog-server-dev/Dockerfile_dev 预热出的 build 镜像.
# 2. 未命中时回退消费 blog-client/Dockerfile.env 与 blog-server-dev/Dockerfile_golang 预热出的环境镜像.
# 3. 再未命中时, 才使用本文件中的 fallback stage 独立完成环境准备与源码构建.

ARG NODE_VERSION=24.15.0
ARG FFMPEG_IMAGE=jiaopengzi/ffmpeg:8.1.1
ARG CLIENT_BUILD_IMAGE=client-build-fallback
ARG CLIENT_ENV_IMAGE=client-env-fallback
ARG SERVER_BUILD_IMAGE=server-build-fallback
ARG SERVER_GOLANG_IMAGE=server-golang-fallback
ARG BLOG_ENV_IMAGE=blog:env

FROM node:${NODE_VERSION} AS client-env-fallback

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH

WORKDIR /app

COPY blog-client/package.json blog-client/pnpm-lock.yaml blog-client/pnpm-workspace.yaml ./

RUN PNPM_VERSION="$(node -p 'JSON.parse(require("node:fs").readFileSync("./package.json", "utf8")).packageManager.match(/^pnpm@(.*)$/)[1]')" \
    && npm install -g "pnpm@${PNPM_VERSION}"

RUN pnpm install --frozen-lockfile

FROM ${CLIENT_ENV_IMAGE} AS client-builder

WORKDIR /app

COPY blog-client/ ./

RUN pnpm build

FROM scratch AS client-build-fallback

COPY --from=client-builder /app/dist /usr/share/nginx/html
COPY blog-client/LICENSE /usr/share/nginx/html/LICENSE
COPY blog-client/nginx.conf /etc/nginx/nginx.conf
COPY blog-client/redirects.map /etc/nginx/redirects.map

FROM ${CLIENT_BUILD_IMAGE} AS client-artifacts

FROM golang:1.26.3-alpine AS server-golang-fallback

WORKDIR /app

RUN echo "https://mirrors.aliyun.com/alpine/latest-stable/main" >/etc/apk/repositories \
    && echo "https://mirrors.aliyun.com/alpine/latest-stable/community" >>/etc/apk/repositories \
    && apk add --no-cache make git curl tzdata

FROM ${SERVER_GOLANG_IMAGE} AS server-builder

WORKDIR /app

COPY blog-server-dev/go.mod blog-server-dev/go.sum ./

RUN go mod download

COPY blog-server-dev/ ./

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/boot ./boot/main.go \
    && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/blog-server . \
    && cp -r ./config /out/config \
    && cp -r ./templates /out/templates \
    && cp -r ./docs /out/docs \
    && rm -rf /out/docs/md

FROM scratch AS server-build-fallback

COPY --from=server-builder /out/blog-server /home/blog-server/blog-server
COPY --from=server-builder /out/boot /home/blog-server/boot
COPY --from=server-builder /out/config /home/blog-server/config
COPY --from=server-builder /out/templates /home/blog-server/templates
COPY --from=server-builder /out/docs /home/blog-server/docs
COPY blog-server-dev/LICENSE /home/blog-server/LICENSE

FROM ${SERVER_BUILD_IMAGE} AS server-artifacts

FROM ${FFMPEG_IMAGE} AS ffmpeg-binaries

FROM ${BLOG_ENV_IMAGE}

ARG BLOG_VERSION=dev

ENV BLOG_VERSION=${BLOG_VERSION}

COPY --from=ffmpeg-binaries /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg-binaries /usr/local/bin/ffprobe /usr/local/bin/ffprobe

COPY --from=server-artifacts /home/blog-server/blog-server /home/blog-server/blog-server
COPY --from=server-artifacts /home/blog-server/boot /home/blog-server/boot
COPY --from=server-artifacts /home/blog-server/config /home/blog-server/config-default
COPY --from=server-artifacts /home/blog-server/templates /home/blog-server/templates
COPY --from=server-artifacts /home/blog-server/docs /home/blog-server/docs
COPY --from=server-artifacts /home/blog-server/LICENSE /home/blog-server/LICENSE

COPY --from=client-artifacts /usr/share/nginx/html /usr/share/nginx/html
COPY --from=client-artifacts /etc/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=client-artifacts /etc/nginx/redirects.map /etc/nginx/redirects.map

COPY single/docker/rootfs/ /

RUN mkdir -p /opt/blog-client \
    && cp -a /etc/nginx /opt/blog-client/nginx-template \
    && chmod +x /usr/local/bin/blog-entrypoint.sh /home/blog-server/blog-server /home/blog-server/boot \
    && printf '%s\n' "$BLOG_VERSION" >/home/blog-server/VERSION \
    && chown -R blog-server:blog-server /home/blog-server

VOLUME ["/data"]

EXPOSE 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD ["/bin/bash", "-lc", "curl -fsS --max-time 5 http://127.0.0.1:${BLOG_SERVER_PORT:-5426}/api/v1/is-setup | grep -q 'request_id' && curl -kfsS --max-time 5 https://127.0.0.1:${BLOG_HTTPS_PORT:-443}/nginx-health >/dev/null"]

ENTRYPOINT ["/usr/local/bin/blog-entrypoint.sh"]