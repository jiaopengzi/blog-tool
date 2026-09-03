#!/bin/bash
# FilePath    : blog-tool/client/config.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : client nginx 模板与 SSL 配置复制

# client_get_compose_image 从 client Compose 文件读取目标镜像引用.
# 参数: 无.
# 返回: 成功时输出镜像引用, Compose 文件或 image 字段缺失时返回非 0.
client_get_compose_image() {
    local client_image=""

    if [[ ! -f "$DOCKER_COMPOSE_FILE_CLIENT" ]]; then
        log_error "未找到 client Compose 文件: $DOCKER_COMPOSE_FILE_CLIENT"
        return 1
    fi

    client_image="$(awk '
        /^[[:space:]]*image:[[:space:]]*/ {
            sub(/^[[:space:]]*image:[[:space:]]*/, "")
            print
            exit
        }
    ' "$DOCKER_COMPOSE_FILE_CLIENT")"

    if [[ -z "$client_image" ]]; then
        log_error "未从 client Compose 文件读取到镜像: $DOCKER_COMPOSE_FILE_CLIENT"
        return 1
    fi

    printf '%s\n' "$client_image"
}

# client_image_has_nuxt_runtime_config 判断目标镜像是否提供 Nuxt nginx 模板.
# 参数: $1: client 镜像引用.
# 返回: 镜像包含 nginx.conf.template 时返回 0, 否则返回非 0.
client_image_has_nuxt_runtime_config() {
    local client_image="$1"

    sudo docker run --rm --entrypoint /bin/sh "$client_image" \
        -c 'test -f /etc/nginx/nginx.conf.template' >/dev/null 2>&1
}

# client_copy_nuxt_runtime_assets 按需从 Nuxt 镜像复制 nginx 模板运行资产到持久化目录.
# 参数: $1: client 镜像引用. $2: 持久化 nginx 配置目录.
# 返回: 必需模板资产复制成功时返回 0, 容器或文件复制失败时返回非 0.
client_copy_nuxt_runtime_assets() {
    local client_image="$1"
    local nginx_dir="$2"
    local temp_container="temp_container_blog_client_config_migration"
    local copy_status=0

    if ! sudo mkdir -p "$nginx_dir"; then
        log_error "创建 client nginx 配置目录失败: $nginx_dir"
        return 1
    fi

    sudo docker rm -f "$temp_container" >/dev/null 2>&1 || true
    if ! sudo docker create --name "$temp_container" "$client_image" >/dev/null; then
        log_error "创建 client 配置迁移临时容器失败: $client_image"
        return 1
    fi

    if [[ ! -f "$nginx_dir/nginx.conf.template" ]] \
        && ! sudo docker cp "$temp_container:/etc/nginx/nginx.conf.template" "$nginx_dir/nginx.conf.template"; then
        log_error "复制 Nuxt nginx 模板失败: $client_image"
        copy_status=1
    fi

    if [[ $copy_status -eq 0 && ! -f "$nginx_dir/mime.types" ]] \
        && ! sudo docker cp "$temp_container:/etc/nginx/mime.types" "$nginx_dir/mime.types"; then
        log_error "复制 Nuxt mime.types 失败: $client_image"
        copy_status=1
    fi

    if [[ $copy_status -eq 0 && ! -f "$nginx_dir/redirects.map" ]]; then
        if ! sudo docker cp "$temp_container:/etc/nginx/redirects.map" "$nginx_dir/redirects.map"; then
            log_warn "Nuxt 镜像未提供 redirects.map, 跳过复制: $client_image"
        fi
    fi

    sudo docker rm -f "$temp_container" >/dev/null 2>&1 || true
    return "$copy_status"
}

