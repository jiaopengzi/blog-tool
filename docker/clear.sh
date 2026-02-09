#!/bin/bash
# FilePath    : blog-tool/docker/clear.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : docker清理

# 清理容器、镜像、网络、构建缓存
docker_clear_cache() {
    log_debug "run docker_clear_cache"

    # 删除无用的镜像、容器、网络、构建缓存
    sudo docker container prune -f # 删除所有停止状态的容器
    sudo docker network prune -f   # 删除所有不使用的网络
    sudo docker image prune -f     # 删除所有不使用的镜像
    sudo docker builder prune -f   # 删除所有不使用的构建缓存

    # 删除标签为 <none> 的镜像
    sudo docker images | grep "<none>" | awk '{print $3}' | xargs sudo docker rmi -f || true
}
