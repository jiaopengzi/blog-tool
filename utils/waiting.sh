#!/bin/bash
# FilePath    : blog-tool/utils/waiting.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 等待动画工具

# 内部变量：存储等待动画的后台进程ID
__spinner_pid=""

# 内部变量: 记录是否设置过滚动区域(DECSTBM), 用于 stop 时正确还原
__spinner_scroll_set=""

# 内部变量: 信号兜底 trap 是否已经安装(避免重复安装)
__spinner_trap_installed=""

# 内部函数: 信号/退出兜底清理, 防止 Ctrl+C 后 spinner 进程残留与终端滚动区域错乱
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

    # 安装信号兜底 trap, 防止异常退出后 spinner 进程残留与终端滚动区域错乱
    __spinner_install_trap

    # 取终端尺寸
    local rows cols
    rows=$(tput lines 2>/dev/null || echo 24)
    cols=$(tput cols 2>/dev/null || echo 80)

    # 设置滚动区域为 1..rows-1 行, 把最后一行从滚动区域中排除出来,
    # 这样上方任何输出/换行/滚动都不会影响最后一行(spinner 所在行).
    # \033[1;Hr 设置 DECSTBM; 设置后光标会跳到 (1,1), 因此再保存光标位置.
    printf "\033[1;%dr" "$((rows - 1))" >&2
    # 把光标移到滚动区底部(rows-1 行行首), 避免后续输出从顶部 (1,1) 开始
    printf "\033[%d;1H" "$((rows - 1))" >&2
    __spinner_scroll_set="1"

    # 当前帧索引
    local spin_index=0

    # 显示等待动画
    # 每帧: 保存光标 -> 跳到最后一行行首 -> 清行并写入 spinner -> 恢复光标
    # spinner 行被排除在滚动区外, 不会被命令输出推走, 位置稳定
    show_spinner() {
        # 立即渲染首帧, 避免短命令一帧都看不到
        printf "\0337\033[%d;1H\033[2K%s\0338" "$rows" "${spinner_frames[$spin_index]}" >&2
        while true; do
            printf "\0337\033[%d;1H\033[2K%s\0338" "$rows" "${spinner_frames[$spin_index]}" >&2
            spin_index=$(((spin_index + 1) % ${#spinner_frames[@]}))
            sleep 0.2
        done
    }

    # 启动等待动画作为后台进程
    show_spinner &
    __spinner_pid=$!

    # 防止 cols 未使用导致 shellcheck 警告
    : "$cols"
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

    # 还原滚动区域, 并清掉 spinner 残留
    if [ -n "$__spinner_scroll_set" ]; then
        local rows
        rows=$(tput lines 2>/dev/null || echo 24)
        # 保存光标 -> 清掉最后一行 spinner -> 还原滚动区域 -> 恢复光标
        printf "\0337\033[%d;1H\033[2K\033[r\0338" "$rows" >&2
        __spinner_scroll_set=""
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
