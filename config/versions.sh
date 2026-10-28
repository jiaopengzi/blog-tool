#!/bin/bash
# FilePath    : blog-tool/config/versions.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Description : 依赖版本唯一维护入口, 保留现有版本及浮动更新策略.

# shellcheck disable=SC2034

IMG_VERSION_PGSQL="18.6"
IMG_VERSION_PGSQL_MAJOR="${IMG_VERSION_PGSQL%%.*}"
IMG_VERSION_REDIS="8.6.8"
# 数据库与搜索组件. ES, IK 和 Kibana 必须使用相同版本, 升级前先确认 IK 已发布.
# IK 发布地址: https://release.infinilabs.com/analysis-ik/stable
IMG_VERSION_ES="9.5.5"
IMG_VERSION_KIBANA="$IMG_VERSION_ES"

# 开发与运行时镜像. 版本与镜像变体分开维护.
IMG_VERSION_ALPINE="latest"
DEP_VERSION_GOLANG="1.27.3"
IMG_VERSION_GOLANG="${DEP_VERSION_GOLANG}-alpine"
IMG_VERSION_NODE="24.22.1"
DEP_VERSION_NGINX="1.31.8"
IMG_VERSION_NGINX="${DEP_VERSION_NGINX}-alpine"
IMG_VERSION_REGISTRY="3"
IMG_VERSION_HTTPD="2"

# single 基础系统与软件源约束.
IMG_VERSION_UBUNTU="24.04"
# noble 是 Ubuntu 24.04 的固定发行代号, 24.04.x 更新无需修改, 更换 Ubuntu 发行版时需同步调整.
SINGLE_UBUNTU_CODENAME="noble"
# 1 是 nginx 官方 apt 包的打包修订号, 并非永久固定; 常规升级通常不变, 若官方调整修订号需核验.
# noble 部分跟随 Ubuntu 发行代号, 此后缀不是 nginx 应用版本.
SINGLE_NGINX_PACKAGE_SUFFIX="1~${SINGLE_UBUNTU_CODENAME}"

# 下载工具保留原策略: Cosign 动态查询 latest.
COSIGN_RELEASE_CHANNEL="latest"