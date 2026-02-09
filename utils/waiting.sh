#!/bin/bash
# FilePath    : blog-tool/utils/waiting.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 等待动画工具

# 内部变量：存储等待动画的后台进程ID
__spinner_pid=""

# 开始等待动画
start_spinner() {
    # 如果动画已经在运行, 直接返回
    if [ -n "$__spinner_pid" ]; then
        return
    fi

    # 等待动画帧(固定宽度, 圆点在条内来回移动)
    local spinner_frames=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

    # 当前帧索引
    local spin_index=0

    # 显示等待动画
    show_spinner() {
        while true; do
            printf "\r%s  " "${spinner_frames[$spin_index]}" >&2
            spin_index=$(((spin_index + 1) % ${#spinner_frames[@]}))
            sleep 0.2
        done
    }

    # 启动等待动画作为后台进程
    show_spinner &
    __spinner_pid=$!
}

# 停止等待动画
stop_spinner() {
    if [ -n "$__spinner_pid" ]; then
        # 检查进程是否仍在运行
        if kill -0 "$__spinner_pid" 2>/dev/null; then
            # 忽略错误防止脚本退出
            kill "$__spinner_pid" 2>/dev/null || true # kill 进程, 忽略错误防止脚本退出
            wait "$__spinner_pid" 2>/dev/null || true # 等待进程退出, 忽略错误防止脚本退出
        fi

        printf "\r  \r" >&2 # 清除残留帧
        __spinner_pid=""    # 清空PID以避免再次停止
    fi
}

# 等待指定的持续时间并显示等待动画
# 参数: 持续时间(秒)
waiting() {
    local duration=$1

    # 如果没有指定持续时间, 直接返回
    if [[ -z "$duration" || "$duration" -le 0 ]]; then
        return
    fi

    # 开始等待动画
    start_spinner

    # 等待指定的持续时间
    sleep "$duration"

    # 停止等待动画
    stop_spinner
}

# 等待文件完成
wait_file_write_complete() {
    log_debug "run wait_file_write_complete"

    log_warn "等待文件写入完成, 这可能需要几分钟时间... 请勿中断！"

    # 参数:
    # $1: run_func 用于触发文件写入的函数
    # $2: file_path 文件路径
    # $3: timeout 超时时间(秒), 可选参数, 默认 300 秒
    local run_func="$1"
    local file_path="$2"
    local timeout=${3:-300}

    # 记录开始时间
    local start_time
    start_time=$(date +%s)

    # 开始等待动画
    start_spinner

    # 执行传入的函数
    $run_func

    # 循环检查文件是否存在
    until sudo [ -f "$file_path" ]; do
        sleep 1

        # 检查是否超时
        local current_time
        current_time=$(date +%s)

        # 计算经过的时间
        local elapsed_time=$((current_time - start_time))

        # 如果超过超时时间就报错退出
        if [ "$elapsed_time" -ge "$timeout" ]; then
            # 停止等待动画
            stop_spinner

            log_error "等待文件写入完成超时, 已超过 $timeout 秒, 请检查相关日志"
            exit 1
        fi
    done

    # 停止等待动画
    stop_spinner

    log_debug "文件 $file_path 写入完成."
}
