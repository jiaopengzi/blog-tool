#!/bin/bash
# FilePath    : blog-tool/config/user_billing_center.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 计费中心用户配置文件, 用户可以修改.

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

#==============================用户修改的配置(billing center) 开始==============================
# pgsql 数据库配置(billing center)
POSTGRES_USER_BILLING_CENTER="billing_center"   # 数据库用户名
POSTGRES_PASSWORD_BILLING_CENTER="123456"       # 数据库用户密码
POSTGRES_DB_BILLING_CENTER="billing_center_jpz" # 应用程序数据库名称
POSTGRES_PORT_BILLING_CENTER="5433"             # 应用程序数据库端口

# redis 配置(billing center)
REDIS_BASE_PORT_BILLING_CENTER="8002"  # redis 起始端口号
REDIS_PASSWORD_BILLING_CENTER="123456" # redis 密码

# 日志级别：error(1) < warn(2) < info(3) < debug(4), 默认记录info及以上
LOG_LEVEL="debug"

# 日志文件路径, 默认在 blog-tool 根目录下
LOG_FILE="$ROOT_DIR/blog_tool.log"
#==============================用户修改的配置(billing center) 结束==============================