# client_migrate_runtime_config 在 Nuxt 升级或 SPA 回滚前迁移持久化 nginx 配置.
# 参数: 无.
# 返回: 配置无需迁移或迁移成功时返回 0, Compose、镜像或配置资产异常时返回非 0.
client_migrate_runtime_config() {
    local nginx_dir="$DATA_VOLUME_DIR/blog-client/nginx"
    local nginx_conf_file="$nginx_dir/nginx.conf"
    local nuxt_template_file="$nginx_dir/nginx.conf.template"
    local spa_backup_file="${nginx_conf_file}.pre-nuxt"
    local client_image=""

    if [[ ! -d "$nginx_dir" ]]; then
        log_debug "未发现持久化 client nginx 配置目录, 跳过迁移: $nginx_dir"
        return 0
    fi

    client_image="$(client_get_compose_image)" || return 1
    if ! sudo docker image inspect "$client_image" >/dev/null 2>&1; then
        log_error "未找到 client 目标镜像, 无法迁移 nginx 配置: $client_image"
        return 1
    fi

    if client_image_has_nuxt_runtime_config "$client_image"; then
        if [[ ! -f "$nuxt_template_file" ]]; then
            if [[ -f "$nginx_conf_file" && ! -f "$spa_backup_file" ]]; then
                if ! sudo cp -a "$nginx_conf_file" "$spa_backup_file"; then
                    log_error "备份旧 client nginx 配置失败: $nginx_conf_file"
                    return 1
                fi
            fi

            client_copy_nuxt_runtime_assets "$client_image" "$nginx_dir" || return 1
            log_info "client nginx 配置已迁移为 Nuxt 模板运行模式"
        elif [[ ! -f "$nginx_dir/mime.types" ]]; then
            client_copy_nuxt_runtime_assets "$client_image" "$nginx_dir" || return 1
        fi

        setup_directory "$CLIENT_UID" "$CLIENT_GID" 755 \
            "$DATA_VOLUME_DIR/blog-client" \
            "$nginx_dir" \
            "$nginx_dir/ssl"
        return 0
    fi

    if [[ -f "$spa_backup_file" ]]; then
        if ! sudo cp -a "$spa_backup_file" "$nginx_conf_file"; then
            log_error "恢复 SPA client nginx 配置失败: $spa_backup_file"
            return 1
        fi
        log_info "client 已切回 SPA 镜像, 已恢复旧 nginx 配置"
    fi
}

# copy_client_config 从镜像复制 nginx 模板和基础配置到宿主机 volume.
# 参数: 无.
# 返回: 复制成功返回 0, Docker 操作失败时由调用命令返回非 0.
copy_client_config() {

    log_debug "run copy_client_config"

    dir_client="$DATA_VOLUME_DIR/blog-client/nginx"

    sudo rm -rf "$dir_client"

    # shellcheck disable=SC2329
    run_copy_config() {
        # 复制配置文件到 volume 目录
        sudo docker cp temp_container_blog_client:/etc/nginx "$DATA_VOLUME_DIR/blog-client" # 复制配置文件
    }

    docker_create_client_temp_container run_copy_config "latest"

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$CLIENT_UID" "$CLIENT_GID" 755 \
        "$DATA_VOLUME_DIR/blog-client" \
        "$DATA_VOLUME_DIR/blog-client/nginx" \
        "$DATA_VOLUME_DIR/blog-client/nginx/ssl"

    # Nuxt 镜像不再内置 nginx.conf; 容器入口根据 Compose 的环境变量渲染 nginx.conf.template.
    log_info "client nginx 模板复制到 volume success"
}

# 复制 blog_client 配置文件
copy_client_config_ssl() {

    log_debug "run copy_client_config_ssl"

    dir_ssl="$DATA_VOLUME_DIR/blog-client/nginx/ssl"

    sudo rm -rf "$dir_ssl"

    if [ "${AUTO_MODE:-false}" = "true" ]; then
        gen_client_nginx_cert
    fi

    # 如果当前目录下 certs_nginx 文件夹不存在则输出提示
    if [ ! -d "$CERTS_NGINX" ]; then
        echo "========================================"
        echo "    请将证书 $CERTS_NGINX 文件夹放到当前目录"
        echo "    证书文件夹结构如下:"
        echo "    $CERTS_NGINX"
        echo "    ├── cert.key"
        echo "    └── cert.pem"
        echo "========================================"
        log_error "请将证书 $CERTS_NGINX 文件夹放到当前目录"
        exit 1
    fi

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$CLIENT_UID" "$CLIENT_GID" 755 \
        "$DATA_VOLUME_DIR/blog-client" \
        "$DATA_VOLUME_DIR/blog-client/nginx" \
        "$DATA_VOLUME_DIR/blog-client/nginx/ssl"

    # 判断当前目录是否为空
    if [ -z "$(ls -A "$CERTS_NGINX")" ]; then
        log_error "证书目录 $CERTS_NGINX 为空, 请添加证书文件"

        ssl_msg "$RED"
        exit 1
    fi

    # 将证书 certs_nginx 目录复制到 volume/blog-client/nginx/ssl 目录
    # **注意这里的引号不要将星号包裹,否则会报错 cp: 对 '/path/to/volume/certs_nginx/*' 调用 stat 失败: 没有那个文件或目录**
    sudo cp -r "$CERTS_NGINX"/* "$DATA_VOLUME_DIR/blog-client/nginx/ssl/"

    # 修改证书目录权限
    setup_directory "$CLIENT_UID" "$CLIENT_GID" 755 "$DATA_VOLUME_DIR/blog-client/nginx/ssl/"

    log_info "client 复制证书文件到 volume success"
}
