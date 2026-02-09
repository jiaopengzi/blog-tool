#!/bin/bash
# FilePath    : blog-tool/server/compose.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : server docker compose 配置文件

# 创建 server docker compose文件
create_docker_compose_server() {
  log_debug "run create_docker_compose_server"

  # 参数
  # $1 版本号, 默认 latest
  local version="${1:-latest}"

  # 如果存在 docker-compose.yaml 文件就删除
  local docker_compose_file="$DOCKER_COMPOSE_FILE_SERVER"
  if [ -f "$docker_compose_file" ]; then
    sudo rm -f "$docker_compose_file"
  fi

  local img_prefix
  img_prefix=$(get_img_prefix)

  #  创建新的 docker-compose-server-client.yaml 文件
  cat >"$docker_compose_file" <<-EOM
# 博客项目前后端分离部署 docker compose 配置文件
# 运行命令:sudo docker compose -f $docker_compose_file -p "$DOCKER_COMPOSE_PROJECT_NAME_SERVER" up -d

services:
  # blog-server 后端服务
  blog-server:
    image: $img_prefix/blog-server:$version
    restart: always
    container_name: blog-server
    user: '$SERVER_UID:$SERVER_GID' # DOCKERFILE 中设置的用户
    # stdin_open: true # 标准输入打开
    # tty: true # 终端打开
    # privileged: true # 拥有容器内命令执行的权限
    volumes:
      - $DATA_VOLUME_DIR/blog-server/config:/home/blog-server/config
      - $DATA_VOLUME_DIR/blog-server/uploads:/home/blog-server/uploads
      - $DATA_VOLUME_DIR/blog-server/logs:/home/blog-server/logs
    ports: # 映射端口，对外提供服务
      - '5426:5426' # blog-server 的服务端口
    networks: # docker 网络设置
      $BRIDGE_SERVER: # 网络名称
        ipv4_address: $IPV4_BASE_SERVER.2 # IP地址
    
    # 健康检查
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s http://localhost:5426/api/v1/is-setup | grep 'request_id'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

networks: # 网络配置
  $BRIDGE_SERVER: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_SERVER # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_SERVER" # 子网
          gateway: "$GATEWAY_SERVER" # 网关
EOM

  # 打印日志
  log_info "$docker_compose_file create success"
}
