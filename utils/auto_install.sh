#!/bin/bash
# FilePath    : blog-tool/utils/auto_install.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 一键安装零交互模式

# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

AUTO_MODE="false"
AUTO_CERT=""
AUTO_CERT_KEY=""
AUTO_ADMIN_USERNAME=""
AUTO_ADMIN_EMAIL=""
AUTO_ADMIN_PASSWORD=""

# 打印零交互安装用法.
# 返回: 直接输出用法说明到 stderr.
print_auto_usage() {
    printf '%s\n' \
    "用法:" \
    "  sudo bash blog-tool.sh --auto --domain=example.com --project_name=blog-server --public_ip=1.2.3.4" \
    "" \
    "参数:" \
    "  --auto                  启用零交互一键安装模式" \
    "  --domain                访问域名, 不要带 http:// 或 https://" \
    "  --project_name          项目名称, 仅允许字母, 数字, 下划线和短横线" \
    "  --public_ip             当前服务器公网 IPv4 地址" \
    "  --cert                  nginx HTTPS 证书文件路径, 可选, 将复制为 cert.pem" \
    "  --cert_key              nginx HTTPS 私钥文件路径, 可选, 将复制为 cert.key" \
    "  --admin_username        管理员用户名, 可选" \
    "  --admin_email           管理员邮箱, 可选, 用于安装完成后自动注册管理员" \
    "  --admin_password        管理员密码, 可选, 用于安装完成后自动注册管理员" >&2
}

# 判断值是否为合法 IPv4 地址.
# 参数: $1: IPv4 地址.
# 返回: 0 表示合法, 1 表示非法.
auto_is_valid_ipv4() {
    local ip="$1"
    local octet
    local -a octets

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<<"$ip"
    for octet in "${octets[@]}"; do
        if ((octet < 0 || octet > 255)); then
            return 1
        fi
    done
}

# 解析 --auto 命令行参数并写入全局变量.
# 参数: $@: 命令行参数列表.
# 返回: 参数合法时返回 0, 否则输出错误并退出.
parse_auto_args() {
    AUTO_MODE="true"

    local arg part
    local -a arg_parts
    for arg in "$@"; do
        IFS=',' read -r -a arg_parts <<<"$arg"
        for part in "${arg_parts[@]}"; do
            case "$part" in
        --auto)
            ;;
        --domain=*)
            DOMAIN_NAME="${part#*=}"
            ;;
        --project_name=* | --project-name=*)
            PROJECT_NAME="${part#*=}"
            ;;
        --public_ip=* | --public-ip=*)
            PUBLIC_IP_ADDRESS="${part#*=}"
            ;;
        --cert=*)
            AUTO_CERT="${part#*=}"
            ;;
        --cert_key=* | --cert-key=*)
            AUTO_CERT_KEY="${part#*=}"
            ;;
        --admin_username=*)
            AUTO_ADMIN_USERNAME="${part#*=}"
            ;;
        --admin_email=*)
            AUTO_ADMIN_EMAIL="${part#*=}"
            ;;
        --admin_password=*)
            AUTO_ADMIN_PASSWORD="${part#*=}"
            ;;
        --help | -h)
            print_auto_usage
            exit 0
            ;;
        *)
            echo "未知参数: $part" >&2
            print_auto_usage
            exit 1
            ;;
        esac
        done
    done
}

