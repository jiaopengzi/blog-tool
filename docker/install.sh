#!/bin/bash
# FilePath    : blog-tool/docker/install.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 安装 docker

# 修补上游 Docker 安装脚本, 注入镜像源并降低非交互安装阻塞风险.
# 参数: $1: 下载后的安装脚本路径.
# 参数: $2: 选中的 Docker CE 镜像源, 为空则保留上游默认源.
# 返回: 修补成功返回 0, 脚本文件不存在返回 1.
docker_patch_install_script() {
    log_debug "run docker_patch_install_script"

    local script_file="$1"
    local docker_mirror="$2"

    if [[ -z "$script_file" || ! -f "$script_file" ]]; then
        log_error "Docker 安装脚本不存在, 无法继续修补"
        return 1
    fi

    if [[ -n "$docker_mirror" ]]; then
        sudo sed -i "s|DOWNLOAD_URL=\"https://mirrors.aliyun.com/docker-ce\"|DOWNLOAD_URL=\"$docker_mirror\"|g" "$script_file"
        sudo sed -i 's|Aliyun|MyFastMirror|g' "$script_file"
    fi

    # blog-tool 不依赖 docker-model-plugin, WSL Ubuntu 上该可选包可能放大 postinst 阻塞面.
    sudo sed -i 's/[[:space:]]docker-model-plugin//g' "$script_file"

    # 上游脚本默认把 apt 输出重定向到 /dev/null, 卡住时没有任何可诊断信息.
    sudo sed -i 's|apt-get -qq update >/dev/null|apt-get update|g' "$script_file"
    sudo sed -i 's|DEBIAN_FRONTEND=noninteractive apt-get -y -qq install|DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical NEEDRESTART_MODE=a APT_LISTCHANGES_FRONTEND=none UCF_FORCE_CONFDEF=1 UCF_FORCE_CONFFOLD=1 apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install|g' "$script_file"
    sudo sed -i 's|install \$pre_reqs >/dev/null|install \$pre_reqs|g' "$script_file"
    sudo sed -i 's|install \$pkgs >/dev/null|install \$pkgs|g' "$script_file"
}

# 执行上游 Docker 安装脚本, 跳过上游自启动并交给本工具统一配置 daemon.
# 参数: $1: 下载后的安装脚本路径.
# 参数: $2: 选中的 Docker CE 镜像源, 非空时使用已注入的 MyFastMirror.
# 返回: 安装脚本成功返回 0, 失败或超时返回非 0.
docker_run_install_script() {
    local script_file="$1"
    local docker_mirror="$2"
    local install_timeout=900
    local -a install_args=(bash "$script_file")

    if [[ -n "$docker_mirror" ]]; then
        install_args+=(--mirror MyFastMirror)
    fi

    if command -v timeout >/dev/null 2>&1; then
        sudo env NO_AUTOSTART=1 timeout "$install_timeout" "${install_args[@]}"
        return $?
    fi

    sudo env NO_AUTOSTART=1 "${install_args[@]}"
}

# 执行 docker 安装和配置
__install_docker() {
    log_debug "run __install_docker"

    # 是否为手动安装, 默认否
    local is_manual_install="${1-n}"

    # 先执行备份，同时避免镜像源不一致导致的问题
    docker_install_backup

    local script_file="./install-docker.sh"
    local script_url=""
    local script_download_success="false"

    local region
    region=$(detect_docker_region)

    local script_urls=()
    if [[ "$region" == "tencent_cn" || "$region" == "cn_non_tencent" ]]; then
        script_urls=(
            "https://gitee.com/jiaopengzi/docker-install/raw/master/install.sh"
            "https://get.docker.com"
        )
    else
        script_urls=(
            "https://get.docker.com"
        )
    fi

    # 下载脚本
    # shellcheck disable=SC2317,SC2329
    run() {
        log_debug "下载命令: sudo curl -fsSL --connect-timeout 5 --max-time 10 $script_url -o $script_file"
        sudo curl -fsSL --connect-timeout 5 --max-time 10 "$script_url" -o "$script_file"
    }

    # 手动重试下载脚本，最多重试 5 次, 初始延迟 2 秒
    for item in "${script_urls[@]}"; do
        script_url="$item"
        log_info "准备下载 docker 安装脚本: $script_url"
        if retry_with_backoff "run" 5 2 "docker 安装脚本下载成功" "docker 安装脚本下载失败" ""; then
            script_download_success="true"
            break
        fi

        log_warn "当前 docker 安装脚本地址不可用, 尝试下一个地址"
    done

    if [[ "$script_download_success" != "true" ]]; then
        log_error "下载 docker 安装脚本失败, 请检查网络连接"
        exit 1
    fi

    local fastest_docker_mirror
    # 手动安装时由用户选择 Docker CE 源, 自动安装时使用测速结果.
    if [[ "$is_manual_install" == "y" ]]; then
        fastest_docker_mirror=$(manual_select_docker_source)
    else
        fastest_docker_mirror=$(find_fastest_docker_mirror)
    fi

    if [[ -n "$fastest_docker_mirror" ]]; then
        log_info "使用最快的 Docker CE 镜像源: $fastest_docker_mirror"
    else
        log_warn "未找到可用的 Docker CE 镜像源, 将使用上游默认源进行安装"
    fi

    docker_patch_install_script "$script_file" "$fastest_docker_mirror" || return 1

    # 给脚本执行权限
    sudo chmod +x "$script_file"

    log_info "正在安装 docker, 请耐心等待..."

    # 执行安装脚本并记录日志
    if (set -o pipefail; docker_run_install_script "$script_file" "$fastest_docker_mirror" 2>&1 | tee -a ./install.log); then
        log_info "docker 安装脚本执行完成"

        # 进一步验证 docker 是否真的安装成功
        if command -v docker &>/dev/null && docker --version &>/dev/null; then
            log_info "docker 安装验证成功，docker 命令可用"
        else
            log_error "docker 命令不可用，安装失败，请检查安装日志"
            return 1
        fi
    else
        log_error "docker 安装失败"
        return 1
    fi

    log_info "docker 安装完成, 开始设置 docker daemon 配置"

    # 设置 docker 日志配置
    set_daemon_config

    # 移除安装脚本
    sudo rm -f "$script_file"

    # 移除安装日志
    sudo rm -f ./install.log
}

