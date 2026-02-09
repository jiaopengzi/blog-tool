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

    # log_info "常用软件安装完成, 重启中..."
    # /usr/sbin/reboot
}
