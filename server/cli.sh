#!/bin/bash
# FilePath    : blog-tool/server/cli.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : blog-server 命令行操作脚本

# 通过 CLI 执行命令
blog_server_cli() {
  log_debug "run blog_server_cli"

  local arg=$1

  # 在容器中执行
  log_debug "执行命令: sudo docker exec -it blog-server /bin/sh -c \"/home/blog-server/blog-server ${arg}\""

  sudo docker exec -it blog-server /bin/sh -c "/home/blog-server/blog-server ${arg}"

  # 重启容器
  log_info "重启容器"
  docker_server_restart
}

# 插入测试数据
insert_demo_data() {
  log_debug "run insert_demo_data"
  blog_server_cli "insert-demo-data"
}

# 注册管理员用户
register_admin() {
  log_debug "run register_admin"
  blog_server_cli "register-admin"
}

# 注册管理员用户
reset_password() {
  log_debug "run reset_password"
  blog_server_cli "reset-password"
}
