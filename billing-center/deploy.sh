#!/bin/bash
# FilePath    : blog-tool/billing-center/deploy.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2026 by jiaopengzi, All Rights Reserved.
# Description : billing_center 部署

# 删除 billing_center 镜像
docker_rmi_billing_center() {
    log_debug "run docker_rmi_billing_center"

    local is_delete
    is_delete=$(read_user_input "确认停止 billing_center 服务并删除镜像吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        docker_billing_center_stop

        log_debug "执行的命令：sudo docker images --format \"table {{.Repository}}\t{{.Tag}}\t{{.ID}}\" | grep billing-center | awk '{print \$3}' | xargs sudo docker rmi -f"

        sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | grep billing-center | awk '{print $3}' | xargs sudo docker rmi -f

        log_info "删除 billing_center 镜像完成, 请使用 sudo docker images 查看镜像明细"
    fi
}

# 创建 sever 的 volume
mkdir_billing_center_volume() {
    log_debug "run mkdir_billing_center_volume"

    # 创建 volume 目录 注意用户id和组id
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 \
        "$DATA_VOLUME_DIR/billing-center" \
        "$DATA_VOLUME_DIR/billing-center/logs"

    log_info "创建 billing_center volume 目录成功"
}

# 删除 client 的 volume
remove_billing_center_volume() {
    log_debug "run remove_billing_center_volume"

    # 询问用户是否删除 volume
    local confirm
    confirm=$(read_user_input "是否删除 billing_center 相关 volume 数据 (默认n) [y|n]? " "n")
    if [ "$confirm" != "y" ]; then
        log_info "取消删除 billing_center volume 目录"
        return
    fi

    # 如果有文件夹就删除
    if [ -d "$DATA_VOLUME_DIR/billing-center" ]; then
        sudo rm -rf "$DATA_VOLUME_DIR/billing-center"
        log_info "删除 $DATA_VOLUME_DIR/billing-center 目录成功"
    fi
}

# 构建 billing_center 开发环境镜像
docker_build_billing_center_env() {
    log_debug "run docker_build_billing_center_env"

    # shellcheck disable=SC2329
    run() {
        cd "$ROOT_DIR" || exit

        git_clone_cd "billing-center"

        # 运行 Dockerfile_golang
        sudo docker build --no-cache -t billing-center:golang -f Dockerfile_golang .

        # 运行 Dockerfile_pnpm
        sudo docker build --no-cache -t billing-center:pnpm -f Dockerfile_pnpm .

        # 回到脚本所在目录
        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"
    }

    log_timer "构建 billing-center golang pnpm 镜像" run
}

# 构建 blog_billing_center 镜像
docker_build_billing_center() {
    log_debug "run docker_build_billing_center"

    # shellcheck disable=SC2329
    run() {
        cd "$ROOT_DIR" || exit

        git_clone_cd "billing-center"

        # 运行 Dockerfile
        sudo docker build --no-cache -t "$REGISTRY_REMOTE_SERVER/billing-center:build" -f Dockerfile_dev .

        # 回到脚本所在目录
        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"
    }

    log_timer "构建 billing-center 镜像" run
}

# 创建 billing_center 的临时容器并执行传入的函数
docker_create_billing_center_temp_container() {
    log_debug "run docker_create_billing_center_temp_container"

    # 执行函数
    local run_func="$1"
    # 容器标签
    local version="$2"

    # 判断是否有临时容器存在, 有就删除
    if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^temp_container_blog_billing_center\$"; then
        sudo docker rm -f temp_container_blog_billing_center >/dev/null 2>&1 || true
    fi

    # 创建临时容器
    sudo docker create -u "$JPZ_UID:$JPZ_GID" --name temp_container_blog_billing_center "$(get_img_prefix)/billing-center:$version" >/dev/null 2>&1 || true

    # 执行传入的函数
    $run_func

    # 删除临时容器
    sudo docker rm -f temp_container_blog_billing_center >/dev/null 2>&1 || true
}

# billing_center 产物目录
DIR_ARTIFACTS_BILLING_CENTER="$DATA_VOLUME_DIR/billing-center/artifacts"
DIR_APP_BILLING_CENTER="$DATA_VOLUME_DIR/billing-center/artifacts/billing-center"

# billing_center 产物复制到本地
billing_center_artifacts_copy_to_local() {
    log_debug "run billing_center_artifacts_copy_to_local"

    local dir_artifacts=$DIR_ARTIFACTS_BILLING_CENTER
    local dir_app=$DIR_APP_BILLING_CENTER

    log_debug "dir_artifacts=====> $dir_artifacts"
    log_debug "dir_app=====> $dir_app"

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
        sudo docker cp temp_container_blog_billing_center:/home/billing-center "$dir_artifacts"
    }

    # 使用 build 版本的镜像复制产物
    docker_create_billing_center_temp_container run_copy_artifacts "build"

    log_info "billing-center 产物复制到本地, 产物路径: $dir_app"

    # 查看版本
    log_debug "billing-center 版本: $(sudo cat "$dir_app/VERSION" 2>/dev/null)"
}

