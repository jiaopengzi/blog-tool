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
SINGLE_DOWNLOAD_CACHE_DIR=""                                    # single 下载缓存目录, 运行时按仓库根目录初始化
SINGLE_CONTEXT_DIR="$SINGLE_CONTEXT_PARENT_DIR/context"         # 单镜像构建上下文目录
SINGLE_CONTEXT_DOWNLOAD_CACHE_DIR="$SINGLE_CONTEXT_DIR/blog-cache" # 单镜像上下文下载缓存目录
SINGLE_DOCKERFILE_RELATIVE="single/docker/Dockerfile"           # 单镜像全量 Dockerfile 相对路径
SINGLE_DOCKERFILE_ENV_RELATIVE="single/docker/env.Dockerfile"   # 单镜像运行时环境 Dockerfile 相对路径
SINGLE_DOCKERFILE_BUILD_RELATIVE="single/docker/build.Dockerfile" # 单镜像装配 Dockerfile 相对路径
SINGLE_TOOL_ROOT=""                                             # blog-tool 根目录, 仅在源码模式下需要
SINGLE_WORKSPACE_ROOT=""                                        # 三仓库共同父目录
SINGLE_CLIENT_ROOT=""                                           # blog-client 根目录
SINGLE_SERVER_ROOT=""                                           # blog-server-dev 根目录
SINGLE_PUSH_TENCENT_ENABLED="false"                             # 是否显式启用腾讯云增量推送
SINGLE_PUSH_DOCKER_HUB_ENABLED="false"                          # 是否显式启用 Docker Hub 增量推送
SINGLE_PARSED_VERSION=""                                        # single CLI 最近一次解析出的版本号
SINGLE_RUN_IMAGE_REF=""                                         # single 运行镜像引用
SINGLE_RUN_DATA_DIR="/data/blog"                               # single 运行数据目录
SINGLE_RUN_CONTAINER_NAME="blog"                               # single 运行容器名称
SINGLE_RUN_PUBLIC_HOST=""                                       # single 运行对外地址
SINGLE_RUN_HTTPS_CERT_FILE=""                                  # single 运行时宿主机证书路径
SINGLE_RUN_HTTPS_KEY_FILE=""                                   # single 运行时宿主机私钥路径
SINGLE_RUN_HTTPS_PORT="443"                                    # single 运行时 HTTPS 端口

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

# 解析前端环境镜像.
# 返回: 打印可复用镜像名, 未命中则不输出.
single_resolve_client_env_image() {
    if single_has_local_image "blog-client:env"; then
        echo "blog-client:env"
    fi
}

# 解析前端构建产物镜像.
# 返回: 打印可复用镜像名, 未命中则不输出.
single_resolve_client_build_image() {
    if single_has_local_image "blog-client:build"; then
        echo "blog-client:build"
    fi
}

# 解析后端 Golang 环境镜像.
# 返回: 打印可复用镜像名, 未命中则不输出.
single_resolve_server_golang_image() {
    if single_has_local_image "blog-server:golang"; then
        echo "blog-server:golang"
    fi
}

# 解析后端构建产物镜像.
# 返回: 打印可复用镜像名, 未命中则不输出.
single_resolve_server_build_image() {
    if single_has_local_image "blog-server:build"; then
        echo "blog-server:build"
    fi
}

# 判断当前是否具备镜像签名条件.
single_can_sign_image() {
    [[ -n "${COSIGN_PRIVATE_KEY:-}" ]] && [[ -n "${COSIGN_PRIVATE_KEY_PWD:-}" ]]
}

# 解析 blog-server:build 构建所需的签名私钥文件.
# 返回: 打印可用私钥路径, 未命中则不输出.
single_resolve_server_sign_key() {
    if [[ -n "${SIGN_PRIVATE_KEY:-}" ]] && [[ -f "${SIGN_PRIVATE_KEY}" ]]; then
        echo "$SIGN_PRIVATE_KEY"
    fi
}

