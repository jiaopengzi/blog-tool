#!/bin/bash
# FilePath    : blog-tool/utils/check.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 运行脚本前的检查

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# 设置环境变量
export LC_ALL=C.UTF-8

# 设置主机名称
check_is_root() {
    log_debug "run check_is_root"

    # 检查是否是 root 权限运行
    if [ $UID -ne 0 ]; then
        log_error "请使用 root 或者 sudo 运行此脚本."
        exit 1
    fi
}

# 设置主机名称
check_character() {
    log_debug "run check_is_character"

    # 计算测试字符串中的中文字符和英文字符数量
    read -r chn_chars eng_chars <<<"$(count_chars "测试Test中文字符English123456")"

    # 正确的结果是 中文字符数 6, 英文字符数 17
    if [[ $chn_chars -ne 6 || $eng_chars -ne 17 ]]; then
        log_warn "当前环境下字符计算异常, 请设置系统语言为 UTF-8 编码格式."
    fi
}

# 检查 /urs/bin 和 /bin 和 /usr/sbin 和 /sbin 是否在环境变量 PATH 中
check_env_path() {
    log_debug "run check_env_path"

    local paths_to_check=("/usr/bin" "/bin" "/usr/sbin" "/sbin")
    local missing_paths=()
    for path in "${paths_to_check[@]}"; do
        if ! echo "$PATH" | grep -qE "(^|:)$path(:|$)"; then
            missing_paths+=("$path")
        fi
    done

    if [ ${#missing_paths[@]} -ne 0 ]; then
        # 提示用户是否添加缺少的路径到环境变量 PATH 中
        printf '\n环境变量 PATH 中缺少以下路径: %s\n\n' "${missing_paths[*]}"
        is_add=$(read_user_input "是否将它们添加到 PATH 中以确保脚本正常运行.(默认n) [y|n]? " "n")
        if [ "$is_add" == "y" ]; then
            # 拿到合并和的字符串 echo >> 添加到 当前用户的 ~/.bashrc 文件中 和 root 用户的 ~/.bashrc 文件中
            # 合并路径为一个 export 语句, 一次性追加到文件
            export_cmd="export PATH=\$PATH$(printf ':%s' "${missing_paths[@]}")"
            printf '%s\n' "$export_cmd" >>"$HOME/.bashrc"
            printf '%s\n' "$export_cmd" >>"/root/.bashrc"

            # 提示用户哪些路径,路劲使用分号分隔
            log_info "已将以下路径添加到环境变量 PATH 中: ${missing_paths[*]}"
            log_warn "请重新登录终端或运行 'source ~/.bashrc' 以使更改生效."
            exit 0
        else
            log_warn "未将缺少的路径: ${missing_paths[*]} 添加到环境变量 PATH 中, 脚本无法正常运行."
        fi
    fi
}

# 检查 域名和公网IP地址变量
check_install_base() {
    log_debug "run check_install_base"
    local which_software_list=(
        sudo
        curl
        git
        wget
        unzip
        zip
        tar
        gzip
        bc
        jq
        python3
    )
    # 使用 command -v 检查 $which_software_list 命令是否存在
    local missing_commands=()
    for cmd in "${which_software_list[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    # 如果有缺少的命令则安装基础软件
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_warn "检测到未安装基础软件"
        is_install=$(read_user_input "是否开始安装基础依赖软件(默认n) [y|n]? " "n")
        if [ "$is_install" == "y" ]; then
            log_info "开始安装基础软件..."
            install_common_software
            log_info "基础软件安装完成, 请重新运行脚本."
            exit 0
        else
            log_error "未安装基础软件: ${missing_commands[*]}, 脚本无法正常运行."
            exit 0
        fi
    fi
}

# 交互式获取或加载配置, 支持默认值, 并写入配置文件
# 参数：
#   $1 - 变量名(如 DOMAIN_NAME)
#   $2 - 配置文件路径(如 "$BLOG_TOOL_ENV/domain_name")
#   $3 - 提示前缀信息(如 "请输入您的域名如：example.com")
#   $4 - 默认值(如 "$HOST_INTRANET_IP")
load_interactive_config() {
    local var_name=$1
    local config_file=$2
    local prompt_msg=$3
    local default_value=$4

    # 如果变量未设置
    if [ -z "${!var_name}" ]; then
        if [ -f "$config_file" ]; then
            local file_value
            file_value=$(cat "$config_file")
            if [ -z "$file_value" ]; then
                log_error "$config_file 文件为空, 请写入有效值"
            else
                printf -v "$var_name" '%s' "$file_value"
            fi
        else
            # 提示用户输入
            printf "\n%s (默认: %s), 回车使用默认值: " "$prompt_msg" "$default_value"
            read -r user_input
            if [ -z "$user_input" ]; then
                printf -v "$var_name" '%s' "$default_value"
            else
                printf -v "$var_name" '%s' "$user_input"
            fi
        fi
    fi

    # 最终将变量的值写入配置文件
    echo "${!var_name}" | sudo tee "$config_file" >/dev/null
}

# 加载必须的配置项, 文件必须存在且内容非空, 否则报错
# 参数：
#   $1 - 变量名(如 REGISTRY_REMOTE_SERVER)
#   $2 - 配置文件路径(如 "$BLOG_TOOL_ENV/private_registry_remote_server")
#   $3 - 错误提示信息前缀(可选, 用于定制 log_error)
#   $4 - 是否必须存在标志(可选, 默认必须存在)
load_config_from_file_and_validate() {
    local var_name=$1
    local config_file=$2
    local error_prefix=${3:-""}
    local must_exist=${4:-"true"}

    # 1) 如果文件存在 -> 检查可读性 -> 读取(只取首行)并去除首尾空白 -> 校验非空 -> 赋值并返回
    # 2) 如果文件不存在且 must_exist 为 true -> 报错
    # 3) 否则静默返回(允许不存在)
    if [ -e "$config_file" ]; then
        # 文件存在, 先检查是否可读
        if [ ! -r "$config_file" ]; then
            log_error "${error_prefix}${config_file} 存在但不可读, 请检查权限"
        fi

        # 只读取文件第一行, 避免读取大文件并去除首尾空白
        local file_value
        IFS= read -r file_value <"$config_file"
        # 去除首尾空白字符
        file_value="${file_value#"${file_value%%[![:space:]]*}"}"
        file_value="${file_value%"${file_value##*[![:space:]]}"}"

        # 文件为空时报错
        if [ -z "$file_value" ]; then
            log_error "${error_prefix}${config_file} 文件为空, 请写入有效值"
        fi

        # 将值导出到指定变量并返回
        printf -v "$var_name" '%s' "$file_value"
        return
    fi

    # 文件不存在：如果必须存在则报错, 否则允许继续(不设置变量)
    if [ "$must_exist" = true ]; then
        log_error "${error_prefix}${config_file} 文件不存在, 请创建并写入有效值"
    fi
}

# 函数：优先使用环境变量, 其次尝试从文件加载配置, 否则报错
# 参数：
#   $1 - 环境变量名(如 DOCKER_HUB_TOKEN)
#   $2 - 变量名(如 DOCKER_HUB_TOKEN, 通常同名)
#   $3 - 配置文件路径(如 "$BLOG_TOOL_ENV/docker_hub_token")
#   $4 - 错误提示前缀
load_env_or_file_config() {
    local env_var_name=$1
    local var_name=$2
    local config_file=$3
    local error_prefix=${4:-""}

    if [ -n "${!env_var_name:-}" ]; then
        # 优先判断环境变量是否有值, 直接使用
        printf -v "$var_name" '%s' "${!env_var_name}"
    else
        # 环境变量未设置, 尝试从文件加载
        load_config_from_file_and_validate "$var_name" "$config_file" "$error_prefix"
    fi
}

# 检查 域名和公网IP地址变量
check_domain_ip() {
    log_debug "run check_domain_ip"

    if [ ! -d "$BLOG_TOOL_ENV" ]; then
        mkdir -p "$BLOG_TOOL_ENV"
    fi

    # 域名配置
    load_interactive_config \
        DOMAIN_NAME \
        "$BLOG_TOOL_ENV/domain_name" \
        "请输入您的域名如：example.com" \
        "$HOST_INTRANET_IP"

    # 公网IP地址配置
    load_interactive_config \
        PUBLIC_IP_ADDRESS \
        "$BLOG_TOOL_ENV/public_ip_address" \
        "请输入您的公网ip如：1.2.3.4" \
        "$HOST_INTRANET_IP"
}

check_dev_var() {
    log_debug "run check_dev_var"

    # 运行模式配置, "$BLOG_TOOL_ENV/run_mode" 文件非必须存在
    load_config_from_file_and_validate \
        RUN_MODE \
        "$BLOG_TOOL_ENV/run_mode" \
        "运行模式" \
        "false"

    if run_mode_is_pro; then
        return 0
    fi

    if [ ! -d "$BLOG_TOOL_ENV" ]; then
        mkdir -p "$BLOG_TOOL_ENV"
    fi

    # 必须存在的配置项(无交互, 报错如果缺失或为空)
    load_config_from_file_and_validate \
        REGISTRY_REMOTE_SERVER \
        "$BLOG_TOOL_ENV/private_registry_remote_server" \
        "私有仓库地址"

    load_config_from_file_and_validate \
        REGISTRY_USER_NAME \
        "$BLOG_TOOL_ENV/private_user" \
        "私有仓库用户名"

    load_config_from_file_and_validate \
        REGISTRY_PASSWORD \
        "$BLOG_TOOL_ENV/private_password" \
        "私有仓库密码"

    # 开发环境基础配置(交互式加载, 首次运行时输入, 之后从文件读取)
    load_interactive_config \
        GIT_PREFIX_LOCAL \
        "$BLOG_TOOL_ENV/git_prefix_local" \
        "请输入内网 Git 地址前缀如：git@10.0.0.100" \
        "git@127.0.0.1"

    # 更新依赖 GIT_PREFIX_LOCAL 的变量
    GIT_LOCAL="$GIT_PREFIX_LOCAL:$GIT_USER"

    load_interactive_config \
        HOST_NAME \
        "$BLOG_TOOL_ENV/host_name" \
        "请输入主机名如：my-host" \
        "$(hostname)"

    load_interactive_config \
        SSH_PORT \
        "$BLOG_TOOL_ENV/ssh_port" \
        "请输入 SSH 端口" \
        "22"

    load_interactive_config \
        GATEWAY_IPV4 \
        "$BLOG_TOOL_ENV/gateway_ipv4" \
        "请输入默认网关如：10.0.0.1" \
        "$(ip route | awk '/default/ {print $3; exit}')"

    # 优先使用环境变量, 其次尝试从文件加载(token类)
    load_env_or_file_config \
        DOCKER_HUB_TOKEN \
        DOCKER_HUB_TOKEN \
        "$BLOG_TOOL_ENV/docker_hub_token" \
        "docker hub token"

    load_env_or_file_config \
        GITHUB_TOKEN \
        GITHUB_TOKEN \
        "$BLOG_TOOL_ENV/github_token" \
        "github token"

    load_env_or_file_config \
        GITEE_TOKEN \
        GITEE_TOKEN \
        "$BLOG_TOOL_ENV/gitee_token" \
        "gitee token"
}

# 更新运行模式
update_run_mode() {
    if [ ! -d "$BLOG_TOOL_ENV" ]; then
        mkdir -p "$BLOG_TOOL_ENV"
    fi

    # 判断 "$BLOG_TOOL_ENV/run_mode" 文件是否存在
    if [ -f "$BLOG_TOOL_ENV/run_mode" ]; then
        RUN_MODE=$(sudo cat "$BLOG_TOOL_ENV/run_mode")
    else
        echo "$RUN_MODE" | tee "$BLOG_TOOL_ENV/run_mode" >/dev/null
    fi

    # 根据运行模式调整 RUN_MODE 为 pro 时 且 使用函数 is_mem_greater_than 判断是否大于 4G
    # 设置为注释状态
    if [[ "$RUN_MODE" == "pro" ]] && is_mem_greater_than 4; then
        ES_JAVA_OPTS_ENV="# $ES_JAVA_OPTS_ENV"
        MEM_LIMIT_ES="# $MEM_LIMIT_ES"
        MEM_LIMIT_KIBANA="# $MEM_LIMIT_KIBANA"
    fi
}

# 检查开发环境变量
check_dir() {
    log_debug "run check_dir"

    # 数据根目录
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    # blog-tool 环境目录
    if [ ! -d "$BLOG_TOOL_ENV" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$BLOG_TOOL_ENV"
    fi

    # docker-compose 目录
    if [ ! -d "$DOCKER_COMPOS_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DOCKER_COMPOS_DIR"
    fi

    # CA 证书目录
    if [ ! -d "$CA_CERT_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CA_CERT_DIR"
    fi

    # Nginx 证书目录
    if [ ! -d "$CERTS_NGINX" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CERTS_NGINX"
    fi
}

# 设置主机名称
check() {
    log_debug "run check"

    check_is_root
    check_character
    check_env_path
    check_install_base
    check_domain_ip
    check_dev_var
    check_dir
    update_run_mode

    # 解码 python 脚本内容到临时文件
    decode_py_base64_main
}
