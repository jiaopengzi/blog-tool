#!/bin/bash
# FilePath    : blog-tool/billing-center/nginx.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2026 by jiaopengzi, All Rights Reserved.
# Description : billing_center nginx 相关

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

    log_info "client 复制配置文件到 volume success"
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

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    # 修改证书目录权限
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR/billing-center/config/"

    log_info "billing-center 复制配置文件到 volume success"
}