# 输出单镜像帮助信息.
single_print_help() {
    cat <<EOF
用法:
    sudo bash blog-tool-dev.sh --env-single
  sudo bash blog-tool-dev.sh --build-single --version v1.0.0
    sudo bash blog-tool-dev.sh --push-single --version v1.0.0
        sudo bash blog-tool-dev.sh --run-single [--image repo.example.com/blog:v1.0.0]

参数:
  --version, --single-version   指定单镜像版本号, 例如 v1.0.0.
    --push-tencent                仅对 --push-single 生效, 显式启用腾讯云增量推送.
    --push-docker-hub             仅对 --push-single 生效, 显式启用 Docker Hub 增量推送.
        --image                       仅对 --run-single 生效, 指定运行镜像, 默认优先使用本地 blog:build.
        --data-dir                    仅对 --run-single 生效, 指定单镜像数据目录, 默认 /data/blog.
        --name                        仅对 --run-single 生效, 指定容器名称, 默认 blog.
        --public-host                 仅对 --run-single 生效, 指定对外访问域名或 IP.
        --https-cert                  仅对 --run-single 生效, 指定宿主机 HTTPS 证书路径.
        --https-key                   仅对 --run-single 生效, 指定宿主机 HTTPS 私钥路径.
        --https-port                  仅对 --run-single 生效, 指定宿主机与容器 HTTPS 端口, 默认 443.
  -h, --help                    查看帮助信息.

说明:
        1. --env-single 负责构建 blog:env, 供后续单镜像装配复用.
        2. --build-single 负责装配 blog:build, 缺少版本号时会提示输入.
        3. --push-single 默认仅推送本地 blog:build 到 REGISTRY_REMOTE_SERVER_PUBLIC, 缺少版本号时会提示输入.
        4. 腾讯云与 docker.io 仅在显式传入 --push-tencent 或 --push-docker-hub 时才会执行增量推送.
        5. REGISTRY_REMOTE_SERVER_PUBLIC 与 REGISTRY_REMOTE_SERVER 共用用户名和密码.
        6. 装配阶段优先复用 blog-client:build 和 blog-server:build; 未命中时优先按 blog-client 的 Dockerfile.dev 与 blog-server-dev 的 Dockerfile_dev 预热, 后端缺少签名私钥时再回退到 blog-client:env 和 blog-server:golang.
        7. --run-single 会在宿主机侧预处理数据目录和自定义 HTTPS 证书, 适合直接使用宿主机证书路径启动单镜像.
EOF
}

