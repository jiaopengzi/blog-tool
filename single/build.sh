#!/bin/bash
# FilePath    : blog-tool/single/build.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 单镜像构建与推送工具.

# shellcheck disable=SC2034,SC2153,SC2154

SINGLE_IMAGE_NAME="blog"                                        # 单镜像名称
SINGLE_ENV_IMAGE_NAME="$SINGLE_IMAGE_NAME:env"                 # 单镜像运行时环境镜像
SINGLE_CONTEXT_PARENT_DIR="${BLOG_TOOL_ENV:-$ROOT_DIR/volume/blog_tool_env}/single-image"
SINGLE_DOWNLOAD_CACHE_DIR="${BLOG_TOOL_ENV:-$ROOT_DIR/volume/blog_tool_env}/single-image-cache" # single 下载缓存目录, 独立于构建上下文保留
SINGLE_CONTEXT_DIR="$SINGLE_CONTEXT_PARENT_DIR/context"         # 单镜像构建上下文目录
SINGLE_CONTEXT_DOWNLOAD_CACHE_DIR="$SINGLE_CONTEXT_DIR/blog-cache" # 单镜像上下文下载缓存目录
SINGLE_DOCKERFILE_RELATIVE="single/docker/Dockerfile"           # 单镜像全量 Dockerfile 相对路径
SINGLE_DOCKERFILE_ENV_RELATIVE="single/docker/env.Dockerfile"   # 单镜像运行时环境 Dockerfile 相对路径
SINGLE_DOCKERFILE_BUILD_RELATIVE="single/docker/build.Dockerfile" # 单镜像装配 Dockerfile 相对路径
SINGLE_TOOL_ROOT=""                                             # blog-tool 根目录, 仅在源码模式下需要
SINGLE_PUSH_REPO_ENABLED="false"                                # 是否显式启用默认公开私有仓库推送
SINGLE_PUSH_TENCENT_ENABLED="false"                             # 是否显式启用腾讯云仓库推送
SINGLE_PUSH_DOCKER_HUB_ENABLED="false"                          # 是否显式启用 Docker Hub 推送
SINGLE_COMPONENT_SERVER_VERSION=""                              # 最近一次从镜像中解析出的后端版本号
SINGLE_COMPONENT_CLIENT_VERSION=""                              # 最近一次从镜像中解析出的前端版本号
SINGLE_BUILD_SERVER_VERSION=""                                  # 本次 single 构建指定的后端版本号
SINGLE_BUILD_CLIENT_VERSION=""                                  # 本次 single 构建指定的前端版本号

# 解析 single 部署阶段默认对外主机名.
# 说明: 优先使用 DOMAIN_NAME, 未设置时回退为宿主机内网 IP, 与 --auto 的 deploy 语义保持一致.
single_resolve_default_public_host() {
    if [[ -n "${DOMAIN_NAME:-}" ]]; then
        echo "$DOMAIN_NAME"
        return 0
    fi

    if [[ -n "${HOST_INTRANET_IP:-}" ]]; then
        echo "$HOST_INTRANET_IP"
        return 0
    fi

    if declare -F detect_host_intranet_ip >/dev/null 2>&1; then
        local detected_host_ip=""

        detected_host_ip="$(detect_host_intranet_ip)"
        if [[ -n "$detected_host_ip" ]] && [[ "$detected_host_ip" != "127.0.0.1" ]]; then
            echo "$detected_host_ip"
            return 0
        fi
    fi

    echo "127.0.0.1"
}

# 输出 single 本地运行建议命令.
# 参数: $1: 镜像引用, 例如 blog:build.
single_print_run_hint() {
    local image_ref="$1"
    local public_host=""

    public_host="$(single_resolve_default_public_host)"

    log_info "局域网部署建议对外地址: https://$public_host"
    log_info "本地运行示例: HOST_IP=\"\$(hostname -I | awk '{print \$1}')\" && sudo docker run -d --name blog -p 443:443 -v /data/blog:/data -e BLOG_PUBLIC_HOST=\"\$HOST_IP\" $image_ref"
    log_info "如需域名访问, 请在 run 阶段覆盖为: -e BLOG_PUBLIC_HOST=your.domain; 兼容旧变量: -e DOMAIN_NAME=your.domain"
}

# 检查本地可复用镜像是否存在.
# 参数: $1: 镜像名.
single_has_local_image() {
    local image_name="$1"

    sudo docker image inspect "$image_name" >/dev/null 2>&1
}

# 判断当前是否具备镜像签名条件.
single_can_sign_image() {
    [[ -n "${COSIGN_PRIVATE_KEY:-}" ]] && [[ -n "${COSIGN_PRIVATE_KEY_PWD:-}" ]]
}

# 输出单镜像帮助信息.
single_print_help() {
    cat <<EOF
用法:
    sudo bash blog-tool-dev.sh --env-single
    sudo bash blog-tool-dev.sh --build-single --server v1.0.0 --client v1.0.0
    sudo bash blog-tool-dev.sh --push-single --repo

参数:
    --server                      仅对 --build-single 生效, 指定要拉取的 blog-server 版本.
    --client                      仅对 --build-single 生效, 指定要拉取的 blog-client 版本.
    --repo                        仅对 --push-single 生效, 显式推送到 REGISTRY_REMOTE_SERVER_PUBLIC.
    --tencent                     仅对 --push-single 生效, 显式推送到 REGISTRY_REMOTE_SERVER_TENCENT.
    --docker-hub                  仅对 --push-single 生效, 显式推送到 Docker Hub.
  -h, --help                    查看帮助信息.

说明:
    1. --env-single 负责构建 blog:env, 供后续单镜像装配复用.
    2. --build-single 负责装配 blog:build, 必须显式传入 --server 与 --client, 构建时会直接拉取 jiaopengzi/blog-server 与 jiaopengzi/blog-client 对应版本, 再计算 single 版本.
    3. --push-single 需要显式指定至少一个远端仓库, 例如 --repo, --tencent, --docker-hub; 推送版本默认使用最近一次构建自动计算出的 single 版本.
    4. 单镜像推送支持任意组合选择多个目标仓库, 会按 repo -> tencent -> docker-hub 顺序执行.
    5. REGISTRY_REMOTE_SERVER_PUBLIC 与 REGISTRY_REMOTE_SERVER 共用用户名和密码.
    6. 装配阶段直接消费 jiaopengzi/blog-client 与 jiaopengzi/blog-server 的已发布镜像, single/docker/build.Dockerfile 不再自行构建前后端产物.
EOF
}

