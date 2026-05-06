#!/bin/bash
# FilePath    : blog-tool/system/apt.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : apt 相关工具

# 在存在 sudo 时使用 sudo 执行命令, 否则直接执行.
# 参数: $@: 要执行的命令与参数.
# 返回: 透传原命令退出码.
run_with_sudo_if_available() {
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

# 使用非交互模式执行 apt-get, 避免 conffile 与 needrestart 阻塞安装流程.
# 参数: $1: apt-get 子命令; $@: 其余参数.
# 返回: 透传 apt-get 的退出码.
apt_get_noninteractive() {
    local sub_command=$1
    shift

    local -a apt_cmd=(
        env
        DEBIAN_FRONTEND=noninteractive
        DEBIAN_PRIORITY=critical
        NEEDRESTART_MODE=a
        APT_LISTCHANGES_FRONTEND=none
        UCF_FORCE_CONFDEF=1
        UCF_FORCE_CONFFOLD=1
        apt-get
        -o Dpkg::Options::=--force-confdef
        -o Dpkg::Options::=--force-confold
        "$sub_command"
    )

    run_with_sudo_if_available "${apt_cmd[@]}" "$@"
}

# 执行 apt update.
# 返回: 透传 apt-get update 退出码.
apt_update() {
    log_debug "run apt_update"

    apt_get_noninteractive update
}

# 执行安装并自动接受默认配置.
# 参数: $@: 要安装的软件包列表.
# 返回: 透传 apt-get install 退出码.
apt_install_y() {
    log_debug "run apt_install_y"

    apt_get_noninteractive install -y "$@"
}

# 添加 backports 源
add_backports_apt_source() {
    log_debug "run add_backports_apt_source"

    local sources_list="/etc/apt/sources.list"

    # 文件存在就删除原来的配置
    if [ -f "$sources_list" ]; then
        sudo sed -i '/# Backports 仓库开始/,/# Backports 仓库结束/d' "$sources_list"
    fi

    #    # 添加 backports 仓库
    #    {
    #        echo "# Backports 仓库开始"
    #        get_backports_source
    #        echo "# Backports 仓库结束"
    #    } | sudo tee -a "$sources_list"

    apt_update
}

# 删除 backports 源
del_backports_apt_source() {
    log_debug "run del_backports_apt_source"

    local sources_list="/etc/apt/sources.list"
    # 文件存在就删除原来的配置
    if [ -f "$sources_list" ]; then
        sudo sed -i '/# Backports 仓库开始/,/# Backports 仓库结束/d' "$sources_list"
    fi

    apt_update
}

# 安装所有更新
install_all_update() {
    log_debug "run install_all_update"

    # 更新
    apt_update

    # 安装工具
    install_common_software
    # 安装docker
    install_docker

    log_info "所有更新完成"
}
