#!/bin/bash
# FilePath    : blog-tool/utils/db.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 数据库工具

# 获取 docker compose 中指定镜像的版本号.
# 参数: $1: docker compose 文件路径.
# 参数: $2: 镜像名称, 如 postgres.
# 返回: 输出解析到的版本号; 未找到时输出空字符串.
get_docker_compose_image_version() {
    log_debug "run get_docker_compose_image_version"

    local docker_compose_file="$1"
    local image_name="$2"
    local image_version=""

    if [ -z "$docker_compose_file" ] || [ -z "$image_name" ]; then
        log_error "读取 docker compose 镜像版本失败, 参数不能为空"
        return 1
    fi

    if [ ! -f "$docker_compose_file" ]; then
        log_warn "docker compose 文件不存在, 跳过版本读取: $docker_compose_file"
        echo ""
        return 0
    fi

    image_version=$(awk -v image_name="$image_name" '
        {
            line = $0
            gsub(/\047/, "", line)

            if (line ~ /^[[:space:]]*image:[[:space:]]*/) {
                sub(/^[[:space:]]*image:[[:space:]]*/, "", line)
                if (index(line, image_name ":") == 1) {
                    sub("^" image_name ":", "", line)
                    print line
                    exit
                }
            }
        }
    ' "$docker_compose_file")

    echo "$image_version"
}

# 获取 docker compose 中指定镜像的运行版本, 未读取到时回退到默认版本.
# 参数: $1: docker compose 文件路径.
# 参数: $2: 镜像名称, 如 elasticsearch.
# 参数: $3: 默认版本号.
# 返回: 输出 compose 中的版本号; 若不存在则输出默认版本号.
get_docker_compose_image_version_or_default() {
    log_debug "run get_docker_compose_image_version_or_default"

    local docker_compose_file="$1"
    local image_name="$2"
    local default_version="$3"
    local image_version=""

    image_version=$(get_docker_compose_image_version "$docker_compose_file" "$image_name")

    if [ -n "$image_version" ]; then
        echo "$image_version"
        return 0
    fi

    echo "$default_version"
}

# 获取运行期 pgsql 容器名称.
# 参数: $1: docker compose 文件路径.
# 参数: $2: 容器名称后缀, 如 -billing-center; 默认空.
# 返回: 输出当前 compose 实际版本对应的 pgsql 容器名.
get_runtime_pgsql_container_name() {
    log_debug "run get_runtime_pgsql_container_name"

    local docker_compose_file="$1"
    local name_suffix="${2:-}"
    local runtime_pgsql_version=""

    runtime_pgsql_version=$(get_docker_compose_image_version_or_default "$docker_compose_file" "postgres" "$IMG_VERSION_PGSQL")
    echo "pgsql-$runtime_pgsql_version$name_suffix"
}

# 获取运行期 redis 容器名称.
# 参数: $1: docker compose 文件路径.
# 参数: $2: redis 端口.
# 返回: 输出当前 compose 实际版本对应的 redis 容器名.
get_runtime_redis_container_name() {
    log_debug "run get_runtime_redis_container_name"

    local docker_compose_file="$1"
    local redis_port="$2"
    local runtime_redis_version=""

    if [ -z "$docker_compose_file" ] || [ -z "$redis_port" ]; then
        log_error "获取运行期 redis 容器名称失败, 参数不能为空"
        return 1
    fi

    runtime_redis_version=$(get_docker_compose_image_version_or_default "$docker_compose_file" "redis" "$IMG_VERSION_REDIS")
    echo "redis-$runtime_redis_version-$redis_port"
}

# 获取运行期 es 容器名称.
# 参数: $1: docker compose 文件路径.
# 参数: $2: 节点编号后缀, 如 01; 默认 01.
# 返回: 输出当前 compose 实际版本对应的 es 容器名.
get_runtime_es_container_name() {
    log_debug "run get_runtime_es_container_name"

    local docker_compose_file="$1"
    local node_suffix="${2:-01}"
    local runtime_es_version=""

    if [ -z "$docker_compose_file" ]; then
        log_error "获取运行期 es 容器名称失败, 参数不能为空"
        return 1
    fi

    runtime_es_version=$(get_docker_compose_image_version_or_default "$docker_compose_file" "elasticsearch" "$IMG_VERSION_ES")
    echo "es-$runtime_es_version-$node_suffix"
}

# 替换 docker compose 中指定镜像的版本号.
# 参数: $1: docker compose 文件路径.
# 参数: $2: 镜像名称, 如 postgres.
# 参数: $3: 原版本号.
# 参数: $4: 目标版本号.
# 返回: 成功返回 0; 文件不存在或无需替换时返回 0; 失败返回非 0.
replace_docker_compose_image_version() {
    log_debug "run replace_docker_compose_image_version"

    local docker_compose_file="$1"
    local image_name="$2"
    local current_version="$3"
    local target_version="$4"
    local escaped_current_version=""
    local escaped_target_version=""

    if [ -z "$docker_compose_file" ] || [ -z "$image_name" ] || [ -z "$target_version" ]; then
        log_error "替换 docker compose 镜像版本失败, 参数不能为空"
        return 1
    fi

    if [ ! -f "$docker_compose_file" ]; then
        log_warn "docker compose 文件不存在, 跳过版本替换: $docker_compose_file"
        return 0
    fi

    if [ -n "$current_version" ] && [ "$current_version" == "$target_version" ]; then
        log_info "docker compose 版本未变化, 跳过替换: $target_version"
        return 0
    fi

    if ! grep -Fq "$current_version" "$docker_compose_file"; then
        log_warn "未在 docker compose 中找到需要替换的版本号: $current_version"
        return 0
    fi

    escaped_current_version=$(printf '%s\n' "$current_version" | sed 's/[][\\/.^$*+?{}|()]/\\&/g')
    escaped_target_version=$(printf '%s\n' "$target_version" | sed 's/[\\&]/\\&/g')

    if ! sed -i "s/${escaped_current_version}/${escaped_target_version}/g" "$docker_compose_file"; then
        log_error "替换 docker compose 版本失败: $current_version -> $target_version"
        return 1
    fi

    log_info "已更新 docker compose 文件中的全部版本号: $current_version -> $target_version"
}

# 对比脚本版本与 docker compose 版本, 并返回重启使用的版本来源.
# 参数: $1: 服务名称.
# 参数: $2: 当前脚本版本.
# 参数: $3: docker compose 中的版本.
# 返回: 输出 same, script 或 compose.
select_db_restart_version_source() {
    log_debug "run select_db_restart_version_source"

    local service_name="$1"
    local script_version="$2"
    local compose_version="$3"
    local compose_version_display="${compose_version:-未检测到}"
    local version_choice=""

    log_info "服务 $service_name 版本信息: 当前最新版本 $script_version, 历史 docker compose 版本 $compose_version_display"

    if [ -z "$compose_version" ]; then
        log_warn "服务 $service_name 未检测到历史 docker compose 版本, 将使用当前最新版本继续"
        echo "script"
        return 0
    fi

    if [ "$script_version" == "$compose_version" ]; then
        echo "same"
        return 0
    fi

    version_choice=$(read_user_input "\n检测到 $service_name 版本不一致:\n  1. 当前最新版本: $script_version\n  2. 历史 docker compose 版本: $compose_version\n请选择本次重启使用的版本, 默认使用 docker compose 版本 [1|2]: " "2")

    case "$version_choice" in
    1 | script | s)
        log_info "服务 $service_name 已选择当前最新版本: $script_version"
        echo "script"
        ;;
    2 | compose | c)
        log_info "服务 $service_name 已选择历史 docker compose 版本: $compose_version"
        echo "compose"
        ;;
    *)
        log_error "无效的版本选择: $version_choice, 仅支持输入 1 或 2"
        ;;
    esac
}

