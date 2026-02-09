#!/bin/bash
# FilePath    : blog-tool/config/user.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 用户配置文件, 用户可以修改.

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

#==============================用户修改的配置 开始==============================
# 域名配置
DOMAIN_NAME=""       # 访问域名, 请确保域名已解析到当前服务器IP地址
PUBLIC_IP_ADDRESS="" # 公网IP地址

# pgsql 数据库配置
POSTGRES_USER="user_blog"     # 数据库用户名
POSTGRES_PASSWORD="123456"    # 数据库用户密码
POSTGRES_DB="blog_server_jpz" # 应用程序数据库名称
POSTGRES_PORT="5432"          # 应用程序数据库名称

# redis 配置
REDIS_BASE_PORT="7002"  # redis 起始端口号
REDIS_PASSWORD="123456" # redis 密码

# es 配置
ES_NODE_COUNT="1"         # 节点数量
ELASTIC_PASSWORD="123456" # 设置 es 的密码, 至少6个字符, 用户名为 elastic
KIBANA_PASSWORD="123456"  # 设置 kibana 的密码, 至少6个字符, 用户名为 kibana_system

# 日志级别：error(1) < warn(2) < info(3) < debug(4), 默认记录info及以上
LOG_LEVEL="debug"

# 日志文件路径, 默认在 blog-tool 根目录下
LOG_FILE="$ROOT_DIR/blog_tool.log"
#==============================用户修改的配置 结束==============================
