#!/bin/bash
# FilePath    : blog-tool/utils/server_client.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : server 和 client 的工具函数

# 删除 server client 镜像
docker_rmi_server_client() {
    log_debug "run docker_rmi_server_client"
    docker_rmi_server
    docker_rmi_client
    docker_clear_cache
}

# 创建 sever 和 client 的 volume
mkdir_server_client_volume() {
    log_debug "run mkdir_server_client_volume"
    mkdir_server_volume
    mkdir_client_volume
}

# 删除 sever 和 client 的 volume
remove_server_client_volume() {
    log_debug "run remove_server_client_volume"
    remove_server_volume
    remove_client_volume
}

# 拉取 server client 镜像
docker_pull_server_client() {
    log_debug "run docker_pull_server_client"
    docker_pull_server
    docker_pull_client
}

# 构建 server client 推送镜像及启动服务
docker_build_push_start_server_client() {
    log_debug "run docker_build_push_start_server_client"
    docker_build_push_server_client
    docker_server_client_install
}

# 构建 server client 推送镜像
docker_build_push_server_client() {
    log_debug "run docker_build_push_server_client"

    # shellcheck disable=SC2329
    run() {
        docker_build_push_server
        docker_build_push_client
    }
    log_timer "server client 镜像构建及推送" run
}

# 安装 server client 服务
docker_server_client_install() {
    log_debug "run docker_server_client_install"
    local is_install
    is_install=$(read_user_input "$WEB_INSTALL_SERVER_TIPS" "n")

    # 是否全新安装 server
    if [ "$is_install" == "y" ]; then
        local web_set_db
        web_set_db=$(read_user_input "$WEB_SET_DB_TIPS" "n")
        log_debug "web_set_db=$web_set_db"

        # 传递参数给 docker_server_install
        {
            echo "$is_install"
            echo "$web_set_db"
        } | docker_server_install

        docker_client_install
    else
        log_info "退出全新安装"
    fi
}

# 启动 server client 服务
docker_server_client_start() {
    log_debug "run docker_server_client_start"
    docker_server_start
    docker_client_start
}

# 停止 server client 服务
docker_server_client_stop() {
    log_debug "run docker_server_client_stop"
    docker_server_stop
    docker_client_stop
}

# 重启 server client 服务
docker_server_client_restart() {
    log_debug "run docker_server_client_restart"
    docker_server_restart
    docker_client_restart
}

# 删除 server client 服务及数据
docker_server_client_delete() {
    log_debug "run docker_server_client_delete"
    docker_server_delete
    docker_client_delete
}

# 停止所有服务
docker_all_stop() {
    log_debug "run docker_all_stop"
    docker_client_stop
    docker_server_stop
    stop_db_es
    stop_db_redis
    stop_db_pgsql
}

# 重启所有服务
docker_all_restart() {
    log_debug "run docker_all_restart"
    restart_db_pgsql
    restart_db_redis
    restart_db_es
    docker_server_restart
    docker_client_restart
}

# 获取项目文件的 raw 文件 URL
get_raw() {
    log_debug "run get_raw"
    # 参数:
    # $1: project 项目名称
    # $2: file 文件名称
    # $3: platform 平台: github | gitee, 可选参数, 默认 github
    local project="$1"
    local file="$2"
    local platform="${3:-github}"

    # 根据平台生成 raw 文件 URL
    local raw_url
    if [ "$platform" = "github" ]; then
        raw_url="https://raw.githubusercontent.com/jiaopengzi/$project/refs/heads/main/$file"
    elif [ "$platform" = "gitee" ]; then
        raw_url="https://gitee.com/jiaopengzi/$project/raw/main/$file"
    fi

    echo "$raw_url"
}

# 获取指定服务的版本列表
get_service_versions() {
    log_debug "run get_service_versions"
    # 参数:
    # $1: service_name 服务名称
    local service_name="${1-blog-client}"

    # 脚本下载地址根据网络环境选择
    local raw_url

    # 检测网络环境开启动画
    start_spinner

    if [[ $(curl -s ipinfo.io/country) == "CN" ]]; then
        log_debug "检测到国内网络环境, 使用 gitee 获取 $service_name 版本"
        raw_url=$(get_raw "$service_name" "CHANGELOG.md" "gitee")
    else
        log_debug "检测到非国内网络环境, 使用 github 获取 $service_name 版本"
        raw_url=$(get_raw "$service_name" "CHANGELOG.md" "github")
    fi

    # 将 changelog 文件下载到本地临时文件
    local changelog_temp_file
    changelog_temp_file=$(mktemp)
    curl -sSL "$raw_url" -o "$changelog_temp_file"

    # 上述网络操作完成停止动画
    stop_spinner

    extract_changelog_version_date "$changelog_temp_file"
}

