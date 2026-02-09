#!/bin/bash
# FilePath    : blog-tool/options/all.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 展示选项 all

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# 定义选项和函数名称, 使用:分割的有序列表
OPTIONS_ALL=(
    # 系统配置
    "新增必要运行用户:add_group_user"
    "设置主机名称:set_hostname"
    "添加 Backports 源:add_backports_apt_source"
    "删除 Backports 源:del_backports_apt_source"
    "安装依赖软件:install_common_software"
    "配置 ssh:set_ssh_config"
    "安装所有更新:install_all_update"
    "系统常规升级:apt_full_upgrade"
    "系统大版本升级:update_apt_source_and_full_upgrade"

    # 网络配置
    "局域网静态 IP 配置:set_host_intranet_ip"

    # SSL 证书
    "生成自定义证书:gen_cert"

    # 安装 docker
    "最快 docker ce 源:find_fastest_docker_mirror"
    "安装 docker:install_docker"
    "手动安装 docker:manual_install_docker"
    "设置 daemon:set_daemon_config"
    "卸载 docker:uninstall_docker"
    "生成自定义证书:gen_cert"

    # 安装 docker
    "最快 docker ce 源:find_fastest_docker_mirror"
    "安装 docker:install_docker"
    "手动安装 docker:manual_install_docker"
    "设置 daemon:set_daemon_config"
    "卸载 docker:uninstall_docker"

    # 拉取镜像
    "拉取开发镜像:pull_docker_image_dev"
    "拉取生产数据库镜像:pull_docker_image_pro_db"
    "拉取生产数据库镜像-计费中心:pull_docker_image_pro_db_billing_center"

    # 私有仓库
    "运行私有分发镜像仓库:docker_run_registry"

    # 安装数据库
    "安装所有数据库:install_database"
    "删除所有数据库:delete_database"
    "全新安装所有数据库:reset_install_database"
    "安装所有数据库-计费中心:install_database_billing_center"
    "删除所有数据库-计费中心:delete_database_billing_center"
    "安装 pgsql:install_db_pgsql"
    "安装 pgsql 计费中心:install_db_pgsql_billing_center"
    "删除 pgsql:delete_db_pgsql"
    "删除 pgsql 计费中心:delete_db_pgsql_billing_center"
    "安装 redis:install_db_redis"
    "安装 redis 计费中心:install_db_redis_billing_center"
    "删除 redis:delete_db_redis"
    "删除 redis 计费中心:delete_db_redis_billing_center"
    "安装 es 和 kibana:install_es_kibana"
    "删除 es 和 kibana:delete_es_kibana"

    # 构建编译过程镜像
    "构建 billing center 镜像:docker_build_billing_center_env"
    "构建 server env 镜像:docker_build_server_env"
    "构建 client env 镜像:docker_build_client_env"

    # 构建并推送结果镜像
    "构建并推送 billing center:docker_build_push_billing_center"
    "构建并推送 server client:docker_build_push_server_client"
    "server 产物复制到本地:server_artifacts_copy_to_local"
    "构建并推送 server:docker_build_push_server"
    "仅推送 server:docker_push_server"
    "client 产物复制到本地:client_artifacts_copy_to_local"
    "构建并推送 client:docker_build_push_client"
    "仅推送 client:docker_push_client"

    # 管理文件目录
    "创建 billing center 配置目录:mkdir_billing_center_volume"
    "创建 server 配置目录:mkdir_server_volume"
    "创建 client 配置目录:mkdir_client_volume"
    "创建 server client 配置目录:mkdir_server_client_volume"
    "删除 billing center 配置目录:remove_billing_center_volume"
    "删除 server 配置目录:remove_server_volume"
    "删除 client 配置目录:remove_client_volume"
    "删除 server client 配置目录:remove_server_client_volume"

    # 拉取生产镜像
    "拉取 billing center 镜像:docker_pull_billing_center"
    "拉取 server 镜像:docker_pull_server"
    "拉取 client 镜像:docker_pull_client"
    "拉取 server client 镜像:docker_pull_server_client"

    # 启动服务
    "安装 billing center 服务:docker_billing_center_install"
    "打印计费中心 CA 证书:ca_cert_byte_print"
    "安装 server 服务:docker_server_install"
    "插入测试数据:insert_demo_data"
    "注册管理员:register_admin"
    "重置用户密码:reset_password"
    "安装 client 服务:docker_client_install"
    "安装 server client 服务:docker_server_client_install"

    # 服务管理
    "启动 billing center 服务:docker_billing_center_start"
    "启动 server 服务:docker_server_start"
    "启动 client 服务:docker_client_start"
    "启动 server client 服务:docker_server_client_start"
    "停止 billing center 服务:docker_billing_center_stop"
    "停止 server 服务:docker_server_stop"
    "停止 client 服务:docker_client_stop"
    "停止 server client 服务:docker_server_client_stop"
    "重启 billing center 服务:docker_billing_center_restart"
    "重启 server 服务:docker_server_restart"
    "重启 client 服务:docker_client_restart"
    "重启 server client 服务:docker_server_client_restart"

    # 一键安装
    "一键安装:one_click_install"

    # 全部服务管理
    "停止所有服务(备份|恢复):docker_all_stop"
    "重启所有服务:docker_all_restart"

    # 版本管理
    "查看 server 版本:show_server_versions"
    "查看 client 版本:show_client_versions"
    "升级或回滚 billing center:start_or_rollback_billing_center_by_version"
    "升级或回滚 server:start_or_rollback_server_by_version"
    "升级或回滚 client:start_or_rollback_client_by_version"

    # 删除服务
    "删除 billing center 服务:docker_billing_center_delete"
    "删除 server 服务:docker_server_delete"
    "删除 client 服务:docker_client_delete"
    "删除 server client 服务:docker_server_client_delete"

    # 删除镜像
    "删除 billing center 镜像:docker_rmi_billing_center"
    "删除 server 镜像:docker_rmi_server"
    "删除 client 镜像:docker_rmi_client"
    "删除 server client 镜像:docker_rmi_server_client"

    # 清理 docker
    "清理 docker:docker_clear_cache"

    # 监控日志
    "监控 server 日志:blog_server_logs"
    "监控 billing center 日志:billing_center_logs"

    "退出:exit_script"
)

