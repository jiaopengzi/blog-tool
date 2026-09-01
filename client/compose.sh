#!/bin/bash
# FilePath    : blog-tool/client/compose.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : Nuxt client Docker Compose 配置, 通过环境变量注入 SSR 与 nginx 运行参数

# create_docker_compose_client 生成 Nuxt client 的 Docker Compose 配置.
# 参数: $1: 镜像版本号, 省略时使用 latest.
# 返回: 写入配置成功返回 0, 文件创建失败时由调用命令返回非 0.
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
    environment:
      # client 与 server 使用独立 Docker 网络, 通过宿主机已映射端口访问后端.
      NUXT_API_BASE: 'http://$HOST_INTRANET_IP:5426'
      # SSR 的 canonical 与 Open Graph 地址需要使用实际部署域名.
      NUXT_PUBLIC_BASE_URL: 'https://$DOMAIN_NAME'
      # entrypoint 使用此值渲染 nginx.conf.template 的 server_name.
      NGINX_SERVER_NAME: '$DOMAIN_NAME'
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
