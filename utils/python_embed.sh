#!/bin/bash
# FilePath    : blog-tool/python/embed.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : python 脚本嵌入与提取

# # 解码并解压嵌入的 Python 脚本写入指定目录
# base64_decode_py_scripts_to_dir() {
#     local output_dir="./python"

#     # 判断输出目录是否存在, 不存在则创建
#     if [ ! -d "$output_dir" ]; then
#         mkdir -p "$output_dir"
#     fi

#     # 历遍当前脚本文件中的所有嵌入的 python 脚本变量
#     grep -oP '^py_base64_\K[^(=]+' "$0" | while read -r py_file_name; do
#         log_debug "正在解码并解压脚本: $py_file_name"
#         var_name="py_base64_${py_file_name}"

#         # 解码并解压到临时文件, 注意 !var_name 为变量名取值
#         echo "${!var_name}" | base64 -d | gzip -d >"$output_dir/$py_file_name.py"
#     done
# }

# 解码并解压指定嵌入的 Python 脚本变量内容
decode_py_base64_main() {
    log_debug "run decode_py_base64_main"
    # 读取变量 PY_BASE64_MAIN 解码并解压, 保存到文件
    echo "${PY_BASE64_MAIN}" | base64 -d | gzip -d >"${PY_SCRIPT_FILE}"
}

# 提取 changelog 中指定版本的变更日志块
extract_changelog_block() {
    log_debug "run extract_changelog_block"

    # $1: changelog 文件路径
    # $2: 版本号
    local changelog_file="$1"
    local changelog_version="$2"

    # 可选：检查文件是否成功写入
    if [[ ! -s "${PY_SCRIPT_FILE}" ]]; then
        log_error "解码后的 Python 脚本文件为空或不存在"
        exit 1
    fi

    log_debug "解码后的 Python 脚本文件已创建: ${PY_SCRIPT_FILE}"

    python3 "${PY_SCRIPT_FILE}" extract_changelog_block "$changelog_file" "$changelog_version"
}

# 提取 changelog 中指定版本的发布日期
extract_changelog_version_date() {
    log_debug "run extract_changelog_version_date"

    # $1: changelog 文件路径
    local changelog_file="$1"

    # 可选：检查文件是否成功写入
    if [[ ! -s "${PY_SCRIPT_FILE}" ]]; then
        log_error "解码后的 Python 脚本文件为空或不存在"
        exit 1
    fi

    log_debug "解码后的 Python 脚本文件已创建: ${PY_SCRIPT_FILE}"

    python3 "${PY_SCRIPT_FILE}" extract_changelog_version_date "$changelog_file"
}
