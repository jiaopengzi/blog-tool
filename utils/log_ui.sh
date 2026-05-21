#!/bin/bash
# FilePath    : blog-tool/utils/log_ui.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 日志扩展函数, 包含免责声明与 logo 展示.

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
