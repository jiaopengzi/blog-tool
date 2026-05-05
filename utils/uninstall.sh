#!/bin/bash
# FilePath    : blog-tool/utils/uninstall.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : blog-tool 用户版卸载工具

# 获取当前脚本的绝对路径.
# 返回: 通过 stdout 输出脚本绝对路径.
get_blog_tool_script_path() {
    log_debug "run get_blog_tool_script_path"

    local script_path="${BASH_SOURCE[0]}"

    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$script_path"
    else
        echo "$ROOT_DIR/$(basename "$script_path")"
    fi
}

# 输出用户版涉及的 compose 文件和项目名称.
# 返回: 每行输出 file|project 格式.
list_blog_tool_user_compose_projects() {
    log_debug "run list_blog_tool_user_compose_projects"

    cat <<-EOM
$DOCKER_COMPOSE_FILE_PGSQL|$DOCKER_COMPOSE_PROJECT_NAME_PGSQL
$DOCKER_COMPOSE_FILE_REDIS|$DOCKER_COMPOSE_PROJECT_NAME_REDIS
$DOCKER_COMPOSE_FILE_ES|$DOCKER_COMPOSE_PROJECT_NAME_ES
$DOCKER_COMPOSE_FILE_SERVER|$DOCKER_COMPOSE_PROJECT_NAME_SERVER
$DOCKER_COMPOSE_FILE_CLIENT|$DOCKER_COMPOSE_PROJECT_NAME_CLIENT
EOM
}

# 删除 blog-tool 运行期间可能残留的临时容器.
# 返回: 清理完成.
remove_blog_tool_temp_containers() {
    log_debug "run remove_blog_tool_temp_containers"

    local container_name=""
    local -a temp_containers=(
        temp_container_blog_server
        temp_container_blog_client
        temp_container_es
        temp_container_kibana
    )

    for container_name in "${temp_containers[@]}"; do
        sudo docker rm -f "$container_name" >/dev/null 2>&1 || true
    done
}

# 停止并删除当前 blog-tool 创建的项目容器.
# 返回: 0 表示执行完成, 非 0 表示 docker 不可用.
remove_blog_tool_containers() {
    log_debug "run remove_blog_tool_containers"

    local item=""
    local compose_file=""
    local project_name=""
    local container_ids=""

    if ! command -v docker >/dev/null 2>&1; then
        log_warn "未检测到 docker 命令, 跳过容器清理"
        return 1
    fi

    remove_blog_tool_temp_containers

    while IFS= read -r item; do
        [ -z "$item" ] && continue

        compose_file="${item%%|*}"
        project_name="${item##*|}"

        if [ -f "$compose_file" ]; then
            sudo docker compose -f "$compose_file" -p "$project_name" down || true
        fi

        container_ids=$(sudo docker ps -aq --filter "label=com.docker.compose.project=$project_name")
        if [ -n "$container_ids" ]; then
            echo "$container_ids" | xargs -r sudo docker rm -f >/dev/null 2>&1 || true
        fi
    done < <(list_blog_tool_user_compose_projects)

    log_info "已停止并删除当前 blog-tool 项目容器"
}

# 删除当前 blog-tool 创建的项目网络.
# 返回: 清理完成.
remove_blog_tool_networks() {
    log_debug "run remove_blog_tool_networks"

    local network_name=""
    local -a network_names=(
        "$BRIDGE_PGSQL"
        "$BRIDGE_REDIS"
        "$BRIDGE_ES"
        "$BRIDGE_SERVER"
        "$BRIDGE_CLIENT"
    )

    for network_name in "${network_names[@]}"; do
        [ -n "$network_name" ] || continue
        sudo docker network rm "$network_name" >/dev/null 2>&1 || true
    done

    log_info "已清理当前 blog-tool 项目网络"
}

