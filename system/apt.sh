#!/bin/bash
# FilePath    : blog-tool/system/apt.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : apt 相关工具

# 标记当前进程是否已临时切换 apt 软件源.
APT_SOURCE_SWITCHED="false"

# 记录本轮临时切换时创建的新源文件, 便于恢复时删除.
APT_SOURCE_CREATED_FILES=()

# 记录本轮安装阶段选中的临时 apt 镜像源, 便于日志定位.
APT_SELECTED_MIRROR=""

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

# 执行严格模式的 apt update.
# 返回: 任一软件源索引刷新失败时返回非 0.
apt_update() {
    log_debug "run apt_update"

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
        -o APT::Update::Error-Mode=any
        update
    )

    run_with_sudo_if_available "${apt_cmd[@]}"
}

# 执行安装并自动接受默认配置.
# 参数: $@: 要安装的软件包列表.
# 返回: 透传 apt-get install 退出码.
apt_install_y() {
    log_debug "run apt_install_y"

    apt_get_noninteractive install -y "$@"
}

# 使用当前可用的 HTTP 探测工具检查目标 URL 是否可访问.
# 参数: $1: 要探测的 URL.
# 返回: 0 表示可访问, 1 表示不可访问或当前缺少探测工具.
apt_probe_url() {
    local target_url=$1

    if [ -z "$target_url" ]; then
        return 1
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -fsL --connect-timeout 5 --max-time 10 -o /dev/null "$target_url"
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q --spider -T 10 "$target_url"
        return $?
    fi

    log_debug "当前未安装 curl 或 wget, 无法预探测 apt 镜像可用性"
    return 1
}

# 探测当前系统下某个 apt 镜像是否覆盖主仓库、updates 与 backports.
# 参数: $1: 镜像基础 URL.
# 返回: 0 表示当前系统关键 suites 均可访问, 1 表示至少一个 suite 不可访问.
apt_probe_mirror_for_current_system() {
    local base_url=$1
    local suite_name=""
    local probe_url=""
    local -a suites_to_probe=()

    detect_system
    if [ -z "$SYSTEM_CODENAME" ] || [ "$SYSTEM_CODENAME" = "unknown" ]; then
        return 1
    fi

    suites_to_probe=(
        "$SYSTEM_CODENAME"
        "$SYSTEM_CODENAME-updates"
        "$SYSTEM_CODENAME-backports"
    )

    for suite_name in "${suites_to_probe[@]}"; do
        probe_url="${base_url%/}/dists/${suite_name}/InRelease"
        if ! apt_probe_url "$probe_url"; then
            log_debug "apt 镜像预探测失败: $probe_url"
            return 1
        fi
    done

    return 0
}

# 选择当前系统可用的 Debian 临时 apt 镜像源.
# 返回: 输出首个可用镜像基础 URL; 若均不可用则输出空字符串.
select_debian_apt_mirror() {
    local mirror_url=""
    local -a mirror_candidates=(
        "http://mirrors.tencent.com/debian/"
        "https://mirrors.tuna.tsinghua.edu.cn/debian/"
        "https://mirrors.aliyun.com/debian/"
    )

    for mirror_url in "${mirror_candidates[@]}"; do
        if apt_probe_mirror_for_current_system "$mirror_url"; then
            echo "$mirror_url"
            return 0
        fi
    done

    echo ""
}

# 选择当前系统可用的 Ubuntu 临时 apt 镜像源.
# 返回: 输出首个可用镜像基础 URL; 若均不可用则输出空字符串.
select_ubuntu_apt_mirror() {
    local mirror_url=""
    local -a mirror_candidates=(
        "http://mirrors.tencent.com/ubuntu/"
        "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
        "https://mirrors.aliyun.com/ubuntu/"
    )

    for mirror_url in "${mirror_candidates[@]}"; do
        if apt_probe_mirror_for_current_system "$mirror_url"; then
            echo "$mirror_url"
            return 0
        fi
    done

    echo ""
}

# 记录当前临时切换时新创建的 apt 源文件.
# 参数: $1: 文件路径.
# 返回: 始终返回 0.
mark_apt_source_created_file() {
    local file_path=$1

    if [ -z "$file_path" ]; then
        return 0
    fi

    APT_SOURCE_CREATED_FILES+=("$file_path")
}