# billing_center 产物版本获取
billing_center_artifacts_version() {
    local dir_app=$DIR_APP_BILLING_CENTER

    # cat 读取 VERSION 文件内容
    local version
    version=$(sudo cat "$dir_app/VERSION" 2>/dev/null)

    # 解析版本号
    read -r version is_dev <<<"$(parsing_version "$version")"

    echo "$version" "$is_dev"
}

# billing_center 产物打包
billing_center_artifacts_zip() {
    local version="$1"
    local dir_artifacts=$DIR_ARTIFACTS_BILLING_CENTER
    local dir_app=$DIR_APP_BILLING_CENTER

    # 记录当前所在目录
    local current_dir
    current_dir=$(pwd)

    # 将 app 目录下的文件进行 zip 打包并保存到 artifacts 目录下
    cd "$dir_app" || exit

    # 构造 zip 压缩包名称
    zip_name="billing-center-$version.zip"

    # 打印当前目录
    log_debug "需要打包的目录 $(pwd)"

    # 判断当前目录是否为空
    if [ -z "$(ls -A .)" ]; then
        log_error "billing-center 产物目录为空, 无法打包"
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

# 推送 billing_center 镜像到远端服务器
docker_push_billing_center() {
    log_debug "run docker_push_billing_center"

    # 1. 复制产物到本地
    billing_center_artifacts_copy_to_local

    # 2. 获取版本号
    local version_info
    version_info=$(billing_center_artifacts_version)
    read -r version is_dev <<<"$version_info"

    # 3. 推送到私有仓库
    docker_tag_push_private_registry "billing-center" "$version"

    echo "不发布到生产环境, 仅推送到私有仓库"

    # # 4. 更新 changelog
    # sync_repo_by_tag "billing-center" "$version" "$GIT_GITHUB"
    # sync_repo_by_tag "billing-center" "$version" "$GIT_GITEE"

    # # 5. 发布到生产环境
    # if [ "$is_dev" = false ]; then
    #     # 推送到 Docker Hub
    #     docker_tag_push_docker_hub "billing-center" "$version"

    #     # 产物发布到 GitHub 和 Gitee Releases

    #     # 打包产物
    #     local zip_path
    #     zip_path=$(billing_center_artifacts_zip "$version")

    #     # 发布
    #     releases_with_md_platform "billing-center" "$version" "$zip_path" "github"
    #     releases_with_md_platform "billing-center" "$version" "$zip_path" "gitee"

    #     # 移除压缩包
    #     if [ -f "$zip_path" ]; then
    #         sudo rm -f "$zip_path"
    #         log_info "移除本地产物包 $zip_path 成功"
    #     fi
    # else
    #     # 如果不是生产环境, 复制到本地的产物包删除
    #     sudo rm -rf "$DIR_APP_BILLING_CENTER"
    # fi
}

# # 拉取 billing_center 镜像
# docker_pull_billing_center() {
#     log_debug "run docker_pull_billing_center"

#     local version=${1-latest}

#     # 根据运行模式拉取不同仓库的镜像
#     if run_mode_is_dev; then
#         # shellcheck disable=SC2329
#         run() {
#             timeout_retry_docker_pull "$REGISTRY_REMOTE_SERVER/billing-center" "$version"
#             # sudo docker pull "$REGISTRY_REMOTE_SERVER/billing-center:$version"
#         }
#         docker_private_registry_login_logout run
#     else
#         timeout_retry_docker_pull "$DOCKER_HUB_OWNER/billing-center" "$version"
#         # sudo docker pull "$DOCKER_HUB_OWNER/billing-center:$version"
#     fi
# }

# 拉取 billing_center 镜像
docker_pull_billing_center() {
    log_debug "run docker_pull_billing_center"

    local version=${1-latest}

    # billing_center 只从私有仓库拉取, 不区分运行模式
    # shellcheck disable=SC2329
    run() {
        timeout_retry_docker_pull "$REGISTRY_REMOTE_SERVER/billing-center" "$version"
        # sudo docker pull "$REGISTRY_REMOTE_SERVER/billing-center:$version"
    }
    docker_private_registry_login_logout run
}

# 构建 billing_center 推送镜像
docker_build_push_billing_center() {
    log_debug "run docker_build_push_billing_center"

    docker_build_billing_center
    docker_push_billing_center
}

# 启动 billing_center 容器
wait_billing_center_start() {
    log_debug "run wait_billing_center_start"

    log_warn "等待 billing-center 启动, 这可能需要几分钟时间... 请勿中断！"

    # 如果超过5分钟还没启动成功就报错退出
    local timeout=300
    local start_time
    start_time=$(date +%s)

    # -k 跳过 SSL 证书验证(自签名证书)
    until sudo curl -sk "https://localhost/api/v1/helper/version" | grep -q "request_id"; do
        # 等待 5 秒, 并显示动画
        waiting 5

        # 检查是否超时
        local current_time
        current_time=$(date +%s)

        # 计算经过的时间
        local elapsed_time=$((current_time - start_time))

        # 如果超过超时时间就报错退出
        if [ "$elapsed_time" -ge "$timeout" ]; then
            log_error "billing-center 启动超时, 请检查日志排查问题."
            exit 1
        fi
    done

    # 再等 5 秒, 让 docker 健康检查有时间完成
    waiting 5

    log_info "billing-center 启动完成"
}

# 启动 billing_center 容器
docker_billing_center_start() {
    log_debug "run docker_billing_center_install"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER" up -d

    # 等待 billing_center 启动
    wait_billing_center_start
}

# 停止 billing_center 容器
docker_billing_center_stop() {
    log_debug "run docker_billing_center_stop"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER" down || true
}

# 重启 billing_center 容器
docker_billing_center_restart() {
    log_debug "run docker_billing_center_restart"
    docker_billing_center_stop
    docker_billing_center_start
}

# 设置 billing_center 是否完成初始化
docker_billing_center_install() {
    log_debug "run docker_billing_center_install"

    local is_install
    is_install=$(read_user_input "是否全新安装 billing_center (y/n)?" "n")

    # 是否全新安装 billing_center
    if [ "$is_install" == "y" ]; then
        mkdir_billing_center_volume
        copy_billing_center_server_config
        copy_billing_center_nginx_config

        create_docker_compose_billing_center
        docker_billing_center_start

        log_info "billing_center 容器启动完成, 请使用 sudo docker ps -a 查看容器明细"

        # log_info "监控日志"
        # billing_center_logs
    else
        log_info "退出全新安装"
    fi
}

# 删除 billing_center 服务及数据
docker_billing_center_delete() {
    log_debug "run docker_billing_center_delete"

    local is_delete
    is_delete=$(read_user_input "确认停止 billing_center 服务并删除数据吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        docker_billing_center_stop

        log_debug "is_delete=====> $is_delete"

        echo "$is_delete" | remove_billing_center_volume

        log_info "billing_center 服务及数据删除完成, 请使用 sudo docker ps -a 查看容器明细"
    fi
}

# 根据版本启动或回滚 server 服务
start_or_rollback_billing_center_by_version() {
    log_debug "run start_or_rollback_billing_center_by_version"

    # 读取用户输入的版本号
    read -r -p "请输入 billing_center 需要升级或回滚的版本号: " version

    # 如果用户没有输入, 使用默认值
    if [ -z "$version" ]; then
        log_error "版本号不能为空, 请重新运行脚本并输入正确的版本号"
    fi

    # # 检查版本是否存在
    # check_service_version "billing-center" "$version"

    # 拉取镜像
    docker_pull_billing_center "$version"

    # 停止容器
    docker_billing_center_stop

    # 按照指定版本创建 docker compose 文件
    create_docker_compose_billing_center "$version"

    # 不删除数据卷重启服务
    docker_billing_center_restart

    log_info "服务 billing-center 已成功升级或回滚到版本 $version"
}
