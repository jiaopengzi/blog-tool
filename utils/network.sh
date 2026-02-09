#!/bin/bash
# FilePath    : blog-tool/utils/network.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 网络相关工具

# 获取 CIDR(子网掩码数字)
# 参数: $1: 子网掩码, 例如: 255.255.255.0
# 返回: CIDR 值, 例如: 24
get_cidr() {
    # 获取子网掩码
    local mask=$1

    # 没有安装 bc 返回默认值 24
    if ! command -v bc >/dev/null 2>&1; then
        echo "24"
        return
    fi

    # 使用点分割得到四个数字
    IFS='.' read -ra ADDR <<<"$mask"

    # 初始化一个空字符串来存储二进制表示
    binary_mask=""

    # 对四个数字使用十进制转为二进制，并拼接起来
    for i in "${ADDR[@]}"; do
        binary_part=$(echo "obase=2; $i" | bc)
        binary_mask+=$binary_part
    done

    # 数一下这字符串中有多少个1就是多少位
    cidr=$(grep -o "1" <<<"$binary_mask" | wc -l)

    # 输出 CIDR 值
    echo "$cidr"
}

# 检查端口是否可用
# 参数: $1: 端口号
# 返回: 0 - 可用, 1 - 被占用
check_port_available() {
    local port=$1
    if lsof -i :"$port" >/dev/null; then
        log_error "端口 $port 被占用"
        return 1 # 端口被占用
    else
        log_info "端口 $port 可用"
        return 0 # 端口可用
    fi
}

# 检查 URL 是否可访问
# 参数: $1: URL 地址
# 返回: 0 - 可访问, 1 - 不可访问
check_url_accessible() {
    local url=$1
    local timeout=$2

    # 设置默认超时时间为 5 秒
    if [[ -z "$timeout" ]]; then
        timeout=5
    fi

    log_debug "正在检查 URL 可访问性: $url (超时: ${timeout}s)"
    # 开始等待动画
    start_spinner

    # 使用 curl 检查 URL 可访问性
    if curl -Is --max-time "$timeout" "$url" >/dev/null; then
        log_debug "URL 可访问: $url"
        stop_spinner
        return 0 # URL 可访问
    else
        log_debug "URL 不可访问: $url"
        stop_spinner
        return 1 # URL 不可访问
    fi
}
