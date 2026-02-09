#!/bin/bash
# FilePath    : blog-tool/db/pgsql.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : pgsql docker 相关操作

# postgresql.conf 文件
get_content_postgresql_conf() {
  local postgres_port=$1

  local content_postgresql_conf
  content_postgresql_conf=$(
    cat <<EOL
# PostgreSQL 配置文件

# 配置目录: /etc/postgresql
# 数据目录: /var/lib/postgresql

# 连接设置
listen_addresses = '*'                             # 监听地址,'*'为监听所有IP
port = $postgres_port                              # 监听端口
max_connections = 200                              # 最大连接数
superuser_reserved_connections = 3                 # 超级用户保留连接数
ssl = off                                          # SSL加密

# 认证设置
password_encryption = scram-sha-256                # 密码加密方法 (scram-sha-256 or md5)

# 内存参数设置
shared_buffers = 256MB                             # 共享缓冲区大小
effective_cache_size = 256MB                       # 工作内存大小
maintenance_work_mem = 64MB                        # 维护工作内存大小
temp_buffers = 8MB                                 # 临时缓冲区大小
dynamic_shared_memory_type = posix                 # 动态共享内存类型 (posix, sysv, windows, mmap)

# 写入参数设置
fsync = on                                         # 同步磁盘写入
wal_sync_method = fsync                            # WAL同步方法
synchronous_commit = on                            # 同步提交
checkpoint_timeout = 5min                          # 检查点超时时间
checkpoint_completion_target = 0.9                 # 检查点完成目标百分比
checkpoint_flush_after = 32kB                      # 检查点刷新间隔大小

# 磁盘参数设置
max_wal_size = 1GB                                 # WAL日志文件最大大小
min_wal_size = 80MB                                # WAL日志文件最小大小

timezone = 'Asia/Shanghai'                         # 时区设置 (UTC, Asia/Shanghai, Etc/UTC)

# 日志设置
log_destination = 'stderr'                         # 日志输出目标
logging_collector = on                             # 启用日志收集
log_directory = 'pg_log'                           # 日志目录
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'    # 日志文件名
log_truncate_on_rotation = on                      # 截断旧日志
log_rotation_age = 7d                              # 日志轮换时间
log_rotation_size = 10MB                           # 日志轮换大小
log_min_duration_statement = -1                    # 记录慢查询阈值（毫秒）
log_line_prefix = '%t [%p]: [%x] %u@%d %i '        # 日志行前缀格式
log_timezone = 'Asia/Shanghai'                     # 日志时区

# 运行时统计信息设置
track_activities = on                              # 与踪连接活动
track_counts = on                                  # 与踪对象数量
update_process_title = on                          # 更新进程标题显示状态

# 其他参数
datestyle = 'iso, mdy'                             # 日期输出格式
lc_messages='en_US.UTF-8'                          # 本地化消息显示设置
lc_monetary='en_US.UTF-8'                          # 本地化货币显示设置
lc_numeric='en_US.UTF-8'                           # 本地化数字显示设置
lc_time='en_US.UTF-8'                              # 本地化时间显示设置
default_text_search_config = 'pg_catalog.english'  # 默认全文搜索配置
EOL
  )

  # 返回内容
  echo "$content_postgresql_conf"
}

# pg_hba.conf 文件
get_content_pg_hba_conf() {
  local subnet_pgsql=$1
  local subnet_server=$2

  local content_pg_hba_conf
  content_pg_hba_conf=$(
    cat <<EOL
# PostgreSQL Client Authentication Configuration File
# ===================================================

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust

# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     trust

# ip4访问权限限制开始
#host    all             all             10.0.0.0/16         scram-sha-256 # 允许此 IP 地址访问
#host    all             all             $subnet_pgsql        scram-sha-256 # 允许此 IP 地址访问
#host    all             all             $subnet_server        scram-sha-256 # 允许此 IP 地址访问
#host    all             all             $HOST_INTRANET_IP/$(get_cidr "$HOST_INTRANET_MARK")        scram-sha-256 # 允许此 IP 地址访问
# ip4访问权限限制结束

# ip4访问权限放开开始
host    all             all             0.0.0.0/0               scram-sha-256 # 允许所有 ip4 访问
# ip4访问权限放开结束

# ip6 访问权限
# host    all             all             ::/0                    scram-sha-256
EOL
  )
  # 返回内容
  echo "$content_pg_hba_conf"
}

# 启动 pgsql 容器
start_db_pgsql() {
  log_debug "run start_db_pgsql"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" up -d
}

# 停止 pgsql 容器
stop_db_pgsql() {
  log_debug "run stop_db_pgsql"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" down || true
}

# 重启 pgsql 容器
restart_db_pgsql() {
  log_debug "run restart_db_pgsql"
  stop_db_pgsql
  start_db_pgsql
}

