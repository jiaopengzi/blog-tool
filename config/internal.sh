#!/bin/bash
# FilePath    : blog-tool/config/internal.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 内部配置文件, 用户不可修改, 除非您知道您在做什么.

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# 运行模式 dev | pro (开发环境 | 生产环境)
RUN_MODE="pro"

# 数据根目录
DATA_VOLUME_DIR="$ROOT_DIR/volume"

# 工具配置目录
BLOG_TOOL_ENV="$DATA_VOLUME_DIR/blog_tool_env"

# 基础依赖软件列表
BASE_SOFTWARE_LIST=(
    sudo
    neovim
    git
    curl
    wget
    unzip
    zip
    tar
    gzip
    ca-certificates
    net-tools
    openvswitch-switch
    openssh-server
    bc
    aptitude
    cron
    jq
    python3
)

# 检测是否安装软件的标志目录
IS_INSTALL_SOFTWARE=""

# Docker CE 镜像源列表
DOCKER_CE_SOURCES=(
    "https://mirrors.aliyun.com/docker-ce|阿里云公网"
    "http://mirrors.cloud.aliyuncs.com|阿里云内网"
    "http://mirrors.aliyuncs.com|阿里云内网经典"
    # "https://mirrors.tencent.com/docker-ce|腾讯云公网"
    # "http://mirrors.tencentyun.com/docker-ce|腾讯云内网"
    "https://mirrors.163.com/docker-ce|网易云"
    "https://mirrors.cernet.edu.cn/docker-ce|中国教育网"
    "https://mirrors.tuna.tsinghua.edu.cn/docker-ce|清华大学"
    "https://mirrors.huaweicloud.com/docker-ce|华为云"
    "https://mirrors.cmecloud.cn/docker-ce|中国移动云"
    # "https://mirrors.volces.com/docker|火山引擎"
    "https://mirror.azure.cn/docker-ce|Azure 中国"
    "https://mirrors.pku.edu.cn/docker-ce|北京大学"
    "https://mirrors.zju.edu.cn/docker-ce|浙江大学"
    "https://mirrors.nju.edu.cn/docker-ce|南京大学"
    "https://mirror.sjtu.edu.cn/docker-ce|上海交通大学"
    "https://mirrors.cqupt.edu.cn/docker-ce|重庆邮电大学"
    "https://mirrors.ustc.edu.cn/docker-ce|中国科学技术大学"
    "https://mirror.iscas.ac.cn/docker-ce|中国科学院"
    "https://download.docker.com|官方源"
)

# docker hub 用户名
DOCKER_HUB_REGISTRY="docker.io" # docker hub 仓库地址
DOCKER_HUB_OWNER="jiaopengzi"   # docker hub 用户名

START_TIME=$(date +%s) # 记录开始时间
APP_NAME="jpz"         # 应用名称 不能包含大写字母和字符
DISPLAY_COLS=3         # 输出显示的列数, 用于输出对齐, 一般为 3, 可以根据实际情况调整

# 检查 ifconfig 是否存在
if command -v ifconfig >/dev/null 2>&1; then
    # 默认内网 IP
    HOST_INTRANET_IP=$(ifconfig | sed -n '/^[eE]/,+3p' | grep 'inet ' | awk '{print $2}')

    # 默认子网掩码
    HOST_INTRANET_MARK=$(ifconfig | sed -n '/^[eE]/,+3p' | grep 'inet ' | awk '{print $4}')
else
    # 如果 ifconfig 不存在, 使用回环地址
    HOST_INTRANET_IP="127.0.0.1"
    HOST_INTRANET_MARK="255.0.0.0"
fi

# 私有 ca 证书存放目录
CA_CERT_DIR="$DATA_VOLUME_DIR/certs_ca"
# 证书有效期(天)
CERT_DAYS_VALID=3650

# docker 镜像版本
IMG_VERSION_REDIS="8.4.0"    # redis 版本
IMG_VERSION_PGSQL="18.1"     # pgsql 版本
IMG_VERSION_PGSQL_MAJOR="18" # pgsql主要版本号

# https://release.infinilabs.com/analysis-ik/stable/elasticsearch-analysis-ik-9.2.4.zip
# 优先查看分词工具是否更新到最新版本, 以分词工具的版本为准, 其他版本保持一致
IMG_VERSION_ES="9.2.4"     # 7.17.28 8.18.1
IMG_VERSION_KIBANA="9.2.4" # 与 es 保持版本一致

# 需要创建的运行用户
JPZ_UID=2025    # 服务端用户
JPZ_GID=2025    # 服务端用户组
DB_UID=999      # 数据库用户 id
DB_GID=999      # 数据库用户组 id
ES_UID=1000     # es 用户 id
ES_GID=0        # es 用户组 id
KIBANA_UID=1000 # kibana 用户 id
KIBANA_GID=0    # kibana 用户组 id
CLIENT_UID=101  # 前端用户 id (nginx)
CLIENT_GID=101  # 前端用户组 id (nginx)
SERVER_UID=2024 # 后端用户 id (Dockerfile自行设置)
SERVER_GID=2024 # 后端用户组 id (Dockerfile自行设置)

