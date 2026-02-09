#!/bin/bash
# FilePath    : blog-tool/system/sys.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 系统相关

# 设置主机名称
set_hostname() {
    log_debug "run set_hostname"

    # 读取用户输入
    printf "\n请输入新的主机名(默认:%s): $HOST_NAME"
    read -r input1

    if [[ -n "$input1" ]]; then
        HOST_NAME="$input1"
    fi

    sudo hostnamectl set-hostname "$HOST_NAME"

    log_info "主机名已设置为 $HOST_NAME ，请重新连接"
}

# 设置内网静态ip
set_host_intranet_ip() {
    log_debug "run set_host_intranet_ip"

    # 确认是否设置内网静态ip
    input1=$(read_user_input "设置静态ip需要重新连接,是否设置内网静态ip (默认n) [y|n]? " "n")

    if [[ "$input1" == "y" ]]; then
        # 读取用户输入
        printf "\nIP默认:%s,回车表示使用默认值" "$HOST_INTRANET_IP"
        printf "\n请输入本机的内网IP地址:"
        read -r input2

        # 读取用户输入
        printf "\n网关默认:%s,回车表示使用默认值 $GATEWAY_IPV4"
        printf "\n请输入本机的网关地址:"
        read -r input3

        if [[ -n "$input2" ]]; then
            HOST_INTRANET_IP="$input2"
        fi

        if [[ -n "$input3" ]]; then
            GATEWAY_IPV4="$input3"
        fi

        # 配置文件路径
        FILE="/etc/network/interfaces"

        # 新的网络配置
        read -r -d '' NEW_CONFIG <<EOM
iface INTERFACE_NAME inet static
    address $HOST_INTRANET_IP
    netmask 255.255.0.0
    gateway $GATEWAY_IPV4
    dns-nameservers $GATEWAY_IPV4 223.5.5.5 8.8.8.8
EOM

        # 获取网卡名称
        INTERFACE_NAME=$(awk '/allow-hotplug/ {print $2}' $FILE)

        # 替换 INTERFACE_NAME
        NEW_CONFIG=${NEW_CONFIG//INTERFACE_NAME/$INTERFACE_NAME}

        # 使用 awk 替换原始配置
        awk -v r="$NEW_CONFIG" "{gsub(/iface $INTERFACE_NAME inet dhcp/,r)}1" $FILE >temp && sudo mv temp $FILE

        # 重启网络服务
        sudo /etc/init.d/networking restart
    fi
}
