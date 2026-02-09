#!/bin/bash
# FilePath    : blog-tool/utils/db.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 数据库工具

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
