#!/bin/bash
# FilePath    : blog-tool/docker/mirror.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : Docker 镜像源测速脚本

DOCKER_CE_TEST_DOWNLOAD_FILE="linux/$(get_docker_repo_path)/gpg" # 测试文件路径(相对于镜像源根目录)

# 测试并找出最快的 Docker CE 镜像源 (并发抢占式版本)
find_fastest_docker_mirror() {
    # 创建临时目录来存储每个任务的结果, 并确保脚本退出时清理
    local temp_dir
    temp_dir=$(mktemp -d)

    # 在函数退出时清理临时目录
    trap 'rm -rf "$temp_dir"' EXIT

    # 关联数组: PID -> Source URL
    declare -A pids_to_sources
    log_info "正在启动对所有 Docker CE 镜像源进行并发测速..."

    # 1. 并发启动所有测试任务
    for item in "${DOCKER_CE_SOURCES[@]}"; do
        log_debug "启动测试任务 for source: $item"
        local source
        # 按 '|' 分割为 URL 和 描述，避免参数扩展在复杂字符串下出错
        IFS='|' read -r source _ <<<"$item"

        # 为每个源创建一个唯一的输出文件
        # 将URL中的非字母数字字符替换为下划线, 以避免文件名问题
        local sanitized_source
        sanitized_source="${source//[!a-zA-Z0-9]/_}"
        local output_file="$temp_dir/${sanitized_source}.out"

        # 启动后台任务
        (
            # 清除子进程对父 shell EXIT trap 的继承, 避免子进程退出时删除临时目录
            trap - EXIT

            local test_url="${source}/${DOCKER_CE_TEST_DOWNLOAD_FILE}"
            # 使用 curl 进行测试
            # --connect-timeout: 连接阶段的超时时间
            # --max-time: 整个操作的超时时间
            local time_total
            time_total=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 3 -m 10 "$test_url" 2>/dev/null) || time_total=""

            # 检查 curl 命令本身是否成功执行 (即没有因为超时等原因被中断)
            # 如果 curl 失败, 它的退出码非0, 并且 time_total 可能为空
            # 通过检查 time_total 是否为有效数字来判断且小于10秒
            if [[ "$time_total" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (($(echo "$time_total < 10" | bc -l 2>/dev/null || echo 0))); then
                # 只有在成功且耗时小于10秒的情况下, 才将结果写入文件
                echo "$time_total $source" >"$output_file"
            else
                # 否则, 写入一个失败标记
                echo "FAILED" >"$output_file"
            fi
        ) &

        # 记录后台进程的PID和它对应的源地址
        local pid=$!
        pids_to_sources["$pid"]="$source"

        log_debug "已启动测试任务 PID: $pid -> $source"
    done

    log_debug "所有测试任务已启动, 共 ${#pids_to_sources[@]} 个。正在等待首个成功响应的源..."

    local fastest_source=""
    local fastest_time=""

    # 2. 主循环: 收集本轮完成的所有任务, 并从中选出最快的
    # 设置一个超时计数器, 防止无限期等待
    local timeout_counter=0
    local max_timeout=50 # 大约10秒 (50 * 0.2s)

    while [ ${#pids_to_sources[@]} -gt 0 ] && [ $timeout_counter -lt $max_timeout ]; do
        declare -A completed_this_round # 存储本轮完成的任务 PID -> Source
        # 遍历当前所有活动的PID
        for pid in "${!pids_to_sources[@]}"; do
            # 检查进程是否还存在
            if ! kill -0 "$pid" 2>/dev/null; then
                # 进程已结束, 读取它的结果文件
                local source_url="${pids_to_sources[$pid]}"
                local sanitized_source
                sanitized_source="${source_url//[!a-zA-Z0-9]/_}"
                local output_file="$temp_dir/${sanitized_source}.out"

                if [ -f "$output_file" ]; then
                    read -r result <"$output_file"
                    # 从监控数组中移除已结束的PID
                    unset "pids_to_sources[$pid]"
                    # 将完成的任务暂存起来
                    completed_this_round["$pid"]="$source_url|$result"
                fi
            fi
        done

        # 本轮有任务完成, 检查其中是否有成功的, 并找出最快的一个
        if [ ${#completed_this_round[@]} -gt 0 ]; then
            local best_time_in_round=""
            local best_source_in_round=""

            # 遍历本轮所有已完成的结果
            for pid in "${!completed_this_round[@]}"; do
                IFS='|' read -r source_url result <<<"${completed_this_round[$pid]}"

                # 检查结果是否为成功
                if [[ "$result" != FAILED* ]]; then
                    used_time=$(echo "$result" | cut -d' ' -f1)

                    # 如果是第一个成功的, 或者比当前最好的更快, 则更新
                    if [ -z "$best_time_in_round" ]; then
                        # 第一个成功的结果
                        best_time_in_round="$used_time"
                        best_source_in_round=$(echo "$result" | cut -d' ' -f2-)
                    elif (($(echo "$used_time < $best_time_in_round" | bc -l))); then
                        # 比当前最佳的更快，更新最佳
                        best_time_in_round="$used_time"
                        best_source_in_round=$(echo "$result" | cut -d' ' -f2-)
                    fi
                fi
            done

            # 如果在本轮找到了最快的成功源, 则立即确定结果并退出
            if [ -n "$best_source_in_round" ]; then
                fastest_time="$best_time_in_round"
                fastest_source="$best_source_in_round"

                log_debug "🎉 找到最快的 Docker CE 镜像源！"
                log_debug "镜像地址: $fastest_source"
                log_debug "响应时间: $(awk "BEGIN {printf \"%.0f\", $fastest_time * 1000}") ms"

                # 3. 终止所有剩余的后台任务
                log_debug "终止其他正在进行的测试任务..."
                for remaining_pid in "${pids_to_sources[@]}"; do
                    log_debug "终止任务 PID: $remaining_pid"

                    # 需要使用 || true 来防止 kill 失败时脚本退出
                    sudo kill "$remaining_pid" 2>/dev/null || true
                done
                break 2 # 跳出内外层循环
            fi
        fi

        timeout_counter=$((timeout_counter + 1))
        sleep 0.2 # 每200ms轮询一次
    done

    # 4. 收尾工作
    if [ -z "$fastest_source" ]; then
        log_error "❌ 错误：在指定时间内未能找到任何可用的 Docker CE 镜像源。"
        log_error "   请检查网络连接或镜像列表 'DOCKER_CE_SOURCES' 是否正确。"
        return 1
    fi

    echo "$fastest_source"
}

# 备份并删除 docker apt 源和 keyring 文件
docker_install_backup() {
    log_debug "run docker_install_backup"

    # 时间戳
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    # 备份并删除 /etc/apt/sources.list.d/docker.list
    local docker_list_file="/etc/apt/sources.list.d/docker.list"

    if [ -f "$docker_list_file" ]; then
        local bak_dir="/etc/apt/sources.list.d/backup"
        # 如果目录不存在则创建
        if [ ! -d "$bak_dir" ]; then
            sudo mkdir -p "$bak_dir"
            log_debug "已创建备份目录 $bak_dir"
        fi

        # 备份文件
        sudo cp -a "$docker_list_file" "$bak_dir/docker.list.bak_$timestamp"
        log_info "已备份 $docker_list_file 到 $bak_dir/docker.list.bak_$timestamp"

        # 删除文件
        sudo rm -f "$docker_list_file"
        log_debug "已删除 $docker_list_file"
    else
        log_warn "未找到 $docker_list_file，跳过备份和删除"
    fi

    # 备份并删除 /etc/apt/keyrings/docker.asc
    local docker_key_file="/etc/apt/keyrings/docker.asc"
    if [ -f "$docker_key_file" ]; then
        local bak_dir="/etc/apt/keyrings/backup"
        # 如果目录不存在则创建
        if [ ! -d "$bak_dir" ]; then
            sudo mkdir -p "$bak_dir"
            log_debug "已创建备份目录 $bak_dir"
        fi

        # 备份文件
        sudo cp -a "$docker_key_file" "$bak_dir/docker.asc.bak_$timestamp"
        log_info "已备份 $docker_key_file 到 $bak_dir/docker.asc.bak_$timestamp"

        # 删除文件
        sudo rm -f "$docker_key_file"
        log_debug "已删除 $docker_key_file"
    else
        log_warn "未找到 $docker_key_file，跳过备份和删除"
    fi
}

# 手动选择 docker 源
manual_select_docker_source() {
    log_debug "run __install_docker"
    # 1. 打印中文名称（带序号）
    echo "请选择一个 Docker CE 镜像源：" >&2
    for i in "${!DOCKER_CE_SOURCES[@]}"; do
        url="${DOCKER_CE_SOURCES[$i]%|*}"
        name="${DOCKER_CE_SOURCES[$i]#*|}"
        log_debug "选项 $((i + 1)): $name ($url)"
        printf "%2d) %s\n" $((i + 1)) "$name" >&2
    done

    # 2. 获取用户输入
    read -rp "请输入序号（1-${#DOCKER_CE_SOURCES[@]}）: " choice

    # 校验输入是否合法
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#DOCKER_CE_SOURCES[@]}" ]; then
        log_error "无效的输入！请输入 1 到 ${#DOCKER_CE_SOURCES[@]} 之间的数字。"
        exit 1
    fi

    # 3. 获取对应的 URL
    selected_item="${DOCKER_CE_SOURCES[$((choice - 1))]}"
    url="${selected_item%|*}"

    log_debug "用户选择的 Docker CE 镜像源: $url"

    # 输出结果
    log_info "您选择的是：${selected_item#*|}"
    echo "$url"
}
