#!/bin/bash
# FilePath    : blog-tool/system/software.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 系统软件安装

# 安装常用软件
install_common_software() {
    log_debug "run install_common_software"

    # 安装常用软件
    apt_update

    # 无代理直接更新
    if command -v sudo >/dev/null 2>&1; then
        sudo apt install -y "${BASE_SOFTWARE_LIST[@]}"
    else
        apt install -y "${BASE_SOFTWARE_LIST[@]}"
    fi

    # 设置历史记录大小
    if ! grep -q "export HISTSIZE=*" "$HOME/.bashrc"; then
        # 如果不存在则添加
        echo 'export HISTSIZE=5000' | tee -a "$HOME/.bashrc"
    fi

    # 设置历史文件大小
    if ! grep -q "export HISTFILESIZE=*" "$HOME/.bashrc"; then
        # 如果不存在则添加
        echo 'export HISTFILESIZE=5000' | tee -a "$HOME/.bashrc"
    fi

    # cosign 仅用于开发版工具的构建推送签名, 生产用户发行版安装依赖时跳过
    if blog_tool_build_type_is_dev; then
        install_cosign
    fi

    # log_info "常用软件安装完成, 重启中..."
    # /usr/sbin/reboot
}

# 安装 cosign（官方二进制，适配 Debian/Ubuntu）
# 若网络无法访问 github.com 则跳过安装, 不阻断主流程
install_cosign() {
    log_debug "run install_cosign"

    if command -v cosign >/dev/null 2>&1; then
        log_info "cosign 已安装: $(cosign version 2>&1 | head -1)"
        return 0
    fi

    local arch
    arch=$(uname -m)
    case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)
        log_warn "不支持的架构: $arch, 跳过 cosign 安装"
        return 0
        ;;
    esac

    # 获取最新版本号, 设置连接超时与最大等待时间, 避免 github 不可达时长时间阻塞
    local latest_version
    latest_version=$(curl --connect-timeout 10 --max-time 30 -fsSL \
        https://api.github.com/repos/sigstore/cosign/releases/latest 2>/dev/null |
        grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/') || true

    if [ -z "$latest_version" ]; then
        log_warn "获取 cosign 最新版本失败, 可能是网络无法访问 github.com, 跳过安装"
        return 0
    fi

    local bin_url="https://github.com/sigstore/cosign/releases/download/v${latest_version}/cosign-linux-${arch}"

    log_info "安装 cosign v${latest_version} (${arch})..."

    # 启动等待动画, 下载期间给用户视觉反馈
    start_spinner

    # 下载超时 30 秒, 并设置最低速率限制(1 字节/秒持续 15 秒视为停滞)
    local download_ok=true
    if command -v sudo >/dev/null 2>&1; then
        if ! sudo curl --connect-timeout 10 --max-time 30 --speed-limit 1 --speed-time 15 \
            -fsSL "$bin_url" -o /usr/local/bin/cosign; then
            download_ok=false
            sudo rm -f /usr/local/bin/cosign
        fi
    else
        if ! curl --connect-timeout 10 --max-time 30 --speed-limit 1 --speed-time 15 \
            -fsSL "$bin_url" -o /usr/local/bin/cosign; then
            download_ok=false
            rm -f /usr/local/bin/cosign
        fi
    fi

    # 无论成功与否都先停止动画, 再输出结果日志
    stop_spinner

    if [ "$download_ok" = false ]; then
        log_warn "下载 cosign 超时或失败, 可能是网络无法访问 github.com, 跳过安装"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo chmod +x /usr/local/bin/cosign
    else
        chmod +x /usr/local/bin/cosign
    fi

    log_info "cosign 安装完成: $(cosign version 2>&1 | head -1)"
}
