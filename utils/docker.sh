#!/bin/bash
# FilePath    : blog-tool/utils/docker.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : Docker 相关工具

# 将 SemVer 格式(可能带 +Metadata)转为合法的 Docker tag
# 输入举例：v0.1.5-dev+251116
# 输出举例：v0.1.5-dev-251116
# 用途：生成一个 Docker 兼容的 tag, 同时尽量保留 SemVer 信息
semver_to_docker_tag() {
    log_debug "run semver_to_docker_tag"

    local semver="$1"

    # # 如果有 'v' 去掉开头的 'v'
    # local clean_semver="${semver#v}"

    # # 替换 '+' 为 '-', 因为 Docker tag 不允许 '+'
    # local docker_tag="${clean_semver/\+/-}"

    local docker_tag="${semver/\+/-}"

    log_debug "将原来 SemVer 风格的版本号: '$semver' 转换为 Docker 允许的 Tag: '$docker_tag'"

    echo "$docker_tag"
}

# 生成镜像引用.
# 参数: $1: 镜像名称.
# 参数: $2: 引用模式, 仅支持 tag 或 digest.
# 参数: $3: tag 或 digest 的具体值.
docker_build_image_reference() {
    log_debug "run docker_build_image_reference"

    local image_name="$1"
    local ref_mode="$2"
    local ref_value="$3"

    if [ -z "$image_name" ] || [ -z "$ref_mode" ] || [ -z "$ref_value" ]; then
        log_error "构造镜像引用失败, 参数不能为空"
        return 1
    fi

    case "$ref_mode" in
    tag)
        echo "$image_name:$ref_value"
        ;;
    digest)
        local digest_value="$ref_value"
        digest_value="${digest_value#*@}"

        if [[ "$digest_value" != sha256:* ]]; then
            log_error "digest 模式的值必须以 sha256: 开头, 当前值: $ref_value"
            return 1
        fi

        echo "$image_name@$digest_value"
        ;;
    *)
        log_error "镜像引用模式仅支持 tag 或 digest, 当前模式: $ref_mode"
        return 1
        ;;
    esac
}

# 检查 cosign 命令是否可用.
docker_check_cosign() {
    log_debug "run docker_check_cosign"

    if ! command -v cosign >/dev/null 2>&1; then
        log_error "未检测到 cosign 命令, 请先安装 cosign"
        return 1
    fi
}

