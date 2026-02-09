#!/bin/bash
# FilePath    : blog-tool/utils/mode_env.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 模式环境工具

# 判断当前运行模式是否为生产环境
run_mode_is_pro() {
    if [ "$RUN_MODE" == "pro" ]; then
        log_debug "run_mode_is_pro: 当前运行模式为生产环境"
        return 0
    else
        log_debug "run_mode_is_pro: 当前运行模式为开发环境"
        return 1
    fi
}

# 判断当前运行模式是否为开发环境
run_mode_is_dev() {
    if run_mode_is_pro; then
        return 1
    else
        return 0
    fi
}

# 获取镜像前缀
get_img_prefix() {
    # 默认镜像前缀
    local img_prefix="$DOCKER_HUB_OWNER"

    # 如果是开发环境就使用私有仓库地址作为前缀
    if run_mode_is_dev; then
        img_prefix="$REGISTRY_REMOTE_SERVER"
    fi

    echo "$img_prefix"
}

# 判断版本是否为生产环境版本
version_is_pro() {
    local version="$1"

    # 根据 version_part 按照语义化版本规范过滤生产环境版本, 即只允许 vX.Y.Z 格式的版本号
    if [[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        log_debug "version_is_pro: $version 符合生产环境版本规范"
        return 0
    else
        log_debug "version_is_pro: $version 不符合生产环境版本规范"
        return 1
    fi
}

version_is_dev() {
    local version="$1"
    if version_is_pro "$version"; then
        return 1
    else
        return 0
    fi
}

# 解析版本号
parsing_version() {
    local version="$1"
    local version_date is_dev

    # 生成时间戳版本(用于 dev 场景)
    version_date=$(date +%y%m%d%H%M)

    # 默认视为开发版本
    is_dev=true

    # 如果符合语义化版本规范(x.y.z), 则视为生产版本
    if version_is_pro "$version"; then
        is_dev=false
        echo "$version" "$is_dev"
        return
    fi

    # 若未指定版本或显式为 "dev", 则使用带时间戳的 dev 版本
    if [[ "$version" == "dev" || -z "$version" ]]; then
        version="dev-$version_date"
    fi

    echo "$version" "$is_dev"
}
