# blog 单镜像运行时环境 Dockerfile

ARG UBUNTU_VERSION=24.04
ARG POSTGRES_MAJOR=18
ARG REDIS_VERSION=8.6.3
ARG REDIS_DOWNLOAD_SHA=58d0d1eb49a1ea6c2179659707fec171b1e2e2b8d5157ed2ec59d1d66ad5a654
ARG ELASTICSEARCH_VERSION=9.4.1
ARG NGINX_VERSION=1.31.0

FROM ubuntu:${UBUNTU_VERSION} AS ubuntu-apt-base

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    printf '%s\n' \
    '#!/bin/sh' \
    'set -eu' \
    'attempt=1' \
    'while true; do' \
    '    if "$@"; then' \
    '        exit 0' \
    '    fi' \
    '    if [ "$attempt" -ge 5 ]; then' \
    '        exit 1' \
    '    fi' \
    '    attempt=$((attempt + 1))' \
    '    rm -rf /var/lib/apt/lists/*' \
    'done' >/usr/local/bin/apt-retry; \
    chmod +x /usr/local/bin/apt-retry; \
    /usr/local/bin/apt-retry apt-get update; \
    /usr/local/bin/apt-retry apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    gnupg \
    locales \
    openssl \
    passwd \
    tar \
    tzdata; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

FROM ubuntu-apt-base AS elasticsearch-with-ik

ARG ELASTICSEARCH_VERSION=9.4.1

COPY blog-cache/ ./blog-cache/

RUN set -eux; \
    elasticsearch_archive="elasticsearch-${ELASTICSEARCH_VERSION}-linux-x86_64.tar.gz"; \
    ik_archive="elasticsearch-analysis-ik-${ELASTICSEARCH_VERSION}.zip"; \
    if [ -f "./blog-cache/${elasticsearch_archive}" ]; then cp "./blog-cache/${elasticsearch_archive}" /tmp/elasticsearch.tar.gz; else curl -fsSL "https://artifacts.elastic.co/downloads/elasticsearch/${elasticsearch_archive}" -o /tmp/elasticsearch.tar.gz; fi; \
    mkdir -p /opt/elasticsearch; \
    tar -xzf /tmp/elasticsearch.tar.gz -C /opt/elasticsearch --strip-components=1; \
    rm -f /tmp/elasticsearch.tar.gz; \
    if [ -f "./blog-cache/${ik_archive}" ]; then cp "./blog-cache/${ik_archive}" /tmp/analysis-ik.zip; else curl -fsSL "https://release.infinilabs.com/analysis-ik/stable/${ik_archive}" -o /tmp/analysis-ik.zip; fi; \
    /opt/elasticsearch/bin/elasticsearch-plugin install --batch file:///tmp/analysis-ik.zip; \
    mkdir -p /opt/elasticsearch/config/analysis-ik; \
    printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">' \
    '<properties>' \
    '    <comment>IK Analyzer 扩展配置</comment>' \
    '    <entry key="ext_dict">my.dic</entry>' \
    '    <entry key="ext_stopwords"></entry>' \
    '</properties>' >/opt/elasticsearch/config/analysis-ik/IKAnalyzer.cfg.xml; \
    touch /opt/elasticsearch/config/analysis-ik/my.dic; \
    rm -f /tmp/analysis-ik.zip; \
    rm -rf ./blog-cache

FROM ubuntu-apt-base AS redis-binaries

ARG REDIS_VERSION=8.6.3
ARG REDIS_DOWNLOAD_SHA=58d0d1eb49a1ea6c2179659707fec171b1e2e2b8d5157ed2ec59d1d66ad5a654

COPY blog-cache/ ./blog-cache/

