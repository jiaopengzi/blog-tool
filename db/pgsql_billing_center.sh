#!/bin/bash
# FilePath    : blog-tool/db/pgsql_billing_center.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2026 by jiaopengzi, All Rights Reserved.
# Description : 计费中心数据库

# 启动 pgsql 容器(billing center)
start_db_pgsql_billing_center() {
  log_debug "run start_db_pgsql_billing_center"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" up -d
}

# 停止 pgsql 容器(billing center)
stop_db_pgsql_billing_center() {
  log_debug "run stop_db_pgsql_billing_center"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" down || true
}

# 重启 pgsql 容器(billing center)
restart_db_pgsql_billing_center() {
  log_debug "run restart_db_pgsql_billing_center"
  stop_db_pgsql_billing_center
  start_db_pgsql_billing_center
}

# 安装 pgsql 数据库(billing center)
install_db_pgsql_billing_center() {
  log_debug "run install_db_pgsql_billing_center"
  # shellcheck disable=SC2329
  run() {
    local all_remove_data # 是否删除历史数据 默认不删除

    all_remove_data=$(read_user_input "是否删除 pgsql_billing_center 数据库信息(默认n) [y|n]? " "n")

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
      # 如果不存在则创建
      setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/pgsql_billing_center"

    # 创建一个名为 docker-compose.yaml 的新文件
    local docker_compose_file="$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER"

    # 如果存在 docker-compose.yaml 执行 docker compose down
    if [ -f "$docker_compose_file" ]; then
      sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" down || true # 删除容器
      touch "$docker_compose_file"
    fi

    cat >"$docker_compose_file" <<-EOM
services:
  # PostgreSQL 服务
  postgres:
    image: 'postgres:$IMG_VERSION_PGSQL'
    container_name: $POSTGRES_DOCKER_NAME_BILLING_CENTER
    restart: always
    user: '$DB_UID:$DB_GID' # DOCKERFILE 中设置的用户
    environment:
      POSTGRES_USER: $POSTGRES_USER_BILLING_CENTER
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD_BILLING_CENTER
      POSTGRES_DB: $POSTGRES_DB_BILLING_CENTER
      # 初始化使用和配置有所重复,需要保留 --auth-local=trust 本地连接不需要密码  --auth-host=scram-sha-256 远程连接需要密码 --data-checksums 数据校验
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=trust --data-checksums"

    # 使用自定义配置文件
    command: postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

    volumes:
      - $DATA_VOLUME_DIR/pgsql_billing_center/conf/postgresql.conf:/etc/postgresql/postgresql.conf # 自定义配置文件
      - $DATA_VOLUME_DIR/pgsql_billing_center/conf/pg_hba.conf:/etc/postgresql/pg_hba.conf # 在 postgresql.conf 配置文件中指定路径
      # 数据目录调整,参考:https://github.com/docker-library/postgres/pull/1259
      - $DATA_VOLUME_DIR/pgsql_billing_center/data:/var/lib/postgresql/$IMG_VERSION_PGSQL_MAJOR/docker # 数据存储目录
      - $DATA_VOLUME_DIR/pgsql_billing_center/log:/var/log/postgresql # 日志存储目录

    ports:
      - "$POSTGRES_PORT_BILLING_CENTER:$POSTGRES_PORT_BILLING_CENTER" # 映射端口

    networks: # 网络配置
      $BRIDGE_PGSQL_BILLING_CENTER: # 网络名称
        ipv4_address: $POSTGRES_IP_BILLING_CENTER # IP地址

networks: # 网络配置
  $BRIDGE_PGSQL_BILLING_CENTER: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_PGSQL_BILLING_CENTER # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_PGSQL_BILLING_CENTER" # 子网
          gateway: "$GATEWAY_PGSQL_BILLING_CENTER" # 网关
EOM

    # 删除历史数据 pgsql_billing_center
    if [ "$all_remove_data" == "y" ]; then

      sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center"
      if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
      fi

      # 创建新目录
      setup_directory "$DB_UID" "$DB_GID" 755 \
        "$DATA_VOLUME_DIR/pgsql_billing_center" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/data" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/conf" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/log"

      # 获取配置文件内容
      local content_postgresql_conf
      local content_pg_hba_conf

      content_postgresql_conf=$(get_content_postgresql_conf "$POSTGRES_PORT_BILLING_CENTER")
      content_pg_hba_conf=$(get_content_pg_hba_conf "$SUBNET_PGSQL_BILLING_CENTER" "$SUBNET_BILLING_CENTER")

      # 写入配置文件并设置权限
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_postgresql_conf" "$DATA_VOLUME_DIR/pgsql_billing_center/conf/postgresql.conf"
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_pg_hba_conf" "$DATA_VOLUME_DIR/pgsql_billing_center/conf/pg_hba.conf"

      log_info "已删除 pgsql_billing_center 历史数据"

    else
      log_info "未删除 pgsql_billing_center 历史数据"
    fi

    # 启动 pgsql 容器
    start_db_pgsql_billing_center

    # # 删除pgsql_billing_center不使用的默认配置文件
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center/data/postgresql.conf"
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center/data/pg_hba.conf"

  }

  log_timer "pgsql_billing_center 启动" run

  log_info "pgsql_billing_center 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 停止并删除 pgsql_billing_center 数据库
delete_db_pgsql_billing_center() {
  log_debug "run delete_db_pgsql_billing_center"

  local is_delete
  is_delete=$(read_user_input "确认停止 pgsql_billing_center 服务并删除数据吗(默认n) [y|n] " "n")

  if [[ "$is_delete" == "y" ]]; then
    # 停止容器
    stop_db_pgsql_billing_center

    # 删除数据库数据
    sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center"
  fi
}