# 解析 single 命令参数.
# 参数: $1: 动作类型, env | build | push.
# 参数: $@: 命令行参数.
single_parse_cli_args() {
    local single_action="$1"

    SINGLE_PUSH_REPO_ENABLED="false"
    SINGLE_PUSH_TENCENT_ENABLED="false"
    SINGLE_PUSH_DOCKER_HUB_ENABLED="false"
    SINGLE_BUILD_SERVER_VERSION=""
    SINGLE_BUILD_CLIENT_VERSION=""

    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --version|--single-version)
            log_error "single 版本由 server 和 client 的版本自动计算, 不支持手动指定 $1"
            return 1
            ;;
        --version=*|--single-version=*)
            log_error "single 版本由 server 和 client 的版本自动计算, 不支持手动指定 ${1%%=*}"
            return 1
            ;;
        --server=*)
            if [[ "$single_action" != "build" ]]; then
                log_error "参数 --server 仅支持与 --build-single 一起使用"
                return 1
            fi
            SINGLE_BUILD_SERVER_VERSION="${1#*=}"
            ;;
        --server)
            if [[ "$single_action" != "build" ]]; then
                log_error "参数 --server 仅支持与 --build-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --server 缺少版本值"
                return 1
            fi
            SINGLE_BUILD_SERVER_VERSION="$1"
            ;;
        --client=*)
            if [[ "$single_action" != "build" ]]; then
                log_error "参数 --client 仅支持与 --build-single 一起使用"
                return 1
            fi
            SINGLE_BUILD_CLIENT_VERSION="${1#*=}"
            ;;
        --client)
            if [[ "$single_action" != "build" ]]; then
                log_error "参数 --client 仅支持与 --build-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --client 缺少版本值"
                return 1
            fi
            SINGLE_BUILD_CLIENT_VERSION="$1"
            ;;
        --repo)
            if [[ "$single_action" != "push" ]]; then
                log_error "参数 --repo 仅支持与 --push-single 一起使用"
                return 1
            fi
            SINGLE_PUSH_REPO_ENABLED="true"
            ;;
        --tencent)
            if [[ "$single_action" != "push" ]]; then
                log_error "参数 --tencent 仅支持与 --push-single 一起使用"
                return 1
            fi
            SINGLE_PUSH_TENCENT_ENABLED="true"
            ;;
        --docker-hub)
            if [[ "$single_action" != "push" ]]; then
                log_error "参数 --docker-hub 仅支持与 --push-single 一起使用"
                return 1
            fi
            SINGLE_PUSH_DOCKER_HUB_ENABLED="true"
            ;;
        -h|--help)
            single_print_help
            return 2
            ;;
        *)
            log_error "不支持的参数: $1"
            return 1
            ;;
        esac

        shift
    done

    if [[ "$single_action" == "push" ]] \
        && [[ "$SINGLE_PUSH_REPO_ENABLED" != "true" ]] \
        && [[ "$SINGLE_PUSH_TENCENT_ENABLED" != "true" ]] \
        && [[ "$SINGLE_PUSH_DOCKER_HUB_ENABLED" != "true" ]]; then
        log_error "参数 --push-single 至少需要显式指定一个远端仓库: --repo, --tencent, --docker-hub"
        return 1
    fi

    if [[ "$single_action" == "build" ]] \
        && [[ -z "$SINGLE_BUILD_SERVER_VERSION" || -z "$SINGLE_BUILD_CLIENT_VERSION" ]]; then
        log_error "参数 --build-single 必须同时指定 --server 和 --client 版本"
        return 1
    fi
}

# 确保当前功能仅在开发版工具中使用.
single_require_dev_build() {
    if ! blog_tool_build_type_is_dev; then
        log_error "单镜像构建仅支持开发版 blog-tool-dev.sh"
        return 1
    fi
}

# 检查 Docker 是否可用.
single_check_docker_ready() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "未检测到 docker 命令, 请先安装 Docker"
        return 1
    fi

    if ! sudo docker info >/dev/null 2>&1; then
        log_error "Docker daemon 不可用, 请先启动 Docker 服务"
        return 1
    fi
}

# 检查单镜像构建与推送共用的基础环境.
single_check_base_env() {
    single_require_dev_build || return 1

    check_is_root
    check_character
    check_env_path
    check_install_base
    single_check_docker_ready || return 1

    if [[ ! -d "$DATA_VOLUME_DIR" ]]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    if [[ ! -d "$BLOG_TOOL_ENV" ]]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$BLOG_TOOL_ENV"
    fi
}

# 加载单镜像公开私有仓库地址.
single_load_public_registry_env() {
    local public_registry_file="$BLOG_TOOL_ENV/public_registry_remote_server"
    local legacy_public_registry_file="$BLOG_TOOL_ENV/private_registry_remote_server_public"

    load_env_or_file_config \
        REGISTRY_REMOTE_SERVER_PUBLIC \
        REGISTRY_REMOTE_SERVER_PUBLIC \
        "$public_registry_file" \
        "单镜像公开私有仓库地址" \
        "false"

    if [[ -n "${REGISTRY_REMOTE_SERVER_PUBLIC:-}" ]]; then
        return 0
    fi

    if [[ -f "$legacy_public_registry_file" ]]; then
        load_env_or_file_config \
            REGISTRY_REMOTE_SERVER_PUBLIC \
            REGISTRY_REMOTE_SERVER_PUBLIC \
            "$legacy_public_registry_file" \
            "单镜像公开私有仓库地址(兼容旧文件)" \
            "false"

        if [[ -n "${REGISTRY_REMOTE_SERVER_PUBLIC:-}" ]]; then
            log_warn "检测到旧配置文件 $legacy_public_registry_file, 建议迁移为 $public_registry_file"
            return 0
        fi
    fi

    log_error "单镜像公开私有仓库地址未设置, 请设置环境变量 REGISTRY_REMOTE_SERVER_PUBLIC 或写入 $public_registry_file"
    return 1
}

