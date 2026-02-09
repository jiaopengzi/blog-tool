#!/bin/bash
# FilePath    : blog-tool/utils/dir_file.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 目录和文件工具

# 为指定目录设置用户、组即权限
# 参数: $1: 用户
# 参数: $2: 组
# 参数: $3: 权限
# 参数: $4: 可变参数, 目录列表
# 用法: setup_directory 2000 2000 750 /path/to/dir1 /path/to/dir2 /path/to/dir3
setup_directory() {
    log_debug "run setup_directory"

    if [ $# -lt 4 ]; then
        echo "Usage: setup_directory <user> <group> <permissions> <dir1> [<dir2> ...]"
        return 1
    fi

    local user=$1
    local group=$2
    local permissions=$3
    shift 3 # 参数左移3位

    for dir_name in "$@"; do
        # 如果目录不存在则创建
        if [ ! -d "$dir_name" ]; then
            sudo mkdir -p "$dir_name" # 创建目录
        fi
        sudo chown -R "$user":"$group" "$dir_name" # 重新设置用户和组
        sudo chmod -R "$permissions" "$dir_name"   # 设置权限
        # sudo chown "$user":"$group" "$dir_name" # 重新设置用户和组(不递归,影响当前目录,不影响子目录和文件)
        # sudo chmod "$permissions" "$dir_name"   # 设置权限(不递归,影响当前目录,不影响子目录和文件)
    done
}

# 覆盖写入并为指定文件设置用户、组即权限
# 参数: $1: 用户
# 参数: $2: 组
# 参数: $3: 权限
# 参数: $4: 内容
# 参数: $5: 文件名
# 用法: over_write_set_owner 2000 2000 600 "content" /path/to/file
over_write_set_owner() {
    log_debug "run over_write_set_owner"

    if [ $# -ne 5 ]; then # 参数个数必须为5
        # 不等于5个参数提示如下
        echo "Usage: over_write_set_owner <user> <group> <permissions> <content> <filePath>"
        return 1
    fi

    local user=$1        # 用户
    local group=$2       # 组
    local permissions=$3 # 权限
    local content=$4     # 内容
    local filePath=$5    # 文件名

    echo "$content" | sudo tee "$filePath" >/dev/null # 写入文件
    sudo chown -R "$user:$group" "$filePath"          # 设置文件用户和组
    sudo chmod -R "$permissions" "$filePath"          # 设置文件权限
}

# 读取目录下的所有文件名到字符串变量中
# 参数: $1: 目录路径
# 用法: read_dir_basename_to_str /path/to/dir
read_dir_basename_to_str() {
    log_debug "run read_dir_basename_to_str"

    local dir_path=$1
    local file_list=""

    if [ -d "$dir_path" ]; then
        for file in "$dir_path"/*; do
            if [ -f "$file" ]; then
                file_name=$(sudo basename "$file")
                file_list+="$file_name "
            fi
        done
    else
        log_error "目录 $dir_path 不存在。"
        return 1
    fi

    echo "$file_list"
}

# 读取目录下的所有文件名为列表
# 参数: $1: 目录路径
# 用法: read_dir_basename_to_list /path/to/dir
read_dir_basename_to_list() {
    log_debug "run read_dir_basename_to_list"

    local dir="$1"
    local files=()
    for f in "$dir"/*; do
        files+=("$(sudo basename "$f")")
    done
    printf "%s\n" "${files[@]}"
}
