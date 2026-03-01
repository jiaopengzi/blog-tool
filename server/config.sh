#!/bin/bash
# FilePath    : blog-tool/server/config.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : server 配置

# 设置 server is_setup
server_set_is_setup() {
    log_debug "run server_is_setup"

    local setup_flag="$1"

    # app 修改
    if [ "$setup_flag" == true ]; then
        sudo sed -r -i "s|is_setup: false|is_setup: true|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"
    else
        sudo sed -r -i "s|is_setup: true|is_setup: false|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"
    fi

    log_info "server 设置 is_setup=$setup_flag success"
}

# 设置 server es 是否使用用户自定义 ca 证书
server_set_es_use_ca_cert() {
    log_debug "run server_set_es_use_ca_cert"

    local setup_flag="$1"

    # app 修改
    if [ "$setup_flag" == true ]; then
        sudo sed -r -i "s|use_ca_cert: false|use_ca_cert: true|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"
    else
        sudo sed -r -i "s|use_ca_cert: true|use_ca_cert: false|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"
    fi

    log_info "server 设置 es use_ca_cert=$setup_flag success"
}

# 设置 server es jwt secret key
server_update_jwt_secret_key() {
    log_debug "run server_update_jwt_secret_key"
    # 生成一个随机64位的 secret key
    local secret_key
    secret_key="$(openssl rand -hex 32)"
    log_debug "generated jwt secret key: $secret_key"

    # 使用单引号包围整个sed表达式，并且正确转义双引号
    sudo sed -i "s%secret_key:[[:space:]]*\"[^\"]*\"%secret_key: \"$secret_key\"%" "$DATA_VOLUME_DIR/blog-server/config/jwt.yaml"
}

# 更新 server 配置文件中的数据库密码
server_update_password_key() {
    log_debug "run server_update_password_key"

    local config_dir="$DATA_VOLUME_DIR/blog-server/config"

    # pgsql 密码更新
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$POSTGRES_PASSWORD\"%" "$config_dir/pgsql.yaml"

    # redis 密码更新(所有节点)
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$REDIS_PASSWORD\"%" "$config_dir/redis.yaml"

    # es 密码更新
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$ELASTIC_PASSWORD\"%" "$config_dir/es.yaml"

    log_info "server 更新数据库密码配置 success"
}

# 设置 server 主机地址
server_set_host() {
    log_debug "run server_is_setup"

    local host_addr="$1"

    # 替换 host 地址带有双引号的情况
    sudo sed -r -i "s|host: \"http[s]*://[a-z0-9.:]*\"|host: \"$host_addr\"|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"

    # 替换 host 地址不带双引号的情况
    sudo sed -r -i "s|host: http[s]*://[a-z0-9.:]*|host: $host_addr|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"

    log_info "server 设置 host=$host_addr success"
}

# 复制 blog_server 配置文件
copy_server_config() {
    log_debug "run copy_server_config"
    # 是否已经使用当前工具安装数据库, 默认是
    local web_set_db="${1-n}"

    log_debug "web_set_db=$web_set_db"

    dir_server="$DATA_VOLUME_DIR/blog-server/config"

    sudo rm -rf "$dir_server"

    # shellcheck disable=SC2329
    run_copy_config() {
        # 复制配置文件到 volume 目录 不能使用 sudo docker compose cp，因为yaml中设置了 volume 会覆盖掉
        sudo docker cp temp_container_blog_server:/home/blog-server/config "$dir_server" # 复制配置文件
    }

    docker_create_server_temp_container run_copy_config "latest"

    # 将配置文件中ip地址替换为服务器内网ip地址(s双引号)
    # 严格匹配 IPv4(避免匹配空串)
    sudo sed -r -i "s|^([[:space:]]*host:[[:space:]]*)(\"?)[0-9]{1,3}(\.[0-9]{1,3}){3}(\"?)|\1\2$HOST_INTRANET_IP\4|g" "$DATA_VOLUME_DIR/blog-server/config/pgsql.yaml"

    # redis 配置修改
    sudo sed -r -i "s|^([[:space:]]*-[[:space:]]*host:[[:space:]]*)(\"?)[0-9]{1,3}(\.[0-9]{1,3}){3}(\"?)|\1\2$HOST_INTRANET_IP\4|g" "$DATA_VOLUME_DIR/blog-server/config/redis.yaml"

    # es 配置修改
    sudo sed -r -i "s|- \"https://[0-9.:]*\"|- \"https://$HOST_INTRANET_IP:9200\"|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"
    sudo sed -r -i "s|- https://[0-9.:]*|- \"https://$HOST_INTRANET_IP:9200\"|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"

    # 更新 jwt secret key
    server_update_jwt_secret_key

    # 更新数据库密码配置
    server_update_password_key

    # app 设置
    if [ "$web_set_db" == "y" ]; then
        server_set_is_setup false
    else
        server_set_is_setup true

        # 将 es 的 ca.crt 文件内容更新到 es.yaml 文件中
        if [ -f "$CA_CERT_DIR/ca.crt" ]; then
            update_yaml_block "$DATA_VOLUME_DIR/blog-server/config/es.yaml" "ca_cert: |" "$CA_CERT_DIR/ca.crt"
        fi

        # 设置 es 使用 ca 证书
        server_set_es_use_ca_cert true
    fi

    # 设置 host 地址
    server_set_host "https://$DOMAIN_NAME"

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$SERVER_UID" "$SERVER_GID" 755 "$DATA_VOLUME_DIR/blog-server"

    log_info "server 复制配置文件到 volume success"
}