# 收集当前 blog-tool 使用过的镜像引用.
# 返回: 通过 stdout 输出去重后的镜像列表, 每行一个.
collect_blog_tool_images() {
    log_debug "run collect_blog_tool_images"

    local item=""
    local compose_file=""

    while IFS= read -r item; do
        [ -z "$item" ] && continue

        compose_file="${item%%|*}"
        if [ ! -f "$compose_file" ]; then
            continue
        fi

        awk '
            /^[[:space:]]*image:[[:space:]]*/ {
                line = $0
                sub(/^[[:space:]]*image:[[:space:]]*/, "", line)
                gsub(/"/, "", line)
                gsub(/\047/, "", line)
                print line
            }
        ' "$compose_file"
    done < <(list_blog_tool_user_compose_projects)

    sudo docker images --format '{{.Repository}}:{{.Tag}}' | awk '
        $0 ~ /(^|\/)blog-server:/ || $0 ~ /(^|\/)blog-client:/ {
            print $0
        }
    '
}

# 删除当前 blog-tool 涉及的镜像.
# 返回: 0 表示执行完成, 非 0 表示 docker 不可用.
remove_blog_tool_images() {
    log_debug "run remove_blog_tool_images"

    local image_ref=""
    local image_count=0

    if ! command -v docker >/dev/null 2>&1; then
        log_warn "未检测到 docker 命令, 跳过镜像清理"
        return 1
    fi

    remove_blog_tool_temp_containers

    while IFS= read -r image_ref; do
        [ -n "$image_ref" ] || continue
        sudo docker image rm -f "$image_ref" >/dev/null 2>&1 || true
        image_count=$((image_count + 1))
    done < <(collect_blog_tool_images | awk 'NF > 0' | sort -u)

    if [ $image_count -eq 0 ]; then
        log_info "未检测到需要删除的 blog-tool 镜像"
    else
        log_info "已删除 $image_count 个 blog-tool 相关镜像引用"
    fi
}

# 删除当前 blog-tool 的全部数据目录.
# 返回: 清理完成.
remove_blog_tool_volume_dir() {
    log_debug "run remove_blog_tool_volume_dir"

    if [ -d "$DATA_VOLUME_DIR" ]; then
        sudo rm -rf "$DATA_VOLUME_DIR"
        log_info "已删除数据目录: $DATA_VOLUME_DIR"
    else
        log_info "数据目录不存在, 跳过删除: $DATA_VOLUME_DIR"
    fi
}

# 删除 blog-tool 日志文件.
# 返回: 清理完成.
remove_blog_tool_log_file() {
    log_debug "run remove_blog_tool_log_file"

    if [ -f "$LOG_FILE" ]; then
        sudo rm -f "$LOG_FILE"
        printf '[%s]\n' "已删除日志文件: $LOG_FILE" >&2
    else
        printf '[%s]\n' "日志文件不存在, 跳过删除: $LOG_FILE" >&2
    fi
}

# 执行当前 blog-tool 安装的卸载流程.
# 返回: 完成用户选择的卸载项.
uninstall_blog_tool() {
    log_debug "run uninstall_blog_tool"

    local confirm_uninstall=""
    local remove_containers_choice=""
    local remove_volume_choice=""
    local remove_images_choice=""
    local remove_log_choice=""
    local uninstall_docker_choice=""
    local remove_docker_data_choice="n"
    local script_path=""

    if [ "$BLOG_TOOL_BUILD_TYPE" != "user" ]; then
        log_error "--uninstall 仅支持用户版 blog-tool.sh"
        exit 1
    fi

    script_path=$(get_blog_tool_script_path)

    confirm_uninstall=$(read_user_input "即将卸载当前 blog-tool.sh 安装的项目, 并按你的选择删除容器、volume、镜像、日志和 Docker.\n是否继续, 默认n [y|n]? " "n")
    if [ "$confirm_uninstall" != "y" ]; then
        log_info "已取消卸载"
        return
    fi

    remove_containers_choice=$(read_user_input "[1/5]是否停止并删除当前项目容器, 默认y [y|n]? " "y")
    remove_images_choice=$(read_user_input "[2/5]是否删除当前项目涉及的 docker 镜像, 默认y [y|n]? " "y")
    remove_volume_choice=$(read_user_input "[3/5]是否删除当前项目全部 volume 数据目录, 默认y [y|n]? " "y")
    uninstall_docker_choice=$(read_user_input "[4/5]是否卸载 docker 软件, 默认n [y|n]? " "n")
    remove_log_choice=$(read_user_input "[5/5]是否删除 blog-tool 日志文件, 默认y [y|n]? " "y")

    if [ "$uninstall_docker_choice" = "y" ]; then
        remove_docker_data_choice=$(read_user_input "是否同时删除 docker 历史数据目录 /var/lib/docker 和 /var/lib/containerd, 默认n [y|n]? " "n")
    fi

    if [ "$remove_containers_choice" = "y" ]; then
        remove_blog_tool_containers
        remove_blog_tool_networks
    else
        log_info "跳过项目容器清理"
    fi

    if [ "$remove_images_choice" = "y" ]; then
        remove_blog_tool_images
    else
        log_info "跳过项目镜像清理"
    fi

    if [ "$remove_volume_choice" = "y" ]; then
        remove_blog_tool_volume_dir
    else
        log_info "跳过项目 volume 目录清理"
    fi

    if [ "$uninstall_docker_choice" = "y" ]; then
        __uninstall_docker "$remove_docker_data_choice"
    else
        log_info "跳过 docker 卸载"
    fi

    if [ "$remove_log_choice" = "y" ]; then
        remove_blog_tool_log_file
    else
        log_info "跳过日志文件清理"
    fi

    printf '%s\n' \
        "" \
        "当前脚本卸载流程已执行完成." \
        "如需彻底移除脚本文件, 请手动删除: $script_path"
}