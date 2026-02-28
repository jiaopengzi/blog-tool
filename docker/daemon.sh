#!/bin/bash
# FilePath    : blog-tool/docker/daemon.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : Docker 守护进程配置相关脚本

# 设置 docker daemon 配置
set_daemon_config() {
    log_debug "run set_daemon_config"

    local target_dir="/etc/docker"
    local target_file="/etc/docker/daemon.json"
    local validate_cmd="sudo dockerd --validate --config-file"

    # 检查并备份
    if [ ! -f "$target_file" ]; then
        log_debug "docker daemon 配置文件不存在, 创建新文件"
        sudo mkdir -p "$target_dir"
        echo '{}' | sudo tee "$target_file" >/dev/null
    else
        log_debug "docker daemon 配置文件已存在, 进行备份"
        sudo cp "$target_file" "${target_file}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # 使用 heredoc 创建配置文件
    local tmp_file="$target_file.tmp"

    # 创建基础配置
    # 共用的 daemon 配置部分
    # live-restore: 启用后即使 docker 守护进程崩溃, 容器也会继续运行
    # log-driver: 设置日志驱动为 json-file
    # log-opts: 配置日志选项, 最大大小 100MB, 最多保留 7 个文件, 并添加 production 标签
    cat >"$tmp_file" <<'EOF'
{
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "7",
    "labels": "production"
  }
EOF

    # 根据网络环境添加镜像加速
    if [[ $(curl -s --max-time 5 ipinfo.io/country) == "CN" ]]; then
        log_debug "检测到国内网络环境, 使用国内镜像加速"
        cat >>"$tmp_file" <<'EOF'
  ,
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
EOF
    fi

    # 关闭 JSON
    cat >>"$tmp_file" <<'EOF'
}
EOF

    # 验证配置
    if $validate_cmd "$tmp_file" >/dev/null 2>&1; then
        log_debug "docker 日志配置语法验证通过"
    else
        log_error "docker 日志配置语法验证失败, 请检查 $tmp_file 文件"
        log_error "文件内容:"
        sudo cat "$tmp_file"
        sudo rm -f "$tmp_file"
        return 1
    fi

    # 应用配置
    sudo mv "$tmp_file" "$target_file"

    log_info "docker 正在重启..."
    sudo systemctl restart docker 2>/dev/null || sudo service docker restart 2>/dev/null

    # log_info "当前 docker daemon 配置内容如下:"
    # if command -v jq >/dev/null 2>&1 && sudo jq '.' "$target_file" 2>/dev/null; then
    #     log_debug "docker daemon 配置文件内容已成功格式化显示"
    #     # jq 格式化成功
    #     :
    # else
    #     # 回退到直接显示
    #     log_warn "无法使用 jq 格式化显示 docker daemon 配置文件内容，直接输出原始内容"
    #     sudo cat "$target_file"
    # fi

    log_info "如果您需要修改配置, 请编辑 $target_file 文件并重启 docker 服务"
}