# 展示指定服务的版本列表
show_service_versions() {
    log_debug "run show_service_versions"
    # 参数:
    # $1: service_name 服务名称
    local service_name="${1-blog-client}"

    # 获取版本列表
    local versions
    versions=$(get_service_versions "$service_name")

    # 使用 semver_to_docker_tag 将版本号转换为 Docker 标签格式
    local formatted_versions=""
    local has_versions=false
    while IFS= read -r line; do
        local date_part version_part formatted_version
        version_part=$(echo "$line" | awk '{print $1}')
        date_part=$(echo "$line" | awk '{print $2}')

        formatted_version="$date_part\t$(semver_to_docker_tag "$version_part")"

        # 根据 version_part 按照语义化版本规范过滤生产环境版本, 即只显示 x.y.z 格式的版本
        if run_mode_is_pro; then
            # 判断版本是否为生产环境版本
            if (version_is_pro "$version_part"); then
                formatted_versions+="$formatted_version\n"
                has_versions=true
            fi
        else
            formatted_versions+="$formatted_version\n"
            has_versions=true
        fi

    done <<<"$versions"

    # 如果没有可用版本则提示并退出
    if [ "$has_versions" = false ]; then
        log_warn "服务 $service_name 暂无可用版本列表"
        exit 0
    fi

    # 将显示的版本信息进行美化中间间隔增加制表符,增加表头
    formatted_versions=$(echo -e "发布日期\t版本号\n$formatted_versions" | column -t)

    log_info "\n\n服务 $service_name 可用版本列表如下:\n\n$formatted_versions\n"
}

# 展示 server 版本列表
show_server_versions() {
    log_debug "run show_server_versions"
    show_service_versions "blog-server"
}

# 展示 client 版本列表
show_client_versions() {
    log_debug "run show_client_versions"
    show_service_versions "blog-client"
}

# 检查指定服务的版本是否存在
check_service_version() {
    log_debug "run check_service_version"
    # 参数:
    # $1: service_name 服务名称
    # $2: version 版本号
    local service_name="${1-blog-server}"
    local version="$2"

    # 获取所有版本列表
    local versions
    versions=$(get_service_versions "$service_name")

    # 检查指定版本是否存在
    local version_exists=false

    # 遍历版本列表进行检查
    while IFS= read -r line; do
        # 提取版本号部分
        local v
        v=$(echo "$line" | awk '{print $1}')

        # 使用 semver_to_docker_tag 将版本号转换为 Docker 标签格式
        local formatted_v
        formatted_v=$(semver_to_docker_tag "$v")

        # 比较转换后的版本号与指定版本号
        if [[ "$formatted_v" == "$version" ]]; then
            version_exists=true
            break
        fi
    done <<<"$versions"

    # 如果版本不存在则报错退出
    if [ "$version_exists" = false ]; then
        log_error "服务 $service_name 未找到版本 $version, 请检查后重试"
        exit 1
    fi

    # 根据 version_part 按照语义化版本规范过滤生产环境版本, 即只允许 x.y.z 格式的版本
    if run_mode_is_pro && (version_is_dev "$version"); then
        log_error "当前运行模式为生产环境, 版本 $version 不符合生产环境版本规范, 请检查后重试"
        exit 1
    fi

    # 版本存在则继续启动或回滚服务
    log_info "服务 $service_name 找到版本 $version"
}

# 根据版本启动或回滚 server 服务
start_or_rollback_server_by_version() {
    log_debug "run start_or_rollback_server_by_version"

    # 读取用户输入的版本号
    read -r -p "请输入 server 需要升级或回滚的版本号: " version

    # 如果用户没有输入, 使用默认值
    if [ -z "$version" ]; then
        log_error "版本号不能为空, 请重新运行脚本并输入正确的版本号"
    fi

    # 检查版本是否存在
    check_service_version "blog-server" "$version"

    # 拉取镜像
    docker_pull_server "$version"

    # 停止容器
    docker_server_stop

    # 按照指定版本创建 docker compose 文件
    create_docker_compose_server "$version"

    # 不删除数据卷重启服务
    docker_server_restart

    log_info "服务 blog-server 已成功升级或回滚到版本 $version"
}

# 根据版本启动或回滚 client 服务
start_or_rollback_client_by_version() {
    log_debug "run start_or_rollback_client_by_version"

    # 读取用户输入的版本号
    read -r -p "请输入 client 需要升级或回滚的版本号: " version

    # 如果用户没有输入, 使用默认值
    if [ -z "$version" ]; then
        log_error "版本号不能为空, 请重新运行脚本并输入正确的版本号"
    fi

    # 检查版本是否存在
    check_service_version "blog-client" "$version"

    # 拉取镜像
    docker_pull_client "$version"

    # 停止容器
    docker_client_stop

    # 按照指定版本创建 docker compose 文件
    create_docker_compose_client "$version"

    # 不删除数据卷重启服务
    docker_client_restart

    log_info "服务 blog-client 已成功升级或回滚到版本 $version"
}
