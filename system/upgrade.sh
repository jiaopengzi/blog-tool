#!/bin/bash
# FilePath    : blog-tool/system/upgrade.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 系统升级

# apt 全量升级
apt_full_upgrade() {
    log_debug "run apt_full_upgrade"

    sudo apt update
    sudo apt full-upgrade -y

    # 清理现场
    sudo apt autoclean
    sudo apt autoremove -y

    # 查看当前系统版本
    log_debug "当前系统版本信息:"
    lsb_release -a
    cat /etc/debian_version
}

# 更新 apt 源从 bookworm(12) 到 trixie(13)
update_apt_source() {
    log_debug "run update_apt_source"

    local sources_list="/etc/apt/sources.list"
    local sources_list_d="/etc/apt/sources.list.d"

    # 文件存在就删除原来的配置
    if [ -f "$sources_list" ]; then
        # 先备份在替换
        sudo cp "$sources_list" "$sources_list.bak_$(date +%Y%m%d%H%M%S)"
        sudo cp -r "$sources_list_d" "$sources_list_d.bak_$(date +%Y%m%d%H%M%S)"

        # 打印备份信息
        log_info "备份 sources.list 到 $sources_list.bak_$(date +%Y%m%d%H%M%S)"
        log_info "备份 sources.list.d 到 $sources_list_d.bak_$(date +%Y%m%d%H%M%S)"

        sudo sed -i "s/$OLD_SYS_VERSION/$NEW_SYS_VERSION/g" "$sources_list"
        # 替换所有 .list 文件中的内容
        sudo find /etc/apt/sources.list.d/ -name "*.list" -exec sed -i "s/$OLD_SYS_VERSION/$NEW_SYS_VERSION/g" {} \;
    fi
}

# 更新 apt 源并执行全量升级
update_apt_source_and_full_upgrade() {
    log_debug "run update_apt_source_and_full_upgrade"

    # 用户确认
    log_warn "请确保您已经备份了重要数据, 升级过程中可能会出现不可预知的问题."
    read -r -p "您确定要将系统从 $OLD_SYS_VERSION 升级到 $NEW_SYS_VERSION 吗? (y/n): " confirm
    if [[ $confirm != "y" ]]; then
        log_info "用户取消升级"
        return
    fi

    log_info "开始更新 apt 源从 $OLD_SYS_VERSION 到 $NEW_SYS_VERSION"
    update_apt_source

    log_info "更新 apt 源完成, 开始执行 apt 全量升级"

    apt_full_upgrade
    log_info "apt 全量升级完成"
}
