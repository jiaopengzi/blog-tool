#!/bin/bash
# FilePath    : blog-tool/utils/password.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 密码安全工具, 生产环境密码生成与强度检查

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# 生成强密码
# 使用 openssl rand -hex 32 生成 64 字符十六进制字符串
# 返回: 通过 stdout 输出生成的密码字符串
generate_strong_password() {
	log_debug "run generate_strong_password"

	openssl rand -hex 32
}

# 判断密码是否为弱密码
# 参数: $1: password - 待检查的密码字符串
# 返回: 0 表示是弱密码, 1 表示不是弱密码
is_weak_password() {
	log_debug "run is_weak_password"

	local password="$1"
	local password_length=${#password}

	# 空密码视为弱密码
	if [[ -z "$password" ]]; then
		return 0
	fi

	# 长度小于 16 字符视为弱密码
	if ((password_length < 16)); then
		return 0
	fi

	# 常见弱密码列表
	local -a weak_list=(
		"123456"
		"12345678"
		"1234567890"
		"0123456789"
		"password"
		"qwerty"
		"abc123"
		"admin123"
		"root123"
		"123456789"
		"1234567890123456"
	)

	local weak
	for weak in "${weak_list[@]}"; do
		if [[ "$password" == "$weak" ]]; then
			return 0
		fi
	done

	# 检查是否全部为相同字符, 如 "aaaaaaaaaaaaaaaa"
	local first_char="${password:0:1}"
	local same_char_pattern
	same_char_pattern=$(printf '%*s' "$password_length" '' | tr ' ' "$first_char")
	if [[ "$password" == "$same_char_pattern" ]]; then
		return 0
	fi

	# 不是弱密码
	return 1
}

# 处理已存在的密码文件: 读取密码, 检查强度, 弱密码提示替换
# 参数: $1: var_name - Shell 变量名
#       $2: config_file - 密码文件路径
#       $3: description - 中文描述
_handle_existing_password() {
	local var_name="$1"
	local config_file="$2"
	local description="$3"
	local password user_choice

	# 读取密码文件内容
	IFS= read -r password <"$config_file"

	if is_weak_password "$password"; then
		# 弱密码: 提示用户确认是否替换
		log_warn "$description 强度不足, 建议替换为强密码"
		user_choice=$(read_user_input "⚠️  $description 当前为弱密码, 是否自动生成强密码替换? (y/n, 默认: y): " "y")

		if [[ "$user_choice" == "y" ]]; then
			password=$(generate_strong_password)
			over_write_set_owner "$JPZ_UID" "$JPZ_GID" 600 "$password" "$config_file"
			log_debug "✅ 已自动生成强密码并写入 $config_file"
		else
			log_warn "⚠️  用户选择保留弱密码: $description"
		fi
	else
		log_debug "$description 密码强度检查通过"
	fi

	# 将文件中的密码值赋给对应的 Shell 变量
	printf -v "$var_name" '%s' "$password"
}

# 处理不存在的密码文件: 生成强密码并写入
# 参数: $1: var_name - Shell 变量名
#       $2: config_file - 密码文件路径
#       $3: description - 中文描述
_generate_new_password() {
	local var_name="$1"
	local config_file="$2"
	local description="$3"
	local password

	password=$(generate_strong_password)
	over_write_set_owner "$JPZ_UID" "$JPZ_GID" 600 "$password" "$config_file"
	log_info "✅ 已自动生成 $description 并写入 $config_file"

	# 将生成的密码赋给对应的 Shell 变量
	printf -v "$var_name" '%s' "$password"
}

# 检查密码安全性(主入口函数)
# 仅在 pro 模式下执行; 对每个密码变量:
#   - 文件不存在: 自动生成强密码并写入 $BLOG_TOOL_ENV
#   - 文件存在且为弱密码: 提示用户确认是否替换
#   - 文件存在且为强密码: 直接使用
check_password_security() {
	log_debug "run check_password_security"

	# # 仅在 pro 模式下执行密码检查, dev 模式跳过
	# if run_mode_is_dev; then
	# 	log_debug "非 pro 模式, 跳过密码安全检查"
	# 	return 0
	# fi

	# 确保 $BLOG_TOOL_ENV 目录存在
	if [[ ! -d "$BLOG_TOOL_ENV" ]]; then
		mkdir -p "$BLOG_TOOL_ENV"
	fi

	# 密码变量与 $BLOG_TOOL_ENV 文件名的映射
	# 格式: "Shell 变量名:文件名:中文描述"
	local -a password_map=(
		"POSTGRES_PASSWORD:postgres_password:PostgreSQL 数据库密码"
		"REDIS_PASSWORD:redis_password:Redis 密码"
		"ELASTIC_PASSWORD:elastic_password:Elasticsearch 密码"
		"KIBANA_PASSWORD:kibana_password:Kibana 密码"
		"POSTGRES_PASSWORD_BILLING_CENTER:postgres_password_billing_center:计费中心 PostgreSQL 数据库密码"
		"REDIS_PASSWORD_BILLING_CENTER:redis_password_billing_center:计费中心 Redis 密码"
	)

	local entry var_name file_name description
	local config_file

	for entry in "${password_map[@]}"; do
		# 解析映射条目
		IFS=':' read -r var_name file_name description <<<"$entry"

		# 使用 declare -p 检查变量是否存在, 处理不同构建版本中密码变量数量不同的情况
		if ! declare -p "$var_name" &>/dev/null; then
			log_debug "$var_name 变量不存在, 跳过(可能不在当前构建版本中)"
			continue
		fi

		config_file="$BLOG_TOOL_ENV/$file_name"

		if [[ -f "$config_file" ]]; then
			_handle_existing_password "$var_name" "$config_file" "$description"
		else
			_generate_new_password "$var_name" "$config_file" "$description"
		fi
	done
}
