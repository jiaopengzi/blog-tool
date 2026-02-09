#!/bin/bash
# FilePath    : blog-tool/system/user.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 用户相关

# 新建不登录用户和用户组
create_user_and_group_nologin() {
    log_debug "run create_user_and_group_nologin"

    local uid=$1  # 用户 id
    local gid=$2  # 用户组 id
    local name=$3 # 用户名 和 用户组名 相同

    # 检查用户组是否存在
    if ! getent group "$gid" >/dev/null; then
        # 如果用户组不存在, 创建新的用户组
        sudo groupadd -g "$gid" "$name"
        log_info "创建不登录用户组: $name, gid: $gid"
    else
        log_warn "用户组 gid:$gid 已经存在"
    fi

    # 检查用户是否存在
    if ! id -u "$uid" >/dev/null 2>&1; then
        # 如果用户不存在, 创建新的用户
        sudo useradd -r -M -u "$uid" -g "$gid" "$name"
        sudo usermod -s /sbin/nologin "$name"

        log_info "创建不登录用户: $name, uid: $uid"
    else
        log_warn "用户 uid:$uid 已经存在"
    fi
}

# 新增用户和用户组
add_group_user() {
    log_debug "run add_group_user"

    # 创建用户任务运行的用户和组不需要登录
    create_user_and_group_nologin "$DB_UID" "$DB_GID" "$APP_NAME-database"
    create_user_and_group_nologin "$CLIENT_UID" "$CLIENT_GID" "$APP_NAME-client"
    create_user_and_group_nologin "$SERVER_GID" "$SERVER_GID" "$APP_NAME-server"
    create_user_and_group_nologin "$JPZ_UID" "$JPZ_GID" "$APP_NAME-project"

    # # 创建登录用户

    # # 检查用户组是否存在
    # if ! getent group "$SERVER_GID" >/dev/null; then
    #     # 如果用户组不存在，创建新的用户组
    #     sudo groupadd -g "$SERVER_GID" "$BLOG_USER_GROUP" # 新增用户组
    # else
    #     log_warn "gid:$SERVER_GID 已经存在."
    # fi

    # # 检查用户是否存在
    # if ! id -u "$SERVER_UID" >/dev/null 2>&1; then
    #     # 如果用户不存在, 创建新的用户
    #     sudo useradd -m -u "$SERVER_UID" -g "$SERVER_GID" "$BLOG_USER" # 新增用户 -m 创建家目录 -u 指定用户 id -g 指定用户组 id
    #     sudo usermod -aG sudo "$BLOG_USER"                             # 添加到 sudo 组
    #     sudo chsh -s /bin/bash "$BLOG_USER"                            # 设置默认 shell 为 bash
    #     echo "$BLOG_USER:<your-password>" | sudo chpasswd               # 设置默认密码
    #     sudo getent passwd "$BLOG_USER"                                # 查看新增用户

    #     # 打印提示信息
    #     log_info "用户 $BLOG_USER 已创建,并添加到 sudo 组."
    #     log_info "初始密码: <your-password>"
    #     log_warn "请及时登录并修改用户 $BLOG_USER 的初始密码."
    # else
    #     log_warn "uid:$SERVER_UID 已经存在."
    # fi
}
