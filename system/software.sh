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

    # 安装 cosign（Ubuntu 默认 apt 源无此包，需单独安装二进制）
    install_cosign

    # log_info "常用软件安装完成, 重启中..."
    # /usr/sbin/reboot
}

# 安装 cosign（官方二进制，适配 Debian/Ubuntu）
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
        log_error "不支持的架构: $arch"
        return 1
        ;;
    esac

    local latest_version
    latest_version=$(curl -fsSL https://api.github.com/repos/sigstore/cosign/releases/latest |
        grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')

    if [ -z "$latest_version" ]; then
        log_error "获取 cosign 最新版本失败"
        return 1
    fi

    local bin_url="https://github.com/sigstore/cosign/releases/download/v${latest_version}/cosign-linux-${arch}"

    log_info "安装 cosign v${latest_version} (${arch})..."
    if command -v sudo >/dev/null 2>&1; then
        sudo curl -fsSL "$bin_url" -o /usr/local/bin/cosign
        sudo chmod +x /usr/local/bin/cosign
    else
        curl -fsSL "$bin_url" -o /usr/local/bin/cosign
        chmod +x /usr/local/bin/cosign
    fi

    log_info "cosign 安装完成: $(cosign version 2>&1 | head -1)"
}
