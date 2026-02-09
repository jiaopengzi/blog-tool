#!/bin/bash
# FilePath    : blog-tool/utils/yaml.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : yaml 相关工具

# update_yaml_block 更新 YAML 文件中指定的 `key: |` 多行字符串块内容
# 用法：update_yaml_block "yaml文件路径" "yaml_key_line" "新内容文本文件路径"
#   - yaml_key_line: 如 "key: |" (必须与 YAML 文件中完全一致, 包括缩进！)
#   - 新内容文本文件路径：每行内容会被自动加上与 key: | 相同的缩进
update_yaml_block() {
    local YAML_FILE="$1"
    local YAML_KEY_LINE="$2"
    local NEW_CONTENT_FILE="$3"

    # ===== 检查传入参数是否为空 =====
    if [[ -z "$YAML_FILE" || -z "$YAML_KEY_LINE" || -z "$NEW_CONTENT_FILE" ]]; then
        echo "❌ 错误：请提供 YAML 文件路径、YAML key 行(如 'key: |')、以及新内容文件路径"
        echo "   用法: update_yaml_block \"yaml文件路径\" \"yaml_key_line\" \"新内容文件路径\""
        return 1
    fi

    # ===== 检查文件是否存在 (使用 sudo) =====
    if ! sudo test -f "$YAML_FILE"; then
        echo "❌ 错误：YAML 文件不存在: $YAML_FILE"
        return 1
    fi

    if ! sudo test -f "$NEW_CONTENT_FILE"; then
        echo "❌ 错误：新内容文件不存在: $NEW_CONTENT_FILE"
        return 1
    fi

    # ===== 查找 `key: |` 所在行 =====
    local KEY_LINE_NUM
    KEY_LINE_NUM=$(sudo grep -n "^${YAML_KEY_LINE}$" "$YAML_FILE" | sudo cut -d: -f1)

    if [[ -z "$KEY_LINE_NUM" ]]; then
        echo "❌ 错误：未找到 YAML key 行: '$YAML_KEY_LINE', 请确认格式与文件中完全一致(包括缩进！)"
        return 1
    fi

    # echo "✅ 找到目标 key 行: '$YAML_KEY_LINE', 位于第 $KEY_LINE_NUM 行"

    # ===== 获取块内容起始行 =====
    local BLOCK_START_LINE=$((KEY_LINE_NUM + 1))
    local TOTAL_LINES
    TOTAL_LINES=$(sudo cat "$YAML_FILE" | wc -l | awk '{print $1}')

    if [[ $BLOCK_START_LINE -gt $TOTAL_LINES ]]; then
        echo "❌ 错误：未找到 YAML key 行: '$YAML_KEY_LINE'的下一行不存在, 可能格式错)"
        return 1
    fi

    # 获取块起始行内容, 用于计算缩进
    local BLOCK_START_LINE_CONTENT
    BLOCK_START_LINE_CONTENT=$(sudo sed -n "${BLOCK_START_LINE}p" "$YAML_FILE")

    # 计算缩进(连续的空格)
    local INDENT=""
    local i char
    for ((i = 0; i < ${#BLOCK_START_LINE_CONTENT}; i++)); do
        char="${BLOCK_START_LINE_CONTENT:$i:1}"
        if [[ "$char" == " " ]]; then
            INDENT="${INDENT}${char}"
        else
            break
        fi
    done

    # local INDENT_LEN=${#INDENT}
    # echo "✅ 检测到缩进(来自块内容起始行): 共 $INDENT_LEN 个空格"

    # ===== 为新块内容的每一行添加缩进 =====
    local NEW_CONTENT_RAW
    NEW_CONTENT_RAW=$(sudo cat "$NEW_CONTENT_FILE" 2>/dev/null)

    if [[ -z "$NEW_CONTENT_RAW" ]]; then
        echo "❌ 错误：无法读取新内容文件 '$NEW_CONTENT_FILE'，请检查文件权限"
        return 1
    fi

    # ===== 为每一行添加缩进 =====
    local FORMATTED_BLOCK=""
    while IFS= read -r line; do
        FORMATTED_BLOCK+="${INDENT}${line}"$'\n'
    done <<<"$NEW_CONTENT_RAW"

    # ===== 使用 awk 进行精准替换, 仅替换匹配缩进的 key 块 =====
    local TMP_FILE
    TMP_FILE=$(sudo mktemp)

    if sudo awk -v start_line="$BLOCK_START_LINE" \
        -v indent="$INDENT" \
        -v new_cert="$FORMATTED_BLOCK" \
        '
    BEGIN {
        in_cert_block = 0
        replaced = 0
    }

    NR < start_line {
        print
    }

    NR == start_line {
        # 检查此行是否有我们预期的缩进, 以确认是目标块内容起始行
        current_indent = ""
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == " ") {
                current_indent = current_indent c
            } else {
                break
            }
        }
        if (current_indent == indent) {
            # 是目标缩进, 进行替换
            print new_cert
            in_cert_block = 1
            replaced = 1
        } else {
            # 缩进不对, 原样输出, 不替换
            print
        }
    }

    NR > start_line {
        if (in_cert_block == 1) {
            # 检查是否还处于同一缩进块内
            current_indent = ""
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == " ") {
                    current_indent = current_indent c
                } else {
                    break
                }
            }
            if (current_indent == indent) {
                # 仍是缩进块内, 已被新块内容替代, 所以这里不打印
                # 即跳过原 YAML 中的这些行
            } else {
                # 缩进已改变, 内容块结束, 恢复打印
                in_cert_block = 0
                print $0
            }
        } else {
            # 不在块中, 正常打印
            print $0
        }
    }
    ' "$YAML_FILE" | sudo tee "$TMP_FILE" >/dev/null; then
        # 备份原文件
        sudo cp "$YAML_FILE" "${YAML_FILE}.bak"
        # 替换原文件
        sudo mv "$TMP_FILE" "$YAML_FILE"
        echo "✅ 成功更新 YAML 文件中到 YAML key 行: '$YAML_KEY_LINE' 的多行字符串块内容"
        echo "📂 原文件已备份为: ${YAML_FILE}.bak"
    else
        echo "❌ 替换失败"
        sudo rm -f "$TMP_FILE"
        return 1
    fi
}

# update_yaml_block "/home/jiaopengzi/test/es.yaml" "ca_cert: |" "/home/jiaopengzi/cert_ca_es/ca.crt"
