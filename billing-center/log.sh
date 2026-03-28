#!/bin/bash
# FilePath    : blog-tool/billing-center/log.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 日志

# 查看 billing-center 日志
billing_center_logs() {
    log_debug "run billing_center_logs"

    app_log \
        "billing-center" \
        "$DATA_VOLUME_DIR/billing-center/logs/app.log" \
        "$DATA_VOLUME_DIR/billing-center/config/log_zap.yaml" \
        "docker_billing_center_restart"
}
