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
# 使用 JWT_SECRET_KEY 变量(由 check_password_security 统一管理并持久化), 避免重复安装时 key 变更导致业务问题
server_update_jwt_secret_key() {
    log_debug "run server_update_jwt_secret_key"

    local secret_key="$JWT_SECRET_KEY"

    # JWT_SECRET_KEY 未初始化时兜底: 临时生成但不持久化(正常流程不应走到此分支)
    if [[ -z "$secret_key" ]]; then
        log_warn "JWT_SECRET_KEY 未设置, 临时生成随机密钥(建议先运行 check_password_security)"
        secret_key="$(openssl rand -hex 32)"
    fi

    log_debug "使用的 jwt secret key 前16个字符: ${secret_key:0:16}"

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
    log_debug "run server_set_host"

    local host_addr="$1"

    # 替换 host 地址带有双引号的情况
    # 使用 ^ 锚定行首并捕获前导空格, 避免误匹配 billing_center_host 等含 host 的其他字段
    sudo sed -r -i "s|^([[:space:]]*)host: \"http[s]*://[a-z0-9.:]*\"|\1host: \"$host_addr\"|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"

    # 替换 host 地址不带双引号的情况
    sudo sed -r -i "s|^([[:space:]]*)host: http[s]*://[a-z0-9.:]*|\1host: $host_addr|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"

    log_info "server 设置 host=$host_addr success"
}

# 设置项目名称
server_set_project_name() {
    log_debug "run server_set_project_name"

    local project_name="$1"

    # 若仍未设置则跳过
    if [[ -z "$project_name" ]]; then
        log_warn "PROJECT_NAME 未设置, 跳过设置项目名称"
        return 0
    fi

    # 替换 app.yaml 中的 name 字段(支持带/不带双引号)
    sudo sed -r -i "s|^([[:space:]]*)name:[[:space:]]*\"?[^\"]*\"?|\1name: \"$project_name\"|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"

    log_info "server 设置 project name=$project_name success"
}

# server_append_missing_config_entry 仅在配置文件缺少顶级键时追加默认配置.
# 参数: $1: 配置文件路径. $2: 顶级配置键. $3: 要追加的完整 YAML 配置行.
# 返回: 配置已存在或追加成功时返回 0, 配置文件不存在或写入失败时返回非 0.
server_append_missing_config_entry() {
    local config_file="$1"
    local config_key="$2"
    local config_entry="$3"

    if [[ ! -f "$config_file" ]]; then
        log_error "配置迁移失败, 未找到配置文件: $config_file"
        return 1
    fi

    if grep -Eq "^[[:space:]]*${config_key}:" "$config_file"; then
        return 0
    fi

    printf '\n%s\n' "$config_entry" | sudo tee -a "$config_file" >/dev/null || {
        log_error "配置迁移失败, 无法追加 $config_key 到 $config_file"
        return 1
    }

    log_info "server 配置已补齐缺失键: $config_key"
}

# 旧版访问统计配置迁移所需的默认项.
# 新增迁移时, 请在对应检查和执行函数中使用独立的配置项数组.
SERVER_LEGACY_VISIT_STATS_APP_ENTRIES=(
    'trusted_proxies: ["178.18.16.0/24", "178.18.18.0/24", "127.0.0.1/8"]'
    'visit_cookie_max_age: 31536000'
    'cron_task_visit_stats: "0 7 * * * *"'
    'cron_task_post_visit_stats: "0 12 * * * *"'
)
SERVER_LEGACY_VISIT_STATS_REDIS_ENTRIES=(
    'visit_pv_expire: 172800'
    'visit_uv_expire: 604800'
    'post_visit_pv_expire: 172800'
    'ip_limit_visit_report: 3600'
    'ip_limit_expire_visit_report: 3600'
    'id_limit_visit_report: 600'
    'id_limit_expire_visit_report: 3600'
)

# 旧版配置迁移注册表, 三个数组下标必须一一对应.
SERVER_LEGACY_CONFIG_MIGRATION_NAMES=(
    "访问统计配置"
)
SERVER_LEGACY_CONFIG_MIGRATION_CHECKS=(
    "server_legacy_visit_stats_config_needs_migration"
)
SERVER_LEGACY_CONFIG_MIGRATION_EXECUTORS=(
    "server_migrate_legacy_visit_stats_config"
)

# server_config_entries_complete 判断配置文件是否已包含全部指定顶级键.
# 参数: $1: 配置文件路径. $2...: 包含顶级键的完整 YAML 配置行.
# 返回: 全部键存在时返回 0, 配置文件或任一键缺失时返回 1.
server_config_entries_complete() {
    local config_file="$1"
    local config_entry=""
    local config_key=""

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    shift
    for config_entry in "$@"; do
        config_key="${config_entry%%:*}"
        if ! grep -Eq "^[[:space:]]*${config_key}:" "$config_file"; then
            return 1
        fi
    done

    return 0
}

