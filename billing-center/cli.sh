#!/bin/bash
# FilePath    : blog-tool/billing-center/cli.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : billing-center 命令行操作脚本

# 通过 CLI 执行命令
billing_center_cli() {
  log_debug "run billing_center_cli"

  local arg=$1

  # 在容器中执行
  log_debug "执行命令: sudo docker exec -it billing-center /bin/sh -c \"/home/billing-center/billing-center ${arg}\""

  sudo docker exec -it billing-center /bin/sh -c "/home/billing-center/billing-center ${arg}"

  # 重启容器
  # log_info "重启容器"
  # docker_billing_center_restart
}

# 打印 CA 证书的字节信息
ca_cert_byte_print() {
  log_debug "run ca-cert-byte-print"
  billing_center_cli "ca-cert-byte-print -n 32"
}
