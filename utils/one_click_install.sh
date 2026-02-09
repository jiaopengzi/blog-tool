#!/bin/bash
# FilePath    : blog-tool/utils/db.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 数据库工具

# 一键安装 删除数据库
one_click_install() {
    log_debug "run one_click_install"

    local is_install # 是否删除历史数据 默认不删除
    is_install=$(read_user_input "一键安装将会执行如下操作 \
    \n    1.新增必要用户 \
    \n    2.生成自定义证书 \
    \n    3.全新安装 docker (当前机器有业务在 docker 上运行，请慎用！！！)\
    \n    4.拉取镜像\
    \n    5.安装数据库\
    \n    6.安装 server client 服务\
    \n是否进行安装(默认n) [y|n]? " "n")

    if [[ "$is_install" == "y" ]]; then
        log_info "开始执行安装"

        # shellcheck disable=SC2329
        run() {
            add_group_user

            gen_cert

            echo "y" | install_docker

            echo "y" | pull_docker_image_pro_all

            reset_install_database

            {
                echo "y"
                echo "n"
            } | docker_server_client_install
        }

        log_timer "一键安装" run
    else
        log_info "退出安装"
    fi
}
