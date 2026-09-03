#!/bin/bash
# FilePath    : blog-tool/single/docker/rootfs/usr/local/bin/blog-entrypoint.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : blog 单镜像运行入口, 负责初始化并拉起 Nuxt Nitro、nginx、blog-server、PostgreSQL、Redis、Elasticsearch.
# Note        : 此文件保留在 single/docker/rootfs/usr/local/bin, 是为了与容器内 /usr/local/bin/blog-entrypoint.sh 的落点保持一致.
# Note        : single/docker/rootfs 目录按容器根文件系统布局组织, 构建时通过 COPY single/docker/rootfs/ / 直接还原到镜像内, 因此这里的目录层级来自容器路径映射, 不是源码层级设计过深.

set -euo pipefail

LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_FILE="${LOG_FILE:-/var/log/blog-entrypoint.log}"
BLOG_TOOL_ENV="${BLOG_TOOL_ENV:-/tmp/blog_tool_env}"

mkdir -p "$(dirname "$LOG_FILE")" "$BLOG_TOOL_ENV"
# shellcheck disable=SC1091
source /usr/local/lib/blog-tool/log.sh

BLOG_PUBLIC_HOST_SOURCE="default"
if [[ -n "${BLOG_PUBLIC_HOST:-}" ]]; then
    BLOG_PUBLIC_HOST_SOURCE="BLOG_PUBLIC_HOST"
elif [[ -n "${DOMAIN_NAME:-}" ]]; then
    BLOG_PUBLIC_HOST_SOURCE="DOMAIN_NAME"
elif [[ -n "${HOST_INTRANET_IP:-}" ]]; then
    BLOG_PUBLIC_HOST_SOURCE="HOST_INTRANET_IP"
fi

BLOG_DATA_DIR="${BLOG_DATA_DIR:-/data}"
BLOG_PUBLIC_HOST="${BLOG_PUBLIC_HOST:-${DOMAIN_NAME:-${HOST_INTRANET_IP:-localhost}}}"
BLOG_PROJECT_NAME="${BLOG_PROJECT_NAME:-blog}"
BLOG_HTTPS_PORT="${BLOG_HTTPS_PORT:-443}"
BLOG_SERVER_PORT="${BLOG_SERVER_PORT:-5426}"
BLOG_NITRO_PORT="${BLOG_NITRO_PORT:-7364}"
BLOG_PG_PORT="${BLOG_PG_PORT:-15432}"
BLOG_REDIS_PORT="${BLOG_REDIS_PORT:-16379}"
BLOG_ES_PORT="${BLOG_ES_PORT:-19200}"
BLOG_POSTGRES_USER="${BLOG_POSTGRES_USER:-user_blog}"
BLOG_POSTGRES_DB="${BLOG_POSTGRES_DB:-blog_server_jpz}"
BLOG_ES_USER="elastic"
BLOG_MEMORY_PROFILE="${BLOG_MEMORY_PROFILE:-auto}"
BLOG_ES_JAVA_OPTS="${BLOG_ES_JAVA_OPTS:-}"
BLOG_PG_SHARED_BUFFERS="${BLOG_PG_SHARED_BUFFERS:-}"
BLOG_PG_MAX_CONNECTIONS="${BLOG_PG_MAX_CONNECTIONS:-}"
BLOG_NGINX_WORKER_PROCESSES="${BLOG_NGINX_WORKER_PROCESSES:-}"
BLOG_CERT_DAYS="${BLOG_CERT_DAYS:-36525}"
BLOG_HTTPS_CERT_FILE="${BLOG_HTTPS_CERT_FILE:-}"
BLOG_HTTPS_KEY_FILE="${BLOG_HTTPS_KEY_FILE:-}"

BLOG_INTERNAL_CERT_DIR="$BLOG_DATA_DIR/certs/internal-ca"
BLOG_CLIENT_NGINX_DIR="$BLOG_DATA_DIR/blog-client/nginx"
BLOG_CLIENT_NGINX_TEMPLATE_FILE="/opt/blog-client/nginx.conf.template"
BLOG_CLIENT_REDIRECTS_MAP_FILE="/opt/blog-client/redirects.map"
BLOG_CLIENT_MIME_TYPES_FILE="/opt/blog-client/mime.types"
BLOG_HTTPS_CERT_DIR="$BLOG_CLIENT_NGINX_DIR/ssl"
BLOG_LEGACY_HTTPS_CERT_DIR="$BLOG_DATA_DIR/certs/https"
BLOG_SERVER_DATA_DIR="$BLOG_DATA_DIR/blog-server"
BLOG_POSTGRES_DATA_DIR="$BLOG_DATA_DIR/postgres"
BLOG_POSTGRES_CLUSTER_DIR="$BLOG_POSTGRES_DATA_DIR/cluster"
BLOG_POSTGRES_CONF_DIR="$BLOG_POSTGRES_DATA_DIR/config"
BLOG_REDIS_DATA_DIR="$BLOG_DATA_DIR/redis"
BLOG_ES_DATA_DIR="$BLOG_DATA_DIR/elasticsearch"
BLOG_LEGACY_RUNTIME_ENV_FILE="$BLOG_DATA_DIR/runtime-secrets.env"
BLOG_PIDS_FILE="$BLOG_DATA_DIR/blog.pids"

POSTGRES_PID=""
REDIS_PID=""
ES_PID=""
SERVER_PID=""
NITRO_PID=""
NGINX_PID=""
BLOG_HOST_MEM_MB="0"

# 读取容器可见的实际内存上限, 优先使用 cgroup limit, 未命中时回退宿主机总内存.
detect_available_memory_mb() {
    local mem_total_kb=""
    local memory_limit_bytes=""
    local resolved_limit_mb="0"

    mem_total_kb="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
    if [[ -n "$mem_total_kb" ]] && [[ "$mem_total_kb" =~ ^[0-9]+$ ]]; then
        resolved_limit_mb=$((mem_total_kb / 1024))
    fi

    for cgroup_file in \
        /sys/fs/cgroup/memory.max \
        /sys/fs/cgroup/memory/memory.limit_in_bytes; do
        if [[ ! -r "$cgroup_file" ]]; then
            continue
        fi

        memory_limit_bytes="$(cat "$cgroup_file" 2>/dev/null || true)"
        if [[ -z "$memory_limit_bytes" ]] || [[ "$memory_limit_bytes" == "max" ]] || [[ ! "$memory_limit_bytes" =~ ^[0-9]+$ ]]; then
            continue
        fi

        # 某些运行时会给出接近无穷大的大整数, 这里直接忽略.
        if [[ "$memory_limit_bytes" -ge 9223372036854771712 ]]; then
            continue
        fi

        local cgroup_limit_mb=$((memory_limit_bytes / 1024 / 1024))
        if [[ "$cgroup_limit_mb" -gt 0 ]] && [[ "$cgroup_limit_mb" -lt "$resolved_limit_mb" || "$resolved_limit_mb" -eq 0 ]]; then
            resolved_limit_mb="$cgroup_limit_mb"
        fi
    done

    printf '%s\n' "$resolved_limit_mb"
}

