#!/bin/bash
# FilePath    : blog-tool/utils/waiting.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 等待动画工具

# 内部变量：存储等待动画的后台进程ID
__spinner_pid=""

# 内部变量: 信号兜底 trap 是否已经安装(避免重复安装)
__spinner_trap_installed=""

# 内部函数: 信号/退出兜底清理, 防止 Ctrl+C 后 spinner 进程残留
__spinner_cleanup_on_exit() {
    # 不调用 log 函数, 避免在退出阶段产生递归输出
    stop_spinner 2>/dev/null || true
}

# 内部函数: 安装信号兜底 trap, 仅首次调用时安装
# EXIT 兜现正常/异常退出; INT/TERM/HUP 兜现中断, 清理后再以原信号结束自身, 保留正确退出码
__spinner_install_trap() {
    if [ -n "$__spinner_trap_installed" ]; then
        return
    fi
    trap '__spinner_cleanup_on_exit' EXIT
    trap '__spinner_cleanup_on_exit; trap - INT;  kill -INT  $$' INT
    trap '__spinner_cleanup_on_exit; trap - TERM; kill -TERM $$' TERM
    trap '__spinner_cleanup_on_exit; trap - HUP;  kill -HUP  $$' HUP
    __spinner_trap_installed="1"
}

# 开始等待动画
# 设计:
#   - 采用 \r 跟随光标方案: spinner 始终写在 "当前光标所在行" 的行首
#   - 不使用 DECSTBM 滚动区域, 避免在大量日志/不规则换行场景下产生残留与错位
#   - 配合 utils/log.sh 中日志写入前的 \r\033[2K, 实现 spinner 与日志输出无缝交替
start_spinner() {
    # 如果动画已经在运行, 直接返回
    if [ -n "$__spinner_pid" ]; then
        return
    fi

    # 等待动画帧(固定宽度, 圆点在条内来回移动)
    local spinner_frames=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

    # 仅在 stderr 是 TTY 时启用动画, 避免污染重定向到文件的输出
    if [ ! -t 2 ]; then
        return
    fi

    # 安装信号兜底 trap, 防止异常退出后 spinner 进程残留
    __spinner_install_trap

    # 当前帧索引
    local spin_index=0

    # 显示等待动画
    # 每帧: \r 回到行首 -> 写入 spinner + 两个空格 -> 再 \r 把光标拉回行首
    # 关键: 把光标停在行首, 这样并发的 stdout 输出(如 docker pull 的 "8.6.2: Pulling...")
    #      会从行首开始打印, 自然覆盖掉 spinner 的 3 列字符, 不会出现 "⣟  8.6.2: ..." 拼接残留
    show_spinner() {
        # 立即渲染首帧, 避免瞬时命令一帧都看不到
        printf "\r%s  \r" "${spinner_frames[$spin_index]}" >&2
        while true; do
            printf "\r%s  \r" "${spinner_frames[$spin_index]}" >&2
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
        __spinner_pid="" # 清空PID以避免再次停止
    fi

    # 仅在 TTY 下才发送 ANSI 清除序列, 避免污染非 TTY 输出
    if [ -t 2 ]; then
        # \r 回到行首 -> \033[2K 整行清除, 光标停在行首
        # 即使 spinner 后跟了更长的命令输出也能彻底清除, 避免 prompt 出现在行中部
        printf "\r\033[2K" >&2
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
