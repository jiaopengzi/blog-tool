#!/bin/bash
# FilePath    : blog-tool/docker/images.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : docker镜像拉取

# 拉取开发环境镜像
pull_docker_image_dev() {
    log_debug "run pull_docker_image_dev"

    # 拉取必要的docker镜像

    timeout_retry_docker_pull "alpine" "$IMG_VERSION_ALPINE"
    timeout_retry_docker_pull "golang" "$IMG_VERSION_GOLANG"
    timeout_retry_docker_pull "node" "$IMG_VERSION_NODE"
    timeout_retry_docker_pull "redis" "$IMG_VERSION_REDIS"
    timeout_retry_docker_pull "postgres" "$IMG_VERSION_PGSQL"
    timeout_retry_docker_pull "elasticsearch" "$IMG_VERSION_ES"
    timeout_retry_docker_pull "kibana" "$IMG_VERSION_KIBANA"
    timeout_retry_docker_pull "nginx" "$IMG_VERSION_NGINX"
    timeout_retry_docker_pull "registry" "$IMG_VERSION_REGISTRY"
    timeout_retry_docker_pull "httpd" "$IMG_VERSION_HTTPD"

    log_info "docker 开发环境镜像拉取完成"
}

# 拉取生产环境db镜像
pull_docker_image_pro_db() {
    log_debug "run pull_docker_image_pro_db"

    # 拉取必要的docker镜像

    timeout_retry_docker_pull "redis" "$IMG_VERSION_REDIS"
    timeout_retry_docker_pull "postgres" "$IMG_VERSION_PGSQL"
    timeout_retry_docker_pull "elasticsearch" "$IMG_VERSION_ES"

    log_info "docker 生产环境数据库镜像拉取完成"
}

# 拉取生产环境db镜像
pull_docker_image_pro_db_billing_center() {
    log_debug "run pull_docker_image_pro_db_billing_center"

    # 拉取必要的docker镜像

    timeout_retry_docker_pull "redis" "$IMG_VERSION_REDIS"
    timeout_retry_docker_pull "postgres" "$IMG_VERSION_PGSQL"

    log_info "docker 生产环境数据库镜像拉取完成"
}

# 拉取生产环境所有镜像
pull_docker_image_pro_all() {
    log_debug "run pull_docker_image_pro_all"

    local has_db
    has_db=$(read_user_input "是否包含数据库镜像 pgsql redis es (默认y) [y|n]? " "y")

    if [[ "$has_db" == "y" ]]; then
        pull_docker_image_pro_db
    fi

    docker_pull_server
    docker_pull_client
}
