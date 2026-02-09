#!/bin/bash
# FilePath    : blog-tool/utils/sys.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 系统相关工具

## CPU 逻辑核心数 (lscpu 的 CPU(s) 字段)
get_cpu_logical() {
    grep -c '^processor[[:space:]]*:' /proc/cpuinfo
}

# 获取内存总大小 (GB, 精确到小数点后 2 位)
get_mem_gb() {
    awk '/^MemTotal:/ {printf "%.2f\n", $2/1024/1024}' /proc/meminfo
}

# 判断内存是否大于 n GB
is_mem_greater_than() {
    # 参数:
    # $1 - 内存阈值 (GB)
    local mem_gb
    mem_gb=$(get_mem_gb)

    log_debug "当前内存: ${mem_gb}GB, 阈值: ${1}GB"

    local threshold=$1
    awk -v mem="$mem_gb" -v thresh="$threshold" 'BEGIN {exit (mem > thresh) ? 0 : 1}'
}
