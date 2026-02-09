#!/bin/bash
# FilePath    : blog-tool/client/deploy.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : server 部署

# 删除 client 镜像
docker_rmi_client() {
    # 删除镜像
    log_debug "run docker_rmi_client"

    local is_delete
    is_delete=$(read_user_input "确认停止 client 服务并删除镜像吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        docker_client_stop

        log_debug "执行的命令：sudo docker images --format \"table {{.Repository}}\t{{.Tag}}\t{{.ID}}\" | grep blog-client | awk '{print \$3}' | xargs sudo docker rmi -f"
        sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | grep blog-client | awk '{print $3}' | xargs sudo docker rmi -f

        log_info "删除 client 镜像完成, 请使用 sudo docker images 查看镜像明细"
    fi
}

# 创建 client 的 volume
mkdir_client_volume() {
    # 创建 volume 目录 注意用户id和组id
    log_debug "run mkdir_client_volume"

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$CLIENT_UID" "$CLIENT_GID" 755 \
        "$DATA_VOLUME_DIR/blog-client" \
        "$DATA_VOLUME_DIR/blog-client/nginx"

    log_info "创建 client volume 目录成功"
}

# 删除 client 的 volume
remove_client_volume() {
    log_debug "run remove_client_volume"

    # 询问用户是否删除 volume
    local confirm
    confirm=$(read_user_input "是否删除 client 相关 volume 数据 (默认n) [y|n]? " "n")
    if [ "$confirm" != "y" ]; then
        log_info "取消删除 client volume 目录"
        return
    fi

    # 如果有 volume 文件夹就删除
    if [ -d "$DATA_VOLUME_DIR/blog-client" ]; then
        sudo rm -rf "$DATA_VOLUME_DIR/blog-client"
        log_info "删除 $DATA_VOLUME_DIR/blog-client 目录成功"
    fi
}

# 构建 client 开发环境镜像
docker_build_client_env() {
    log_debug "run docker_build_client_env"

    # shellcheck disable=SC2329
    run() {
        cd "$ROOT_DIR" || exit

        git_clone_cd "blog-client-dev"

        # 运行 Dockerfile.env
        sudo docker build --no-cache -t blog-client:env -f Dockerfile.env .

        # 回到脚本所在目录
        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"
    }

    log_timer "构建 blog-client:env 镜像" run
}

# 构建 blog_client 镜像
docker_build_client() {
    log_debug "run docker_build_client"

    # shellcheck disable=SC2329
    run() {
        # 回到脚本所在目录
        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"

        git_clone_cd "blog-client-dev"

        # 运行 Dockerfile
        sudo docker build --no-cache -t "$REGISTRY_REMOTE_SERVER/blog-client:build" -f Dockerfile.dev .

        # 回到脚本所在目录
        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"
    }

    log_timer "构建 blog-client 镜像" run
}

# 创建 client 的临时容器并执行传入的函数
docker_create_client_temp_container() {
    log_debug "run docker_create_client_temp_container"

    # 执行函数
    local run_func="$1"
    # 容器标签
    local version="$2"

    # 判断是否有临时容器存在, 有就删除
    if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^temp_container_blog_client\$"; then
        sudo docker rm -f temp_container_blog_client >/dev/null 2>&1 || true
    fi

    # 创建临时容器
    sudo docker create -u "$CLIENT_UID:$CLIENT_GID" --name temp_container_blog_client "$(get_img_prefix)/blog-client:$version" >/dev/null 2>&1 || true

    # 执行传入的函数
    $run_func

    # 删除临时容器
    sudo docker rm -f temp_container_blog_client >/dev/null 2>&1 || true
}

# client 产物目录
DIR_ARTIFACTS_CLIENT="$DATA_VOLUME_DIR/blog-client/artifacts"
DIR_APP_CLIENT="$DATA_VOLUME_DIR/blog-client/artifacts/app"

# server 产物复制到本地
client_artifacts_copy_to_local() {
    log_debug "run client_artifacts_copy_to_local"

    local dir_artifacts=$DIR_ARTIFACTS_CLIENT
    local dir_app=$DIR_APP_CLIENT

    if [ ! -d "$dir_artifacts" ]; then
        sudo mkdir -p "$dir_artifacts"
    fi

    # 如果有 app 目录就删除, 然后重新创建
    if [ -d "$dir_app" ]; then
        sudo rm -rf "$dir_app"
    fi
    sudo mkdir -p "$dir_app"

    # shellcheck disable=SC2329
    run_copy_artifacts() {
        # 复制编译产物到本地
        sudo docker cp temp_container_blog_client:/etc/nginx "$dir_app"            # nginx 配置文件
        sudo docker cp temp_container_blog_client:/usr/share/nginx/html "$dir_app" # 前端静态文件
    }

    # 使用 build 版本的镜像复制产物
    docker_create_client_temp_container run_copy_artifacts "build"

    log_info "blog-client 产物复制到本地, 产物路径: $dir_app"

    # 查看版本
    log_debug "blog-client 版本: $(sudo cat "$dir_app/html/VERSION" 2>/dev/null)"
}

# client 产物版本获取
client_artifacts_version() {
    local dir_app=$DIR_APP_CLIENT

    # cat 读取 VERSION 文件内容
    local version
    version=$(sudo cat "$dir_app/html/VERSION" 2>/dev/null)

    # 解析版本号
    read -r version is_dev <<<"$(parsing_version "$version")"

    echo "$version" "$is_dev"
}

# client 产物打包
client_artifacts_zip() {
    local version="$1"
    local dir_artifacts=$DIR_ARTIFACTS_CLIENT
    local dir_app=$DIR_APP_CLIENT

    # 记录当前所在目录
    local current_dir
    current_dir=$(pwd)

    # 将 app 目录下的文件进行 zip 打包并保存到 artifacts 目录下
    cd "$dir_app" || exit

    # 构造 zip 压缩包名称
    zip_name="blog-client-$version.zip"

    # 打印当前目录
    log_debug "需要打包的目录 $(pwd)"

    # 判断当前目录是否为空
    if [ -z "$(ls -A .)" ]; then
        log_error "blog-server 产物目录为空, 无法打包"
        exit 1
    fi

    # shellcheck disable=SC2329
    run() {
        # 打包 zip, 静默模式
        sudo zip -qr "../$zip_name" ./*
    }

    wait_file_write_complete run "../$zip_name"

    # 回到脚本所在目录
    cd "$current_dir" || exit

    # 移除 app 目录
    sudo rm -rf "$dir_app"

    # 返回打包包名称供后续使用
    echo "$dir_artifacts/$zip_name"
}

# 推送 client 镜像到远端服务器
docker_push_client() {
    log_debug "run docker_push_client"

    # 1. 复制产物到本地
    client_artifacts_copy_to_local

    # 2. 获取版本号
    local version_info
    version_info=$(client_artifacts_version)
    read -r version is_dev <<<"$version_info"

    # 3. 推送到私有仓库
    docker_tag_push_private_registry "blog-client" "$version"

    # 4. 更新 changelog
    sync_repo_by_tag "blog-client" "$version" "$GIT_GITHUB"
    sync_repo_by_tag "blog-client" "$version" "$GIT_GITEE"

    # 5. 发布到生产环境
    if [ "$is_dev" = false ]; then
        # # 推送到 Docker Hub
        docker_tag_push_docker_hub "blog-client" "$version"

        # 产物发布到 GitHub 和 Gitee Releases

        # 打包产物
        local zip_path
        zip_path=$(client_artifacts_zip "$version")

        # 发布
        releases_with_md_platform "blog-client" "$version" "$zip_path" "github"
        releases_with_md_platform "blog-client" "$version" "$zip_path" "gitee"

        # 移除压缩包
        if [ -f "$zip_path" ]; then
            sudo rm -f "$zip_path"
            log_info "移除本地产物包 $zip_path 成功"
        fi
    else
        # 如果不是生产环境, 复制到本地的产物包删除
        sudo rm -rf "$DIR_APP_CLIENT"
    fi
}

# 拉取 client 镜像
docker_pull_client() {
    log_debug "run docker_pull_client"

    local version=${1-latest}

    # 根据运行模式拉取不同仓库的镜像
    if run_mode_is_dev; then
        # shellcheck disable=SC2329
        run() {
            timeout_retry_docker_pull "$REGISTRY_REMOTE_SERVER/blog-client" "$version"
            # sudo docker pull "$REGISTRY_REMOTE_SERVER/blog-client:$version"
        }
        docker_private_registry_login_logout run
    else
        timeout_retry_docker_pull "$DOCKER_HUB_OWNER/blog-client" "$version"
        # sudo docker pull "$DOCKER_HUB_OWNER/blog-client:$version"
    fi
}

# 构建 client 推送镜像
docker_build_push_client() {
    log_debug "run docker_build_push_client"

    docker_build_client
    docker_push_client
}

# 启动 server client 面板服务信息
panel_msg() {
    # 打印访问地址
    local msg

    # 判断 DOMAIN_NAME 中是否有协议头, 都统一为 https
    if [[ "$DOMAIN_NAME" != http*://* ]]; then
        DOMAIN_NAME="https://$DOMAIN_NAME"
    fi

    msg="\n================================\n\n"
    msg+=" blog 服务已启动成功! 请在浏览器中访问: $DOMAIN_NAME\n\n"
    msg+=" 管理员注册请访问(仅限首次注册): $DOMAIN_NAME/register-admin\n\n"
    msg+="================================"

    echo -e "${GREEN}${msg}${NC}"
}

# 提示证书信息
ssl_msg() {

    # $1 显示颜色
    local color="$1"

    local msg
    msg="\n================================"
    msg+="\n 1. 如果您需要设置自己域名的证书, 请将您的证书复制到目录 $CERTS_NGINX, 证书文件命名 cert.pem 和 cert.key; 然后重启 client 服务."
    msg+="\n 2. 如果局域网使用, 请使用当前脚本, 生成自定义证书; 并将自定义的CA证书:$CA_CERT_DIR/ca.crt 导出并安装到受信任的根证书颁发机构, 用于处理浏览器 https 警告."
    msg+="\n================================\n"

    echo -e "${color}${msg}${NC}"
}

# 显示面板信息
show_panel() {
    log_debug "run show_panel"

    # 打印面板信息
    panel_msg

    # 提示证书信息
    ssl_msg "$GREEN"
}

# 启动 client 容器
docker_client_start() {
    log_debug "run docker_client_start"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_CLIENT" -p "$DOCKER_COMPOSE_PROJECT_NAME_CLIENT" up -d

    # 显示面板信息
    show_panel
}

# 停止 client 容器
docker_client_stop() {
    log_debug "run docker_client_stop"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_CLIENT" -p "$DOCKER_COMPOSE_PROJECT_NAME_CLIENT" down || true
}

# 重启 client 容器
docker_client_restart() {
    log_debug "run docker_client_restart"
    docker_client_stop
    docker_client_start
}

# 启动 client 容器
docker_client_install() {
    log_debug "run docker_client_install"

    mkdir_client_volume
    copy_client_config
    create_docker_compose_client
    docker_client_start

    log_info "client 容器启动完成"
}

# 删除 client 服务及数据
docker_client_delete() {
    log_debug "run docker_client_delete"

    local is_delete
    is_delete=$(read_user_input "确认停止 client 服务并删除数据吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        docker_client_stop

        log_debug "is_delete=====> $is_delete"

        echo "$is_delete" | remove_client_volume

        log_info "client 服务及数据删除完成, 请使用 sudo docker ps -a 查看容器明细"
    fi
}
