#!/bin/bash
# FilePath    : blog-tool/client/config.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : client 配置

# 复制 blog_client 配置文件
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

    # 修改 nginx.conf 配置文件中的 blog-server 地址为宿主机内网 IP 地址
    sudo sed -r -i \
        "s/http:\/\/blog-server:5426/http:\/\/$HOST_INTRANET_IP:5426/g" \
        "$DATA_VOLUME_DIR/blog-client/nginx/nginx.conf"

    # 修改 nginx.conf 配置文件中的访问域名, 仅匹配合法域名或 IPv4 的 server_name 指令
    local server_name_pattern='^([[:space:]]*)server_name[[:space:]]+(([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}|([0-9]{1,3}\.){3}[0-9]{1,3});'
    sudo sed -r -i \
        "s/$server_name_pattern/\\1server_name $DOMAIN_NAME;/g" \
        "$DATA_VOLUME_DIR/blog-client/nginx/nginx.conf"

    log_info "client 复制配置文件到 volume success"
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
