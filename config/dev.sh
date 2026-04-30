#!/bin/bash
# FilePath    : blog-tool/config/dev.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 开发配置文件, 仅用于开发环境.

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# git 仓库地址前缀
GIT_PREFIX_LOCAL="" # 内网 Git 地址, 通过 check_dev_var 交互式加载
GIT_PREFIX_GITEE="git@gitee.com"
GIT_PREFIX_GITHUB="git@github.com"

# git 用户
GIT_USER="jiaopengzi"

# git
GIT_LOCAL="$GIT_PREFIX_LOCAL:$GIT_USER"
GIT_GITEE="$GIT_PREFIX_GITEE:$GIT_USER"
GIT_GITHUB="$GIT_PREFIX_GITHUB:$GIT_USER"

# 产物上传api前缀
GIT_API_PREFIX_GITHUB="https://api.github.com"
GIT_API_PREFIX_GITEE="https://gitee.com/api/v5"

# 私有仓库配置主要用于开发阶段
REGISTRY_REMOTE_SERVER="" # 远端服务器地址
REGISTRY_USER_NAME=""     # docker registry 用户名
REGISTRY_PASSWORD=""      # 私有仓库密码

# 腾讯云公共仓库配置, 推送时需要凭据, 拉取时无需登录; 地址默认值由 config/internal.sh 提供
REGISTRY_USER_NAME_TENCENT="${REGISTRY_USER_NAME_TENCENT:-}" # 腾讯 docker registry 用户名
REGISTRY_PASSWORD_TENCENT="${REGISTRY_PASSWORD_TENCENT:-}"   # 腾讯 docker registry 密码

# 密码和 token 变量
DOCKER_HUB_REMOTE_SERVER="docker.io"                 # 远端服务器地址
DOCKER_HUB_TOKEN="${DOCKER_HUB_TOKEN:-}"             # docker hub token
GITHUB_TOKEN="${GITHUB_TOKEN:-}"                     # github token
GITEE_TOKEN="${GITEE_TOKEN:-}"                       # gitee token
COSIGN_PRIVATE_KEY="${COSIGN_PRIVATE_KEY:-}"         # Cosign 私钥文件绝对路径
COSIGN_PRIVATE_KEY_PWD="${COSIGN_PRIVATE_KEY_PWD:-}" # Cosign 私钥密码
COSIGN_PASSWORD="${COSIGN_PASSWORD:-}"               # Cosign 标准密码环境变量

# docker 镜像版本
IMG_VERSION_ALPINE="latest"
IMG_VERSION_GOLANG="1.26.2-alpine"
IMG_VERSION_NODE="24.15.0"
IMG_VERSION_NGINX="1.30.0-alpine"
IMG_VERSION_REGISTRY="3"
IMG_VERSION_HTTPD="2"

HOST_NAME=""    # 默认主机名, 通过 check_dev_var 交互式加载
SSH_PORT=""     # 默认 SSH 端口, 通过 check_dev_var 交互式加载
GATEWAY_IPV4="" # 默认网关, 通过 check_dev_var 交互式加载

# # 系统版本 (默认值, 会被 system/detect.sh 的 init_system_detection 覆盖)
# OLD_SYS_VERSION="bookworm" # Debian 12
# NEW_SYS_VERSION="trixie"   # Debian 13
# NEW_SYS_VERSION_NUM="13"   # Debian 数字版本