# 使用停止和启动函数完成一次数据库重启.
# 参数: $1: 停止函数名.
# 参数: $2: 启动函数名.
# 返回: 成功时完成 stop/start 流程.
restart_db_by_handlers() {
    log_debug "run restart_db_by_handlers"

    local stop_func="$1"
    local start_func="$2"

    if [ -z "$stop_func" ] || [ -z "$start_func" ]; then
        log_error "数据库重启失败, 停止函数和启动函数不能为空"
        return 1
    fi

    if ! declare -f "$stop_func" >/dev/null; then
        log_error "数据库重启失败, 未找到停止函数: $stop_func"
        return 1
    fi

    if ! declare -f "$start_func" >/dev/null; then
        log_error "数据库重启失败, 未找到启动函数: $start_func"
        return 1
    fi

    "$stop_func"
    "$start_func"
}

# 按版本选择策略重启数据库服务.
# 参数: $1: 服务名称.
# 参数: $2: docker compose 文件路径.
# 参数: $3: 镜像名称.
# 参数: $4: 当前脚本版本.
# 参数: $5: 按现有 compose 直接重启的函数名.
# 参数: $6: 版本替换函数名, 可为空; 为空时默认替换 compose 文件中的全部旧版本号.
# 参数: $7: 停止函数名.
# 参数: $8: 启动函数名.
# 返回: 成功时完成重启.
restart_db_with_version_choice() {
    log_debug "run restart_db_with_version_choice"

    local service_name="$1"
    local docker_compose_file="$2"
    local image_name="$3"
    local script_version="$4"
    local restart_compose_func="$5"
    local replace_compose_version_func="$6"
    local stop_func="$7"
    local start_func="$8"
    local compose_version=""
    local restart_source=""

    if [ -z "$service_name" ] || [ -z "$docker_compose_file" ] || [ -z "$image_name" ] || [ -z "$script_version" ] || [ -z "$restart_compose_func" ] || [ -z "$stop_func" ] || [ -z "$start_func" ]; then
        log_error "数据库版本重启失败, 参数不能为空"
        return 1
    fi

    if ! declare -f "$restart_compose_func" >/dev/null; then
        log_error "数据库版本重启失败, 未找到函数: $restart_compose_func"
        return 1
    fi

    compose_version=$(get_docker_compose_image_version "$docker_compose_file" "$image_name")
    restart_source=$(select_db_restart_version_source "$service_name" "$script_version" "$compose_version")

    if [ "$restart_source" == "same" ] || [ "$restart_source" == "compose" ]; then
        "$restart_compose_func"
        return 0
    fi

    if ! declare -f "$stop_func" >/dev/null; then
        log_error "数据库版本重启失败, 未找到停止函数: $stop_func"
        return 1
    fi

    if ! declare -f "$start_func" >/dev/null; then
        log_error "数据库版本重启失败, 未找到启动函数: $start_func"
        return 1
    fi

    "$stop_func"

    if [ -n "$compose_version" ] && [ "$compose_version" != "$script_version" ]; then
        if [ -n "$replace_compose_version_func" ]; then
            if ! declare -f "$replace_compose_version_func" >/dev/null; then
                log_error "数据库版本重启失败, 未找到函数: $replace_compose_version_func"
                return 1
            fi

            "$replace_compose_version_func" "$docker_compose_file" "$compose_version" "$script_version"
        else
            replace_docker_compose_image_version "$docker_compose_file" "$image_name" "$compose_version" "$script_version"
        fi
    fi

    "$start_func"
}

