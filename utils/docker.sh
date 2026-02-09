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

    # tag 镜像
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$DOCKER_HUB_OWNER/$project:$docker_tag_version"
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$DOCKER_HUB_OWNER/$project:latest"

    # 推送镜像到 docker hub
    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "$docker_tag_version"

    # 等待 5 秒以确保镜像在 Docker Hub 上可见, 避免推送 latest 失败
    waiting 5

    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "latest"

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

    # 避免无法推送,及时出登录
    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
}

# 私有仓库登录执行函数登出
docker_private_registry_login_logout() {
    log_debug "run docker_private_registry_login_logout"

    local run_func="$1"

    # 显示回显密码的前后3位以确认变量传入正确
    log_debug "密码 首尾3位: ${REGISTRY_PASSWORD:0:3}...${REGISTRY_PASSWORD: -3}"

    # 登录私有仓库
    sudo docker login "$REGISTRY_REMOTE_SERVER" -u "$REGISTRY_USER_NAME" --password-stdin <<<"$REGISTRY_PASSWORD"

    # 执行传入的函数
    $run_func

    # 避免无法推送,及时出登录
    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
}