# 加载单镜像推送所需的仓库与签名配置.
single_load_push_env() {
    local cosign_private_key_file="$BLOG_TOOL_ENV/cosign_private_key"

    single_load_public_registry_env || return 1

    load_env_or_file_config \
        REGISTRY_USER_NAME \
        REGISTRY_USER_NAME \
        "$BLOG_TOOL_ENV/private_user" \
        "公开私有仓库用户名"

    load_env_or_file_config \
        REGISTRY_PASSWORD \
        REGISTRY_PASSWORD \
        "$BLOG_TOOL_ENV/private_password" \
        "公开私有仓库密码"

    load_config_from_file_and_validate \
        REGISTRY_REMOTE_SERVER_TENCENT \
        "$BLOG_TOOL_ENV/private_registry_remote_server_tencent" \
        "腾讯仓库地址" \
        "false"

    load_env_or_file_config \
        REGISTRY_USER_NAME_TENCENT \
        REGISTRY_USER_NAME_TENCENT \
        "$BLOG_TOOL_ENV/private_user_tencent" \
        "腾讯仓库用户名" \
        "false"

    load_env_or_file_config \
        REGISTRY_PASSWORD_TENCENT \
        REGISTRY_PASSWORD_TENCENT \
        "$BLOG_TOOL_ENV/private_password_tencent" \
        "腾讯仓库密码" \
        "false"

    load_env_or_file_config \
        DOCKER_HUB_TOKEN \
        DOCKER_HUB_TOKEN \
        "$BLOG_TOOL_ENV/docker_hub_token" \
        "docker hub token" \
        "false"

    if [[ ! -f "$cosign_private_key_file" ]] && [[ -f "$BLOG_TOOL_ENV/cosign_private_key.bak" ]]; then
        cosign_private_key_file="$BLOG_TOOL_ENV/cosign_private_key.bak"
    fi

    load_env_or_file_config \
        COSIGN_PRIVATE_KEY \
        COSIGN_PRIVATE_KEY \
        "$cosign_private_key_file" \
        "cosign 私钥" \
        "false" \
        "full_content"

    load_env_or_file_config \
        COSIGN_PRIVATE_KEY_PWD \
        COSIGN_PRIVATE_KEY_PWD \
        "$BLOG_TOOL_ENV/cosign_private_key_pwd" \
        "cosign 私钥密码" \
        "false"
}

# 检查本地构建前置环境.
single_check_build_env() {
    log_debug "run single_check_build_env"

    single_check_base_env || return 1
}

# 检查远端推送前置环境.
single_check_push_env() {
    log_debug "run single_check_push_env"

    single_check_base_env || return 1
    single_load_push_env || return 1
}

# 判断给定目录是否为 blog-tool 根目录.
# 参数: $1: 待判断目录.
single_is_tool_root() {
    local candidate_dir="$1"

    [[ -f "$candidate_dir/blog-tool.code-workspace" ]] && [[ -d "$candidate_dir/single/docker" ]]
}

# 判断当前发行版是否已经内嵌 single/docker 资产.
single_has_embedded_docker_assets() {
    [[ -n "${SINGLE_DOCKER_BASE64:-}" ]]
}

# 定位 blog-tool 根目录.
# 返回: 打印 blog-tool 根目录绝对路径.
single_find_tool_root() {
    local search_dir="$ROOT_DIR"
    local parent_dir=""
    local child_dir=""
    local depth=0

    while [[ $depth -lt 6 ]]; do
        if single_is_tool_root "$search_dir"; then
            echo "$search_dir"
            return 0
        fi

        child_dir="$search_dir/blog-tool"
        if single_is_tool_root "$child_dir"; then
            echo "$child_dir"
            return 0
        fi

        parent_dir="$(dirname "$search_dir")"
        if [[ "$parent_dir" == "$search_dir" ]]; then
            break
        fi

        search_dir="$parent_dir"
        ((depth++)) || true
    done

    return 1
}

# 判断源码模式下是否具备 single/docker 文件.
single_has_source_docker_assets() {
    [[ -n "$SINGLE_TOOL_ROOT" ]] \
        && [[ -f "$SINGLE_TOOL_ROOT/$SINGLE_DOCKERFILE_RELATIVE" ]] \
        && [[ -f "$SINGLE_TOOL_ROOT/$SINGLE_DOCKERFILE_ENV_RELATIVE" ]] \
        && [[ -f "$SINGLE_TOOL_ROOT/$SINGLE_DOCKERFILE_BUILD_RELATIVE" ]]
}

# 将开发版脚本中内嵌的 single/docker 资产解压到目标目录.
# 参数: $1: 目标目录, 通常为构建上下文根目录.
single_extract_embedded_docker_assets() {
    local target_dir="$1"

    if ! single_has_embedded_docker_assets; then
        log_error "当前发行版未内嵌 single/docker 资产"
        return 1
    fi

    sudo mkdir -p "$target_dir"
    printf '%s' "$SINGLE_DOCKER_BASE64" | base64 -d | gzip -d | sudo tar -xf - -C "$target_dir"
}

# 初始化 single 构建所需的 Docker 资产与缓存路径.
single_init_build_assets() {
    log_debug "run single_init_build_assets"

    SINGLE_TOOL_ROOT=""

    if SINGLE_TOOL_ROOT="$(single_find_tool_root)"; then
        :
    fi

    if single_has_embedded_docker_assets; then
        return 0
    fi

    if ! single_has_source_docker_assets; then
        if [[ -n "$SINGLE_TOOL_ROOT" ]]; then
            log_error "未找到完整的 single/docker 源码资产, 请检查: $SINGLE_TOOL_ROOT/single/docker"
        else
            log_error "当前环境既没有 blog-tool/single/docker 源码目录, 也没有内嵌 single/docker 资产, 无法继续单镜像构建"
        fi
        return 1
    fi
}

# 重置 single 构建上下文目录, 仅保留本地下载缓存目录.
single_reset_build_context() {
    sudo rm -rf "$SINGLE_CONTEXT_PARENT_DIR"
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$SINGLE_CONTEXT_PARENT_DIR" "$SINGLE_CONTEXT_DIR"
}

# 准备仅用于 single 装配阶段的构建上下文.
single_prepare_image_build_context() {
    log_debug "run single_prepare_image_build_context"

    single_init_build_assets || return 1
    single_reset_build_context
    single_prepare_docker_assets "$SINGLE_CONTEXT_DIR" || return 1

    log_info "single 装配上下文已准备完成: $SINGLE_CONTEXT_DIR"
}

