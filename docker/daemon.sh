#!/bin/bash
# FilePath    : blog-tool/docker/daemon.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : Docker 守护进程配置相关脚本

# 设置 docker daemon 配置
set_daemon_config() {
    log_debug "run set_daemon_config"

    # 检查 /etc/docker/daemon.json 文件是否存在, 如果不存在就创建它
    if [ ! -f "/etc/docker/daemon.json" ]; then
        sudo mkdir -p /etc/docker
        echo '{}' | sudo tee /etc/docker/daemon.json >/dev/null
    else
        # 备份原文件, 加上时间戳防止覆盖
        sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # 共用的 daemon 配置部分
    # live-restore: 启用后即使 docker 守护进程崩溃, 容器也会继续运行
    # log-driver: 设置日志驱动为 json-file
    # log-opts: 配置日志选项, 最大大小 100MB, 最多保留 7 个文件, 并添加 production 标签
    local common_config='
    .["live-restore"] = true |
    .["log-driver"] = "json-file" |
    .["log-opts"]["max-size"] = "100m" |
    .["log-opts"]["max-file"] = "7" |
    .["log-opts"]["labels"] = "production"'

    # 根据网络环境构建完整的 jq 过滤器
    local jq_filter
    if [[ $(curl -s ipinfo.io/country) == "CN" ]]; then
        log_debug "检测到国内网络环境, 使用国内源安装 docker"

        # 国内环境, 在公共配置基础上添加 registry-mirrors
        # 腾讯的只支持内网访问
        jq_filter="$common_config
        | .[\"registry-mirrors\"] = [
            \"https://mirror.ccs.tencentyun.com\",
            \"https://docker.xuanyuan.me\",
            \"https://docker.1ms.run\"
        ]"
    else
        log_debug "检测到非国内网络环境, 使用官方源安装 docker"

        # 非国内环境, 不需要添加 registry-mirrors
        jq_filter="$common_config"
    fi

    # 统一使用构建好的过滤器执行 jq 命令
    sudo jq "$jq_filter" /etc/docker/daemon.json | sudo tee /etc/docker/daemon.json.tmp >/dev/null

    # 验证配置文件语法是否正确; 判断回显是否包含 "configuration OK" 内容
    if sudo dockerd --validate --config-file /etc/docker/daemon.json.tmp 2>&1 | grep -q "configuration OK"; then
        log_debug "docker 日志配置语法验证通过"
    else
        log_error "docker 日志配置语法验证失败, 请检查 /etc/docker/daemon.json.tmp 文件"
        sudo rm -f /etc/docker/daemon.json.tmp
        return 1
    fi

    sudo mv /etc/docker/daemon.json.tmp /etc/docker/daemon.json

    # 重启 docker 服务使配置生效
    log_info "docker 正在重启..."
    sudo systemctl restart docker

    log_info "docker daemon 配置设置完成, 请查看 /etc/docker/daemon.json 文件"
}