# 根据宿主可见内存自动收敛运行参数, 让 4G 机器也能尽量稳定启动.
# 说明: 显式传入的环境变量优先级更高, 仅在未设置时做自动降档.
resolve_memory_profile() {
    local selected_profile="$BLOG_MEMORY_PROFILE"

    BLOG_HOST_MEM_MB="$(detect_available_memory_mb)"
    if [[ -z "$BLOG_HOST_MEM_MB" ]] || [[ ! "$BLOG_HOST_MEM_MB" =~ ^[0-9]+$ ]]; then
        BLOG_HOST_MEM_MB=0
    fi

    if [[ "$selected_profile" == "auto" ]]; then
        if [[ "$BLOG_HOST_MEM_MB" -gt 0 ]] && [[ "$BLOG_HOST_MEM_MB" -le 3072 ]]; then
            selected_profile="tiny"
        elif [[ "$BLOG_HOST_MEM_MB" -gt 0 ]] && [[ "$BLOG_HOST_MEM_MB" -le 5120 ]]; then
            selected_profile="small"
        else
            selected_profile="default"
        fi
    fi

    if [[ -z "$BLOG_ES_JAVA_OPTS" ]]; then
        case "$selected_profile" in
        tiny) BLOG_ES_JAVA_OPTS="-Xms256m -Xmx256m -XX:ActiveProcessorCount=1" ;;
        small) BLOG_ES_JAVA_OPTS="-Xms384m -Xmx384m -XX:ActiveProcessorCount=1" ;;
        *) BLOG_ES_JAVA_OPTS="-Xms512m -Xmx512m" ;;
        esac
    fi

    if [[ -z "$BLOG_PG_SHARED_BUFFERS" ]]; then
        case "$selected_profile" in
        tiny) BLOG_PG_SHARED_BUFFERS="32MB" ;;
        small) BLOG_PG_SHARED_BUFFERS="64MB" ;;
        *) BLOG_PG_SHARED_BUFFERS="128MB" ;;
        esac
    fi

    if [[ -z "$BLOG_PG_MAX_CONNECTIONS" ]]; then
        case "$selected_profile" in
        tiny) BLOG_PG_MAX_CONNECTIONS="20" ;;
        small) BLOG_PG_MAX_CONNECTIONS="40" ;;
        *) BLOG_PG_MAX_CONNECTIONS="100" ;;
        esac
    fi

    if [[ -z "$BLOG_NGINX_WORKER_PROCESSES" ]]; then
        case "$selected_profile" in
        tiny|small) BLOG_NGINX_WORKER_PROCESSES="1" ;;
        *) BLOG_NGINX_WORKER_PROCESSES="auto" ;;
        esac
    fi

    log_info "内存档位: $selected_profile, 可见内存: ${BLOG_HOST_MEM_MB}MB, ES_JAVA_OPTS: $BLOG_ES_JAVA_OPTS, PG shared_buffers: $BLOG_PG_SHARED_BUFFERS"
}

# 输出 Redis overcommit 建议, 该设置需要在宿主机上生效.
warn_if_vm_overcommit_disabled() {
    local overcommit_value=""

    overcommit_value="$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || true)"
    if [[ "$overcommit_value" != "1" ]]; then
        log_warn "检测到宿主机 vm.overcommit_memory=${overcommit_value:-unknown}, Redis 可能告警; 建议在宿主机执行: sudo sysctl vm.overcommit_memory=1"
    fi
}

# 返回 PostgreSQL 可执行文件绝对路径, 避免 su 切换用户后 PATH 被重置导致找不到命令.
# 参数: $1: 二进制名称, 例如 initdb.
require_postgres_binary() {
    local binary_name="$1"
    local binary_path=""

    binary_path="$(command -v "$binary_name" 2>/dev/null || true)"
    if [[ -z "$binary_path" ]]; then
        log_error "未找到 PostgreSQL 可执行文件: $binary_name"
        exit 1
    fi

    printf '%s\n' "$binary_path"
}

normalize_public_host() {
    BLOG_PUBLIC_HOST="${BLOG_PUBLIC_HOST#http://}"
    BLOG_PUBLIC_HOST="${BLOG_PUBLIC_HOST#https://}"
    BLOG_PUBLIC_HOST="${BLOG_PUBLIC_HOST%%/*}"

    if [[ -z "$BLOG_PUBLIC_HOST" ]]; then
        BLOG_PUBLIC_HOST="localhost"
    fi
}

# patch_client_nginx_config 调整已从 Nuxt 模板渲染的 nginx 配置以适配 single 端口.
# 参数: 无.
# 返回: 修改成功返回 0, sed 执行失败时返回非 0.
patch_client_nginx_config() {
    local nginx_conf_file="$BLOG_CLIENT_NGINX_DIR/nginx.conf"
    local https_redirect_target="https://\$host\$request_uri"
    local server_proxy_url="http://127.0.0.1:${BLOG_SERVER_PORT}"
    local nitro_proxy_url="http://127.0.0.1:${BLOG_NITRO_PORT}"

    if [[ ! -f "$nginx_conf_file" ]]; then
        log_error "未找到 blog-client nginx.conf: $nginx_conf_file"
        exit 1
    fi

    if [[ "$BLOG_HTTPS_PORT" != "443" ]]; then
        https_redirect_target="https://\$host:${BLOG_HTTPS_PORT}\$request_uri"
    fi

    sed -ri "s|^([[:space:]]*)worker_processes[[:space:]]+[^;]+;|\\1worker_processes ${BLOG_NGINX_WORKER_PROCESSES};|" "$nginx_conf_file"
    sed -ri "s|^([[:space:]]*listen[[:space:]]+)[0-9]+([[:space:]]+ssl;)|\\1${BLOG_HTTPS_PORT}\\2|" "$nginx_conf_file"
    sed -ri "s|^([[:space:]]*listen[[:space:]]+\[::\]:)[0-9]+([[:space:]]+ssl;)|\\1${BLOG_HTTPS_PORT}\\2|" "$nginx_conf_file"
    sed -ri "0,/^[[:space:]]*return 301 https:\/\/\\\$host.*\\\$request_uri;$/s||            return 301 ${https_redirect_target};|" "$nginx_conf_file"
    sed -ri "s|^([[:space:]]*server_name[[:space:]]+)[^;]+;|\\1${BLOG_PUBLIC_HOST};|" "$nginx_conf_file"
    sed -ri "s|^([[:space:]]*proxy_pass[[:space:]]+)http://127\.0\.0\.1:[0-9]+(/api/v1/sitemap;)|\\1${server_proxy_url}\\2|" "$nginx_conf_file"
    sed -ri "s|^([[:space:]]*proxy_pass[[:space:]]+)http://127\.0\.0\.1:[0-9]+(/api/;)|\\1${server_proxy_url}\\2|" "$nginx_conf_file"
    sed -ri "/^[[:space:]]*location[[:space:]]+~\\*.*uploads.*\\{/,/^[[:space:]]*\\}/ s|^([[:space:]]*proxy_pass[[:space:]]+)http://127\.0\.0\.1:[0-9]+(;)|\\1${server_proxy_url}\\2|" "$nginx_conf_file"
    sed -ri "/^[[:space:]]*location[[:space:]]+\/[[:space:]]*\\{/,/^[[:space:]]*\\}/ s|^([[:space:]]*proxy_pass[[:space:]]+)http://127\.0\.0\.1:[0-9]+(;)|\\1${nitro_proxy_url}\\2|" "$nginx_conf_file"
}

