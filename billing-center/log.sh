#!/bin/bash
# FilePath    : blog-tool/billing-center/log.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 日志

# 查看 billing-center 日志
billing_center_logs() {
    log_debug "run billing_center_logs"

    printf "========================================\n"
    printf "    [ 1 ] 查看 billing-center 常规日志\n"
    printf "    [ 2 ] 查看 billing-center 验证码日志\n"
    printf "========================================\n"
    local user_input
    user_input=$(read_user_input "请输入对应数字查看日志 [1-2]? " "1")

    local log_file filter_cmd

    case "$user_input" in
    1)
        # 常规日志
        log_file="$DATA_VOLUME_DIR/billing-center/logs/app.log"
        filter_cmd=()
        ;;
    2)
        # 验证码日志
        log_file="$DATA_VOLUME_DIR/billing-center/logs/app.log"
        filter_cmd=("grep" "发送验证码")
        ;;
    *)
        # 无效输入
        log_warn "无效输入：$user_input"
        return 1
        ;;
    esac

    # 检查日志文件是否存在
    if [ ! -f "$log_file" ]; then
        log_warn "$log_file, 日志文件不存在或当前无日志可查看"
        return 1
    fi

    # 构建命令：tail -f + 可选过滤
    if [ ${#filter_cmd[@]} -eq 0 ]; then
        tail -f "$log_file"
    else
        tail -f "$log_file" | "${filter_cmd[@]}"
    fi
}