# 安装 pgsql 数据库
install_db_pgsql() {
  log_debug "run install_db_pgsql"

  # shellcheck disable=SC2329
  run() {
    local all_remove_data # 是否删除历史数据 默认不删除

    all_remove_data=$(read_user_input "是否删除 pgsql 数据库信息(默认n) [y|n]? " "n")

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
      # 如果不存在则创建
      setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/pgsql"

    # 创建一个名为 docker-compose.yaml 的新文件
    local docker_compose_file="$DOCKER_COMPOSE_FILE_PGSQL"

    # 如果存在 docker-compose.yaml 执行docker compose down
    if [ -f "$docker_compose_file" ]; then
      sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" down || true # 删除容器
      touch "$docker_compose_file"
    fi

    cat >"$docker_compose_file" <<-EOM
services:
  # PostgreSQL 服务
  postgres:
    image: 'postgres:$IMG_VERSION_PGSQL'
    container_name: $POSTGRES_DOCKER_NAME
    restart: always
    user: '$DB_UID:$DB_GID' # DOCKERFILE 中设置的用户
    environment:
      POSTGRES_USER: $POSTGRES_USER
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
      POSTGRES_DB: $POSTGRES_DB
      # 初始化使用和配置有所重复,需要保留 --auth-local=trust 本地连接不需要密码  --auth-host=scram-sha-256 远程连接需要密码 --data-checksums 数据校验
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=trust --data-checksums"

    # 使用自定义配置文件
    command: postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

    volumes:
      - $DATA_VOLUME_DIR/pgsql/conf/postgresql.conf:/etc/postgresql/postgresql.conf # 自定义配置文件
      - $DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf:/etc/postgresql/pg_hba.conf # 在 postgresql.conf 配置文件中指定路径
      # 数据目录调整,参考:https://github.com/docker-library/postgres/pull/1259
      - $DATA_VOLUME_DIR/pgsql/data:/var/lib/postgresql/$IMG_VERSION_PGSQL_MAJOR/docker # 数据存储目录
      - $DATA_VOLUME_DIR/pgsql/log:/var/log/postgresql # 日志存储目录

    ports:
      - "$POSTGRES_PORT:5432" # 映射端口

    networks: # 网络配置
      $BRIDGE_PGSQL: # 网络名称
        ipv4_address: $POSTGRES_IP # IP地址

networks: # 网络配置
  $BRIDGE_PGSQL: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_PGSQL # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_PGSQL" # 子网
          gateway: "$GATEWAY_PGSQL" # 网关
EOM

    # 删除历史数据 pgsql
    if [ "$all_remove_data" == "y" ]; then

      sudo rm -rf "$DATA_VOLUME_DIR/pgsql"
      if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
      fi
      # 创建新目录
      setup_directory "$DB_UID" "$DB_GID" 755 \
        "$DATA_VOLUME_DIR/pgsql" \
        "$DATA_VOLUME_DIR/pgsql/data" \
        "$DATA_VOLUME_DIR/pgsql/conf" \
        "$DATA_VOLUME_DIR/pgsql/log"

      # 获取配置文件内容
      local content_postgresql_conf
      local content_pg_hba_conf

      content_postgresql_conf=$(get_content_postgresql_conf "$POSTGRES_PORT")
      content_pg_hba_conf=$(get_content_pg_hba_conf "$SUBNET_PGSQL" "$SUBNET_SERVER")

      # 写入配置文件并设置权限
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_postgresql_conf" "$DATA_VOLUME_DIR/pgsql/conf/postgresql.conf"
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_pg_hba_conf" "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf"

      log_info "已删除 pgsql 历史数据"

    else
      log_info "未删除 pgsql 历史数据"
    fi

    # 启动 pgsql 容器
    start_db_pgsql

    # # 删除pgsql不使用的默认配置文件
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql/data/postgresql.conf"
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql/data/pg_hba.conf"

  }
  log_timer "pgsql 启动" run

  log_info "pgsql 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 切换 pgsql 访问权限
# 使用示例
#   toggle_pg_hba_conf restrict /path/to/pg_hba.conf
#   toggle_pg_hba_conf open /path/to/pg_hba.conf
toggle_pg_hba_conf() {
  log_debug "run toggle_pg_hba_conf"

  local mode="$1"
  local file_path="$2"

  if [[ "$mode" == "restrict" ]]; then
    sudo awk '/# ip4访问权限限制开始/,/# ip4访问权限限制结束/ {sub(/^#host/, "host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
    sudo awk '/# ip4访问权限放开开始/,/# ip4访问权限放开结束/ {sub(/^host/, "#host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
  elif [[ "$mode" == "open" ]]; then
    sudo awk '/# ip4访问权限限制开始/,/# ip4访问权限限制结束/ {sub(/^#host/, "#host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
    sudo awk '/# ip4访问权限放开开始/,/# ip4访问权限放开结束/ {sub(/^#host/, "host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
  else
    log_error "切换 pg_hba.conf 访问权限失败, 模式错误: $mode; 只能是 restrict 或 open"
    return 1
  fi

  log_info "$file_path 已经切换 $mode 模式."
}

# 开放 pgsql 访问权限
open_pgsql_access_by_pg_hba.conf() {
  log_debug "run open_pgsql_access_by_pg_hba.conf"

  sudo docker stop "$POSTGRES_DOCKER_NAME"                          # 停止容器 pgsql 容器
  toggle_pg_hba_conf open "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf" # 切换访问权限
  sudo docker start "$POSTGRES_DOCKER_NAME"                         # 重启容器
}

# 限制 pgsql 访问权限
restrict_pgsql_access_by_pg_hba.conf() {
  log_debug "run restrict_pgsql_access_by_pg_hba.conf"

  sudo docker stop "$POSTGRES_DOCKER_NAME"                              # 停止容器 pgsql 容器
  toggle_pg_hba_conf restrict "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf" # 切换访问权限
  sudo docker start "$POSTGRES_DOCKER_NAME"                             # 重启容器
}

# 停止并删除 pgsql 数据库
delete_db_pgsql() {
  log_debug "run delete_db_pgsql"

  local is_delete
  is_delete=$(read_user_input "确认停止 pgsql 服务并删除数据吗(默认n) [y|n] " "n")

  if [[ "$is_delete" == "y" ]]; then
    # 停止容器
    stop_db_pgsql

    # 删除数据库数据
    sudo rm -rf "$DATA_VOLUME_DIR/pgsql"
  fi
}