# prepare_nitro_runtime 初始化 Nuxt Nitro 和 nginx 模板共用的运行时环境变量.
# 参数: 无.
# 返回: 环境变量设置成功时返回 0, 计算公开地址失败时返回非 0.
prepare_nitro_runtime() {
    export NITRO_PORT="$BLOG_NITRO_PORT"
    export NUXT_API_BASE="http://127.0.0.1:${BLOG_SERVER_PORT}"
    NUXT_PUBLIC_BASE_URL="$(server_public_url)" || return 1
    export NUXT_PUBLIC_BASE_URL
    export NODE_ENV="${NODE_ENV:-production}"
}

# client_nginx_config_is_spa 判断持久化 nginx.conf 是否仍使用 SPA 根路由入口.
# 参数: $1: nginx.conf 文件路径.
# 返回: 根路由包含 try_files 和 /index.html 时返回 0, 否则返回非 0.
client_nginx_config_is_spa() {
    local nginx_conf_file="$1"

    awk '
        /^[[:space:]]*location[[:space:]]+\/[[:space:]]*\{/ { in_root_location=1; next }
        in_root_location && /^[[:space:]]*\}/ { exit }
        in_root_location && /^[[:space:]]*try_files[[:space:]].*\/index\.html;/ { is_spa=1; exit }
        END { exit(is_spa ? 0 : 1) }
    ' "$nginx_conf_file"
}

# migrate_legacy_client_nginx_config 备份 SPA nginx.conf, 让首次 Nuxt 启动重新渲染 SSR 配置.
# 参数: $1: nginx.conf 文件路径.
# 返回: 不是 SPA 配置或迁移成功时返回 0, 文件备份或删除失败时返回非 0.
migrate_legacy_client_nginx_config() {
    local nginx_conf_file="$1"
    local backup_file="${nginx_conf_file}.pre-nuxt"

    if [[ ! -f "$nginx_conf_file" ]] || ! client_nginx_config_is_spa "$nginx_conf_file"; then
        return 0
    fi

    if ! cp -a --update=none "$nginx_conf_file" "$backup_file"; then
        log_error "备份旧 SPA nginx 配置失败: $nginx_conf_file"
        return 1
    fi

    if ! rm -f "$nginx_conf_file"; then
        log_error "删除旧 SPA nginx 配置失败: $nginx_conf_file"
        return 1
    fi

    log_warn "检测到旧 SPA nginx 配置, 已备份为: $backup_file"
}

# ensure_client_nginx_config 通过 Nuxt nginx 模板生成 single 运行时配置.
# 参数: 无.
# 返回: 生成成功返回 0, 模板或渲染工具缺失时退出容器.
ensure_client_nginx_config() {
    local nginx_conf_file="$BLOG_CLIENT_NGINX_DIR/nginx.conf"

    if [[ ! -f "$BLOG_CLIENT_NGINX_TEMPLATE_FILE" ]]; then
        log_error "未找到 blog-client nginx 模板: $BLOG_CLIENT_NGINX_TEMPLATE_FILE"
        exit 1
    fi

    if [[ ! -f "$BLOG_CLIENT_MIME_TYPES_FILE" ]]; then
        log_error "未找到 blog-client mime.types: $BLOG_CLIENT_MIME_TYPES_FILE"
        exit 1
    fi

    ensure_directory "$BLOG_CLIENT_NGINX_DIR" root 755 false
    if [[ -f "$BLOG_CLIENT_REDIRECTS_MAP_FILE" ]]; then
        cp -a --update=none "$BLOG_CLIENT_REDIRECTS_MAP_FILE" "$BLOG_CLIENT_NGINX_DIR/redirects.map"
    fi
    cp -a --update=none "$BLOG_CLIENT_MIME_TYPES_FILE" "$BLOG_CLIENT_NGINX_DIR/mime.types"
    migrate_legacy_client_nginx_config "$nginx_conf_file" || exit 1

    # Nuxt 模板中的后端代理和 Nitro 运行时均直连 single 内的 blog-server.
    prepare_nitro_runtime || exit 1
    export NGINX_SERVER_NAME="$BLOG_PUBLIC_HOST"

    if [[ ! -f "$nginx_conf_file" ]]; then
        envsubst "\${NGINX_SERVER_NAME} \${NUXT_API_BASE}" \
            <"$BLOG_CLIENT_NGINX_TEMPLATE_FILE" \
            >"$nginx_conf_file"
    fi

    patch_client_nginx_config

    rm -rf /etc/nginx
    ln -s "$BLOG_CLIENT_NGINX_DIR" /etc/nginx
}

