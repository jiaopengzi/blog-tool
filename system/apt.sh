#!/bin/bash
# FilePath    : blog-tool/system/apt.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : apt 相关工具

# 标记是否已经切换过 apt 软件源, 避免重复执行.
APT_SOURCE_SWITCHED="false"

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

# 仅在首次切换时备份 apt 源文件.
# 参数: $1: 要备份的文件路径.
# 返回: 始终返回 0.
backup_apt_source_file_once() {
    local file_path=$1
    local backup_path="${file_path}.blog-tool.bak"

    if [ -f "$file_path" ] && [ ! -f "$backup_path" ]; then
        run_with_sudo_if_available cp "$file_path" "$backup_path"
    fi
}

# 将 Debian 软件源切换为腾讯云镜像, 并保留官方安全更新.
# 返回: 0 表示写入成功, 1 表示系统代号未知.
switch_debian_apt_source_to_tencent() {
    detect_system
    if [ -z "$SYSTEM_CODENAME" ] || [ "$SYSTEM_CODENAME" = "unknown" ]; then
        log_warn "当前 Debian 系统代号未知, 跳过 apt 换源"
        return 1
    fi

    local legacy_source_file="/etc/apt/sources.list"
    local deb822_source_file="/etc/apt/sources.list.d/debian.sources"

    if [ -f "$deb822_source_file" ]; then
        backup_apt_source_file_once "$deb822_source_file"
        cat <<EOF | run_with_sudo_if_available tee "$deb822_source_file" >/dev/null
Types: deb
URIs: http://mirrors.tencent.com/debian/
Suites: $SYSTEM_CODENAME $SYSTEM_CODENAME-updates $SYSTEM_CODENAME-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: $SYSTEM_CODENAME-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
        return 0
    fi

    backup_apt_source_file_once "$legacy_source_file"
    cat <<EOF | run_with_sudo_if_available tee "$legacy_source_file" >/dev/null
# 默认注释了源码镜像以提高 apt update 速度, 如有需要可自行取消注释
# 安全更新默认使用官方源, 更新最及时

deb http://mirrors.tencent.com/debian/ $SYSTEM_CODENAME main contrib non-free non-free-firmware
# deb-src http://mirrors.tencent.com/debian/ $SYSTEM_CODENAME main contrib non-free non-free-firmware

deb http://mirrors.tencent.com/debian/ $SYSTEM_CODENAME-updates main contrib non-free non-free-firmware
# deb-src http://mirrors.tencent.com/debian/ $SYSTEM_CODENAME-updates main contrib non-free non-free-firmware

deb http://mirrors.tencent.com/debian/ $SYSTEM_CODENAME-backports main contrib non-free non-free-firmware
# deb-src http://mirrors.tencent.com/debian/ $SYSTEM_CODENAME-backports main contrib non-free non-free-firmware

deb https://security.debian.org/debian-security $SYSTEM_CODENAME-security main contrib non-free non-free-firmware
# deb-src https://security.debian.org/debian-security $SYSTEM_CODENAME-security main contrib non-free non-free-firmware
EOF
}

# 将 Ubuntu 软件源切换为腾讯云镜像, 并保留官方安全更新.
# 返回: 0 表示写入成功, 1 表示系统代号未知.
switch_ubuntu_apt_source_to_tencent() {
    detect_system
    if [ -z "$SYSTEM_CODENAME" ] || [ "$SYSTEM_CODENAME" = "unknown" ]; then
        log_warn "当前 Ubuntu 系统代号未知, 跳过 apt 换源"
        return 1
    fi

    local deb822_source_file="/etc/apt/sources.list.d/ubuntu.sources"
    local legacy_source_file="/etc/apt/sources.list"

    if [ -f "$deb822_source_file" ]; then
        backup_apt_source_file_once "$deb822_source_file"
        cat <<EOF | run_with_sudo_if_available tee "$deb822_source_file" >/dev/null
Types: deb
URIs: http://mirrors.tencentyun.com/ubuntu/
Suites: $SYSTEM_CODENAME $SYSTEM_CODENAME-updates $SYSTEM_CODENAME-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: $SYSTEM_CODENAME-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        return 0
    fi

    backup_apt_source_file_once "$legacy_source_file"
    cat <<EOF | run_with_sudo_if_available tee "$legacy_source_file" >/dev/null
deb http://mirrors.tencentyun.com/ubuntu/ $SYSTEM_CODENAME main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ $SYSTEM_CODENAME-updates main restricted universe multiverse
deb http://mirrors.tencentyun.com/ubuntu/ $SYSTEM_CODENAME-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ $SYSTEM_CODENAME-security main restricted universe multiverse
EOF
}

# 在中国大陆非腾讯云环境下切换 apt 软件源到腾讯云镜像.
# 返回: 0 表示无需切换或切换成功, 非 0 表示切换失败.
switch_cn_non_tencent_apt_source() {
    log_debug "run switch_cn_non_tencent_apt_source"

    if [ "$APT_SOURCE_SWITCHED" = "true" ]; then
        return 0
    fi

    local region
    region=$(detect_docker_region)
    if [ "$region" != "cn_non_tencent" ]; then
        return 0
    fi

    detect_system || {
        log_warn "未识别到 Debian 或 Ubuntu 系统, 跳过 apt 换源"
        return 0
    }

    case "$SYSTEM_FAMILY" in
    debian)
        switch_debian_apt_source_to_tencent || return 1
        ;;
    ubuntu)
        switch_ubuntu_apt_source_to_tencent || return 1
        ;;
    *)
        return 0
        ;;
    esac

    APT_SOURCE_SWITCHED="true"
    log_info "检测到中国大陆非腾讯云环境, 已切换 apt 软件源到腾讯云镜像"
    apt_update
}

# 执行 apt update
apt_update() {
    log_debug "run apt_update"

    apt_get_noninteractive update
}

# 执行安装并设置同意
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
