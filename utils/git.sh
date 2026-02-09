#!/bin/bash
# FilePath    : blog-tool/utils/git.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : git 相关工具

# 从 git 仓库克隆项目并进入目录
git_clone() {
    log_debug "run git_clone"
    # 参数:
    # $1: project_dir 项目目录
    # $2: git_prefix git 仓库前缀, 可选参数, 默认使用 GIT_LOCAL
    local project_dir="$1"
    local git_prefix="${2:-$GIT_LOCAL}"

    log_debug "HOME $HOME"
    log_debug "whoami $(whoami)"
    log_debug "执行克隆命令: git clone $git_prefix/$project_dir.git"

    # 避免和远端仓库冲突, 先删除本地文件夹
    if [ -d "$project_dir" ]; then
        sudo rm -rf "$project_dir"
    fi

    sudo git clone "$git_prefix/$project_dir.git"

    log_debug "查看 git 仓库内容\n$(ls -la "$project_dir")\n"
}

# 从 git 仓库克隆项目并进入目录
git_clone_cd() {
    log_debug "run git_clone_cd"
    # 参数:
    # $1: project_dir 项目目录
    # $2: git_prefix git 仓库前缀, 可选参数, 默认使用 GIT_LOCAL
    local project_dir="$1"
    local git_prefix="${2:-$GIT_LOCAL}"

    git_clone "$project_dir" "$git_prefix"

    # 进入项目目录
    cd "$project_dir" || exit
    log_debug "当前目录 $(pwd)"
}

# git 添加、提交并推送代码
git_add_commit_push() {
    log_debug "run git_add_commit_push"

    # 参数:
    # $1: commit_msg 提交信息
    # $2: force_push 是否强制推送, 可选参数, 默认 false
    local commit_msg="$1"
    local force_push="${2:-false}"

    # 添加所有更改的文件
    sudo git add .

    # 提交更改
    sudo git commit -m "$commit_msg"

    # 推送到远程仓库的主分支
    if [ "$force_push" = true ]; then
        sudo git push -f origin main
        log_warn "强制推送代码到远程仓库"
    else
        sudo git push origin main
        log_info "推送代码到远程仓库"
    fi
}

# 检查当前 Git 工作区是否干净 (无未提交的更改)
git_status_is_clean() {
    log_debug "run git_status_is_clean"
    if [ -z "$(git status --porcelain)" ]; then
        # 工作区干净
        echo true
    else
        # 工作区有未提交的更改
        echo false
    fi
}

# 获取最近的符合 v1.2.3 格式的 Git Tag, 如果没有或不符合格式, 则返回为 dev
get_tag_version() {
    log_debug "run get_tag_version"
    local git_tag
    git_tag=sudo git describe --tags --abbrev=0 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' || echo "dev"
    echo "$git_tag"
}

# 平台: github | gitee
create_release_id() {
    log_debug "run create_release_id"

    local api_prefix="$1"               # API 文件路径
    local token="$2"                    # token
    local repo_owner="$3"               # 仓库所有者
    local repo_name="$4"                # 仓库名称
    local tag="$5"                      # Release 的 Tag 名称
    local release_name="$6"             # Release 名称
    local release_body="$7"             # Release 描述
    local platform="${8:-github}"       # 平台: github | gitee
    local target_commitish="${9:-main}" # 目标分支, gitee 特有参数, 默认为 main

    # 显示回显 token 的前后3位以确认变量传入正确
    log_debug "token 首尾3位: ${token:0:3}...${token: -3}"

    local json_data
    json_data=$(
        jq -n \
            --arg tag_name "$tag" \
            --arg name "$release_name" \
            --arg body "$release_body" \
            --arg target_commitish "$target_commitish" \
            '{
            tag_name: $tag_name,
            name: $name,
            body: $body
        } + (if "'"$platform"'" == "gitee" then {target_commitish: $target_commitish} else {} end)'
    )

    log_debug "创建 Release 的 JSON 数据: $json_data"

    # 创建 Release 的相应
    local release_res
    release_res=$(
        curl -s -X POST \
            -H "Authorization: token $token" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            "$api_prefix/repos/${repo_owner}/${repo_name}/releases" \
            --data "$json_data"
    )

    local release_id
    release_id=$(echo "$release_res" | jq -r '.id // empty')

    if [ -z "$release_id" ]; then
        log_debug "创建 Release 响应: $release_res"
        log_error "创建 Release 失败，未获取到有效的 Release ID"
        exit 1
    fi

    # github 才有的 upload_url
    upload_url=$(echo "$release_res" | jq -r '.upload_url' | sed 's/{.*}//')

    echo "$release_id" "$upload_url"
}