is_ipv4() {
    local value="$1"
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

ensure_directory() {
    local dir_path="$1"
    local owner="$2"
    local mode="$3"
    local recursive_chown="${4:-true}"

    mkdir -p "$dir_path"
    chmod "$mode" "$dir_path"

    if [[ "$recursive_chown" == "true" ]]; then
        chown -R "$owner" "$dir_path"
    else
        chown "$owner" "$dir_path"
    fi
}

load_or_persist_secret() {
    local env_name="$1"
    local secret_file="$2"
    local random_bytes="$3"
    local current_value="${!env_name:-}"

    mkdir -p "$(dirname "$secret_file")"

    if [[ -f "$secret_file" ]] && [[ -s "$secret_file" ]]; then
        current_value="$(cat "$secret_file")"
    else
        if [[ -z "$current_value" ]]; then
            current_value="$(openssl rand -hex "$random_bytes")"
        fi

        printf '%s' "$current_value" >"$secret_file"
        chmod 600 "$secret_file"
    fi

    printf -v "$env_name" '%s' "$current_value"
    export "$env_name=$current_value"
}

ensure_runtime_secrets() {
    load_or_persist_secret "BLOG_POSTGRES_PASSWORD" "$BLOG_DATA_DIR/secrets/postgres_password" 18
    load_or_persist_secret "BLOG_REDIS_PASSWORD" "$BLOG_DATA_DIR/secrets/redis_password" 18
    load_or_persist_secret "BLOG_ES_PASSWORD" "$BLOG_DATA_DIR/secrets/es_password" 18
    load_or_persist_secret "BLOG_JWT_SECRET_KEY" "$BLOG_DATA_DIR/secrets/jwt_secret_key" 32

    if [[ -f "$BLOG_LEGACY_RUNTIME_ENV_FILE" ]]; then
        rm -f "$BLOG_LEGACY_RUNTIME_ENV_FILE"
    fi
}

server_public_url() {
    if [[ "$BLOG_HTTPS_PORT" == "443" ]]; then
        printf 'https://%s' "$BLOG_PUBLIC_HOST"
    else
        printf 'https://%s:%s' "$BLOG_PUBLIC_HOST" "$BLOG_HTTPS_PORT"
    fi
}

gen_ca_cert() {
    local ca_key_file="$BLOG_INTERNAL_CERT_DIR/ca.key"
    local ca_cert_file="$BLOG_INTERNAL_CERT_DIR/ca.crt"

    if [[ -f "$ca_cert_file" ]] && [[ -f "$ca_key_file" ]]; then
        return 0
    fi

    ensure_directory "$BLOG_INTERNAL_CERT_DIR" root 700

    openssl genpkey -algorithm RSA -out "$ca_key_file" >/dev/null 2>&1
    openssl req -x509 -new -nodes \
        -key "$ca_key_file" \
        -sha256 \
        -days "$BLOG_CERT_DAYS" \
        -out "$ca_cert_file" \
        -subj "/C=CN/ST=Sichuan/L=Chengdu/O=jpz/OU=single/CN=$BLOG_PUBLIC_HOST" >/dev/null 2>&1

    chmod 600 "$ca_key_file"
    chmod 644 "$ca_cert_file"
    log_info "已生成内部 CA 证书, 导出路径: $ca_cert_file"
}

generate_signed_cert() {
    local cert_name="$1"
    local cert_dir="$2"
    local common_name="$3"
    local alt_dns_csv="$4"
    local alt_ip_csv="$5"
    local cert_key_file="$cert_dir/$cert_name.key"
    local cert_csr_file="$cert_dir/$cert_name.csr"
    local cert_crt_file="$cert_dir/$cert_name.crt"
    local cert_conf_file="$cert_dir/$cert_name.cnf"
    local ca_key_file="$BLOG_INTERNAL_CERT_DIR/ca.key"
    local ca_cert_file="$BLOG_INTERNAL_CERT_DIR/ca.crt"
    local index=1
    local item=""

    mkdir -p "$cert_dir"

    openssl genpkey -algorithm RSA -out "$cert_key_file" >/dev/null 2>&1
    openssl req -new -key "$cert_key_file" -out "$cert_csr_file" -subj "/C=CN/ST=Sichuan/L=Chengdu/O=jpz/OU=single/CN=$common_name" >/dev/null 2>&1

    cat >"$cert_conf_file" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
C = CN
ST = Sichuan
L = Chengdu
O = jpz
OU = single
CN = $common_name

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
EOF

    IFS=',' read -r -a dns_items <<<"$alt_dns_csv"
    for item in "${dns_items[@]}"; do
        if [[ -n "$item" ]]; then
            printf 'DNS.%s = %s\n' "$index" "$item" >>"$cert_conf_file"
            ((index++)) || true
        fi
    done

    index=1
    IFS=',' read -r -a ip_items <<<"$alt_ip_csv"
    for item in "${ip_items[@]}"; do
        if [[ -n "$item" ]]; then
            printf 'IP.%s = %s\n' "$index" "$item" >>"$cert_conf_file"
            ((index++)) || true
        fi
    done

    openssl x509 -req -in "$cert_csr_file" \
        -CA "$ca_cert_file" \
        -CAkey "$ca_key_file" \
        -CAcreateserial \
        -out "$cert_crt_file" \
        -days "$BLOG_CERT_DAYS" \
        -sha256 \
        -extfile "$cert_conf_file" \
        -extensions v3_req >/dev/null 2>&1

    rm -f "$cert_csr_file" "$cert_conf_file" "$BLOG_INTERNAL_CERT_DIR/ca.srl"
}

# 兼容旧版本证书目录, 将历史 cert.pem 和 cert.key 迁移到与 --auto 一致的 nginx 目录.
migrate_legacy_https_certificate_if_needed() {
    local cert_file="$BLOG_HTTPS_CERT_DIR/cert.pem"
    local key_file="$BLOG_HTTPS_CERT_DIR/cert.key"
    local legacy_cert_file="$BLOG_LEGACY_HTTPS_CERT_DIR/cert.pem"
    local legacy_key_file="$BLOG_LEGACY_HTTPS_CERT_DIR/cert.key"

    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        return 0
    fi

    if [[ ! -f "$legacy_cert_file" || ! -f "$legacy_key_file" ]]; then
        return 0
    fi

    cp "$legacy_cert_file" "$cert_file"
    cp "$legacy_key_file" "$key_file"
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
    log_info "已将历史 HTTPS 证书迁移到: $BLOG_HTTPS_CERT_DIR"
}

# 校验导入后的 HTTPS 证书与私钥, 尽早给出明确错误.
# 参数: $1: 证书文件路径.
# 参数: $2: 私钥文件路径.
validate_https_certificate_pair() {
    local cert_file="$1"
    local key_file="$2"
    local cert_pubkey_sha=""
    local key_pubkey_sha=""

    if ! openssl x509 -in "$cert_file" -noout >/dev/null 2>&1; then
        log_error "自定义 HTTPS 证书内容无效, 请检查证书格式"
        exit 1
    fi

    if ! openssl pkey -in "$key_file" -noout >/dev/null 2>&1; then
        log_error "自定义 HTTPS 私钥内容无效, 请检查私钥格式"
        exit 1
    fi

    cert_pubkey_sha="$(openssl x509 -in "$cert_file" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
    key_pubkey_sha="$(openssl pkey -in "$key_file" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"

    if [[ -z "$cert_pubkey_sha" ]] || [[ -z "$key_pubkey_sha" ]] || [[ "$cert_pubkey_sha" != "$key_pubkey_sha" ]]; then
        log_error "自定义 HTTPS 证书与私钥不匹配, 请检查 cert.pem 和 cert.key 是否为同一对"
        exit 1
    fi
}

# 从容器可见路径导入自定义 HTTPS 证书并持久化到 /data.
# 参数: $1: 持久化证书路径.
# 参数: $2: 持久化私钥路径.
import_https_certificate_from_files() {
    local cert_file="$1"
    local key_file="$2"

    if [[ ! -f "$BLOG_HTTPS_CERT_FILE" || ! -f "$BLOG_HTTPS_KEY_FILE" ]]; then
        log_error "自定义 HTTPS 证书路径不存在或容器不可见, 请检查 BLOG_HTTPS_CERT_FILE 或 BLOG_HTTPS_KEY_FILE; 若希望继续使用当前路径, 请在 docker run 中额外添加 -v $BLOG_HTTPS_CERT_FILE:$BLOG_HTTPS_CERT_FILE:ro 和 -v $BLOG_HTTPS_KEY_FILE:$BLOG_HTTPS_KEY_FILE:ro, 或先复制到 /data/blog-client/nginx/ssl"
        exit 1
    fi

    cp "$BLOG_HTTPS_CERT_FILE" "$cert_file"
    cp "$BLOG_HTTPS_KEY_FILE" "$key_file"
}

ensure_https_certificate() {
    local cert_file="$BLOG_HTTPS_CERT_DIR/cert.pem"
    local key_file="$BLOG_HTTPS_CERT_DIR/cert.key"
    local dns_names="localhost,$BLOG_PUBLIC_HOST"
    local ip_names="127.0.0.1"

    # 证书目录可能包含只读 bind mount 的 cert.pem / cert.key, 这里仅调整目录本身权限, 避免对挂载文件递归 chown.
    ensure_directory "$BLOG_CLIENT_NGINX_DIR" root 755 false
    ensure_directory "$BLOG_HTTPS_CERT_DIR" root 700 false
    migrate_legacy_https_certificate_if_needed

    if [[ -n "$BLOG_HTTPS_CERT_FILE" || -n "$BLOG_HTTPS_KEY_FILE" ]]; then
        if [[ -z "$BLOG_HTTPS_CERT_FILE" || -z "$BLOG_HTTPS_KEY_FILE" ]]; then
            log_error "自定义 HTTPS 证书必须同时提供 BLOG_HTTPS_CERT_FILE 和 BLOG_HTTPS_KEY_FILE"
            exit 1
        fi

        import_https_certificate_from_files "$cert_file" "$key_file"

        validate_https_certificate_pair "$cert_file" "$key_file"
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        log_info "已加载自定义 HTTPS 证书, 并持久化到: $BLOG_HTTPS_CERT_DIR"
        return 0
    fi

    if [[ -f "$cert_file" ]] && [[ -f "$key_file" ]]; then
        return 0
    fi

    if is_ipv4 "$BLOG_PUBLIC_HOST"; then
        ip_names="$ip_names,$BLOG_PUBLIC_HOST"
    fi

    generate_signed_cert "cert" "$BLOG_HTTPS_CERT_DIR" "$BLOG_PUBLIC_HOST" "$dns_names" "$ip_names"
    mv "$BLOG_HTTPS_CERT_DIR/cert.crt" "$cert_file"
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
    log_info "已生成默认 HTTPS 证书, 可导出 CA 证书: $BLOG_INTERNAL_CERT_DIR/ca.crt"
}

ensure_postgres_files() {
    local postgres_conf_file="$BLOG_POSTGRES_CONF_DIR/postgresql.conf"
    local pg_hba_file="$BLOG_POSTGRES_CONF_DIR/pg_hba.conf"

    ensure_directory "$BLOG_POSTGRES_DATA_DIR" postgres:postgres 700
    ensure_directory "$BLOG_POSTGRES_CLUSTER_DIR" postgres:postgres 700
    ensure_directory "$BLOG_POSTGRES_CONF_DIR" postgres:postgres 700
    ensure_directory "$BLOG_POSTGRES_DATA_DIR/log" postgres:postgres 700

    if [[ ! -f "$postgres_conf_file" ]]; then
        cat >"$postgres_conf_file" <<EOF
listen_addresses = '*'
port = $BLOG_PG_PORT
password_encryption = scram-sha-256
    max_connections = $BLOG_PG_MAX_CONNECTIONS
    shared_buffers = $BLOG_PG_SHARED_BUFFERS
timezone = 'Asia/Shanghai'
logging_collector = on
log_directory = '$BLOG_POSTGRES_DATA_DIR/log'
unix_socket_directories = '/var/run/postgresql'
EOF
        chown postgres:postgres "$postgres_conf_file"
    fi

    if [[ ! -f "$pg_hba_file" ]]; then
        cat >"$pg_hba_file" <<EOF
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF
        chown postgres:postgres "$pg_hba_file"
    fi
}

init_postgres_data() {
    local initdb_bin=""

    if [[ -s "$BLOG_POSTGRES_CLUSTER_DIR/PG_VERSION" ]]; then
        return 0
    fi

    ensure_postgres_files
    chown -R postgres:postgres "$BLOG_POSTGRES_DATA_DIR"
    initdb_bin="$(require_postgres_binary initdb)"
    su -s /bin/bash postgres -c "'$initdb_bin' -D '$BLOG_POSTGRES_CLUSTER_DIR' >/dev/null"
}

start_postgres() {
    local postgres_bin=""

    ensure_postgres_files
    init_postgres_data

    postgres_bin="$(require_postgres_binary postgres)"
    su -s /bin/bash postgres -c "'$postgres_bin' -D '$BLOG_POSTGRES_CLUSTER_DIR' -c config_file='$BLOG_POSTGRES_CONF_DIR/postgresql.conf' -c hba_file='$BLOG_POSTGRES_CONF_DIR/pg_hba.conf' -c max_connections='$BLOG_PG_MAX_CONNECTIONS' -c shared_buffers='$BLOG_PG_SHARED_BUFFERS'" &
    POSTGRES_PID=$!
}

wait_for_postgres() {
    local retries=60

    until pg_isready -p "$BLOG_PG_PORT" -U postgres >/dev/null 2>&1; do
        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            log_error "PostgreSQL 启动超时"
            exit 1
        fi
        sleep 2
    done
}

ensure_postgres_app_db() {
    psql -p "$BLOG_PG_PORT" -U postgres -d postgres <<EOF >/dev/null
DO
\$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$BLOG_POSTGRES_USER') THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '$BLOG_POSTGRES_USER', '$BLOG_POSTGRES_PASSWORD');
    ELSE
        EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', '$BLOG_POSTGRES_USER', '$BLOG_POSTGRES_PASSWORD');
    END IF;
END
\$\$;
EOF

    if ! psql -p "$BLOG_PG_PORT" -U postgres -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname = '$BLOG_POSTGRES_DB'" | grep -q '^1$'; then
        psql -p "$BLOG_PG_PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 <<EOF >/dev/null
CREATE DATABASE "$BLOG_POSTGRES_DB" OWNER "$BLOG_POSTGRES_USER";
EOF
    fi
}

ensure_es_default_config_files() {
    local es_conf_dir="$1"

    if [[ ! -f "$es_conf_dir/log4j2.properties" ]]; then
        cp /opt/elasticsearch/config/log4j2.properties "$es_conf_dir/log4j2.properties"
    fi

    if [[ ! -f "$es_conf_dir/jvm.options" ]]; then
        cp /opt/elasticsearch/config/jvm.options "$es_conf_dir/jvm.options"
    fi

    if [[ ! -d "$es_conf_dir/jvm.options.d" ]] && [[ -d /opt/elasticsearch/config/jvm.options.d ]]; then
        cp -r /opt/elasticsearch/config/jvm.options.d "$es_conf_dir/jvm.options.d"
    fi

    if [[ ! -d "$es_conf_dir/analysis-ik" ]] && [[ -d /opt/elasticsearch/config/analysis-ik ]]; then
        cp -r /opt/elasticsearch/config/analysis-ik "$es_conf_dir/analysis-ik"
    fi
}

ensure_redis_config() {
    local redis_conf_file="$BLOG_REDIS_DATA_DIR/redis.conf"
    local redis_bloom_module_file="/usr/local/lib/redis/modules/redisbloom.so"

    ensure_directory "$BLOG_REDIS_DATA_DIR" root 700
    ensure_directory "$BLOG_REDIS_DATA_DIR/data" root 700

    cat >"$redis_conf_file" <<EOF
bind 0.0.0.0
port $BLOG_REDIS_PORT
protected-mode no
daemonize no
appendonly yes
appendfilename "appendonly.aof"
dir $BLOG_REDIS_DATA_DIR/data
requirepass $BLOG_REDIS_PASSWORD
loglevel warning
EOF

    if [[ -f "$redis_bloom_module_file" ]]; then
        printf '%s\n' "loadmodule $redis_bloom_module_file" >>"$redis_conf_file"
    fi
}

start_redis() {
    ensure_redis_config
    redis-server "$BLOG_REDIS_DATA_DIR/redis.conf" &
    REDIS_PID=$!
}

wait_for_redis() {
    local retries=30

    until redis-cli -h 127.0.0.1 -p "$BLOG_REDIS_PORT" -a "$BLOG_REDIS_PASSWORD" ping >/dev/null 2>&1; do
        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            log_error "Redis 启动超时"
            exit 1
        fi
        sleep 1
    done
}

ensure_es_certificates() {
    local es_cert_dir="$BLOG_ES_DATA_DIR/certs"
    local dns_names="localhost,$BLOG_PUBLIC_HOST"
    local ip_names="127.0.0.1"

    ensure_directory "$es_cert_dir" elasticsearch:elasticsearch 700

    if [[ -f "$es_cert_dir/es.crt" && -f "$es_cert_dir/es.key" ]]; then
        return 0
    fi

    if is_ipv4 "$BLOG_PUBLIC_HOST"; then
        ip_names="$ip_names,$BLOG_PUBLIC_HOST"
    fi

    generate_signed_cert "es" "$es_cert_dir" "$BLOG_PUBLIC_HOST" "$dns_names" "$ip_names"
    chown -R elasticsearch:elasticsearch "$es_cert_dir"
}

# 将 Elasticsearch 读取的 SSL 文件同步到 config 目录.
# 说明: Elasticsearch 9.x 通过 entitlement 限制证书读取路径, SSL 资源必须放在 ES_PATH_CONF 内.
sync_es_ssl_files_to_config() {
    local es_conf_dir="$1"
    local es_cert_dir="$BLOG_ES_DATA_DIR/certs"

    cp "$BLOG_INTERNAL_CERT_DIR/ca.crt" "$es_conf_dir/ca.crt"
    cp "$es_cert_dir/es.crt" "$es_conf_dir/es.crt"
    cp "$es_cert_dir/es.key" "$es_conf_dir/es.key"

    chown elasticsearch:elasticsearch "$es_conf_dir/ca.crt" "$es_conf_dir/es.crt" "$es_conf_dir/es.key"
    chmod 644 "$es_conf_dir/ca.crt" "$es_conf_dir/es.crt"
    chmod 600 "$es_conf_dir/es.key"
}

ensure_es_keystore() {
    local es_conf_dir="$BLOG_ES_DATA_DIR/config"
    local keystore_file="$es_conf_dir/elasticsearch.keystore"

    if [[ ! -f "$keystore_file" ]]; then
        su -s /bin/bash elasticsearch -c "ES_PATH_CONF='$es_conf_dir' /opt/elasticsearch/bin/elasticsearch-keystore create" >/dev/null 2>&1
    fi

    if ! su -s /bin/bash elasticsearch -c "ES_PATH_CONF='$es_conf_dir' /opt/elasticsearch/bin/elasticsearch-keystore list" | grep -q '^bootstrap.password$'; then
        printf '%s' "$BLOG_ES_PASSWORD" | su -s /bin/bash elasticsearch -c "ES_PATH_CONF='$es_conf_dir' /opt/elasticsearch/bin/elasticsearch-keystore add -x bootstrap.password" >/dev/null 2>&1
    fi
}

ensure_es_files() {
    local es_conf_dir="$BLOG_ES_DATA_DIR/config"
    local es_data_dir="$BLOG_ES_DATA_DIR/data"
    local es_logs_dir="$BLOG_ES_DATA_DIR/logs"
    local es_conf_file="$es_conf_dir/elasticsearch.yml"

    ensure_directory "$BLOG_ES_DATA_DIR" elasticsearch:elasticsearch 700
    ensure_directory "$es_conf_dir" elasticsearch:elasticsearch 700
    ensure_directory "$es_data_dir" elasticsearch:elasticsearch 700
    ensure_directory "$es_logs_dir" elasticsearch:elasticsearch 700
    ensure_es_certificates
    ensure_es_default_config_files "$es_conf_dir"
    sync_es_ssl_files_to_config "$es_conf_dir"

    cat >"$es_conf_file" <<EOF
cluster.name: blog
node.name: blog-node
path.data: $es_data_dir
path.logs: $es_logs_dir
logger.level: warn
network.host: 0.0.0.0
http.port: $BLOG_ES_PORT
discovery.type: single-node
node.roles: [ master, data, ingest ]
action.destructive_requires_name: true
xpack.ml.enabled: false
ingest.geoip.downloader.enabled: false
xpack.security.enabled: true
xpack.security.enrollment.enabled: false
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: $es_conf_dir/es.key
xpack.security.http.ssl.certificate: $es_conf_dir/es.crt
xpack.security.http.ssl.certificate_authorities: [ "$es_conf_dir/ca.crt" ]
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.key: $es_conf_dir/es.key
xpack.security.transport.ssl.certificate: $es_conf_dir/es.crt
xpack.security.transport.ssl.certificate_authorities: [ "$es_conf_dir/ca.crt" ]
bootstrap.memory_lock: false
http.max_content_length: 100mb
node.store.allow_mmap: false
EOF

    chown -R elasticsearch:elasticsearch "$BLOG_ES_DATA_DIR"
    ensure_es_keystore
}

start_elasticsearch() {
    ensure_es_files

    su -s /bin/bash elasticsearch -c "ES_PATH_CONF='$BLOG_ES_DATA_DIR/config' ES_JAVA_OPTS='$BLOG_ES_JAVA_OPTS' /opt/elasticsearch/bin/elasticsearch" &
    ES_PID=$!
}

# 先等待 ES HTTPS 监听可用, 避免过早发起带认证请求触发多余的安全索引错误日志.
wait_for_elasticsearch_http_ready() {
    local retries=120
    local status_code=""

    while true; do
        if [[ -n "$ES_PID" ]] && ! kill -0 "$ES_PID" >/dev/null 2>&1; then
            print_recent_elasticsearch_logs
            log_error "Elasticsearch 进程已提前退出"
            exit 1
        fi

        status_code="$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$BLOG_ES_PORT/" || true)"
        if [[ "$status_code" == "200" ]] || [[ "$status_code" == "401" ]]; then
            return 0
        fi

        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            print_recent_elasticsearch_logs
            log_error "Elasticsearch HTTPS 监听启动超时"
            exit 1
        fi
        sleep 2
    done
}

