#!/bin/bash
# FilePath    : blog-tool/utils/print.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 打印选项相关工具

# 设置环境变量
export LC_ALL=C.UTF-8

# 计算中文字符和英文字符数量
count_chars() {
    local text="$1"

    # 匹配中文字符(CJK Unified Ideographs)
    local chn_chars
    chn_chars=$(echo -n "$text" | grep -oP '\p{Han}' | wc -l)

    # 匹配英文字符
    local eng_chars
    eng_chars=$(echo -n "$text" | grep -oP '[a-zA-Z0-9]' | wc -l)

    echo "$chn_chars $eng_chars"
}

# 打印分隔线
print_dividers() {
    local start_delimiter=$1 # 开始分隔符
    local col_length=$2      # 列宽
    local cols=$3            # 列数
    local delimiter=$4       # 分隔符
    local line=''            # 初始化分隔线

    # 构造分隔线
    line+="$start_delimiter"
    for ((c = 0; c < cols; c++)); do
        for ((i = 0; i < col_length; i++)); do
            line+="$delimiter"
        done
        line+="$start_delimiter"
    done

    # 打印分隔线
    printf '%s\n' "$line"
}

# 检查是否为 UTF-8 编码
check_utf8() {
    local locale_output
    locale_output=$(locale | head -n 1)
    local value
    value=$(echo "$locale_output" | cut -d '=' -f 2)
    if echo "$value" | grep -q "UTF-8"; then
        echo true
    else
        echo false
    fi
}

###
# @description: 打印选项, 并添加边框
# @param {int} $1: 显示列数
# @param {array} $2...: 选项数组
###
print_options() {
    local display_cols="$1"
    shift

    local options=("$@")                                      # 选项数组
    local count=${#options[@]}                                # 选项数量
    local rows=$(((count + display_cols - 1) / display_cols)) # 行数
    local cell_width=50                                       # 每个单元格的宽度
    local custom_width=6                                      # 自定义宽度 主要是为了显示序号和空格
    local col_length=$((cell_width + custom_width - 1))       # 列宽

    # 打印表头边框
    print_dividers "+" $col_length "$display_cols" "-"

    # 循环打印选项
    for ((row = 0; row < rows; row++)); do
        printf '|' # 每行开始打印左边框
        for ((col = 0; col < display_cols; col++)); do
            local idx=$((row + rows * col))
            if ((idx < count)); then
                local option="${options[$idx]}"
                local option_name="${option%%:*}" # 提取选项名称
                local chn_count
                read -r chn_count _ <<<"$(count_chars "$option_name")"

                # 如果 check_utf8 为真, 说明是 UTF-8 编码, 不需要计算中文字符数量
                if [ "$(check_utf8)" == true ]; then
                    words=$((cell_width + chn_count))
                else
                    words=$((cell_width + chn_count / 3)) # 一个中文字符占 3 个英文字符的位置 计算补齐占位符数量
                fi

                # 打印选项, 左对齐并填充空格
                printf " %02d " $idx                    # 打印序号
                printf " %-*s|" "$words" "$option_name" # 左对齐内容

                # 使用 + 填充字符串
                # printf -v filled "%-*s" 24 "$option_name"
                # printf -v filled "%-*s" $repeat "$option_name"
                # filled="${filled// /+}"
                # echo -n "$filled"
            else
                # 空单元格 减 1 是为了补齐边框 右边框 |
                printf '%*s|' $col_length ""
            fi
        done
        # 在每行之后打印分隔线, 除了最后一行
        echo
        if [ "$row" -lt "$((rows - 1))" ]; then
            print_dividers "+" $col_length "$display_cols" "-"
        fi
    done

    # 打印表尾边框
    print_dividers "+" $col_length "$display_cols" "-"
    echo
}

# 退出脚本
exit_script() {
    # 脚本退出时删除临时文件
    rm -f "${PY_SCRIPT_FILE}"

    log_info "退出脚本"

    exit 0
}

# 判断函数名称是否在 options 数组中, 用于检查用户输入是否有效
is_valid_func() {
    local options=("${!1}")
    local func_name="$2"
    for option in "${options[@]}"; do
        IFS=":" read -r _ function_name <<<"$option"
        if [ "$func_name" == "$function_name" ]; then
            echo "$function_name"
            return 0
        fi
    done
    return 1
}

# 执行函数
exec_func() {
    local func="$1"
    if declare -f "$func" >/dev/null; then
        $func
    else
        log_error "找不到对应的函数：$func"
        exit 1
    fi
}

###
# @description: 获取用户输入并执行相应的函数
# @param {array} $1: 选项数组
###
handle_user_input() {
    local options=("$@")
    # 读取用户输入
    read -r -p "请输入工具所在的序号[0-$((${#options[@]} - 1))] 或者直接输入函数名称: " raw_choice
    # 检查输入是否为数字
    if [[ $raw_choice =~ ^0*[0-9]+$ ]]; then
        # 十进制去除前导零并转换为整数
        choice=$(printf "%d\n" $((10#$raw_choice)) 2>/dev/null)
        # 检查用户输入是否在有效范围内
        if ((choice < 0 || choice >= ${#options[@]})); then
            echo "请输入正确的选项序号"
            exit 1
        fi
        # 查找对应的函数名
        option="${options[$choice]}"
        func_name="${option##*:}" # 提取函数名称
    else
        # 输入不是数字, 尝试匹配函数名称
        func_name=""

        for option in "${options[@]}"; do
            if [[ "${option##*:}" == "$raw_choice" ]]; then
                func_name="$raw_choice"
                break
            fi
        done
        if [[ -z "$func_name" ]]; then
            echo "未找到与输入匹配的函数名称"
            exit 1
        fi

    fi
    # 执行对应的函数
    exec_func "$func_name"
}

# 函数：读取用户输入, 返回标准化的结果
# 参数：
#   1. prompt_text - 提示文本
#   2. default_value - 默认值
# 返回: 用户输入的值(标准化为小写)
read_user_input() {
    local prompt_text=$1
    local default_value=$2
    local user_input=""

    # 预处理提示文本，将 \n 替换为实际换行
    # 使用 bash 的字符串替换功能
    local formatted_prompt="${prompt_text//\\n/$'\n'}"

    # 使用 read -p 与格式化后的提示文本
    read -r -p "$formatted_prompt" user_input

    # 如果用户没有输入, 使用默认值
    if [ -z "$user_input" ]; then
        user_input=$default_value
    fi

    # 将输入转换为小写
    user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

    # 返回用户输入
    echo "$user_input"
}