# 开发阶段重复创建数据库
reset_install_database() {
    log_debug "run reset_install_database"

    echo "y" | install_db_pgsql

    {
        echo "n"
        echo "y"
    } | install_db_redis

    {
        echo "y"
        echo "n"
    } | install_es_kibana
}

# 安装数据库
install_database() {
    log_debug "run install_database"

    local remove_data_pgsql is_redis_cluster remove_data_redis remove_data_es is_kibana
    # 提示用户输入

    # 根据运行模式决定是否询问
    if run_mode_is_dev; then
        remove_data_pgsql=$(read_user_input "[1/5]是否删除 pgsql 数据库信息 (默认n) [y|n]? " "n")
        is_redis_cluster=$(read_user_input "[2/5]是否创建 redis 集群 (默认n) [y|n]? " "n")
        remove_data_redis=$(read_user_input "[3/5]是否删除 redis 数据库信息 (默认n) [y|n]? " "n")
        remove_data_es=$(read_user_input "[4/5]是否删除 es 信息(默认n) [y|n]? " "n")
        is_kibana=$(read_user_input "[5/5]是否包含 kibana (默认n) [y|n]? " "n")
    fi

    if run_mode_is_pro; then
        # 判断是否已经有挂载的数据目录, 只要有一个存在就认为是已有数据
        local pgsql_data_dir="$DATA_VOLUME_DIR/pgsql"
        local redis_data_dir="$DATA_VOLUME_DIR/redis"
        local es_data_dir="$DATA_VOLUME_DIR/es"

        # 默认都有数据
        local has_data=true

        # 所有数据目录都不存在则认为没有数据
        if [ ! -d "$pgsql_data_dir" ] && [ ! -d "$redis_data_dir" ] && [ ! -d "$es_data_dir" ]; then
            has_data=false
        fi

        if [ "$has_data" = true ]; then
            log_warn "检测到已有数据库数据, 请谨慎操作!"
            remove_data_pgsql=$(read_user_input "[1/3]是否删除 pgsql 数据库信息 (默认n) [y|n]? " "n")
            is_redis_cluster="n"
            remove_data_redis=$(read_user_input "[2/3]是否删除 redis 数据库信息 (默认n) [y|n]? " "n")
            remove_data_es=$(read_user_input "[3/3]是否删除 es 信息(默认n) [y|n]? " "n")
            is_kibana="n"
        else
            log_info "未检测到已有数据库数据, 将进行全新安装."
            remove_data_pgsql="y"
            is_redis_cluster="n"
            remove_data_redis="y"
            remove_data_es="y"
            is_kibana="n"
        fi
    fi

    echo "$remove_data_pgsql" | install_db_pgsql

    {
        echo "$is_redis_cluster"
        echo "$remove_data_redis"
    } | install_db_redis

    {
        echo "$remove_data_es"
        echo "$is_kibana"
    } | install_es_kibana
}