OPTIONS_USER=(
    "一键安装:one_click_install"
    # 系统配置
    "安装依赖软件:install_common_software"
    "新增必要运行用户:add_group_user"

    # SSL 证书
    "生成自定义证书:gen_cert"

    # 安装 docker
    "安装 docker:install_docker"

    # 拉取镜像
    "拉取生产镜像:pull_docker_image_pro_all"

    # 安装数据库
    "安装数据库:install_database"

    # 拉取生产镜像
    "安装 server client 服务:docker_server_client_install"

    # 监控日志
    "监控 server 日志:blog_server_logs"

    # 服务管理
    "重启 server 服务:docker_server_restart"
    "重启 client 服务:docker_client_restart"

    # 版本管理
    "查看 server 版本:show_server_versions"
    "查看 client 版本:show_client_versions"
    "升级或回滚 server:start_or_rollback_server_by_version"
    "升级或回滚 client:start_or_rollback_client_by_version"

    # 全部服务管理
    "停止所有服务(备份|恢复):docker_all_stop"
    "重启所有服务:docker_all_restart"

    # 清理 docker
    "清理 docker:docker_clear_cache"

    "退出:exit_script"
)

OPTIONS_USER_NOT_SHOW=(
    "手动安装 docker:manual_install_docker"
    "拉取生产数据库镜像:pull_docker_image_pro_db"

    # 分别安装数据库
    "安装 pgsql:install_db_pgsql"
    "删除 pgsql:delete_db_pgsql"
    "安装 redis:install_db_redis"
    "删除 redis:delete_db_redis"
    "安装 es 和 kibana:install_es_kibana"
    "删除 es 和 kibana:delete_es_kibana"
    "全新安装所有数据库:reset_install_database"

    # 拉取
    "拉取 server 镜像:docker_pull_server"
    "拉取 client 镜像:docker_pull_client"
    "拉取 server client 镜像:docker_pull_server_client"

    "插入测试数据:insert_demo_data"
    "注册管理员:register_admin"
    "重置用户密码:reset_password"

    # 分别创建目录
    "创建 server 配置目录:mkdir_server_volume"
    "创建 client 配置目录:mkdir_client_volume"

    # 安装服务
    "安装 server 服务:docker_server_install"
    "安装 client 服务:docker_client_install"

    # 服务管理
    "启动 server 服务:docker_server_start"
    "启动 client 服务:docker_client_start"
    "启动 server client 服务:docker_server_client_start"
    "停止 server 服务:docker_server_stop"
    "停止 client 服务:docker_client_stop"
    "停止 server client 服务:docker_server_client_stop"
    "重启 server client 服务:docker_server_client_restart"

    # 删除目录
    "删除 server 配置目录:remove_server_volume"
    "删除 client 配置目录:remove_client_volume"

    # 删除服务
    "删除 server 服务:docker_server_delete"
    "删除 client 服务:docker_client_delete"

    "最快 docker ce 源:find_fastest_docker_mirror"
    "设置 daemon:set_daemon_config"
    "卸载 docker:uninstall_docker"
)