# 解析 single 命令参数.
# 参数: $1: 动作类型, env | build | push.
# 参数: $@: 命令行参数.
# 返回: 通过全局变量 SINGLE_PARSED_VERSION 暂存解析出的版本号.
single_parse_cli_args() {
    local single_action="$1"
    local single_version=""

    SINGLE_PUSH_TENCENT_ENABLED="false"
    SINGLE_PUSH_DOCKER_HUB_ENABLED="false"
    SINGLE_PARSED_VERSION=""
    SINGLE_RUN_IMAGE_REF=""
    SINGLE_RUN_DATA_DIR="/data/blog"
    SINGLE_RUN_CONTAINER_NAME="blog"
    SINGLE_RUN_PUBLIC_HOST=""
    SINGLE_RUN_HTTPS_CERT_FILE=""
    SINGLE_RUN_HTTPS_KEY_FILE=""
    SINGLE_RUN_HTTPS_PORT="443"

    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --version=*)
            single_version="${1#*=}"
            ;;
        --single-version=*)
            single_version="${1#*=}"
            ;;
        --version|--single-version)
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 $1 缺少版本值"
                return 1
            fi
            single_version="$1"
            ;;
        --push-tencent)
            if [[ "$single_action" != "push" ]]; then
                log_error "参数 --push-tencent 仅支持与 --push-single 一起使用"
                return 1
            fi
            SINGLE_PUSH_TENCENT_ENABLED="true"
            ;;
        --push-docker-hub)
            if [[ "$single_action" != "push" ]]; then
                log_error "参数 --push-docker-hub 仅支持与 --push-single 一起使用"
                return 1
            fi
            SINGLE_PUSH_DOCKER_HUB_ENABLED="true"
            ;;
        --image=*)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --image 仅支持与 --run-single 一起使用"
                return 1
            fi
            SINGLE_RUN_IMAGE_REF="${1#*=}"
            ;;
        --image)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --image 仅支持与 --run-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --image 缺少镜像值"
                return 1
            fi
            SINGLE_RUN_IMAGE_REF="$1"
            ;;
        --data-dir=*)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --data-dir 仅支持与 --run-single 一起使用"
                return 1
            fi
            SINGLE_RUN_DATA_DIR="${1#*=}"
            ;;
        --data-dir)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --data-dir 仅支持与 --run-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --data-dir 缺少目录值"
                return 1
            fi
            SINGLE_RUN_DATA_DIR="$1"
            ;;
        --name=*)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --name 仅支持与 --run-single 一起使用"
                return 1
            fi
            SINGLE_RUN_CONTAINER_NAME="${1#*=}"
            ;;
        --name)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --name 仅支持与 --run-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --name 缺少容器名称"
                return 1
            fi
            SINGLE_RUN_CONTAINER_NAME="$1"
            ;;
        --public-host=*)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --public-host 仅支持与 --run-single 一起使用"
                return 1
            fi
            SINGLE_RUN_PUBLIC_HOST="${1#*=}"
            ;;
        --public-host)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --public-host 仅支持与 --run-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --public-host 缺少域名或 IP"
                return 1
            fi
            SINGLE_RUN_PUBLIC_HOST="$1"
            ;;
        --https-cert=*)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --https-cert 仅支持与 --run-single 一起使用"
                return 1
            fi
            SINGLE_RUN_HTTPS_CERT_FILE="${1#*=}"
            ;;
        --https-cert)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --https-cert 仅支持与 --run-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --https-cert 缺少证书路径"
                return 1
            fi
            SINGLE_RUN_HTTPS_CERT_FILE="$1"
            ;;
        --https-key=*)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --https-key 仅支持与 --run-single 一起使用"
                return 1
            fi
            SINGLE_RUN_HTTPS_KEY_FILE="${1#*=}"
            ;;
        --https-key)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --https-key 仅支持与 --run-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --https-key 缺少私钥路径"
                return 1
            fi
            SINGLE_RUN_HTTPS_KEY_FILE="$1"
            ;;
        --https-port=*)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --https-port 仅支持与 --run-single 一起使用"
                return 1
            fi
            SINGLE_RUN_HTTPS_PORT="${1#*=}"
            ;;
        --https-port)
            if [[ "$single_action" != "run" ]]; then
                log_error "参数 --https-port 仅支持与 --run-single 一起使用"
                return 1
            fi
            shift
            if [[ $# -eq 0 ]]; then
                log_error "参数 --https-port 缺少端口值"
                return 1
            fi
            SINGLE_RUN_HTTPS_PORT="$1"
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

    SINGLE_PARSED_VERSION="$single_version"
}

# 仅检查 single 运行入口所需的基础环境.
single_check_run_env() {
    single_require_dev_build || return 1

    check_is_root
    check_character
    check_env_path
    check_install_base
    single_check_docker_ready || return 1
}

# 解析 single 运行使用的镜像引用.
# 返回: 打印最终镜像引用.
single_resolve_run_image_ref() {
    if [[ -n "$SINGLE_RUN_IMAGE_REF" ]]; then
        echo "$SINGLE_RUN_IMAGE_REF"
        return 0
    fi

    if single_has_local_image "$SINGLE_IMAGE_NAME:build"; then
        echo "$SINGLE_IMAGE_NAME:build"
        return 0
    fi

    log_error "未找到可运行的单镜像, 请显式传入 --image 或先执行 --build-single"
    return 1
}

# 预创建 single 运行所需数据目录.
single_prepare_run_data_dir() {
    local data_dir="$1"

    sudo mkdir -p "$data_dir/blog-client/nginx/ssl"
    sudo chmod 755 "$data_dir" "$data_dir/blog-client" "$data_dir/blog-client/nginx"
    sudo chmod 700 "$data_dir/blog-client/nginx/ssl"
}

# 将宿主机 HTTPS 证书复制到 single 数据目录, 与 --auto 的 client 证书覆盖语义对齐.
single_prepare_run_https_cert() {
    local data_dir="$1"
    local cert_file="$2"
    local key_file="$3"
    local target_ssl_dir="$data_dir/blog-client/nginx/ssl"

    if [[ -z "$cert_file" && -z "$key_file" ]]; then
        return 0
    fi

    if [[ -z "$cert_file" || -z "$key_file" ]]; then
        log_error "--https-cert 和 --https-key 需要同时提供"
        return 1
    fi

    if [[ ! -r "$cert_file" || ! -r "$key_file" ]]; then
        log_error "宿主机 HTTPS 证书路径不存在或不可读, 请检查 --https-cert 或 --https-key"
        return 1
    fi

    single_prepare_run_data_dir "$data_dir"
    sudo cp -f "$cert_file" "$target_ssl_dir/cert.pem"
    sudo cp -f "$key_file" "$target_ssl_dir/cert.key"
    sudo chmod 600 "$target_ssl_dir/cert.key"
    sudo chmod 644 "$target_ssl_dir/cert.pem"
    log_info "已将宿主机 HTTPS 证书复制到: $target_ssl_dir"
}

# 运行 single 镜像, 在宿主机侧预处理证书和数据目录.
docker_run_single() {
    log_debug "run docker_run_single"

    local image_ref=""
    local public_host=""
    local container_id=""

    single_check_run_env || return 1

    image_ref="$(single_resolve_run_image_ref)" || return 1
    public_host="${SINGLE_RUN_PUBLIC_HOST:-$(single_resolve_default_public_host)}"

    if ! [[ "$SINGLE_RUN_HTTPS_PORT" =~ ^[0-9]+$ ]]; then
        log_error "--https-port 必须为数字"
        return 1
    fi

    if sudo docker ps -a --format '{{.Names}}' | grep -Fxq "$SINGLE_RUN_CONTAINER_NAME"; then
        log_error "容器名称已存在: $SINGLE_RUN_CONTAINER_NAME, 请先删除或改用 --name"
        return 1
    fi

    single_prepare_run_data_dir "$SINGLE_RUN_DATA_DIR"
    single_prepare_run_https_cert "$SINGLE_RUN_DATA_DIR" "$SINGLE_RUN_HTTPS_CERT_FILE" "$SINGLE_RUN_HTTPS_KEY_FILE" || return 1

    log_info "开始运行单镜像容器, 镜像: $image_ref"
    container_id="$(sudo docker run -d \
        --name "$SINGLE_RUN_CONTAINER_NAME" \
        -p "$SINGLE_RUN_HTTPS_PORT:$SINGLE_RUN_HTTPS_PORT" \
        -v "$SINGLE_RUN_DATA_DIR:/data" \
        -e "BLOG_PUBLIC_HOST=$public_host" \
        -e "BLOG_HTTPS_PORT=$SINGLE_RUN_HTTPS_PORT" \
        "$image_ref")" || return 1

    log_info "单镜像容器启动命令已提交, 容器 ID: $container_id"
    log_info "数据目录: $SINGLE_RUN_DATA_DIR"
    log_info "访问地址: https://$public_host"
    log_info "查看日志: sudo docker logs -f $SINGLE_RUN_CONTAINER_NAME"
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

# 判断给定目录是否为 single 运行依赖的工作区根目录.
# 参数: $1: 待判断目录.
single_is_workspace_root() {
    local candidate_dir="$1"

    [[ -d "$candidate_dir/blog-client" ]] && [[ -d "$candidate_dir/blog-server-dev" ]]
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

# 定位 single 运行依赖的工作区根目录.
# 返回: 打印同时包含 blog-client 和 blog-server-dev 的目录绝对路径.
single_find_workspace_root() {
    local search_dir="$ROOT_DIR"
    local parent_dir=""
    local depth=0

    while [[ $depth -lt 6 ]]; do
        if single_is_workspace_root "$search_dir"; then
            echo "$search_dir"
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

# 加载 single 自动拉取源码所需的 Git 前缀配置.
# 说明: 这里仅加载 git_prefix_local, 避免为了 clone 源码额外要求 single 不需要的 dev 配置.
single_load_git_clone_env() {
    if [[ -n "${GIT_PREFIX_LOCAL:-}" ]]; then
        GIT_LOCAL="$GIT_PREFIX_LOCAL:$GIT_USER"
        return 0
    fi

    load_interactive_config \
        GIT_PREFIX_LOCAL \
        "$BLOG_TOOL_ENV/git_prefix_local" \
        "请输入内网 Git 地址前缀如：git@10.0.0.100" \
        "git@127.0.0.1"

    GIT_LOCAL="$GIT_PREFIX_LOCAL:$GIT_USER"
}

# 检查仓库目录是否包含 single 构建所需的关键文件.
# 参数: $1: 仓库目录.
# 参数: $@: 需要存在的相对路径列表.
single_repo_has_required_files() {
    local repo_dir="$1"
    shift
    local required_file=""

    if [[ ! -d "$repo_dir" ]]; then
        return 1
    fi

    for required_file in "$@"; do
        if [[ ! -f "$repo_dir/$required_file" ]]; then
            return 1
        fi
    done

    return 0
}

# 在工作区中确保目标源码仓库存在, 缺失或残缺时自动重新拉取.
# 参数: $1: 仓库目录名.
# 参数: $@: 该仓库必须存在的关键文件.
single_ensure_workspace_repo() {
    local repo_name="$1"
    shift
    local repo_dir="$SINGLE_WORKSPACE_ROOT/$repo_name"
    local current_dir="$PWD"

    if single_repo_has_required_files "$repo_dir" "$@"; then
        return 0
    fi

    if [[ -d "$repo_dir" ]]; then
        log_warn "检测到 $repo_name 目录缺少 single 构建所需文件, 将删除后重新拉取: $repo_dir"
        sudo rm -rf "$repo_dir"
    else
        log_info "未找到 $repo_name 源码目录, 开始自动拉取到: $repo_dir"
    fi

    single_load_git_clone_env || return 1

    sudo mkdir -p "$SINGLE_WORKSPACE_ROOT"
    cd "$SINGLE_WORKSPACE_ROOT" || return 1
    git_clone "$repo_name" "$GIT_LOCAL" || {
        cd "$current_dir" || return 1
        return 1
    }
    cd "$current_dir" || return 1

    if ! single_repo_has_required_files "$repo_dir" "$@"; then
        log_error "$repo_name 拉取完成后仍缺少 single 构建所需文件: $repo_dir"
        return 1
    fi
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

# 初始化三个仓库路径.
single_init_repo_paths() {
    log_debug "run single_init_repo_paths"

    SINGLE_TOOL_ROOT=""
    if SINGLE_TOOL_ROOT="$(single_find_tool_root)"; then
        :
    fi

    if ! SINGLE_WORKSPACE_ROOT="$(single_find_workspace_root)"; then
        if [[ -n "$SINGLE_TOOL_ROOT" ]]; then
            SINGLE_WORKSPACE_ROOT="$(dirname "$SINGLE_TOOL_ROOT")"
            log_warn "未检测到现成的 single 工作区, 将使用 blog-tool 同级目录作为源码拉取目录: $SINGLE_WORKSPACE_ROOT"
        else
            SINGLE_WORKSPACE_ROOT="$ROOT_DIR"
            log_warn "未检测到现成的 single 工作区, 将使用当前脚本所在目录作为源码拉取目录: $SINGLE_WORKSPACE_ROOT"
        fi
    fi

    SINGLE_CLIENT_ROOT="$SINGLE_WORKSPACE_ROOT/blog-client"
    SINGLE_SERVER_ROOT="$SINGLE_WORKSPACE_ROOT/blog-server-dev"
    SINGLE_DOWNLOAD_CACHE_DIR="$SINGLE_WORKSPACE_ROOT/blog-cache"

    single_ensure_workspace_repo "blog-client" "Dockerfile.env" "Dockerfile.dev" "package.json" || return 1
    single_ensure_workspace_repo "blog-server-dev" "Dockerfile_golang" "Dockerfile_dev" "go.mod" || return 1

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
        --exclude='.git' \
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

# 缺失时按 blog-client 原始 Dockerfile.env 构建前端环境镜像.
single_ensure_client_env_image() {
    local dockerfile_path="$SINGLE_CLIENT_ROOT/Dockerfile.env"

    if single_has_local_image "blog-client:env"; then
        return 0
    fi

    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "未找到 blog-client 环境 Dockerfile: $dockerfile_path"
        return 1
    fi

    log_info "未找到前端环境镜像 blog-client:env, 开始基于 Dockerfile.env 首次构建"
    sudo DOCKER_BUILDKIT=1 docker build -t blog-client:env -f "$dockerfile_path" "$SINGLE_CLIENT_ROOT" || return 1
}

# 缺失时按 blog-client 原始 Dockerfile.dev 构建前端构建产物镜像.
single_ensure_client_build_image() {
    local dockerfile_path="$SINGLE_CLIENT_ROOT/Dockerfile.dev"

    if single_has_local_image "blog-client:build"; then
        return 0
    fi

    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "未找到 blog-client 构建 Dockerfile: $dockerfile_path"
        return 1
    fi

    single_ensure_client_env_image || return 1

    log_info "未找到前端构建产物镜像 blog-client:build, 开始基于 Dockerfile.dev 首次构建"
    sudo DOCKER_BUILDKIT=1 docker build -t blog-client:build -f "$dockerfile_path" "$SINGLE_CLIENT_ROOT" || return 1
}

# 缺失时按 blog-server-dev 原始 Dockerfile_golang 构建后端 Golang 环境镜像.
single_ensure_server_golang_image() {
    local dockerfile_path="$SINGLE_SERVER_ROOT/Dockerfile_golang"

    if single_has_local_image "blog-server:golang"; then
        return 0
    fi

    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "未找到 blog-server-dev 环境 Dockerfile: $dockerfile_path"
        return 1
    fi

    log_info "未找到后端环境镜像 blog-server:golang, 开始基于 Dockerfile_golang 首次构建"
    sudo DOCKER_BUILDKIT=1 docker build -t blog-server:golang -f "$dockerfile_path" "$SINGLE_SERVER_ROOT" || return 1
}

# 缺失时按 blog-server-dev 原始 Dockerfile_dev 构建后端构建产物镜像.
single_ensure_server_build_image() {
    local dockerfile_path="$SINGLE_SERVER_ROOT/Dockerfile_dev"
    local sign_key=""

    if single_has_local_image "blog-server:build"; then
        return 0
    fi

    sign_key="$(single_resolve_server_sign_key)"
    if [[ -z "$sign_key" ]]; then
        log_warn "未检测到 SIGN_PRIVATE_KEY, 跳过基于 Dockerfile_dev 预热 blog-server:build"
        return 1
    fi

    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "未找到 blog-server-dev 构建 Dockerfile: $dockerfile_path"
        return 1
    fi

    single_ensure_server_golang_image || return 1

    log_info "未找到后端构建产物镜像 blog-server:build, 开始基于 Dockerfile_dev 首次构建"
    sudo DOCKER_BUILDKIT=1 docker build \
        --secret id=sign_key,src="$sign_key" \
        -t blog-server:build \
        -f "$dockerfile_path" \
        "$SINGLE_SERVER_ROOT" || return 1
}

# 准备单镜像构建上下文.
single_prepare_build_context() {
    log_debug "run single_prepare_build_context"

    single_init_repo_paths || return 1

    sudo rm -rf "$SINGLE_CONTEXT_PARENT_DIR"
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$SINGLE_CONTEXT_PARENT_DIR" "$SINGLE_CONTEXT_DIR"

    single_copy_tree "$SINGLE_CLIENT_ROOT" "$SINGLE_CONTEXT_DIR/blog-client" || return 1
    single_copy_tree "$SINGLE_SERVER_ROOT" "$SINGLE_CONTEXT_DIR/blog-server-dev" || return 1
    single_prepare_docker_assets "$SINGLE_CONTEXT_DIR" || return 1
    single_prepare_env_download_cache || return 1

    log_info "单镜像构建上下文已准备完成: $SINGLE_CONTEXT_DIR"
}

# 获取最近一次本地构建记录的单镜像版本号.
# 返回: 打印版本号, 不存在则不输出.
single_get_last_build_version() {
    local version_file="$SINGLE_CONTEXT_PARENT_DIR/last-build-version"

    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    fi
}

# 持久化最近一次本地构建记录的单镜像版本号.
# 参数: $1: 版本号.
single_save_last_build_version() {
    local single_version="$1"
    local version_file="$SINGLE_CONTEXT_PARENT_DIR/last-build-version"

    mkdir -p "$SINGLE_CONTEXT_PARENT_DIR"
    printf '%s' "$single_version" >"$version_file"
}

# 确保单镜像版本号存在.
# 参数: $1: 版本号.
# 参数: $2: 缺省版本号.
# 返回: 打印最终版本号.
single_resolve_version() {
    local input_version="$1"
    local default_version="${2:-}"
    local final_version="$input_version"

    if [[ -z "$final_version" ]]; then
        final_version=$(read_user_input "请输入单镜像版本号, 例如 v1.0.0: " "$default_version")
    fi

    if [[ -z "$final_version" ]]; then
        log_error "单镜像版本号不能为空"
        return 1
    fi

    if [[ "$final_version" =~ [[:space:]] ]]; then
        log_error "单镜像版本号不能包含空白字符: $final_version"
        return 1
    fi

    echo "$final_version"
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
# 参数: $1: 单镜像版本号.
single_build_image() {
    log_debug "run single_build_image"

    local single_version="$1"
    local dockerfile_path="$SINGLE_CONTEXT_DIR/$SINGLE_DOCKERFILE_BUILD_RELATIVE"
    local client_build_image=""
    local server_build_image=""
    local server_golang_image=""
    local server_sign_key=""
    local build_args=()

    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "单镜像 Dockerfile 不存在: $dockerfile_path"
        return 1
    fi

    client_build_image="$(single_resolve_client_build_image)"
    server_build_image="$(single_resolve_server_build_image)"
    server_golang_image="$(single_resolve_server_golang_image)"
    server_sign_key="$(single_resolve_server_sign_key)"

    if [[ -z "$client_build_image" ]]; then
        single_ensure_client_build_image || return 1
        client_build_image="blog-client:build"
        log_info "前端构建产物镜像首次构建完成: $client_build_image"
    fi
    log_info "复用前端构建产物镜像: $client_build_image"
    build_args+=(--build-arg "CLIENT_BUILD_IMAGE=$client_build_image")

    if [[ -n "$server_build_image" ]]; then
        log_info "复用后端构建产物镜像: $server_build_image"
        build_args+=(--build-arg "SERVER_BUILD_IMAGE=$server_build_image")
    elif [[ -n "$server_sign_key" ]]; then
        single_ensure_server_build_image || return 1
        server_build_image="blog-server:build"
        log_info "后端构建产物镜像首次构建完成: $server_build_image"
        build_args+=(--build-arg "SERVER_BUILD_IMAGE=$server_build_image")
    elif [[ -n "$server_golang_image" ]]; then
        log_info "复用后端环境镜像: $server_golang_image"
        build_args+=(--build-arg "SERVER_GOLANG_IMAGE=$server_golang_image")
    else
        single_ensure_server_golang_image || return 1
        server_golang_image="blog-server:golang"
        log_info "后端环境镜像首次构建完成: $server_golang_image"
        build_args+=(--build-arg "SERVER_GOLANG_IMAGE=$server_golang_image")
    fi

    build_args+=(--build-arg "BLOG_ENV_IMAGE=$SINGLE_ENV_IMAGE_NAME")

    sudo DOCKER_BUILDKIT=1 docker build \
        --build-arg BLOG_VERSION="$single_version" \
        --build-arg NODE_VERSION="$IMG_VERSION_NODE" \
        "${build_args[@]}" \
        -t "$SINGLE_IMAGE_NAME:build" \
        -f "$dockerfile_path" \
        "$SINGLE_CONTEXT_DIR" || return 1

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

    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:$docker_tag_version" || return 1
    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:latest" || return 1

    docker_login_retry "$login_host" "$registry_user" "$registry_password" || return 1

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
        "腾讯云增量推送"
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

    log_info "Docker Hub 增量推送目标: $image_name:$docker_tag_version"

    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:$docker_tag_version" || return 1
    sudo docker tag "$SINGLE_IMAGE_NAME:build" "$image_name:latest" || return 1

    docker_login_retry "$DOCKER_HUB_REGISTRY" "$DOCKER_HUB_OWNER" "$DOCKER_HUB_TOKEN" || return 1

    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$SINGLE_IMAGE_NAME" "$docker_tag_version" || return 1
    waiting 5 || return 1
    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$SINGLE_IMAGE_NAME" "latest" || return 1

    sudo docker logout "$DOCKER_HUB_REGISTRY" >/dev/null 2>&1 || true
    single_cleanup_remote_tags "$image_name" "$docker_tag_version"
}

# 仅构建单镜像.
# 说明: 仅构建单镜像运行时基础环境, 供后续 --build-single 复用.
docker_build_single_env() {
    log_debug "run docker_build_single_env"

    single_check_build_env || return 1

    log_info "开始构建单镜像运行时环境镜像: $SINGLE_ENV_IMAGE_NAME"

    single_prepare_build_context || return 1
    single_build_env_image "true" || return 1

    log_info "单镜像运行时环境镜像构建完成: $SINGLE_ENV_IMAGE_NAME"
}

# 仅构建单镜像.
# 参数: $1: 单镜像版本号.
docker_build_single() {
    log_debug "run docker_build_single"

    local single_version="$1"

    single_check_build_env || return 1
    single_version="$(single_resolve_version "$single_version")" || return 1

    log_info "开始构建单镜像, 镜像名: $SINGLE_IMAGE_NAME, 版本: $single_version"

    single_prepare_build_context || return 1
    single_require_env_image || return 1
    single_build_image "$single_version" || return 1
    single_save_last_build_version "$single_version"

    log_info "单镜像本地构建完成, 可直接使用 $SINGLE_IMAGE_NAME:build 做本地 docker run 验证"
    single_print_run_hint "$SINGLE_IMAGE_NAME:build"
}

# 仅推送单镜像.
# 参数: $1: 单镜像版本号.
docker_push_single() {
    log_debug "run docker_push_single"

    local single_version="$1"
    local last_build_version=""

    single_check_push_env || return 1
    single_require_local_build_image || return 1

    last_build_version="$(single_get_last_build_version)"
    single_version="$(single_resolve_version "$single_version" "$last_build_version")" || return 1

    log_info "默认推送公开私有仓库: $REGISTRY_REMOTE_SERVER_PUBLIC/$SINGLE_IMAGE_NAME"
    single_push_public_registry "$single_version" || return 1

    if [[ "$SINGLE_PUSH_TENCENT_ENABLED" == "true" ]]; then
        log_info "已显式启用腾讯云增量推送: ${REGISTRY_REMOTE_SERVER_TENCENT:-未配置}/$SINGLE_IMAGE_NAME"
        single_push_tencent_registry "$single_version" || return 1
    else
        log_info "未显式指定 --push-tencent, 跳过腾讯云增量推送"
    fi

    if [[ "$SINGLE_PUSH_DOCKER_HUB_ENABLED" == "true" ]]; then
        log_info "已显式启用 Docker Hub 增量推送: $DOCKER_HUB_REMOTE_SERVER/$DOCKER_HUB_OWNER/$SINGLE_IMAGE_NAME"
        single_push_docker_hub "$single_version" || return 1
    else
        log_info "未显式指定 --push-docker-hub, 跳过 Docker Hub 增量推送"
    fi

    log_info "单镜像推送完成, 本地镜像保留为: $SINGLE_IMAGE_NAME:build"
}

# 保留兼容的构建并推送入口.
# 参数: $1: 单镜像版本号.
docker_build_push_single() {
    log_debug "run docker_build_push_single"

    local single_version="$1"

    docker_build_single_env || return 1
    docker_build_single "$single_version" || return 1
    docker_push_single "$single_version" || return 1

    log_info "单镜像构建与推送完成, 本地镜像保留为: $SINGLE_IMAGE_NAME:build"
}

# 处理 single CLI 命令入口.
# 参数: $1: 动作类型, env | build | push | run.
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
        docker_build_single "$SINGLE_PARSED_VERSION"
        ;;
    push)
        docker_push_single "$SINGLE_PARSED_VERSION"
        ;;
    run)
        docker_run_single
        ;;
    *)
        log_error "不支持的 single 动作: $single_action"
        return 1
        ;;
    esac
}