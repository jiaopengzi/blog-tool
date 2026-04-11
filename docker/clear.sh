#!/bin/bash
# FilePath    : blog-tool/docker/clear.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : docker清理

# 清理容器、镜像、网络、构建缓存.
# 返回: 0 表示清理完成, 非 0 表示 Docker 命令执行失败.
docker_clear_cache() {
    log_debug "run docker_clear_cache"

    local builder_prune_output
    local builder_prune_status

    # 删除无用的镜像、容器、网络、构建缓存
    sudo docker container prune -f # 删除所有停止状态的容器
    sudo docker network prune -f   # 删除所有不使用的网络
    sudo docker image prune -f     # 删除所有不使用的镜像

    # 过滤 Docker 新版本附带的人类可读提示, 同时保留真实清理结果和错误码.
    builder_prune_output=$(sudo docker builder prune -f 2>&1)
    builder_prune_status=$?
    if [ $builder_prune_status -ne 0 ]; then
        printf '%s\n' "$builder_prune_output" >&2
        return $builder_prune_status
    fi

    printf '%s\n' "$builder_prune_output" | awk '
        $0 != "WARNING: This output is designed for human readability. For machine-readable output, please use --format." {
            print
        }
    '

    # 删除悬空镜像, 避免 Docker 新版本在人类可读输出变化时误判.
    sudo docker image ls --filter "dangling=true" --quiet | xargs -r sudo docker rmi -f || true
}