# 校验零交互安装参数.
# 返回: 参数合法时返回 0, 否则输出错误并退出.
validate_auto_args() {
    if [ -n "$DOMAIN_NAME" ] && [[ "$DOMAIN_NAME" == http://* || "$DOMAIN_NAME" == https://* ]]; then
        echo "--domain 不要包含 http:// 或 https://: $DOMAIN_NAME" >&2
        exit 1
    fi
    if [ -n "$DOMAIN_NAME" ] && ! [[ "$DOMAIN_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]]; then
        echo "--domain 格式不合法: $DOMAIN_NAME" >&2
        exit 1
    fi
    if [ -n "$PROJECT_NAME" ] && ! [[ "$PROJECT_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "--project_name 仅允许字母, 数字, 下划线和短横线: $PROJECT_NAME" >&2
        exit 1
    fi
    if [ -n "$PUBLIC_IP_ADDRESS" ] && ! auto_is_valid_ipv4 "$PUBLIC_IP_ADDRESS"; then
        echo "--public_ip 不是合法 IPv4 地址: $PUBLIC_IP_ADDRESS" >&2
        exit 1
    fi
    validate_auto_cert_args
    validate_auto_admin_args
    if command -v docker >/dev/null 2>&1; then
        echo "检测到当前机器已安装 Docker, 为避免覆盖已有 Docker 环境, 不能使用 --auto 模式." >&2
        exit 1
    fi
}

# 校验零交互安装的可选 nginx 证书参数.
# 返回: 未传证书或证书参数成对合法时返回 0, 否则输出错误并退出.
validate_auto_cert_args() {
    if [ -z "$AUTO_CERT" ] && [ -z "$AUTO_CERT_KEY" ]; then
        return 0
    fi
    if [ -z "$AUTO_CERT" ] || [ -z "$AUTO_CERT_KEY" ]; then
        echo "--cert 和 --cert_key 需要同时提供" >&2
        exit 1
    fi
    if [ ! -f "$AUTO_CERT" ] || [ ! -r "$AUTO_CERT" ]; then
        echo "--cert 文件不存在或不可读: $AUTO_CERT" >&2
        exit 1
    fi
    if [ ! -f "$AUTO_CERT_KEY" ] || [ ! -r "$AUTO_CERT_KEY" ]; then
        echo "--cert_key 文件不存在或不可读: $AUTO_CERT_KEY" >&2
        exit 1
    fi
}

# 校验零交互安装的可选管理员注册参数.
# 返回: 未传管理员参数或三项参数全部合法时返回 0, 否则输出错误并退出.
validate_auto_admin_args() {
    if [ -z "$AUTO_ADMIN_USERNAME" ] && [ -z "$AUTO_ADMIN_EMAIL" ] && [ -z "$AUTO_ADMIN_PASSWORD" ]; then
        return 0
    fi
    if [ -z "$AUTO_ADMIN_USERNAME" ] || [ -z "$AUTO_ADMIN_EMAIL" ] || [ -z "$AUTO_ADMIN_PASSWORD" ]; then
        echo "--admin_username, --admin_email 和 --admin_password 需要同时提供" >&2
        exit 1
    fi
    if ! [[ "$AUTO_ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
        echo "--admin_email 格式不合法: $AUTO_ADMIN_EMAIL" >&2
        exit 1
    fi
    AUTO_ADMIN_USERNAME=$(printf '%s' "$AUTO_ADMIN_USERNAME" | tr '[:upper:]' '[:lower:]')
    if ! [[ "$AUTO_ADMIN_USERNAME" =~ ^[a-z0-9]{6,20}$ ]]; then
        echo "--admin_username 必须是 6-20 位小写字母或数字: $AUTO_ADMIN_USERNAME" >&2
        exit 1
    fi
    if [ ${#AUTO_ADMIN_PASSWORD} -lt 6 ] || [ ${#AUTO_ADMIN_PASSWORD} -gt 64 ]; then
        echo "--admin_password 长度必须为 6-64 位" >&2
        exit 1
    fi
    if ! [[ "$AUTO_ADMIN_PASSWORD" =~ [0-9] ]] || ! [[ "$AUTO_ADMIN_PASSWORD" =~ [a-z] ]] || ! [[ "$AUTO_ADMIN_PASSWORD" =~ [A-Z] ]]; then
        echo "--admin_password 必须包含大写字母, 小写字母和数字" >&2
        exit 1
    fi
}

# 在零交互模式下自动接受免责声明.
# 返回: 写入免责声明接受标记.
auto_accept_disclaimer() {
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$BLOG_TOOL_ENV"
    echo "用户接受时间: $(date +"%Y-%m-%d %H:%M:%S")" >"$BLOG_TOOL_ENV/disclaimer_accepted"
    log_info "--auto 模式已默认接受免责声明"
}

# 复制用户传入的 nginx 证书到工具证书目录.
# 返回: 成功复制 cert.pem 和 cert.key.
auto_prepare_nginx_cert() {
    [ "$AUTO_MODE" = "true" ] || return 0

    if [ -z "$AUTO_CERT" ] && [ -z "$AUTO_CERT_KEY" ]; then
        gen_client_nginx_cert
        return 0
    fi

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CERTS_NGINX"
    sudo cp -f "$AUTO_CERT" "$CERTS_NGINX/cert.pem"
    sudo cp -f "$AUTO_CERT_KEY" "$CERTS_NGINX/cert.key"
    sudo chmod 600 "$CERTS_NGINX/cert.key"
    sudo chmod 644 "$CERTS_NGINX/cert.pem"
    log_info "已复制 --auto 指定的 nginx 证书到 $CERTS_NGINX"
}

# 安装完成后通过 blog-server 交互式 CLI 注册管理员.
# 返回: 注册成功后重启服务, 注册失败时输出提示并返回 0.
auto_register_admin() {
    [ "$AUTO_MODE" = "true" ] || return 0

    if [ -z "$AUTO_ADMIN_USERNAME" ] || [ -z "$AUTO_ADMIN_EMAIL" ] || [ -z "$AUTO_ADMIN_PASSWORD" ]; then
        return 0
    fi

    log_info "开始自动注册管理员: $AUTO_ADMIN_EMAIL"
    if printf '%s\n%s\n%s\n%s\n' "$AUTO_ADMIN_USERNAME" "$AUTO_ADMIN_EMAIL" "$AUTO_ADMIN_PASSWORD" "$AUTO_ADMIN_PASSWORD" | sudo docker exec -i blog-server /home/blog-server/blog-server register-admin; then
        log_info "管理员自动注册完成: $AUTO_ADMIN_EMAIL"
        docker_server_restart
    else
        log_warn "管理员自动注册未完成, 请执行 register_admin 或访问 https://$DOMAIN_NAME/register-admin 手动完成首次注册"
    fi
}

# 执行零交互一键安装.
# 参数: $@: --auto 模式参数列表.
# 返回: 安装完成或遇到错误退出.
auto_one_click_install() {
    parse_auto_args "$@"
    validate_auto_args
    auto_accept_disclaimer

    check
    auto_prepare_nginx_cert

    log_info "开始执行 --auto 零交互一键安装"
    add_group_user
    gen_my_ca_cert
    auto_prepare_nginx_cert
    install_docker
    pull_docker_image_pro_all
    reset_install_database
    {
        echo "y"
        echo "n"
    } | docker_server_client_install
    auto_register_admin
    log_info "--auto 零交互一键安装完成"
}
