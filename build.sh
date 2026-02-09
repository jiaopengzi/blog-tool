#!/bin/bash
# FilePath    : blog-tool/main.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 将所有脚本合并为一个脚本

# 执行合并编译并上传到指定服务器
# bash build.sh && scp ../blog-tool-dev.sh ../blog-tool.sh ../blog-tool-billing-center.sh <user>@<host>:/home/<user>/

# shellcheck disable=SC1091

# 当前脚本所在目录绝对路径
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# # 当前脚本所在目录相对路径
# ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")"

source "$ROOT_DIR/options/_.sh"

# 定义输出文件
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
OUTPUT_FILE_DEV="$OUTPUT_DIR/blog-tool-dev.sh"                       # 开发版
OUTPUT_FILE_USER="$OUTPUT_DIR/blog-tool.sh"                          # 用户版
OUTPUT_FILE_BILLING_CENTER="$OUTPUT_DIR/blog-tool-billing-center.sh" # 计费中心版
DEV_SH="config/dev.sh"                                               # 开发配置文件路径
USER_SH="config/user.sh"                                             # 用户配置文件路径
USER_BILLING_CENTER_SH="config/user_billing_center.sh"               # 计费中心用户配置文件路径
LOG_SH="utils/log.sh"                                                # 日志记录脚本路径
COMMENT_SRC_TEXT="#"                                                 # 处理注释的源文本
COMMENT_TAR_TEXT="#!!!"                                              # 处理注释的目标文本

# 添加注释块
add_comment_block() {
    # 参数
    # $1: 源文件路径
    # $2: 目标文件路径

    local src_file=$1
    local target_file=$2

    # 判断源文件是否存在
    if [[ ! -f "$src_file" ]]; then
        echo "❌ 错误：源文件 ${src_file} 不存在" >&2
        exit 1
    fi

    # 读取 src 文件内容, 每行前加上 # 号, 写入 target_file
    while IFS= read -r line; do
        echo "# $line" >>"$target_file"
    done <"$src_file"
}

# 添加 /bin/bash 头和注释头
set_header() {
    local target_file=$1

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 先设置 shebang
    cat >"$target_file" <<-EOM
#!/bin/bash

EOM

    # 添加 LiCENSE 注释块
    add_comment_block "$ROOT_DIR/LICENSE" "$target_file"

    # 追加脚本元数据注释块
    cat >>"$target_file" <<-EOM

# Author       : jiaopengzi
# Blog         : https://jiaopengzi.com
# Description  : 博客 sh 工具

set -e

# 当前脚本所在目录绝对路径
ROOT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# # 当前脚本所在目录相对路径
# ROOT_DIR="\$(dirname "\${BASH_SOURCE[0]}")"

EOM
}

# 首先处理用户配置文件,将用户需要编辑的信息放到最开始
# 参数: $1: 目标文件
# 参数: $2: 用户配置文件路径
# 参数: $3: (可选)额外用户配置文件路径, 用于 dev 版同时合并 billing center 配置
handle_user() {

    local target_file=$1
    local user_config_file=$2
    local extra_config_file="${3:-}" # 可选的额外用户配置文件

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 优先添加用户配置文件内容
    if [ -f "$user_config_file" ]; then
        {
            printf "### content from %s\n" "$user_config_file"
            # 去掉头注释, 保留其他内容(从第一行到第一个空行)
            sed '1,/^$/d' "$user_config_file"
            printf "\n" # 添加空行以分隔内容
        } >>"$target_file"
    fi

    # 追加额外用户配置文件(紧跟主配置之后, log.sh 之前)
    if [ -n "$extra_config_file" ] && [ -f "$extra_config_file" ]; then
        {
            printf "### content from %s\n" "$extra_config_file"
            sed '1,/^$/d' "$extra_config_file"
            printf "\n"
        } >>"$target_file"
    fi

    # 日志记录比较底层, 放在靠前的位置
    if [ -f "$LOG_SH" ]; then
        {
            printf "### content from %s\n" "$LOG_SH"
            # 去掉头注释, 保留其他内容(从第一行到第一个空行)
            sed '1,/^$/d' "$LOG_SH"
            printf "\n" # 添加空行以分隔内容
        } >>"$target_file"
    fi
}

