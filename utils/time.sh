#!/bin/bash
# FilePath    : blog-tool/utils/time.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 时间相关工具

# 记录执行时间
# 参数: $1: 事件名称
# 参数: $2: 需要执行的函数
# 参数: $3: 开始时间, 可以不传, 则取当前时间
log_timer() {
    local event run_func start_time end_time time_elapsed hours minutes seconds
    event=$1
    run_func=$2
    start_time=${3:-$(date +%s)}

    log_debug "开始执行: ${event}, 开始时间: $(date -d "@$start_time" +"%Y-%m-%d %H:%M:%S")"

    # 执行传入的函数
    $run_func

    end_time=$(date +%s)
    time_elapsed=$((end_time - start_time))
    hours=$((time_elapsed / 3600))
    minutes=$(((time_elapsed / 60) % 60))
    seconds=$((time_elapsed % 60))
    log_info "${event}共计用时: ${hours}时${minutes}分${seconds}秒"
}