# 卸载 docker 的历史数据.
# 参数: $1: 是否移除历史数据, y 表示移除, 其他值表示保留.
docker_remove_history_data() {
    log_debug "run docker_remove_history_data"

    local remove_history_data="$1"

    if [[ "$remove_history_data" == "y" ]]; then
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd

        sudo rm -f /etc/apt/sources.list.d/docker.list
        sudo rm -f /etc/apt/keyrings/docker.asc

        log_info "已移除 docker 历史数据"
    else
        log_info "未移除 docker 历史数据"
    fi
}

# 停止 docker 卸载前相关 systemd 服务.
# 返回: 尽最大努力停止 docker.socket、docker.service 和 containerd.service.
docker_stop_services_before_uninstall() {
    log_debug "run docker_stop_services_before_uninstall"

    sudo systemctl stop docker.socket >/dev/null 2>&1 || true
    sudo systemctl stop docker.service >/dev/null 2>&1 || true
    sudo systemctl stop containerd.service >/dev/null 2>&1 || true

    log_info "已停止 docker 相关服务"
}

# 卸载 docker.
# 参数: $1: 是否移除历史数据, 可选值为 y、n 或 prompt.
__uninstall_docker() {
    log_debug "run __uninstall_docker"

    local remove_history_data="${1:-prompt}"

    # 停止服务
    docker_stop_services_before_uninstall

    # 卸载 docker
    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-model-plugin || true

    # 自动删除无用依赖
    sudo apt autoremove -y

    log_info "docker 卸载完成"

    if [[ "$remove_history_data" == "prompt" ]]; then
        remove_history_data=$(read_user_input "是否需要移除 docker 的历史数据 docker (默认n) [y|n]? " "n")
    fi

    docker_remove_history_data "$remove_history_data"
}

# 卸载 docker
uninstall_docker() {
    log_debug "run uninstall_docker"

    is_uninstall=$(read_user_input "是否卸载 docker (默认n) [y|n]? " "n")
    if [[ "$is_uninstall" == "y" ]]; then
        __uninstall_docker "prompt"
    else
        log_info "未卸载 docker"
    fi
}

# docker 安装入口函数
install_docker() {
    log_debug "run install_docker"
    # 是否为手动安装, 默认否
    local is_manual_install="${1-n}"

    # 判断是否安装了 docker
    if command -v docker >/dev/null 2>&1; then
        log_warn "检测到已安装 Docker"

        local is_install
        is_install=$(read_user_input "是否需要卸载后重新安装 docker (默认n) [y|n]? " "n")

        if [[ "$is_install" == "y" ]]; then
            log_debug "开始卸载 docker"

            # 卸载 docker
            __uninstall_docker "prompt"

            # 执行安装
            __install_docker "$is_manual_install"
        else
            log_info "跳过 docker 重新安装步骤"
            return
        fi
    else
        # 执行安装
        __install_docker
    fi
}

# 手动安装 docker
manual_install_docker() {
    log_debug "run manual_install_docker"
    __install_docker "y"
}