# 产物发布(支持传入多个带路径的文件名, 自动处理 basename 与 URL 编码,如果 release 不存在则创建, 如果 release 存在不上传文件)
artifacts_releases() {
    log_debug "run artifacts_releases"

    local api_prefix="$1"         # API 文件路径
    local token="$2"              # token
    local repo_owner="$3"         # 仓库所有者
    local repo_name="$4"          # 仓库名称
    local tag="$5"                # Release 的 Tag 名称
    local release_name="$6"       # Release 名称
    local release_body="$7"       # Release 描述
    local platform="${8:-github}" # 平台: github | gitee
    shift 8                       # 剩余参数均为要上传的文件路径

    local file_paths=("$@") # 所有剩余参数视为要上传的文件路径数组

    if [ ${#file_paths[@]} -eq 0 ]; then
        log_error "未指定要上传的文件"
        exit 1
    fi

    # 显示回显 token 的前后3位以确认变量传入正确
    log_debug "token 首尾3位: ${token:0:3}...${token: -3}"

    local release_id
    local upload_url

    # 尝试通过 tag 获取 release 信息
    local release_json
    release_json=$(curl -s -H "Authorization: token $token" "$api_prefix/repos/${repo_owner}/${repo_name}/releases/tags/${tag}")

    # 获取 release_id
    local release_id=""
    if echo "$release_json" | grep -q '"id":'; then
        release_id=$(echo "$release_json" | jq -r '.id // empty')
    fi

    # 判断 release 是否存在
    if [ -z "$release_id" ]; then
        # 如果不存在, 则创建新的 Release
        log_info "创建新的 Release：$tag"

        # 2. 获取版本号
        local release_info
        release_info=$(create_release_id "$api_prefix" "$token" "$repo_owner" "$repo_name" "$tag" "$release_name" "$release_body" "$platform" "main")
        read -r __release_id __upload_url <<<"$release_info"
        log_debug "新创建的 Release ID: $release_id"

        # 赋值给外部变量
        release_id="$__release_id"
        upload_url="$__upload_url"
    else
        # 如果已存在, 则获取该 Release 的详细信息以提取 upload_url
        log_warn "Release 已存在：$tag (id：$release_id)，跳过创建 Release 步骤。"
        return
    fi

    # 当新建的时候啊, 遍历所有文件路径, 逐个上传
    for file_path in "${file_paths[@]}"; do
        # 参数检查：单个文件
        if [ -z "$file_path" ]; then
            log_error "未指定有效的文件路径"
            exit 1
        fi
        if [ ! -f "$file_path" ]; then
            log_error "文件未找到：$file_path"
            exit 1
        fi

        # 不同平台生成 release_id
        if [ "$platform" = "github" ]; then
            # GitHub 平台 上传文件到 Release
            upload_to_github_release "$api_prefix" "$token" "$tag" "$file_path" "$upload_url"
        elif [ "$platform" = "gitee" ]; then
            # Gitee 平台
            upload_to_gitee_release "$api_prefix" "$token" "$repo_owner" "$repo_name" "$release_id" "$file_path"
        fi
    done

    log_info "🎉 所有文件上传流程完成"
}

common_upload_with_logging() {
    local platform_name="$1"    # 平台名称，例如 "GitHub" 或 "Gitee"
    local log_message="$2"      # 用于展示的日志信息，如 "📦 GitHub Release [v1.0]"
    local upload_func_name="$3" # 上传逻辑的函数名（字符串，将在下面通过 $upload_func_name() 调用）

    log_debug "run common_upload_with_logging for $platform_name"

    log_info "$log_message: 开始上传..."

    start_spinner

    # 调用传入的上传函数（它是在外部函数作用域内定义的局部函数）
    if $upload_func_name; then
        log_info "$platform_name: ✅ 上传成功"
        stop_spinner
    else
        stop_spinner
        log_error "$platform_name: ❌ 上传失败"
        return 1
    fi
}

# 上传单个文件到 GitHub Release
upload_to_github_release() {
    local api_prefix="$1" # API 前缀
    local token="$2"      # token
    local tag="$3"        # Release 的 Tag 名称
    local file_path="$4"  # 要上传的文件路径
    local upload_url="$5" # 上传 URL

    local base_name
    base_name=$(basename "$file_path")

    # 使用 jq 做 URL encode (jq 已在环境中使用, 故可依赖)
    local encoded_name
    encoded_name=$(jq -nr --arg v "$base_name" '$v|@uri')

    # 拼接最终上传 URL, 带上编码后的文件名参数
    local final_upload_url
    final_upload_url="${upload_url}?name=${encoded_name}"

    log_debug "GitHub 上传 URL: $final_upload_url"

    # 定义一个局部函数，封装该平台的上传逻辑
    # shellcheck disable=SC2329
    github_upload() {
        sudo curl -sS -X POST -H "Authorization: token $token" \
            -H "Accept: application/json" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @"$file_path" \
            "$final_upload_url"
    }

    # 调用公共函数，传入平台名、日志信息、以及刚刚定义的局部函数名
    common_upload_with_logging \
        "GitHub" \
        "📦 GitHub Release [$tag]" \
        github_upload
}

# 上传单个文件到 Gitee Release
upload_to_gitee_release() {
    local api_prefix="$1" # API 前缀
    local token="$2"      # token
    local repo_owner="$3" # 仓库所有者
    local repo_name="$4"  # 仓库名称
    local release_id="$5" # Release ID
    local file_path="$6"  # 要上传的文件路径

    local base_name
    base_name=$(basename "$file_path")

    # 定义一个局部函数，封装该平台的上传逻辑
    # shellcheck disable=SC2329
    gitee_upload() {
        # 使用 curl 上传文件
        # Gitee 的上传附件接口需要 multipart/form-data
        # 参考文档：https://gitee.com/api/v5/swagger#/postV5ReposOwnerRepoReleasesReleaseIdAttachFiles
        sudo curl -s -X POST \
            -H "Authorization: token $token" \
            -F "file=@\"$file_path\"" \
            -F "name=\"$base_name\"" \
            "${api_prefix}/repos/${repo_owner}/${repo_name}/releases/${release_id}/attach_files"
    }

    common_upload_with_logging \
        "Gitee" \
        "📦 Gitee ReleaseID $release_id" \
        gitee_upload
}

# 产物发布到指定平台 Releases 带 markdown 说明
artifacts_releases_with_platform() {
    log_debug "run artifacts_releases_with_platform"

    # 注意这里的 GITHUB_TOKEN 是在 GitLab CI/CD 的变量中设置的, 或通过环境变量传入
    local repo_owner="$1"         # GitHub 仓库所有者
    local repo_name="$2"          # GitHub 仓库名称
    local tag="$3"                # GitHub Release 的 Tag 名称
    local release_name="$4"       # Release 名称
    local release_body="$5"       # Release 描述
    local platform="${6:-github}" # 平台: github | gitee
    shift 6                       # 剩余参数均为要上传的文件路径

    log_debug "artifacts_releases_with_platform 平台: $platform"

    local file_paths=("$@") # 所有剩余参数视为要上传的文件路径数组

    if [ ${#file_paths[@]} -eq 0 ]; then
        log_error "未指定要上传的文件"
        exit 1
    fi

    # 选择不同平台的 API 前缀
    local git_api_prefix
    local git_token
    if [ "$platform" = "github" ]; then
        git_api_prefix="$GIT_API_PREFIX_GITHUB"
        git_token="$GITHUB_TOKEN"
        log_debug "artifacts_releases_with_platform 使用 GitHub API 前缀: $git_api_prefix"
    elif [ "$platform" = "gitee" ]; then
        git_api_prefix="$GIT_API_PREFIX_GITEE"
        git_token="$GITEE_TOKEN"
        log_debug "artifacts_releases_with_platform 使用 Gitee API 前缀: $git_api_prefix"
    fi

    # 执行上传
    artifacts_releases "$git_api_prefix" "$git_token" "$repo_owner" "$repo_name" "$tag" "$release_name" "$release_body" "$platform" "${file_paths[@]}"
}

# 下载 GitHub Release 资产文件到指定路径
download_github_release_assets() {
    log_debug "run download_github_release_assets"
    local repo_owner="$1" # GitHub 仓库所有者
    local repo_name="$2"  # GitHub 仓库名称
    local tag="$3"        # GitHub Release 的 Tag 名称
    local file_name="$4"  # 文件名
    local path="$5"       # 存放路径

    local download_url="https://github.com/$repo_owner/$repo_name/releases/download/$tag/$file_name"

    sudo wget -c "$download_url" -O "$path/$file_name"
}

# 当 tag 更新时, 同步仓库内容
sync_repo_by_tag() {
    log_debug "run sync_repo_by_tag"
    # 参数:
    # $1: project_dir 项目目录
    # $2: version 版本号
    # $3: git_repo git 仓库地址, 可选参数, 默认使用 GIT_GITHUB
    local project_dir="$1"
    local version="$2"
    local git_repo="${3:-$GIT_GITHUB}"

    # 克隆开发仓库到本地
    git_clone "$project_dir-dev" "$GIT_LOCAL"

    # 如果开发仓库中没有 CHANGELOG.md 文件, 则跳过
    if [ ! -f "$ROOT_DIR/$project_dir-dev/CHANGELOG.md" ]; then
        log_warn "$project_dir-dev 仓库中不存在 CHANGELOG.md 文件, 跳过更新"
        return
    fi

    # 克隆发布仓库到本地, 并进入目录
    git_clone_cd "$project_dir" "$git_repo"

    # 查看当前version标签是否存在
    if sudo git rev-parse --verify "refs/tags/$version" >/dev/null 2>&1; then
        log_warn "Tag '$version' 已存在, 跳过更新 CHANGELOG.md"

        # 返回根目录
        cd "$ROOT_DIR" || exit
        return
    else
        log_info "Tag '$version' 不存在, 继续更新 CHANGELOG.md"
    fi

    # 将开发仓库中的 CHANGELOG.md 复制到发布仓库中
    sudo cp -f "$ROOT_DIR/$project_dir-dev/CHANGELOG.md" "$ROOT_DIR/$project_dir/CHANGELOG.md"
    sudo cp -f "$ROOT_DIR/$project_dir-dev/LICENSE" "$ROOT_DIR/$project_dir/LICENSE"
    sudo cp -f "$ROOT_DIR/$project_dir-dev/README.md" "$ROOT_DIR/$project_dir/README.md"
    log_info "复制 CHANGELOG.md 到 $project_dir 仓库"

    # 进入 blog-server 仓库目录
    cd "$ROOT_DIR/$project_dir" || exit
    log_debug "当前目录 $(pwd)"

    # 判断是否有改动, 有就提交
    if [ "$(git_status_is_clean)" = true ]; then
        log_warn "CHANGELOG.md 无改动, 不需要提交"
    else
        git_add_commit_push "update to $version"
        log_info "更新 $project_dir 仓库的 CHANGELOG.md 完成"
    fi

    # 返回根目录
    cd "$ROOT_DIR" || exit
}

# 产物发布到不同平台 Releases 带 markdown 说明
releases_with_md_platform() {
    log_debug "run releases_with_md_platform"
    # 参数:
    # $1: project 项目名称
    # $2: version 版本号
    # $3: zip_path 产物压缩包路径
    # $4: platform 平台: github | gitee
    local project="$1"
    local version="$2"
    local zip_path="$3"
    local platform="${4:-github}"

    # 根据平台生成 markdown 说明
    local md
    if [ "$platform" = "github" ]; then
        # github 平台 markdown 说明
        md=$(
            cat <<EOL
- 如何使用，请参考 [README.md](https://github.com/jiaopengzi/$project/blob/main/README.md)
- 更新内容，请参考 [CHANGELOG.md](https://github.com/jiaopengzi/$project/blob/main/CHANGELOG.md)
EOL
        )

    elif [ "$platform" = "gitee" ]; then
        # gitee 平台 markdown 说明
        md=$(
            cat <<EOL
- 如何使用，请参考 [README.md](https://gitee.com/jiaopengzi/$project/blob/main/README.md)
- 更新内容，请参考 [CHANGELOG.md](https://gitee.com/jiaopengzi/$project/blob/main/CHANGELOG.md)
EOL
        )

    fi

    # 执行上传
    artifacts_releases_with_platform "$GIT_USER" "$project" "$version" "$version" "$md" "$platform" "$zip_path"
}
