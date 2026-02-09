#!/bin/bash
# FilePath    : blog-tool/utils/log.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 日志记录

# ANSI颜色定义
RED='\033[0;31m'    # 错误(红)
YELLOW='\033[0;33m' # 警告(黄)
GREEN='\033[0;32m'  # 信息(绿)
BLUE='\033[0;34m'   # 调试(蓝)
NC='\033[0m'        # 重置颜色

# 将日志级别字符串转为数值(用于优先级比较)
get_level_num() {
    local level="$1"
    case "$level" in
    error) echo 1 ;;
    warn) echo 2 ;;
    info) echo 3 ;;
    debug) echo 4 ;;
    *) echo 5 ;; # 无效级别, 默认不记录
    esac
}

# 核心日志函数(不再处理 caller_info, 由调用方传入)
# 参数：$1=日志级别, $2=日志消息, $3=调用者信息(格式如 [file:line])
log() {
    local level="$1"
    local message="$2"
    local caller_info="${3:-}" # 由快捷函数传入(可选)

    # 为了日志一致性, 给消息加上中括号
    message="[$message]"

    # 1. 校验级别有效性
    if ! [[ "error warn info debug" =~ (^| )$level( |$) ]]; then
        echo -e "${RED}[WARN] 无效日志级别: $level, 已转为info${NC}" >&2
        level="info"
        message="无效级别[$level] → 原始消息: $message"
    fi

    # 2. 过滤：当前级别优先级低于全局阈值则跳过
    local current_num global_num
    current_num=$(get_level_num "$level")
    global_num=$(get_level_num "$LOG_LEVEL")
    [ "$current_num" -gt "$global_num" ] && return 0

    # 3. 格式化日志时间与级别
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local level_upper="${level^^}"
    local level_pretty
    level_pretty=$(printf "[%-5s]" "$level_upper") # 如 [ERROR]

    # 4. 终端带颜色输出
    local color
    case "$level" in
    error) color="$RED" ;;
    warn) color="$YELLOW" ;;
    info) color="$GREEN" ;;
    debug) color="$BLUE" ;;
    *) color="" ;;
    esac

    # 构建带颜色的终端输出
    # 屏幕输出: debug 级别显示时间与调用者信息, 其它级别只显示消息主体
    local formatted_msg
    if [ "$LOG_LEVEL" = "debug" ]; then
        if [ -n "$caller_info" ]; then
            formatted_msg="[$timestamp] ${level_pretty} ${caller_info} ${message}"
        else
            formatted_msg="[$timestamp] ${level_pretty} [unknown] ${message}"
        fi
    else
        formatted_msg="${message}"
    fi

    # 在控制台输出日志, >&2 确保输出到 stderr, 不被其他命令捕获
    echo -e "${color}${formatted_msg}${NC}" >&2

    # 5. 同样的内容写入日志文件(无颜色)
    local file_msg
    if [ -n "$caller_info" ]; then
        file_msg="[$timestamp] ${level_pretty} ${caller_info} ${message}"
    else
        file_msg="[$timestamp] ${level_pretty} [unknown] ${message}"
    fi

    # 检查是否是 root 权限运行
    if [ $UID -ne 0 ]; then
        echo -e "${RED}请使用 root 或者 sudo 运行此脚本.${NC}"
        exit 1
    fi

    echo "$file_msg" >>"$LOG_FILE"
}

# **在封装的快捷函数中自动添加调用者信息, 不能在进行封装, 否则行号不准确**
# 使用 BASH_LINENO[0] 获取用户调用 log_xxx() 的行号

log_error() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "error" "$message" "$caller_info"
}

log_warn() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "warn" "$message" "$caller_info"
}

log_info() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "info" "$message" "$caller_info"
}

log_debug() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "debug" "$message" "$caller_info"
}

# 免责声明信息
disclaimer_msg() {
    # 检查免责声明接受标记文件
    if [ -f "$BLOG_TOOL_ENV/disclaimer_accepted" ]; then
        # 标志文件中只有一行信息, 记录用户接受时间, 读取出来告知用户
        local accept_time
        accept_time=$(grep "用户接受时间:" "$BLOG_TOOL_ENV/disclaimer_accepted" | cut -d' ' -f2-)
        log_debug "您已于 ${accept_time} 接受免责声明，继续使用本工具。"
        return
    fi

    # 显示免责声明内容
    local msg
    msg=$(
        cat <<EOL

===============================================
                    免责声明                                      
===============================================
本工具按原样提供，使用者需自行承担风险。
开发者不对因使用本工具而产生的任何直接或间接损失负责。
===============================================

EOL
    )

    echo -e "${YELLOW}${msg}${NC}" >&2

    # 询问用户是否继续
    read -rp "是否继续使用本工具？(y/n): " choice
    case "$choice" in
    y | Y)
        # 创建配置目录
        if [ ! -d "$BLOG_TOOL_ENV" ]; then
            mkdir -p "$BLOG_TOOL_ENV"
        fi

        # 创建免责声明已接受的标记文件
        sudo touch "$BLOG_TOOL_ENV/disclaimer_accepted" >/dev/null 2>&1

        # 写入用户接受时间
        echo "用户接受时间: $(date +"%Y-%m-%d %H:%M:%S")" >"$BLOG_TOOL_ENV/disclaimer_accepted"
        log_info "您选择继续使用本工具。"
        ;;
    n | N)
        echo "已退出。"
        exit 0
        ;;
    *)
        echo "无效输入，已退出。"
        exit 1
        ;;
    esac
}

show_logo() {
    # 终端logo欢迎界面
    # https://patorjk.com/software/taag/#p=display&f=ANSI+Shadow&t=j+i+a+o+p+e+n+g+z+i&x=none&v=4&h=4&w=80&we=false

    # 打印访问地址
    local msg
    msg=$(
        cat <<EOL


         ██╗    ██╗     █████╗      ██████╗     ██████╗     ███████╗    ███╗   ██╗     ██████╗     ███████╗    ██╗
         ██║    ██║    ██╔══██╗    ██╔═══██╗    ██╔══██╗    ██╔════╝    ████╗  ██║    ██╔════╝     ╚══███╔╝    ██║
         ██║    ██║    ███████║    ██║   ██║    ██████╔╝    █████╗      ██╔██╗ ██║    ██║  ███╗      ███╔╝     ██║
    ██   ██║    ██║    ██╔══██║    ██║   ██║    ██╔═══╝     ██╔══╝      ██║╚██╗██║    ██║   ██║     ███╔╝      ██║
    ╚█████╔╝    ██║    ██║  ██║    ╚██████╔╝    ██║         ███████╗    ██║ ╚████║    ╚██████╔╝    ███████╗    ██║
     ╚════╝     ╚═╝    ╚═╝  ╚═╝     ╚═════╝     ╚═╝         ╚══════╝    ╚═╝  ╚═══╝     ╚═════╝     ╚══════╝    ╚═╝
                                                                                                              
EOL
    )

    msg+="\n    欢迎使用 blog-tool 部署脚本!\n"

    echo -e "${GREEN}${msg}${NC}" >&2
}