# 仅在首次切换时备份 apt 源文件.
# 参数: $1: 要备份的文件路径.
# 返回: 始终返回 0.
backup_apt_source_file_once() {
    local file_path=$1
    local backup_path="${file_path}.blog-tool.bak"

    if [ -f "$file_path" ]; then
        if [ ! -f "$backup_path" ]; then
            run_with_sudo_if_available cp "$file_path" "$backup_path"
        fi
        return 0
    fi

    mark_apt_source_created_file "$file_path"
}

# 判断文件是否为当前进程临时创建的 apt 源文件.
# 参数: $1: 文件路径.
# 返回: 0 表示是, 1 表示否.
apt_source_file_was_created() {
    local file_path=$1
    local created_file

    for created_file in "${APT_SOURCE_CREATED_FILES[@]}"; do
        if [ "$created_file" = "$file_path" ]; then
            return 0
        fi
    done

    return 1
}

# 将 Debian 软件源临时切换为指定镜像, 并保留官方安全更新.
# 参数: $1: 镜像基础 URL.
# 返回: 0 表示写入成功, 1 表示系统代号未知、镜像为空或写入失败.
switch_debian_apt_source_to_mirror() {
    local mirror_url=$1

    detect_system
    if [ -z "$SYSTEM_CODENAME" ] || [ "$SYSTEM_CODENAME" = "unknown" ]; then
        log_warn "当前 Debian 系统代号未知, 跳过 apt 换源"
        return 1
    fi

    if [ -z "$mirror_url" ]; then
        log_warn "当前 Debian 未命中可用的 apt 镜像, 跳过 apt 换源"
        return 1
    fi

    local legacy_source_file="/etc/apt/sources.list"
    local deb822_source_file="/etc/apt/sources.list.d/debian.sources"

    if [ -f "$deb822_source_file" ]; then
        backup_apt_source_file_once "$deb822_source_file"
        cat <<EOF | run_with_sudo_if_available tee "$deb822_source_file" >/dev/null
Types: deb
URIs: $mirror_url
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

deb ${mirror_url%/}/ $SYSTEM_CODENAME main contrib non-free non-free-firmware
# deb-src ${mirror_url%/}/ $SYSTEM_CODENAME main contrib non-free non-free-firmware

deb ${mirror_url%/}/ $SYSTEM_CODENAME-updates main contrib non-free non-free-firmware
# deb-src ${mirror_url%/}/ $SYSTEM_CODENAME-updates main contrib non-free non-free-firmware

deb ${mirror_url%/}/ $SYSTEM_CODENAME-backports main contrib non-free non-free-firmware
# deb-src ${mirror_url%/}/ $SYSTEM_CODENAME-backports main contrib non-free non-free-firmware

deb https://security.debian.org/debian-security $SYSTEM_CODENAME-security main contrib non-free non-free-firmware
# deb-src https://security.debian.org/debian-security $SYSTEM_CODENAME-security main contrib non-free non-free-firmware
EOF
}

# 将 Ubuntu 软件源临时切换为指定镜像, 并保留官方安全更新.
# 参数: $1: 镜像基础 URL.
# 返回: 0 表示写入成功, 1 表示系统代号未知、镜像为空或写入失败.
switch_ubuntu_apt_source_to_mirror() {
    local mirror_url=$1

    detect_system
    if [ -z "$SYSTEM_CODENAME" ] || [ "$SYSTEM_CODENAME" = "unknown" ]; then
        log_warn "当前 Ubuntu 系统代号未知, 跳过 apt 换源"
        return 1
    fi

    if [ -z "$mirror_url" ]; then
        log_warn "当前 Ubuntu 未命中可用的 apt 镜像, 跳过 apt 换源"
        return 1
    fi

    local deb822_source_file="/etc/apt/sources.list.d/ubuntu.sources"
    local legacy_source_file="/etc/apt/sources.list"

    if [ -f "$deb822_source_file" ]; then
        backup_apt_source_file_once "$deb822_source_file"
        cat <<EOF | run_with_sudo_if_available tee "$deb822_source_file" >/dev/null
Types: deb
URIs: $mirror_url
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
deb ${mirror_url%/}/ $SYSTEM_CODENAME main restricted universe multiverse
deb ${mirror_url%/}/ $SYSTEM_CODENAME-updates main restricted universe multiverse
deb ${mirror_url%/}/ $SYSTEM_CODENAME-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ $SYSTEM_CODENAME-security main restricted universe multiverse
EOF
}