# 私有仓库
BRIDGE_REGISTRY="$APP_NAME-registry$IMG_VERSION_REGISTRY-bridge-net" # 私有仓库 网桥
IPV4_BASE_REGISTRY="178.18.10"                                       # 私有仓库 内网起始 IP 段
SUBNET_REGISTRY="$IPV4_BASE_REGISTRY.0/24"                           # 私有仓库 子网网段
GATEWAY_REGISTRY="$IPV4_BASE_REGISTRY.1"                             # 私有仓库 网关

# pgsql docker 参数
BRIDGE_PGSQL="$APP_NAME-pgsql-bridge-net" # pgsql 网桥
IPV4_BASE_PGSQL="178.18.11"               # pgsql 内网起始 IP 段
SUBNET_PGSQL="$IPV4_BASE_PGSQL.0/24"      # pgsql 子网网段
GATEWAY_PGSQL="$IPV4_BASE_PGSQL.1"        # pgsql 网关

# pgsql 数据库 参数
POSTGRES_DOCKER_NAME="pgsql-$IMG_VERSION_PGSQL" # 服务名称

# pgsql ip
IPV4_ADDRESS_START=2
POSTGRES_IP="$IPV4_BASE_PGSQL.$((IPV4_ADDRESS_START % 256))" # 自增 从 2 开始, 1 为网关

# pgsql docker 参数(billing center)
BRIDGE_PGSQL_BILLING_CENTER="$APP_NAME-billing-center-pgsql-bridge-net" # pgsql 网桥
IPV4_BASE_PGSQL_BILLING_CENTER="178.18.12"                              # pgsql 内网起始 IP 段
SUBNET_PGSQL_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.0/24"      # pgsql 子网网段
GATEWAY_PGSQL_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.1"        # pgsql 网关

# pgsql 数据库 参数(billing center)
POSTGRES_DOCKER_NAME_BILLING_CENTER="pgsql-$IMG_VERSION_PGSQL-billing-center" # 服务名称

# pgsql ip(billing center)
POSTGRES_IP_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.$((IPV4_ADDRESS_START % 256))" # 自增 从 2 开始, 1 为网关

# redis docker 参数
MASTER_COUNT=3                            # 主节点数量
SLAVE_COUNT=3                             # 从节点数量
BRIDGE_REDIS="$APP_NAME-redis-bridge-net" # redis 网桥
IPV4_BASE_REDIS="178.18.13"               # redis 内网起始 IP 段
SUBNET_REDIS="$IPV4_BASE_REDIS.0/24"      # redis 子网网段
GATEWAY_REDIS="$IPV4_BASE_REDIS.1"        # redis 网关

# redis 开始和结束 ip
REDIS_START_IP=$IPV4_BASE_REDIS.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
REDIS_END_IP=$IPV4_BASE_REDIS.$(((MASTER_COUNT + SLAVE_COUNT + 1) % 256))

# redis docker 参数(billing center)
BRIDGE_REDIS_BILLING_CENTER="$APP_NAME-redis-billing-center-bridge-net" # redis 网桥
IPV4_BASE_REDIS_BILLING_CENTER="178.18.14"                              # redis 内网起始 IP 段
SUBNET_REDIS_BILLING_CENTER="$IPV4_BASE_REDIS_BILLING_CENTER.0/24"      # redis 子网网段
GATEWAY_REDIS_BILLING_CENTER="$IPV4_BASE_REDIS_BILLING_CENTER.1"        # redis 网关

# redis 开始和结束 ip(billing center)
REDIS_START_IP_BILLING_CENTER=$IPV4_BASE_REDIS_BILLING_CENTER.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
REDIS_END_IP_BILLING_CENTER=$IPV4_BASE_REDIS_BILLING_CENTER.$(((MASTER_COUNT + SLAVE_COUNT + 1) % 256))

# es docker 参数
BRIDGE_ES="$APP_NAME-es-bridge-net" # es 网桥
IPV4_BASE_ES="178.18.15"            # es 内网起始 IP 段
SUBNET_ES="$IPV4_BASE_ES.0/24"      # es 子网网段
GATEWAY_ES="$IPV4_BASE_ES.1"        # es 网关

# es 开始和结束 ip
ES_START_IP=$IPV4_BASE_ES.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
ES_END_IP=$IPV4_BASE_ES.$(((ES_NODE_COUNT + 1) % 256))

# ES 配置
ES_CLUSTER_NAME=docker-cluster # 集群名称
ES_LICENSE=basic               # 设置 es 的许可证, 默认为 basic
ES_PORT=9200                   # es 端口, 如果使用 127.0.0.1:9200 则表示只能本地访问
KIBANA_PORT=5601               # kibana 端口

#============================== Elasticsearch 重要提示 ==============================
# 优先设置 mem_limit 限制内存使用, 而不设置 ES_JAVA_OPTS, 让 ES 自动分配内存使用, 最小值为 1G, 实践中发现至少1.5G 才能稳定运行
# 如果是小内存机器, 通过设置 ES_JAVA_OPTS 限制堆内存大小, 搭配 mem_limit 使用, 确保 mem_limit 大于 ES_JAVA_OPTS 2倍以上
# 同时关注 _cluster/health 的状态值