# 使用 tar 复制目录, 并排除常见大体积目录.
# 参数: $1: 源目录.
# 参数: $2: 目标目录.
single_copy_tree() {
    local src_dir="$1"
    local dest_dir="$2"

    if [[ ! -d "$src_dir" ]]; then
        log_error "复制目录失败, 源目录不存在: $src_dir"
        return 1
    fi

    sudo mkdir -p "$dest_dir"

    sudo tar \
        --exclude='node_modules' \
        --exclude='dist' \
        --exclude='coverage' \
        --exclude='debugSrc' \
        --exclude='.pnpm-store' \
        --exclude='.turbo' \
        -cf - -C "$src_dir" . | sudo tar -xf - -C "$dest_dir"
}

# 准备 single/docker 构建资产.
# 参数: $1: 构建上下文根目录.
single_prepare_docker_assets() {
    local context_root="$1"

    if single_has_embedded_docker_assets; then
        single_extract_embedded_docker_assets "$context_root" || return 1
    else
        single_copy_tree "$SINGLE_TOOL_ROOT/single/docker" "$context_root/single/docker" || return 1
    fi

    if [[ ! -f "$context_root/$SINGLE_DOCKERFILE_RELATIVE" ]] \
        || [[ ! -f "$context_root/$SINGLE_DOCKERFILE_ENV_RELATIVE" ]] \
        || [[ ! -f "$context_root/$SINGLE_DOCKERFILE_BUILD_RELATIVE" ]]; then
        log_error "single/docker 资产准备失败, 构建上下文中缺少 Dockerfile"
        return 1
    fi
}

# 下载并复用 single 构建依赖归档.
# 参数: $1: 本地缓存文件名.
# 参数: $2: 下载地址.
# 参数: $3: 归档类型, 支持 tar.gz 或 zip.
single_validate_cached_asset() {
    local cache_file="$1"
    local archive_type="$2"

    if [[ ! -s "$cache_file" ]]; then
        return 1
    fi

    case "$archive_type" in
    tar.gz)
        sudo tar -tzf "$cache_file" >/dev/null 2>&1
        ;;
    zip)
        sudo unzip -tq "$cache_file" >/dev/null 2>&1
        ;;
    *)
        log_error "不支持的 single 缓存归档类型: $archive_type"
        return 1
        ;;
    esac
}

# 下载并复用 single 构建依赖归档.
# 参数: $1: 本地缓存文件名.
# 参数: $2: 下载地址.
# 参数: $3: 归档类型, 支持 tar.gz 或 zip.
single_download_cached_asset() {
    local file_name="$1"
    local download_url="$2"
    local archive_type="$3"
    local cache_file="$SINGLE_DOWNLOAD_CACHE_DIR/$file_name"
    local temp_cache_file="$cache_file.part"

    sudo mkdir -p "$SINGLE_DOWNLOAD_CACHE_DIR"

    if single_validate_cached_asset "$cache_file" "$archive_type"; then
        log_info "复用 single 依赖下载缓存: $file_name"
        return 0
    fi

    sudo rm -f "$cache_file"

    log_info "开始下载 single 依赖: $file_name"
    sudo rm -f "$temp_cache_file"
    sudo curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 1800 "$download_url" -o "$temp_cache_file" || return 1

    if ! single_validate_cached_asset "$temp_cache_file" "$archive_type"; then
        sudo rm -f "$temp_cache_file"
        log_error "single 依赖下载后的归档校验失败: $file_name"
        return 1
    fi

    sudo mv -f "$temp_cache_file" "$cache_file"
}

