#!/bin/bash
# FilePath    : blog-tool/db/redis.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : redis

# 启动 redis 容器
start_db_redis() {
    log_debug "run start_db_redis"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS" up -d # 启动容器
}

# 停止 redis 容器
stop_db_redis() {
    log_debug "run stop_db_redis"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS" down || true
}

# 重启 redis 容器
restart_db_redis() {
    log_debug "run restart_db_redis"
    stop_db_redis
    start_db_redis
}

# 创建 redis 数据库
install_db_redis() {
    log_debug "run install_db_redis"

    # shellcheck disable=SC2329
    run() {
        local is_redis_cluster # 是否创建 redis 集群 默认不创建
        local all_remove_data  # 是否删除历史数据 默认不删除

        # 根据运行模式决定是否询问
        is_redis_cluster=$(read_user_input "[1/2]是否创建 redis 集群(默认n) [y|n]? " "n")
        all_remove_data=$(read_user_input "[2/2]是否删除 redis (默认n) [y|n]? " "n")

        if [ ! -d "$DATA_VOLUME_DIR" ]; then
            # 如果不存在则创建
            setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
        fi

        setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/redis"

        # ? ===============重要提示===============

        # 由于 docker 中创建 redis sentinel 无法使用自定义网络和 docker0 网络通信
        # 集群和哨兵不能使用 docker 的 NAT 模式 使用 host 模式
        # 需要使用 --net=host 的方式创建,外部访问需要打开对应端口
        # 参考官网: https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/

        # ? ===============重要提示===============

        # 创建一个名为 docker-compose.yaml 的新文件
        local docker_compose_file="$DOCKER_COMPOSE_FILE_REDIS"

        # 如果存在 docker-compose.yaml 执行docker compose down
        if [ -f "$docker_compose_file" ]; then
            sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS" down || true # 删除容器
            touch "$docker_compose_file"
        fi
        cat >"$docker_compose_file" <<-EOM
services:
EOM

        # 单节点,将主从节点设置为 1，从节点设置为 0
        if [ "$is_redis_cluster" == "n" ]; then
            MASTER_COUNT=1
            SLAVE_COUNT=0
        fi

        cluster_urls="" # 集群节点地址
        redis_ips=""    # ip地址拼接
        # 追加写入 docker-compose 配置文件
        for ((port = REDIS_BASE_PORT; port < REDIS_BASE_PORT + MASTER_COUNT + SLAVE_COUNT; port++)); do
            port_cluster=$((port + 10000))                                     # port_cluster 自增 集群监控端口
            ip_node="$IPV4_BASE_REDIS.$(((port - REDIS_BASE_PORT + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关

            DOCKER_NAMES+=("redis-$IMG_VERSION_REDIS-$port")      # 增加主节点
            cluster_urls+="redis-$IMG_VERSION_REDIS-$port:$port " # 集群节点 名称
            redis_ips+="$ip_node "                                # 集群节点地址

            # 追加写入主节点 docker-compose 配置文件
            cat >>"$docker_compose_file" <<-EOM

  redis-$IMG_VERSION_REDIS-$port:
    image: 'redis:$IMG_VERSION_REDIS'
    restart: always
    container_name: redis-$IMG_VERSION_REDIS-$port
    user: '$DB_UID:$DB_GID' # DOCKERFILE 中设置的用户
    volumes:
      - $DATA_VOLUME_DIR/redis/data/$port:/data
      - $DATA_VOLUME_DIR/redis/conf/$port:/usr/local/etc/redis # 配置文件需要指定文件夹否则会无法写入
      - $DATA_VOLUME_DIR/redis/log/$port:/var/log/redis

    command: [/usr/local/etc/redis/redis.conf] # 指定配置文件重新加载

    ports: # 映射端口，对外提供服务
      - "$port:$port" # redis 的服务端口
      - "$port_cluster:$port_cluster" # redis 集群监控端口
    # stdin_open: true # 标准输入打开
    # tty: true # 终端打开
    # privileged: true # 拥有容器内命令执行的权限

    networks: # docker 网络设置
      $BRIDGE_REDIS: # 网络名称
          ipv4_address: $ip_node
EOM
        done

        # 删除历史数据 redis
        if [ "$all_remove_data" == "y" ]; then

            # 删除历史数据
            sudo rm -rf "$DATA_VOLUME_DIR/redis"

            if [ ! -d "$DATA_VOLUME_DIR" ]; then
                # 如果不存在则创建
                setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
            fi

            # 创建新目录
            setup_directory "$DB_UID" "$DB_GID" 755 \
                "$DATA_VOLUME_DIR/redis" \
                "$DATA_VOLUME_DIR/redis/data" \
                "$DATA_VOLUME_DIR/redis/conf" \
                "$DATA_VOLUME_DIR/redis/log"

            # 删除原来配置 使用新建的配置文件
            for ((port = REDIS_BASE_PORT; port < REDIS_BASE_PORT + MASTER_COUNT + SLAVE_COUNT; port++)); do

                ip_node="$IPV4_BASE_REDIS.$(((port - REDIS_BASE_PORT + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关
                setup_directory "$DB_UID" "$DB_GID" 755 \
                    "$DATA_VOLUME_DIR/redis/data/$port" \
                    "$DATA_VOLUME_DIR/redis/conf/$port" \
                    "$DATA_VOLUME_DIR/redis/log/$port"

                # 默认集群配置为空
                config_cluster=""

                # 添加集群配置
                if [ "${is_redis_cluster,,}" = "y" ]; then
                    # 使用 heredoc 将多行文本赋值给变量
                    config_cluster=$(
                        cat <<EOF
### 复制（主从同步）
# 是否为复制只读
slave-read-only yes

# 主节点 密码
masterauth "$REDIS_PASSWORD"

### 集群配置
# 开启集群模式至少三个主节点
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 15000

# #######CLUSTER DOCKER/NAT support#######
# 集群和哨兵不能使用 docker 的 NAT 模式 使用 host 模式
# 参考:https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/
# cluster-announce-ip redis-$IMG_VERSION_REDIS-$port
# cluster-announce-ip $HOST_INTRANET_IP

cluster-announce-ip $ip_node
cluster-announce-port $port
cluster-announce-bus-port 1$port
EOF
                    )

                fi

                # redis.conf 配置文件
                content=$(
                    cat <<EOL
# Redis 配置文件
######################

### 一般设置
# 绑定 IP (默认情况下,Redis 只允许本地连接)
# bind 127.0.0.1 $ip_node
# bind 127.0.0.1
bind 0.0.0.0

# Redis 监听端口 (默认为 6379)
port $port

# 启用保护模式:no, 关闭 docker 外部才能访问。
protected-mode no

# 设置密码
requirepass "$REDIS_PASSWORD"

### 客户端设置
# 客户端空闲超时时间(单位:秒),设置成 0 则表示不限制客户端空闲时间
timeout 0

# 最大客户端连接数,默认为 10000
maxclients 10000

### 数据存储
# 指定数据文件存放目录
dir ./

# 如果至少有 1 个 key 在 900 秒内被修改了,则生成 RDB 文件
save 900 1

# 如果至少有 10 个 key 在 300 秒内被修改了,则生成 RDB 文件
save 300 10

# 如果至少有 10000 个 key 在 60 秒内被修改了,则生成 RDB 文件
save 60 10000

# RDB 文件名称
dbfilename dump.rdb

# 是否启用 RDB 文件压缩
rdbcompression yes

# 是否使用 CRC64 校验 RDB 文件
rdbchecksum yes

### AOF 
# 启用 AOF 持久化
appendonly yes

# AOF 历史策略
appendfsync everysec

# AOF 文件名称
appendfilename "appendonly.aof"

# 是否重写 AOF 文件
auto-aof-rewrite-min-size 64mb
auto-aof-rewrite-percentage 100

### 日志记录
# 日志等级
loglevel notice

# 日志输出类型
logfile /var/log/redis/redis-server.log

### 系统资源限制
# TCP backlog,根据指定的数量来控制 TCP 连接数
tcp-backlog 511

### 内存管理
# Redis 最大使用内存
# maxmemory 0

# Redis 内存回收策略
maxmemory-policy volatile-lru

# 指定内存样本大小
maxmemory-samples 5

$config_cluster

# ####### CLUSTER DOCKER/NAT support #######

### 其他配置
# 数据库 index 默认为 0
# databases 0

EOL
                )

                # 覆盖写入
                over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content" "$DATA_VOLUME_DIR/redis/conf/$port/redis.conf"
            done

            log_info "已删除 redis 历史数据"
        else
            log_info "未删除 redis 历史数据"
        fi

        # 网络配置
        cat >>"$docker_compose_file" <<-EOM
networks: # 网络配置
  $BRIDGE_REDIS: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_REDIS # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_REDIS" # 子网
          gateway: "$GATEWAY_REDIS" # 网关
EOM
        # 启动 redis 容器
        start_db_redis

        # 创建 redis 集群
        if [ "$all_remove_data" == "y" ] && [ "$is_redis_cluster" = "y" ]; then
            log_info "redis 集群开启"
            redis_name="redis-$IMG_VERSION_REDIS-$REDIS_BASE_PORT"
            # 创建 redis 集群 执行命令 输入 yes
            REDIS_CLI_COMMAND="echo yes | redis-cli -h $redis_name -p $REDIS_BASE_PORT -a $REDIS_PASSWORD --cluster-replicas 1 --cluster create $cluster_urls"

            # 打印交互命令
            log_debug "执行命令: sudo docker exec -it $redis_name /bin/bash -c \"$REDIS_CLI_COMMAND\""

            # 执行命令不使用交互
            sudo docker exec -i "$redis_name" /bin/bash -c "$REDIS_CLI_COMMAND"
            log_info "redis 集群创建完成"
        fi
    }

    log_timer "redis 启动完毕" run

    log_info "redis 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 停止并删除 redis 数据库
delete_db_redis() {
    log_debug "run delete_db_redis"

    local is_delete
    is_delete=$(read_user_input "确认停止 redis 服务并删除数据吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        # 停止容器
        stop_db_redis

        # 删除数据库数据
        sudo rm -rf "$DATA_VOLUME_DIR/redis"
    fi
}