# 在 ES 启动失败时打印最近日志, 便于定位低内存或配置问题.
print_recent_elasticsearch_logs() {
    local es_log_file=""

    es_log_file="$(find "$BLOG_ES_DATA_DIR/logs" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2- || true)"
    if [[ -n "$es_log_file" ]] && [[ -f "$es_log_file" ]]; then
        log_warn "Elasticsearch 最近日志($es_log_file):"
        tail -n 80 "$es_log_file" >&2 || true
    fi
}

wait_for_elasticsearch() {
    local retries=40

    wait_for_elasticsearch_http_ready

    # HTTPS 监听可用后额外留出一点时间, 等待 security 索引和保留用户初始化完成.
    sleep 5

    until curl -sk --cacert "$BLOG_INTERNAL_CERT_DIR/ca.crt" -u "$BLOG_ES_USER:$BLOG_ES_PASSWORD" "https://127.0.0.1:$BLOG_ES_PORT/_security/_authenticate" >/dev/null 2>&1; do
        if [[ -n "$ES_PID" ]] && ! kill -0 "$ES_PID" >/dev/null 2>&1; then
            print_recent_elasticsearch_logs
            log_error "Elasticsearch 进程已提前退出"
            exit 1
        fi

        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            print_recent_elasticsearch_logs
            log_error "Elasticsearch 启动超时"
            exit 1
        fi
        sleep 3
    done
}

