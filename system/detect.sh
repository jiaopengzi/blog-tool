#!/bin/bash
# FilePath    : blog-tool/system/detect.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 系统检测模块, 统一处理 Debian/Ubuntu 系统检测

# =============================================================================
# 系统检测函数
# =============================================================================

##
# 函数: detect_system
# 说明: 检测当前操作系统是否为 Debian/Ubuntu 系列。
#      读取 /etc/os-release 或 /etc/debian_version 并设置以下导出变量：
#        - SYSTEM_FAMILY: debian 或 ubuntu
#        - SYSTEM_CODENAME: 发行代号(如 bookworm、jammy 等), 若未知则为 "unknown"
#        - SYSTEM_VERSION_NUM: 简化的主版本号(如 12、22 等), 找不到则为空字符串
#      返回值：0 表示检测成功并设置了相关变量; 1 表示无法识别系统。
detect_system() {
	if [ -f /etc/os-release ]; then
		local id=""
		id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')

		local version_codename=""
		version_codename=$(grep "^VERSION_CODENAME=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')

		case "$id" in
		debian)
			SYSTEM_FAMILY="debian"
			SYSTEM_CODENAME="$version_codename"
			case "$version_codename" in
			trixie) SYSTEM_VERSION_NUM="13" ;;
			bookworm) SYSTEM_VERSION_NUM="12" ;;
			bullseye) SYSTEM_VERSION_NUM="11" ;;
			*) SYSTEM_VERSION_NUM="" ;;
			esac
			return 0
			;;
		ubuntu)
			SYSTEM_FAMILY="ubuntu"
			SYSTEM_CODENAME="$version_codename"
			case "$version_codename" in
			noble) SYSTEM_VERSION_NUM="24" ;;
			jammy) SYSTEM_VERSION_NUM="22" ;;
			focal) SYSTEM_VERSION_NUM="20" ;;
			bionic) SYSTEM_VERSION_NUM="18" ;;
			*) SYSTEM_VERSION_NUM="" ;;
			esac
			return 0
			;;
		*)
			return 1
			;;
		esac
	fi

	if [ -f /etc/debian_version ]; then
		SYSTEM_FAMILY="debian"
		SYSTEM_CODENAME="unknown"
		SYSTEM_VERSION_NUM=""
		return 0
	fi

	return 1
}

##
# 函数: get_system_family
# 说明: 调用 detect_system 并输出 `SYSTEM_FAMILY` 值(debian/ubuntu 等)。
# 返回: 将 `SYSTEM_FAMILY` 打印到 stdout。
get_system_family() {
	detect_system
	echo "$SYSTEM_FAMILY"
}

##
# 函数: get_system_codename
# 说明: 调用 detect_system 并输出 `SYSTEM_CODENAME`(发行代号)。
# 返回: 将 `SYSTEM_CODENAME` 打印到 stdout。
get_system_codename() {
	detect_system
	echo "$SYSTEM_CODENAME"
}

##
# 函数: get_system_version_num
# 说明: 调用 detect_system 并输出 `SYSTEM_VERSION_NUM`(简化的主要版本号)。
# 返回: 将 `SYSTEM_VERSION_NUM` 打印到 stdout。
get_system_version_num() {
	detect_system
	echo "$SYSTEM_VERSION_NUM"
}

##
# 函数: get_apt_source_base
# 说明: 根据检测到的系统家族返回默认的 APT 源基础 URL。
# 返回: 打印 APT 源基础 URL(例如 http://deb.debian.org/debian 或 http://archive.ubuntu.com/ubuntu)。
get_apt_source_base() {
	detect_system
	case "$SYSTEM_FAMILY" in
	debian) echo "http://deb.debian.org/debian" ;;
	ubuntu) echo "http://archive.ubuntu.com/ubuntu" ;;
	*) echo "http://deb.debian.org/debian" ;;
	esac
}

##
# 函数: get_docker_repo_path
# 说明: 根据系统家族返回 Docker 仓库路径片段(用于构建或拉取镜像时的路径选择)。
# 返回: 打印仓库路径片段("debian" 或 "ubuntu")。
get_docker_repo_path() {
	detect_system
	case "$SYSTEM_FAMILY" in
	debian) echo "debian" ;;
	ubuntu) echo "ubuntu" ;;
	*) echo "debian" ;;
	esac
}

##
# 函数: get_backports_source
# 说明: 生成并输出适用于当前系统的 backports APT 源行。
# 返回: 打印完整的 deb 源行, 或在未知系统时输出空字符串。
get_backports_source() {
	detect_system
	local base_url
	base_url=$(get_apt_source_base)
	case "$SYSTEM_FAMILY" in
	debian)
		echo "deb $base_url $SYSTEM_CODENAME-backports main contrib non-free-firmware"
		;;
	ubuntu)
		echo "deb $base_url $SYSTEM_CODENAME-backports main restricted universe multiverse"
		;;
	*)
		echo ""
		;;
	esac
}

##
# 函数: check_min_version
# 参数: $1 - 要比较的最小版本号(整数, 例如 12 或 22)
# 说明: 检查当前系统的 `SYSTEM_VERSION_NUM` 是否存在且不小于给定的最小版本号。
# 返回: 0 如果满足最小版本要求; 非 0 表示不满足或无法判断。
check_min_version() {
	local min_version="$1"
	detect_system
	[ -z "$SYSTEM_VERSION_NUM" ] && return 1
	[ "$SYSTEM_VERSION_NUM" -ge "$min_version" ] 2>/dev/null
	return $?
}

##
# 函数: print_system_info
# 说明: 调用 detect_system 并将当前检测到的系统信息以可读格式打印出来, 便于调试和日志记录。
print_system_info() {
	detect_system
	echo "SYSTEM_FAMILY: $SYSTEM_FAMILY"
	echo "SYSTEM_CODENAME: $SYSTEM_CODENAME"
	echo "SYSTEM_VERSION_NUM: $SYSTEM_VERSION_NUM"
	echo "APT_SOURCE_BASE: $(get_apt_source_base)"
	echo "DOCKER_REPO_PATH: $(get_docker_repo_path)"
	echo "BACKPORTS_SOURCE: $(get_backports_source)"
}

##
# 函数: init_system_detection
# 说明: 初始化并导出与系统检测相关的环境变量, 便于脚本后续使用这些全局变量。
#      当检测到为 debian/ubuntu 时, 还会设置并导出 `OLD_SYS_VERSION`、`NEW_SYS_VERSION`、`NEW_SYS_VERSION_NUM`。
init_system_detection() {
	detect_system
	export SYSTEM_FAMILY
	export SYSTEM_CODENAME
	export SYSTEM_VERSION_NUM

	if [ "$SYSTEM_FAMILY" = "debian" ] || [ "$SYSTEM_FAMILY" = "ubuntu" ]; then
		OLD_SYS_VERSION="$SYSTEM_CODENAME"
		NEW_SYS_VERSION="$SYSTEM_CODENAME"
		NEW_SYS_VERSION_NUM="$SYSTEM_VERSION_NUM"
		export OLD_SYS_VERSION NEW_SYS_VERSION NEW_SYS_VERSION_NUM
	fi
}