# server_legacy_visit_stats_config_needs_migration 判断旧版访问统计配置是否需要迁移.
# 参数: 无.
# 返回: 需要迁移时返回 0, 已迁移时返回 1.
server_legacy_visit_stats_config_needs_migration() {
    local config_dir="$DATA_VOLUME_DIR/blog-server/config"
    local app_config_file="$config_dir/app.yaml"
    local redis_config_file="$config_dir/redis.yaml"

    if ! server_config_entries_complete "$app_config_file" "${SERVER_LEGACY_VISIT_STATS_APP_ENTRIES[@]}"; then
        return 0
    fi

    if ! server_config_entries_complete "$redis_config_file" "${SERVER_LEGACY_VISIT_STATS_REDIS_ENTRIES[@]}"; then
        return 0
    fi

    return 1
}

# server_migrate_legacy_visit_stats_config 为旧版持久化配置补齐访问统计相关默认键.
# 参数: 无.
# 返回: 全部缺失键补齐成功时返回 0, 配置文件不存在或写入失败时返回非 0.
server_migrate_legacy_visit_stats_config() {
    local config_dir="$DATA_VOLUME_DIR/blog-server/config"
    local app_config_file="$config_dir/app.yaml"
    local redis_config_file="$config_dir/redis.yaml"
    local config_entry=""

    for config_entry in "${SERVER_LEGACY_VISIT_STATS_APP_ENTRIES[@]}"; do
        server_append_missing_config_entry \
            "$app_config_file" \
            "${config_entry%%:*}" \
            "$config_entry" || return 1
    done

    for config_entry in "${SERVER_LEGACY_VISIT_STATS_REDIS_ENTRIES[@]}"; do
        server_append_missing_config_entry \
            "$redis_config_file" \
            "${config_entry%%:*}" \
            "$config_entry" || return 1
    done
}

# server_run_legacy_config_migrations 按注册表执行仍需处理的旧版配置迁移.
# 参数: 无.
# 返回: 无需迁移或全部迁移成功时返回 0, 注册表异常或迁移失败时返回非 0.
server_run_legacy_config_migrations() {
    local migration_index=0
    local migration_status=0
    local migration_name=""
    local migration_check=""
    local migration_executor=""

    if [[ ${#SERVER_LEGACY_CONFIG_MIGRATION_NAMES[@]} -ne ${#SERVER_LEGACY_CONFIG_MIGRATION_CHECKS[@]} ]]; then
        log_error "server 旧版配置迁移注册表不完整"
        return 1
    fi

    if [[ ${#SERVER_LEGACY_CONFIG_MIGRATION_NAMES[@]} -ne ${#SERVER_LEGACY_CONFIG_MIGRATION_EXECUTORS[@]} ]]; then
        log_error "server 旧版配置迁移注册表不完整"
        return 1
    fi

    for ((migration_index = 0; migration_index < ${#SERVER_LEGACY_CONFIG_MIGRATION_NAMES[@]}; migration_index++)); do
        migration_name="${SERVER_LEGACY_CONFIG_MIGRATION_NAMES[$migration_index]}"
        migration_check="${SERVER_LEGACY_CONFIG_MIGRATION_CHECKS[$migration_index]}"
        migration_executor="${SERVER_LEGACY_CONFIG_MIGRATION_EXECUTORS[$migration_index]}"

        if "$migration_check"; then
            "$migration_executor" || return 1
            log_info "server 旧版配置迁移完成: $migration_name"
            continue

        else
            migration_status=$?
            if [[ "$migration_status" -ne 1 ]]; then
                log_error "server 旧版配置迁移检查失败: $migration_name"
                return "$migration_status"
            fi
        fi
    done

    return 0
}

# server_migrate_legacy_config 检查旧版持久化配置并执行已注册的迁移.
# 参数: 无.
# 返回: 无持久化配置或无需迁移时返回 0, 全部迁移成功时返回 0, 执行失败时返回非 0.
server_migrate_legacy_config() {
    local config_dir="$DATA_VOLUME_DIR/blog-server/config"

    if [[ ! -d "$config_dir" ]]; then
        log_debug "未发现旧版 server 配置目录, 跳过配置迁移: $config_dir"
        return 0
    fi

    if [[ ! -f "$config_dir/app.yaml" || ! -f "$config_dir/redis.yaml" ]]; then
        log_warn "server 配置目录不完整, 跳过旧版配置迁移: $config_dir"
        return 0
    fi

    server_run_legacy_config_migrations
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
    # shellcheck disable=SC2153
    server_set_project_name "$PROJECT_NAME"

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$SERVER_UID" "$SERVER_GID" 755 "$DATA_VOLUME_DIR/blog-server"

    log_info "server 复制配置文件到 volume success"
}
