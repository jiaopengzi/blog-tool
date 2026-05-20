# blog 单镜像 Dockerfile

ARG NODE_VERSION=24.15.0
ARG UBUNTU_VERSION=24.04
ARG POSTGRES_MAJOR=18
ARG REDIS_VERSION=8.6.3
ARG ELASTICSEARCH_VERSION=9.4.1
ARG FFMPEG_IMAGE=jiaopengzi/ffmpeg:8.1.1
ARG CLIENT_ENV_IMAGE=client-env-fallback
ARG SERVER_GOLANG_IMAGE=server-golang-fallback

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

FROM ubuntu:${UBUNTU_VERSION} AS elasticsearch-with-ik

ARG ELASTICSEARCH_VERSION=9.4.1

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    tar \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTICSEARCH_VERSION}-linux-x86_64.tar.gz" -o /tmp/elasticsearch.tar.gz \
    && mkdir -p /opt/elasticsearch \
    && tar -xzf /tmp/elasticsearch.tar.gz -C /opt/elasticsearch --strip-components=1 \
    && rm -f /tmp/elasticsearch.tar.gz \
    && curl -fsSL "https://release.infinilabs.com/analysis-ik/stable/elasticsearch-analysis-ik-${ELASTICSEARCH_VERSION}.zip" -o /tmp/analysis-ik.zip \
    && /opt/elasticsearch/bin/elasticsearch-plugin install --batch file:///tmp/analysis-ik.zip \
    && rm -f /tmp/analysis-ik.zip

FROM ubuntu:${UBUNTU_VERSION} AS redis-binaries

ARG REDIS_VERSION=8.6.3

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    tar \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz" -o /tmp/redis.tar.gz \
    && mkdir -p /tmp/redis-src \
    && tar -xzf /tmp/redis.tar.gz -C /tmp/redis-src --strip-components=1 \
    && make -C /tmp/redis-src -j"$(nproc)" BUILD_TLS=no \
    && install -m 0755 /tmp/redis-src/src/redis-server /usr/local/bin/redis-server \
    && install -m 0755 /tmp/redis-src/src/redis-cli /usr/local/bin/redis-cli \
    && rm -rf /tmp/redis.tar.gz /tmp/redis-src

FROM ${FFMPEG_IMAGE} AS ffmpeg-binaries

FROM ubuntu:${UBUNTU_VERSION}

ARG POSTGRES_MAJOR=18
ARG ELASTICSEARCH_VERSION=9.4.1
ARG BLOG_VERSION=dev

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV BLOG_VERSION=${BLOG_VERSION}
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PATH=/usr/lib/postgresql/${POSTGRES_MAJOR}/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    gnupg \
    gnupg2 \
    locales \
    openssl \
    passwd \
    procps \
    tar \
    tzdata \
    ubuntu-keyring \
    lsb-release \
    && printf '%s\n' '#!/bin/sh' 'exit 101' >/usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d \
    && mkdir -p /etc/postgresql-common \
    && printf '%s\n' 'create_main_cluster = false' >/etc/postgresql-common/createcluster.conf \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && printf '%s\n' \
    'Types: deb' \
    'URIs: https://apt.postgresql.org/pub/repos/apt' \
    'Suites: noble-pgdg' \
    'Components: main' \
    'Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc' \
    >/etc/apt/sources.list.d/pgdg.sources \
    && curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg \
    && printf '%s\n' 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/ubuntu noble nginx' >/etc/apt/sources.list.d/nginx.list \
    && printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' >/etc/apt/preferences.d/99nginx \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    nginx \
    postgresql-${POSTGRES_MAJOR} \
    postgresql-client-${POSTGRES_MAJOR} \
    && sed -i '/^# en_US.UTF-8 UTF-8$/s/^# //' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && rm -f /usr/sbin/policy-rc.d \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=redis-binaries /usr/local/bin/redis-server /usr/local/bin/redis-server
COPY --from=redis-binaries /usr/local/bin/redis-cli /usr/local/bin/redis-cli
COPY --from=ffmpeg-binaries /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg-binaries /usr/local/bin/ffprobe /usr/local/bin/ffprobe

COPY --from=elasticsearch-with-ik /opt/elasticsearch /opt/elasticsearch

RUN mkdir -p /opt/elasticsearch/config/analysis-ik \
    && printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">' \
    '<properties>' \
    '    <comment>IK Analyzer 扩展配置</comment>' \
    '    <entry key="ext_dict">my.dic</entry>' \
    '    <entry key="ext_stopwords"></entry>' \
    '</properties>' >/opt/elasticsearch/config/analysis-ik/IKAnalyzer.cfg.xml \
    && touch /opt/elasticsearch/config/analysis-ik/my.dic \
    && if ! getent group blog-server >/dev/null; then groupadd --system blog-server; fi \
    && if ! id -u blog-server >/dev/null 2>&1; then useradd --system -g blog-server -m -d /home/blog-server -s /bin/bash blog-server; fi \
    && if ! getent group elasticsearch >/dev/null; then groupadd --system elasticsearch; fi \
    && if ! id -u elasticsearch >/dev/null 2>&1; then useradd --system -g elasticsearch -m -d /home/elasticsearch -s /bin/bash elasticsearch; fi \
    && mkdir -p /data /var/cache/nginx /var/lib/nginx /run/nginx /home/blog-server /var/run/postgresql /var/lib/postgresql \
    && chmod 3775 /var/run/postgresql \
    && chown -R postgres:postgres /var/run/postgresql /var/lib/postgresql \
    && chown -R blog-server:blog-server /home/blog-server \
    && chown -R elasticsearch:elasticsearch /opt/elasticsearch /home/elasticsearch \
    && chown -R www-data:www-data /var/cache/nginx /var/lib/nginx /run/nginx \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" >/etc/timezone

COPY --from=server-builder /out/blog-server /home/blog-server/blog-server
COPY --from=server-builder /out/boot /home/blog-server/boot
COPY --from=server-builder /out/config /home/blog-server/config-default
COPY --from=server-builder /out/templates /home/blog-server/templates
COPY --from=server-builder /out/docs /home/blog-server/docs
COPY blog-server-dev/LICENSE /home/blog-server/LICENSE

COPY --from=client-builder /app/dist /usr/share/nginx/html
COPY blog-client/LICENSE /usr/share/nginx/html/LICENSE
COPY blog-client/redirects.map /etc/nginx/redirects.map

COPY single/docker/rootfs/ /

RUN chmod +x /usr/local/bin/blog-entrypoint.sh /home/blog-server/blog-server /home/blog-server/boot \
    && printf '%s\n' "$BLOG_VERSION" >/home/blog-server/VERSION \
    && chown -R blog-server:blog-server /home/blog-server

VOLUME ["/data"]

EXPOSE 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD ["/bin/bash", "-lc", "curl -fsS --max-time 5 http://127.0.0.1:${BLOG_SERVER_PORT:-5426}/api/v1/is-setup | grep -q 'request_id' && curl -kfsS --max-time 5 https://127.0.0.1:${BLOG_HTTPS_PORT:-443}/nginx-health >/dev/null"]

ENTRYPOINT ["/usr/local/bin/blog-entrypoint.sh"]