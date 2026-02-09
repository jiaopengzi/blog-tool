#!/bin/bash
# FilePath    : blog-tool/utils/cert.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 证书工具

# 生成 ca 证书
gen_ca_cert() {
    log_debug "run gen_ca_cert"

    local ca_cert_dir="$1"                   # CA 证书存放目录
    local days_valid="$2"                    # 证书有效期
    local ca_key_file="$ca_cert_dir/ca.key"  # CA 私钥文件
    local ca_cert_file="$ca_cert_dir/ca.crt" # CA 证书文件

    log_info "生成私有 CA 证书..."

    # 生成 CA 私钥
    sudo openssl genpkey -algorithm RSA -out "$ca_key_file"
    # 参数解释：
    # genpkey - 生成私钥
    # -algorithm RSA - 使用 RSA 算法
    # -out "$ca_key_file" - 输出私钥文件路径
    # -aes256 - 使用 AES-256 加密私钥
    # -pass pass:your-password - 私钥加密密码

    sudo openssl req -x509 -new -nodes \
        -key "$ca_key_file" \
        -sha256 \
        -days "$days_valid" \
        -out "$ca_cert_file" \
        -subj "/C=CN/ST=Sichuan/L=Chengdu/O=jpz/OU=dev/CN=$HOST_INTRANET_IP"
    # 参数解释：
    # req - 生成证书请求
    # -x509 - 生成自签名证书
    # -new - 创建新的证书请求
    # -nodes - 不加密私钥(这里因为之前已经不加密私钥, 所以不用再次加密)
    # -key "$ca_key_file" - 使用指定的私钥文件
    # -sha256 - 使用 SHA-256 算法签名
    # -days "$days_valid" - 证书有效期
    # -out "$ca_cert_file" - 输出证书文件路径
    # -subj "/C=CN/ST=Sichuan/L=Chengdu/O=jpz/OU=it/CN=127.0.0.1" - 证书主题信息

    # 证书主题信息详细注释：
    # /C=CN - 国家名 (Country Name), 例如 CN 代表中国
    # /ST=Sichuan - 州或省名 (State or Province Name), 例如 Sichuan 代表四川省
    # /L=Chengdu - 地方名 (Locality Name), 例如 Chengdu 代表成都市
    # /O=jpz - 组织名 (Organization Name), 例如 jpz 代表您的公司
    # /OU=it - 组织单位名 (Organizational Unit Name), 例如 dev 代表您的部门
    # /CN=127.0.0.1 - 公共名 (Common Name), 例如 127.0.0.1 代表您的私有 IP 地址

    # 删除临时文件 ca.srl
    sudo rm -f "$ca_cert_dir/ca.srl"

    log_info "CA 证书和私钥已生成并保存在 $ca_cert_dir 目录中。"
}

# 定义一个函数来生成实例证书
generate_instance_cert() {
    log_debug "run generate_instance_cert"

    local name=$1               # 实例名称
    local dns_list=$2           # DNS 列表
    local ip_list=$3            # IP 列表
    local cert_dir=$4           # 证书存放目录
    local days_valid=$5         # 证书有效期
    local ca_cert_file=$6       # CA 证书文件
    local ca_key_file=$7        # CA 私钥文件
    local cert_cn="${8:-$name}" # 证书的 CN 字段, 默认使用实例名称, 可以传入其他值

    # 生成实例私钥
    sudo openssl genpkey -algorithm RSA -out "$cert_dir/$name.key"

    # 生成证书签名请求(CSR)
    sudo openssl req -new -key "$cert_dir/$name.key" -out "$cert_dir/$name.csr" -subj "/C=CN/ST=Sichuan/L=Chengdu/O=jpz/OU=it/CN=$cert_cn"

    # 创建 OpenSSL 配置文件
    sudo tee "$cert_dir/$name.cnf" >/dev/null <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
C = CN
ST = Sichuan
L = Chengdu
O = jpz
OU = it
CN = $cert_cn

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
EOF

    # 添加 DNS 和 IP 到配置文件
    local i
    IFS=',' read -ra dns_arr <<<"$dns_list"
    for i in "${!dns_arr[@]}"; do
        echo "DNS.$((i + 1)) = ${dns_arr[$i]}" | sudo tee -a "$cert_dir/$name.cnf"
    done

    IFS=',' read -ra ip_arr <<<"$ip_list"
    for i in "${!ip_arr[@]}"; do
        echo "IP.$((i + 1)) = ${ip_arr[$i]}" | sudo tee -a "$cert_dir/$name.cnf"
    done

    # 使用 CA 证书签发实例证书
    sudo openssl x509 -req -in "$cert_dir/$name.csr" \
        -CA "$ca_cert_file" \
        -CAkey "$ca_key_file" \
        -CAcreateserial \
        -out "$cert_dir/$name.crt" \
        -days "$days_valid" \
        -sha256 \
        -extfile "$cert_dir/$name.cnf" \
        -extensions v3_req

    # 删除临时文件
    sudo rm -f "$cert_dir/$name.cnf"
    sudo rm -f "$cert_dir/$name.csr"

    # 根据 ca_cert_file 拿到 CA 的目录
    local ca_cert_dir
    ca_cert_dir=$(dirname "$ca_cert_file")
    sudo rm -f "$ca_cert_dir/ca.srl"

    log_info "$name 证书和私钥已生成并保存在 $cert_dir 目录中。"
}

# 生成我的 CA 证书
gen_my_ca_cert() {
    log_debug "run gen_my_ca_cert"

    # 初始化目录
    # shellcheck disable=SC2153
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CA_CERT_DIR"

    # 判断是否存在 ca.crt 文件, 如果不存在则生成, 如果存在则不生成
    if [ ! -f "$CA_CERT_DIR/ca.crt" ]; then
        # 生成 CA 证书
        gen_ca_cert "$CA_CERT_DIR" "$CERT_DAYS_VALID"
    else
        log_warn "CA 证书已存在, 跳过生成."
    fi
}

# 生成前端 nginx 证书
gen_client_nginx_cert() {
    # 初始化目录
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CERTS_NGINX"

    # 生成证书
    # 判断是否存在 cert.pem 文件, 如果不存在则生成, 如果存在则不生成
    if [ ! -f "$CERTS_NGINX/cert.pem" ]; then
        generate_instance_cert "cert" \
            "localhost,127.0.0.1,$HOST_INTRANET_IP,$PUBLIC_IP_ADDRESS" \
            "127.0.0.1,$HOST_INTRANET_IP,$PUBLIC_IP_ADDRESS" \
            "$CERTS_NGINX" \
            "$CERT_DAYS_VALID" \
            "$CA_CERT_DIR/ca.crt" \
            "$CA_CERT_DIR/ca.key" \
            "$HOST_INTRANET_IP"

        # 将 cert.crt 重命名为 cert.pem
        sudo mv "$CERTS_NGINX/cert.crt" "$CERTS_NGINX/cert.pem"
    else
        log_warn "前端 nginx 证书已存在, 跳过生成."
    fi
}

# 检查证书
gen_cert() {
    log_debug "run gen_cert"

    # 生成 CA 证书
    gen_my_ca_cert

    # 生成前端 nginx 证书
    gen_client_nginx_cert

    log_info "证书检查和生成完成"
}