# 在 Elasticsearch 就绪后写入默认索引模板.
# 说明: Elasticsearch 9.x 不允许在 node settings 中声明 index.* 级配置,
# 这里改为通过模板下发默认的 index.max_result_window.
ensure_es_index_defaults() {
    local retries=30
    local template_payload='{"index_patterns":["*"],"priority":1,"template":{"settings":{"index.max_result_window":100000}}}'

    until curl -sk --cacert "$BLOG_INTERNAL_CERT_DIR/ca.crt" \
        -u "$BLOG_ES_USER:$BLOG_ES_PASSWORD" \
        -H 'Content-Type: application/json' \
        -X PUT \
        "https://127.0.0.1:$BLOG_ES_PORT/_index_template/blog-defaults" \
        -d "$template_payload" >/dev/null 2>&1; do
        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            log_error "Elasticsearch 默认索引模板初始化失败"
            exit 1
        fi
        sleep 2
    done
}

copy_server_defaults_if_needed() {
    if [[ ! -d "$BLOG_SERVER_DATA_DIR/config" ]]; then
        mkdir -p "$BLOG_SERVER_DATA_DIR"
        cp -r /home/blog-server/config "$BLOG_SERVER_DATA_DIR/config"
    fi

    mkdir -p "$BLOG_SERVER_DATA_DIR/uploads" "$BLOG_SERVER_DATA_DIR/logs"
    rm -rf /home/blog-server/config /home/blog-server/uploads /home/blog-server/logs
    ln -s "$BLOG_SERVER_DATA_DIR/config" /home/blog-server/config
    ln -s "$BLOG_SERVER_DATA_DIR/uploads" /home/blog-server/uploads
    ln -s "$BLOG_SERVER_DATA_DIR/logs" /home/blog-server/logs
    chown -R blog-server:blog-server "$BLOG_SERVER_DATA_DIR"
}