RUN set -eux; \
    redis_archive="redis-${REDIS_VERSION}-official-src.tar.gz"; \
    redis_download_url="https://github.com/redis/redis/archive/refs/tags/${REDIS_VERSION}.tar.gz"; \
    /usr/local/bin/apt-retry apt-get update; \
    /usr/local/bin/apt-retry apt-get install -y --no-install-recommends \
    dpkg-dev \
    gcc \
    g++ \
    libc6-dev \
    libssl-dev \
    make; \
    arch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    case "$arch" in \
    amd64|arm64) \
    export BUILD_WITH_MODULES=yes; \
    export INSTALL_RUST_TOOLCHAIN=yes; \
    export DISABLE_WERRORS=yes; \
    /usr/local/bin/apt-retry apt-get update; \
    /usr/local/bin/apt-retry apt-get install -y --no-install-recommends \
    git \
    cmake \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    unzip \
    rsync \
    clang \
    automake \
    autoconf \
    libtool; \
    ;; \
    *) \
    export BUILD_WITH_MODULES=no; \
    ;; \
    esac; \
    rm -rf /var/lib/apt/lists/*; \
    if [ -f "./blog-cache/${redis_archive}" ]; then cp "./blog-cache/${redis_archive}" /tmp/redis.tar.gz; else curl -fsSL "$redis_download_url" -o /tmp/redis.tar.gz; fi; \
    echo "${REDIS_DOWNLOAD_SHA} */tmp/redis.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/redis-src; \
    tar -xzf /tmp/redis.tar.gz -C /tmp/redis-src --strip-components=1; \
    grep -E '^ *createBoolConfig[(]"protected-mode",.*, *1 *,.*[)],$' /tmp/redis-src/src/config.c; \
    sed -ri 's!^( *createBoolConfig[(]"protected-mode",.*, *)1( *,.*[)],)$!\10\2!' /tmp/redis-src/src/config.c; \
    grep -E '^ *createBoolConfig[(]"protected-mode",.*, *0 *,.*[)],$' /tmp/redis-src/src/config.c; \
    gnu_arch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    extra_jemalloc_configure_flags="--build=$gnu_arch"; \
    case "${arch##*-}" in \
    amd64|i386|x32) extra_jemalloc_configure_flags="$extra_jemalloc_configure_flags --with-lg-page=12" ;; \
    *) extra_jemalloc_configure_flags="$extra_jemalloc_configure_flags --with-lg-page=16" ;; \
    esac; \
    extra_jemalloc_configure_flags="$extra_jemalloc_configure_flags --with-lg-hugepage=21"; \
    grep -F 'cd jemalloc && ./configure ' /tmp/redis-src/deps/Makefile; \
    sed -ri 's!cd jemalloc && ./configure !&'"$extra_jemalloc_configure_flags"' !' /tmp/redis-src/deps/Makefile; \
    grep -F "cd jemalloc && ./configure $extra_jemalloc_configure_flags " /tmp/redis-src/deps/Makefile; \
    export BUILD_TLS=yes; \
    make -C /tmp/redis-src -j"$(nproc)" all; \
    make -C /tmp/redis-src install; \
    install -m 0755 /tmp/redis-src/src/redis-server /usr/local/bin/redis-server; \
    install -m 0755 /tmp/redis-src/src/redis-cli /usr/local/bin/redis-cli; \
    strip /usr/local/bin/redis-server /usr/local/bin/redis-cli || true; \
    rm -rf /tmp/redis.tar.gz /tmp/redis-src ./blog-cache

FROM ubuntu-apt-base

ARG POSTGRES_MAJOR=18
ARG NGINX_VERSION=1.31.0

ENV TZ=Asia/Shanghai
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PATH=/usr/lib/postgresql/${POSTGRES_MAJOR}/bin:${PATH}

RUN set -eux; \
    nginx_apt_version="${NGINX_VERSION}-1~noble"; \
    printf '%s\n' '#!/bin/sh' 'exit 101' >/usr/sbin/policy-rc.d; \
    chmod +x /usr/sbin/policy-rc.d; \
    mkdir -p /etc/postgresql-common; \
    printf '%s\n' 'create_main_cluster = false' >/etc/postgresql-common/createcluster.conf; \
    install -d /usr/share/postgresql-common/pgdg /usr/share/keyrings; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc; \
    printf '%s\n' 'Types: deb' 'URIs: https://apt.postgresql.org/pub/repos/apt' 'Suites: noble-pgdg' 'Components: main' 'Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc' >/etc/apt/sources.list.d/pgdg.sources; \
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg; \
    printf '%s\n' 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/ubuntu noble nginx' >/etc/apt/sources.list.d/nginx.list; \
    printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' >/etc/apt/preferences.d/99nginx; \
    /usr/local/bin/apt-retry apt-get update; \
    /usr/local/bin/apt-retry apt-get install -y --no-install-recommends "nginx=${nginx_apt_version}" "postgresql-${POSTGRES_MAJOR}" "postgresql-client-${POSTGRES_MAJOR}"; \
    sed -i '/^# en_US.UTF-8 UTF-8$/s/^# //' /etc/locale.gen; \
    locale-gen en_US.UTF-8; \
    if ! getent group blog-server >/dev/null; then groupadd --system blog-server; fi; \
    if ! id -u blog-server >/dev/null 2>&1; then useradd --system -g blog-server -m -d /home/blog-server -s /bin/bash blog-server; fi; \
    if ! getent group elasticsearch >/dev/null; then groupadd --system elasticsearch; fi; \
    if ! id -u elasticsearch >/dev/null 2>&1; then useradd --system -g elasticsearch -m -d /home/elasticsearch -s /bin/bash elasticsearch; fi; \
    mkdir -p /data /var/cache/nginx /var/lib/nginx /run/nginx /home/blog-server /var/run/postgresql /var/lib/postgresql; \
    chmod 3775 /var/run/postgresql; \
    chown -R postgres:postgres /var/run/postgresql /var/lib/postgresql; \
    chown -R blog-server:blog-server /home/blog-server; \
    chown -R www-data:www-data /var/cache/nginx /var/lib/nginx /run/nginx; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    echo 'Asia/Shanghai' >/etc/timezone; \
    rm -f /usr/sbin/policy-rc.d; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* /usr/share/info/*

COPY --from=redis-binaries /usr/local/bin/redis-server /usr/local/bin/redis-cli /usr/local/bin/
COPY --from=redis-binaries /usr/local/lib/redis /usr/local/lib/redis
COPY --chown=elasticsearch:elasticsearch --from=elasticsearch-with-ik /opt/elasticsearch /opt/elasticsearch

VOLUME ["/data"]
