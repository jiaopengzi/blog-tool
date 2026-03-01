#!/bin/bash
# FilePath    : blog-tool/billing-center/compose.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2026 by jiaopengzi, All Rights Reserved.
# Description : billing_center docker compose 配置文件

# 创建 billing_center docker compose文件
create_docker_compose_billing_center() {
  log_debug "run create_docker_compose_billing_center"

  # 参数
  # $1 版本号, 默认 latest
  local version="${1:-latest}"

  # 如果存在 docker-compose.yaml 文件就删除
  local docker_compose_file="$DOCKER_COMPOSE_FILE_BILLING_CENTER"
  if [ -f "$docker_compose_file" ]; then
    sudo rm -f "$docker_compose_file"
  fi

  local img_prefix
  img_prefix=$(get_img_prefix)

  #  创建新的 docker-compose-billing_center-client.yaml 文件
  cat >"$docker_compose_file" <<-EOM
# 运行命令:sudo docker compose -f $docker_compose_file -p "$DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER" up -d

services:
  billing-center:
    image: $img_prefix/billing-center:$version
    restart: always
    container_name: billing-center
    user: '$JPZ_UID:$JPZ_GID' # DOCKERFILE 中设置的用户
    volumes:
      - $DATA_VOLUME_DIR/billing-center/config:/home/billing-center/config
      - $DATA_VOLUME_DIR/billing-center/logs:/home/billing-center/logs
      - $DATA_VOLUME_DIR/billing-center/nginx:/etc/nginx
    ports:
      - '80:80' # http 端口
      - '443:443' # https 端口
    networks: # docker 网络设置
      $BRIDGE_BILLING_CENTER: # 网络名称
        ipv4_address: $IPV4_BASE_BILLING_CENTER.2 # IP地址
    
    # 健康检查
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -sk https://localhost/api/v1/helper/version | grep 'request_id'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

networks: # 网络配置
  $BRIDGE_BILLING_CENTER: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_BILLING_CENTER # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_BILLING_CENTER" # 子网
          gateway: "$GATEWAY_BILLING_CENTER" # 网关
EOM

  # 打印日志
  log_info "$docker_compose_file create success"
}
