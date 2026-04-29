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

    while true; do
        # 写入临时文件以捕获输出, 用于失败时的 pattern 匹配
        local tmpfile
        tmpfile=$(mktemp) || {
            log_error "创建临时文件失败"
            return 1
        }

        # 启动等待动画(写到 stderr), 与命令实时输出(stdout, 含 docker 自身进度条) 并行展示
        start_spinner

        # 通过 tee 将命令输出实时打到终端, 同时捕获到 tmpfile 以便失败时做 pattern 匹配
        # 使用 PIPESTATUS[0] 获取 run_func 的真实退出码, 而非 tee 的退出码
        "$run_func" 2>&1 | tee "$tmpfile"
        status=${PIPESTATUS[0]}

        # 命令执行完成, 停止动画
        stop_spinner

        if [ "$status" -eq 0 ]; then
            rm -f "$tmpfile"
            log_info "$success_msg"
            return 0
        fi

        # 记录失败时的输出
        output=$(cat "$tmpfile")
        rm -f "$tmpfile"

        # 检查是否应重试: 要么无 pattern(总是重试), 要么匹配 pattern
        if [ -z "$retry_on_pattern" ] || echo "$output" | grep -Eiq "$retry_on_pattern"; then
            if [ "$attempt" -ge "$max_retries" ]; then
                # 输出已实时打到屏幕, 这里再聚合打印一次, 便于大量重试输出后定位最终失败原因
                log_error "达到最大重试次数($max_retries), 操作仍失败。最后一次输出: $output"
                return 1
            fi

            log_warn "第 ${attempt}/${max_retries} 次重试, ${delay}s 后重试。退出码: $status"

            # 重试等待期间复用同一个 spinner(start 幂等, 已运行则 noop), 避免闪烁
            start_spinner
            sleep "$delay"
            stop_spinner

            attempt=$((attempt + 1))
            delay=$((delay * 2))
        else
            # 非重试类错误, 立即失败
            log_error "${error_msg_prefix}: $output"
            return 1
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
        # 通过 script 分配伪终端(PTY), 让 docker 检测到 TTY 后绘制进度条;
        # -q 静默, -e 透传命令退出码, -f 实时 flush, -c 指定命令, /dev/null 丢弃 typescript 文件
        # 极简环境可能未安装 script(util-linux), 缺失时回退为普通 docker push (无进度条但不影响功能)
        if command -v script >/dev/null 2>&1; then
            script -qefc "sudo docker push '$image'" /dev/null
        else
            sudo docker push "$image"
        fi
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
    local retryable_pull_pattern

    # 默认使用官方仓库
    local image="$image_name:$version"

    # registry 或分发层偶发返回的元数据异常通常可通过重试恢复.
    # 增加对以下常见可恢复错误的匹配：网络/TLS 相关、证书、连接重置/拒绝，
    # 以及分发层/镜像仓库在元数据层面偶发返回的错误（例如 failed to copy / httpReadSeeker / could not fetch content descriptor / manifest unknown / 404）。
    retryable_pull_pattern="TLS handshake timeout|tls: handshake|tls handshake|x509: certificate|certificate signed by unknown authority|connection reset by peer|connection refused|InvalidArgument: Target.Size must be greater than zero|Target.Size must be greater than zero|failed to copy|httpReadSeeker|could not fetch content descriptor|manifest unknown|no such manifest|404 Not Found|not found|received unexpected HTTP status"

    log_info "开始拉取镜像: $image"

    # shellcheck disable=SC2329
    run() {
        log_debug "执行的命令: sudo docker pull $image"
        # 通过 script 分配伪终端(PTY), 让 docker 检测到 TTY 后绘制带箭头的分层进度条;
        # -q 静默, -e 透传命令退出码, -f 实时 flush, -c 指定命令, /dev/null 丢弃 typescript 文件
        # 极简环境可能未安装 script(util-linux), 缺失时回退为普通 docker pull (无箭头进度条但不影响功能)
        if command -v script >/dev/null 2>&1; then
            script -qefc "sudo docker pull '$image'" /dev/null
        else
            sudo docker pull "$image"
        fi
    }

    retry_with_backoff \
        "run" \
        5 \
        2 \
        "拉取 $image 成功" \
        "docker pull 失败(非 TLS/连接类错误)" \
        "$retryable_pull_pattern"
}
