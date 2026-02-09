#!/bin/bash
# FilePath    : blog-tool/system/ssh.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : ssh配置

# 设置 ssh 配置
set_ssh_config() {
    log_debug "run set_ssh_config"

    # 如果没有 ./id_rsa.pub 文件需要提示用户生成
    if [ ! -f "$ROOT_DIR/id_rsa.pub" ]; then
        log_error "缺少 SSH 公钥文件: $ROOT_DIR/id_rsa.pub"
        exit 1
    fi

    # 读取同目录下的 id_rsa.pub 文件内容
    pub_key=$(cat "$ROOT_DIR/id_rsa.pub")
    authorized_keys=$HOME/.ssh/authorized_keys
    # 设置 SSH 配置
    sshd_config=/etc/ssh/sshd_config

    # 向服务器添加 ssh 公钥

    mkdir -p "$HOME/.ssh"
    touch "$authorized_keys"
    chmod 600 "$authorized_keys"
    # 将公钥添加到 authorized_keys 文件中
    echo "$pub_key" | sudo tee -a "$authorized_keys" >/dev/null

    # 备份原始的 SSH 配置文件
    sudo cp $sshd_config{,.bak}

    # update_ssh_config 函数 更新ssh配置
    update_ssh_config() {
        local key=$1
        local value=$2

        # 更新 /etc/ssh/sshd_config
        if grep -q -E "^(#)?$key" $sshd_config; then
            # 如果存在，将其设置为给定的值
            sudo sed -i "s/^\(#\)\?$key.*/$key $value/g" $sshd_config
        else
            # 如果不存在，添加一行
            echo "$key $value" | sudo tee -a $sshd_config >/dev/null
        fi

    }

    # 更新SSH配置
    # root账户登录
    update_ssh_config "PermitRootLogin" "yes"

    # 不使用密码登录
    update_ssh_config "PasswordAuthentication" "no"

    # 使用密钥对登录
    update_ssh_config "PubkeyAuthentication" "yes"

    # 修改ssh端口
    update_ssh_config "Port" "$SSH_PORT"

    # 禁用PAM
    update_ssh_config "UsePAM" "yes"

    # 重启 SSH 服务以使新的配置生效
    sudo systemctl restart sshd
    log_info "SSH 配置已更新"
    log_info "SSH 端口已修改为 $SSH_PORT"
    log_debug "请使用 cat $authorized_keys 查看文件是否存在公钥 "
}