replace_yaml_block() {
    local yaml_file="$1"
    local block_key="$2"
    local block_source_file="$3"
    local tmp_file="$yaml_file.tmp"

    awk -v block_key="$block_key" -v block_source_file="$block_source_file" '
        BEGIN {
            block_content = ""
            while ((getline line < block_source_file) > 0) {
                block_content = block_content "  " line "\n"
            }
            close(block_source_file)
            replaced = 0
            skipping = 0
        }
        {
            if ($0 ~ "^" block_key ": \\|$") {
                print block_key ": |"
                printf "%s", block_content
                replaced = 1
                skipping = 1
                next
            }
            if (skipping == 1) {
                if ($0 ~ /^[^[:space:]]/) {
                    skipping = 0
                } else {
                    next
                }
            }
            print
        }
        END {
            if (replaced == 0) {
                print block_key ": |"
                printf "%s", block_content
            }
        }
    ' "$yaml_file" >"$tmp_file"

    mv "$tmp_file" "$yaml_file"
}

ensure_server_config() {
    local app_yaml="/home/blog-server/config/app.yaml"
    local pgsql_yaml="/home/blog-server/config/pgsql.yaml"
    local redis_yaml="/home/blog-server/config/redis.yaml"
    local es_yaml="/home/blog-server/config/es.yaml"
    local public_url=""

    copy_server_defaults_if_needed
    public_url="$(server_public_url)"

    sed -ri "s|^([[:space:]]*)host:[[:space:]].*|\1host: \"$public_url\"|" "$app_yaml"
    sed -ri "s|^([[:space:]]*)name:[[:space:]].*|\1name: \"$BLOG_PROJECT_NAME\"|" "$app_yaml"
    sed -ri "s|^([[:space:]]*)port:[[:space:]].*|\1port: $BLOG_SERVER_PORT|" "$app_yaml"
    sed -ri "s|^([[:space:]]*)is_setup:[[:space:]].*|\1is_setup: true|" "$app_yaml"

    sed -ri "s|^([[:space:]]*)host:[[:space:]].*|\1host: \"127.0.0.1\"|" "$pgsql_yaml"
    sed -ri "s|^([[:space:]]*)port:[[:space:]].*|\1port: $BLOG_PG_PORT|" "$pgsql_yaml"
    sed -ri "s|^([[:space:]]*)user:[[:space:]].*|\1user: \"$BLOG_POSTGRES_USER\"|" "$pgsql_yaml"
    sed -ri "s|^([[:space:]]*)password:[[:space:]].*|\1password: \"$BLOG_POSTGRES_PASSWORD\"|" "$pgsql_yaml"
    sed -ri "s|^([[:space:]]*)database:[[:space:]].*|\1database: \"$BLOG_POSTGRES_DB\"|" "$pgsql_yaml"

    sed -ri '0,/^[[:space:]]*-[[:space:]]*host:/s|^([[:space:]]*-[[:space:]]*host:).*|\1 "127.0.0.1"|' "$redis_yaml"
    sed -ri '0,/^[[:space:]]*password:/s|^([[:space:]]*password:).*|\1 "'"$BLOG_REDIS_PASSWORD"'"|' "$redis_yaml"
    sed -ri '0,/^[[:space:]]*port:/s|^([[:space:]]*port:).*|\1 '"$BLOG_REDIS_PORT"'|' "$redis_yaml"

    sed -ri '0,/^[[:space:]]*-[[:space:]]*"https:\/\//s|^([[:space:]]*-[[:space:]]*).*$|\1"https://127.0.0.1:'"$BLOG_ES_PORT"'"|' "$es_yaml"
    sed -ri "s|^([[:space:]]*)user:[[:space:]].*|\1user: \"$BLOG_ES_USER\"|" "$es_yaml"
    sed -ri "s|^([[:space:]]*)password:[[:space:]].*|\1password: \"$BLOG_ES_PASSWORD\"|" "$es_yaml"
    sed -ri "s|^([[:space:]]*)use_ca_cert:[[:space:]].*|\1use_ca_cert: true|" "$es_yaml"
    replace_yaml_block "$es_yaml" "ca_cert" "$BLOG_INTERNAL_CERT_DIR/ca.crt"

    if ! grep -q '^secret_key:' /home/blog-server/config/jwt.yaml; then
        printf 'secret_key: "%s"\n' "$BLOG_JWT_SECRET_KEY" >>/home/blog-server/config/jwt.yaml
    else
        sed -ri "s|^([[:space:]]*)secret_key:[[:space:]].*|\1secret_key: \"$BLOG_JWT_SECRET_KEY\"|" /home/blog-server/config/jwt.yaml
    fi

    chown -R blog-server:blog-server "$BLOG_SERVER_DATA_DIR"
}