# 将 python 脚本进行 gzip 压缩并 base64 编码后嵌入到 shell 脚本中
base64_encode_py_scripts() {
    # python 脚本目录
    local py_dir="$1"

    # 输出的 shell 脚本文件
    local output_file="$2"

    # 遍历 python 目录下的所有 .py 文件
    for file in "$py_dir"/*.py; do
        # 获取文件名
        filename=$(basename "$file")

        # 跳过 test_ 前缀的文件
        if [[ "$filename" == test_*.py ]]; then
            continue
        fi

        if [ -f "$file" ]; then
            # 去掉拓展名,并且转为大写
            filename_no_ext="${filename%.py}"
            filename_no_ext_upper=$(echo "$filename_no_ext" | tr '[:lower:]' '[:upper:]')

            # 将python脚本内容进行 gzip 压缩再 base64 编码
            py_base64_content=$(gzip -c "$file" | base64 -w 0)

            # 写入到输出文件, 变量名格式为 PY_BASE64_<filename_no_ext_upper>
            echo "PY_BASE64_${filename_no_ext_upper}='${py_base64_content}'" >>"$output_file"
        fi
    done
}

# 根据构建类型获取需要合并的目录列表(目录顺序决定了脚本加载顺序, 存在依赖关系)
# 参数: $1: 构建类型 dev | user | billing_center
get_build_dirs() {
    local build_type="$1"

    case "$build_type" in
    billing_center) echo "config options utils system docker db billing-center" ;;
    user) echo "config options utils system docker db server client" ;;
    *) echo "config options utils system docker db billing-center server client" ;; # dev 版包含所有目录
    esac
}

# 判断文件是否应该跳过合并(返回 0 表示跳过, 返回 1 表示保留)
# 参数: $1: 文件路径, $2: 文件名, $3: 所属目录, $4: 构建类型
should_skip_file() {
    local file="$1"
    local filename="$2"
    local dir="$3"
    local build_type="$4"

    # 跳过已单独处理的文件(用户配置文件、日志脚本)和模块入口文件 _.sh
    case "$file" in
    "$USER_SH" | "$USER_BILLING_CENTER_SH" | "$LOG_SH") return 0 ;;
    esac
    [[ "$filename" == "_.sh" ]] && return 0

    # 非开发版跳过开发配置文件
    [[ "$file" == "$DEV_SH" && "$build_type" != "dev" ]] && return 0

    # 按构建类型跳过不需要的数据库文件
    if [[ "$dir" == "db" ]]; then
        case "$build_type" in
        # 计费中心版跳过 es 和 redis(pgsql.sh 包含 billing_center 依赖的公共函数)
        billing_center) [[ "$filename" == "es.sh" || "$filename" == "redis.sh" ]] && return 0 ;;
        # 用户版跳过 billing_center 相关数据库文件
        user) [[ "$filename" == "pgsql_billing_center.sh" || "$filename" == "redis_billing_center.sh" ]] && return 0 ;;
        esac
    fi

    return 1
}

# 追加单个脚本文件内容到目标文件(去除头部注释和 source 行)
# 参数: $1: 源文件路径, $2: 目标文件路径
append_script_content() {
    local file="$1"
    local target_file="$2"

    [[ ! -f "$file" ]] && return 0

    {
        printf "### content from %s\n" "$file"
        # 去除头部注释(从第一行到第一个空行)和 source 开头的行, 追加到目标文件
        sed '1,/^$/d' "$file" | grep -vE '^\s*source'
        printf "\n" # 添加空行以分隔各文件内容
    } >>"$target_file"
}

# 处理其他脚本文件
handle_other() {
    local target_file=$1
    local build_type="${2:-dev}" # 构建类型: dev | user | billing_center

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 获取当前构建类型对应的目录列表
    local dirs_str
    dirs_str=$(get_build_dirs "$build_type")
    read -r -a DIRS <<<"$dirs_str"

    # 遍历目录并合并文件
    for dir in "${DIRS[@]}"; do
        [[ ! -d "$dir" ]] && continue
        for file in "$dir"/*.sh; do
            local filename
            filename=$(basename "$file")

            # 判断是否需要跳过
            should_skip_file "$file" "$filename" "$dir" "$build_type" && continue

            # 追加文件内容到目标文件
            append_script_content "$file" "$target_file"
        done
    done
}

# 追加主函数
append_main() {

    local target_file=$1
    local build_type="${2:-dev}" # 构建类型: dev | user | billing_center

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 选项数组
    local options_array="OPTIONS_ALL[@]"

    # 函数校验数组
    local options_array_valid="OPTIONS_ALL[@]"

    if [ "$build_type" == "user" ]; then
        options_array="OPTIONS_USER[@]"
        # 合并数组用于校验
        options_array_valid="OPTIONS_USER_VALID[@]"
    elif [ "$build_type" == "billing_center" ]; then
        options_array="OPTIONS_BILLING_CENTER[@]"
        # 合并数组用于校验
        options_array_valid="OPTIONS_BILLING_CENTER_VALID[@]"
    fi

    cat >>"$target_file" <<-EOM
main() {
    # 免责声明
    disclaimer_msg
    # 检查
    check

    # 没有参数情况显示选项
    if [ \$# -eq 0 ]; then
        # 显示 logo 欢迎界面
        show_logo

        # 打印选项
        print_options "\$DISPLAY_COLS" "\${$options_array}"

        # 处理用户输入
        handle_user_input "\${$options_array}"
    else
        # 校验是否是有效函数,
        for arg in "\$@"; do
            if func=\$(is_valid_func $options_array_valid "\$arg"); then
                exec_func "\$func"
            else
                echo "未找到与输入匹配的函数名称: \$arg"
            fi
        done
    fi
}

# 调用主函数
main "\$@"

EOM
}

# 获取数组行起止行号
# 参数: $1: 目标文件
# 参数: $2: startMarker 起始标记
# 参数: $3: endMarker 结束标记
getLine() {
    local target_file=$1      # 目标文件
    local startMarker=$2      # 起始标记
    local endMarker=$3        # 结束标记
    local start_line end_line # 起止行号

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 判断起始和结束标记是否为空
    if [[ -z "$startMarker" || -z "$endMarker" ]]; then
        echo "❌ 错误：起始标记和结束标记不能为空" >&2
        exit 1
    fi

    # 匹配开始行
    start_line=$(grep -n "^${startMarker}" "$target_file" | cut -d: -f1)
    if [[ -z "$start_line" ]]; then
        echo "❌ 错误：开始标记 ${startMarker} 未找到" >&2
        exit 1
    fi

    # 匹配结束闭合行
    end_line=$start_line
    local line_count=$((start_line))
    while IFS= read -r line; do
        if [[ $line == "$endMarker" ]] && [[ $line_count -gt $start_line ]]; then
            end_line=$line_count
            break
        fi

        ((line_count++))
    done <<<"$(tail -n+"$start_line" "$target_file")"

    if [[ -z "$end_line" ]]; then
        echo "❌ 错误：结束标记 ${endMarker} 未闭合" >&2
        exit 1
    fi

    echo "$start_line $end_line"
}

# 获取函数起止行号
# 参数: $1: 目标文件
# 参数: $2: 函数名
getFuncLine() {
    local target_file=$1      # 目标文件
    local func_name=$2        # 函数名
    local start_line end_line # 起止行号

    local startMarker="${func_name}()" # 函数起始标记
    local endMarker="}"                # 函数结束标记

    # 使用 getLine 函数获取起止行号
    line_info=$(getLine "$target_file" "$startMarker" "$endMarker")
    echo "$line_info"
}

# 删除指定行范围
# 参数: $1: 目标文件
# 参数: $2: 起始行号
# 参数: $3: 结束行号
removeLine() {
    local target_file=$1
    local start_line=$2
    local end_line=$3

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 校验行号是否合法
    if ! [[ "$start_line" =~ ^[0-9]+$ ]] || ! [[ "$end_line" =~ ^[0-9]+$ ]] || [[ $start_line -gt $end_line ]]; then
        echo "❌ 错误：行号不合法" >&2
        exit 1
    fi

    # 使用sed删除行并保存（原子操作）
    sed -i "${start_line},${end_line}d" "$target_file"
}

# 删除数组定义
# 参数: $1: 目标文件
# 参数: $2: 数组名称
removeArrayLines() {
    local target_file=$1
    local array_name=$2

    local startMarker="$array_name=("
    local endMarker=")"

    # 获取行号
    line_info=$(getLine "$target_file" "$startMarker" "$endMarker")
    read -r start_line end_line <<<"$line_info"

    # 删除行
    removeLine "$target_file" "$start_line" "$end_line"
}

# 移除整行注释(简单两步：匹配头部规则则保留, 否则删除整行注释)
# 用法示例：
# removeLineComments "$SRC_FILE" '^#!|^# (FilePath|Author|Blog|Copyright|Description|shellcheck)'
removeLineComments() {
    local target_file=$1

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 删除单独注释行, 但保留：
    #   - shebang: ^#!
    #   - 元数据注释: ^# (FilePath|Author|Blog|Copyright|Description)
    #   - 保留行内注释(如 echo ... # xxx)

    sed -i -E \
        -e '/^[[:space:]]*#!/b' \
        -e '/^[[:space:]]*# (FilePath|Author|Blog|Copyright|Description|shellcheck)/b' \
        -e '/^[[:space:]]*#/d' \
        "$target_file"
}

# 函数：获取文件中所有 Heredoc 块的起始和结束行号
# 参数:
#   $1 - 目标文件路径(必需)
#   $2 - (可选)要查找的 heredoc 分隔符, 如 "EOF" 或 "EOM"; 如果不传, 则默认同时查找 "EOF" 和 "EOM"
# 输出:
#   打印所有 heredoc 块的信息, 格式为：分隔符:起始行-结束行
getAllHeredocLine() {
    local target_file="$1"
    local delimiters_to_find="${2:-EOF EOM}"

    # 校验文件
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 '$target_file' 不存在" >&2
        return 1
    fi

    # 分割为数组
    read -r -a delims <<<"$delimiters_to_find"

    local -a results=()
    local line_number=0
    local in_heredoc=false
    local current_delimiter=""
    local current_start_line=0

    # 逐行读取文件直到结束
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))

        if ! $in_heredoc; then
            # 检查是否为 heredoc 开始(支持 <<DELIM, <<-DELIM, <<'DELIM', <<-"DELIM" 等)
            for delim in "${delims[@]}"; do
                # 构建正则：<< 或 <<-, 可跟单/双引号或无引号, 后接 delim
                regex="<<-?['\"]?${delim}['\"]?\\b"
                if [[ $line =~ $regex ]]; then
                    in_heredoc=true
                    current_delimiter="$delim"
                    current_start_line=$line_number
                    break
                fi
            done
        else
            # 寻找对应的结束行：行必须严格等于 delimiter(不允许前后空白)
            if [[ "$line" == "$current_delimiter" ]]; then
                # results+=("${current_delimiter}:${current_start_line}-$line_number")
                results+=("${current_delimiter}:${current_start_line}-${line_number}")
                in_heredoc=false
                current_delimiter=""
                current_start_line=0
            fi
        fi
    done <"$target_file"

    # 如果文件以未闭合的 heredoc 结束, 给出提示
    if $in_heredoc; then
        echo "⚠️  警告：文件 '$target_file' 中以未闭合的 heredoc 结束(起始行: $current_start_line, delimiter: $current_delimiter)" >&2
    fi

    # 输出结果
    if [[ ${#results[@]} -eq 0 ]]; then
        echo "ℹ️  未在文件 '$target_file' 中找到任何 Heredoc 块(查找的分隔符: $delimiters_to_find)"
        return 0
    fi

    for entry in "${results[@]}"; do
        echo "$entry"
    done
}

# 标记替换 Heredoc 块中的指定的内容
# 参数:
#   $1 - 目标文件路径
#   $2 - 源文本
#   $3 - 目标文本
#   $4 - (可选)要查找的 heredoc 分隔符, 如 "EOF" 或 "EOM"; 如果不传, 则默认同时查找 "EOF"、 "EOM" 和 "EOL"
replaceHeredoc() {
    local target_file="$1"                       # 目标文件路径
    local srcText="$2"                           # 源文本
    local tarText="$3"                           # 目标文本
    local delimiters_to_find="${4:-EOF EOM EOL}" # 要查找的 heredoc 分隔符, 默认同时查找 EOF 和 EOM 和 EOL

    # 校验文件
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 '$target_file' 不存在" >&2
        return 1
    fi

    # 拿到所有 heredoc 块的信息
    local allHeredocItem
    allHeredocItem=$(getAllHeredocLine "$target_file" "$delimiters_to_find")

    # 循环输出结果
    while IFS= read -r line; do
        # 每行示例 EOM:17-49, 分隔符:起始行-结束行, 按照这个格式解析
        IFS=':-' read -r delim start_line end_line <<<"$line"

        # echo "  分隔符: $delim, 起始行: $start_line, 结束行: $end_line"

        # 替换指定行范围内的内容
        sed -i "${start_line},${end_line}s/$srcText/$tarText/g" "$target_file"

    done <<<"$allHeredocItem"
}

# 处理注释的主函数
handle_heredoc_comments() {
    local target_file="$1"
    local srcText="$2" # 源文本
    local tarText="$3" # 目标文本

    # 校验文件
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 '$target_file' 不存在" >&2
        return 1
    fi

    # 标记替换 Heredoc 块中的注释内容
    replaceHeredoc "$target_file" "$srcText" "$tarText"

    # 删除整行注释
    removeLineComments "$target_file"

    # 恢复 Heredoc 块中的注释内容
    replaceHeredoc "$target_file" "$tarText" "$srcText"
}

# 移除目标文件中不需要的函数
# 参数: $1: 目标文件
# $2...: 需要保留的选项数组名称(如 OPTIONS_USER OPTIONS_USER_NOT_SHOW)
remove_not_needed_funcs() {
    local target_file=$1
    shift

    # 1、提取 OPTIONS_ALL 中的所有函数名, 存入数组 all_funcs
    local -a all_funcs=()
    for item in "${OPTIONS_ALL[@]}"; do
        all_funcs+=("${item#*:}")
    done

    # 2、提取需要保留的选项数组中的所有函数名, 存入数组 keep_funcs
    local -a keep_funcs=()
    for array_name in "$@"; do
        local -n arr="$array_name"
        for item in "${arr[@]}"; do
            keep_funcs+=("${item#*:}")
        done
    done

    # 3、找出在 all_funcs 中但不在 keep_funcs 中的函数名并移除
    for func in "${all_funcs[@]}"; do
        local found=false
        for k_func in "${keep_funcs[@]}"; do
            if [[ "$func" == "$k_func" ]]; then
                found=true
                break
            fi
        done
        if ! $found; then
            line_info=$(getFuncLine "$target_file" "$func" 2>/dev/null) || continue
            read -r start_line end_line <<<"$line_info"
            if [[ -n "$start_line" && -n "$end_line" ]]; then
                removeLine "$target_file" "$start_line" "$end_line"
            fi
        fi
    done
}

# 移除多余的空行(连续多个空行只保留一个)
removeBlankLine() {
    local target_file=$1

    # 校验目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 删除多余的空行(连续多个空行只保留一个)
    sed -i '/^$/N;/^\n$/D' "$target_file"

    # 末尾确保只有一个空行
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$target_file"
}

# 非开发版的注释处理和日志级别调整
# 参数: $1: 目标文件
build_non_dev_cleanup() {
    local target_file="$1"

    # 处理heredoc中的注释
    handle_heredoc_comments "$target_file" "$COMMENT_SRC_TEXT" "$COMMENT_TAR_TEXT"

    # 恢复用户配置文件中的注释标记
    sed -i "s/$COMMENT_TAR_TEXT/$COMMENT_SRC_TEXT/g" "$target_file"

    # 将日志级别改为 info
    sed -i "s/LOG_LEVEL=\"debug\"/LOG_LEVEL=\"info\"/g" "$target_file"
}

# 按构建类型移除不需要的函数
# 参数: $1: 目标文件
# 参数: $2: 构建类型
build_remove_unused_funcs() {
    local target_file="$1"
    local build_type="$2"

    if [ "$build_type" == "user" ]; then
        remove_not_needed_funcs "$target_file" OPTIONS_USER OPTIONS_USER_NOT_SHOW
    elif [ "$build_type" == "billing_center" ]; then
        remove_not_needed_funcs "$target_file" OPTIONS_BILLING_CENTER OPTIONS_BILLING_CENTER_NOT_SHOW
    fi
    # dev 版保留所有函数, 无需移除
}

# 按构建类型移除不需要的数组定义
# 参数: $1: 目标文件
# 参数: $2: 构建类型
build_remove_unused_arrays() {
    local target_file="$1"
    local build_type="$2"

    # 定义每种构建类型需要移除的数组
    local -a arrays_to_remove=()

    if [ "$build_type" == "user" ]; then
        arrays_to_remove=(OPTIONS_ALL OPTIONS_BILLING_CENTER OPTIONS_BILLING_CENTER_NOT_SHOW OPTIONS_BILLING_CENTER_VALID)
    elif [ "$build_type" == "billing_center" ]; then
        arrays_to_remove=(OPTIONS_ALL OPTIONS_USER OPTIONS_USER_NOT_SHOW OPTIONS_USER_VALID)
    else
        arrays_to_remove=(OPTIONS_USER OPTIONS_USER_NOT_SHOW OPTIONS_USER_VALID OPTIONS_BILLING_CENTER OPTIONS_BILLING_CENTER_NOT_SHOW OPTIONS_BILLING_CENTER_VALID)
    fi

    for array_name in "${arrays_to_remove[@]}"; do
        removeArrayLines "$target_file" "$array_name"
    done
}

# 构建函数
# 参数: $1: 目标文件
# 参数: $2: 构建类型, 可选参数, 默认为 dev; dev | user | billing_center
build() {
    local target_file="$1"       # 目标文件
    local build_type="${2:-dev}" # 构建类型: dev | user | billing_center

    # 校验文件
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 '$target_file' 不存在" >&2
        return 1
    fi

    # 设置头部
    set_header "$target_file"

    # 根据构建类型选择用户配置文件
    if [ "$build_type" == "billing_center" ]; then
        handle_user "$target_file" "$USER_BILLING_CENTER_SH"
    elif [ "$build_type" == "dev" ]; then
        # dev 版合并两个用户配置文件, billing center 配置紧跟 user 配置之后、log.sh 之前
        handle_user "$target_file" "$USER_SH" "$USER_BILLING_CENTER_SH"
    else
        handle_user "$target_file" "$USER_SH"
    fi
    if [ "$build_type" != "dev" ]; then
        # 替换用户配置文件中的注释标记, 防止被移除
        sed -i "s/$COMMENT_SRC_TEXT/$COMMENT_TAR_TEXT/g" "$target_file"
    fi

    # 嵌入 python 脚本
    base64_encode_py_scripts "$ROOT_DIR/python" "$target_file"

    # 处理其他脚本文件
    handle_other "$target_file" "$build_type"

    # 追加主函数
    append_main "$target_file" "$build_type"

    # 非开发版: 注释清理、日志级别调整、移除多余函数
    if [ "$build_type" != "dev" ]; then
        build_non_dev_cleanup "$target_file"
        build_remove_unused_funcs "$target_file" "$build_type"
    fi

    # 移除不需要的数组定义
    build_remove_unused_arrays "$target_file" "$build_type"

    # 移除多余的空行
    removeBlankLine "$target_file"

    echo "合并完成, 输出文件：$target_file"
}

# 执行构建
main() {
    mkdir -p "$OUTPUT_DIR"

    # 不存在则创建输出文件
    if [[ ! -f "$OUTPUT_FILE_DEV" ]]; then
        touch "$OUTPUT_FILE_DEV"
    fi

    if [[ ! -f "$OUTPUT_FILE_USER" ]]; then
        touch "$OUTPUT_FILE_USER"
    fi

    if [[ ! -f "$OUTPUT_FILE_BILLING_CENTER" ]]; then
        touch "$OUTPUT_FILE_BILLING_CENTER"
    fi

    # 构建开发版
    build "$OUTPUT_FILE_DEV" "dev"

    # 构建用户版
    build "$OUTPUT_FILE_USER" "user"

    # 构建计费中心版
    build "$OUTPUT_FILE_BILLING_CENTER" "billing_center"
}

# 入口函数
main