# 1G = 1024 * 1024 * 1024 = 1073741824
# 1.2G = 1.2 * 1024 * 1024 * 1024 = 1288490188
# 2G = 2 * 1024 * 1024 * 1024 = 2147483648
MEM_LIMIT_ES="mem_limit: 1288490188"     # 内存限制 es (bytes)
MEM_LIMIT_KIBANA="mem_limit: 1073741824" # 内存限制 kibana

# Elasticsearch 堆内存推荐设置参考 (仅供参考, 具体还需根据实际业务场景调整)

# | 服务器总内存   | 推荐 ES 堆内存                                    | 适用场景                          |
# | ------------ | ----------------------------------------------- | ---------------------------------|
# | 2GB          | 256MB ~ 512MB 但极不推荐生产                      | 几乎不可行                         |
# | 4GB          | 512MB ~ 2GB                                     | 小型部署、低并发、测试、预发布环境     |
# | 8GB          | 2GB ~ 4GB                                       | 中小型业务                         |
# | 16GB         | 4GB ~ 8GB                                       | 中等规模业务                       |
# | 32GB         | 8GB ~ 16GB                                      | 中大型业务                         |
# | 64GB+        | 16GB ~ 32GB (不超过 32GB)                        | 大型业务, 多节点分片                |

# 小内存机器设置 es 堆内存大小 (bytes)
ES_JAVA_OPTS_ENV="- ES_JAVA_OPTS=-Xms512m -Xmx512m"
#============================== Elasticsearch 重要提示 ==============================

# server
BRIDGE_SERVER="$APP_NAME-bridge-server" # server 网桥
IPV4_BASE_SERVER="178.18.16"            # SERVER 内网起始 IP 段
SUBNET_SERVER="$IPV4_BASE_SERVER.0/24"  # server 子网网段
GATEWAY_SERVER="$IPV4_BASE_SERVER.1"    # server 网关

# server(billing center)
BRIDGE_BILLING_CENTER="$APP_NAME-bridge-billing-center" # server 网桥
IPV4_BASE_BILLING_CENTER="178.18.17"                    # SERVER 内网起始 IP 段
SUBNET_BILLING_CENTER="$IPV4_BASE_BILLING_CENTER.0/24"  # server 子网网段
GATEWAY_BILLING_CENTER="$IPV4_BASE_BILLING_CENTER.1"    # server 网关

# client
BRIDGE_CLIENT="$APP_NAME-bridge-client"    # client 网桥
IPV4_BASE_CLIENT="178.18.18"               # CLIENT 内网起始 IP 段
SUBNET_CLIENT="$IPV4_BASE_CLIENT.0/24"     # client 子网网段
GATEWAY_CLIENT="$IPV4_BASE_CLIENT.1"       # client 网关
CERTS_NGINX="$DATA_VOLUME_DIR/certs_nginx" # nginx 证书

# docker compose 文件
DOCKER_COMPOS_DIR="$DATA_VOLUME_DIR/docker_compose_files"
DOCKER_COMPOSE_FILE_PGSQL="$DOCKER_COMPOS_DIR/compose-pgsql.yaml"
DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-pgsql-billing-center.yaml"
DOCKER_COMPOSE_FILE_REDIS="$DOCKER_COMPOS_DIR/compose-redis.yaml"
DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-redis-billing-center.yaml"
DOCKER_COMPOSE_FILE_ES="$DOCKER_COMPOS_DIR/compose-es.yaml"
DOCKER_COMPOSE_FILE_SERVER="$DOCKER_COMPOS_DIR/compose-server.yaml"
DOCKER_COMPOSE_FILE_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-billing-center.yaml"
DOCKER_COMPOSE_FILE_CLIENT="$DOCKER_COMPOS_DIR/compose-client.yaml"

# docker compose 项目名称
DOCKER_COMPOSE_PROJECT_NAME_SERVER="$APP_NAME-server"
DOCKER_COMPOSE_PROJECT_NAME_PGSQL="$APP_NAME-pgsql"
DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER="$APP_NAME-pgsql-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_REDIS="$APP_NAME-redis"
DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER="$APP_NAME-redis-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_ES="$APP_NAME-es"
DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER="$APP_NAME-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_CLIENT="$APP_NAME-client"

# 临时文件存放解码后的 python 脚本内容
PY_SCRIPT_FILE="/tmp/embedded_python_main.py"

WEB_INSTALL_SERVER_TIPS="当前需要全新安装 server 服务，会使用初始化覆盖原有配置，是否进行全新安装 \n默认选择n [y|n]? "
WEB_SET_DB_TIPS="\n================================\n是否使用前端网页填写数据库信息?\n\n说明\n  如果自行单独设置数据就选择 y.\n  如果使用当前脚本工具安装了数据就选择 n.\n默认选择n [y|n]? "