# 准备 env.Dockerfile 需要的本地归档缓存.
single_prepare_env_download_cache() {
    log_debug "run single_prepare_env_download_cache"

    local elasticsearch_file="elasticsearch-${IMG_VERSION_ES}-linux-x86_64.tar.gz"
    local redis_file="redis-${IMG_VERSION_REDIS}-official-src.tar.gz"
    local ik_file="elasticsearch-analysis-ik-${IMG_VERSION_ES}.zip"
    local cache_file=""

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$SINGLE_DOWNLOAD_CACHE_DIR" "$SINGLE_CONTEXT_DOWNLOAD_CACHE_DIR"
    sudo rm -f "$SINGLE_CONTEXT_DOWNLOAD_CACHE_DIR"/* >/dev/null 2>&1 || true

    single_download_cached_asset "$elasticsearch_file" "https://artifacts.elastic.co/downloads/elasticsearch/${elasticsearch_file}" "tar.gz" || return 1
    single_download_cached_asset "$redis_file" "https://github.com/redis/redis/archive/refs/tags/${IMG_VERSION_REDIS}.tar.gz" "tar.gz" || return 1
    single_download_cached_asset "$ik_file" "https://release.infinilabs.com/analysis-ik/stable/${ik_file}" "zip" || return 1

    for cache_file in "$elasticsearch_file" "$redis_file" "$ik_file"; do
        sudo install -m 0644 "$SINGLE_DOWNLOAD_CACHE_DIR/$cache_file" "$SINGLE_CONTEXT_DOWNLOAD_CACHE_DIR/$cache_file" || return 1
    done
}

# 准备 env-single 需要的构建上下文, 包含 env.Dockerfile 依赖归档缓存.
single_prepare_env_build_context() {
    log_debug "run single_prepare_env_build_context"

    single_prepare_image_build_context || return 1
    single_prepare_env_download_cache || return 1

    log_info "single env 构建上下文已准备完成: $SINGLE_CONTEXT_DIR"
}

# 获取最近一次本地构建记录的 single 自动计算版本号.
# 返回: 打印版本号, 不存在则不输出.
single_get_last_build_version() {
    local version_file="$SINGLE_CONTEXT_PARENT_DIR/last-build-version"

    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    fi
}

# 持久化最近一次本地构建记录的 single 自动计算版本号.
# 参数: $1: 版本号.
single_save_last_build_version() {
    local single_version="$1"
    local version_file="$SINGLE_CONTEXT_PARENT_DIR/last-build-version"

    mkdir -p "$SINGLE_CONTEXT_PARENT_DIR"
    printf '%s' "$single_version" >"$version_file"
}

# 将版本字符串转换为可嵌入 semver metadata 的安全标识.
# 参数: $1: 原始版本字符串.
single_sanitize_semver_identifier() {
    local raw_value="$1"
    local sanitized_value=""

    sanitized_value=$(printf '%s' "$raw_value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^0-9a-z-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')

    if [[ -z "$sanitized_value" ]]; then
        sanitized_value="unknown"
    fi

    echo "$sanitized_value"
}

# 从两个生产版本中选择较高的语义化版本.
# 参数: $1: 左侧版本.
# 参数: $2: 右侧版本.
single_pick_higher_pro_version() {
    local left_version="$1"
    local right_version="$2"
    local higher_version=""

    higher_version=$(printf '%s\n%s\n' "${left_version#v}" "${right_version#v}" | sort -V | tail -n 1)
    echo "v$higher_version"
}

# 根据镜像内的 server/client 版本计算 single 版本.
# 参数: $1: server 版本.
# 参数: $2: client 版本.
single_compute_version_from_components() {
    local server_version="$1"
    local client_version="$2"
    local server_meta=""
    local client_meta=""
    local base_version=""
    local single_version=""

    if [[ -z "$server_version" || -z "$client_version" ]]; then
        log_error "计算 single 版本失败, server/client 版本不能为空"
        return 1
    fi

    log_debug "计算 single 版本, server 版本: $server_version"
    log_debug "计算 single 版本, client 版本: $client_version"

    if [[ "$server_version" == "$client_version" ]] && version_is_pro "$server_version"; then
        single_version="$server_version"
        log_debug "single 版本计算结果: $single_version"
        echo "$single_version"
        return 0
    fi

    server_meta="$(single_sanitize_semver_identifier "$server_version")"
    client_meta="$(single_sanitize_semver_identifier "$client_version")"

    if version_is_pro "$server_version" && version_is_pro "$client_version"; then
        base_version="$(single_pick_higher_pro_version "$server_version" "$client_version")"
        single_version="$base_version+server.$server_meta.client.$client_meta"
        log_debug "single 版本计算结果: $single_version"
        echo "$single_version"
        return 0
    fi

    if version_is_pro "$server_version"; then
        base_version="$server_version"
    elif version_is_pro "$client_version"; then
        base_version="$client_version"
    else
        base_version="v0.0.0"
    fi

    single_version="$base_version-single.server.$server_meta.client.$client_meta"
    log_debug "single 版本计算结果: $single_version"
    echo "$single_version"
}

# 从本地镜像中读取指定文件内容.
# 参数: $1: 镜像引用.
# 参数: $2: 镜像内文件路径.
single_read_file_from_local_image() {
    local image_ref="$1"
    local file_path="$2"
    local container_name="temp_container_single_version_reader"
    local temp_dir=""
    local temp_file=""

    sudo docker rm -f "$container_name" >/dev/null 2>&1 || true

    if ! sudo docker create --name "$container_name" "$image_ref" >/dev/null 2>&1; then
        log_error "从镜像读取文件失败, 无法创建临时容器: $image_ref"
        return 1
    fi

    temp_dir=$(mktemp -d) || {
        sudo docker rm -f "$container_name" >/dev/null 2>&1 || true
        log_error "从镜像读取文件失败, 无法创建临时目录"
        return 1
    }

    if ! sudo docker cp "$container_name:$file_path" "$temp_dir/" >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        sudo docker rm -f "$container_name" >/dev/null 2>&1 || true
        log_error "从镜像读取文件失败, 未找到文件: $image_ref -> $file_path"
        return 1
    fi

    temp_file="$temp_dir/$(basename "$file_path")"
    cat "$temp_file"

    rm -rf "$temp_dir"
    sudo docker rm -f "$container_name" >/dev/null 2>&1 || true
}

# 从本地镜像中解析 server/client 版本.
# 参数: $1: 镜像引用.
single_collect_component_versions_from_local_image() {
    local image_ref="$1"
    local raw_server_version=""
    local raw_client_version=""

    raw_server_version=$(single_read_file_from_local_image "$image_ref" "/home/blog-server/VERSION") || return 1
    raw_client_version=$(single_read_file_from_local_image "$image_ref" "/usr/share/nginx/html/VERSION") || return 1

    raw_server_version=$(printf '%s' "$raw_server_version" | tr -d '\r\n')
    raw_client_version=$(printf '%s' "$raw_client_version" | tr -d '\r\n')

    read -r SINGLE_COMPONENT_SERVER_VERSION _ <<<"$(parsing_version "$raw_server_version")"
    read -r SINGLE_COMPONENT_CLIENT_VERSION _ <<<"$(parsing_version "$raw_client_version")"

    log_debug "single 镜像内 server 原始版本: $raw_server_version"
    log_debug "single 镜像内 client 原始版本: $raw_client_version"
    log_debug "single 镜像内 server 解析版本: $SINGLE_COMPONENT_SERVER_VERSION"
    log_debug "single 镜像内 client 解析版本: $SINGLE_COMPONENT_CLIENT_VERSION"
}

# 根据本地 blog:build 镜像实际内容计算 single 版本.
single_calculate_local_build_version() {
    local calculated_version=""

    single_collect_component_versions_from_local_image "$SINGLE_IMAGE_NAME:build" || return 1
    calculated_version="$(single_compute_version_from_components "$SINGLE_COMPONENT_SERVER_VERSION" "$SINGLE_COMPONENT_CLIENT_VERSION")" || return 1

    log_debug "single 自动计算版本结果: $calculated_version"
    echo "$calculated_version"
}

# 解析 push 阶段应使用的 single 版本.
single_resolve_push_version() {
    local last_build_version=""

    last_build_version="$(single_get_last_build_version)"
    if [[ -n "$last_build_version" ]]; then
        log_debug "使用最近一次 single 构建记录的版本: $last_build_version"
        echo "$last_build_version"
        return 0
    fi

    log_warn "未找到最近一次 single 构建记录的版本, 将根据本地 blog:build 重新计算"
    single_calculate_local_build_version
}

# 清理本次构建临时拉取的前后端镜像.
# 参数: $1: 后端镜像引用.
# 参数: $2: 前端镜像引用.
single_cleanup_build_component_images() {
    local server_image_ref="$1"
    local client_image_ref="$2"

    if [[ -n "$server_image_ref" || -n "$client_image_ref" ]]; then
        sudo docker image rm -f "$server_image_ref" "$client_image_ref" >/dev/null 2>&1 || true
    fi
}

# 拉取本次构建需要的前后端发布镜像.
# 参数: $1: 后端版本号.
# 参数: $2: 前端版本号.
single_pull_build_component_images() {
    local server_version="$1"
    local client_version="$2"
    local server_docker_tag=""
    local client_docker_tag=""

    server_docker_tag="$(semver_to_docker_tag "$server_version")"
    client_docker_tag="$(semver_to_docker_tag "$client_version")"

    log_debug "single build server 输入版本: $server_version"
    log_debug "single build server 拉取 tag: $server_docker_tag"
    log_debug "single build client 输入版本: $client_version"
    log_debug "single build client 拉取 tag: $client_docker_tag"

    docker_pull_image_with_region "$DOCKER_HUB_OWNER/blog-server" "$server_docker_tag" || return 1
    docker_pull_image_with_region "$DOCKER_HUB_OWNER/blog-client" "$client_docker_tag" || {
        single_cleanup_build_component_images "$DOCKER_HUB_OWNER/blog-server:$server_docker_tag" ""
        return 1
    }
}

# 确保本地已存在可推送的单镜像.
single_require_local_build_image() {
    if ! single_has_local_image "$SINGLE_IMAGE_NAME:build"; then
        log_error "未找到本地单镜像 $SINGLE_IMAGE_NAME:build, 请先执行 --build-single"
        return 1
    fi
}

# 确保单镜像运行时环境镜像存在.
single_require_env_image() {
    if ! single_has_local_image "$SINGLE_ENV_IMAGE_NAME"; then
        log_error "未找到单镜像运行时环境镜像 $SINGLE_ENV_IMAGE_NAME, 请先执行 --env-single"
        return 1
    fi
}

# 构建单镜像本地 build 标签.
# 参数: $1: 是否强制重建, true 表示即使本地已存在也重新构建.
single_build_env_image() {
    log_debug "run single_build_env_image"

    local force_rebuild="${1:-false}"
    local dockerfile_path="$SINGLE_CONTEXT_DIR/$SINGLE_DOCKERFILE_ENV_RELATIVE"

    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "单镜像运行时环境 Dockerfile 不存在: $dockerfile_path"
        return 1
    fi

    if [[ "$force_rebuild" != "true" ]] && single_has_local_image "$SINGLE_ENV_IMAGE_NAME"; then
        log_info "复用单镜像运行时环境镜像: $SINGLE_ENV_IMAGE_NAME"
        return 0
    fi

    if [[ "$force_rebuild" == "true" ]] && single_has_local_image "$SINGLE_ENV_IMAGE_NAME"; then
        log_info "已显式执行 --env-single, 开始重建单镜像运行时环境镜像: $SINGLE_ENV_IMAGE_NAME"
    fi

    log_info "开始构建单镜像运行时环境镜像: $SINGLE_ENV_IMAGE_NAME"

    sudo DOCKER_BUILDKIT=1 docker build \
        --build-arg POSTGRES_VERSION="$IMG_VERSION_PGSQL" \
        --build-arg POSTGRES_MAJOR="$IMG_VERSION_PGSQL_MAJOR" \
        --build-arg REDIS_VERSION="$IMG_VERSION_REDIS" \
        --build-arg ELASTICSEARCH_VERSION="$IMG_VERSION_ES" \
        --build-arg NGINX_VERSION="${IMG_VERSION_NGINX%-alpine}" \
        -t "$SINGLE_ENV_IMAGE_NAME" \
        -f "$dockerfile_path" \
        "$SINGLE_CONTEXT_DIR" || return 1

    log_info "单镜像运行时环境镜像构建完成: $SINGLE_ENV_IMAGE_NAME"
}

# 构建单镜像本地 build 标签.
single_build_image() {
    log_debug "run single_build_image"

    local dockerfile_path="$SINGLE_CONTEXT_DIR/$SINGLE_DOCKERFILE_BUILD_RELATIVE"
    local server_version="$1"
    local client_version="$2"
    local single_version="$3"
    local server_docker_tag=""
    local client_docker_tag=""
    local server_image_ref=""
    local client_image_ref=""
    local build_status=0
    local build_args=()

    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "单镜像 Dockerfile 不存在: $dockerfile_path"
        return 1
    fi

    server_docker_tag="$(semver_to_docker_tag "$server_version")"
    client_docker_tag="$(semver_to_docker_tag "$client_version")"
    server_image_ref="$DOCKER_HUB_OWNER/blog-server:$server_docker_tag"
    client_image_ref="$DOCKER_HUB_OWNER/blog-client:$client_docker_tag"

    single_pull_build_component_images "$server_version" "$client_version" || return 1

    build_args+=(--build-arg "SERVER_IMAGE=$server_image_ref")
    build_args+=(--build-arg "CLIENT_IMAGE=$client_image_ref")
    build_args+=(--build-arg "SERVER_VERSION=$server_version")
    build_args+=(--build-arg "CLIENT_VERSION=$client_version")
    build_args+=(--build-arg "SINGLE_VERSION=$single_version")

    build_args+=(--build-arg "BLOG_ENV_IMAGE=$SINGLE_ENV_IMAGE_NAME")

    sudo DOCKER_BUILDKIT=1 docker build \
        "${build_args[@]}" \
        -t "$SINGLE_IMAGE_NAME:build" \
        -f "$dockerfile_path" \
        "$SINGLE_CONTEXT_DIR" || build_status=$?

    single_cleanup_build_component_images "$server_image_ref" "$client_image_ref"

    if [[ $build_status -ne 0 ]]; then
        return "$build_status"
    fi

    log_info "单镜像本地构建完成: $SINGLE_IMAGE_NAME:build"
}

# 清理单个远端镜像临时 tag.
# 参数: $1: 完整镜像名.
# 参数: $2: Docker tag 版本号.
single_cleanup_remote_tags() {
    local image_name="$1"
    local docker_tag_version="$2"

    sudo docker image rm "$image_name:$docker_tag_version" "$image_name:latest" >/dev/null 2>&1 || true
}

# 获取本地镜像 ID, 用作镜像内容摘要.
# 参数: $1: 本地镜像引用, 例如 blog:build.
single_get_local_image_id() {
    local image_ref="$1"
    local image_id=""

    image_id=$(sudo docker image inspect --format '{{.Id}}' "$image_ref" 2>/dev/null) || {
        log_error "获取本地镜像 ID 失败: $image_ref"
        return 1
    }

    if [[ -z "$image_id" ]]; then
        log_error "本地镜像 ID 为空: $image_ref"
        return 1
    fi

    echo "$image_id"
}

# 获取远端 tag 对应镜像的 config digest.
# 参数: $1: 完整镜像名, 例如 repo.example.com/public/blog.
# 参数: $2: Docker tag 版本号.
# 返回: 远端不存在时返回 2.
single_get_remote_config_digest() {
    local image_name="$1"
    local docker_tag_version="$2"
    local inspect_output=""
    local config_digest=""

    if ! inspect_output=$(sudo docker manifest inspect "$image_name:$docker_tag_version" 2>/dev/null); then
        return 2
    fi

    config_digest=$(printf '%s\n' "$inspect_output" | awk '
        /"config"[[:space:]]*:[[:space:]]*\{/ { in_config=1; next }
        in_config && /"digest"[[:space:]]*:/ {
            gsub(/[",]/, "", $2)
            print $2
            exit
        }
        in_config && /^  \}/ { in_config=0 }
    ')

    if [[ -z "$config_digest" ]]; then
        log_error "解析远端镜像 config digest 失败: $image_name:$docker_tag_version"
        return 1
    fi

    echo "$config_digest"
}

# 判断远端 tag 对应镜像内容是否与本地 build 镜像一致.
# 参数: $1: 完整镜像名, 例如 repo.example.com/public/blog.
# 参数: $2: Docker tag 版本号.
# 参数: $3: 本地镜像引用, 例如 blog:build.
# 返回: 一致返回 0, 不一致或远端不存在返回 1.
single_remote_image_matches_local() {
    local image_name="$1"
    local docker_tag_version="$2"
    local local_image_ref="$3"
    local local_image_id=""
    local remote_config_digest=""
    local remote_status=0

    local_image_id=$(single_get_local_image_id "$local_image_ref") || return 1
    remote_config_digest=$(single_get_remote_config_digest "$image_name" "$docker_tag_version") || remote_status=$?

    if [[ $remote_status -eq 2 ]]; then
        return 1
    fi

    if [[ $remote_status -ne 0 ]]; then
        return "$remote_status"
    fi

    if [[ "$local_image_id" == "$remote_config_digest" ]]; then
        return 0
    fi

    log_info "目标版本标签已存在但内容不同, 将继续推送覆盖: $image_name:$docker_tag_version"
    log_debug "本地镜像 ID: $local_image_id"
    log_debug "远端 config digest: $remote_config_digest"
    return 1
}

# 将本地单镜像推送到指定仓库.
# 参数: $1: 目标仓库前缀, 例如 registry.example.com/jiaopengzi.
# 参数: $2: 登录用户名.
# 参数: $3: 登录密码.
# 参数: $4: 单镜像版本号.
# 参数: $5: 推送阶段描述.
single_tag_and_push_registry() {
    log_debug "run single_tag_and_push_registry"

    local registry_prefix="$1"
    local registry_user="$2"
    local registry_password="$3"
    local single_version="$4"
    local stage_name="$5"
    local docker_tag_version=""
    local login_host=""
    local image_name=""

    if [[ -z "$registry_prefix" ]]; then
        log_error "$stage_name 推送失败, 目标仓库前缀不能为空"
        return 1
    fi

    if [[ -z "$registry_user" || -z "$registry_password" ]]; then
        log_error "$stage_name 推送失败, 登录用户名或密码为空"
        return 1
    fi

    docker_tag_version=$(semver_to_docker_tag "$single_version")
    login_host="${registry_prefix%%/*}"
    image_name="$registry_prefix/$SINGLE_IMAGE_NAME"

    log_info "$stage_name 目标镜像: $image_name:$docker_tag_version"

    docker_login_retry "$login_host" "$registry_user" "$registry_password" || return 1

    if single_remote_image_matches_local "$image_name" "$docker_tag_version" "$SINGLE_IMAGE_NAME:build"; then
        log_warn "$stage_name 目标镜像已存在且内容一致, 跳过推送与签名: $image_name:$docker_tag_version"
        sudo docker logout "$login_host" >/dev/null 2>&1 || true
        return 0
    fi

    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:$docker_tag_version" || return 1
    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:latest" || return 1

    timeout_retry_docker_push "$registry_prefix" "$SINGLE_IMAGE_NAME" "$docker_tag_version" || return 1
    waiting 5 || return 1
    timeout_retry_docker_push "$registry_prefix" "$SINGLE_IMAGE_NAME" "latest" || return 1

    if single_can_sign_image; then
        docker_sign_pushed_image "$image_name" "$docker_tag_version" "$COSIGN_PRIVATE_KEY" || return 1
    else
        log_warn "$stage_name 未配置 cosign 私钥或密码, 跳过镜像签名"
    fi

    sudo docker logout "$login_host" >/dev/null 2>&1 || true
    single_cleanup_remote_tags "$image_name" "$docker_tag_version"
}

# 推送到默认公开仓库.
# 参数: $1: 单镜像版本号.
single_push_public_registry() {
    local shared_registry_user="$REGISTRY_USER_NAME"
    local shared_registry_password="$REGISTRY_PASSWORD"

    single_tag_and_push_registry \
        "$REGISTRY_REMOTE_SERVER_PUBLIC" \
        "$shared_registry_user" \
        "$shared_registry_password" \
        "$1" \
        "默认公开私有仓库推送"
}

# 推送到腾讯云仓库.
# 参数: $1: 单镜像版本号.
single_push_tencent_registry() {
    local single_version="$1"

    if [[ -z "$REGISTRY_REMOTE_SERVER_TENCENT" ]]; then
        log_warn "未配置 REGISTRY_REMOTE_SERVER_TENCENT, 跳过腾讯云增量推送"
        return 0
    fi

    if [[ -z "$REGISTRY_USER_NAME_TENCENT" || -z "$REGISTRY_PASSWORD_TENCENT" ]]; then
        log_warn "未配置腾讯云仓库凭据, 跳过腾讯云增量推送"
        return 0
    fi

    single_tag_and_push_registry \
        "$REGISTRY_REMOTE_SERVER_TENCENT" \
        "$REGISTRY_USER_NAME_TENCENT" \
        "$REGISTRY_PASSWORD_TENCENT" \
        "$single_version" \
        "腾讯云推送"
}

# 推送到 Docker Hub.
# 参数: $1: 单镜像版本号.
single_push_docker_hub() {
    log_debug "run single_push_docker_hub"

    local single_version="$1"
    local docker_tag_version=""
    local image_name="$DOCKER_HUB_OWNER/$SINGLE_IMAGE_NAME"

    if [[ -z "$DOCKER_HUB_TOKEN" ]]; then
        log_warn "未配置 DOCKER_HUB_TOKEN, 跳过 Docker Hub 增量推送"
        return 0
    fi

    docker_tag_version=$(semver_to_docker_tag "$single_version")

    log_info "Docker Hub 推送目标: $image_name:$docker_tag_version"

    docker_login_retry "$DOCKER_HUB_REGISTRY" "$DOCKER_HUB_OWNER" "$DOCKER_HUB_TOKEN" || return 1

    if single_remote_image_matches_local "$image_name" "$docker_tag_version" "$SINGLE_IMAGE_NAME:build"; then
        log_warn "Docker Hub 目标镜像已存在且内容一致, 跳过推送与签名: $image_name:$docker_tag_version"
        sudo docker logout "$DOCKER_HUB_REGISTRY" >/dev/null 2>&1 || true
        return 0
    fi

    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:$docker_tag_version" || return 1
    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:latest" || return 1

    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$SINGLE_IMAGE_NAME" "$docker_tag_version" || return 1
    waiting 5 || return 1
    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$SINGLE_IMAGE_NAME" "latest" || return 1

    if single_can_sign_image; then
        docker_sign_pushed_image "$image_name" "$docker_tag_version" "$COSIGN_PRIVATE_KEY" || {
            sudo docker logout "$DOCKER_HUB_REGISTRY" >/dev/null 2>&1 || true
            return 1
        }
    else
        log_warn "Docker Hub 未配置 cosign 私钥或密码, 跳过镜像签名"
    fi

    sudo docker logout "$DOCKER_HUB_REGISTRY" >/dev/null 2>&1 || true
    single_cleanup_remote_tags "$image_name" "$docker_tag_version"
}

# 仅构建单镜像.
# 说明: 仅构建单镜像运行时基础环境, 供后续 --build-single 复用.
docker_build_single_env() {
    log_debug "run docker_build_single_env"

    single_check_build_env || return 1

    log_info "开始构建单镜像运行时环境镜像: $SINGLE_ENV_IMAGE_NAME"

    single_prepare_env_build_context || return 1
    single_build_env_image "true" || return 1

    log_info "单镜像运行时环境镜像构建完成: $SINGLE_ENV_IMAGE_NAME"
}

# 仅构建单镜像.
docker_build_single() {
    log_debug "run docker_build_single"

    local single_version=""
    local normalized_server_version=""
    local normalized_client_version=""

    single_check_build_env || return 1

    normalized_server_version="$(printf '%s' "$SINGLE_BUILD_SERVER_VERSION" | tr -d '\r\n')"
    normalized_client_version="$(printf '%s' "$SINGLE_BUILD_CLIENT_VERSION" | tr -d '\r\n')"
    single_version="$(single_compute_version_from_components "$normalized_server_version" "$normalized_client_version")" || return 1

    log_info "开始构建单镜像, 镜像名: $SINGLE_IMAGE_NAME"
    log_debug "single build 指定 server 版本: $normalized_server_version"
    log_debug "single build 指定 client 版本: $normalized_client_version"
    log_debug "single build 计算版本结果: $single_version"

    single_prepare_image_build_context || return 1
    single_require_env_image || return 1
    single_build_image "$normalized_server_version" "$normalized_client_version" "$single_version" || return 1
    single_save_last_build_version "$single_version"

    log_info "单镜像本地构建完成, 自动计算版本: $single_version"
    log_debug "single build 最终使用版本: $single_version"
    log_info "可直接使用 $SINGLE_IMAGE_NAME:build 做本地 docker run 验证"
    single_print_run_hint "$SINGLE_IMAGE_NAME:build"
}

# 仅推送单镜像.
docker_push_single() {
    log_debug "run docker_push_single"

    local single_version=""

    single_check_push_env || return 1
    single_require_local_build_image || return 1

    single_version="$(single_resolve_push_version)" || return 1
    log_debug "single push 使用版本: $single_version"

    if [[ "$SINGLE_PUSH_REPO_ENABLED" == "true" ]]; then
        log_info "已显式启用默认公开私有仓库推送: $REGISTRY_REMOTE_SERVER_PUBLIC/$SINGLE_IMAGE_NAME"
        single_push_public_registry "$single_version" || return 1
    else
        log_info "未显式指定 --repo, 跳过默认公开私有仓库推送"
    fi

    if [[ "$SINGLE_PUSH_TENCENT_ENABLED" == "true" ]]; then
        log_info "已显式启用腾讯云推送: ${REGISTRY_REMOTE_SERVER_TENCENT:-未配置}/$SINGLE_IMAGE_NAME"
        single_push_tencent_registry "$single_version" || return 1
    else
        log_info "未显式指定 --tencent, 跳过腾讯云推送"
    fi

    if [[ "$SINGLE_PUSH_DOCKER_HUB_ENABLED" == "true" ]]; then
        log_info "已显式启用 Docker Hub 推送: $DOCKER_HUB_REMOTE_SERVER/$DOCKER_HUB_OWNER/$SINGLE_IMAGE_NAME"
        single_push_docker_hub "$single_version" || return 1
    else
        log_info "未显式指定 --docker-hub, 跳过 Docker Hub 推送"
    fi

    log_info "单镜像推送完成, 本地镜像保留为: $SINGLE_IMAGE_NAME:build"
}

# 保留兼容的构建并推送入口.
docker_build_push_single() {
    log_debug "run docker_build_push_single"

    docker_build_single_env || return 1
    docker_build_single || return 1
    docker_push_single || return 1

    log_info "单镜像构建与推送完成, 本地镜像保留为: $SINGLE_IMAGE_NAME:build"
}

# 处理 single CLI 命令入口.
# 参数: $1: 动作类型, env | build | push.
# 参数: $@: 命令行参数.
single_cli_main() {
    log_debug "run single_cli_main"

    local single_action="$1"
    local parse_status=0

    shift

    single_parse_cli_args "$single_action" "$@" || parse_status=$?

    if [[ $parse_status -eq 2 ]]; then
        return 0
    fi

    if [[ $parse_status -ne 0 ]]; then
        return "$parse_status"
    fi

    case "$single_action" in
    env)
        docker_build_single_env
        ;;
    build)
        docker_build_single
        ;;
    push)
        docker_push_single
        ;;
    *)
        log_error "不支持的 single 动作: $single_action"
        return 1
        ;;
    esac
}