# 校验临时切换后的 apt 软件源是否可用, 不可用时立即恢复原源兜底.
# 返回: 0 表示当前可继续使用临时源或已成功回退到原源, 1 表示恢复失败.
validate_temporary_apt_source_or_fallback() {
    log_debug "run validate_temporary_apt_source_or_fallback"

    if [ "$APT_SOURCE_SWITCHED" != "true" ]; then
        return 0
    fi

    if apt_update; then
        log_info "临时切换的 apt 软件源校验通过"
        return 0
    fi

    log_warn "临时切换的 apt 软件源不可用, 立即回退到原始软件源"

    if ! restore_temporary_apt_source "true"; then
        log_error "临时 apt 软件源不可用且恢复原始软件源失败"
        return 1
    fi

    log_info "已回退到原始软件源, 将继续使用官方源安装基础软件"
    return 0
}

# 在基础软件安装前, 仅对中国大陆非腾讯云环境临时切换 apt 软件源.
# 返回: 0 表示无需切换或切换成功, 1 表示切换失败.
prepare_temporary_apt_source_for_install() {
    log_debug "run prepare_temporary_apt_source_for_install"

    if [ "$APT_SOURCE_SWITCHED" = "true" ]; then
        return 0
    fi

    local region
    region=$(detect_docker_region)
    if [ "$region" != "cn_non_tencent" ]; then
        return 0
    fi

    detect_system || {
        log_warn "未识别到 Debian 或 Ubuntu 系统, 跳过 apt 临时换源"
        return 0
    }

    local selected_mirror=""

    case "$SYSTEM_FAMILY" in
    debian)
        selected_mirror=$(select_debian_apt_mirror)
        if [ -z "$selected_mirror" ]; then
            log_warn "未找到可用的 Debian 临时 apt 镜像, 将继续使用官方源"
            return 0
        fi
        switch_debian_apt_source_to_mirror "$selected_mirror" || return 1
        ;;
    ubuntu)
        selected_mirror=$(select_ubuntu_apt_mirror)
        if [ -z "$selected_mirror" ]; then
            log_warn "未找到可用的 Ubuntu 临时 apt 镜像, 将继续使用官方源"
            return 0
        fi
        switch_ubuntu_apt_source_to_mirror "$selected_mirror" || return 1
        ;;
    *)
        return 0
        ;;
    esac

    APT_SOURCE_SWITCHED="true"
    APT_SELECTED_MIRROR="$selected_mirror"
    log_info "检测到中国大陆非腾讯云环境, 安装基础软件前已临时切换 apt 软件源到: $APT_SELECTED_MIRROR"

    validate_temporary_apt_source_or_fallback
}

# 恢复本轮临时切换前的 apt 软件源.
# 参数: $1: 是否在恢复后立即执行 apt update, 可选值 true / false, 默认 false.
# 返回: 0 表示无需恢复或恢复成功, 1 表示恢复失败.
restore_temporary_apt_source() {
    log_debug "run restore_temporary_apt_source"
    local should_update_after_restore="${1:-false}"

    if [ "$APT_SOURCE_SWITCHED" != "true" ]; then
        return 0
    fi

    local file_path
    local backup_path
    local restored_any="false"
    local restore_failed="false"
    local -a restore_targets=(
        "/etc/apt/sources.list"
        "/etc/apt/sources.list.d/debian.sources"
        "/etc/apt/sources.list.d/ubuntu.sources"
    )

    for file_path in "${restore_targets[@]}"; do
        backup_path="${file_path}.blog-tool.bak"

        if [ -f "$backup_path" ]; then
            if ! run_with_sudo_if_available mv -f "$backup_path" "$file_path"; then
                restore_failed="true"
            else
                restored_any="true"
            fi
            continue
        fi

        if apt_source_file_was_created "$file_path"; then
            if ! run_with_sudo_if_available rm -f "$file_path"; then
                restore_failed="true"
            else
                restored_any="true"
            fi
        fi
    done

    APT_SOURCE_SWITCHED="false"
    APT_SOURCE_CREATED_FILES=()
    APT_SELECTED_MIRROR=""

    if [ "$restore_failed" = "true" ]; then
        log_error "恢复临时切换前的 apt 软件源失败, 请手动检查"
        return 1
    fi

    if [ "$restored_any" = "true" ]; then
        log_info "已恢复临时切换前的 apt 软件源"
        if [ "$should_update_after_restore" = "true" ]; then
            if ! apt_update; then
                log_error "恢复 apt 软件源后执行 apt-get update 失败"
                return 1
            fi
        fi
    fi

    return 0
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
