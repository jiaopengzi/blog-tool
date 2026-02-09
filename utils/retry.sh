#!/bin/bash
# FilePath    : blog-tool/utils/retry.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com,
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 重试相关工具

# 通用的带指数退避的重试机制
retry_with_backoff() {
    # 参数说明:
    #   $1: run_func                # 执行的函数
    #   $2: max_retries             # 最大重试次数(默认5)
    #   $3: initial_delay           # 初始延迟秒数(默认2)
    #   $4: success_msg             # 成功时的日志信息
    #   $5: error_msg_prefix        # 错误前缀(用于非重试错误)
    #   $6: retry_on_pattern        # 仅当输出匹配此正则时才重试(否则立即失败)
    local run_func="$1"
    local max_retries=${2:-5}
    local delay=${3:-2}
    local success_msg="$4"
    local error_msg_prefix="$5"
    local retry_on_pattern="$6"

    local attempt=1
    local output
    local status

    # 动画开始
    start_spinner

    while true; do
        # 写人临时文件以捕获输出
        local tmpfile
        tmpfile=$(mktemp) || {
            stop_spinner
            log_error "创建临时文件失败"
            return 1
        }

        # 执行函数, 同时显示输出并捕获
        if "$run_func" >"$tmpfile" 2>&1; then
            # 先停止动画
            stop_spinner

            # 将记录的输出显示到终端
            cat "$tmpfile"
            rm -f "$tmpfile"

            # 打印日志
            log_info "$success_msg"
            return 0
        else
            status=$?

            # 记录失败时的输出
            output=$(cat "$tmpfile")

            # 检查是否应重试: 要么无 pattern(总是重试), 要么匹配 pattern
            if [ -z "$retry_on_pattern" ] || echo "$output" | grep -Eiq "$retry_on_pattern"; then
                if [ "$attempt" -ge "$max_retries" ]; then
                    stop_spinner
                    log_error "达到最大重试次数($max_retries), 操作仍失败。输出: $output"
                    return 1
                fi

                log_warn "第 ${attempt}/${max_retries} 次重试, ${delay}s 后重试。退出码: $status"
                sleep "$delay"
                attempt=$((attempt + 1))
                delay=$((delay * 2))
            else
                # 非重试类错误, 立即失败
                stop_spinner
                log_error "${error_msg_prefix}: $output"
                return 1
            fi
        fi
    done
}

# docker 登录重试
docker_login_retry() {

    log_debug "run docker_login_retry"
    # 参数
    # $1: registry_server 仓库地址
    # $2: username 用户名
    # $3: password 密码
    local registry_server="$1"
    local username="$2"
    local password="$3"

    log_info "正在登录 docker 仓库: $registry_server"

    # shellcheck disable=SC2329
    run() {
        sudo docker login "$registry_server" -u "$username" --password-stdin <<<"$password"
    }

    retry_with_backoff \
        "run" \
        5 \
        2 \
        "登录仓库 $registry_server 成功" \
        "登录仓库失败(非重试类错误)" \
        "" # 登录失败通常重试, 不设 pattern
}

# 带超时的 docker push 重试
timeout_retry_docker_push() {
    log_debug "run timeout_retry_docker_push"
    # 参数
    # $1: registry_server_or_user 私有仓库地址 或 docker hub 用户名
    # $2: project 项目名称
    # $3: version 版本号
    local registry_server_or_user="$1"
    local project=$2
    local version=$3

    local image="$registry_server_or_user/$project:$version"

    log_info "准备推送镜像: $image"

    # shellcheck disable=SC2329
    run() {
        log_debug "执行的命令: sudo docker push $image"
        sudo docker push "$image"
    }

    retry_with_backoff \
        "run" \
        5 \
        2 \
        "推送 $image 成功" \
        "docker push 失败(非 TLS/连接类错误)" \
        "TLS handshake timeout|tls: handshake|tls handshake|x509: certificate|certificate signed by unknown authority|connection reset by peer|connection refused"
}

# 带超时的 docker pull 重试
timeout_retry_docker_pull() {
    log_debug "run timeout_retry_docker_pull"
    # 参数
    # $1: image_name 项目名称
    # $2: version 版本号
    local image_name=$1
    local version=$2

    # 默认使用官方仓库
    local image="$image_name:$version"

    log_info "开始拉取镜像: $image"

    # shellcheck disable=SC2329
    run() {
        log_debug "执行的命令: sudo docker pull $image"
        sudo docker pull "$image"
    }

    retry_with_backoff \
        "run" \
        5 \
        2 \
        "拉取 $image 成功" \
        "docker pull 失败(非 TLS/连接类错误)" \
        "TLS handshake timeout|tls: handshake|tls handshake|x509: certificate|certificate signed by unknown authority|connection reset by peer|connection refused"
}