# 删除数据库
delete_database() {
    log_debug "run delete_database"

    local is_delete # 是否删除历史数据 默认不删除
    is_delete=$(read_user_input "确认要删除吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        # 删除容器
        echo "$is_delete" | delete_db_pgsql
        echo "$is_delete" | delete_db_redis
        echo "$is_delete" | delete_es_kibana

        log_info "删除数据库成功"
    else
        log_info "未删除数据库"
    fi
}

# 安装数据库(billing center)
install_database_billing_center() {
    log_debug "run install_database_billing_center"
    local remove_data_pgsql is_redis_cluster remove_data_redis
    # 提示用户输入

    # 根据运行模式决定是否询问
    if run_mode_is_dev; then
        remove_data_pgsql=$(read_user_input "[1/3]是否删除 pgsql_billing_center 数据库信息 (默认n) [y|n]? " "n")
        is_redis_cluster=$(read_user_input "[2/3]是否创建 redis_billing_center 集群 (默认n) [y|n]? " "n")
        remove_data_redis=$(read_user_input "[3/3]是否删除 redis_billing_center 数据库信息 (默认n) [y|n]? " "n")
    fi

    if run_mode_is_pro; then
        # 判断是否已经有挂载的数据目录, 只要有一个存在就认为是已有数据
        local pgsql_data_dir="$DATA_VOLUME_DIR/pgsql_billing_center"
        local redis_data_dir="$DATA_VOLUME_DIR/redis_billing_center"

        # 默认都有数据
        local has_data=true

        # 所有数据目录都不存在则认为没有数据
        if [ ! -d "$pgsql_data_dir" ] && [ ! -d "$redis_data_dir" ]; then
            has_data=false
        fi

        if [ "$has_data" = true ]; then
            log_warn "检测到已有数据库数据, 请谨慎操作!"
            remove_data_pgsql=$(read_user_input "[1/2]是否删除 pgsql_billing_center 数据库信息 (默认n) [y|n]? " "n")
            is_redis_cluster="n"
            remove_data_redis=$(read_user_input "[2/2]是否删除 redis_billing_center 数据库信息 (默认n) [y|n]? " "n")
        else
            log_info "未检测到已有数据库数据, 将进行全新安装."
            remove_data_pgsql="y"
            is_redis_cluster="n"
            remove_data_redis="y"
        fi
    fi

    echo "$remove_data_pgsql" | install_db_pgsql_billing_center

    {
        echo "$is_redis_cluster"
        echo "$remove_data_redis"
    } | install_db_redis_billing_center
}

# 删除数据库(billing center)
delete_database_billing_center() {
    log_debug "run delete_database_billing_center"

    local is_delete # 是否删除历史数据 默认不删除
    is_delete=$(read_user_input "确认要删除计费中心数据库吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        # 删除容器
        echo "$is_delete" | delete_db_pgsql_billing_center
        echo "$is_delete" | delete_db_redis_billing_center

        log_info "删除计费中心数据库成功"
    else
        log_info "未删除计费中心数据库"
    fi
}

# 重启数据库, 重启前询问用户确认, 重启后同步重启 server 服务.
# 返回: 用户取消时直接返回; 成功时完成数据库及 server 重启.
restart_database() {
    log_debug "run restart_database"

    local confirm
    confirm=$(read_user_input "重启数据库将造成服务中断, 确认继续吗(默认n) [y|n]? " "n")
    if [[ "$confirm" != "y" ]]; then
        log_info "已取消重启数据库"
        return 0
    fi

    restart_db_pgsql
    restart_db_redis
    restart_db_es

    log_info "数据库重启完成, 开始重启 server 服务"
    docker_server_restart
}

# 重启数据库(billing center), 重启前询问用户确认, 重启后同步重启 billing center 服务.
# 返回: 用户取消时直接返回; 成功时完成数据库及 billing center 重启.
restart_database_billing_center() {
    log_debug "run restart_database_billing_center"

    local confirm
    confirm=$(read_user_input "重启数据库将造成服务中断, 确认继续吗(默认n) [y|n]? " "n")
    if [[ "$confirm" != "y" ]]; then
        log_info "已取消重启计费中心数据库"
        return 0
    fi

    restart_db_pgsql_billing_center
    restart_db_redis_billing_center

    log_info "计费中心数据库重启完成, 开始重启 billing center 服务"
    docker_billing_center_restart
}
