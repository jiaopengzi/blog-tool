#!/bin/bash
# FilePath    : blog-tool/client/compose.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : server docker compose 配置文件

# 创建 client docker compose文件
create_docker_compose_client() {
  log_debug "run create_docker_compose_client"

  # 参数
  # $1 版本号, 默认 latest
  local version="${1:-latest}"

  # 如果存在 docker-compose.yaml 文件就删除
  local docker_compose_file="$DOCKER_COMPOSE_FILE_CLIENT"
  if [ -f "$docker_compose_file" ]; then
    sudo rm -f "$docker_compose_file"
  fi

  local img_prefix
  img_prefix=$(get_img_prefix)
  # 创建新的 docker-compose-server-client.yaml 文件
  cat >"$docker_compose_file" <<-EOM
# 博客项目前后端分离部署 docker compose 配置文件
# 运行命令:sudo docker compose -f $docker_compose_file up -d

services:
  blog-client:
    image: $img_prefix/blog-client:$version
    container_name: blog-client
    restart: always
    user: '$CLIENT_UID:$CLIENT_GID' # 使用 nginx 默认用户 101:101
    # stdin_open: true # 标准输入打开
    # tty: true # 终端打开
    # privileged: true # 拥有容器内命令执行的权限
    # depends_on: # 添加依赖关系
    #   - blog-server # client 依赖于 server
    volumes:
      - $DATA_VOLUME_DIR/blog-client/nginx:/etc/nginx
    ports:
      - '80:80' # http 端口
      - '443:443' # https 端口
    networks: # docker 网络设置
      $BRIDGE_CLIENT: # 网络名称
        ipv4_address: $IPV4_BASE_CLIENT.3 # IP地址

networks: # 网络配置
  $BRIDGE_CLIENT: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_CLIENT # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_CLIENT" # 子网
          gateway: "$GATEWAY_CLIENT" # 网关
EOM

  # 打印日志
  log_info "$docker_compose_file 创建成功"
}
