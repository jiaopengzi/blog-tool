#!/bin/bash
# FilePath    : blog-tool/server/deploy.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : server 部署

# 删除 server 镜像
docker_rmi_server() {
    log_debug "run docker_rmi_server"

    local is_delete
    is_delete=$(read_user_input "确认停止 server 服务并删除镜像吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        docker_server_stop

        log_debug "执行的命令：sudo docker images --format \"table {{.Repository}}\t{{.Tag}}\t{{.ID}}\" | grep blog-server | awk '{print \$3}' | xargs sudo docker rmi -f"

        sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | grep blog-server | awk '{print $3}' | xargs sudo docker rmi -f

        log_info "删除 server 镜像完成, 请使用 sudo docker images 查看镜像明细"
    fi
}

# 创建 sever 的 volume
mkdir_server_volume() {
    log_debug "run mkdir_server_volume"

    # 创建 volume 目录 注意用户id和组id
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$SERVER_UID" "$SERVER_GID" 755 \
        "$DATA_VOLUME_DIR/blog-server" \
        "$DATA_VOLUME_DIR/blog-server/config" \
        "$DATA_VOLUME_DIR/blog-server/uploads" \
        "$DATA_VOLUME_DIR/blog-server/logs"

    log_info "创建 server volume 目录成功"
}

# 删除 client 的 volume
remove_server_volume() {
    log_debug "run remove_server_volume"

    # 询问用户是否删除 volume
    local confirm
    confirm=$(read_user_input "是否删除 server 相关 volume 数据 (默认n) [y|n]? " "n")
    if [ "$confirm" != "y" ]; then
        log_info "取消删除 server volume 目录"
        return
    fi

    # 如果有 volume 文件夹就删除
    if [ -d "$DATA_VOLUME_DIR/blog-server" ]; then
        sudo rm -rf "$DATA_VOLUME_DIR/blog-server"
        log_info "删除 $DATA_VOLUME_DIR/blog-server 目录成功"
    fi
}

# 构建 server 开发环境镜像
docker_build_server_env() {
    log_debug "run docker_build_server_env"

    # shellcheck disable=SC2329
    run() {
        cd "$ROOT_DIR" || exit

        git_clone_cd "blog-server-dev"

        # 运行 Dockerfile_golang
        sudo docker build --no-cache -t blog-server:golang -f Dockerfile_golang .

        # # 运行 Dockerfile_alpine
        # sudo docker build --no-cache -t blog-server:alpine -f Dockerfile_alpine .

        # 回到脚本所在目录
        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"
    }

    log_timer "构建 blog-server env 镜像" run
}

# 构建 blog_server 镜像
# 参数: $1: (可选)签名私钥文件路径, 未传则使用 SIGN_PRIVATE_KEY 变量
# 单独调用需要传递环境变量 SIGN_PRIVATE_KEY, key 需要使用绝对路径 示例:
# sudo SIGN_PRIVATE_KEY=/your/path/cert_key.pem bash blog-tool-dev.sh docker_build_server
docker_build_server() {
    log_debug "run docker_build_server"

    local sign_key="${1:-$SIGN_PRIVATE_KEY}"

    # shellcheck disable=SC2329
    run() {
        cd "$ROOT_DIR" || exit

        git_clone_cd "blog-server-dev"

        # # 运行 Dockerfile
        # sudo docker build --no-cache -t "$REGISTRY_REMOTE_SERVER/blog-server:build" -f Dockerfile_dev .

        # 查看私钥路径前16个字符, 确保环境变量传递正确
        log_info "sign_key 前16个字符: ${sign_key:0:16}"

        # 使用 BuildKit 构建, 以支持 --secret 参数传递签名密钥
        # 在容器中的 Makefile 里会使用这个密钥对产物进行签名, 以确保产物的安全性和可信度
        sudo DOCKER_BUILDKIT=1 docker build --no-cache \
            --secret id=sign_key,src="$sign_key" \
            -t "$REGISTRY_REMOTE_SERVER/blog-server:build" \
            -f Dockerfile_dev .

        # 回到脚本所在目录
        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"
    }

    log_timer "构建 blog-server 镜像" run
}

# 创建 server 的临时容器并执行传入的函数
docker_create_server_temp_container() {
    log_debug "run docker_create_server_temp_container"

    # 执行函数
    local run_func="$1"
    # 容器标签
    local version="$2"

    # 判断是否有临时容器存在, 有就删除
    if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^temp_container_blog_server\$"; then
        sudo docker rm -f temp_container_blog_server >/dev/null 2>&1 || true
    fi

    # 创建临时容器
    sudo docker create -u "$SERVER_UID:$SERVER_GID" --name temp_container_blog_server "$(get_img_prefix)/blog-server:$version" >/dev/null 2>&1 || true

    # 执行传入的函数
    $run_func

    # 删除临时容器
    sudo docker rm -f temp_container_blog_server >/dev/null 2>&1 || true
}

# server 产物目录
DIR_ARTIFACTS_SERVER="$DATA_VOLUME_DIR/blog-server/artifacts"
DIR_APP_SERVER="$DATA_VOLUME_DIR/blog-server/artifacts/blog-server"

# server 产物复制到本地
server_artifacts_copy_to_local() {
    log_debug "run server_artifacts_copy_to_local"

    local dir_artifacts=$DIR_ARTIFACTS_SERVER
    local dir_app=$DIR_APP_SERVER

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
        sudo docker cp temp_container_blog_server:/home/blog-server "$dir_artifacts"
    }

    # 使用 build 版本的镜像复制产物
    docker_create_server_temp_container run_copy_artifacts "build"

    log_info "blog-server 产物复制到本地, 产物路径: $dir_app"

    # 查看版本
    log_debug "blog-server 版本: $(sudo cat "$dir_app/VERSION" 2>/dev/null)"
}

