#!/bin/bash
# FilePath    : blog-tool/billing-center/nginx.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2026 by jiaopengzi, All Rights Reserved.
# Description : billing_center nginx 相关

# billing_center_get_compose_image 从 billing-center Compose 文件读取目标镜像引用.
# 参数: 无.
# 返回: 成功时输出镜像引用, Compose 文件或 image 字段缺失时返回非 0.
billing_center_get_compose_image() {
    local billing_center_image=""

    if [[ ! -f "$DOCKER_COMPOSE_FILE_BILLING_CENTER" ]]; then
        log_error "未找到 billing-center Compose 文件: $DOCKER_COMPOSE_FILE_BILLING_CENTER"
        return 1
    fi

    billing_center_image="$(awk '
        /^[[:space:]]*image:[[:space:]]*/ {
            sub(/^[[:space:]]*image:[[:space:]]*/, "")
            print
            exit
        }
    ' "$DOCKER_COMPOSE_FILE_BILLING_CENTER")"

    if [[ -z "$billing_center_image" ]]; then
        log_error "未从 billing-center Compose 文件读取到镜像: $DOCKER_COMPOSE_FILE_BILLING_CENTER"
        return 1
    fi

    printf '%s\n' "$billing_center_image"
}

# billing_center_migrate_runtime_config 在升级或回滚前同步目标镜像的 nginx 基础配置.
# 参数: 无.
# 返回: 配置无需迁移或迁移成功时返回 0, 镜像或文件同步失败时返回非 0.
billing_center_migrate_runtime_config() {
    local nginx_dir="$DATA_VOLUME_DIR/billing-center/nginx"
    local billing_center_image=""
    local temp_container="temp_container_blog_billing_center_config_migration"
    local temp_root=""
    local temp_nginx_dir=""

    if [[ ! -d "$nginx_dir" ]]; then
        log_debug "未发现持久化 billing-center nginx 配置目录, 跳过迁移: $nginx_dir"
        return 0
    fi

    billing_center_image="$(billing_center_get_compose_image)" || return 1

    if ! sudo docker image inspect "$billing_center_image" >/dev/null 2>&1; then
        log_error "未找到 billing-center 目标镜像, 无法迁移 nginx 配置: $billing_center_image"
        return 1
    fi

    temp_root="$(mktemp -d "${TMPDIR:-/tmp}/billing-center-nginx.XXXXXX")" || {
        log_error "创建 billing-center nginx 迁移临时目录失败"
        return 1
    }
    temp_nginx_dir="$temp_root/nginx"

    sudo docker rm -f "$temp_container" >/dev/null 2>&1 || true
    if ! sudo docker create --name "$temp_container" "$billing_center_image" >/dev/null; then
        sudo rm -rf "$temp_root"
        log_error "创建 billing-center 配置迁移临时容器失败: $billing_center_image"
        return 1
    fi

    if ! sudo docker cp "$temp_container:/etc/nginx" "$temp_root"; then
        sudo docker rm -f "$temp_container" >/dev/null 2>&1 || true
        sudo rm -rf "$temp_root"
        log_error "复制 billing-center nginx 配置失败: $billing_center_image"
        return 1
    fi

    sudo docker rm -f "$temp_container" >/dev/null 2>&1 || true

    if [[ ! -d "$temp_nginx_dir" ]]; then
        sudo rm -rf "$temp_root"
        log_error "billing-center 目标镜像未提供 /etc/nginx 目录: $billing_center_image"
        return 1
    fi

    if ! find "$nginx_dir" -mindepth 1 -maxdepth 1 ! -name ssl -exec sudo rm -rf {} +; then
        sudo rm -rf "$temp_root"
        log_error "清理旧 billing-center nginx 配置失败: $nginx_dir"
        return 1
    fi

    if ! sudo cp -a "$temp_nginx_dir"/. "$nginx_dir"/; then
        sudo rm -rf "$temp_root"
        log_error "写入 billing-center 新 nginx 配置失败: $nginx_dir"
        return 1
    fi

    sudo rm -rf "$temp_root"

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 \
        "$DATA_VOLUME_DIR/billing-center" \
        "$nginx_dir" \
        "$nginx_dir/ssl"

    log_info "billing-center nginx 配置已同步到目标镜像: $billing_center_image"
}

# 复制 billing-center nginx 配置文件
copy_billing_center_nginx_config() {

    log_debug "run copy_billing_center_nginx_config"

    dir_billing_center="$DATA_VOLUME_DIR/billing-center/nginx"

    sudo rm -rf "$dir_billing_center"

    # shellcheck disable=SC2329
    run_copy_config() {
        # 复制配置文件到 volume 目录
        sudo docker cp temp_container_blog_billing_center:/etc/nginx "$DATA_VOLUME_DIR/billing-center" # 复制配置文件
    }

    docker_create_billing_center_temp_container run_copy_config "latest"

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

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 \
        "$DATA_VOLUME_DIR/billing-center" \
        "$DATA_VOLUME_DIR/billing-center/nginx" \
        "$DATA_VOLUME_DIR/billing-center/nginx/ssl"

    # 判断当前目录是否为空
    if [ -z "$(ls -A "$CERTS_NGINX")" ]; then
        log_error "证书目录 $CERTS_NGINX 为空, 请添加证书文件"

        ssl_msg "$RED"
        exit 1
    fi

    # 将证书 certs_nginx 目录复制到 volume/billing-center/nginx/ssl 目录
    # **注意这里的引号不要将星号包裹,否则会报错 cp: 对 '/path/to/volume/certs_nginx/*' 调用 stat 失败: 没有那个文件或目录**
    sudo cp -r "$CERTS_NGINX"/* "$DATA_VOLUME_DIR/billing-center/nginx/ssl/"

    # 修改证书目录权限
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR/billing-center/nginx/ssl/"

    log_info "billing-center 复制 nginx 配置文件到 volume success"
}

# 更新 billing-center 配置文件中的数据库密码
server_update_password_key_billing_center() {
    log_debug "run server_update_password_key_billing_center"

    local config_dir="$DATA_VOLUME_DIR/billing-center/config"

    # pgsql 密码更新
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$POSTGRES_PASSWORD_BILLING_CENTER\"%" "$config_dir/pgsql.yaml"

    # redis 密码更新(所有节点)
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$REDIS_PASSWORD_BILLING_CENTER\"%" "$config_dir/redis.yaml"

    log_info "billing-center 更新数据库密码配置 success"
}

# 复制 billing-center server 配置文件
copy_billing_center_server_config() {

    log_debug "run copy_billing_center_server_config"

    dir_billing_center="$DATA_VOLUME_DIR/billing-center/config"

    sudo rm -rf "$dir_billing_center"

    # 如果 bc-config 和 cert 目录存在不存在就提示用户准备好配置文件
    if [ ! -d "./bc-config" ]; then
        local msg=""
        msg+="\n请将 billing_center 配置文件准备好并放置到以下目录: "
        msg+="\n    ./bc-config (配置文件)"
        msg+="\n"
        log_warn "$msg"
        log_warn "bc-config 目录不存在, 请先准备好配置文件后再进行全新安装"
        exit 1
    fi

    # 复制配置文件到 volume 目录
    cp -r "./bc-config/" "$DATA_VOLUME_DIR/billing-center/config/"

    # 更新配置文件中的密码
    server_update_password_key_billing_center

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    # 修改配置目录权限
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR/billing-center/config/"

    log_info "billing-center 复制后端配置文件到 volume success"
}
