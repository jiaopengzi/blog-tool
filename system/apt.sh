#!/bin/bash
# FilePath    : blog-tool/system/apt.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : apt 相关工具

# 标记是否已经切换过 apt 软件源, 避免重复执行.
APT_SOURCE_SWITCHED="false"
APT_SOURCE_TEMP_ACTIVE="false"
APT_SOURCE_SCOPE_DEPTH=0
APT_SOURCE_PREVIOUS_EXIT_TRAP=""
APT_SOURCE_TRACKED_FILES=""

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
    local absent_marker="${file_path}.blog-tool.absent"

    case ",${APT_SOURCE_TRACKED_FILES}," in
    *",${file_path},"*)
        ;;
    *)
        if [ -z "$APT_SOURCE_TRACKED_FILES" ]; then
            APT_SOURCE_TRACKED_FILES="$file_path"
        else
            APT_SOURCE_TRACKED_FILES="${APT_SOURCE_TRACKED_FILES},${file_path}"
        fi
        ;;
    esac

    if [ -e "$file_path" ] && [ ! -f "$backup_path" ]; then
        run_with_sudo_if_available cp "$file_path" "$backup_path"
        run_with_sudo_if_available rm -f "$absent_marker"
        return 0
    fi

    if [ ! -e "$file_path" ] && [ ! -f "$backup_path" ] && [ ! -f "$absent_marker" ]; then
        run_with_sudo_if_available touch "$absent_marker"
    fi
}

# 恢复当前流程中备份过的 apt 源文件, 并清理备份标记.
# 返回: 始终返回 0.
restore_apt_source_backups() {
    local tracked_file=""
    local backup_path=""
    local absent_marker=""

    if [ -z "$APT_SOURCE_TRACKED_FILES" ]; then
        return 0
    fi

    IFS=',' read -r -a tracked_files <<<"$APT_SOURCE_TRACKED_FILES"
    for tracked_file in "${tracked_files[@]}"; do
        [ -n "$tracked_file" ] || continue
        backup_path="${tracked_file}.blog-tool.bak"
        absent_marker="${tracked_file}.blog-tool.absent"

        if [ -f "$backup_path" ]; then
            run_with_sudo_if_available cp "$backup_path" "$tracked_file"
            run_with_sudo_if_available rm -f "$backup_path" "$absent_marker"
            continue
        fi

        if [ -f "$absent_marker" ]; then
            run_with_sudo_if_available rm -f "$tracked_file" "$absent_marker"
        fi
    done

    APT_SOURCE_TRACKED_FILES=""
}

# 处理临时换源的 EXIT 兜底恢复, 防止流程异常退出后遗留镜像源修改.
# 返回: 始终返回 0.
apt_source_exit_trap_handler() {
    restore_temporary_cn_non_tencent_apt_source true || true

    if [ -n "$APT_SOURCE_PREVIOUS_EXIT_TRAP" ]; then
        eval "$APT_SOURCE_PREVIOUS_EXIT_TRAP"
    fi
}

# 注册临时换源的 EXIT 恢复钩子.
# 返回: 始终返回 0.
register_apt_source_exit_trap() {
    local current_exit_trap=""

    current_exit_trap=$(trap -p EXIT | sed -n "s/^trap -- '\(.*\)' EXIT$/\1/p")
    if [ "$current_exit_trap" = "apt_source_exit_trap_handler" ]; then
        return 0
    fi

    APT_SOURCE_PREVIOUS_EXIT_TRAP="$current_exit_trap"
    trap 'apt_source_exit_trap_handler' EXIT
}

# 恢复临时换源前的 EXIT 钩子.
# 返回: 始终返回 0.
unregister_apt_source_exit_trap() {
    if [ -n "$APT_SOURCE_PREVIOUS_EXIT_TRAP" ]; then
        eval "trap -- $(printf '%q' "$APT_SOURCE_PREVIOUS_EXIT_TRAP") EXIT"
    else
        trap - EXIT
    fi

    APT_SOURCE_PREVIOUS_EXIT_TRAP=""
}

# 判断主机名当前是否可解析, 用于避免将不可用镜像写入 apt 源.
# 参数: $1: 主机名.
# 返回: 0 表示可解析, 1 表示不可解析.
apt_host_is_resolvable() {
    local host_name=$1

    if command -v getent >/dev/null 2>&1; then
        getent hosts "$host_name" >/dev/null 2>&1
        return $?
    fi

    if command -v host >/dev/null 2>&1; then
        host "$host_name" >/dev/null 2>&1
        return $?
    fi

    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$host_name" >/dev/null 2>&1
        return $?
    fi

    return 0
}

# 获取当前系统架构对应的 Ubuntu 仓库路径.
# 返回: x86 返回 ubuntu, 其他架构返回 ubuntu-ports.
get_ubuntu_repo_path_for_arch() {
    local current_arch=""

    if command -v dpkg >/dev/null 2>&1; then
        current_arch=$(dpkg --print-architecture 2>/dev/null)
    fi

    if [ -z "$current_arch" ]; then
        case "$(uname -m)" in
        x86_64 | amd64 | i386 | i686)
            current_arch="amd64"
            ;;
        aarch64 | arm64)
            current_arch="arm64"
            ;;
        armv7l | armhf)
            current_arch="armhf"
            ;;
        ppc64el)
            current_arch="ppc64el"
            ;;
        riscv64)
            current_arch="riscv64"
            ;;
        s390x)
            current_arch="s390x"
            ;;
        *)
            current_arch="amd64"
            ;;
        esac
    fi

    case "$current_arch" in
    amd64 | i386)
        echo "ubuntu"
        ;;
    *)
        echo "ubuntu-ports"
        ;;
    esac
}

