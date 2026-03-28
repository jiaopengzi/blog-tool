#!/bin/bash
# FilePath    : blog-tool/utils/log_app.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 应用日志公共工具

# 修改应用日志级别
# 参数: $1: yaml 配置文件路径
# 参数: $2: 重启函数名
_app_log_set_level() {
    local yaml_config_path="$1"
    local restart_func="$2"

    # 检查 yaml 配置文件是否存在
    if ! sudo test -f "$yaml_config_path"; then
        log_warn "$yaml_config_path, 日志配置文件不存在或尚未初始化"
        return 1
    fi

    printf "========================================\n"
    printf "    日志级别选项\n"
    printf "    [ 1 ] debug\n"
    printf "    [ 2 ] info\n"
    printf "    [ 3 ] warn\n"
    printf "    [ 4 ] error\n"
    printf "========================================\n"

    local level_input
    level_input=$(read_user_input "请选择日志级别 [1-4]? " "2")

    local new_level
    case "$level_input" in
    1) new_level="debug" ;;
    2) new_level="info" ;;
    3) new_level="warn" ;;
    4) new_level="error" ;;
    *)
        log_warn "无效输入：$level_input"
        return 1
        ;;
    esac

    # 读取当前级别
    local current_level
    current_level=$(sudo grep -E '^\s+level:' "$yaml_config_path" | head -n 1 | sed 's/.*level:[[:space:]]*//' | tr -d '"')

    log_info "当前日志级别: $current_level, 即将修改为: $new_level"

    # 二次确认：重启会导致业务中断
    local confirm
    confirm=$(read_user_input "修改日志级别后需要重启容器, 期间业务将短暂中断, 确认继续吗 (默认n) [y|n]? " "n")
    if [ "$confirm" != "y" ]; then
        log_info "已取消修改日志级别"
        return 0
    fi

    # 更新 yaml 中的 level 字段
    sudo sed -i "s/^\(\s\+level:\s*\)\".*/\1\"$new_level\"/" "$yaml_config_path"

    log_info "日志级别已更新为: $new_level"

    # 重启容器
    log_info "正在重启容器..."
    $restart_func
}

# 应用日志公共函数
# 参数: $1: 服务展示名称, 如 billing-center / blog-server
# 参数: $2: 日志文件路径
# 参数: $3: zap yaml 配置文件路径
# 参数: $4: 重启函数名
app_log() {
    log_debug "run app_log"

    local service_name="$1"
    local log_file="$2"
    local yaml_config_path="$3"
    local restart_func="$4"

    printf "========================================\n"
    printf "    [ 1 ] 查看 %s 日志\n" "$service_name"
    printf "    [ 2 ] 修改 %s 日志级别\n" "$service_name"
    printf "========================================\n"

    local user_input
    user_input=$(read_user_input "请输入对应数字 [1-2]? " "1")

    case "$user_input" in
    1)
        # 检查日志文件是否存在
        if [ ! -f "$log_file" ]; then
            log_warn "$log_file, 日志文件不存在或当前无日志可查看"
            return 1
        fi
        tail -f "$log_file"
        ;;
    2)
        _app_log_set_level "$yaml_config_path" "$restart_func"
        ;;
    *)
        log_warn "无效输入：$user_input"
        return 1
        ;;
    esac
}
