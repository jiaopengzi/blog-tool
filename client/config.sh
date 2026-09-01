#!/bin/bash
# FilePath    : blog-tool/client/config.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : client nginx 模板与 SSL 配置复制

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
