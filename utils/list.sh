#!/bin/bash
# FilePath    : blog-tool/utils/list.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 列表相关工具

# 按照指定前缀和数量生成节点并排除指定节点
# echo $(generate_items_exclude es 1 3) # 输出 es-02,es-03
# echo $(generate_items_exclude es 2 3) # 输出 es-01,es-03
# echo $(generate_items_exclude es 3 3) # 输出 es-01,es-02
generate_items_exclude() {
    log_debug "run generate_items_exclude"

    local prefix=$1        # 前缀
    local exclude_index=$2 # 排除的索引
    local count=$3         # 总的数量
    local result=""

    for ((i = 1; i <= count; i++)); do
        if ((i != exclude_index)); then
            formattedI=$(printf "%02d" $i)
            result+="$prefix-$formattedI,"
        fi
    done

    # 去掉最后一个逗号
    result=${result%,}

    echo "$result"
}

# 按照指定前缀和数量生成所有节点
# echo $(generate_items_al es 3) # 输出 es-01,es-02,es-03
generate_items_all() {
    log_debug "run generate_items_all"
    
    local prefix=$1 # 前缀
    local count=$2  # 总的数量
    local result=""

    for ((i = 1; i <= count; i++)); do
        formattedI=$(printf "%02d" $i)
        result+="$prefix-$formattedI,"
    done

    # 去掉最后一个逗号
    result=${result%,}

    echo "$result"
}
