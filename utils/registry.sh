#!/bin/bash
# FilePath    : blog-tool/utils/registry.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 自定义镜像仓库

# 创建自定义镜像仓库用于分发镜像
docker_run_registry() {
  log_debug "run docker_run_registry"

  # 回到脚本所在目录
  cd "$ROOT_DIR" || exit

  # 如果有 registry 文件夹就删除
  if [ -d "$ROOT_DIR/registry" ]; then
    cd "$ROOT_DIR/registry" || exit
    # 停止并删除容器
    # 判断是会否有 docker-compose.yaml 文件
    if [ -f "$ROOT_DIR/registry/docker-compose.yaml" ]; then
      sudo docker compose down || true
    fi

    cd "$ROOT_DIR" || exit

    # 删除 registry 文件夹
    sudo rm -rf "$ROOT_DIR/registry"
  fi

  docker_run_registry_new
}

# 创建 registry 仓库
docker_run_registry_new() {
  log_debug "run docker_run_registry_new"

  # 创建 registry 目录
  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry"

  # 如果当前目录下 certs_nginx 文件夹不存在则输出提示
  if [ ! -d "$CERTS_NGINX" ]; then
    echo "========================================"
    echo "    请将证书 $CERTS_NGINX 文件夹放到当前目录"
    echo "    证书文件夹结构如下:"
    echo "    $CERTS_NGINX"
    echo "    ├── cert.key"
    echo "    └── cert.pem"
    echo "========================================"
    log_error "缺少 $CERTS_NGINX 证书目录, 无法继续创建 registry 镜像仓库"
    exit 1
  fi

  # 复制 certs_nginx 文件夹到 registry 目录下
  cp -r "$CERTS_NGINX" "$ROOT_DIR/registry/certs_nginx"

  # 进入 ./registry
  cd "$ROOT_DIR/registry" || exit

  # 打印当前目录
  log_debug "当前目录 $(pwd)"

  # 创建用户
  # mkdir auth # 创建存放用户密码文件夹
  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry/auth"
  sudo docker run --entrypoint htpasswd httpd:"$IMG_VERSION_HTTPD" -Bbn "$REGISTRY_USER_NAME" "$REGISTRY_PASSWORD" | sudo tee "$ROOT_DIR/registry/auth/htpasswd" >/dev/null # 创建用户密码文件

  # 删除 httpd 临时容器
  sudo docker ps -a | grep httpd:"$IMG_VERSION_HTTPD" | awk '{print $1}' | xargs sudo docker rm -f

  # mkdir data # 创建存放镜像数据文件夹
  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry/data"

  #  创建新的 docker-compose.yaml 文件
  cat >>"$ROOT_DIR/registry/docker-compose.yaml" <<-EOM
# 默认文件名 docker-compose.yml 使用命令 sudo docker compose up -d

services:
  registry:
    restart: always
    container_name: 'registry$IMG_VERSION_REGISTRY'
    image: 'registry:$IMG_VERSION_REGISTRY'
    user: '$JPZ_UID:$JPZ_UID'
    ports:
      - 5000:5000
      # - 443:443
    environment:
      # REGISTRY_HTTP_ADDR: 0.0.0.0:443 # 443 可以自定义指定容器内部开放端口
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/cert.pem # 证书 pem 容器内部路径
      REGISTRY_HTTP_TLS_KEY: /certs/cert.key # 证书 key 容器内部路径
      REGISTRY_AUTH: htpasswd # 认证方式
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd # 认证文件路径
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm # 认证域
      REGISTRY_LOG_LEVEL: "warn" # 将日志级别设为 warning 及以上
      REGISTRY_TRACING_ENABLED: "false" # 是否启用追踪
      REGISTRY_TRACING_ENDPOINT: "" # 追踪端点
      OTEL_TRACES_EXPORTER: "none" # 禁用 OpenTelemetry traces 导出
      OTEL_EXPORTER_OTLP_ENDPOINT: "" # 清空默认 OTLP endpoint 避免尝试连接 localhost:4318
    volumes:
      - $ROOT_DIR/registry/data:/var/lib/registry # 数据存储路径
      - $ROOT_DIR/registry/certs_nginx:/certs # 证书存储路径
      - $ROOT_DIR/registry/auth:/auth # 认证文件存储路径
    networks: # 网络配置
      $BRIDGE_REGISTRY: # 网络名称

networks: # 网络配置
  $BRIDGE_REGISTRY: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_REGISTRY # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_REGISTRY" # 子网
          gateway: "$GATEWAY_REGISTRY" # 网关
EOM

  # 启动服务
  sudo docker compose up -d

  # 登录私有仓库
  sudo docker login "$REGISTRY_REMOTE_SERVER" -u "$REGISTRY_USER_NAME" --password-stdin <<<"$REGISTRY_PASSWORD"
}