start_blog_server() {
    ensure_server_config

    su -s /bin/bash blog-server -c "cd /home/blog-server && ./boot -config /home/blog-server/config/app.yaml -app /home/blog-server/blog-server" &
    SERVER_PID=$!
}

wait_for_blog_server() {
    local retries=90

    until curl -s --max-time 5 "http://127.0.0.1:$BLOG_SERVER_PORT/api/v1/is-setup" >/dev/null 2>&1; do
        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            log_error "blog-server 启动超时"
            exit 1
        fi
        sleep 2
    done
}

# start_nitro 启动 Nuxt Nitro SSR 服务.
# 参数: 无.
# 返回: 成功后记录 NITRO_PID, 启动失败由后续就绪检查终止容器.
start_nitro() {
    prepare_nitro_runtime || exit 1
    node /app/.output/server/index.mjs &
    NITRO_PID=$!
}

# wait_for_nitro 等待 Nuxt Nitro 监听本机端口.
# 参数: 无.
# 返回: 服务就绪返回 0, 进程退出或超时则退出容器.
wait_for_nitro() {
    local retries=30

    until (echo >/dev/tcp/127.0.0.1/"$BLOG_NITRO_PORT") >/dev/null 2>&1; do
        if ! kill -0 "$NITRO_PID" >/dev/null 2>&1; then
            log_error "Nuxt Nitro 启动期间退出"
            exit 1
        fi

        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            log_error "Nuxt Nitro 启动超时"
            exit 1
        fi
        sleep 1
    done
}

# start_nginx 渲染 Nuxt nginx 模板后启动 nginx 前台进程.
# 参数: 无.
# 返回: 成功后记录 NGINX_PID, 配置渲染、校验或 nginx 启动失败时退出容器.
start_nginx() {
    ensure_client_nginx_config
    if ! nginx -t; then
        log_error "Nuxt nginx 配置校验失败"
        exit 1
    fi
    nginx -g 'daemon off;' &
    NGINX_PID=$!
}

# record_pids 将关键服务 PID 写入持久化目录供外部诊断.
# 参数: 无.
# 返回: 写入成功返回 0, 文件系统失败时返回非 0.
record_pids() {
    cat >"$BLOG_PIDS_FILE" <<EOF
POSTGRES_PID=$POSTGRES_PID
REDIS_PID=$REDIS_PID
ES_PID=$ES_PID
SERVER_PID=$SERVER_PID
NITRO_PID=$NITRO_PID
NGINX_PID=$NGINX_PID
EOF
}

# stop_services 以依赖反向顺序停止 single 内的全部关键服务.
# 参数: 无.
# 返回: 始终返回 0, 单个服务停止失败会继续清理其余服务.
stop_services() {
    local pg_ctl_bin=""

    set +e

    if [[ -n "$NGINX_PID" ]]; then
        kill "$NGINX_PID" >/dev/null 2>&1 || true
    fi

    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
    fi

    if [[ -n "$NITRO_PID" ]]; then
        kill "$NITRO_PID" >/dev/null 2>&1 || true
    fi

    if [[ -n "$ES_PID" ]]; then
        kill "$ES_PID" >/dev/null 2>&1 || true
    fi

    if [[ -n "$REDIS_PID" ]]; then
        redis-cli -h 127.0.0.1 -p "$BLOG_REDIS_PORT" -a "$BLOG_REDIS_PASSWORD" shutdown >/dev/null 2>&1 || kill "$REDIS_PID" >/dev/null 2>&1 || true
    fi

    if [[ -n "$POSTGRES_PID" ]]; then
        pg_ctl_bin="$(require_postgres_binary pg_ctl)"
        su -s /bin/bash postgres -c "'$pg_ctl_bin' -D '$BLOG_POSTGRES_CLUSTER_DIR' -m fast stop" >/dev/null 2>&1 || kill "$POSTGRES_PID" >/dev/null 2>&1 || true
    fi
}

handle_signal() {
    log_warn "接收到停止信号, 开始关闭所有服务"
    stop_services
    exit 0
}

show_boot_summary() {
    log_info "blog 启动完成"
    log_info "访问地址: $(server_public_url)"
    log_info "对外访问主机来源: $BLOG_PUBLIC_HOST_SOURCE"
    log_info "默认仅提供 HTTPS 访问, 误用 http:// 访问 443 端口时会自动跳转到 https://"
    log_warn "若使用 docker run 启动容器, 仍需显式添加端口映射, 例如: -p ${BLOG_HTTPS_PORT}:${BLOG_HTTPS_PORT}; 否则宿主机或局域网无法直接访问 HTTPS 页面"
    log_info "CA 证书导出路径: $BLOG_INTERNAL_CERT_DIR/ca.crt"
    log_info "若需连接数据库, 请映射容器端口: pgsql=$BLOG_PG_PORT redis=$BLOG_REDIS_PORT es=$BLOG_ES_PORT"

    if [[ "$BLOG_PUBLIC_HOST_SOURCE" == "default" ]]; then
        log_warn "当前未显式传入 BLOG_PUBLIC_HOST、DOMAIN_NAME 或 HOST_INTRANET_IP, 访问地址暂回退为 https://$BLOG_PUBLIC_HOST。若需宿主机或局域网访问, 请在宿主机执行: HOST_IP=\"\$(hostname -I | awk '{print \$1}')\" && sudo docker run ... -e BLOG_PUBLIC_HOST=\"\$HOST_IP\""
    fi
}

main() {
    trap handle_signal INT TERM

    normalize_public_host
    resolve_memory_profile
    warn_if_vm_overcommit_disabled
    ensure_runtime_secrets
    gen_ca_cert
    ensure_https_certificate

    start_postgres
    wait_for_postgres
    ensure_postgres_app_db

    start_redis
    wait_for_redis

    start_elasticsearch
    wait_for_elasticsearch
    ensure_es_index_defaults

    start_blog_server
    wait_for_blog_server

    start_nitro
    wait_for_nitro

    start_nginx
    record_pids
    show_boot_summary

    if ! wait -n "$POSTGRES_PID" "$REDIS_PID" "$ES_PID" "$SERVER_PID" "$NITRO_PID" "$NGINX_PID"; then
        local exit_code=$?
        log_error "检测到关键服务退出, 容器即将停止"
        stop_services
        exit "$exit_code"
    fi
}

main "$@"