# 合并数组用户 is_valid_func
OPTIONS_USER_VALID=(
    "${OPTIONS_USER[@]}"
    "${OPTIONS_USER_NOT_SHOW[@]}"
)

OPTIONS_BILLING_CENTER=(
    # 系统配置
    "安装依赖软件:install_common_software"
    "新增必要运行用户:add_group_user"

    # 安装 docker
    "安装 docker:install_docker"

    # 安装数据库
    "拉取生产数据库镜像:pull_docker_image_pro_db_billing_center"
    "安装所有数据库-计费中心:install_database_billing_center"
    "删除所有数据库-计费中心:delete_database_billing_center"

    # 拉取镜像
    "拉取 billing center 镜像:docker_pull_billing_center"

    # 启动服务
    "安装 billing center 服务:docker_billing_center_install"
    "打印计费中心 CA 证书:ca_cert_byte_print"

    # 服务管理
    "启动 billing center 服务:docker_billing_center_start"
    "停止 billing center 服务:docker_billing_center_stop"
    "重启 billing center 服务:docker_billing_center_restart"

    # 版本管理
    "升级或回滚 billing center:start_or_rollback_billing_center_by_version"

    # 删除服务
    "删除 billing center 服务:docker_billing_center_delete"

    # 删除镜像
    "删除 billing center 镜像:docker_rmi_billing_center"

    # 监控日志
    "监控 billing center 日志:billing_center_logs"

    # 清理 docker
    "清理 docker:docker_clear_cache"

    "退出:exit_script"
)

OPTIONS_BILLING_CENTER_NOT_SHOW=(
    "手动安装 docker:manual_install_docker"
    "最快 docker ce 源:find_fastest_docker_mirror"
    "设置 daemon:set_daemon_config"
    "卸载 docker:uninstall_docker"

    # 创建目录
    "创建 billing center 配置目录:mkdir_billing_center_volume"
    "删除 billing center 配置目录:remove_billing_center_volume"

    # 分别安装数据库
    "安装 pgsql 计费中心:install_db_pgsql_billing_center"
    "删除 pgsql 计费中心:delete_db_pgsql_billing_center"
    "安装 redis 计费中心:install_db_redis_billing_center"
    "删除 redis 计费中心:delete_db_redis_billing_center"
)

# 合并数组用于 is_valid_func
OPTIONS_BILLING_CENTER_VALID=(
    "${OPTIONS_BILLING_CENTER[@]}"
    "${OPTIONS_BILLING_CENTER_NOT_SHOW[@]}"
)