# server 产物版本获取
server_artifacts_version() {
    local dir_app=$DIR_APP_SERVER

    # cat 读取 VERSION 文件内容
    local version
    version=$(sudo cat "$dir_app/VERSION" 2>/dev/null)

    # 解析版本号
    read -r version is_dev <<<"$(parsing_version "$version")"

    echo "$version" "$is_dev"
}

# server 产物打包
server_artifacts_zip() {
    local version="$1"
    local dir_artifacts=$DIR_ARTIFACTS_SERVER
    local dir_app=$DIR_APP_SERVER

    # 记录当前所在目录
    local current_dir
    current_dir=$(pwd)

    # 将 app 目录下的文件进行 zip 打包并保存到 artifacts 目录下
    cd "$dir_app" || exit

    # 构造 zip 压缩包名称
    zip_name="blog-server-$version.zip"

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

# 推送 server 镜像到远端服务器
docker_push_server() {
    log_debug "run docker_push_server"

    # 1. 复制产物到本地
    server_artifacts_copy_to_local

    # 2. 获取版本号
    local version_info
    version_info=$(server_artifacts_version)
    read -r version is_dev <<<"$version_info"

    # 3. 推送到私有仓库
    docker_tag_push_private_registry "blog-server" "$version"

    echo "暂时不发布到生产环境, 仅推送到私有仓库"

    # # 4. 更新 changelog
    # sync_repo_by_tag "blog-server" "$version" "$GIT_GITHUB"
    # sync_repo_by_tag "blog-server" "$version" "$GIT_GITEE"

    # # 5. 发布到生产环境
    # if [ "$is_dev" = false ]; then
    #     # 推送到 Docker Hub
    #     docker_tag_push_docker_hub "blog-server" "$version"

    #     # 产物发布到 GitHub 和 Gitee Releases

    #     # 打包产物
    #     local zip_path
    #     zip_path=$(server_artifacts_zip "$version")

    #     # 发布
    #     releases_with_md_platform "blog-server" "$version" "$zip_path" "github"
    #     releases_with_md_platform "blog-server" "$version" "$zip_path" "gitee"

    #     # 移除压缩包
    #     if [ -f "$zip_path" ]; then
    #         sudo rm -f "$zip_path"
    #         log_info "移除本地产物包 $zip_path 成功"
    #     fi
    # else
    #     # 如果不是生产环境, 复制到本地的产物包删除
    #     sudo rm -rf "$DIR_APP_SERVER"
    # fi
}

# 拉取 server 镜像
docker_pull_server() {
    log_debug "run docker_pull_server"

    local version=${1-latest}

    # 根据运行模式拉取不同仓库的镜像
    if run_mode_is_dev; then
        # shellcheck disable=SC2329
        run() {
            timeout_retry_docker_pull "$REGISTRY_REMOTE_SERVER/blog-server" "$version"
            # sudo docker pull "$REGISTRY_REMOTE_SERVER/blog-server:$version"
        }
        docker_private_registry_login_logout run
    else
        timeout_retry_docker_pull "$DOCKER_HUB_OWNER/blog-server" "$version"
        # sudo docker pull "$DOCKER_HUB_OWNER/blog-server:$version"
    fi
}

# 构建 server 推送镜像
docker_build_push_server() {
    log_debug "run docker_build_push_server"

    docker_build_server
    docker_push_server
}

# 启动 server 容器
wait_server_start() {
    log_debug "run wait_server_start"

    log_warn "等待 blog-server 启动, 这可能需要几分钟时间... 请勿中断！"

    # 如果超过5分钟还没启动成功就报错退出
    local timeout=300
    local start_time
    start_time=$(date +%s)

    until sudo curl -s "http://$HOST_INTRANET_IP:5426/api/v1/is-setup" | grep -q "request_id"; do
        # 等待 10 秒, 并显示动画
        waiting 10

        # 检查是否超时
        local current_time
        current_time=$(date +%s)

        # 计算经过的时间
        local elapsed_time=$((current_time - start_time))

        # 如果超过超时时间就报错退出
        if [ "$elapsed_time" -ge "$timeout" ]; then
            log_error "blog-server 启动超时, 请检查日志排查问题."
            exit 1
        fi
    done

    # 再等 5 秒, 让 docker 健康检查有时间完成
    waiting 5

    log_info "blog-server 启动完成"
}

# 启动 server 容器
docker_server_start() {
    log_debug "run docker_server_install"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_SERVER" -p "$DOCKER_COMPOSE_PROJECT_NAME_SERVER" up -d

    # 等待 server 启动
    wait_server_start
}

# 停止 server 容器
docker_server_stop() {
    log_debug "run docker_server_stop"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_SERVER" -p "$DOCKER_COMPOSE_PROJECT_NAME_SERVER" down || true
}

# 重启 server 容器
docker_server_restart() {
    log_debug "run docker_server_restart"
    docker_server_stop
    docker_server_start
}

# 设置 server 是否完成初始化
docker_server_install() {
    log_debug "run docker_server_install"

    local is_install
    is_install=$(read_user_input "$WEB_INSTALL_SERVER_TIPS" "n")

    # 是否全新安装 server
    if [ "$is_install" == "y" ]; then
        local web_set_db
        web_set_db=$(read_user_input "$WEB_SET_DB_TIPS" "n")

        mkdir_server_volume

        log_debug "web_set_db=$web_set_db"
        copy_server_config "$web_set_db"

        create_docker_compose_server
        docker_server_start

        log_info "server 容器启动完成, 请使用 sudo docker ps -a 查看容器明细"

        # log_info "监控日志"
        # blog_server_logs
    else
        log_info "退出全新安装"
    fi
}

# 删除 server 服务及数据
docker_server_delete() {
    log_debug "run docker_server_delete"

    local is_delete
    is_delete=$(read_user_input "确认停止 server 服务并删除数据吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        docker_server_stop

        log_debug "is_delete=====> $is_delete"

        echo "$is_delete" | remove_server_volume

        log_info "server 服务及数据删除完成, 请使用 sudo docker ps -a 查看容器明细"
    fi
}
