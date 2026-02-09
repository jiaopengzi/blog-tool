#!/bin/bash
# FilePath    : blog-tool/docker/install.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 安装 docker

# 执行 docker 安装和配置
__install_docker() {
    log_debug "run __install_docker"

    # 是否为手动安装, 默认否
    local is_manual_install="${1-n}"

    # 先执行备份，同时避免镜像源不一致导致的问题
    docker_install_backup

    # 脚本下载地址
    local script_url="https://get.docker.com"

    local script_file="./install-docker.sh"

    # 下载脚本
    # shellcheck disable=SC2329
    run() {
        # sudo curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 5 --max-time 10 "$script_url" -o "$script_file"
        log_debug "下载命令: sudo curl -fsSL --connect-timeout 5 --max-time 10 $script_url -o $script_file"
        sudo curl -fsSL --connect-timeout 5 --max-time 10 "$script_url" -o "$script_file"
    }

    # 手动重试下载脚本，最多重试 5 次, 初始延迟 2 秒
    if ! retry_with_backoff "run" 5 2 "docker 安装脚本下载成功" "docker 安装脚本下载失败" ""; then
        log_error "下载 docker 安装脚本失败, 请检查网络连接"
        exit 1
    fi

    # 获取最快的 Docker CE 镜像源
    local fastest_docker_mirror
    # 如果是手动安装，则不使用镜像源加速
    if [[ "$is_manual_install" == "y" ]]; then
        fastest_docker_mirror=$(manual_select_docker_source)
    else
        fastest_docker_mirror=$(find_fastest_docker_mirror)
    fi

    # 将 DEFAULT_DOWNLOAD_URL="https://download.docker.com" 替换为最快的镜像源
    if [[ -n "$fastest_docker_mirror" ]]; then
        log_info "使用最快的 Docker CE 镜像源: $fastest_docker_mirror"

        # 替换下载地址
        sudo sed -i "s|DOWNLOAD_URL=\"https://mirrors.aliyun.com/docker-ce\"|DOWNLOAD_URL=\"$fastest_docker_mirror\"|g" "$script_file"

        # 将所有字符串 Aliyun 替换为 MyFastMirror
        sudo sed -i "s|Aliyun|MyFastMirror|g" "$script_file"
    else
        log_warn "未找到可用的 Docker CE 镜像源, 将使用默认官方源进行安装，可能会因为网络问题导致安装失败"
    fi

    # 给脚本执行权限
    sudo chmod +x "$script_file"

    log_info "正在安装 docker, 请耐心等待..."

    # 执行安装脚本并记录日志
    if sudo bash "$script_file" --mirror MyFastMirror 2>&1 | tee -a ./install.log; then
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

    # 设置 docker 日志配置
    set_daemon_config

    # 移除安装脚本
    sudo rm -f "$script_file"

    # 移除安装日志
    sudo rm -f ./install.log
}

# 卸载 docker
__uninstall_docker() {
    log_debug "run __uninstall_docker"

    # 停止服务
    sudo systemctl stop docker || true

    # 卸载 docker
    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

    # 自动删除无用依赖
    sudo apt autoremove -y

    log_info "docker 卸载完成"

    is_remove=$(read_user_input "是否需要移除 docker 的历史数据 docker (默认n) [y|n]? " "n")

    if [[ "$is_remove" == "y" ]]; then
        # 删除相关数据
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd

        # 删除 apt 源和 keyring
        sudo rm /etc/apt/sources.list.d/docker.list
        sudo rm /etc/apt/keyrings/docker.asc

        log_info "已移除 docker 历史数据"
    else
        log_info "未移除 docker 历史数据"
    fi
}

# 卸载 docker
uninstall_docker() {
    log_debug "run uninstall_docker"

    is_uninstall=$(read_user_input "是否卸载 docker (默认n) [y|n]? " "n")
    if [[ "$is_uninstall" == "y" ]]; then
        __uninstall_docker
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
            __uninstall_docker

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
