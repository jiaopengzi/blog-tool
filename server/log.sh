#!/bin/bash
# FilePath    : blog-tool/server/log.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 日志

# 查看 blog-server 日志
blog_server_logs() {
    log_debug "run blog_server_logs"

    app_log \
        "blog-server" \
        "$DATA_VOLUME_DIR/blog-server/logs/app.log" \
        "$DATA_VOLUME_DIR/blog-server/config/log_zap.yaml" \
        "docker_server_restart"
}