# 选择当前机器可解析的腾讯 Ubuntu 镜像基础地址.
# 说明: 优先使用 mirrors.tencent.com, 不可解析时回退 mirrors.cloud.tencent.com.
# 返回: 输出基础地址, 未找到可用镜像时返回 1.
get_tencent_ubuntu_mirror_base() {
    local repo_path
    repo_path=$(get_ubuntu_repo_path_for_arch)

    local -a base_urls=(
        "http://mirrors.tencent.com/${repo_path}/"
        "http://mirrors.cloud.tencent.com/${repo_path}/"
    )
    local base_url=""
    local host_name=""

    for base_url in "${base_urls[@]}"; do
        host_name=$(printf '%s' "$base_url" | awk -F/ '{print $3}')
        if apt_host_is_resolvable "$host_name"; then
            echo "$base_url"
            return 0
        fi
    done

    return 1
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
    local ubuntu_mirror_base=""

    ubuntu_mirror_base=$(get_tencent_ubuntu_mirror_base) || {
        log_warn "未找到当前机器可解析的腾讯 Ubuntu 镜像域名, 跳过 apt 换源"
        return 0
    }

    if [ -f "$deb822_source_file" ]; then
        backup_apt_source_file_once "$deb822_source_file"
        cat <<EOF | run_with_sudo_if_available tee "$deb822_source_file" >/dev/null
Types: deb
URIs: $ubuntu_mirror_base
Suites: $SYSTEM_CODENAME $SYSTEM_CODENAME-security $SYSTEM_CODENAME-updates $SYSTEM_CODENAME-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        return 0
    fi

    backup_apt_source_file_once "$legacy_source_file"
    cat <<EOF | run_with_sudo_if_available tee "$legacy_source_file" >/dev/null
deb $ubuntu_mirror_base $SYSTEM_CODENAME main restricted universe multiverse
deb $ubuntu_mirror_base $SYSTEM_CODENAME-security main restricted universe multiverse
deb $ubuntu_mirror_base $SYSTEM_CODENAME-updates main restricted universe multiverse
deb $ubuntu_mirror_base $SYSTEM_CODENAME-backports main restricted universe multiverse
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
    apt_get_noninteractive clean all
    apt_update
}

# 开始当前流程的临时腾讯镜像换源, 支持嵌套调用.
# 参数: $1: 流程名称, 用于日志输出.
# 返回: 0 表示无需换源或切换成功, 非 0 表示切换失败.
begin_temporary_cn_non_tencent_apt_source() {
    local flow_name=${1:-"当前流程"}

    if [ "$APT_SOURCE_TEMP_ACTIVE" = "true" ]; then
        APT_SOURCE_SCOPE_DEPTH=$((APT_SOURCE_SCOPE_DEPTH + 1))
        return 0
    fi

    switch_cn_non_tencent_apt_source || return 1

    if [ "$APT_SOURCE_SWITCHED" != "true" ]; then
        return 0
    fi

    register_apt_source_exit_trap
    APT_SOURCE_TEMP_ACTIVE="true"
    APT_SOURCE_SCOPE_DEPTH=1
    log_info "${flow_name} 已启用临时 apt 换源, 流程结束后将自动恢复"
}

# 结束当前流程的临时腾讯镜像换源, 在最外层调用时恢复原始软件源.
# 参数: $1: 是否强制恢复, true 表示忽略嵌套层级.
# 返回: 始终返回 0.
restore_temporary_cn_non_tencent_apt_source() {
    local force_restore=${1:-false}

    if [ "$APT_SOURCE_TEMP_ACTIVE" != "true" ]; then
        return 0
    fi

    if [ "$force_restore" != "true" ] && [ "$APT_SOURCE_SCOPE_DEPTH" -gt 1 ]; then
        APT_SOURCE_SCOPE_DEPTH=$((APT_SOURCE_SCOPE_DEPTH - 1))
        return 0
    fi

    restore_apt_source_backups
    APT_SOURCE_SWITCHED="false"
    APT_SOURCE_TEMP_ACTIVE="false"
    APT_SOURCE_SCOPE_DEPTH=0
    unregister_apt_source_exit_trap

    # 恢复原始源后刷新索引, 避免后续命中临时镜像缓存.
    apt_get_noninteractive clean all || true
    apt_update || true

    log_info "已恢复临时切换前的 apt 软件源"
}

# 在临时腾讯镜像换源作用域内执行指定函数, 并在流程结束后自动恢复软件源.
# 参数: $1: 流程名称; $2: 要执行的函数名; $@: 函数参数.
# 返回: 透传被执行函数的退出码.
run_with_temporary_cn_non_tencent_apt_source() {
    local flow_name=$1
    local target_func=$2
    local status=0

    shift 2

    begin_temporary_cn_non_tencent_apt_source "$flow_name" || return 1
    "$target_func" "$@" || status=$?
    restore_temporary_cn_non_tencent_apt_source false || true
    return $status
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