# 输出密钥结构调试信息, 避免直接打印敏感正文.
# 参数: $1: 密钥内容.
# 参数: $2: 密钥用途说明.
# 参数: $3: 调试阶段说明.
docker_debug_key_summary() {
    log_debug "run docker_debug_key_summary"

    local key_content="$1"
    local key_label="$2"
    local stage_label="$3"

    local key_length
    key_length=$(printf '%s' "$key_content" | wc -c | awk '{print $1}')

    local line_count
    line_count=$(printf '%s' "$key_content" | awk 'END {print NR}')

    local first_line
    first_line=$(printf '%s' "$key_content" | head -n 1)

    local last_line
    last_line=$(printf '%s' "$key_content" | tail -n 1)

    local has_literal_newline="false"
    if printf '%s' "$key_content" | grep -q '\\n'; then
        has_literal_newline="true"
    fi

    local wrapped_with_quotes="false"
    if [[ "$key_content" == \"*\" ]] || [[ "$key_content" == \'*\' ]]; then
        wrapped_with_quotes="true"
    fi

    log_debug "${key_label}${stage_label}摘要: 长度=${key_length}, 行数=${line_count}, 含字面量\\n=${has_literal_newline}, 外层引号包裹=${wrapped_with_quotes}"
    log_debug "${key_label}${stage_label}首行: ${first_line}"
    log_debug "${key_label}${stage_label}尾行: ${last_line}"
}

# 将密钥来源解析为可供 cosign 使用的本地文件.
# 参数: $1: 密钥来源, 支持文件路径或 PEM 密钥内容.
# 参数: $2: 密钥用途说明, 如私钥或公钥.
# 返回: 输出可用的密钥文件路径.
docker_resolve_key_file() {
    log_debug "run docker_resolve_key_file"

    local key_source="$1"
    local key_label="$2"
    local normalized_key=""

    if [ -z "$key_source" ]; then
        log_error "${key_label}为空, 无法解析密钥文件"
        return 1
    fi

    if [ -f "$key_source" ]; then
        log_debug "检测到${key_label}为文件路径, 路径首尾3位: ${key_source:0:3}...${key_source: -3}"
        docker_debug_key_summary "$(cat "$key_source")" "$key_label" "文件内容"
        echo "$key_source"
        return 0
    fi

    if echo "$key_source" | grep -Eq "BEGIN .*KEY"; then
        docker_debug_key_summary "$key_source" "$key_label" "原始输入"

        local tmp_key_file
        tmp_key_file=$(mktemp) || {
            log_error "创建临时${key_label}文件失败"
            return 1
        }

        chmod 600 "$tmp_key_file" || {
            rm -f "$tmp_key_file"
            log_error "设置临时${key_label}文件权限失败"
            return 1
        }

        # 兼容 CI 中将多行 PEM 压成单行并使用 \n 传递的场景.
        if printf '%s' "$key_source" | grep -q '\\n'; then
            normalized_key=$(printf '%b' "$key_source")
        else
            normalized_key="$key_source"
        fi

        # 统一移除 Windows 风格回车, 避免 cosign 解析 PEM 失败.
        normalized_key=$(printf '%s' "$normalized_key" | tr -d '\r')

        docker_debug_key_summary "$normalized_key" "$key_label" "归一化后"

        printf '%s' "$normalized_key" >"$tmp_key_file" || {
            rm -f "$tmp_key_file"
            log_error "写入临时${key_label}文件失败"
            return 1
        }

        docker_debug_key_summary "$(cat "$tmp_key_file")" "$key_label" "落盘后"

        log_debug "检测到${key_label}为 PEM 内容, 已写入临时文件: ${tmp_key_file:0:3}...${tmp_key_file: -3}"
        echo "$tmp_key_file"
        return 0
    fi

    log_error "${key_label}既不是有效文件路径, 也不是合法的 PEM 密钥内容"
    return 1
}

# 获取远端镜像 digest.
# 参数: $1: 镜像名称.
# 参数: $2: 引用模式, 仅支持 tag 或 digest.
# 参数: $3: tag 或 digest 的具体值.
docker_get_digest() {
    log_debug "run docker_get_digest"

    local image_name="$1"
    local ref_mode="$2"
    local ref_value="$3"

    if [ "$ref_mode" = "digest" ]; then
        local digest_value="$ref_value"
        digest_value="${digest_value#*@}"

        if [[ "$digest_value" != sha256:* ]]; then
            log_error "digest 模式的值必须以 sha256: 开头, 当前值: $ref_value"
            return 1
        fi

        echo "$digest_value"
        return 0
    fi

    local image_ref
    image_ref=$(docker_build_image_reference "$image_name" "$ref_mode" "$ref_value") || return 1

    local inspect_output
    if ! inspect_output=$(sudo docker buildx imagetools inspect "$image_ref" 2>&1); then
        log_error "获取镜像 digest 失败, 镜像: $image_ref, 输出: $inspect_output"
        return 1
    fi

    local digest_value
    digest_value=$(echo "$inspect_output" | awk '/^Digest:/ {print $2; exit}')

    if [ -z "$digest_value" ]; then
        log_error "未从 inspect 输出中解析到 digest, 镜像: $image_ref"
        return 1
    fi

    log_info "获取镜像 digest 成功, 镜像: $image_ref, digest: $digest_value"
    echo "$digest_value"
}

# 使用 Cosign 对镜像签名.
# 参数: $1: 私钥文件路径.
# 参数: $2: 镜像名称.
# 参数: $3: 引用模式, 仅支持 tag 或 digest.
# 参数: $4: tag 或 digest 的具体值.
docker_sign_image() {
    log_debug "run docker_sign_image"

    local private_key="${1:-$COSIGN_PRIVATE_KEY}"
    local image_name="$2"
    local ref_mode="$3"
    local ref_value="$4"
    local private_key_file=""
    local private_key_pwd="${COSIGN_PRIVATE_KEY_PWD:-}"
    local private_key_source=""
    local private_key_pwd_source=""

    docker_check_cosign || return 1

    if [ -n "${1:-}" ]; then
        private_key_source="函数参数"
    elif [ -n "${COSIGN_PRIVATE_KEY:-}" ]; then
        private_key_source="COSIGN_PRIVATE_KEY"
    else
        private_key_source="未命中"
    fi

    if [ -n "${COSIGN_PRIVATE_KEY_PWD:-}" ]; then
        private_key_pwd_source="COSIGN_PRIVATE_KEY_PWD"
    else
        private_key_pwd_source="未命中"
    fi

    # 显示私钥路径和私钥密码的前后3位, 便于确认环境变量读取是否正确.
    log_debug "私钥来源: ${private_key_source}"
    log_debug "私钥密码来源: ${private_key_pwd_source}"
    log_debug "私钥路径首尾3位: ${private_key:0:3}...${private_key: -3}"
    log_debug "私钥密码首尾3位: ${private_key_pwd:0:3}...${private_key_pwd: -3}"

    if [ -z "$private_key" ]; then
        log_error "签名失败, 未提供私钥文件路径"
        return 1
    fi

    if [ -z "$private_key_pwd" ]; then
        log_error "签名失败, 未检测到可用的私钥密码变量(COSIGN_PRIVATE_KEY_PWD)"
        return 1
    fi

    private_key_file=$(docker_resolve_key_file "$private_key" "私钥") || return 1

    local image_ref
    image_ref=$(docker_build_image_reference "$image_name" "$ref_mode" "$ref_value") || return 1

    log_info "开始签名镜像: $image_ref"

    if ! COSIGN_PASSWORD="$private_key_pwd" cosign sign --yes --key "$private_key_file" "$image_ref"; then
        [ "$private_key_file" != "$private_key" ] && rm -f "$private_key_file"
        log_error "镜像签名失败: $image_ref"
        return 1
    fi

    [ "$private_key_file" != "$private_key" ] && rm -f "$private_key_file"

    log_info "镜像签名成功: $image_ref"
}

# 使用 Cosign 验证镜像签名.
# 参数: $1: 公钥文件路径.
# 参数: $2: 镜像名称.
# 参数: $3: 引用模式, 仅支持 tag 或 digest.
# 参数: $4: tag 或 digest 的具体值.
docker_verify_image() {
    log_debug "run docker_verify_image"

    local public_key="$1"
    local image_name="$2"
    local ref_mode="$3"
    local ref_value="$4"
    local public_key_file=""

    docker_check_cosign || return 1

    if [ -z "$public_key" ]; then
        log_error "验签失败, 未提供公钥文件路径"
        return 1
    fi

    public_key_file=$(docker_resolve_key_file "$public_key" "公钥") || return 1

    local image_ref
    image_ref=$(docker_build_image_reference "$image_name" "$ref_mode" "$ref_value") || return 1

    log_info "开始验签镜像: $image_ref"

    if ! cosign verify --key "$public_key_file" "$image_ref"; then
        [ "$public_key_file" != "$public_key" ] && rm -f "$public_key_file"
        log_error "镜像验签失败: $image_ref"
        return 1
    fi

    [ "$public_key_file" != "$public_key" ] && rm -f "$public_key_file"

    log_info "镜像验签成功: $image_ref"
}

# 在镜像推送完成后, 获取 digest 并完成签名.
# 参数: $1: 镜像名称.
# 参数: $2: 已推送的 tag.
# 参数: $3: 私钥文件路径, 未传则使用 COSIGN_PRIVATE_KEY.
docker_sign_pushed_image() {
    log_debug "run docker_sign_pushed_image"

    local image_name="$1"
    local image_tag="$2"
    local private_key="${3:-$COSIGN_PRIVATE_KEY}"

    if [ -z "$image_name" ] || [ -z "$image_tag" ]; then
        log_error "镜像签名失败, 镜像名称和 tag 不能为空"
        return 1
    fi

    local image_digest
    image_digest=$(docker_get_digest "$image_name" "tag" "$image_tag") || return 1
    docker_sign_image "$private_key" "$image_name" "digest" "$image_digest" || return 1

    log_info "镜像签名完成, 镜像: $image_name, digest: $image_digest"
}

# 删除本地已打 tag 的镜像, 保留 build 标签.
# 参数: $1: 镜像名称.
# 参数: $2: 版本 tag.
docker_remove_local_tagged_images() {
    log_debug "run docker_remove_local_tagged_images"

    local image_name="$1"
    local image_tag="$2"

    if [ -z "$image_name" ] || [ -z "$image_tag" ]; then
        log_error "删除本地 tag 镜像失败, 镜像名称和 tag 不能为空"
        return 1
    fi

    if ! sudo docker image rm "$image_name:$image_tag" "$image_name:latest" >/dev/null 2>&1; then
        log_warn "删除本地 tag 镜像失败, 请手动检查: $image_name:$image_tag, $image_name:latest"
        return 1
    fi

    # 清理
    docker_clear_cache

    log_info "删除本地 tag 镜像成功: $image_name:$image_tag, $image_name:latest"
}

# 镜像打标签并推送到 docker hub
docker_tag_push_docker_hub() {
    log_debug "run docker_tag_push_docker_hub"
    local project=$1
    local version=$2

    # 显示回显 token 的前后3位以确认变量传入正确
    log_debug "token 首尾3位: ${DOCKER_HUB_TOKEN:0:3}...${DOCKER_HUB_TOKEN: -3}"

    # 登录 docker hub
    docker_login_retry "$DOCKER_HUB_REGISTRY" "$DOCKER_HUB_OWNER" "$DOCKER_HUB_TOKEN"

    # 查看当前version标签是否存在
    if sudo docker manifest inspect "$DOCKER_HUB_OWNER/$project:$version" >/dev/null 2>&1; then
        log_warn "Docker Hub 镜像 $DOCKER_HUB_OWNER/$project:$version 已存在, 跳过推送"

        # 避免无法推送, 及时出登录
        sudo docker logout "$DOCKER_HUB_REGISTRY" || true
        return 0
    fi

    # 转换版本号为 Docker tag 兼容格式
    local docker_tag_version
    docker_tag_version=$(semver_to_docker_tag "$version")
    local image_name="$DOCKER_HUB_OWNER/$project"

    # 确定 build 镜像来源（GitHub Actions 中无私有 registry，直接用本地 tag）
    local build_img_source="$REGISTRY_REMOTE_SERVER/$project:build"
    if [ "${GITHUB_ACTIONS}" = "true" ]; then
        build_img_source="$project:build"
    fi

    # tag 镜像
    sudo docker tag "$build_img_source" "$DOCKER_HUB_OWNER/$project:$docker_tag_version"
    sudo docker tag "$build_img_source" "$DOCKER_HUB_OWNER/$project:latest"

    # 推送镜像到 docker hub
    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "$docker_tag_version"

    # 等待 5 秒以确保镜像在 Docker Hub 上可见, 避免推送 latest 失败
    waiting 5

    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "latest"

    # 推送完成后对版本镜像签名.
    docker_sign_pushed_image "$image_name" "$docker_tag_version" "$COSIGN_PRIVATE_KEY" || {
        sudo docker logout "$DOCKER_HUB_REGISTRY" || true
        return 1
    }

    # 推送和签名成功后, 清理本地版本 tag 与 latest, 保留 build 标签供后续复用.
    docker_remove_local_tagged_images "$image_name" "$docker_tag_version" || true

    # 避免无法推送, 及时出登录
    sudo docker logout "$DOCKER_HUB_REGISTRY" || true
}

# 镜像打标签并推送到私有仓库
docker_tag_push_private_registry() {
    log_debug "run docker_tag_push_private_registry"
    local project=$1
    local version=$2

    # 转换版本号为 Docker tag 兼容格式
    local docker_tag_version
    docker_tag_version=$(semver_to_docker_tag "$version")
    local image_name="$REGISTRY_REMOTE_SERVER/$project"

    # tag 镜像
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$REGISTRY_REMOTE_SERVER/$project:$docker_tag_version"
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$REGISTRY_REMOTE_SERVER/$project:latest"

    # 显示回显密码的前后3位以确认变量传入正确
    log_debug "密码 首尾3位: ${REGISTRY_PASSWORD:0:3}...${REGISTRY_PASSWORD: -3}"

    # 登录私有仓库
    docker_login_retry "$REGISTRY_REMOTE_SERVER" "$REGISTRY_USER_NAME" "$REGISTRY_PASSWORD"

    # 推送镜像到私有仓库
    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER" "$project" "$docker_tag_version"

    # 等待 5 秒以确保镜像在远端可见, 避免推送 latest 失败
    waiting 5

    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER" "$project" "latest"

    # 推送完成后对版本镜像签名.
    docker_sign_pushed_image "$image_name" "$docker_tag_version" "$COSIGN_PRIVATE_KEY" || {
        sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
        return 1
    }

    # 推送和签名成功后, 清理本地版本 tag 与 latest, 保留 build 标签供后续复用.
    docker_remove_local_tagged_images "$image_name" "$docker_tag_version" || true

    # 避免无法推送,及时出登录
    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
}

# 私有仓库登录执行函数登出
docker_private_registry_login_logout() {
    log_debug "run docker_private_registry_login_logout"

    local run_func="$1"
    local run_status=0

    # 显示回显密码的前后3位以确认变量传入正确
    log_debug "密码 首尾3位: ${REGISTRY_PASSWORD:0:3}...${REGISTRY_PASSWORD: -3}"

    # 登录私有仓库
    sudo docker login "$REGISTRY_REMOTE_SERVER" -u "$REGISTRY_USER_NAME" --password-stdin <<<"$REGISTRY_PASSWORD"

    # 执行传入的函数
    $run_func || run_status=$?

    # 避免无法推送,及时出登录
    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true

    return "$run_status"
}

# 镜像打标签并推送到腾讯云公共仓库
# 参数: $1 本地镜像名称(标准 docker hub 风格, 如 redis / postgres / elasticsearch / $DOCKER_HUB_OWNER/blog-server)
# 参数: $2 本地镜像版本(本地 tag, 例如 8.0.5、build、1.0.8)
# 参数: $3 推送到腾讯仓库时使用的版本(例如 8.0.5、1.0.8); 不传则等于参数 2
# 参数: $4 是否签名, 可选值 true / false; 默认 true
docker_tag_push_public_registry_tencent() {
    log_debug "run docker_tag_push_public_registry_tencent"

    local local_image="$1"
    local local_version="$2"
    local tencent_version="${3:-$2}"
    local should_sign="${4:-true}"

    if [ -z "$local_image" ] || [ -z "$local_version" ]; then
        log_error "推送到腾讯仓库失败, 镜像名称和版本不能为空"
        return 1
    fi

    if [ -z "$REGISTRY_REMOTE_SERVER_TENCENT" ]; then
        log_error "腾讯仓库地址 REGISTRY_REMOTE_SERVER_TENCENT 未配置"
        return 1
    fi

    if [ -z "$REGISTRY_USER_NAME_TENCENT" ] || [ -z "$REGISTRY_PASSWORD_TENCENT" ]; then
        log_error "腾讯仓库用户名/密码未配置, 跳过推送 $local_image:$local_version"
        log_error "请通过环境变量 REGISTRY_USER_NAME_TENCENT/REGISTRY_PASSWORD_TENCENT,"
        log_error "或写入文件 $BLOG_TOOL_ENV/private_user_tencent 与 $BLOG_TOOL_ENV/private_password_tencent 后重试"
        return 1
    fi

    # 取本地镜像的 basename, 与腾讯仓库 owner 拼接
    local image_basename="${local_image##*/}"
    local tencent_image="$REGISTRY_REMOTE_SERVER_TENCENT/$image_basename"

    # 转换版本号为 Docker tag 兼容格式
    local docker_tag_version
    docker_tag_version=$(semver_to_docker_tag "$tencent_version")

    # tag 镜像
    sudo docker tag "$local_image:$local_version" "$tencent_image:$docker_tag_version"
    sudo docker tag "$local_image:$local_version" "$tencent_image:latest"

    # 显示密码前后3位
    log_debug "腾讯密码 首尾3位: ${REGISTRY_PASSWORD_TENCENT:0:3}...${REGISTRY_PASSWORD_TENCENT: -3}"

    # 腾讯仓库登录端点(去掉 owner 路径段)
    local tencent_login_host="${REGISTRY_REMOTE_SERVER_TENCENT%%/*}"

    # 登录腾讯仓库
    docker_login_retry "$tencent_login_host" "$REGISTRY_USER_NAME_TENCENT" "$REGISTRY_PASSWORD_TENCENT"

    # 推送
    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER_TENCENT" "$image_basename" "$docker_tag_version"
    waiting 5
    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER_TENCENT" "$image_basename" "latest"

    if [ "$should_sign" = true ]; then
        # 推送完成后对版本镜像签名.
        docker_sign_pushed_image "$tencent_image" "$docker_tag_version" "$COSIGN_PRIVATE_KEY" || {
            sudo docker logout "$tencent_login_host" || true
            return 1
        }
    else
        log_debug "跳过腾讯仓库镜像签名: $tencent_image:$docker_tag_version"
    fi

    # 推送完成后清理本地腾讯前缀 tag, 避免污染本地镜像列表
    sudo docker image rm "$tencent_image:$docker_tag_version" "$tencent_image:latest" >/dev/null 2>&1 || true

    # 及时退出登录
    sudo docker logout "$tencent_login_host" || true

    log_info "推送到腾讯仓库成功: $tencent_image:$docker_tag_version"
}

# 区域感知镜像拉取: 国内非腾讯云从腾讯仓库拉取并 tag 回标准名, 其他区域走默认拉取.
# 参数: $1 标准镜像名 (如 redis、postgres、elasticsearch、$DOCKER_HUB_OWNER/blog-server)
# 参数: $2 版本
docker_pull_image_with_region() {
    log_debug "run docker_pull_image_with_region"

    local standard_image="$1"
    local version="$2"

    if [ -z "$standard_image" ] || [ -z "$version" ]; then
        log_error "区域感知拉取失败, 镜像名和版本不能为空"
        return 1
    fi

    local region
    region=$(detect_docker_region)

    if [ "$region" != "cn_non_tencent" ]; then
        timeout_retry_docker_pull "$standard_image" "$version"
        return $?
    fi

    # 国内非腾讯云: 从腾讯公共仓库拉取(无需登录), 拉取后 tag 为标准名以保持 compose 引用统一
    local image_basename="${standard_image##*/}"
    local tencent_image="$REGISTRY_REMOTE_SERVER_TENCENT/$image_basename"

    log_info "检测到国内非腾讯云环境, 从腾讯公共仓库拉取: $tencent_image:$version"

    timeout_retry_docker_pull "$tencent_image" "$version" || return 1

    sudo docker tag "$tencent_image:$version" "$standard_image:$version"
    sudo docker image rm "$tencent_image:$version" >/dev/null 2>&1 || true

    log_debug "已将 $tencent_image:$version 重打标签为 $standard_image:$version"
}

# 获取构建阶段应使用的基础镜像引用.
# 参数: $1 标准镜像名 (如 redis、postgres、elasticsearch、$DOCKER_HUB_OWNER/blog-server)
# 参数: $2 版本.
# 返回: 输出当前区域下最合适的镜像引用, 供 Dockerfile FROM 使用.
docker_get_base_image_with_region() {
    log_debug "run docker_get_base_image_with_region"

    local standard_image="$1"
    local version="$2"

    if [ -z "$standard_image" ] || [ -z "$version" ]; then
        log_error "获取区域基础镜像失败, 镜像名和版本不能为空"
        return 1
    fi

    local region
    region=$(detect_docker_region)

    if [ "$region" != "cn_non_tencent" ]; then
        echo "$standard_image:$version"
        return 0
    fi

    local image_basename="${standard_image##*/}"
    echo "$REGISTRY_REMOTE_SERVER_TENCENT/$image_basename:$version"
}

# 检测 docker 镜像源区域: 输出 tencent_cn | cn_non_tencent | overseas, 结果在进程内缓存
DOCKER_REGION_CACHE=""

# 清空 docker 镜像源区域缓存, 供依赖安装后触发重新探测.
# 返回: 始终返回 0.
reset_docker_region_cache() {
    DOCKER_REGION_CACHE=""
}

detect_docker_region() {
    if [ -n "$DOCKER_REGION_CACHE" ]; then
        echo "$DOCKER_REGION_CACHE"
        return 0
    fi

    local region="overseas"
    local country=""
    local has_probe_tool="false"

    if command -v curl >/dev/null 2>&1; then
        has_probe_tool="true"
        country=$(curl -s --max-time 5 ipinfo.io/country)
    elif command -v wget >/dev/null 2>&1; then
        has_probe_tool="true"
        country=$(wget -qO- -T 5 ipinfo.io/country 2>/dev/null)
    fi

    if [ "$has_probe_tool" != "true" ]; then
        log_debug "当前未安装 curl 或 wget, 暂时无法探测 docker 镜像源区域, 稍后重试"
        echo "$region"
        return 0
    fi

    if [[ "$country" == "CN" ]]; then
        if command -v curl >/dev/null 2>&1 && curl -s --max-time 5 -I https://mirror.ccs.tencentyun.com/ >/dev/null 2>&1; then
            region="tencent_cn"
        elif command -v wget >/dev/null 2>&1 && wget -q --spider -T 5 https://mirror.ccs.tencentyun.com/ >/dev/null 2>&1; then
            region="tencent_cn"
        else
            region="cn_non_tencent"
        fi
    fi

    DOCKER_REGION_CACHE="$region"
    log_debug "检测到 docker 镜像源区域: $region"
    echo "$region"
}

# 推送 db 镜像(redis / postgres / elasticsearch)到腾讯公共仓库.
# 需要本地已存在 redis:$IMG_VERSION_REDIS 等标准 tag 的镜像.
push_db_images_public_registry_tencent() {
    log_debug "run push_db_images_public_registry_tencent"

    docker_tag_push_public_registry_tencent "redis" "$IMG_VERSION_REDIS" "$IMG_VERSION_REDIS" false
    docker_tag_push_public_registry_tencent "postgres" "$IMG_VERSION_PGSQL" "$IMG_VERSION_PGSQL" false
    docker_tag_push_public_registry_tencent "elasticsearch" "$IMG_VERSION_ES" "$IMG_VERSION_ES" false

    log_info "数据库基础镜像推送到腾讯公共仓库完成"
}
