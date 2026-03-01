#!/bin/bash

# MIT License
# 
# Copyright (c) 2025 焦棚子
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Author       : jiaopengzi
# Blog         : https://jiaopengzi.com
# Description  : 博客 sh 工具

set -e

# 当前脚本所在目录绝对路径
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# # 当前脚本所在目录相对路径
# ROOT_DIR="$(dirname "${BASH_SOURCE[0]}")"

### content from config/user.sh
# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

#==============================用户修改的配置 开始==============================
# 域名配置
DOMAIN_NAME=""       # 访问域名, 请确保域名已解析到当前服务器IP地址
PUBLIC_IP_ADDRESS="" # 公网IP地址

# pgsql 数据库配置
POSTGRES_USER="user_blog"     # 数据库用户名
POSTGRES_PASSWORD="123456"    # 数据库用户密码
POSTGRES_DB="blog_server_jpz" # 应用程序数据库名称
POSTGRES_PORT="5432"          # 应用程序数据库名称

# redis 配置
REDIS_BASE_PORT="7002"  # redis 起始端口号
REDIS_PASSWORD="123456" # redis 密码

# es 配置
ES_NODE_COUNT="1"         # 节点数量
ELASTIC_PASSWORD="123456" # 设置 es 的密码, 至少6个字符, 用户名为 elastic
KIBANA_PASSWORD="123456"  # 设置 kibana 的密码, 至少6个字符, 用户名为 kibana_system

# 日志级别：error(1) < warn(2) < info(3) < debug(4), 默认记录info及以上
LOG_LEVEL="debug"

# 日志文件路径, 默认在 blog-tool 根目录下
LOG_FILE="$ROOT_DIR/blog_tool.log"
#==============================用户修改的配置 结束==============================

### content from config/user_billing_center.sh
# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

#==============================用户修改的配置(billing center) 开始==============================
# pgsql 数据库配置(billing center)
POSTGRES_USER_BILLING_CENTER="billing_center"   # 数据库用户名
POSTGRES_PASSWORD_BILLING_CENTER="123456"       # 数据库用户密码
POSTGRES_DB_BILLING_CENTER="billing_center_jpz" # 应用程序数据库名称
POSTGRES_PORT_BILLING_CENTER="5433"             # 应用程序数据库端口

# redis 配置(billing center)
REDIS_BASE_PORT_BILLING_CENTER="8002"  # redis 起始端口号
REDIS_PASSWORD_BILLING_CENTER="123456" # redis 密码

# 日志级别：error(1) < warn(2) < info(3) < debug(4), 默认记录info及以上
LOG_LEVEL="debug"

# 日志文件路径, 默认在 blog-tool 根目录下
LOG_FILE="$ROOT_DIR/blog_tool.log"
#==============================用户修改的配置(billing center) 结束==============================

### content from utils/log.sh
# ANSI颜色定义
RED='\033[0;31m'    # 错误(红)
YELLOW='\033[0;33m' # 警告(黄)
GREEN='\033[0;32m'  # 信息(绿)
BLUE='\033[0;34m'   # 调试(蓝)
NC='\033[0m'        # 重置颜色

# 将日志级别字符串转为数值(用于优先级比较)
get_level_num() {
    local level="$1"
    case "$level" in
    error) echo 1 ;;
    warn) echo 2 ;;
    info) echo 3 ;;
    debug) echo 4 ;;
    *) echo 5 ;; # 无效级别, 默认不记录
    esac
}

# 核心日志函数(不再处理 caller_info, 由调用方传入)
# 参数：$1=日志级别, $2=日志消息, $3=调用者信息(格式如 [file:line])
log() {
    local level="$1"
    local message="$2"
    local caller_info="${3:-}" # 由快捷函数传入(可选)

    # 为了日志一致性, 给消息加上中括号
    message="[$message]"

    # 1. 校验级别有效性
    if ! [[ "error warn info debug" =~ (^| )$level( |$) ]]; then
        echo -e "${RED}[WARN] 无效日志级别: $level, 已转为info${NC}" >&2
        level="info"
        message="无效级别[$level] → 原始消息: $message"
    fi

    # 2. 过滤：当前级别优先级低于全局阈值则跳过
    local current_num global_num
    current_num=$(get_level_num "$level")
    global_num=$(get_level_num "$LOG_LEVEL")
    [ "$current_num" -gt "$global_num" ] && return 0

    # 3. 格式化日志时间与级别
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local level_upper="${level^^}"
    local level_pretty
    level_pretty=$(printf "[%-5s]" "$level_upper") # 如 [ERROR]

    # 4. 终端带颜色输出
    local color
    case "$level" in
    error) color="$RED" ;;
    warn) color="$YELLOW" ;;
    info) color="$GREEN" ;;
    debug) color="$BLUE" ;;
    *) color="" ;;
    esac

    # 构建带颜色的终端输出
    # 屏幕输出: debug 级别显示时间与调用者信息, 其它级别只显示消息主体
    local formatted_msg
    if [ "$LOG_LEVEL" = "debug" ]; then
        if [ -n "$caller_info" ]; then
            formatted_msg="[$timestamp] ${level_pretty} ${caller_info} ${message}"
        else
            formatted_msg="[$timestamp] ${level_pretty} [unknown] ${message}"
        fi
    else
        formatted_msg="${message}"
    fi

    # 在控制台输出日志, >&2 确保输出到 stderr, 不被其他命令捕获
    echo -e "${color}${formatted_msg}${NC}" >&2

    # 5. 同样的内容写入日志文件(无颜色)
    local file_msg
    if [ -n "$caller_info" ]; then
        file_msg="[$timestamp] ${level_pretty} ${caller_info} ${message}"
    else
        file_msg="[$timestamp] ${level_pretty} [unknown] ${message}"
    fi

    # 检查是否是 root 权限运行
    if [ $UID -ne 0 ]; then
        echo -e "${RED}请使用 root 或者 sudo 运行此脚本.${NC}"
        exit 1
    fi

    echo "$file_msg" >>"$LOG_FILE"
}

# **在封装的快捷函数中自动添加调用者信息, 不能在进行封装, 否则行号不准确**
# 使用 BASH_LINENO[0] 获取用户调用 log_xxx() 的行号

log_error() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "error" "$message" "$caller_info"
}

log_warn() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "warn" "$message" "$caller_info"
}

log_info() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "info" "$message" "$caller_info"
}

log_debug() {
    local message="$1"
    local caller_info="[${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}]"
    log "debug" "$message" "$caller_info"
}

# 免责声明信息
disclaimer_msg() {
    # 检查免责声明接受标记文件
    if [ -f "$BLOG_TOOL_ENV/disclaimer_accepted" ]; then
        # 标志文件中只有一行信息, 记录用户接受时间, 读取出来告知用户
        local accept_time
        accept_time=$(grep "用户接受时间:" "$BLOG_TOOL_ENV/disclaimer_accepted" | cut -d' ' -f2-)
        log_debug "您已于 ${accept_time} 接受免责声明，继续使用本工具。"
        return
    fi

    # 显示免责声明内容
    local msg
    msg=$(
        cat <<EOL

===============================================
                    免责声明                                      
===============================================
本工具按原样提供，使用者需自行承担风险。
开发者不对因使用本工具而产生的任何直接或间接损失负责。
===============================================

EOL
    )

    echo -e "${YELLOW}${msg}${NC}" >&2

    # 询问用户是否继续
    read -rp "是否继续使用本工具？(y/n): " choice
    case "$choice" in
    y | Y)
        # 创建配置目录
        if [ ! -d "$BLOG_TOOL_ENV" ]; then
            mkdir -p "$BLOG_TOOL_ENV"
        fi

        # 创建免责声明已接受的标记文件
        sudo touch "$BLOG_TOOL_ENV/disclaimer_accepted" >/dev/null 2>&1

        # 写入用户接受时间
        echo "用户接受时间: $(date +"%Y-%m-%d %H:%M:%S")" >"$BLOG_TOOL_ENV/disclaimer_accepted"
        log_info "您选择继续使用本工具。"
        ;;
    n | N)
        echo "已退出。"
        exit 0
        ;;
    *)
        echo "无效输入，已退出。"
        exit 1
        ;;
    esac
}

show_logo() {
    # 终端logo欢迎界面
    # https://patorjk.com/software/taag/#p=display&f=ANSI+Shadow&t=j+i+a+o+p+e+n+g+z+i&x=none&v=4&h=4&w=80&we=false

    # 打印访问地址
    local msg
    msg=$(
        cat <<EOL

         ██╗    ██╗     █████╗      ██████╗     ██████╗     ███████╗    ███╗   ██╗     ██████╗     ███████╗    ██╗
         ██║    ██║    ██╔══██╗    ██╔═══██╗    ██╔══██╗    ██╔════╝    ████╗  ██║    ██╔════╝     ╚══███╔╝    ██║
         ██║    ██║    ███████║    ██║   ██║    ██████╔╝    █████╗      ██╔██╗ ██║    ██║  ███╗      ███╔╝     ██║
    ██   ██║    ██║    ██╔══██║    ██║   ██║    ██╔═══╝     ██╔══╝      ██║╚██╗██║    ██║   ██║     ███╔╝      ██║
    ╚█████╔╝    ██║    ██║  ██║    ╚██████╔╝    ██║         ███████╗    ██║ ╚████║    ╚██████╔╝    ███████╗    ██║
     ╚════╝     ╚═╝    ╚═╝  ╚═╝     ╚═════╝     ╚═╝         ╚══════╝    ╚═╝  ╚═══╝     ╚═════╝     ╚══════╝    ╚═╝
                                                                                                              
EOL
    )

    msg+="\n    欢迎使用 blog-tool 部署脚本!\n"

    echo -e "${GREEN}${msg}${NC}" >&2
}

PY_BASE64_MAIN='H4sICO43iWkAA21haW4ucHkAzVfrb9NWFP+ev+LIFZINidMUmKZIUdUBm5BgIMYmsSZEbnzzGE5i2U6gAyRehZalTbexMh7bYNB1D1grbaOhj+yfyXXST/wLO9fXsZ02LRXbJPIh8b335Dx/53euB+D9gkZOKlYe8BOHMa2ci1jlshbVx618uRQtKoWSrI+HBmCkghsGABf8rKCUdVLKfV7Ao/fwXwDdo7xl6WY8GvVF5Ey5iGKHyvq4UcjlLUfMX4kZCYYGhw7C2HhAbxhGNA1OMQkTThGTGFWiyqjmMDEzRkG3CuUSquF+QvtBg078QZfn6cTyxoObdHYyFCoU9bJhgWLkdMUwSXdtkFDWKBdBVSxiFYoE3P3uOhQKCYIQak9N2g+f0fpya6XWXlmwH93a+PHb9v0bUFSMc2r5PNp8utJqfvFq7X5oYABGY/J+eTAldqPPFax8ZYxFHkhE1MmvE4oRNYhGFJOYUUvJRasxeVA+KEGEZeJAZPCdyGDMVTskH0ht3a+yg/3/vT3nINbf4KA8GDEtZUwj+4YOxmKxoX5iqFaORcaIpewodACFFE3P7yy1H6WMzI4iQyhSYijRxneUi6GcSqr9ZVjBQyGVZIFcsAwlY6UzeaWUI5i+NOYwc0701zp2SxgwoyYiUIqHGOrx/3Ztqj2x0Gl+TSfmPezY9Vlan9u4+hdt/gqj5wjRQQFPlV89dqJ4+04VJegs3OjUrjPIeSdgz91qrb5oNZ7TxZd05Q43hCL2gz/tuSV6c4L+/pJ+dzfkeDVi5EzuH/v0RgCiaRmFUk6KB7Sjos7yIm3e8P7khhmQ9mILA6Kf/nQNBAeKAgjVwAPDCq9vbGi/wP05RayKUQq4xJXGofP3Hfrg+86im7hgMN30cg0D0FlcxYxuyUhA+Dx2ArAG2FIzwRDCQEqZsopWE0LFykbeFSRQTMgG0lQuWaRkQQKyskEUVZS6plvrf7fv/Gw/f0In73Ue/9xpNulanVfYrt2iv9/3qhHwZgDsO4t27aqbtqnp9toVqII9OddqTNPGT1AV3TQ6yWMHwPMovVqr0ZcvOtfXae3lxgQTth9OgW6QiNvKEIWxSkFTgc7OoNpWY4bWFzeuTG183bRn5hkqHNIKuYXEkNxyyizxuijJGn8Qqp8IXpiutfUf0ak4BFrfK2dKlGW5lzvAnv6mM7PcWp3BKnKzdHKp1fii1UC/fgWB6RFYdLxe9sPf6FKzN1VYJIsYJXTTyApnxYGBpLk3OYpf4nC8OnzRIDIyv6ITEaOQLkujZ5Op1N5kigskRVxLuJakYXnvsCQOJ866Gi4lP5U8/Ng/zNtTTR4jmnfLgh3DjouKlckz+0Q2iWJk8qLrU7gLizA7O3zi9MixY3CJPR/94MMTp44cGvnoCF8f//jY6aPHjn54xMsnB7dnkQccBjqzunHvKQKCFe+Xlfa9dUfecHqEeyLnjHJFF2NSt15QyLo+Eg3LvwNpuYVOs6G2qQ8ClPW/sRPD3tQVhKvHFrR+m068oPUvaeO6fXfefvjDv+ao3XCK/c1Se/VGGDg7B81v3JumK3V75is6eRcxP0Fnf3uty6jn0Ro2fauxAqMiy60/CMKATZF6i+jq7eCdN+STzYQgnA3QQXU4qe5Lyt0v7P7IaPI8Pu9L7ZOGJSaX2kQJuBdhf02qFw9cjuD3kPuNzOB1PjF572cLJVXRtP7N//qG3xlrQXOyiRdP8RwZT2hKcUxV4EIcLozGUswQwxVJnDYqxGfmpZtcH0chrc0xIJ7BT+T48cjhwy46NwU06mFFdLEa9u66jFh09uCAOY0rhN2eM5E9xcgeVXB4J+scBzYlT18W3wd6VDIFUCh1jTuCqdAWXkO3PF7codswWThmkeKQ9dLpklIk6TQkEiCk0+y1JJ0W4t3EPL1Pb61jr9Mv11urTzuPa/xNAK9itP4k7LaCvbxKbz/CywWK93tv4Cpcle1nz/joovVruIuJps9nuXo6/YdrbXa6vbAUdtpg9bkniBOQnzO2dzZdNGNB2RDuvpDIyH2VIuLqpHMiqv6LTUI4ud17jcDzb1bGuEJWYv4kK6qa9veZPishIFsXlZKKVJInmp4QsFXxFsMj8Yc+z812t1/wYg9E4guhB75Zxwv+LHpIEbZR7HnFR1G/UbLparXposu7V+rrluOJ4uZYFHrpFS1b4zpJOJDnPmw2zseMsBvlfqBuP/RR7yEdXOaNb6Xebjivq0pwvPcvTo/Em9QnqEAIe5KvK9duJr+rTtrO3+1y+6YV7E1qZ+GJ/f2szxR+h6LJQDc5P8wNU+SeIg2xlex2lENF2+HaH9AGMSsam8/bvVlynZtmv7PZvVp4utADrs5X76QQbzyWyE98YXZF7CcndLueaLuLqAcJuwqs5/bZJ74dRggbH9vHmBUuutKX4SITv4zB/AMDe6kXxRIAAA=='
### content from config/dev.sh
# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# git 仓库地址前缀
GIT_PREFIX_LOCAL="" # 内网 Git 地址, 通过 check_dev_var 交互式加载
GIT_PREFIX_GITEE="git@gitee.com"
GIT_PREFIX_GITHUB="git@github.com"

# git 用户
GIT_USER="jiaopengzi"

# git
GIT_LOCAL="$GIT_PREFIX_LOCAL:$GIT_USER"
GIT_GITEE="$GIT_PREFIX_GITEE:$GIT_USER"
GIT_GITHUB="$GIT_PREFIX_GITHUB:$GIT_USER"

# 产物上传api前缀
GIT_API_PREFIX_GITHUB="https://api.github.com"
GIT_API_PREFIX_GITEE="https://gitee.com/api/v5"

# 私有仓库配置主要用于开发阶段
REGISTRY_REMOTE_SERVER="" # 远端服务器地址
REGISTRY_USER_NAME=""     # docker registry 用户名
REGISTRY_PASSWORD=""      # 私有仓库密码

# 密码和 token 变量
DOCKER_HUB_REMOTE_SERVER="docker.io" # 远端服务器地址
DOCKER_HUB_TOKEN=""                  # docker hub token
GITHUB_TOKEN=""                      # github token
GITEE_TOKEN=""                       # gitee token

# docker 镜像版本
IMG_VERSION_ALPINE="latest"
IMG_VERSION_GOLANG="1.25.6-alpine"
IMG_VERSION_NODE="22.22.0"
IMG_VERSION_NGINX="1.29.0-alpine"
IMG_VERSION_REGISTRY="3"
IMG_VERSION_HTTPD="2"

HOST_NAME=""    # 默认主机名, 通过 check_dev_var 交互式加载
SSH_PORT=""     # 默认 SSH 端口, 通过 check_dev_var 交互式加载
GATEWAY_IPV4="" # 默认网关, 通过 check_dev_var 交互式加载

# # 系统版本 (默认值, 会被 system/detect.sh 的 init_system_detection 覆盖)
# OLD_SYS_VERSION="bookworm" # Debian 12
# NEW_SYS_VERSION="trixie"   # Debian 13
# NEW_SYS_VERSION_NUM="13"   # Debian 数字版本

### content from config/internal.sh
# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# 运行模式 dev | pro (开发环境 | 生产环境)
RUN_MODE="pro"

# 数据根目录
DATA_VOLUME_DIR="$ROOT_DIR/volume"

# 工具配置目录
BLOG_TOOL_ENV="$DATA_VOLUME_DIR/blog_tool_env"

# 基础依赖软件列表
BASE_SOFTWARE_LIST=(
    sudo
    neovim
    git
    curl
    wget
    unzip
    zip
    tar
    gzip
    ca-certificates
    net-tools
    openvswitch-switch
    openssh-server
    bc
    aptitude
    cron
    jq
    python3
)

# 检测是否安装软件的标志目录
IS_INSTALL_SOFTWARE=""

# Docker CE 镜像源列表
DOCKER_CE_SOURCES=(
    "https://mirrors.aliyun.com/docker-ce|阿里云公网"
    "http://mirrors.cloud.aliyuncs.com|阿里云内网"
    "http://mirrors.aliyuncs.com|阿里云内网经典"
    # "https://mirrors.tencent.com/docker-ce|腾讯云公网"
    # "http://mirrors.tencentyun.com/docker-ce|腾讯云内网"
    "https://mirrors.163.com/docker-ce|网易云"
    "https://mirrors.cernet.edu.cn/docker-ce|中国教育网"
    "https://mirrors.tuna.tsinghua.edu.cn/docker-ce|清华大学"
    "https://mirrors.huaweicloud.com/docker-ce|华为云"
    "https://mirrors.cmecloud.cn/docker-ce|中国移动云"
    # "https://mirrors.volces.com/docker|火山引擎"
    "https://mirror.azure.cn/docker-ce|Azure 中国"
    "https://mirrors.pku.edu.cn/docker-ce|北京大学"
    "https://mirrors.zju.edu.cn/docker-ce|浙江大学"
    "https://mirrors.nju.edu.cn/docker-ce|南京大学"
    "https://mirror.sjtu.edu.cn/docker-ce|上海交通大学"
    "https://mirrors.cqupt.edu.cn/docker-ce|重庆邮电大学"
    "https://mirrors.ustc.edu.cn/docker-ce|中国科学技术大学"
    "https://mirror.iscas.ac.cn/docker-ce|中国科学院"
    "https://download.docker.com|官方源"
)

# docker hub 用户名
DOCKER_HUB_REGISTRY="docker.io" # docker hub 仓库地址
DOCKER_HUB_OWNER="jiaopengzi"   # docker hub 用户名

START_TIME=$(date +%s) # 记录开始时间
APP_NAME="jpz"         # 应用名称 不能包含大写字母和字符
DISPLAY_COLS=3         # 输出显示的列数, 用于输出对齐, 一般为 3, 可以根据实际情况调整

# 检查 ifconfig 是否存在
if command -v ifconfig >/dev/null 2>&1; then
    # 默认内网 IP
    HOST_INTRANET_IP=$(ifconfig | sed -n '/^[eE]/,+3p' | grep 'inet ' | awk '{print $2}')

    # 默认子网掩码
    HOST_INTRANET_MARK=$(ifconfig | sed -n '/^[eE]/,+3p' | grep 'inet ' | awk '{print $4}')
else
    # 如果 ifconfig 不存在, 使用回环地址
    HOST_INTRANET_IP="127.0.0.1"
    HOST_INTRANET_MARK="255.0.0.0"
fi

# 私有 ca 证书存放目录
CA_CERT_DIR="$DATA_VOLUME_DIR/certs_ca"
# 证书有效期(天)
CERT_DAYS_VALID=3650

# docker 镜像版本
IMG_VERSION_REDIS="8.4.0"    # redis 版本
IMG_VERSION_PGSQL="18.1"     # pgsql 版本
IMG_VERSION_PGSQL_MAJOR="18" # pgsql主要版本号

# https://release.infinilabs.com/analysis-ik/stable/elasticsearch-analysis-ik-9.2.4.zip
# 优先查看分词工具是否更新到最新版本, 以分词工具的版本为准, 其他版本保持一致
IMG_VERSION_ES="9.2.4"     # 7.17.28 8.18.1
IMG_VERSION_KIBANA="9.2.4" # 与 es 保持版本一致

# 需要创建的运行用户
JPZ_UID=2025    # 服务端用户
JPZ_GID=2025    # 服务端用户组
DB_UID=999      # 数据库用户 id
DB_GID=999      # 数据库用户组 id
ES_UID=1000     # es 用户 id
ES_GID=0        # es 用户组 id
KIBANA_UID=1000 # kibana 用户 id
KIBANA_GID=0    # kibana 用户组 id
CLIENT_UID=101  # 前端用户 id (nginx)
CLIENT_GID=101  # 前端用户组 id (nginx)
SERVER_UID=2024 # 后端用户 id (Dockerfile自行设置)
SERVER_GID=2024 # 后端用户组 id (Dockerfile自行设置)

# 私有仓库
BRIDGE_REGISTRY="$APP_NAME-registry$IMG_VERSION_REGISTRY-bridge-net" # 私有仓库 网桥
IPV4_BASE_REGISTRY="178.18.10"                                       # 私有仓库 内网起始 IP 段
SUBNET_REGISTRY="$IPV4_BASE_REGISTRY.0/24"                           # 私有仓库 子网网段
GATEWAY_REGISTRY="$IPV4_BASE_REGISTRY.1"                             # 私有仓库 网关

# pgsql docker 参数
BRIDGE_PGSQL="$APP_NAME-pgsql-bridge-net" # pgsql 网桥
IPV4_BASE_PGSQL="178.18.11"               # pgsql 内网起始 IP 段
SUBNET_PGSQL="$IPV4_BASE_PGSQL.0/24"      # pgsql 子网网段
GATEWAY_PGSQL="$IPV4_BASE_PGSQL.1"        # pgsql 网关

# pgsql 数据库 参数
POSTGRES_DOCKER_NAME="pgsql-$IMG_VERSION_PGSQL" # 服务名称

# pgsql ip
IPV4_ADDRESS_START=2
POSTGRES_IP="$IPV4_BASE_PGSQL.$((IPV4_ADDRESS_START % 256))" # 自增 从 2 开始, 1 为网关

# pgsql docker 参数(billing center)
BRIDGE_PGSQL_BILLING_CENTER="$APP_NAME-billing-center-pgsql-bridge-net" # pgsql 网桥
IPV4_BASE_PGSQL_BILLING_CENTER="178.18.12"                              # pgsql 内网起始 IP 段
SUBNET_PGSQL_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.0/24"      # pgsql 子网网段
GATEWAY_PGSQL_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.1"        # pgsql 网关

# pgsql 数据库 参数(billing center)
POSTGRES_DOCKER_NAME_BILLING_CENTER="pgsql-$IMG_VERSION_PGSQL-billing-center" # 服务名称

# pgsql ip(billing center)
POSTGRES_IP_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.$((IPV4_ADDRESS_START % 256))" # 自增 从 2 开始, 1 为网关

# redis docker 参数
MASTER_COUNT=3                            # 主节点数量
SLAVE_COUNT=3                             # 从节点数量
BRIDGE_REDIS="$APP_NAME-redis-bridge-net" # redis 网桥
IPV4_BASE_REDIS="178.18.13"               # redis 内网起始 IP 段
SUBNET_REDIS="$IPV4_BASE_REDIS.0/24"      # redis 子网网段
GATEWAY_REDIS="$IPV4_BASE_REDIS.1"        # redis 网关

# redis 开始和结束 ip
REDIS_START_IP=$IPV4_BASE_REDIS.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
REDIS_END_IP=$IPV4_BASE_REDIS.$(((MASTER_COUNT + SLAVE_COUNT + 1) % 256))

# redis docker 参数(billing center)
BRIDGE_REDIS_BILLING_CENTER="$APP_NAME-redis-billing-center-bridge-net" # redis 网桥
IPV4_BASE_REDIS_BILLING_CENTER="178.18.14"                              # redis 内网起始 IP 段
SUBNET_REDIS_BILLING_CENTER="$IPV4_BASE_REDIS_BILLING_CENTER.0/24"      # redis 子网网段
GATEWAY_REDIS_BILLING_CENTER="$IPV4_BASE_REDIS_BILLING_CENTER.1"        # redis 网关

# redis 开始和结束 ip(billing center)
REDIS_START_IP_BILLING_CENTER=$IPV4_BASE_REDIS_BILLING_CENTER.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
REDIS_END_IP_BILLING_CENTER=$IPV4_BASE_REDIS_BILLING_CENTER.$(((MASTER_COUNT + SLAVE_COUNT + 1) % 256))

# es docker 参数
BRIDGE_ES="$APP_NAME-es-bridge-net" # es 网桥
IPV4_BASE_ES="178.18.15"            # es 内网起始 IP 段
SUBNET_ES="$IPV4_BASE_ES.0/24"      # es 子网网段
GATEWAY_ES="$IPV4_BASE_ES.1"        # es 网关

# es 开始和结束 ip
ES_START_IP=$IPV4_BASE_ES.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
ES_END_IP=$IPV4_BASE_ES.$(((ES_NODE_COUNT + 1) % 256))

# ES 配置
ES_CLUSTER_NAME=docker-cluster # 集群名称
ES_LICENSE=basic               # 设置 es 的许可证, 默认为 basic
ES_PORT=9200                   # es 端口, 如果使用 127.0.0.1:9200 则表示只能本地访问
KIBANA_PORT=5601               # kibana 端口

#============================== Elasticsearch 重要提示 ==============================
# 优先设置 mem_limit 限制内存使用, 而不设置 ES_JAVA_OPTS, 让 ES 自动分配内存使用, 最小值为 1G, 实践中发现至少1.5G 才能稳定运行
# 如果是小内存机器, 通过设置 ES_JAVA_OPTS 限制堆内存大小, 搭配 mem_limit 使用, 确保 mem_limit 大于 ES_JAVA_OPTS 2倍以上
# 同时关注 _cluster/health 的状态值

# 1G = 1024 * 1024 * 1024 = 1073741824
# 1.2G = 1.2 * 1024 * 1024 * 1024 = 1288490188
# 2G = 2 * 1024 * 1024 * 1024 = 2147483648
MEM_LIMIT_ES="mem_limit: 1288490188"     # 内存限制 es (bytes)
MEM_LIMIT_KIBANA="mem_limit: 1073741824" # 内存限制 kibana

# Elasticsearch 堆内存推荐设置参考 (仅供参考, 具体还需根据实际业务场景调整)

# | 服务器总内存   | 推荐 ES 堆内存                                    | 适用场景                          |
# | ------------ | ----------------------------------------------- | ---------------------------------|
# | 2GB          | 256MB ~ 512MB 但极不推荐生产                      | 几乎不可行                         |
# | 4GB          | 512MB ~ 2GB                                     | 小型部署、低并发、测试、预发布环境     |
# | 8GB          | 2GB ~ 4GB                                       | 中小型业务                         |
# | 16GB         | 4GB ~ 8GB                                       | 中等规模业务                       |
# | 32GB         | 8GB ~ 16GB                                      | 中大型业务                         |
# | 64GB+        | 16GB ~ 32GB (不超过 32GB)                        | 大型业务, 多节点分片                |

# 小内存机器设置 es 堆内存大小 (bytes)
ES_JAVA_OPTS_ENV="- ES_JAVA_OPTS=-Xms512m -Xmx512m"
#============================== Elasticsearch 重要提示 ==============================

# server
BRIDGE_SERVER="$APP_NAME-bridge-server" # server 网桥
IPV4_BASE_SERVER="178.18.16"            # SERVER 内网起始 IP 段
SUBNET_SERVER="$IPV4_BASE_SERVER.0/24"  # server 子网网段
GATEWAY_SERVER="$IPV4_BASE_SERVER.1"    # server 网关

# server(billing center)
BRIDGE_BILLING_CENTER="$APP_NAME-bridge-billing-center" # server 网桥
IPV4_BASE_BILLING_CENTER="178.18.17"                    # SERVER 内网起始 IP 段
SUBNET_BILLING_CENTER="$IPV4_BASE_BILLING_CENTER.0/24"  # server 子网网段
GATEWAY_BILLING_CENTER="$IPV4_BASE_BILLING_CENTER.1"    # server 网关

# client
BRIDGE_CLIENT="$APP_NAME-bridge-client"    # client 网桥
IPV4_BASE_CLIENT="178.18.18"               # CLIENT 内网起始 IP 段
SUBNET_CLIENT="$IPV4_BASE_CLIENT.0/24"     # client 子网网段
GATEWAY_CLIENT="$IPV4_BASE_CLIENT.1"       # client 网关
CERTS_NGINX="$DATA_VOLUME_DIR/certs_nginx" # nginx 证书

# docker compose 文件
DOCKER_COMPOS_DIR="$DATA_VOLUME_DIR/docker_compose_files"
DOCKER_COMPOSE_FILE_PGSQL="$DOCKER_COMPOS_DIR/compose-pgsql.yaml"
DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-pgsql-billing-center.yaml"
DOCKER_COMPOSE_FILE_REDIS="$DOCKER_COMPOS_DIR/compose-redis.yaml"
DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-redis-billing-center.yaml"
DOCKER_COMPOSE_FILE_ES="$DOCKER_COMPOS_DIR/compose-es.yaml"
DOCKER_COMPOSE_FILE_SERVER="$DOCKER_COMPOS_DIR/compose-server.yaml"
DOCKER_COMPOSE_FILE_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-billing-center.yaml"
DOCKER_COMPOSE_FILE_CLIENT="$DOCKER_COMPOS_DIR/compose-client.yaml"

# docker compose 项目名称
DOCKER_COMPOSE_PROJECT_NAME_SERVER="$APP_NAME-server"
DOCKER_COMPOSE_PROJECT_NAME_PGSQL="$APP_NAME-pgsql"
DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER="$APP_NAME-pgsql-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_REDIS="$APP_NAME-redis"
DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER="$APP_NAME-redis-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_ES="$APP_NAME-es"
DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER="$APP_NAME-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_CLIENT="$APP_NAME-client"

# 临时文件存放解码后的 python 脚本内容
PY_SCRIPT_FILE="/tmp/embedded_python_main.py"

WEB_INSTALL_SERVER_TIPS="当前需要全新安装 server 服务，会使用初始化覆盖原有配置，是否进行全新安装 \n默认选择n [y|n]? "
WEB_SET_DB_TIPS="\n================================\n是否使用前端网页填写数据库信息?\n\n说明\n  如果自行单独设置数据就选择 y.\n  如果使用当前脚本工具安装了数据就选择 n.\n默认选择n [y|n]? "

### content from options/all.sh
# 当前文件不检测未使用的变量
# shellcheck disable=SC2034

# 定义选项和函数名称, 使用:分割的有序列表
OPTIONS_ALL=(
    # 系统配置
    "新增必要运行用户:add_group_user"
    "设置主机名称:set_hostname"
    "添加 Backports 源:add_backports_apt_source"
    "删除 Backports 源:del_backports_apt_source"
    "安装依赖软件:install_common_software"
    "配置 ssh:set_ssh_config"
    "安装所有更新:install_all_update"
    "系统常规升级:apt_full_upgrade"
    "系统大版本升级:update_apt_source_and_full_upgrade"

    # 网络配置
    "局域网静态 IP 配置:set_host_intranet_ip"

    # SSL 证书
    "生成自定义证书:gen_cert"

    # 安装 docker
    "最快 docker ce 源:find_fastest_docker_mirror"
    "安装 docker:install_docker"
    "手动安装 docker:manual_install_docker"
    "设置 daemon:set_daemon_config"
    "卸载 docker:uninstall_docker"
    "生成自定义证书:gen_cert"

    # 安装 docker
    "最快 docker ce 源:find_fastest_docker_mirror"
    "安装 docker:install_docker"
    "手动安装 docker:manual_install_docker"
    "设置 daemon:set_daemon_config"
    "卸载 docker:uninstall_docker"

    # 拉取镜像
    "拉取开发镜像:pull_docker_image_dev"
    "拉取生产数据库镜像:pull_docker_image_pro_db"
    "拉取生产数据库镜像-计费中心:pull_docker_image_pro_db_billing_center"

    # 私有仓库
    "运行私有分发镜像仓库:docker_run_registry"

    # 安装数据库
    "安装所有数据库:install_database"
    "删除所有数据库:delete_database"
    "全新安装所有数据库:reset_install_database"
    "安装所有数据库-计费中心:install_database_billing_center"
    "删除所有数据库-计费中心:delete_database_billing_center"
    "安装 pgsql:install_db_pgsql"
    "安装 pgsql 计费中心:install_db_pgsql_billing_center"
    "删除 pgsql:delete_db_pgsql"
    "删除 pgsql 计费中心:delete_db_pgsql_billing_center"
    "安装 redis:install_db_redis"
    "安装 redis 计费中心:install_db_redis_billing_center"
    "删除 redis:delete_db_redis"
    "删除 redis 计费中心:delete_db_redis_billing_center"
    "安装 es 和 kibana:install_es_kibana"
    "删除 es 和 kibana:delete_es_kibana"

    # 构建编译过程镜像
    "构建 billing center 镜像:docker_build_billing_center_env"
    "构建 server env 镜像:docker_build_server_env"
    "构建 client env 镜像:docker_build_client_env"

    # 构建并推送结果镜像
    "构建并推送 billing center:docker_build_push_billing_center"
    "构建并推送 server client:docker_build_push_server_client"
    "server 产物复制到本地:server_artifacts_copy_to_local"
    "构建并推送 server:docker_build_push_server"
    "仅构建 server:docker_build_server"
    "仅推送 server:docker_push_server"
    "client 产物复制到本地:client_artifacts_copy_to_local"
    "构建并推送 client:docker_build_push_client"
    "仅推送 client:docker_push_client"

    # 管理文件目录
    "创建 billing center 配置目录:mkdir_billing_center_volume"
    "创建 server 配置目录:mkdir_server_volume"
    "创建 client 配置目录:mkdir_client_volume"
    "创建 server client 配置目录:mkdir_server_client_volume"
    "删除 billing center 配置目录:remove_billing_center_volume"
    "删除 server 配置目录:remove_server_volume"
    "删除 client 配置目录:remove_client_volume"
    "删除 server client 配置目录:remove_server_client_volume"

    # 拉取生产镜像
    "拉取 billing center 镜像:docker_pull_billing_center"
    "拉取 server 镜像:docker_pull_server"
    "拉取 client 镜像:docker_pull_client"
    "拉取 server client 镜像:docker_pull_server_client"

    # 启动服务
    "安装 billing center 服务:docker_billing_center_install"
    "打印计费中心 CA 证书:ca_cert_byte_print"
    "安装 server 服务:docker_server_install"
    "插入测试数据:insert_demo_data"
    "注册管理员:register_admin"
    "重置用户密码:reset_password"
    "安装 client 服务:docker_client_install"
    "安装 server client 服务:docker_server_client_install"

    # 服务管理
    "启动 billing center 服务:docker_billing_center_start"
    "启动 server 服务:docker_server_start"
    "启动 client 服务:docker_client_start"
    "启动 server client 服务:docker_server_client_start"
    "停止 billing center 服务:docker_billing_center_stop"
    "停止 server 服务:docker_server_stop"
    "停止 client 服务:docker_client_stop"
    "停止 server client 服务:docker_server_client_stop"
    "重启 billing center 服务:docker_billing_center_restart"
    "重启 server 服务:docker_server_restart"
    "重启 client 服务:docker_client_restart"
    "重启 server client 服务:docker_server_client_restart"

    # 一键安装
    "一键安装:one_click_install"

    # 全部服务管理
    "停止所有服务(备份|恢复):docker_all_stop"
    "重启所有服务:docker_all_restart"

    # 版本管理
    "查看 server 版本:show_server_versions"
    "查看 client 版本:show_client_versions"
    "升级或回滚 billing center:start_or_rollback_billing_center_by_version"
    "升级或回滚 server:start_or_rollback_server_by_version"
    "升级或回滚 client:start_or_rollback_client_by_version"

    # 删除服务
    "删除 billing center 服务:docker_billing_center_delete"
    "删除 server 服务:docker_server_delete"
    "删除 client 服务:docker_client_delete"
    "删除 server client 服务:docker_server_client_delete"

    # 删除镜像
    "删除 billing center 镜像:docker_rmi_billing_center"
    "删除 server 镜像:docker_rmi_server"
    "删除 client 镜像:docker_rmi_client"
    "删除 server client 镜像:docker_rmi_server_client"

    # 清理 docker
    "清理 docker:docker_clear_cache"

    # 监控日志
    "监控 server 日志:blog_server_logs"
    "监控 billing center 日志:billing_center_logs"

    "退出:exit_script"
)

# 合并数组用户 is_valid_func

# 合并数组用于 is_valid_func

### content from utils/cert.sh
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

### content from utils/check.sh
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

    # 检查密码安全性
    check_password_security

    # 解码 python 脚本内容到临时文件
    decode_py_base64_main
}

### content from utils/db.sh
# 开发阶段重复创建数据库
reset_install_database() {
    log_debug "run reset_install_database"

    echo "y" | install_db_pgsql

    {
        echo "n"
        echo "y"
    } | install_db_redis

    {
        echo "y"
        echo "n"
    } | install_es_kibana
}

# 安装数据库
install_database() {
    log_debug "run install_database"

    local remove_data_pgsql is_redis_cluster remove_data_redis remove_data_es is_kibana
    # 提示用户输入

    # 根据运行模式决定是否询问
    if run_mode_is_dev; then
        remove_data_pgsql=$(read_user_input "[1/5]是否删除 pgsql 数据库信息 (默认n) [y|n]? " "n")
        is_redis_cluster=$(read_user_input "[2/5]是否创建 redis 集群 (默认n) [y|n]? " "n")
        remove_data_redis=$(read_user_input "[3/5]是否删除 redis 数据库信息 (默认n) [y|n]? " "n")
        remove_data_es=$(read_user_input "[4/5]是否删除 es 信息(默认n) [y|n]? " "n")
        is_kibana=$(read_user_input "[5/5]是否包含 kibana (默认n) [y|n]? " "n")
    fi

    if run_mode_is_pro; then
        # 判断是否已经有挂载的数据目录, 只要有一个存在就认为是已有数据
        local pgsql_data_dir="$DATA_VOLUME_DIR/pgsql"
        local redis_data_dir="$DATA_VOLUME_DIR/redis"
        local es_data_dir="$DATA_VOLUME_DIR/es"

        # 默认都有数据
        local has_data=true

        # 所有数据目录都不存在则认为没有数据
        if [ ! -d "$pgsql_data_dir" ] && [ ! -d "$redis_data_dir" ] && [ ! -d "$es_data_dir" ]; then
            has_data=false
        fi

        if [ "$has_data" = true ]; then
            log_warn "检测到已有数据库数据, 请谨慎操作!"
            remove_data_pgsql=$(read_user_input "[1/3]是否删除 pgsql 数据库信息 (默认n) [y|n]? " "n")
            is_redis_cluster="n"
            remove_data_redis=$(read_user_input "[2/3]是否删除 redis 数据库信息 (默认n) [y|n]? " "n")
            remove_data_es=$(read_user_input "[3/3]是否删除 es 信息(默认n) [y|n]? " "n")
            is_kibana="n"
        else
            log_info "未检测到已有数据库数据, 将进行全新安装."
            remove_data_pgsql="y"
            is_redis_cluster="n"
            remove_data_redis="y"
            remove_data_es="y"
            is_kibana="n"
        fi
    fi

    echo "$remove_data_pgsql" | install_db_pgsql

    {
        echo "$is_redis_cluster"
        echo "$remove_data_redis"
    } | install_db_redis

    {
        echo "$remove_data_es"
        echo "$is_kibana"
    } | install_es_kibana
}

# 删除数据库
delete_database() {
    log_debug "run delete_database"

    local is_delete # 是否删除历史数据 默认不删除
    is_delete=$(read_user_input "确认要删除吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        # 删除容器
        echo "$is_delete" | delete_db_pgsql
        echo "$is_delete" | delete_db_redis
        echo "$is_delete" | delete_es_kibana

        log_info "删除数据库成功"
    else
        log_info "未删除数据库"
    fi
}

# 安装数据库(billing center)
install_database_billing_center() {
    log_debug "run install_database_billing_center"
    local remove_data_pgsql is_redis_cluster remove_data_redis
    # 提示用户输入

    # 根据运行模式决定是否询问
    if run_mode_is_dev; then
        remove_data_pgsql=$(read_user_input "[1/3]是否删除 pgsql_billing_center 数据库信息 (默认n) [y|n]? " "n")
        is_redis_cluster=$(read_user_input "[2/3]是否创建 redis_billing_center 集群 (默认n) [y|n]? " "n")
        remove_data_redis=$(read_user_input "[3/3]是否删除 redis_billing_center 数据库信息 (默认n) [y|n]? " "n")
    fi

    if run_mode_is_pro; then
        # 判断是否已经有挂载的数据目录, 只要有一个存在就认为是已有数据
        local pgsql_data_dir="$DATA_VOLUME_DIR/pgsql_billing_center"
        local redis_data_dir="$DATA_VOLUME_DIR/redis_billing_center"

        # 默认都有数据
        local has_data=true

        # 所有数据目录都不存在则认为没有数据
        if [ ! -d "$pgsql_data_dir" ] && [ ! -d "$redis_data_dir" ]; then
            has_data=false
        fi

        if [ "$has_data" = true ]; then
            log_warn "检测到已有数据库数据, 请谨慎操作!"
            remove_data_pgsql=$(read_user_input "[1/2]是否删除 pgsql_billing_center 数据库信息 (默认n) [y|n]? " "n")
            is_redis_cluster="n"
            remove_data_redis=$(read_user_input "[2/2]是否删除 redis_billing_center 数据库信息 (默认n) [y|n]? " "n")
        else
            log_info "未检测到已有数据库数据, 将进行全新安装."
            remove_data_pgsql="y"
            is_redis_cluster="n"
            remove_data_redis="y"
        fi
    fi

    echo "$remove_data_pgsql" | install_db_pgsql_billing_center

    {
        echo "$is_redis_cluster"
        echo "$remove_data_redis"
    } | install_db_redis_billing_center
}

# 删除数据库(billing center)
delete_database_billing_center() {
    log_debug "run delete_database_billing_center"

    local is_delete # 是否删除历史数据 默认不删除
    is_delete=$(read_user_input "确认要删除计费中心数据库吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        # 删除容器
        echo "$is_delete" | delete_db_pgsql_billing_center
        echo "$is_delete" | delete_db_redis_billing_center

        log_info "删除计费中心数据库成功"
    else
        log_info "未删除计费中心数据库"
    fi
}

### content from utils/dir_file.sh
# 为指定目录设置用户、组即权限
# 参数: $1: 用户
# 参数: $2: 组
# 参数: $3: 权限
# 参数: $4: 可变参数, 目录列表
# 用法: setup_directory 2000 2000 750 /path/to/dir1 /path/to/dir2 /path/to/dir3
setup_directory() {
    log_debug "run setup_directory"

    if [ $# -lt 4 ]; then
        echo "Usage: setup_directory <user> <group> <permissions> <dir1> [<dir2> ...]"
        return 1
    fi

    local user=$1
    local group=$2
    local permissions=$3
    shift 3 # 参数左移3位

    for dir_name in "$@"; do
        # 如果目录不存在则创建
        if [ ! -d "$dir_name" ]; then
            sudo mkdir -p "$dir_name" # 创建目录
        fi
        sudo chown -R "$user":"$group" "$dir_name" # 重新设置用户和组
        sudo chmod -R "$permissions" "$dir_name"   # 设置权限
        # sudo chown "$user":"$group" "$dir_name" # 重新设置用户和组(不递归,影响当前目录,不影响子目录和文件)
        # sudo chmod "$permissions" "$dir_name"   # 设置权限(不递归,影响当前目录,不影响子目录和文件)
    done
}

# 覆盖写入并为指定文件设置用户、组即权限
# 参数: $1: 用户
# 参数: $2: 组
# 参数: $3: 权限
# 参数: $4: 内容
# 参数: $5: 文件名
# 用法: over_write_set_owner 2000 2000 600 "content" /path/to/file
over_write_set_owner() {
    log_debug "run over_write_set_owner"

    if [ $# -ne 5 ]; then # 参数个数必须为5
        # 不等于5个参数提示如下
        echo "Usage: over_write_set_owner <user> <group> <permissions> <content> <filePath>"
        return 1
    fi

    local user=$1        # 用户
    local group=$2       # 组
    local permissions=$3 # 权限
    local content=$4     # 内容
    local filePath=$5    # 文件名

    echo "$content" | sudo tee "$filePath" >/dev/null # 写入文件
    sudo chown -R "$user:$group" "$filePath"          # 设置文件用户和组
    sudo chmod -R "$permissions" "$filePath"          # 设置文件权限
}

# 读取目录下的所有文件名到字符串变量中
# 参数: $1: 目录路径
# 用法: read_dir_basename_to_str /path/to/dir
read_dir_basename_to_str() {
    log_debug "run read_dir_basename_to_str"

    local dir_path=$1
    local file_list=""

    if [ -d "$dir_path" ]; then
        for file in "$dir_path"/*; do
            if [ -f "$file" ]; then
                file_name=$(sudo basename "$file")
                file_list+="$file_name "
            fi
        done
    else
        log_error "目录 $dir_path 不存在。"
        return 1
    fi

    echo "$file_list"
}

# 读取目录下的所有文件名为列表
# 参数: $1: 目录路径
# 用法: read_dir_basename_to_list /path/to/dir
read_dir_basename_to_list() {
    log_debug "run read_dir_basename_to_list"

    local dir="$1"
    local files=()
    for f in "$dir"/*; do
        files+=("$(sudo basename "$f")")
    done
    printf "%s\n" "${files[@]}"
}

### content from utils/docker.sh
# 将 SemVer 格式(可能带 +Metadata)转为合法的 Docker tag
# 输入举例：v0.1.5-dev+251116
# 输出举例：v0.1.5-dev-251116
# 用途：生成一个 Docker 兼容的 tag, 同时尽量保留 SemVer 信息
semver_to_docker_tag() {
    log_debug "run semver_to_docker_tag"

    local semver="$1"

    # # 如果有 'v' 去掉开头的 'v'
    # local clean_semver="${semver#v}"

    # # 替换 '+' 为 '-', 因为 Docker tag 不允许 '+'
    # local docker_tag="${clean_semver/\+/-}"

    local docker_tag="${semver/\+/-}"

    log_debug "将原来 SemVer 风格的版本号: '$semver' 转换为 Docker 允许的 Tag: '$docker_tag'"

    echo "$docker_tag"
}

# 镜像打标签并推送到 docker hub
docker_tag_push_docker_hub() {
    log_debug "run docker_tag_push_docker_hub"
    local project=$1
    local version=$2

    # 显示回显 token 的前后3位以确认变量传入正确
    log_debug "token 首尾3位: ${DOCKER_HUB_TOKEN:0:3}...${DOCKER_HUB_TOKEN: -3}"

    # 登录 docker hub
    docker_login_retry "$DOCKER_HUB_REGISTRY" "$DOCKER_HUB_OWNER" "$DOCKER_HUB_TOKEN"

    # 查看当前version标签是否存在
    if sudo docker manifest inspect "$DOCKER_HUB_OWNER/$project:$version" >/dev/null 2>&1; then
        log_warn "Docker Hub 镜像 $DOCKER_HUB_OWNER/$project:$version 已存在, 跳过推送"

        # 避免无法推送, 及时出登录
        sudo docker logout "$DOCKER_HUB_REGISTRY" || true
        return 0
    fi

    # 转换版本号为 Docker tag 兼容格式
    local docker_tag_version
    docker_tag_version=$(semver_to_docker_tag "$version")

    # tag 镜像
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$DOCKER_HUB_OWNER/$project:$docker_tag_version"
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$DOCKER_HUB_OWNER/$project:latest"

    # 推送镜像到 docker hub
    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "$docker_tag_version"

    # 等待 5 秒以确保镜像在 Docker Hub 上可见, 避免推送 latest 失败
    waiting 5

    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "latest"

    # 避免无法推送, 及时出登录
    sudo docker logout "$DOCKER_HUB_REGISTRY" || true
}

# 镜像打标签并推送到私有仓库
docker_tag_push_private_registry() {
    log_debug "run docker_tag_push_private_registry"
    local project=$1
    local version=$2

    # 转换版本号为 Docker tag 兼容格式
    local docker_tag_version
    docker_tag_version=$(semver_to_docker_tag "$version")

    # tag 镜像
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$REGISTRY_REMOTE_SERVER/$project:$docker_tag_version"
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$REGISTRY_REMOTE_SERVER/$project:latest"

    # 显示回显密码的前后3位以确认变量传入正确
    log_debug "密码 首尾3位: ${REGISTRY_PASSWORD:0:3}...${REGISTRY_PASSWORD: -3}"

    # 登录私有仓库
    docker_login_retry "$REGISTRY_REMOTE_SERVER" "$REGISTRY_USER_NAME" "$REGISTRY_PASSWORD"

    # 推送镜像到私有仓库
    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER" "$project" "$docker_tag_version"

    # 等待 5 秒以确保镜像在远端可见, 避免推送 latest 失败
    waiting 5

    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER" "$project" "latest"

    # 避免无法推送,及时出登录
    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
}

# 私有仓库登录执行函数登出
docker_private_registry_login_logout() {
    log_debug "run docker_private_registry_login_logout"

    local run_func="$1"

    # 显示回显密码的前后3位以确认变量传入正确
    log_debug "密码 首尾3位: ${REGISTRY_PASSWORD:0:3}...${REGISTRY_PASSWORD: -3}"

    # 登录私有仓库
    sudo docker login "$REGISTRY_REMOTE_SERVER" -u "$REGISTRY_USER_NAME" --password-stdin <<<"$REGISTRY_PASSWORD"

    # 执行传入的函数
    $run_func

    # 避免无法推送,及时出登录
    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
}

### content from utils/ffmpeg.sh
# 定义变量
DOWNLOAD_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.0-latest-linux64-gpl-8.0.tar.xz" # BtbN 官方最新预编译版下载地址
TEMP_DIR="/tmp/ffmpeg_install"                                                                                          # 临时下载和解压目录
INSTALL_DIR="/usr/local/bin"                                                                                            # 安装目录

# 安装 ffmpeg
install_ffmpeg() {
    log_debug "run install_ffmpeg"
    log_info "开始安装预编译版 FFmpeg(来自 BtbN 官方构建)"
    log_info "下载地址: $DOWNLOAD_URL"
    log_info "安装目录: $INSTALL_DIR"

    # 创建临时目录
    sudo mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    # 下载 FFmpeg 预编译包
    echo "[1/6] 正在下载 FFmpeg 预编译二进制包..."
    sudo wget -O ffmpeg.tar.xz "$DOWNLOAD_URL"

    if [ ! -f "ffmpeg.tar.xz" ]; then
        log_error "下载失败, 请检查网络连接或下载地址是否有效"
        exit 1
    fi

    # 解压
    echo "[2/6] 正在解压 ffmpeg.tar.xz..."
    sudo tar -xvf ffmpeg.tar.xz

    # 通常解压后得到一个文件夹, 如：ffmpeg-n8.0-linux64-gpl
    # 我们查找解压出来的目录(一般包含 ffmpeg 可执行文件)
    FFMPEG_EXTRACTED_DIR=$(sudo find . -type d -name "*linux64-gpl*" | sudo head -n 1)

    if [ -z "$FFMPEG_EXTRACTED_DIR" ]; then
        log_error "未找到解压后的 FFmpeg 目录"
        ls -l
        exit 1
    fi

    echo "[3/6] 解压到的目录: $FFMPEG_EXTRACTED_DIR"

    # 如果目录不存在则创建
    if [ ! -d "$INSTALL_DIR" ]; then
        log_info "创建安装目录: $INSTALL_DIR"
        sudo mkdir -p "$INSTALL_DIR"
    fi

    # 复制 ffmpeg 可执行文件到安装目录
    echo "[4/6] 正在复制 FFmpeg 可执行文件到 $INSTALL_DIR ..."
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffmpeg" "$INSTALL_DIR/"
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffprobe" "$INSTALL_DIR/"
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffplay" "$INSTALL_DIR/"

    echo "[5/6] 赋权并完成安装..."
    # 设置可执行权限(通常已设置, 但再确保一次)
    sudo chmod +x "$INSTALL_DIR/ffmpeg"
    sudo chmod +x "$INSTALL_DIR/ffprobe"
    sudo chmod +x "$INSTALL_DIR/ffplay"

    # 清理临时文件
    echo "[6/6] 清理临时文件..."
    cd /tmp || exit 1
    sudo rm -rf "$TEMP_DIR"

    log_info "FFmpeg 预编译版 安装完成！"
    log_info "📍 FFmpeg 安装位置: $INSTALL_DIR"
    log_info "🔗 全局命令: ffmpeg, ffprobe, ffplay; 可通过以下命令验证：ffmpeg -version | which ffmpeg"
}

# 卸载 ffmpeg
uninstall_ffmpeg() {
    log_debug "run uninstall_ffmpeg"
    log_info "开始卸载 FFmpeg 预编译版..."

    # 删除 ffmpeg 可执行文件
    sudo rm -f "$INSTALL_DIR/ffmpeg"
    sudo rm -f "$INSTALL_DIR/ffprobe"
    sudo rm -f "$INSTALL_DIR/ffplay"

    log_info "FFmpeg 预编译版 已卸载！"
}

### content from utils/git.sh
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

### content from utils/list.sh
# 按照指定前缀和数量生成节点并排除指定节点
# echo $(generate_items_exclude es 1 3) # 输出 es-02,es-03
# echo $(generate_items_exclude es 2 3) # 输出 es-01,es-03
# echo $(generate_items_exclude es 3 3) # 输出 es-01,es-02
generate_items_exclude() {
    log_debug "run generate_items_exclude"

    local prefix=$1        # 前缀
    local exclude_index=$2 # 排除的索引
    local count=$3         # 总的数量
    local result=""

    for ((i = 1; i <= count; i++)); do
        if ((i != exclude_index)); then
            formattedI=$(printf "%02d" $i)
            result+="$prefix-$formattedI,"
        fi
    done

    # 去掉最后一个逗号
    result=${result%,}

    echo "$result"
}

# 按照指定前缀和数量生成所有节点
# echo $(generate_items_al es 3) # 输出 es-01,es-02,es-03
generate_items_all() {
    log_debug "run generate_items_all"
    
    local prefix=$1 # 前缀
    local count=$2  # 总的数量
    local result=""

    for ((i = 1; i <= count; i++)); do
        formattedI=$(printf "%02d" $i)
        result+="$prefix-$formattedI,"
    done

    # 去掉最后一个逗号
    result=${result%,}

    echo "$result"
}

### content from utils/mode_env.sh
# 判断当前运行模式是否为生产环境
run_mode_is_pro() {
    if [ "$RUN_MODE" == "pro" ]; then
        log_debug "run_mode_is_pro: 当前运行模式为生产环境"
        return 0
    else
        log_debug "run_mode_is_pro: 当前运行模式为开发环境"
        return 1
    fi
}

# 判断当前运行模式是否为开发环境
run_mode_is_dev() {
    if run_mode_is_pro; then
        return 1
    else
        return 0
    fi
}

# 获取镜像前缀
get_img_prefix() {
    # 默认镜像前缀
    local img_prefix="$DOCKER_HUB_OWNER"

    # 如果是开发环境就使用私有仓库地址作为前缀
    if run_mode_is_dev; then
        img_prefix="$REGISTRY_REMOTE_SERVER"
    fi

    echo "$img_prefix"
}

# 判断版本是否为生产环境版本
version_is_pro() {
    local version="$1"

    # 根据 version_part 按照语义化版本规范过滤生产环境版本, 即只允许 vX.Y.Z 格式的版本号
    if [[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        log_debug "version_is_pro: $version 符合生产环境版本规范"
        return 0
    else
        log_debug "version_is_pro: $version 不符合生产环境版本规范"
        return 1
    fi
}

version_is_dev() {
    local version="$1"
    if version_is_pro "$version"; then
        return 1
    else
        return 0
    fi
}

# 解析版本号
parsing_version() {
    local version="$1"
    local version_date is_dev

    # 生成时间戳版本(用于 dev 场景)
    version_date=$(date +%y%m%d%H%M)

    # 默认视为开发版本
    is_dev=true

    # 如果符合语义化版本规范(x.y.z), 则视为生产版本
    if version_is_pro "$version"; then
        is_dev=false
        echo "$version" "$is_dev"
        return
    fi

    # 若未指定版本或显式为 "dev", 则使用带时间戳的 dev 版本
    if [[ "$version" == "dev" || -z "$version" ]]; then
        version="dev-$version_date"
    fi

    echo "$version" "$is_dev"
}

### content from utils/network.sh
# 获取 CIDR(子网掩码数字)
# 参数: $1: 子网掩码, 例如: 255.255.255.0
# 返回: CIDR 值, 例如: 24
get_cidr() {
    # 获取子网掩码
    local mask=$1

    # 没有安装 bc 返回默认值 24
    if ! command -v bc >/dev/null 2>&1; then
        echo "24"
        return
    fi

    # 使用点分割得到四个数字
    IFS='.' read -ra ADDR <<<"$mask"

    # 初始化一个空字符串来存储二进制表示
    binary_mask=""

    # 对四个数字使用十进制转为二进制，并拼接起来
    for i in "${ADDR[@]}"; do
        binary_part=$(echo "obase=2; $i" | bc)
        binary_mask+=$binary_part
    done

    # 数一下这字符串中有多少个1就是多少位
    cidr=$(grep -o "1" <<<"$binary_mask" | wc -l)

    # 输出 CIDR 值
    echo "$cidr"
}

# 检查端口是否可用
# 参数: $1: 端口号
# 返回: 0 - 可用, 1 - 被占用
check_port_available() {
    local port=$1
    if lsof -i :"$port" >/dev/null; then
        log_error "端口 $port 被占用"
        return 1 # 端口被占用
    else
        log_info "端口 $port 可用"
        return 0 # 端口可用
    fi
}

# 检查 URL 是否可访问
# 参数: $1: URL 地址
# 返回: 0 - 可访问, 1 - 不可访问
check_url_accessible() {
    local url=$1
    local timeout=$2

    # 设置默认超时时间为 5 秒
    if [[ -z "$timeout" ]]; then
        timeout=5
    fi

    log_debug "正在检查 URL 可访问性: $url (超时: ${timeout}s)"
    # 开始等待动画
    start_spinner

    # 使用 curl 检查 URL 可访问性
    if curl -Is --max-time "$timeout" "$url" >/dev/null; then
        log_debug "URL 可访问: $url"
        stop_spinner
        return 0 # URL 可访问
    else
        log_debug "URL 不可访问: $url"
        stop_spinner
        return 1 # URL 不可访问
    fi
}

### content from utils/one_click_install.sh
# 一键安装 删除数据库
one_click_install() {
    log_debug "run one_click_install"

    local is_install # 是否删除历史数据 默认不删除
    is_install=$(read_user_input "一键安装将会执行如下操作 \
    \n    1.新增必要用户 \
    \n    2.生成自定义证书 \
    \n    3.全新安装 docker (当前机器有业务在 docker 上运行，请慎用！！！)\
    \n    4.拉取镜像\
    \n    5.安装数据库\
    \n    6.安装 server client 服务\
    \n是否进行安装(默认n) [y|n]? " "n")

    if [[ "$is_install" == "y" ]]; then
        log_info "开始执行安装"

        # shellcheck disable=SC2329
        run() {
            add_group_user

            gen_cert

            echo "y" | install_docker

            echo "y" | pull_docker_image_pro_all

            reset_install_database

            {
                echo "y"
                echo "n"
            } | docker_server_client_install
        }

        log_timer "一键安装" run
    else
        log_info "退出安装"
    fi
}

### content from utils/password.sh
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

### content from utils/print.sh
# 设置环境变量
export LC_ALL=C.UTF-8

# 计算中文字符和英文字符数量
count_chars() {
    local text="$1"

    # 匹配中文字符(CJK Unified Ideographs)
    local chn_chars
    chn_chars=$(echo -n "$text" | grep -oP '\p{Han}' | wc -l)

    # 匹配英文字符
    local eng_chars
    eng_chars=$(echo -n "$text" | grep -oP '[a-zA-Z0-9]' | wc -l)

    echo "$chn_chars $eng_chars"
}

# 打印分隔线
print_dividers() {
    local start_delimiter=$1 # 开始分隔符
    local col_length=$2      # 列宽
    local cols=$3            # 列数
    local delimiter=$4       # 分隔符
    local line=''            # 初始化分隔线

    # 构造分隔线
    line+="$start_delimiter"
    for ((c = 0; c < cols; c++)); do
        for ((i = 0; i < col_length; i++)); do
            line+="$delimiter"
        done
        line+="$start_delimiter"
    done

    # 打印分隔线
    printf '%s\n' "$line"
}

# 检查是否为 UTF-8 编码
check_utf8() {
    local locale_output
    locale_output=$(locale | head -n 1)
    local value
    value=$(echo "$locale_output" | cut -d '=' -f 2)
    if echo "$value" | grep -q "UTF-8"; then
        echo true
    else
        echo false
    fi
}

###
# @description: 打印选项, 并添加边框
# @param {int} $1: 显示列数
# @param {array} $2...: 选项数组
###
print_options() {
    local display_cols="$1"
    shift

    local options=("$@")                                      # 选项数组
    local count=${#options[@]}                                # 选项数量
    local rows=$(((count + display_cols - 1) / display_cols)) # 行数
    local cell_width=50                                       # 每个单元格的宽度
    local custom_width=6                                      # 自定义宽度 主要是为了显示序号和空格
    local col_length=$((cell_width + custom_width - 1))       # 列宽

    # 打印表头边框
    print_dividers "+" $col_length "$display_cols" "-"

    # 循环打印选项
    for ((row = 0; row < rows; row++)); do
        printf '|' # 每行开始打印左边框
        for ((col = 0; col < display_cols; col++)); do
            local idx=$((row + rows * col))
            if ((idx < count)); then
                local option="${options[$idx]}"
                local option_name="${option%%:*}" # 提取选项名称
                local chn_count
                read -r chn_count _ <<<"$(count_chars "$option_name")"

                # 如果 check_utf8 为真, 说明是 UTF-8 编码, 不需要计算中文字符数量
                if [ "$(check_utf8)" == true ]; then
                    words=$((cell_width + chn_count))
                else
                    words=$((cell_width + chn_count / 3)) # 一个中文字符占 3 个英文字符的位置 计算补齐占位符数量
                fi

                # 打印选项, 左对齐并填充空格
                printf " %02d " $idx                    # 打印序号
                printf " %-*s|" "$words" "$option_name" # 左对齐内容

                # 使用 + 填充字符串
                # printf -v filled "%-*s" 24 "$option_name"
                # printf -v filled "%-*s" $repeat "$option_name"
                # filled="${filled// /+}"
                # echo -n "$filled"
            else
                # 空单元格 减 1 是为了补齐边框 右边框 |
                printf '%*s|' $col_length ""
            fi
        done
        # 在每行之后打印分隔线, 除了最后一行
        echo
        if [ "$row" -lt "$((rows - 1))" ]; then
            print_dividers "+" $col_length "$display_cols" "-"
        fi
    done

    # 打印表尾边框
    print_dividers "+" $col_length "$display_cols" "-"
    echo
}

# 退出脚本
exit_script() {
    # 脚本退出时删除临时文件
    rm -f "${PY_SCRIPT_FILE}"

    log_info "退出脚本"

    exit 0
}

# 判断函数名称是否在 options 数组中, 用于检查用户输入是否有效
is_valid_func() {
    local options=("${!1}")
    local func_name="$2"
    for option in "${options[@]}"; do
        IFS=":" read -r _ function_name <<<"$option"
        if [ "$func_name" == "$function_name" ]; then
            echo "$function_name"
            return 0
        fi
    done
    return 1
}

# 执行函数
exec_func() {
    local func="$1"
    if declare -f "$func" >/dev/null; then
        $func
    else
        log_error "找不到对应的函数：$func"
        exit 1
    fi
}

###
# @description: 获取用户输入并执行相应的函数
# @param {array} $1: 选项数组
###
handle_user_input() {
    local options=("$@")
    # 读取用户输入
    read -r -p "请输入工具所在的序号[0-$((${#options[@]} - 1))] 或者直接输入函数名称: " raw_choice
    # 检查输入是否为数字
    if [[ $raw_choice =~ ^0*[0-9]+$ ]]; then
        # 十进制去除前导零并转换为整数
        choice=$(printf "%d\n" $((10#$raw_choice)) 2>/dev/null)
        # 检查用户输入是否在有效范围内
        if ((choice < 0 || choice >= ${#options[@]})); then
            echo "请输入正确的选项序号"
            exit 1
        fi
        # 查找对应的函数名
        option="${options[$choice]}"
        func_name="${option##*:}" # 提取函数名称
    else
        # 输入不是数字, 尝试匹配函数名称
        func_name=""

        for option in "${options[@]}"; do
            if [[ "${option##*:}" == "$raw_choice" ]]; then
                func_name="$raw_choice"
                break
            fi
        done
        if [[ -z "$func_name" ]]; then
            echo "未找到与输入匹配的函数名称"
            exit 1
        fi

    fi
    # 执行对应的函数
    exec_func "$func_name"
}

# 函数：读取用户输入, 返回标准化的结果
# 参数：
#   1. prompt_text - 提示文本
#   2. default_value - 默认值
# 返回: 用户输入的值(标准化为小写)
read_user_input() {
    local prompt_text=$1
    local default_value=$2
    local user_input=""

    # 预处理提示文本，将 \n 替换为实际换行
    # 使用 bash 的字符串替换功能
    local formatted_prompt="${prompt_text//\\n/$'\n'}"

    # 使用 read -p 与格式化后的提示文本
    read -r -p "$formatted_prompt" user_input

    # 如果用户没有输入, 使用默认值
    if [ -z "$user_input" ]; then
        user_input=$default_value
    fi

    # 将输入转换为小写
    user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

    # 返回用户输入
    echo "$user_input"
}

### content from utils/python_embed.sh
# # 解码并解压嵌入的 Python 脚本写入指定目录
# base64_decode_py_scripts_to_dir() {
#     local output_dir="./python"

#     # 判断输出目录是否存在, 不存在则创建
#     if [ ! -d "$output_dir" ]; then
#         mkdir -p "$output_dir"
#     fi

#     # 历遍当前脚本文件中的所有嵌入的 python 脚本变量
#     grep -oP '^py_base64_\K[^(=]+' "$0" | while read -r py_file_name; do
#         log_debug "正在解码并解压脚本: $py_file_name"
#         var_name="py_base64_${py_file_name}"

#         # 解码并解压到临时文件, 注意 !var_name 为变量名取值
#         echo "${!var_name}" | base64 -d | gzip -d >"$output_dir/$py_file_name.py"
#     done
# }

# 解码并解压指定嵌入的 Python 脚本变量内容
decode_py_base64_main() {
    log_debug "run decode_py_base64_main"
    # 读取变量 PY_BASE64_MAIN 解码并解压, 保存到文件
    echo "${PY_BASE64_MAIN}" | base64 -d | gzip -d >"${PY_SCRIPT_FILE}"
}

# 提取 changelog 中指定版本的变更日志块
extract_changelog_block() {
    log_debug "run extract_changelog_block"

    # $1: changelog 文件路径
    # $2: 版本号
    local changelog_file="$1"
    local changelog_version="$2"

    # 可选：检查文件是否成功写入
    if [[ ! -s "${PY_SCRIPT_FILE}" ]]; then
        log_error "解码后的 Python 脚本文件为空或不存在"
        exit 1
    fi

    log_debug "解码后的 Python 脚本文件已创建: ${PY_SCRIPT_FILE}"

    python3 "${PY_SCRIPT_FILE}" extract_changelog_block "$changelog_file" "$changelog_version"
}

# 提取 changelog 中指定版本的发布日期
extract_changelog_version_date() {
    log_debug "run extract_changelog_version_date"

    # $1: changelog 文件路径
    local changelog_file="$1"

    # 可选：检查文件是否成功写入
    if [[ ! -s "${PY_SCRIPT_FILE}" ]]; then
        log_error "解码后的 Python 脚本文件为空或不存在"
        exit 1
    fi

    log_debug "解码后的 Python 脚本文件已创建: ${PY_SCRIPT_FILE}"

    python3 "${PY_SCRIPT_FILE}" extract_changelog_version_date "$changelog_file"
}

### content from utils/registry.sh
# 创建自定义镜像仓库用于分发镜像
docker_run_registry() {
  log_debug "run docker_run_registry"

  # 回到脚本所在目录
  cd "$ROOT_DIR" || exit

  # 如果有 registry 文件夹就删除
  if [ -d "$ROOT_DIR/registry" ]; then
    cd "$ROOT_DIR/registry" || exit
    # 停止并删除容器
    # 判断是会否有 docker-compose.yaml 文件
    if [ -f "$ROOT_DIR/registry/docker-compose.yaml" ]; then
      sudo docker compose down || true
    fi

    cd "$ROOT_DIR" || exit

    # 删除 registry 文件夹
    sudo rm -rf "$ROOT_DIR/registry"
  fi

  docker_run_registry_new
}

# 创建 registry 仓库
docker_run_registry_new() {
  log_debug "run docker_run_registry_new"

  # 创建 registry 目录
  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry"

  # 如果当前目录下 certs_nginx 文件夹不存在则输出提示
  if [ ! -d "$CERTS_NGINX" ]; then
    echo "========================================"
    echo "    请将证书 $CERTS_NGINX 文件夹放到当前目录"
    echo "    证书文件夹结构如下:"
    echo "    $CERTS_NGINX"
    echo "    ├── cert.key"
    echo "    └── cert.pem"
    echo "========================================"
    log_error "缺少 $CERTS_NGINX 证书目录, 无法继续创建 registry 镜像仓库"
    exit 1
  fi

  # 复制 certs_nginx 文件夹到 registry 目录下
  cp -r "$CERTS_NGINX" "$ROOT_DIR/registry/certs_nginx"

  # 进入 ./registry
  cd "$ROOT_DIR/registry" || exit

  # 打印当前目录
  log_debug "当前目录 $(pwd)"

  # 创建用户
  # mkdir auth # 创建存放用户密码文件夹
  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry/auth"
  sudo docker run --entrypoint htpasswd httpd:"$IMG_VERSION_HTTPD" -Bbn "$REGISTRY_USER_NAME" "$REGISTRY_PASSWORD" | sudo tee "$ROOT_DIR/registry/auth/htpasswd" >/dev/null # 创建用户密码文件

  # 删除 httpd 临时容器
  sudo docker ps -a | grep httpd:"$IMG_VERSION_HTTPD" | awk '{print $1}' | xargs sudo docker rm -f

  # mkdir data # 创建存放镜像数据文件夹
  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry/data"

  #  创建新的 docker-compose.yaml 文件
  cat >>"$ROOT_DIR/registry/docker-compose.yaml" <<-EOM
# 默认文件名 docker-compose.yml 使用命令 sudo docker compose up -d

services:
  registry:
    restart: always
    container_name: 'registry$IMG_VERSION_REGISTRY'
    image: 'registry:$IMG_VERSION_REGISTRY'
    user: '$JPZ_UID:$JPZ_UID'
    ports:
      - 5000:5000
      # - 443:443
    environment:
      # REGISTRY_HTTP_ADDR: 0.0.0.0:443 # 443 可以自定义指定容器内部开放端口
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/cert.pem # 证书 pem 容器内部路径
      REGISTRY_HTTP_TLS_KEY: /certs/cert.key # 证书 key 容器内部路径
      REGISTRY_AUTH: htpasswd # 认证方式
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd # 认证文件路径
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm # 认证域
      REGISTRY_LOG_LEVEL: "warn" # 将日志级别设为 warning 及以上
      REGISTRY_TRACING_ENABLED: "false" # 是否启用追踪
      REGISTRY_TRACING_ENDPOINT: "" # 追踪端点
      OTEL_TRACES_EXPORTER: "none" # 禁用 OpenTelemetry traces 导出
      OTEL_EXPORTER_OTLP_ENDPOINT: "" # 清空默认 OTLP endpoint 避免尝试连接 localhost:4318
    volumes:
      - $ROOT_DIR/registry/data:/var/lib/registry # 数据存储路径
      - $ROOT_DIR/registry/certs_nginx:/certs # 证书存储路径
      - $ROOT_DIR/registry/auth:/auth # 认证文件存储路径
    networks: # 网络配置
      $BRIDGE_REGISTRY: # 网络名称

networks: # 网络配置
  $BRIDGE_REGISTRY: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_REGISTRY # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_REGISTRY" # 子网
          gateway: "$GATEWAY_REGISTRY" # 网关
EOM

  # 启动服务
  sudo docker compose up -d

  # 登录私有仓库
  sudo docker login "$REGISTRY_REMOTE_SERVER" -u "$REGISTRY_USER_NAME" --password-stdin <<<"$REGISTRY_PASSWORD"
}

### content from utils/retry.sh
# 通用的带指数退避的重试机制
retry_with_backoff() {
    # 参数说明:
    #   $1: run_func                # 执行的函数
    #   $2: max_retries             # 最大重试次数(默认5)
    #   $3: initial_delay           # 初始延迟秒数(默认2)
    #   $4: success_msg             # 成功时的日志信息
    #   $5: error_msg_prefix        # 错误前缀(用于非重试错误)
    #   $6: retry_on_pattern        # 仅当输出匹配此正则时才重试(否则立即失败)
    local run_func="$1"
    local max_retries=${2:-5}
    local delay=${3:-2}
    local success_msg="$4"
    local error_msg_prefix="$5"
    local retry_on_pattern="$6"

    local attempt=1
    local output
    local status

    # 动画开始
    start_spinner

    while true; do
        # 写人临时文件以捕获输出
        local tmpfile
        tmpfile=$(mktemp) || {
            stop_spinner
            log_error "创建临时文件失败"
            return 1
        }

        # 执行函数, 同时显示输出并捕获
        if "$run_func" >"$tmpfile" 2>&1; then
            # 先停止动画
            stop_spinner

            # 将记录的输出显示到终端
            cat "$tmpfile"
            rm -f "$tmpfile"

            # 打印日志
            log_info "$success_msg"
            return 0
        else
            status=$?

            # 记录失败时的输出
            output=$(cat "$tmpfile")

            # 检查是否应重试: 要么无 pattern(总是重试), 要么匹配 pattern
            if [ -z "$retry_on_pattern" ] || echo "$output" | grep -Eiq "$retry_on_pattern"; then
                if [ "$attempt" -ge "$max_retries" ]; then
                    stop_spinner
                    log_error "达到最大重试次数($max_retries), 操作仍失败。输出: $output"
                    return 1
                fi

                log_warn "第 ${attempt}/${max_retries} 次重试, ${delay}s 后重试。退出码: $status"
                sleep "$delay"
                attempt=$((attempt + 1))
                delay=$((delay * 2))
            else
                # 非重试类错误, 立即失败
                stop_spinner
                log_error "${error_msg_prefix}: $output"
                return 1
            fi
        fi
    done
}

# docker 登录重试
docker_login_retry() {

    log_debug "run docker_login_retry"
    # 参数
    # $1: registry_server 仓库地址
    # $2: username 用户名
    # $3: password 密码
    local registry_server="$1"
    local username="$2"
    local password="$3"

    log_info "正在登录 docker 仓库: $registry_server"

    # shellcheck disable=SC2329
    run() {
        sudo docker login "$registry_server" -u "$username" --password-stdin <<<"$password"
    }

    retry_with_backoff \
        "run" \
        5 \
        2 \
        "登录仓库 $registry_server 成功" \
        "登录仓库失败(非重试类错误)" \
        "" # 登录失败通常重试, 不设 pattern
}

# 带超时的 docker push 重试
timeout_retry_docker_push() {
    log_debug "run timeout_retry_docker_push"
    # 参数
    # $1: registry_server_or_user 私有仓库地址 或 docker hub 用户名
    # $2: project 项目名称
    # $3: version 版本号
    local registry_server_or_user="$1"
    local project=$2
    local version=$3

    local image="$registry_server_or_user/$project:$version"

    log_info "准备推送镜像: $image"

    # shellcheck disable=SC2329
    run() {
        log_debug "执行的命令: sudo docker push $image"
        sudo docker push "$image"
    }

    retry_with_backoff \
        "run" \
        5 \
        2 \
        "推送 $image 成功" \
        "docker push 失败(非 TLS/连接类错误)" \
        "TLS handshake timeout|tls: handshake|tls handshake|x509: certificate|certificate signed by unknown authority|connection reset by peer|connection refused"
}

# 带超时的 docker pull 重试
timeout_retry_docker_pull() {
    log_debug "run timeout_retry_docker_pull"
    # 参数
    # $1: image_name 项目名称
    # $2: version 版本号
    local image_name=$1
    local version=$2

    # 默认使用官方仓库
    local image="$image_name:$version"

    log_info "开始拉取镜像: $image"

    # shellcheck disable=SC2329
    run() {
        log_debug "执行的命令: sudo docker pull $image"
        sudo docker pull "$image"
    }

    retry_with_backoff \
        "run" \
        5 \
        2 \
        "拉取 $image 成功" \
        "docker pull 失败(非 TLS/连接类错误)" \
        "TLS handshake timeout|tls: handshake|tls handshake|x509: certificate|certificate signed by unknown authority|connection reset by peer|connection refused"
}

### content from utils/server_client.sh
# 删除 server client 镜像
docker_rmi_server_client() {
    log_debug "run docker_rmi_server_client"
    docker_rmi_server
    docker_rmi_client
    docker_clear_cache
}

# 创建 sever 和 client 的 volume
mkdir_server_client_volume() {
    log_debug "run mkdir_server_client_volume"
    mkdir_server_volume
    mkdir_client_volume
}

# 删除 sever 和 client 的 volume
remove_server_client_volume() {
    log_debug "run remove_server_client_volume"
    remove_server_volume
    remove_client_volume
}

# 拉取 server client 镜像
docker_pull_server_client() {
    log_debug "run docker_pull_server_client"
    docker_pull_server
    docker_pull_client
}

# 构建 server client 推送镜像及启动服务
docker_build_push_start_server_client() {
    log_debug "run docker_build_push_start_server_client"
    docker_build_push_server_client
    docker_server_client_install
}

# 构建 server client 推送镜像
docker_build_push_server_client() {
    log_debug "run docker_build_push_server_client"

    # shellcheck disable=SC2329
    run() {
        docker_build_push_server
        docker_build_push_client
    }
    log_timer "server client 镜像构建及推送" run
}

# 安装 server client 服务
docker_server_client_install() {
    log_debug "run docker_server_client_install"
    local is_install
    is_install=$(read_user_input "$WEB_INSTALL_SERVER_TIPS" "n")

    # 是否全新安装 server
    if [ "$is_install" == "y" ]; then
        local web_set_db
        web_set_db=$(read_user_input "$WEB_SET_DB_TIPS" "n")
        log_debug "web_set_db=$web_set_db"

        # 传递参数给 docker_server_install
        {
            echo "$is_install"
            echo "$web_set_db"
        } | docker_server_install

        docker_client_install
    else
        log_info "退出全新安装"
    fi
}

# 启动 server client 服务
docker_server_client_start() {
    log_debug "run docker_server_client_start"
    docker_server_start
    docker_client_start
}

# 停止 server client 服务
docker_server_client_stop() {
    log_debug "run docker_server_client_stop"
    docker_server_stop
    docker_client_stop
}

# 重启 server client 服务
docker_server_client_restart() {
    log_debug "run docker_server_client_restart"
    docker_server_restart
    docker_client_restart
}

# 删除 server client 服务及数据
docker_server_client_delete() {
    log_debug "run docker_server_client_delete"
    docker_server_delete
    docker_client_delete
}

# 停止所有服务
docker_all_stop() {
    log_debug "run docker_all_stop"
    docker_client_stop
    docker_server_stop
    stop_db_es
    stop_db_redis
    stop_db_pgsql
}

# 重启所有服务
docker_all_restart() {
    log_debug "run docker_all_restart"
    restart_db_pgsql
    restart_db_redis
    restart_db_es
    docker_server_restart
    docker_client_restart
}

# 获取项目文件的 raw 文件 URL
get_raw() {
    log_debug "run get_raw"
    # 参数:
    # $1: project 项目名称
    # $2: file 文件名称
    # $3: platform 平台: github | gitee, 可选参数, 默认 github
    local project="$1"
    local file="$2"
    local platform="${3:-github}"

    # 根据平台生成 raw 文件 URL
    local raw_url
    if [ "$platform" = "github" ]; then
        raw_url="https://raw.githubusercontent.com/jiaopengzi/$project/refs/heads/main/$file"
    elif [ "$platform" = "gitee" ]; then
        raw_url="https://gitee.com/jiaopengzi/$project/raw/main/$file"
    fi

    echo "$raw_url"
}

# 获取指定服务的版本列表
get_service_versions() {
    log_debug "run get_service_versions"
    # 参数:
    # $1: service_name 服务名称
    local service_name="${1-blog-client}"

    # 脚本下载地址根据网络环境选择
    local raw_url

    # 检测网络环境开启动画
    start_spinner

    if [[ $(curl -s ipinfo.io/country) == "CN" ]]; then
        log_debug "检测到国内网络环境, 使用 gitee 获取 $service_name 版本"
        raw_url=$(get_raw "$service_name" "CHANGELOG.md" "gitee")
    else
        log_debug "检测到非国内网络环境, 使用 github 获取 $service_name 版本"
        raw_url=$(get_raw "$service_name" "CHANGELOG.md" "github")
    fi

    # 将 changelog 文件下载到本地临时文件
    local changelog_temp_file
    changelog_temp_file=$(mktemp)
    curl -sSL "$raw_url" -o "$changelog_temp_file"

    # 上述网络操作完成停止动画
    stop_spinner

    extract_changelog_version_date "$changelog_temp_file"
}

# 展示指定服务的版本列表
show_service_versions() {
    log_debug "run show_service_versions"
    # 参数:
    # $1: service_name 服务名称
    local service_name="${1-blog-client}"

    # 获取版本列表
    local versions
    versions=$(get_service_versions "$service_name")

    # 使用 semver_to_docker_tag 将版本号转换为 Docker 标签格式
    local formatted_versions=""
    local has_versions=false
    while IFS= read -r line; do
        local date_part version_part formatted_version
        version_part=$(echo "$line" | awk '{print $1}')
        date_part=$(echo "$line" | awk '{print $2}')

        formatted_version="$date_part\t$(semver_to_docker_tag "$version_part")"

        # 根据 version_part 按照语义化版本规范过滤生产环境版本, 即只显示 x.y.z 格式的版本
        if run_mode_is_pro; then
            # 判断版本是否为生产环境版本
            if (version_is_pro "$version_part"); then
                formatted_versions+="$formatted_version\n"
                has_versions=true
            fi
        else
            formatted_versions+="$formatted_version\n"
            has_versions=true
        fi

    done <<<"$versions"

    # 如果没有可用版本则提示并退出
    if [ "$has_versions" = false ]; then
        log_warn "服务 $service_name 暂无可用版本列表"
        exit 0
    fi

    # 将显示的版本信息进行美化中间间隔增加制表符,增加表头
    formatted_versions=$(echo -e "发布日期\t版本号\n$formatted_versions" | column -t)

    log_info "\n\n服务 $service_name 可用版本列表如下:\n\n$formatted_versions\n"
}

# 展示 server 版本列表
show_server_versions() {
    log_debug "run show_server_versions"
    show_service_versions "blog-server"
}

# 展示 client 版本列表
show_client_versions() {
    log_debug "run show_client_versions"
    show_service_versions "blog-client"
}

# 检查指定服务的版本是否存在
check_service_version() {
    log_debug "run check_service_version"
    # 参数:
    # $1: service_name 服务名称
    # $2: version 版本号
    local service_name="${1-blog-server}"
    local version="$2"

    # 获取所有版本列表
    local versions
    versions=$(get_service_versions "$service_name")

    # 检查指定版本是否存在
    local version_exists=false

    # 遍历版本列表进行检查
    while IFS= read -r line; do
        # 提取版本号部分
        local v
        v=$(echo "$line" | awk '{print $1}')

        # 使用 semver_to_docker_tag 将版本号转换为 Docker 标签格式
        local formatted_v
        formatted_v=$(semver_to_docker_tag "$v")

        # 比较转换后的版本号与指定版本号
        if [[ "$formatted_v" == "$version" ]]; then
            version_exists=true
            break
        fi
    done <<<"$versions"

    # 如果版本不存在则报错退出
    if [ "$version_exists" = false ]; then
        log_error "服务 $service_name 未找到版本 $version, 请检查后重试"
        exit 1
    fi

    # 根据 version_part 按照语义化版本规范过滤生产环境版本, 即只允许 x.y.z 格式的版本
    if run_mode_is_pro && (version_is_dev "$version"); then
        log_error "当前运行模式为生产环境, 版本 $version 不符合生产环境版本规范, 请检查后重试"
        exit 1
    fi

    # 版本存在则继续启动或回滚服务
    log_info "服务 $service_name 找到版本 $version"
}

# 根据版本启动或回滚 server 服务
start_or_rollback_server_by_version() {
    log_debug "run start_or_rollback_server_by_version"

    # 读取用户输入的版本号
    read -r -p "请输入 server 需要升级或回滚的版本号: " version

    # 如果用户没有输入, 使用默认值
    if [ -z "$version" ]; then
        log_error "版本号不能为空, 请重新运行脚本并输入正确的版本号"
    fi

    # 检查版本是否存在
    check_service_version "blog-server" "$version"

    # 拉取镜像
    docker_pull_server "$version"

    # 停止容器
    docker_server_stop

    # 按照指定版本创建 docker compose 文件
    create_docker_compose_server "$version"

    # 不删除数据卷重启服务
    docker_server_restart

    log_info "服务 blog-server 已成功升级或回滚到版本 $version"
}

# 根据版本启动或回滚 client 服务
start_or_rollback_client_by_version() {
    log_debug "run start_or_rollback_client_by_version"

    # 读取用户输入的版本号
    read -r -p "请输入 client 需要升级或回滚的版本号: " version

    # 如果用户没有输入, 使用默认值
    if [ -z "$version" ]; then
        log_error "版本号不能为空, 请重新运行脚本并输入正确的版本号"
    fi

    # 检查版本是否存在
    check_service_version "blog-client" "$version"

    # 拉取镜像
    docker_pull_client "$version"

    # 停止容器
    docker_client_stop

    # 按照指定版本创建 docker compose 文件
    create_docker_compose_client "$version"

    # 不删除数据卷重启服务
    docker_client_restart

    log_info "服务 blog-client 已成功升级或回滚到版本 $version"
}

### content from utils/sys.sh
## CPU 逻辑核心数 (lscpu 的 CPU(s) 字段)
get_cpu_logical() {
    grep -c '^processor[[:space:]]*:' /proc/cpuinfo
}

# 获取内存总大小 (GB, 精确到小数点后 2 位)
get_mem_gb() {
    awk '/^MemTotal:/ {printf "%.2f\n", $2/1024/1024}' /proc/meminfo
}

# 判断内存是否大于 n GB
is_mem_greater_than() {
    # 参数:
    # $1 - 内存阈值 (GB)
    local mem_gb
    mem_gb=$(get_mem_gb)

    log_debug "当前内存: ${mem_gb}GB, 阈值: ${1}GB"

    local threshold=$1
    awk -v mem="$mem_gb" -v thresh="$threshold" 'BEGIN {exit (mem > thresh) ? 0 : 1}'
}

### content from utils/time.sh
# 记录执行时间
# 参数: $1: 事件名称
# 参数: $2: 需要执行的函数
# 参数: $3: 开始时间, 可以不传, 则取当前时间
log_timer() {
    local event run_func start_time end_time time_elapsed hours minutes seconds
    event=$1
    run_func=$2
    start_time=${3:-$(date +%s)}

    log_debug "开始执行: ${event}, 开始时间: $(date -d "@$start_time" +"%Y-%m-%d %H:%M:%S")"

    # 执行传入的函数
    $run_func

    end_time=$(date +%s)
    time_elapsed=$((end_time - start_time))
    hours=$((time_elapsed / 3600))
    minutes=$(((time_elapsed / 60) % 60))
    seconds=$((time_elapsed % 60))
    log_info "${event}共计用时: ${hours}时${minutes}分${seconds}秒"
}

### content from utils/waiting.sh
# 内部变量：存储等待动画的后台进程ID
__spinner_pid=""

# 开始等待动画
start_spinner() {
    # 如果动画已经在运行, 直接返回
    if [ -n "$__spinner_pid" ]; then
        return
    fi

    # 等待动画帧(固定宽度, 圆点在条内来回移动)
    local spinner_frames=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

    # 当前帧索引
    local spin_index=0

    # 显示等待动画
    show_spinner() {
        while true; do
            printf "\r%s  " "${spinner_frames[$spin_index]}" >&2
            spin_index=$(((spin_index + 1) % ${#spinner_frames[@]}))
            sleep 0.2
        done
    }

    # 启动等待动画作为后台进程
    show_spinner &
    __spinner_pid=$!
}

# 停止等待动画
stop_spinner() {
    if [ -n "$__spinner_pid" ]; then
        # 检查进程是否仍在运行
        if kill -0 "$__spinner_pid" 2>/dev/null; then
            # 忽略错误防止脚本退出
            kill "$__spinner_pid" 2>/dev/null || true # kill 进程, 忽略错误防止脚本退出
            wait "$__spinner_pid" 2>/dev/null || true # 等待进程退出, 忽略错误防止脚本退出
        fi

        printf "\r  \r" >&2 # 清除残留帧
        __spinner_pid=""    # 清空PID以避免再次停止
    fi
}

# 等待指定的持续时间并显示等待动画
# 参数: 持续时间(秒)
waiting() {
    local duration=$1

    # 如果没有指定持续时间, 直接返回
    if [[ -z "$duration" || "$duration" -le 0 ]]; then
        return
    fi

    # 开始等待动画
    start_spinner

    # 等待指定的持续时间
    sleep "$duration"

    # 停止等待动画
    stop_spinner
}

# 等待文件完成
wait_file_write_complete() {
    log_debug "run wait_file_write_complete"

    log_warn "等待文件写入完成, 这可能需要几分钟时间... 请勿中断！"

    # 参数:
    # $1: run_func 用于触发文件写入的函数
    # $2: file_path 文件路径
    # $3: timeout 超时时间(秒), 可选参数, 默认 300 秒
    local run_func="$1"
    local file_path="$2"
    local timeout=${3:-300}

    # 记录开始时间
    local start_time
    start_time=$(date +%s)

    # 开始等待动画
    start_spinner

    # 执行传入的函数
    $run_func

    # 循环检查文件是否存在
    until sudo [ -f "$file_path" ]; do
        sleep 1

        # 检查是否超时
        local current_time
        current_time=$(date +%s)

        # 计算经过的时间
        local elapsed_time=$((current_time - start_time))

        # 如果超过超时时间就报错退出
        if [ "$elapsed_time" -ge "$timeout" ]; then
            # 停止等待动画
            stop_spinner

            log_error "等待文件写入完成超时, 已超过 $timeout 秒, 请检查相关日志"
            exit 1
        fi
    done

    # 停止等待动画
    stop_spinner

    log_debug "文件 $file_path 写入完成."
}

### content from utils/yaml.sh
# update_yaml_block 更新 YAML 文件中指定的 `key: |` 多行字符串块内容
# 用法：update_yaml_block "yaml文件路径" "yaml_key_line" "新内容文本文件路径"
#   - yaml_key_line: 如 "key: |" (必须与 YAML 文件中完全一致, 包括缩进！)
#   - 新内容文本文件路径：每行内容会被自动加上与 key: | 相同的缩进
update_yaml_block() {
    local YAML_FILE="$1"
    local YAML_KEY_LINE="$2"
    local NEW_CONTENT_FILE="$3"

    # ===== 检查传入参数是否为空 =====
    if [[ -z "$YAML_FILE" || -z "$YAML_KEY_LINE" || -z "$NEW_CONTENT_FILE" ]]; then
        echo "❌ 错误：请提供 YAML 文件路径、YAML key 行(如 'key: |')、以及新内容文件路径"
        echo "   用法: update_yaml_block \"yaml文件路径\" \"yaml_key_line\" \"新内容文件路径\""
        return 1
    fi

    # ===== 检查文件是否存在 (使用 sudo) =====
    if ! sudo test -f "$YAML_FILE"; then
        echo "❌ 错误：YAML 文件不存在: $YAML_FILE"
        return 1
    fi

    if ! sudo test -f "$NEW_CONTENT_FILE"; then
        echo "❌ 错误：新内容文件不存在: $NEW_CONTENT_FILE"
        return 1
    fi

    # ===== 查找 `key: |` 所在行 =====
    local KEY_LINE_NUM
    KEY_LINE_NUM=$(sudo grep -n "^${YAML_KEY_LINE}$" "$YAML_FILE" | sudo cut -d: -f1)

    if [[ -z "$KEY_LINE_NUM" ]]; then
        echo "❌ 错误：未找到 YAML key 行: '$YAML_KEY_LINE', 请确认格式与文件中完全一致(包括缩进！)"
        return 1
    fi

    # echo "✅ 找到目标 key 行: '$YAML_KEY_LINE', 位于第 $KEY_LINE_NUM 行"

    # ===== 获取块内容起始行 =====
    local BLOCK_START_LINE=$((KEY_LINE_NUM + 1))
    local TOTAL_LINES
    TOTAL_LINES=$(sudo cat "$YAML_FILE" | wc -l | awk '{print $1}')

    if [[ $BLOCK_START_LINE -gt $TOTAL_LINES ]]; then
        echo "❌ 错误：未找到 YAML key 行: '$YAML_KEY_LINE'的下一行不存在, 可能格式错)"
        return 1
    fi

    # 获取块起始行内容, 用于计算缩进
    local BLOCK_START_LINE_CONTENT
    BLOCK_START_LINE_CONTENT=$(sudo sed -n "${BLOCK_START_LINE}p" "$YAML_FILE")

    # 计算缩进(连续的空格)
    local INDENT=""
    local i char
    for ((i = 0; i < ${#BLOCK_START_LINE_CONTENT}; i++)); do
        char="${BLOCK_START_LINE_CONTENT:$i:1}"
        if [[ "$char" == " " ]]; then
            INDENT="${INDENT}${char}"
        else
            break
        fi
    done

    # local INDENT_LEN=${#INDENT}
    # echo "✅ 检测到缩进(来自块内容起始行): 共 $INDENT_LEN 个空格"

    # ===== 为新块内容的每一行添加缩进 =====
    local NEW_CONTENT_RAW
    NEW_CONTENT_RAW=$(sudo cat "$NEW_CONTENT_FILE" 2>/dev/null)

    if [[ -z "$NEW_CONTENT_RAW" ]]; then
        echo "❌ 错误：无法读取新内容文件 '$NEW_CONTENT_FILE'，请检查文件权限"
        return 1
    fi

    # ===== 为每一行添加缩进 =====
    local FORMATTED_BLOCK=""
    while IFS= read -r line; do
        FORMATTED_BLOCK+="${INDENT}${line}"$'\n'
    done <<<"$NEW_CONTENT_RAW"

    # ===== 使用 awk 进行精准替换, 仅替换匹配缩进的 key 块 =====
    local TMP_FILE
    TMP_FILE=$(sudo mktemp)

    if sudo awk -v start_line="$BLOCK_START_LINE" \
        -v indent="$INDENT" \
        -v new_cert="$FORMATTED_BLOCK" \
        '
    BEGIN {
        in_cert_block = 0
        replaced = 0
    }

    NR < start_line {
        print
    }

    NR == start_line {
        # 检查此行是否有我们预期的缩进, 以确认是目标块内容起始行
        current_indent = ""
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == " ") {
                current_indent = current_indent c
            } else {
                break
            }
        }
        if (current_indent == indent) {
            # 是目标缩进, 进行替换
            print new_cert
            in_cert_block = 1
            replaced = 1
        } else {
            # 缩进不对, 原样输出, 不替换
            print
        }
    }

    NR > start_line {
        if (in_cert_block == 1) {
            # 检查是否还处于同一缩进块内
            current_indent = ""
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == " ") {
                    current_indent = current_indent c
                } else {
                    break
                }
            }
            if (current_indent == indent) {
                # 仍是缩进块内, 已被新块内容替代, 所以这里不打印
                # 即跳过原 YAML 中的这些行
            } else {
                # 缩进已改变, 内容块结束, 恢复打印
                in_cert_block = 0
                print $0
            }
        } else {
            # 不在块中, 正常打印
            print $0
        }
    }
    ' "$YAML_FILE" | sudo tee "$TMP_FILE" >/dev/null; then
        # 备份原文件
        sudo cp "$YAML_FILE" "${YAML_FILE}.bak"
        # 替换原文件
        sudo mv "$TMP_FILE" "$YAML_FILE"
        echo "✅ 成功更新 YAML 文件中到 YAML key 行: '$YAML_KEY_LINE' 的多行字符串块内容"
        echo "📂 原文件已备份为: ${YAML_FILE}.bak"
    else
        echo "❌ 替换失败"
        sudo rm -f "$TMP_FILE"
        return 1
    fi
}

# update_yaml_block "/home/jiaopengzi/test/es.yaml" "ca_cert: |" "/home/jiaopengzi/cert_ca_es/ca.crt"

### content from system/apt.sh
# 执行 apt update
apt_update() {
    log_debug "run apt_update"

    if command -v sudo >/dev/null 2>&1; then
        sudo apt update
    else
        apt update
    fi
}

# 执行安装并设置同意
apt_install_y() {
    log_debug "run apt_install_y"

    sudo apt install -y "$@"
}

# 添加 backports 源
add_backports_apt_source() {
    log_debug "run add_backports_apt_source"

    local sources_list="/etc/apt/sources.list"

    # 文件存在就删除原来的配置
    if [ -f "$sources_list" ]; then
        sudo sed -i '/# Backports 仓库开始/,/# Backports 仓库结束/d' "$sources_list"
    fi

    #    # 添加 backports 仓库
    #    {
    #        echo "# Backports 仓库开始"
    #        get_backports_source
    #        echo "# Backports 仓库结束"
    #    } | sudo tee -a "$sources_list"

    apt_update
}

# 删除 backports 源
del_backports_apt_source() {
    log_debug "run del_backports_apt_source"

    local sources_list="/etc/apt/sources.list"
    # 文件存在就删除原来的配置
    if [ -f "$sources_list" ]; then
        sudo sed -i '/# Backports 仓库开始/,/# Backports 仓库结束/d' "$sources_list"
    fi

    apt_update
}

# 安装所有更新
install_all_update() {
    log_debug "run install_all_update"

    # 更新
    apt_update

    # 安装工具
    install_common_software
    # 安装docker
    install_docker

    log_info "所有更新完成"
}

### content from system/detect.sh
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

### content from system/software.sh
# 安装常用软件
install_common_software() {
    log_debug "run install_common_software"

    # 安装常用软件
    apt_update

    # 无代理直接更新
    if command -v sudo >/dev/null 2>&1; then
        sudo apt install -y "${BASE_SOFTWARE_LIST[@]}"
    else
        apt install -y "${BASE_SOFTWARE_LIST[@]}"
    fi

    # 设置历史记录大小
    if ! grep -q "export HISTSIZE=*" "$HOME/.bashrc"; then
        # 如果不存在则添加
        echo 'export HISTSIZE=5000' | tee -a "$HOME/.bashrc"
    fi

    # 设置历史文件大小
    if ! grep -q "export HISTFILESIZE=*" "$HOME/.bashrc"; then
        # 如果不存在则添加
        echo 'export HISTFILESIZE=5000' | tee -a "$HOME/.bashrc"
    fi

    # log_info "常用软件安装完成, 重启中..."
    # /usr/sbin/reboot
}

### content from system/ssh.sh
# 设置 ssh 配置
set_ssh_config() {
    log_debug "run set_ssh_config"

    # 如果没有 ./id_rsa.pub 文件需要提示用户生成
    if [ ! -f "$ROOT_DIR/id_rsa.pub" ]; then
        log_error "缺少 SSH 公钥文件: $ROOT_DIR/id_rsa.pub"
        exit 1
    fi

    # 读取同目录下的 id_rsa.pub 文件内容
    pub_key=$(cat "$ROOT_DIR/id_rsa.pub")
    authorized_keys=$HOME/.ssh/authorized_keys
    # 设置 SSH 配置
    sshd_config=/etc/ssh/sshd_config

    # 向服务器添加 ssh 公钥

    mkdir -p "$HOME/.ssh"
    touch "$authorized_keys"
    chmod 600 "$authorized_keys"
    # 将公钥添加到 authorized_keys 文件中
    echo "$pub_key" | sudo tee -a "$authorized_keys" >/dev/null

    # 备份原始的 SSH 配置文件
    sudo cp $sshd_config{,.bak}

    # update_ssh_config 函数 更新ssh配置
    update_ssh_config() {
        local key=$1
        local value=$2

        # 更新 /etc/ssh/sshd_config
        if grep -q -E "^(#)?$key" $sshd_config; then
            # 如果存在，将其设置为给定的值
            sudo sed -i "s/^\(#\)\?$key.*/$key $value/g" $sshd_config
        else
            # 如果不存在，添加一行
            echo "$key $value" | sudo tee -a $sshd_config >/dev/null
        fi

    }

    # 更新SSH配置
    # root账户登录
    update_ssh_config "PermitRootLogin" "yes"

    # 不使用密码登录
    update_ssh_config "PasswordAuthentication" "no"

    # 使用密钥对登录
    update_ssh_config "PubkeyAuthentication" "yes"

    # 修改ssh端口
    update_ssh_config "Port" "$SSH_PORT"

    # 禁用PAM
    update_ssh_config "UsePAM" "yes"

    # 重启 SSH 服务以使新的配置生效
    sudo systemctl restart sshd
    log_info "SSH 配置已更新"
    log_info "SSH 端口已修改为 $SSH_PORT"
    log_debug "请使用 cat $authorized_keys 查看文件是否存在公钥 "
}

### content from system/sys.sh
# 设置主机名称
set_hostname() {
    log_debug "run set_hostname"

    # 读取用户输入
    printf "\n请输入新的主机名(默认:%s): $HOST_NAME"
    read -r input1

    if [[ -n "$input1" ]]; then
        HOST_NAME="$input1"
    fi

    sudo hostnamectl set-hostname "$HOST_NAME"

    log_info "主机名已设置为 $HOST_NAME ，请重新连接"
}

# 设置内网静态ip
set_host_intranet_ip() {
    log_debug "run set_host_intranet_ip"

    # 确认是否设置内网静态ip
    input1=$(read_user_input "设置静态ip需要重新连接,是否设置内网静态ip (默认n) [y|n]? " "n")

    if [[ "$input1" == "y" ]]; then
        # 读取用户输入
        printf "\nIP默认:%s,回车表示使用默认值" "$HOST_INTRANET_IP"
        printf "\n请输入本机的内网IP地址:"
        read -r input2

        # 读取用户输入
        printf "\n网关默认:%s,回车表示使用默认值 $GATEWAY_IPV4"
        printf "\n请输入本机的网关地址:"
        read -r input3

        if [[ -n "$input2" ]]; then
            HOST_INTRANET_IP="$input2"
        fi

        if [[ -n "$input3" ]]; then
            GATEWAY_IPV4="$input3"
        fi

        # 配置文件路径
        FILE="/etc/network/interfaces"

        # 新的网络配置
        read -r -d '' NEW_CONFIG <<EOM
iface INTERFACE_NAME inet static
    address $HOST_INTRANET_IP
    netmask 255.255.0.0
    gateway $GATEWAY_IPV4
    dns-nameservers $GATEWAY_IPV4 223.5.5.5 8.8.8.8
EOM

        # 获取网卡名称
        INTERFACE_NAME=$(awk '/allow-hotplug/ {print $2}' $FILE)

        # 替换 INTERFACE_NAME
        NEW_CONFIG=${NEW_CONFIG//INTERFACE_NAME/$INTERFACE_NAME}

        # 使用 awk 替换原始配置
        awk -v r="$NEW_CONFIG" "{gsub(/iface $INTERFACE_NAME inet dhcp/,r)}1" $FILE >temp && sudo mv temp $FILE

        # 重启网络服务
        sudo /etc/init.d/networking restart
    fi
}

### content from system/upgrade.sh
# apt 全量升级
apt_full_upgrade() {
    log_debug "run apt_full_upgrade"

    sudo apt update
    sudo apt full-upgrade -y

    # 清理现场
    sudo apt autoclean
    sudo apt autoremove -y

    # 查看当前系统版本
    log_debug "当前系统版本信息:"
    lsb_release -a
    cat /etc/debian_version
}

# 更新 apt 源从 bookworm(12) 到 trixie(13)
update_apt_source() {
    log_debug "run update_apt_source"

    local sources_list="/etc/apt/sources.list"
    local sources_list_d="/etc/apt/sources.list.d"

    # 文件存在就删除原来的配置
    if [ -f "$sources_list" ]; then
        # 先备份在替换
        sudo cp "$sources_list" "$sources_list.bak_$(date +%Y%m%d%H%M%S)"
        sudo cp -r "$sources_list_d" "$sources_list_d.bak_$(date +%Y%m%d%H%M%S)"

        # 打印备份信息
        log_info "备份 sources.list 到 $sources_list.bak_$(date +%Y%m%d%H%M%S)"
        log_info "备份 sources.list.d 到 $sources_list_d.bak_$(date +%Y%m%d%H%M%S)"

        sudo sed -i "s/$OLD_SYS_VERSION/$NEW_SYS_VERSION/g" "$sources_list"
        # 替换所有 .list 文件中的内容
        sudo find /etc/apt/sources.list.d/ -name "*.list" -exec sed -i "s/$OLD_SYS_VERSION/$NEW_SYS_VERSION/g" {} \;
    fi
}

# 更新 apt 源并执行全量升级
update_apt_source_and_full_upgrade() {
    log_debug "run update_apt_source_and_full_upgrade"

    # 用户确认
    log_warn "请确保您已经备份了重要数据, 升级过程中可能会出现不可预知的问题."
    read -r -p "您确定要将系统从 $OLD_SYS_VERSION 升级到 $NEW_SYS_VERSION 吗? (y/n): " confirm
    if [[ $confirm != "y" ]]; then
        log_info "用户取消升级"
        return
    fi

    log_info "开始更新 apt 源从 $OLD_SYS_VERSION 到 $NEW_SYS_VERSION"
    update_apt_source

    log_info "更新 apt 源完成, 开始执行 apt 全量升级"

    apt_full_upgrade
    log_info "apt 全量升级完成"
}

### content from system/user.sh
# 新建不登录用户和用户组
create_user_and_group_nologin() {
    log_debug "run create_user_and_group_nologin"

    local uid=$1  # 用户 id
    local gid=$2  # 用户组 id
    local name=$3 # 用户名 和 用户组名 相同

    # 检查用户组是否存在
    if ! getent group "$gid" >/dev/null; then
        # 如果用户组不存在, 创建新的用户组
        sudo groupadd -g "$gid" "$name"
        log_info "创建不登录用户组: $name, gid: $gid"
    else
        log_warn "用户组 gid:$gid 已经存在"
    fi

    # 检查用户是否存在
    if ! id -u "$uid" >/dev/null 2>&1; then
        # 如果用户不存在, 创建新的用户
        sudo useradd -r -M -u "$uid" -g "$gid" "$name"
        sudo usermod -s /sbin/nologin "$name"

        log_info "创建不登录用户: $name, uid: $uid"
    else
        log_warn "用户 uid:$uid 已经存在"
    fi
}

# 新增用户和用户组
add_group_user() {
    log_debug "run add_group_user"

    # 创建用户任务运行的用户和组不需要登录
    create_user_and_group_nologin "$DB_UID" "$DB_GID" "$APP_NAME-database"
    create_user_and_group_nologin "$CLIENT_UID" "$CLIENT_GID" "$APP_NAME-client"
    create_user_and_group_nologin "$SERVER_GID" "$SERVER_GID" "$APP_NAME-server"
    create_user_and_group_nologin "$JPZ_UID" "$JPZ_GID" "$APP_NAME-project"

    # # 创建登录用户

    # # 检查用户组是否存在
    # if ! getent group "$SERVER_GID" >/dev/null; then
    #     # 如果用户组不存在，创建新的用户组
    #     sudo groupadd -g "$SERVER_GID" "$BLOG_USER_GROUP" # 新增用户组
    # else
    #     log_warn "gid:$SERVER_GID 已经存在."
    # fi

    # # 检查用户是否存在
    # if ! id -u "$SERVER_UID" >/dev/null 2>&1; then
    #     # 如果用户不存在, 创建新的用户
    #     sudo useradd -m -u "$SERVER_UID" -g "$SERVER_GID" "$BLOG_USER" # 新增用户 -m 创建家目录 -u 指定用户 id -g 指定用户组 id
    #     sudo usermod -aG sudo "$BLOG_USER"                             # 添加到 sudo 组
    #     sudo chsh -s /bin/bash "$BLOG_USER"                            # 设置默认 shell 为 bash
    #     echo "$BLOG_USER:<your-password>" | sudo chpasswd               # 设置默认密码
    #     sudo getent passwd "$BLOG_USER"                                # 查看新增用户

    #     # 打印提示信息
    #     log_info "用户 $BLOG_USER 已创建,并添加到 sudo 组."
    #     log_info "初始密码: <your-password>"
    #     log_warn "请及时登录并修改用户 $BLOG_USER 的初始密码."
    # else
    #     log_warn "uid:$SERVER_UID 已经存在."
    # fi
}

### content from docker/clear.sh
# 清理容器、镜像、网络、构建缓存
docker_clear_cache() {
    log_debug "run docker_clear_cache"

    # 删除无用的镜像、容器、网络、构建缓存
    sudo docker container prune -f # 删除所有停止状态的容器
    sudo docker network prune -f   # 删除所有不使用的网络
    sudo docker image prune -f     # 删除所有不使用的镜像
    sudo docker builder prune -f   # 删除所有不使用的构建缓存

    # 删除标签为 <none> 的镜像
    sudo docker images | grep "<none>" | awk '{print $3}' | xargs sudo docker rmi -f || true
}

### content from docker/daemon.sh
# 设置 docker daemon 配置
set_daemon_config() {
    log_debug "run set_daemon_config"

    local target_dir="/etc/docker"
    local target_file="/etc/docker/daemon.json"
    local validate_cmd="sudo dockerd --validate --config-file"

    # 检查并备份
    if [ ! -f "$target_file" ]; then
        log_debug "docker daemon 配置文件不存在, 创建新文件"
        sudo mkdir -p "$target_dir"
        echo '{}' | sudo tee "$target_file" >/dev/null
    else
        log_debug "docker daemon 配置文件已存在, 进行备份"
        sudo cp "$target_file" "${target_file}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # 使用 heredoc 创建配置文件
    local tmp_file="$target_file.tmp"

    # 创建基础配置
    # 共用的 daemon 配置部分
    # live-restore: 启用后即使 docker 守护进程崩溃, 容器也会继续运行
    # log-driver: 设置日志驱动为 json-file
    # log-opts: 配置日志选项, 最大大小 100MB, 最多保留 7 个文件, 并添加 production 标签
    cat >"$tmp_file" <<'EOF'
{
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "7",
    "labels": "production"
  }
EOF

    # 根据网络环境添加镜像加速
    if [[ $(curl -s --max-time 5 ipinfo.io/country) == "CN" ]]; then
        log_debug "检测到国内网络环境, 使用国内镜像加速"
        cat >>"$tmp_file" <<'EOF'
  ,
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
EOF
    fi

    # 关闭 JSON
    cat >>"$tmp_file" <<'EOF'
}
EOF

    # 验证配置
    if $validate_cmd "$tmp_file" >/dev/null 2>&1; then
        log_debug "docker 日志配置语法验证通过"
    else
        log_error "docker 日志配置语法验证失败, 请检查 $tmp_file 文件"
        log_error "文件内容:"
        sudo cat "$tmp_file"
        sudo rm -f "$tmp_file"
        return 1
    fi

    # 应用配置
    sudo mv "$tmp_file" "$target_file"

    log_info "docker 正在重启..."
    sudo systemctl restart docker 2>/dev/null || sudo service docker restart 2>/dev/null

    # log_info "当前 docker daemon 配置内容如下:"
    # if command -v jq >/dev/null 2>&1 && sudo jq '.' "$target_file" 2>/dev/null; then
    #     log_debug "docker daemon 配置文件内容已成功格式化显示"
    #     # jq 格式化成功
    #     :
    # else
    #     # 回退到直接显示
    #     log_warn "无法使用 jq 格式化显示 docker daemon 配置文件内容，直接输出原始内容"
    #     sudo cat "$target_file"
    # fi

    log_info "如果您需要修改配置, 请编辑 $target_file 文件并重启 docker 服务"
}

### content from docker/images.sh
# 拉取开发环境镜像
pull_docker_image_dev() {
    log_debug "run pull_docker_image_dev"

    # 拉取必要的docker镜像

    timeout_retry_docker_pull "alpine" "$IMG_VERSION_ALPINE"
    timeout_retry_docker_pull "golang" "$IMG_VERSION_GOLANG"
    timeout_retry_docker_pull "node" "$IMG_VERSION_NODE"
    timeout_retry_docker_pull "redis" "$IMG_VERSION_REDIS"
    timeout_retry_docker_pull "postgres" "$IMG_VERSION_PGSQL"
    timeout_retry_docker_pull "elasticsearch" "$IMG_VERSION_ES"
    timeout_retry_docker_pull "kibana" "$IMG_VERSION_KIBANA"
    timeout_retry_docker_pull "nginx" "$IMG_VERSION_NGINX"
    timeout_retry_docker_pull "registry" "$IMG_VERSION_REGISTRY"
    timeout_retry_docker_pull "httpd" "$IMG_VERSION_HTTPD"

    log_info "docker 开发环境镜像拉取完成"
}

# 拉取生产环境db镜像
pull_docker_image_pro_db() {
    log_debug "run pull_docker_image_pro_db"

    # 拉取必要的docker镜像

    timeout_retry_docker_pull "redis" "$IMG_VERSION_REDIS"
    timeout_retry_docker_pull "postgres" "$IMG_VERSION_PGSQL"
    timeout_retry_docker_pull "elasticsearch" "$IMG_VERSION_ES"

    log_info "docker 生产环境数据库镜像拉取完成"
}

# 拉取生产环境db镜像
pull_docker_image_pro_db_billing_center() {
    log_debug "run pull_docker_image_pro_db_billing_center"

    # 拉取必要的docker镜像

    timeout_retry_docker_pull "redis" "$IMG_VERSION_REDIS"
    timeout_retry_docker_pull "postgres" "$IMG_VERSION_PGSQL"

    log_info "docker 生产环境数据库镜像拉取完成"
}

# 拉取生产环境所有镜像
pull_docker_image_pro_all() {
    log_debug "run pull_docker_image_pro_all"

    local has_db
    has_db=$(read_user_input "是否包含数据库镜像 pgsql redis es (默认y) [y|n]? " "y")

    if [[ "$has_db" == "y" ]]; then
        pull_docker_image_pro_db
    fi

    docker_pull_server
    docker_pull_client
}

### content from docker/install.sh
# 执行 docker 安装和配置
__install_docker() {
    log_debug "run __install_docker"

    # 是否为手动安装, 默认否
    local is_manual_install="${1-n}"

    # 先执行备份，同时避免镜像源不一致导致的问题
    docker_install_backup

    # 脚本下载地址
    local script_url="https://get.docker.com"

    local script_file="./install-docker.sh"

    # 下载脚本
    # shellcheck disable=SC2329
    run() {
        # sudo curl -fsSL --retry 5 --retry-delay 3 --connect-timeout 5 --max-time 10 "$script_url" -o "$script_file"
        log_debug "下载命令: sudo curl -fsSL --connect-timeout 5 --max-time 10 $script_url -o $script_file"
        sudo curl -fsSL --connect-timeout 5 --max-time 10 "$script_url" -o "$script_file"
    }

    # 手动重试下载脚本，最多重试 5 次, 初始延迟 2 秒
    if ! retry_with_backoff "run" 5 2 "docker 安装脚本下载成功" "docker 安装脚本下载失败" ""; then
        log_error "下载 docker 安装脚本失败, 请检查网络连接"
        exit 1
    fi

    # 获取最快的 Docker CE 镜像源
    local fastest_docker_mirror
    # 如果是手动安装，则不使用镜像源加速
    if [[ "$is_manual_install" == "y" ]]; then
        fastest_docker_mirror=$(manual_select_docker_source)
    else
        fastest_docker_mirror=$(find_fastest_docker_mirror)
    fi

    # 将 DEFAULT_DOWNLOAD_URL="https://download.docker.com" 替换为最快的镜像源
    if [[ -n "$fastest_docker_mirror" ]]; then
        log_info "使用最快的 Docker CE 镜像源: $fastest_docker_mirror"

        # 替换下载地址
        sudo sed -i "s|DOWNLOAD_URL=\"https://mirrors.aliyun.com/docker-ce\"|DOWNLOAD_URL=\"$fastest_docker_mirror\"|g" "$script_file"

        # 将所有字符串 Aliyun 替换为 MyFastMirror
        sudo sed -i "s|Aliyun|MyFastMirror|g" "$script_file"
    else
        log_warn "未找到可用的 Docker CE 镜像源, 将使用默认官方源进行安装，可能会因为网络问题导致安装失败"
    fi

    # 给脚本执行权限
    sudo chmod +x "$script_file"

    log_info "正在安装 docker, 请耐心等待..."

    # 执行安装脚本并记录日志
    if sudo bash "$script_file" --mirror MyFastMirror 2>&1 | tee -a ./install.log; then
        log_info "docker 安装脚本执行完成"

        # 进一步验证 docker 是否真的安装成功
        if command -v docker &>/dev/null && docker --version &>/dev/null; then
            log_info "docker 安装验证成功，docker 命令可用"
        else
            log_error "docker 命令不可用，安装失败，请检查安装日志"
            return 1
        fi
    else
        log_error "docker 安装失败"
        return 1
    fi

    log_info "docker 安装完成, 开始设置 docker daemon 配置"

    # 设置 docker 日志配置
    set_daemon_config

    # 移除安装脚本
    sudo rm -f "$script_file"

    # 移除安装日志
    sudo rm -f ./install.log
}

# 卸载 docker
__uninstall_docker() {
    log_debug "run __uninstall_docker"

    # 停止服务
    sudo systemctl stop docker || true

    # 卸载 docker
    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

    # 自动删除无用依赖
    sudo apt autoremove -y

    log_info "docker 卸载完成"

    is_remove=$(read_user_input "是否需要移除 docker 的历史数据 docker (默认n) [y|n]? " "n")

    if [[ "$is_remove" == "y" ]]; then
        # 删除相关数据
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd

        # 删除 apt 源和 keyring
        sudo rm /etc/apt/sources.list.d/docker.list
        sudo rm /etc/apt/keyrings/docker.asc

        log_info "已移除 docker 历史数据"
    else
        log_info "未移除 docker 历史数据"
    fi
}

# 卸载 docker
uninstall_docker() {
    log_debug "run uninstall_docker"

    is_uninstall=$(read_user_input "是否卸载 docker (默认n) [y|n]? " "n")
    if [[ "$is_uninstall" == "y" ]]; then
        __uninstall_docker
    else
        log_info "未卸载 docker"
    fi
}

# docker 安装入口函数
install_docker() {
    log_debug "run install_docker"
    # 是否为手动安装, 默认否
    local is_manual_install="${1-n}"

    # 判断是否安装了 docker
    if command -v docker >/dev/null 2>&1; then
        log_warn "检测到已安装 Docker"

        local is_install
        is_install=$(read_user_input "是否需要卸载后重新安装 docker (默认n) [y|n]? " "n")

        if [[ "$is_install" == "y" ]]; then
            log_debug "开始卸载 docker"

            # 卸载 docker
            __uninstall_docker

            # 执行安装
            __install_docker "$is_manual_install"
        else
            log_info "跳过 docker 重新安装步骤"
            return
        fi
    else
        # 执行安装
        __install_docker
    fi
}

# 手动安装 docker
manual_install_docker() {
    log_debug "run manual_install_docker"
    __install_docker "y"
}

### content from docker/mirror.sh
DOCKER_CE_TEST_DOWNLOAD_FILE="linux/$(get_docker_repo_path)/gpg" # 测试文件路径(相对于镜像源根目录)

# 测试并找出最快的 Docker CE 镜像源 (并发抢占式版本)
find_fastest_docker_mirror() {
    # 创建临时目录来存储每个任务的结果, 并确保脚本退出时清理
    local temp_dir
    temp_dir=$(mktemp -d)

    # 在函数退出时清理临时目录
    trap 'rm -rf "$temp_dir"' EXIT

    # 关联数组: PID -> Source URL
    declare -A pids_to_sources
    log_info "正在启动对所有 Docker CE 镜像源进行并发测速..."

    # 1. 并发启动所有测试任务
    for item in "${DOCKER_CE_SOURCES[@]}"; do
        log_debug "启动测试任务 for source: $item"
        local source
        # 按 '|' 分割为 URL 和 描述，避免参数扩展在复杂字符串下出错
        IFS='|' read -r source _ <<<"$item"

        # 为每个源创建一个唯一的输出文件
        # 将URL中的非字母数字字符替换为下划线, 以避免文件名问题
        local sanitized_source
        sanitized_source="${source//[!a-zA-Z0-9]/_}"
        local output_file="$temp_dir/${sanitized_source}.out"

        # 启动后台任务
        (
            # 清除子进程对父 shell EXIT trap 的继承, 避免子进程退出时删除临时目录
            trap - EXIT

            local test_url="${source}/${DOCKER_CE_TEST_DOWNLOAD_FILE}"
            # 使用 curl 进行测试
            # --connect-timeout: 连接阶段的超时时间
            # --max-time: 整个操作的超时时间
            local time_total
            time_total=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 3 -m 10 "$test_url" 2>/dev/null) || time_total=""

            # 检查 curl 命令本身是否成功执行 (即没有因为超时等原因被中断)
            # 如果 curl 失败, 它的退出码非0, 并且 time_total 可能为空
            # 通过检查 time_total 是否为有效数字来判断且小于10秒
            if [[ "$time_total" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (($(echo "$time_total < 10" | bc -l 2>/dev/null || echo 0))); then
                # 只有在成功且耗时小于10秒的情况下, 才将结果写入文件
                echo "$time_total $source" >"$output_file"
            else
                # 否则, 写入一个失败标记
                echo "FAILED" >"$output_file"
            fi
        ) &

        # 记录后台进程的PID和它对应的源地址
        local pid=$!
        pids_to_sources["$pid"]="$source"

        log_debug "已启动测试任务 PID: $pid -> $source"
    done

    log_debug "所有测试任务已启动, 共 ${#pids_to_sources[@]} 个。正在等待首个成功响应的源..."

    local fastest_source=""
    local fastest_time=""

    # 2. 主循环: 收集本轮完成的所有任务, 并从中选出最快的
    # 设置一个超时计数器, 防止无限期等待
    local timeout_counter=0
    local max_timeout=50 # 大约10秒 (50 * 0.2s)

    while [ ${#pids_to_sources[@]} -gt 0 ] && [ $timeout_counter -lt $max_timeout ]; do
        declare -A completed_this_round # 存储本轮完成的任务 PID -> Source
        # 遍历当前所有活动的PID
        for pid in "${!pids_to_sources[@]}"; do
            # 检查进程是否还存在
            if ! kill -0 "$pid" 2>/dev/null; then
                # 进程已结束, 读取它的结果文件
                local source_url="${pids_to_sources[$pid]}"
                local sanitized_source
                sanitized_source="${source_url//[!a-zA-Z0-9]/_}"
                local output_file="$temp_dir/${sanitized_source}.out"

                if [ -f "$output_file" ]; then
                    read -r result <"$output_file"
                    # 从监控数组中移除已结束的PID
                    unset "pids_to_sources[$pid]"
                    # 将完成的任务暂存起来
                    completed_this_round["$pid"]="$source_url|$result"
                fi
            fi
        done

        # 本轮有任务完成, 检查其中是否有成功的, 并找出最快的一个
        if [ ${#completed_this_round[@]} -gt 0 ]; then
            local best_time_in_round=""
            local best_source_in_round=""

            # 遍历本轮所有已完成的结果
            for pid in "${!completed_this_round[@]}"; do
                IFS='|' read -r source_url result <<<"${completed_this_round[$pid]}"

                # 检查结果是否为成功
                if [[ "$result" != FAILED* ]]; then
                    used_time=$(echo "$result" | cut -d' ' -f1)

                    # 如果是第一个成功的, 或者比当前最好的更快, 则更新
                    if [ -z "$best_time_in_round" ]; then
                        # 第一个成功的结果
                        best_time_in_round="$used_time"
                        best_source_in_round=$(echo "$result" | cut -d' ' -f2-)
                    elif (($(echo "$used_time < $best_time_in_round" | bc -l))); then
                        # 比当前最佳的更快，更新最佳
                        best_time_in_round="$used_time"
                        best_source_in_round=$(echo "$result" | cut -d' ' -f2-)
                    fi
                fi
            done

            # 如果在本轮找到了最快的成功源, 则立即确定结果并退出
            if [ -n "$best_source_in_round" ]; then
                fastest_time="$best_time_in_round"
                fastest_source="$best_source_in_round"

                log_debug "🎉 找到最快的 Docker CE 镜像源！"
                log_debug "镜像地址: $fastest_source"
                log_debug "响应时间: $(awk "BEGIN {printf \"%.0f\", $fastest_time * 1000}") ms"

                # 3. 终止所有剩余的后台任务
                log_debug "终止其他正在进行的测试任务..."
                for remaining_pid in "${pids_to_sources[@]}"; do
                    log_debug "终止任务 PID: $remaining_pid"

                    # 需要使用 || true 来防止 kill 失败时脚本退出
                    sudo kill "$remaining_pid" 2>/dev/null || true
                done
                break 2 # 跳出内外层循环
            fi
        fi

        timeout_counter=$((timeout_counter + 1))
        sleep 0.2 # 每200ms轮询一次
    done

    # 4. 收尾工作
    if [ -z "$fastest_source" ]; then
        log_error "❌ 错误：在指定时间内未能找到任何可用的 Docker CE 镜像源。"
        log_error "   请检查网络连接或镜像列表 'DOCKER_CE_SOURCES' 是否正确。"
        return 1
    fi

    echo "$fastest_source"
}

# 备份并删除 docker apt 源和 keyring 文件
docker_install_backup() {
    log_debug "run docker_install_backup"

    # 时间戳
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    # 备份并删除 /etc/apt/sources.list.d/docker.list
    local docker_list_file="/etc/apt/sources.list.d/docker.list"

    if [ -f "$docker_list_file" ]; then
        local bak_dir="/etc/apt/sources.list.d/backup"
        # 如果目录不存在则创建
        if [ ! -d "$bak_dir" ]; then
            sudo mkdir -p "$bak_dir"
            log_debug "已创建备份目录 $bak_dir"
        fi

        # 备份文件
        sudo cp -a "$docker_list_file" "$bak_dir/docker.list.bak_$timestamp"
        log_info "已备份 $docker_list_file 到 $bak_dir/docker.list.bak_$timestamp"

        # 删除文件
        sudo rm -f "$docker_list_file"
        log_debug "已删除 $docker_list_file"
    else
        log_warn "未找到 $docker_list_file，跳过备份和删除"
    fi

    # 备份并删除 /etc/apt/keyrings/docker.asc
    local docker_key_file="/etc/apt/keyrings/docker.asc"
    if [ -f "$docker_key_file" ]; then
        local bak_dir="/etc/apt/keyrings/backup"
        # 如果目录不存在则创建
        if [ ! -d "$bak_dir" ]; then
            sudo mkdir -p "$bak_dir"
            log_debug "已创建备份目录 $bak_dir"
        fi

        # 备份文件
        sudo cp -a "$docker_key_file" "$bak_dir/docker.asc.bak_$timestamp"
        log_info "已备份 $docker_key_file 到 $bak_dir/docker.asc.bak_$timestamp"

        # 删除文件
        sudo rm -f "$docker_key_file"
        log_debug "已删除 $docker_key_file"
    else
        log_warn "未找到 $docker_key_file，跳过备份和删除"
    fi
}

# 手动选择 docker 源
manual_select_docker_source() {
    log_debug "run __install_docker"
    # 1. 打印中文名称（带序号）
    echo "请选择一个 Docker CE 镜像源：" >&2
    for i in "${!DOCKER_CE_SOURCES[@]}"; do
        url="${DOCKER_CE_SOURCES[$i]%|*}"
        name="${DOCKER_CE_SOURCES[$i]#*|}"
        log_debug "选项 $((i + 1)): $name ($url)"
        printf "%2d) %s\n" $((i + 1)) "$name" >&2
    done

    # 2. 获取用户输入
    read -rp "请输入序号（1-${#DOCKER_CE_SOURCES[@]}）: " choice

    # 校验输入是否合法
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#DOCKER_CE_SOURCES[@]}" ]; then
        log_error "无效的输入！请输入 1 到 ${#DOCKER_CE_SOURCES[@]} 之间的数字。"
        exit 1
    fi

    # 3. 获取对应的 URL
    selected_item="${DOCKER_CE_SOURCES[$((choice - 1))]}"
    url="${selected_item%|*}"

    log_debug "用户选择的 Docker CE 镜像源: $url"

    # 输出结果
    log_info "您选择的是：${selected_item#*|}"
    echo "$url"
}

### content from db/es.sh
# 创建 es 挂载目录
mkdir_es_volume() {
  log_debug "run mkdir_es_volume"

  # 创建目录
  if [ ! -d "$DATA_VOLUME_DIR/es" ]; then
    setup_directory "$ES_UID" "$ES_GID" 755 "$DATA_VOLUME_DIR/es"
  fi
}

# 复制 es 配置文件
copy_es_config() {
  log_debug "run copy_es_config"

  local is_kibana=$1                       # 是否包含 kibana
  local ca_cert_file="$CA_CERT_DIR/ca.crt" # CA 证书文件
  local ca_key_file="$CA_CERT_DIR/ca.key"  # CA 私钥文件

  # 生成 ca 证书
  gen_my_ca_cert

  # 创建临时容器,用于复制配置文件
  sudo docker create --name temp_container_es -m 512MB "elasticsearch:$IMG_VERSION_ES" >/dev/null 2>&1 || true

  # 预下载 IK 分词器插件到 es 目录(避免容器内无法访问外网, 仅下载一次供所有节点复用)
  local ik_zip_name="elasticsearch-analysis-ik-$IMG_VERSION_ES.zip"
  local ik_zip_url="https://release.infinilabs.com/analysis-ik/stable/$ik_zip_name"
  local ik_zip_shared="$DATA_VOLUME_DIR/es/plugin/$ik_zip_name"
  if [ ! -f "$ik_zip_shared" ]; then
    log_info "下载 IK 分词器插件: $ik_zip_url"
    setup_directory "$ES_UID" "$ES_GID" 755 "$DATA_VOLUME_DIR/es/plugin"
    sudo curl -fSL -o "$ik_zip_shared" "$ik_zip_url"
    sudo chown "$ES_UID:$ES_GID" "$ik_zip_shared"
  fi

  # 根据 ES 节点数量,循环复制配置文件
  local i
  for ((i = 1; i <= ES_NODE_COUNT; i++)); do
    # ip_node 自增 从 2 开始, 1 为网关
    local ip_node="$IPV4_BASE_ES.$(((i + 1) % 256))"

    # 格式化节点编号
    local formattedI
    formattedI=$(printf "%02d" $i)

    # 节点目录
    local dir_node="$DATA_VOLUME_DIR/es/node-$formattedI"

    sudo rm -rf "$dir_node"                                                                         # 删除原来的配置文件
    setup_directory "$ES_UID" "$ES_GID" 755 "$dir_node/config" "$dir_node/data" "$dir_node/plugins" # 创建目录
    sudo docker cp temp_container_es:/usr/share/elasticsearch/config "$dir_node"                    # 配置
    sudo docker cp temp_container_es:/usr/share/elasticsearch/data "$dir_node"                      # 数据
    sudo docker cp temp_container_es:/usr/share/elasticsearch/plugins "$dir_node"                   # 插件
    sudo cp "$ca_cert_file" "$dir_node/config/ca.crt"                                               # CA 证书

    # 生成证书
    generate_instance_cert "es-$IMG_VERSION_ES-$formattedI" \
      "es-$IMG_VERSION_ES-$formattedI,localhost" \
      "127.0.0.1,$HOST_INTRANET_IP,$ip_node,$PUBLIC_IP_ADDRESS" \
      "$dir_node/config" \
      "$CERT_DAYS_VALID" \
      "$ca_cert_file" \
      "$ca_key_file"

    # 再次赋权
    setup_directory "$ES_UID" "$ES_GID" 755 "$dir_node/config" "$dir_node/data" "$dir_node/plugins"

    # 复制预下载的 IK 插件 zip 到节点 config 目录(不能放 plugins 目录否则会被当成已安装插件)
    sudo cp "$ik_zip_shared" "$dir_node/config/$ik_zip_name"
    sudo chown "$ES_UID:$ES_GID" "$dir_node/config/$ik_zip_name"

    # 在 "$dir_node/config" 中 创建插件配置文件 elasticsearch-plugins.yml,写入插件配置,用于插件安装
    sudo touch "$dir_node/config/elasticsearch-plugins.yml"
    sudo chown "$ES_UID:$ES_GID" "$dir_node/config/elasticsearch-plugins.yml"
    sudo tee -a "$dir_node/config/elasticsearch-plugins.yml" >/dev/null <<-EOM
# 参考 https://www.elastic.co/guide/en/elasticsearch/plugins/current/manage-plugins-using-configuration-file.html
plugins:
  - id: analysis-ik # ik 分词器
    # 版本管理地址: https://release.infinilabs.com/analysis-ik/stable/
    location: file:///usr/share/elasticsearch/config/$ik_zip_name
EOM

  done

  # 删除临时容器
  sudo docker rm -f temp_container_es >/dev/null 2>&1 || true

  # 是否包含 kibana
  if [ "$is_kibana" = "y" ]; then
    # 创建临时容器
    sudo docker create --name temp_container_kibana -m 512MB "kibana:$IMG_VERSION_KIBANA" >/dev/null 2>&1 || true

    # 复制 kibana 配置文件
    sudo rm -rf "$DATA_VOLUME_DIR/es/kibana"                                                                              # 删除原来的配置文件
    setup_directory "$KIBANA_UID" "$KIBANA_GID" 755 "$DATA_VOLUME_DIR/es/kibana/config" "$DATA_VOLUME_DIR/es/kibana/data" # 创建目录
    sudo docker cp temp_container_kibana:/usr/share/kibana/config "$DATA_VOLUME_DIR/es/kibana"                            # 复制配置文件
    sudo docker cp temp_container_kibana:/usr/share/kibana/data "$DATA_VOLUME_DIR/es/kibana"                              # 复制配置文件
    sudo docker rm -f temp_container_kibana >/dev/null 2>&1 || true                                                       # 删除临时容器
    sudo cp "$ca_cert_file" "$DATA_VOLUME_DIR/es/kibana/config/ca.crt"                                                    # CA 证书
    setup_directory "$KIBANA_UID" "$KIBANA_GID" 755 "$DATA_VOLUME_DIR/es/kibana/config" "$DATA_VOLUME_DIR/es/kibana/data" # 再次赋权

    # 向 "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml" 文件追加配置, 切换为中文 i18n.locale: "zh-CN"
    # 首先判断 是否有 i18n.locale, 如果没有则追加, 如果有则替换
    if ! sudo grep -q "i18n.locale" "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml"; then
      printf "\ni18n.locale: \"zh-CN\"\n" | sudo tee -a "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml"
    else
      sudo sed -i 's/i18n.locale: .*/i18n.locale: "zh-CN"/' "$DATA_VOLUME_DIR/es/kibana/config/kibana.yml"
    fi
  fi

  log_info "es 复制配置文件到 volume success"
}

# 创建 es 配置文件
create_docker_compose_es() {
  log_debug "run create_docker_compose_es"

  local all_remove_data # 是否删除历史数据 默认不删除
  local is_kibana       # 是否包含 kibana 默认包含

  # 提示用户输入

  # 根据运行模式决定是否询问
  if run_mode_is_dev; then
    all_remove_data=$(read_user_input "[1/2]是否删除 es 信息(默认n) [y|n]? " "n")
    is_kibana=$(read_user_input "[2/2]是否包含 kibana (默认n) [y|n]? " "n")
  fi
  if run_mode_is_pro; then
    all_remove_data=$(read_user_input "是否删除 es 信息(默认n) [y|n]? " "n")
    is_kibana="n"
  fi

  if [ ! -d "$DATA_VOLUME_DIR" ]; then
    # 如果不存在则创建
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
  fi

  setup_directory "$ES_UID" "$ES_GID" 755 "$DATA_VOLUME_DIR/es" # 创建目录

  # 创建一个名为 docker-compose.yaml 的新文件
  local docker_compose_file="$DOCKER_COMPOSE_FILE_ES"

  # 如果存在 docker-compose.yaml 执行docker compose down
  if [ -f "$docker_compose_file" ]; then
    sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_ES" down || true # 删除容器
    touch "$docker_compose_file"
  fi

  # 参考
  # https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-basic
  # https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-compose
  # https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-prod#docker-set-heap-size
  # https://www.elastic.co/docs/reference/elasticsearch/jvm-settings#set-jvm-heap-size
  # https://github.com/elastic/elasticsearch/blob/main/docs/reference/setup/install/docker/docker-compose.yml

  cat >"$docker_compose_file" <<-EOM
services:
EOM

  # 配置文件目录
  local i
  for ((i = 1; i <= ES_NODE_COUNT; i++)); do
    local formattedI
    formattedI=$(printf "%02d" "$i")
    local dir_node="$DATA_VOLUME_DIR/es/node-$formattedI"
    local ip_node="$IPV4_BASE_ES.$(((i + 1) % 256))" # ip_node 自增 从 2 开始, 1 为网关

    # 生成 es 配置文件
    initial_master_nodes=$(generate_items_all "es-$IMG_VERSION_ES" "$ES_NODE_COUNT") # 生成所有 es 节点
    seed_hosts=$(generate_items_exclude "es-$IMG_VERSION_ES" "$i" "$ES_NODE_COUNT")  # 生成所有 es 节点,排除当前节点
    # 追加写入主节点 docker-compose 配置文件
    cat >>"$docker_compose_file" <<-EOM

  # 补全两位小数显示
  es-$IMG_VERSION_ES-$formattedI:
    image: elasticsearch:$IMG_VERSION_ES
    container_name: es-$IMG_VERSION_ES-$formattedI
    restart: always
    volumes:
      - $dir_node/data:/usr/share/elasticsearch/data
      - $dir_node/config:/usr/share/elasticsearch/config
      - $dir_node/plugins:/usr/share/elasticsearch/plugins
    user: "$ES_UID:$ES_GID"
EOM
    # 仅当 i = 0 时添加 ports 部分 和 entrypoint 部分
    if [ "$i" -eq 1 ]; then
      cat >>"$docker_compose_file" <<-EOM
    ports:
      - $ES_PORT:9200
EOM
    fi

    cat >>"$docker_compose_file" <<-EOM
    environment:
      - node.name=es-$IMG_VERSION_ES-$formattedI
      - cluster.name=$ES_CLUSTER_NAME
EOM
    # 仅当 $ES_NODE_COUNT > 1 时添加 cluster 部分
    if [ "$ES_NODE_COUNT" -gt 1 ]; then
      cat >>"$docker_compose_file" <<-EOM
      - cluster.initial_master_nodes=$initial_master_nodes
      - discovery.seed_hosts=$seed_hosts
EOM
    else # 仅有一个节点时
      cat >>"$docker_compose_file" <<-EOM
      - discovery.type=single-node
EOM
    fi

    cat >>"$docker_compose_file" <<-EOM
      # Password for the 'elastic' user (at least 6 characters)
      - ELASTIC_PASSWORD=$ELASTIC_PASSWORD
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.key
      - xpack.security.http.ssl.certificate=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.crt
      - xpack.security.http.ssl.certificate_authorities=/usr/share/elasticsearch/config/ca.crt
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.key=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.key
      - xpack.security.transport.ssl.certificate=/usr/share/elasticsearch/config/es-$IMG_VERSION_ES-$formattedI.crt
      - xpack.security.transport.ssl.certificate_authorities=/usr/share/elasticsearch/config/ca.crt
      - xpack.security.transport.ssl.verification_mode=certificate
      - xpack.license.self_generated.type=$ES_LICENSE
      - xpack.ml.use_auto_machine_memory_percent=false
      $ES_JAVA_OPTS_ENV

    $MEM_LIMIT_ES 

    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s --cacert /usr/share/elasticsearch/config/ca.crt https://localhost:9200 | grep -q 'missing authentication credentials'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120
    networks: # docker 网络设置
      $BRIDGE_ES: # 网络名称
          ipv4_address: $ip_node
EOM
  done

  # 删除历史数据 es
  if [ "$all_remove_data" == "y" ]; then

    # 删除历史数据
    sudo rm -rf "$DATA_VOLUME_DIR/es"

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
      # 如果不存在则创建
      setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    # 创建新目录并复制初始配置
    copy_es_config "$is_kibana"

    log_info "已删除 es 历史数据"
  else
    log_info "未删除 es 历史数据"
  fi

  # ========================================================= es 结束

  # ========================================================= kibana 开始
  if [ "$is_kibana" == "y" ]; then
    cat >>"$docker_compose_file" <<-EOM
  # kibana 服务 
  kibana:
    depends_on:
EOM

    # 动态生成 depends_on 部分
    for ((i = 1; i <= ES_NODE_COUNT; i++)); do
      formattedI=$(printf "%02d" "$i")
      cat >>"$docker_compose_file" <<-EOM
      es-$IMG_VERSION_ES-$formattedI:
        condition: service_healthy
EOM
    done

    cat >>"$docker_compose_file" <<-EOM
    image: kibana:$IMG_VERSION_KIBANA
    container_name: kibana-$IMG_VERSION_KIBANA
    restart: always
    volumes:
      - $DATA_VOLUME_DIR/es/kibana/data:/usr/share/kibana/data
      - $DATA_VOLUME_DIR/es/kibana/config:/usr/share/kibana/config
    user: "$ES_UID:$ES_GID"
    ports:
      - $KIBANA_PORT:5601
    environment:
      - SERVERNAME=kibana
      - ELASTICSEARCH_HOSTS=https://es-$IMG_VERSION_ES-01:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=$KIBANA_PASSWORD
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/ca.crt
    $MEM_LIMIT_KIBANA
    
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s -I http://localhost:5601 | grep -q 'HTTP/1.1 302 Found'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

    networks: # 网络配置
      $BRIDGE_ES: # 网络名称
        ipv4_address: "$IPV4_BASE_ES.$(((ES_NODE_COUNT + 2) % 256))" # IP地址
EOM
  fi

  # 添加网络配置
  cat >>"$docker_compose_file" <<-EOM

networks: # 网络配置
  $BRIDGE_ES: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_ES # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_ES" # 子网
          gateway: "$GATEWAY_ES" # 网关
EOM

  # ========================================================= kibana 结束
}

# es kibana 并健康检查
health_check_db_es() {
  log_debug "run health_check_db_es"

  local es_container="es-$IMG_VERSION_ES-01" # 第一个 ES 节点容器名
  log_warn "等待 Elasticsearch 启动, 这可能需要几分钟时间... 请勿中断！"

  # 通过 docker inspect 检查容器健康状态(依赖 docker-compose 中已配置的 healthcheck)
  until sudo docker inspect --format='{{.State.Health.Status}}' "$es_container" 2>/dev/null | grep -q 'healthy'; do
    # 等待 10 秒, 并显示动画
    waiting 10
  done

  log_info "Elasticsearch 启动完成"

  log_debug "设置 kibana_system 用户密码为 $KIBANA_PASSWORD"

  # 通过 docker exec 在容器内执行, 避免宿主机网络问题
  until sudo docker exec "$es_container" curl -s --cacert /usr/share/elasticsearch/config/ca.crt -u "elastic:$ELASTIC_PASSWORD" -X POST -H "Content-Type: application/json" "https://localhost:9200/_security/user/kibana_system/_password" -d "{\"password\":\"$KIBANA_PASSWORD\"}" 2>/dev/null | grep -q "^{}"; do
    # 等待 5 秒, 并显示动画
    waiting 5
  done
}

# 启动 es 容器
start_db_es() {
  log_debug "run start_db_es"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_ES" -p "$DOCKER_COMPOSE_PROJECT_NAME_ES" up -d

  # 进行健康检查
  health_check_db_es
}

# 停止 es 容器
stop_db_es() {
  log_debug "run stop_db_es"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_ES" -p "$DOCKER_COMPOSE_PROJECT_NAME_ES" down || true
}

# 重启 es 容器
restart_db_es() {
  log_debug "run restart_db_es"
  stop_db_es
  start_db_es
}

# 安装 es kibana
install_es_kibana() {
  log_debug "run install_es_kibana"

  # shellcheck disable=SC2329
  run() {
    # 创建目录
    mkdir_es_volume
    # 创建 docker-compose.yaml
    create_docker_compose_es

    # 启动服务
    start_db_es
  }

  log_timer "es 安装" run

  log_info "es 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 删除 es kibana
delete_es_kibana() {
  log_debug "run delete_es_kibana"

  local is_delete
  is_delete=$(read_user_input "确认停止 es 服务并删除数据吗(默认n) [y|n]? " "n")

  if [[ "$is_delete" == "y" ]]; then
    # 停止容器
    stop_db_es

    # 删除 es kibana 数据
    sudo rm -rf "$DATA_VOLUME_DIR/es"
  fi
}

### content from db/pgsql_billing_center.sh
# 启动 pgsql 容器(billing center)
start_db_pgsql_billing_center() {
  log_debug "run start_db_pgsql_billing_center"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" up -d
}

# 停止 pgsql 容器(billing center)
stop_db_pgsql_billing_center() {
  log_debug "run stop_db_pgsql_billing_center"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" down || true
}

# 重启 pgsql 容器(billing center)
restart_db_pgsql_billing_center() {
  log_debug "run restart_db_pgsql_billing_center"
  stop_db_pgsql_billing_center
  start_db_pgsql_billing_center
}

# 安装 pgsql 数据库(billing center)
install_db_pgsql_billing_center() {
  log_debug "run install_db_pgsql_billing_center"
  # shellcheck disable=SC2329
  run() {
    local all_remove_data # 是否删除历史数据 默认不删除

    all_remove_data=$(read_user_input "是否删除 pgsql_billing_center 数据库信息(默认n) [y|n]? " "n")

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
      # 如果不存在则创建
      setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/pgsql_billing_center"

    # 创建一个名为 docker-compose.yaml 的新文件
    local docker_compose_file="$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER"

    # 如果存在 docker-compose.yaml 执行 docker compose down
    if [ -f "$docker_compose_file" ]; then
      sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" down || true # 删除容器
      touch "$docker_compose_file"
    fi

    cat >"$docker_compose_file" <<-EOM
services:
  # PostgreSQL 服务
  postgres:
    image: 'postgres:$IMG_VERSION_PGSQL'
    container_name: $POSTGRES_DOCKER_NAME_BILLING_CENTER
    restart: always
    user: '$DB_UID:$DB_GID' # DOCKERFILE 中设置的用户
    environment:
      POSTGRES_USER: $POSTGRES_USER_BILLING_CENTER
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD_BILLING_CENTER
      POSTGRES_DB: $POSTGRES_DB_BILLING_CENTER
      # 初始化使用和配置有所重复,需要保留 --auth-local=trust 本地连接不需要密码  --auth-host=scram-sha-256 远程连接需要密码 --data-checksums 数据校验
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=trust --data-checksums"

    # 使用自定义配置文件
    command: postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

    volumes:
      - $DATA_VOLUME_DIR/pgsql_billing_center/conf/postgresql.conf:/etc/postgresql/postgresql.conf # 自定义配置文件
      - $DATA_VOLUME_DIR/pgsql_billing_center/conf/pg_hba.conf:/etc/postgresql/pg_hba.conf # 在 postgresql.conf 配置文件中指定路径
      # 数据目录调整,参考:https://github.com/docker-library/postgres/pull/1259
      - $DATA_VOLUME_DIR/pgsql_billing_center/data:/var/lib/postgresql/$IMG_VERSION_PGSQL_MAJOR/docker # 数据存储目录
      - $DATA_VOLUME_DIR/pgsql_billing_center/log:/var/log/postgresql # 日志存储目录

    ports:
      - "$POSTGRES_PORT_BILLING_CENTER:$POSTGRES_PORT_BILLING_CENTER" # 映射端口

    networks: # 网络配置
      $BRIDGE_PGSQL_BILLING_CENTER: # 网络名称
        ipv4_address: $POSTGRES_IP_BILLING_CENTER # IP地址

networks: # 网络配置
  $BRIDGE_PGSQL_BILLING_CENTER: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_PGSQL_BILLING_CENTER # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_PGSQL_BILLING_CENTER" # 子网
          gateway: "$GATEWAY_PGSQL_BILLING_CENTER" # 网关
EOM

    # 删除历史数据 pgsql_billing_center
    if [ "$all_remove_data" == "y" ]; then

      sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center"
      if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
      fi

      # 创建新目录
      setup_directory "$DB_UID" "$DB_GID" 755 \
        "$DATA_VOLUME_DIR/pgsql_billing_center" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/data" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/conf" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/log"

      # 获取配置文件内容
      local content_postgresql_conf
      local content_pg_hba_conf

      content_postgresql_conf=$(get_content_postgresql_conf "$POSTGRES_PORT_BILLING_CENTER")
      content_pg_hba_conf=$(get_content_pg_hba_conf "$SUBNET_PGSQL_BILLING_CENTER" "$SUBNET_BILLING_CENTER")

      # 写入配置文件并设置权限
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_postgresql_conf" "$DATA_VOLUME_DIR/pgsql_billing_center/conf/postgresql.conf"
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_pg_hba_conf" "$DATA_VOLUME_DIR/pgsql_billing_center/conf/pg_hba.conf"

      log_info "已删除 pgsql_billing_center 历史数据"

    else
      log_info "未删除 pgsql_billing_center 历史数据"
    fi

    # 启动 pgsql 容器
    start_db_pgsql_billing_center

    # # 删除pgsql_billing_center不使用的默认配置文件
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center/data/postgresql.conf"
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center/data/pg_hba.conf"

  }

  log_timer "pgsql_billing_center 启动" run

  log_info "pgsql_billing_center 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 停止并删除 pgsql_billing_center 数据库
delete_db_pgsql_billing_center() {
  log_debug "run delete_db_pgsql_billing_center"

  local is_delete
  is_delete=$(read_user_input "确认停止 pgsql_billing_center 服务并删除数据吗(默认n) [y|n] " "n")

  if [[ "$is_delete" == "y" ]]; then
    # 停止容器
    stop_db_pgsql_billing_center

    # 删除数据库数据
    sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center"
  fi
}

### content from db/pgsql.sh
# postgresql.conf 文件
get_content_postgresql_conf() {
  local postgres_port=$1

  local content_postgresql_conf
  content_postgresql_conf=$(
    cat <<EOL
# PostgreSQL 配置文件

# 配置目录: /etc/postgresql
# 数据目录: /var/lib/postgresql

# 连接设置
listen_addresses = '*'                             # 监听地址,'*'为监听所有IP
port = $postgres_port                              # 监听端口
max_connections = 200                              # 最大连接数
superuser_reserved_connections = 3                 # 超级用户保留连接数
ssl = off                                          # SSL加密

# 认证设置
password_encryption = scram-sha-256                # 密码加密方法 (scram-sha-256 or md5)

# 内存参数设置
shared_buffers = 256MB                             # 共享缓冲区大小
effective_cache_size = 256MB                       # 工作内存大小
maintenance_work_mem = 64MB                        # 维护工作内存大小
temp_buffers = 8MB                                 # 临时缓冲区大小
dynamic_shared_memory_type = posix                 # 动态共享内存类型 (posix, sysv, windows, mmap)

# 写入参数设置
fsync = on                                         # 同步磁盘写入
wal_sync_method = fsync                            # WAL同步方法
synchronous_commit = on                            # 同步提交
checkpoint_timeout = 5min                          # 检查点超时时间
checkpoint_completion_target = 0.9                 # 检查点完成目标百分比
checkpoint_flush_after = 32kB                      # 检查点刷新间隔大小

# 磁盘参数设置
max_wal_size = 1GB                                 # WAL日志文件最大大小
min_wal_size = 80MB                                # WAL日志文件最小大小

timezone = 'Asia/Shanghai'                         # 时区设置 (UTC, Asia/Shanghai, Etc/UTC)

# 日志设置
log_destination = 'stderr'                         # 日志输出目标
logging_collector = on                             # 启用日志收集
log_directory = 'pg_log'                           # 日志目录
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'    # 日志文件名
log_truncate_on_rotation = on                      # 截断旧日志
log_rotation_age = 7d                              # 日志轮换时间
log_rotation_size = 10MB                           # 日志轮换大小
log_min_duration_statement = -1                    # 记录慢查询阈值（毫秒）
log_line_prefix = '%t [%p]: [%x] %u@%d %i '        # 日志行前缀格式
log_timezone = 'Asia/Shanghai'                     # 日志时区

# 运行时统计信息设置
track_activities = on                              # 与踪连接活动
track_counts = on                                  # 与踪对象数量
update_process_title = on                          # 更新进程标题显示状态

# 其他参数
datestyle = 'iso, mdy'                             # 日期输出格式
lc_messages='en_US.UTF-8'                          # 本地化消息显示设置
lc_monetary='en_US.UTF-8'                          # 本地化货币显示设置
lc_numeric='en_US.UTF-8'                           # 本地化数字显示设置
lc_time='en_US.UTF-8'                              # 本地化时间显示设置
default_text_search_config = 'pg_catalog.english'  # 默认全文搜索配置
EOL
  )

  # 返回内容
  echo "$content_postgresql_conf"
}

# pg_hba.conf 文件
get_content_pg_hba_conf() {
  local subnet_pgsql=$1
  local subnet_server=$2

  local content_pg_hba_conf
  content_pg_hba_conf=$(
    cat <<EOL
# PostgreSQL Client Authentication Configuration File
# ===================================================

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust

# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     trust

# ip4访问权限限制开始
#host    all             all             10.0.0.0/16         scram-sha-256 # 允许此 IP 地址访问
#host    all             all             $subnet_pgsql        scram-sha-256 # 允许此 IP 地址访问
#host    all             all             $subnet_server        scram-sha-256 # 允许此 IP 地址访问
#host    all             all             $HOST_INTRANET_IP/$(get_cidr "$HOST_INTRANET_MARK")        scram-sha-256 # 允许此 IP 地址访问
# ip4访问权限限制结束

# ip4访问权限放开开始
host    all             all             0.0.0.0/0               scram-sha-256 # 允许所有 ip4 访问
# ip4访问权限放开结束

# ip6 访问权限
# host    all             all             ::/0                    scram-sha-256
EOL
  )
  # 返回内容
  echo "$content_pg_hba_conf"
}

# 启动 pgsql 容器
start_db_pgsql() {
  log_debug "run start_db_pgsql"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" up -d
}

# 停止 pgsql 容器
stop_db_pgsql() {
  log_debug "run stop_db_pgsql"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" down || true
}

# 重启 pgsql 容器
restart_db_pgsql() {
  log_debug "run restart_db_pgsql"
  stop_db_pgsql
  start_db_pgsql
}

# 安装 pgsql 数据库
install_db_pgsql() {
  log_debug "run install_db_pgsql"

  # shellcheck disable=SC2329
  run() {
    local all_remove_data # 是否删除历史数据 默认不删除

    all_remove_data=$(read_user_input "是否删除 pgsql 数据库信息(默认n) [y|n]? " "n")

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
      # 如果不存在则创建
      setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/pgsql"

    # 创建一个名为 docker-compose.yaml 的新文件
    local docker_compose_file="$DOCKER_COMPOSE_FILE_PGSQL"

    # 如果存在 docker-compose.yaml 执行docker compose down
    if [ -f "$docker_compose_file" ]; then
      sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" down || true # 删除容器
      touch "$docker_compose_file"
    fi

    cat >"$docker_compose_file" <<-EOM
services:
  # PostgreSQL 服务
  postgres:
    image: 'postgres:$IMG_VERSION_PGSQL'
    container_name: $POSTGRES_DOCKER_NAME
    restart: always
    user: '$DB_UID:$DB_GID' # DOCKERFILE 中设置的用户
    environment:
      POSTGRES_USER: $POSTGRES_USER
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
      POSTGRES_DB: $POSTGRES_DB
      # 初始化使用和配置有所重复,需要保留 --auth-local=trust 本地连接不需要密码  --auth-host=scram-sha-256 远程连接需要密码 --data-checksums 数据校验
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=trust --data-checksums"

    # 使用自定义配置文件
    command: postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf

    volumes:
      - $DATA_VOLUME_DIR/pgsql/conf/postgresql.conf:/etc/postgresql/postgresql.conf # 自定义配置文件
      - $DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf:/etc/postgresql/pg_hba.conf # 在 postgresql.conf 配置文件中指定路径
      # 数据目录调整,参考:https://github.com/docker-library/postgres/pull/1259
      - $DATA_VOLUME_DIR/pgsql/data:/var/lib/postgresql/$IMG_VERSION_PGSQL_MAJOR/docker # 数据存储目录
      - $DATA_VOLUME_DIR/pgsql/log:/var/log/postgresql # 日志存储目录

    ports:
      - "$POSTGRES_PORT:5432" # 映射端口

    networks: # 网络配置
      $BRIDGE_PGSQL: # 网络名称
        ipv4_address: $POSTGRES_IP # IP地址

networks: # 网络配置
  $BRIDGE_PGSQL: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_PGSQL # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_PGSQL" # 子网
          gateway: "$GATEWAY_PGSQL" # 网关
EOM

    # 删除历史数据 pgsql
    if [ "$all_remove_data" == "y" ]; then

      sudo rm -rf "$DATA_VOLUME_DIR/pgsql"
      if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
      fi
      # 创建新目录
      setup_directory "$DB_UID" "$DB_GID" 755 \
        "$DATA_VOLUME_DIR/pgsql" \
        "$DATA_VOLUME_DIR/pgsql/data" \
        "$DATA_VOLUME_DIR/pgsql/conf" \
        "$DATA_VOLUME_DIR/pgsql/log"

      # 获取配置文件内容
      local content_postgresql_conf
      local content_pg_hba_conf

      content_postgresql_conf=$(get_content_postgresql_conf "$POSTGRES_PORT")
      content_pg_hba_conf=$(get_content_pg_hba_conf "$SUBNET_PGSQL" "$SUBNET_SERVER")

      # 写入配置文件并设置权限
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_postgresql_conf" "$DATA_VOLUME_DIR/pgsql/conf/postgresql.conf"
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_pg_hba_conf" "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf"

      log_info "已删除 pgsql 历史数据"

    else
      log_info "未删除 pgsql 历史数据"
    fi

    # 启动 pgsql 容器
    start_db_pgsql

    # # 删除pgsql不使用的默认配置文件
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql/data/postgresql.conf"
    # sudo rm -rf "$DATA_VOLUME_DIR/pgsql/data/pg_hba.conf"

  }
  log_timer "pgsql 启动" run

  log_info "pgsql 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 切换 pgsql 访问权限
# 使用示例
#   toggle_pg_hba_conf restrict /path/to/pg_hba.conf
#   toggle_pg_hba_conf open /path/to/pg_hba.conf
toggle_pg_hba_conf() {
  log_debug "run toggle_pg_hba_conf"

  local mode="$1"
  local file_path="$2"

  if [[ "$mode" == "restrict" ]]; then
    sudo awk '/# ip4访问权限限制开始/,/# ip4访问权限限制结束/ {sub(/^#host/, "host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
    sudo awk '/# ip4访问权限放开开始/,/# ip4访问权限放开结束/ {sub(/^host/, "#host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
  elif [[ "$mode" == "open" ]]; then
    sudo awk '/# ip4访问权限限制开始/,/# ip4访问权限限制结束/ {sub(/^#host/, "#host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
    sudo awk '/# ip4访问权限放开开始/,/# ip4访问权限放开结束/ {sub(/^#host/, "host"); print; next} 1' "$file_path" | sudo tee temp >/dev/null && sudo mv temp "$file_path"
  else
    log_error "切换 pg_hba.conf 访问权限失败, 模式错误: $mode; 只能是 restrict 或 open"
    return 1
  fi

  log_info "$file_path 已经切换 $mode 模式."
}

# 开放 pgsql 访问权限
open_pgsql_access_by_pg_hba.conf() {
  log_debug "run open_pgsql_access_by_pg_hba.conf"

  sudo docker stop "$POSTGRES_DOCKER_NAME"                          # 停止容器 pgsql 容器
  toggle_pg_hba_conf open "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf" # 切换访问权限
  sudo docker start "$POSTGRES_DOCKER_NAME"                         # 重启容器
}

# 限制 pgsql 访问权限
restrict_pgsql_access_by_pg_hba.conf() {
  log_debug "run restrict_pgsql_access_by_pg_hba.conf"

  sudo docker stop "$POSTGRES_DOCKER_NAME"                              # 停止容器 pgsql 容器
  toggle_pg_hba_conf restrict "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf" # 切换访问权限
  sudo docker start "$POSTGRES_DOCKER_NAME"                             # 重启容器
}

# 停止并删除 pgsql 数据库
delete_db_pgsql() {
  log_debug "run delete_db_pgsql"

  local is_delete
  is_delete=$(read_user_input "确认停止 pgsql 服务并删除数据吗(默认n) [y|n] " "n")

  if [[ "$is_delete" == "y" ]]; then
    # 停止容器
    stop_db_pgsql

    # 删除数据库数据
    sudo rm -rf "$DATA_VOLUME_DIR/pgsql"
  fi
}

### content from db/redis_billing_center.sh
# 启动 redis 容器(billing center)
start_db_redis_billing_center() {
    log_debug "run start_db_redis_billing_center"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER" up -d # 启动容器
}

# 停止 redis 容器(billing center)
stop_db_redis_billing_center() {
    log_debug "run stop_db_redis_billing_center"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER" down || true
}

# 重启 redis 容器(billing center)
restart_db_redis_billing_center() {
    log_debug "run restart_db_redis_billing_center"
    stop_db_redis_billing_center
    start_db_redis_billing_center
}

# 创建 redis 数据库(billing center)
install_db_redis_billing_center() {
    log_debug "run install_db_redis_billing_center"
    # shellcheck disable=SC2329
    run() {
        local is_redis_cluster # 是否创建 redis 集群 默认不创建
        local all_remove_data  # 是否删除历史数据 默认不删除

        # 根据运行模式决定是否询问
        is_redis_cluster=$(read_user_input "[1/2]是否创建 redis_billing_center 集群(默认n) [y|n]? " "n")
        all_remove_data=$(read_user_input "[2/2]是否删除 redis_billing_center (默认n) [y|n]? " "n")

        if [ ! -d "$DATA_VOLUME_DIR" ]; then
            # 如果不存在则创建
            setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
        fi

        setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/redis_billing_center"

        # ? ===============重要提示===============

        # 由于 docker 中创建 redis sentinel 无法使用自定义网络和 docker0 网络通信
        # 集群和哨兵不能使用 docker 的 NAT 模式 使用 host 模式
        # 需要使用 --net=host 的方式创建,外部访问需要打开对应端口
        # 参考官网: https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/

        # ? ===============重要提示===============

        # 创建一个名为 docker-compose.yaml 的新文件
        local docker_compose_file="$DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER"

        # 如果存在 docker-compose.yaml 执行docker compose down
        if [ -f "$docker_compose_file" ]; then
            sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER" down || true # 删除容器
            touch "$docker_compose_file"
        fi
        cat >"$docker_compose_file" <<-EOM
services:
EOM

        # 单节点,将主从节点设置为 1，从节点设置为 0
        if [ "$is_redis_cluster" == "n" ]; then
            MASTER_COUNT=1
            SLAVE_COUNT=0
        fi

        cluster_urls="" # 集群节点地址
        redis_ips=""    # ip地址拼接
        # 追加写入 docker-compose 配置文件
        for ((port = REDIS_BASE_PORT_BILLING_CENTER; port < REDIS_BASE_PORT_BILLING_CENTER + MASTER_COUNT + SLAVE_COUNT; port++)); do
            port_cluster=$((port + 10000))                                                                   # port_cluster 自增 集群监控端口
            ip_node="$IPV4_BASE_REDIS_BILLING_CENTER.$(((port - REDIS_BASE_PORT_BILLING_CENTER + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关

            # DOCKER_NAMES+=("redis-$IMG_VERSION_REDIS-$port")      # 增加主节点
            cluster_urls+="redis-$IMG_VERSION_REDIS-$port:$port " # 集群节点 名称
            redis_ips+="$ip_node "                                # 集群节点地址

            # 追加写入主节点 docker-compose 配置文件
            cat >>"$docker_compose_file" <<-EOM

  redis-$IMG_VERSION_REDIS-$port:
    image: 'redis:$IMG_VERSION_REDIS'
    restart: always
    container_name: redis-$IMG_VERSION_REDIS-$port
    user: '$DB_UID:$DB_GID' # DOCKERFILE 中设置的用户
    volumes:
      - $DATA_VOLUME_DIR/redis_billing_center/data/$port:/data
      - $DATA_VOLUME_DIR/redis_billing_center/conf/$port:/usr/local/etc/redis # 配置文件需要指定文件夹否则会无法写入
      - $DATA_VOLUME_DIR/redis_billing_center/log/$port:/var/log/redis

    command: [/usr/local/etc/redis/redis.conf] # 指定配置文件重新加载

    ports: # 映射端口，对外提供服务
      - "$port:$port" # redis 的服务端口
      - "$port_cluster:$port_cluster" # redis 集群监控端口
    # stdin_open: true # 标准输入打开
    # tty: true # 终端打开
    # privileged: true # 拥有容器内命令执行的权限

    networks: # docker 网络设置
      $BRIDGE_REDIS_BILLING_CENTER: # 网络名称
          ipv4_address: $ip_node
EOM
        done

        # 删除历史数据 redis_billing_center
        if [ "$all_remove_data" == "y" ]; then

            # 删除历史数据
            sudo rm -rf "$DATA_VOLUME_DIR/redis_billing_center"
            if [ ! -d "$DATA_VOLUME_DIR" ]; then
                # 如果不存在则创建
                setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
            fi

            # 创建新目录
            setup_directory "$DB_UID" "$DB_GID" 755 \
                "$DATA_VOLUME_DIR/redis_billing_center" \
                "$DATA_VOLUME_DIR/redis_billing_center/data" \
                "$DATA_VOLUME_DIR/redis_billing_center/conf" \
                "$DATA_VOLUME_DIR/redis_billing_center/log"

            # 删除原来配置 使用新建的配置文件
            for ((port = REDIS_BASE_PORT_BILLING_CENTER; port < REDIS_BASE_PORT_BILLING_CENTER + MASTER_COUNT + SLAVE_COUNT; port++)); do

                ip_node="$IPV4_BASE_REDIS_BILLING_CENTER.$(((port - REDIS_BASE_PORT_BILLING_CENTER + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关
                setup_directory "$DB_UID" "$DB_GID" 755 \
                    "$DATA_VOLUME_DIR/redis_billing_center/data/$port" \
                    "$DATA_VOLUME_DIR/redis_billing_center/conf/$port" \
                    "$DATA_VOLUME_DIR/redis_billing_center/log/$port"

                # 默认集群配置为空
                config_cluster=""

                # 添加集群配置
                if [ "${is_redis_cluster,,}" = "y" ]; then
                    # 使用 heredoc 将多行文本赋值给变量
                    config_cluster=$(
                        cat <<EOF
### 复制（主从同步）
# 是否为复制只读
slave-read-only yes

# 主节点 密码
masterauth "$REDIS_PASSWORD_BILLING_CENTER"

### 集群配置
# 开启集群模式至少三个主节点
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 15000

# #######CLUSTER DOCKER/NAT support#######
# 集群和哨兵不能使用 docker 的 NAT 模式 使用 host 模式
# 参考:https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/
# cluster-announce-ip redis-$IMG_VERSION_REDIS-$port
# cluster-announce-ip $HOST_INTRANET_IP

cluster-announce-ip $ip_node
cluster-announce-port $port
cluster-announce-bus-port 1$port
EOF
                    )

                fi

                # redis.conf 配置文件
                content=$(
                    cat <<EOL
# Redis 配置文件
######################

### 一般设置
# 绑定 IP (默认情况下,Redis 只允许本地连接)
# bind 127.0.0.1 $ip_node
# bind 127.0.0.1
bind 0.0.0.0

# Redis 监听端口 (默认为 6379)
port $port

# 启用保护模式:no, 关闭 docker 外部才能访问。
protected-mode no

# 设置密码
requirepass "$REDIS_PASSWORD_BILLING_CENTER"

### 客户端设置
# 客户端空闲超时时间(单位:秒),设置成 0 则表示不限制客户端空闲时间
timeout 0

# 最大客户端连接数,默认为 10000
maxclients 10000

### 数据存储
# 指定数据文件存放目录
dir ./

# 如果至少有 1 个 key 在 900 秒内被修改了,则生成 RDB 文件
save 900 1

# 如果至少有 10 个 key 在 300 秒内被修改了,则生成 RDB 文件
save 300 10

# 如果至少有 10000 个 key 在 60 秒内被修改了,则生成 RDB 文件
save 60 10000

# RDB 文件名称
dbfilename dump.rdb

# 是否启用 RDB 文件压缩
rdbcompression yes

# 是否使用 CRC64 校验 RDB 文件
rdbchecksum yes

### AOF 
# 启用 AOF 持久化
appendonly yes

# AOF 历史策略
appendfsync everysec

# AOF 文件名称
appendfilename "appendonly.aof"

# 是否重写 AOF 文件
auto-aof-rewrite-min-size 64mb
auto-aof-rewrite-percentage 100

### 日志记录
# 日志等级
loglevel notice

# 日志输出类型
logfile /var/log/redis/redis-server.log

### 系统资源限制
# TCP backlog,根据指定的数量来控制 TCP 连接数
tcp-backlog 511

### 内存管理
# Redis 最大使用内存
# maxmemory 0

# Redis 内存回收策略
maxmemory-policy volatile-lru

# 指定内存样本大小
maxmemory-samples 5

$config_cluster

# ####### CLUSTER DOCKER/NAT support #######

### 其他配置
# 数据库 index 默认为 0
# databases 0

EOL
                )

                # 覆盖写入
                over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content" "$DATA_VOLUME_DIR/redis_billing_center/conf/$port/redis.conf"
            done

            log_info "已删除 redis_billing_center 历史数据"
        else
            log_info "未删除 redis_billing_center 历史数据"
        fi

        # 网络配置
        cat >>"$docker_compose_file" <<-EOM
networks: # 网络配置
  $BRIDGE_REDIS_BILLING_CENTER: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_REDIS_BILLING_CENTER # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_REDIS_BILLING_CENTER" # 子网
          gateway: "$GATEWAY_REDIS_BILLING_CENTER" # 网关
EOM
        # 启动 redis 容器
        start_db_redis_billing_center

        # 创建 redis 集群
        if [ "$all_remove_data" == "y" ] && [ "$is_redis_cluster" = "y" ]; then
            log_info "redis 集群开启"
            redis_name="redis-$IMG_VERSION_REDIS-$REDIS_BASE_PORT_BILLING_CENTER"
            # 创建 redis 集群 执行命令 输入 yes
            REDIS_CLI_COMMAND="echo yes | redis-cli -h $redis_name -p $REDIS_BASE_PORT_BILLING_CENTER -a $REDIS_PASSWORD_BILLING_CENTER --cluster-replicas 1 --cluster create $cluster_urls"

            # 打印交互命令
            log_debug "执行命令: sudo docker exec -it $redis_name /bin/bash -c \"$REDIS_CLI_COMMAND\""

            # 执行命令不使用交互
            sudo docker exec -i "$redis_name" /bin/bash -c "$REDIS_CLI_COMMAND"
            log_info "redis 集群创建完成"
        fi
    }

    log_timer "redis 启动完毕" run

    log_info "redis_billing_center 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 停止并删除 redis 数据库(billing center)
delete_db_redis_billing_center() {
    log_debug "run delete_db_redis_billing_center"

    local is_delete
    is_delete=$(read_user_input "确认停止 redis_billing_center 服务并删除数据吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        # 停止容器
        stop_db_redis_billing_center

        # 删除数据库数据
        sudo rm -rf "$DATA_VOLUME_DIR/redis_billing_center"
    fi
}

### content from db/redis.sh
# 启动 redis 容器
start_db_redis() {
    log_debug "run start_db_redis"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS" up -d # 启动容器
}

# 停止 redis 容器
stop_db_redis() {
    log_debug "run stop_db_redis"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS" down || true
}

# 重启 redis 容器
restart_db_redis() {
    log_debug "run restart_db_redis"
    stop_db_redis
    start_db_redis
}

# 创建 redis 数据库
install_db_redis() {
    log_debug "run install_db_redis"

    # shellcheck disable=SC2329
    run() {
        local is_redis_cluster # 是否创建 redis 集群 默认不创建
        local all_remove_data  # 是否删除历史数据 默认不删除

        # 根据运行模式决定是否询问
        is_redis_cluster=$(read_user_input "[1/2]是否创建 redis 集群(默认n) [y|n]? " "n")
        all_remove_data=$(read_user_input "[2/2]是否删除 redis (默认n) [y|n]? " "n")

        if [ ! -d "$DATA_VOLUME_DIR" ]; then
            # 如果不存在则创建
            setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
        fi

        setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/redis"

        # ? ===============重要提示===============

        # 由于 docker 中创建 redis sentinel 无法使用自定义网络和 docker0 网络通信
        # 集群和哨兵不能使用 docker 的 NAT 模式 使用 host 模式
        # 需要使用 --net=host 的方式创建,外部访问需要打开对应端口
        # 参考官网: https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/

        # ? ===============重要提示===============

        # 创建一个名为 docker-compose.yaml 的新文件
        local docker_compose_file="$DOCKER_COMPOSE_FILE_REDIS"

        # 如果存在 docker-compose.yaml 执行docker compose down
        if [ -f "$docker_compose_file" ]; then
            sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS" down || true # 删除容器
            touch "$docker_compose_file"
        fi
        cat >"$docker_compose_file" <<-EOM
services:
EOM

        # 单节点,将主从节点设置为 1，从节点设置为 0
        if [ "$is_redis_cluster" == "n" ]; then
            MASTER_COUNT=1
            SLAVE_COUNT=0
        fi

        cluster_urls="" # 集群节点地址
        redis_ips=""    # ip地址拼接
        # 追加写入 docker-compose 配置文件
        for ((port = REDIS_BASE_PORT; port < REDIS_BASE_PORT + MASTER_COUNT + SLAVE_COUNT; port++)); do
            port_cluster=$((port + 10000))                                     # port_cluster 自增 集群监控端口
            ip_node="$IPV4_BASE_REDIS.$(((port - REDIS_BASE_PORT + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关

            DOCKER_NAMES+=("redis-$IMG_VERSION_REDIS-$port")      # 增加主节点
            cluster_urls+="redis-$IMG_VERSION_REDIS-$port:$port " # 集群节点 名称
            redis_ips+="$ip_node "                                # 集群节点地址

            # 追加写入主节点 docker-compose 配置文件
            cat >>"$docker_compose_file" <<-EOM

  redis-$IMG_VERSION_REDIS-$port:
    image: 'redis:$IMG_VERSION_REDIS'
    restart: always
    container_name: redis-$IMG_VERSION_REDIS-$port
    user: '$DB_UID:$DB_GID' # DOCKERFILE 中设置的用户
    volumes:
      - $DATA_VOLUME_DIR/redis/data/$port:/data
      - $DATA_VOLUME_DIR/redis/conf/$port:/usr/local/etc/redis # 配置文件需要指定文件夹否则会无法写入
      - $DATA_VOLUME_DIR/redis/log/$port:/var/log/redis

    command: [/usr/local/etc/redis/redis.conf] # 指定配置文件重新加载

    ports: # 映射端口，对外提供服务
      - "$port:$port" # redis 的服务端口
      - "$port_cluster:$port_cluster" # redis 集群监控端口
    # stdin_open: true # 标准输入打开
    # tty: true # 终端打开
    # privileged: true # 拥有容器内命令执行的权限

    networks: # docker 网络设置
      $BRIDGE_REDIS: # 网络名称
          ipv4_address: $ip_node
EOM
        done

        # 删除历史数据 redis
        if [ "$all_remove_data" == "y" ]; then

            # 删除历史数据
            sudo rm -rf "$DATA_VOLUME_DIR/redis"

            if [ ! -d "$DATA_VOLUME_DIR" ]; then
                # 如果不存在则创建
                setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
            fi

            # 创建新目录
            setup_directory "$DB_UID" "$DB_GID" 755 \
                "$DATA_VOLUME_DIR/redis" \
                "$DATA_VOLUME_DIR/redis/data" \
                "$DATA_VOLUME_DIR/redis/conf" \
                "$DATA_VOLUME_DIR/redis/log"

            # 删除原来配置 使用新建的配置文件
            for ((port = REDIS_BASE_PORT; port < REDIS_BASE_PORT + MASTER_COUNT + SLAVE_COUNT; port++)); do

                ip_node="$IPV4_BASE_REDIS.$(((port - REDIS_BASE_PORT + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关
                setup_directory "$DB_UID" "$DB_GID" 755 \
                    "$DATA_VOLUME_DIR/redis/data/$port" \
                    "$DATA_VOLUME_DIR/redis/conf/$port" \
                    "$DATA_VOLUME_DIR/redis/log/$port"

                # 默认集群配置为空
                config_cluster=""

                # 添加集群配置
                if [ "${is_redis_cluster,,}" = "y" ]; then
                    # 使用 heredoc 将多行文本赋值给变量
                    config_cluster=$(
                        cat <<EOF
### 复制（主从同步）
# 是否为复制只读
slave-read-only yes

# 主节点 密码
masterauth "$REDIS_PASSWORD"

### 集群配置
# 开启集群模式至少三个主节点
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 15000

# #######CLUSTER DOCKER/NAT support#######
# 集群和哨兵不能使用 docker 的 NAT 模式 使用 host 模式
# 参考:https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/
# cluster-announce-ip redis-$IMG_VERSION_REDIS-$port
# cluster-announce-ip $HOST_INTRANET_IP

cluster-announce-ip $ip_node
cluster-announce-port $port
cluster-announce-bus-port 1$port
EOF
                    )

                fi

                # redis.conf 配置文件
                content=$(
                    cat <<EOL
# Redis 配置文件
######################

### 一般设置
# 绑定 IP (默认情况下,Redis 只允许本地连接)
# bind 127.0.0.1 $ip_node
# bind 127.0.0.1
bind 0.0.0.0

# Redis 监听端口 (默认为 6379)
port $port

# 启用保护模式:no, 关闭 docker 外部才能访问。
protected-mode no

# 设置密码
requirepass "$REDIS_PASSWORD"

### 客户端设置
# 客户端空闲超时时间(单位:秒),设置成 0 则表示不限制客户端空闲时间
timeout 0

# 最大客户端连接数,默认为 10000
maxclients 10000

### 数据存储
# 指定数据文件存放目录
dir ./

# 如果至少有 1 个 key 在 900 秒内被修改了,则生成 RDB 文件
save 900 1

# 如果至少有 10 个 key 在 300 秒内被修改了,则生成 RDB 文件
save 300 10

# 如果至少有 10000 个 key 在 60 秒内被修改了,则生成 RDB 文件
save 60 10000

# RDB 文件名称
dbfilename dump.rdb

# 是否启用 RDB 文件压缩
rdbcompression yes

# 是否使用 CRC64 校验 RDB 文件
rdbchecksum yes

### AOF 
# 启用 AOF 持久化
appendonly yes

# AOF 历史策略
appendfsync everysec

# AOF 文件名称
appendfilename "appendonly.aof"

# 是否重写 AOF 文件
auto-aof-rewrite-min-size 64mb
auto-aof-rewrite-percentage 100

### 日志记录
# 日志等级
loglevel notice

# 日志输出类型
logfile /var/log/redis/redis-server.log

### 系统资源限制
# TCP backlog,根据指定的数量来控制 TCP 连接数
tcp-backlog 511

### 内存管理
# Redis 最大使用内存
# maxmemory 0

# Redis 内存回收策略
maxmemory-policy volatile-lru

# 指定内存样本大小
maxmemory-samples 5

$config_cluster

# ####### CLUSTER DOCKER/NAT support #######

### 其他配置
# 数据库 index 默认为 0
# databases 0

EOL
                )

                # 覆盖写入
                over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content" "$DATA_VOLUME_DIR/redis/conf/$port/redis.conf"
            done

            log_info "已删除 redis 历史数据"
        else
            log_info "未删除 redis 历史数据"
        fi

        # 网络配置
        cat >>"$docker_compose_file" <<-EOM
networks: # 网络配置
  $BRIDGE_REDIS: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_REDIS # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_REDIS" # 子网
          gateway: "$GATEWAY_REDIS" # 网关
EOM
        # 启动 redis 容器
        start_db_redis

        # 创建 redis 集群
        if [ "$all_remove_data" == "y" ] && [ "$is_redis_cluster" = "y" ]; then
            log_info "redis 集群开启"
            redis_name="redis-$IMG_VERSION_REDIS-$REDIS_BASE_PORT"
            # 创建 redis 集群 执行命令 输入 yes
            REDIS_CLI_COMMAND="echo yes | redis-cli -h $redis_name -p $REDIS_BASE_PORT -a $REDIS_PASSWORD --cluster-replicas 1 --cluster create $cluster_urls"

            # 打印交互命令
            log_debug "执行命令: sudo docker exec -it $redis_name /bin/bash -c \"$REDIS_CLI_COMMAND\""

            # 执行命令不使用交互
            sudo docker exec -i "$redis_name" /bin/bash -c "$REDIS_CLI_COMMAND"
            log_info "redis 集群创建完成"
        fi
    }

    log_timer "redis 启动完毕" run

    log_info "redis 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

# 停止并删除 redis 数据库
delete_db_redis() {
    log_debug "run delete_db_redis"

    local is_delete
    is_delete=$(read_user_input "确认停止 redis 服务并删除数据吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        # 停止容器
        stop_db_redis

        # 删除数据库数据
        sudo rm -rf "$DATA_VOLUME_DIR/redis"
    fi
}

### content from billing-center/cli.sh
# 通过 CLI 执行命令
billing_center_cli() {
  log_debug "run billing_center_cli"

  local arg=$1

  # 在容器中执行
  log_debug "执行命令: sudo docker exec -it billing-center /bin/sh -c \"/home/billing-center/billing-center ${arg}\""

  sudo docker exec -it billing-center /bin/sh -c "/home/billing-center/billing-center ${arg}"

  # 重启容器
  # log_info "重启容器"
  # docker_billing_center_restart
}

# 打印 CA 证书的字节信息
ca_cert_byte_print() {
  log_debug "run ca-cert-byte-print"
  billing_center_cli "ca-cert-byte-print -n 32"
}

### content from billing-center/compose.sh
# 创建 billing_center docker compose文件
create_docker_compose_billing_center() {
  log_debug "run create_docker_compose_billing_center"

  # 参数
  # $1 版本号, 默认 latest
  local version="${1:-latest}"

  # 如果存在 docker-compose.yaml 文件就删除
  local docker_compose_file="$DOCKER_COMPOSE_FILE_BILLING_CENTER"
  if [ -f "$docker_compose_file" ]; then
    sudo rm -f "$docker_compose_file"
  fi

  local img_prefix
  img_prefix=$(get_img_prefix)

  #  创建新的 docker-compose-billing_center-client.yaml 文件
  cat >"$docker_compose_file" <<-EOM
# 运行命令:sudo docker compose -f $docker_compose_file -p "$DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER" up -d

services:
  billing-center:
    image: $img_prefix/billing-center:$version
    restart: always
    container_name: billing-center
    user: '$JPZ_UID:$JPZ_GID' # DOCKERFILE 中设置的用户
    volumes:
      - $DATA_VOLUME_DIR/billing-center/config:/home/billing-center/config
      - $DATA_VOLUME_DIR/billing-center/logs:/home/billing-center/logs
      - $DATA_VOLUME_DIR/billing-center/nginx:/etc/nginx
    ports:
      - '80:80' # http 端口
      - '443:443' # https 端口
    networks: # docker 网络设置
      $BRIDGE_BILLING_CENTER: # 网络名称
        ipv4_address: $IPV4_BASE_BILLING_CENTER.2 # IP地址
    
    # 健康检查
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -sk https://localhost/api/v1/helper/version | grep 'request_id'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

networks: # 网络配置
  $BRIDGE_BILLING_CENTER: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_BILLING_CENTER # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_BILLING_CENTER" # 子网
          gateway: "$GATEWAY_BILLING_CENTER" # 网关
EOM

  # 打印日志
  log_info "$docker_compose_file create success"
}

### content from billing-center/config.sh
# 复制 billing-center nginx 配置文件
copy_billing_center_nginx_config() {

    log_debug "run copy_billing_center_nginx_config"

    dir_billing_center="$DATA_VOLUME_DIR/billing-center/nginx"

    sudo rm -rf "$dir_billing_center"

    # shellcheck disable=SC2329
    run_copy_config() {
        # 复制配置文件到 volume 目录
        sudo docker cp temp_container_blog_billing_center:/etc/nginx "$DATA_VOLUME_DIR/billing-center" # 复制配置文件
    }

    docker_create_billing_center_temp_container run_copy_config "latest"

    # 如果当前目录下 certs_nginx 文件夹不存在则输出提示
    if [ ! -d "$CERTS_NGINX" ]; then
        echo "========================================"
        echo "    请将证书 $CERTS_NGINX 文件夹放到当前目录"
        echo "    证书文件夹结构如下:"
        echo "    $CERTS_NGINX"
        echo "    ├── cert.key"
        echo "    └── cert.pem"
        echo "========================================"
        log_error "请将证书 $CERTS_NGINX 文件夹放到当前目录"
        exit 1
    fi

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 \
        "$DATA_VOLUME_DIR/billing-center" \
        "$DATA_VOLUME_DIR/billing-center/nginx" \
        "$DATA_VOLUME_DIR/billing-center/nginx/ssl"

    # 判断当前目录是否为空
    if [ -z "$(ls -A "$CERTS_NGINX")" ]; then
        log_error "证书目录 $CERTS_NGINX 为空, 请添加证书文件"

        ssl_msg "$RED"
        exit 1
    fi

    # 将证书 certs_nginx 目录复制到 volume/billing-center/nginx/ssl 目录
    # **注意这里的引号不要将星号包裹,否则会报错 cp: 对 '/path/to/volume/certs_nginx/*' 调用 stat 失败: 没有那个文件或目录**
    sudo cp -r "$CERTS_NGINX"/* "$DATA_VOLUME_DIR/billing-center/nginx/ssl/"

    # 修改证书目录权限
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR/billing-center/nginx/ssl/"

    log_info "billing-center 复制 nginx 配置文件到 volume success"
}

# 更新 billing-center 配置文件中的数据库密码
server_update_password_key_billing_center() {
    log_debug "run server_update_password_key_billing_center"

    local config_dir="$DATA_VOLUME_DIR/billing-center/config"

    # pgsql 密码更新
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$POSTGRES_PASSWORD_BILLING_CENTER\"%" "$config_dir/pgsql.yaml"

    # redis 密码更新(所有节点)
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$REDIS_PASSWORD_BILLING_CENTER\"%" "$config_dir/redis.yaml"

    log_info "billing-center 更新数据库密码配置 success"
}

# 复制 billing-center server 配置文件
copy_billing_center_server_config() {

    log_debug "run copy_billing_center_server_config"

    dir_billing_center="$DATA_VOLUME_DIR/billing-center/config"

    sudo rm -rf "$dir_billing_center"

    # 如果 bc-config 和 cert 目录存在不存在就提示用户准备好配置文件
    if [ ! -d "./bc-config" ]; then
        local msg=""
        msg+="\n请将 billing_center 配置文件准备好并放置到以下目录: "
        msg+="\n    ./bc-config (配置文件)"
        msg+="\n"
        log_warn "$msg"
        log_warn "bc-config 目录不存在, 请先准备好配置文件后再进行全新安装"
        exit 1
    fi

    # 复制配置文件到 volume 目录
    cp -r "./bc-config/" "$DATA_VOLUME_DIR/billing-center/config/"

    # 更新配置文件中的密码
    server_update_password_key_billing_center

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    # 修改配置目录权限
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR/billing-center/config/"

    log_info "billing-center 复制后端配置文件到 volume success"
}

### content from billing-center/deploy.sh
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

### content from billing-center/log.sh
# 查看 billing-center 日志
billing_center_logs() {
    log_debug "run billing_center_logs"

    printf "========================================\n"
    printf "    [ 1 ] 查看 billing-center 常规日志\n"
    printf "    [ 2 ] 查看 billing-center 验证码日志\n"
    printf "========================================\n"
    local user_input
    user_input=$(read_user_input "请输入对应数字查看日志 [1-2]? " "1")

    local log_file filter_cmd

    case "$user_input" in
    1)
        # 常规日志
        log_file="$DATA_VOLUME_DIR/billing-center/logs/app.log"
        filter_cmd=()
        ;;
    2)
        # 验证码日志
        log_file="$DATA_VOLUME_DIR/billing-center/logs/app.log"
        filter_cmd=("grep" "发送验证码")
        ;;
    *)
        # 无效输入
        log_warn "无效输入：$user_input"
        return 1
        ;;
    esac

    # 检查日志文件是否存在
    if [ ! -f "$log_file" ]; then
        log_warn "$log_file, 日志文件不存在或当前无日志可查看"
        return 1
    fi

    # 构建命令：tail -f + 可选过滤
    if [ ${#filter_cmd[@]} -eq 0 ]; then
        tail -f "$log_file"
    else
        tail -f "$log_file" | "${filter_cmd[@]}"
    fi
}

### content from server/cli.sh
# 通过 CLI 执行命令
blog_server_cli() {
  log_debug "run blog_server_cli"

  local arg=$1

  # 在容器中执行
  log_debug "执行命令: sudo docker exec -it blog-server /bin/sh -c \"/home/blog-server/blog-server ${arg}\""

  sudo docker exec -it blog-server /bin/sh -c "/home/blog-server/blog-server ${arg}"

  # 重启容器
  log_info "重启容器"
  docker_server_restart
}

# 插入测试数据
insert_demo_data() {
  log_debug "run insert_demo_data"
  blog_server_cli "insert-demo-data"
}

# 注册管理员用户
register_admin() {
  log_debug "run register_admin"
  blog_server_cli "register-admin"
}

# 注册管理员用户
reset_password() {
  log_debug "run reset_password"
  blog_server_cli "reset-password"
}

### content from server/compose.sh
# 创建 server docker compose文件
create_docker_compose_server() {
  log_debug "run create_docker_compose_server"

  # 参数
  # $1 版本号, 默认 latest
  local version="${1:-latest}"

  # 如果存在 docker-compose.yaml 文件就删除
  local docker_compose_file="$DOCKER_COMPOSE_FILE_SERVER"
  if [ -f "$docker_compose_file" ]; then
    sudo rm -f "$docker_compose_file"
  fi

  local img_prefix
  img_prefix=$(get_img_prefix)

  #  创建新的 docker-compose-server-client.yaml 文件
  cat >"$docker_compose_file" <<-EOM
# 博客项目前后端分离部署 docker compose 配置文件
# 运行命令:sudo docker compose -f $docker_compose_file -p "$DOCKER_COMPOSE_PROJECT_NAME_SERVER" up -d

services:
  # blog-server 后端服务
  blog-server:
    image: $img_prefix/blog-server:$version
    restart: always
    container_name: blog-server
    user: '$SERVER_UID:$SERVER_GID' # DOCKERFILE 中设置的用户
    # stdin_open: true # 标准输入打开
    # tty: true # 终端打开
    # privileged: true # 拥有容器内命令执行的权限
    volumes:
      - $DATA_VOLUME_DIR/blog-server/config:/home/blog-server/config
      - $DATA_VOLUME_DIR/blog-server/uploads:/home/blog-server/uploads
      - $DATA_VOLUME_DIR/blog-server/logs:/home/blog-server/logs
    ports: # 映射端口，对外提供服务
      - '5426:5426' # blog-server 的服务端口
    networks: # docker 网络设置
      $BRIDGE_SERVER: # 网络名称
        ipv4_address: $IPV4_BASE_SERVER.2 # IP地址
    
    # 健康检查
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s http://localhost:5426/api/v1/is-setup | grep 'request_id'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120

networks: # 网络配置
  $BRIDGE_SERVER: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_SERVER # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_SERVER" # 子网
          gateway: "$GATEWAY_SERVER" # 网关
EOM

  # 打印日志
  log_info "$docker_compose_file create success"
}

### content from server/config.sh
# 设置 server is_setup
server_set_is_setup() {
    log_debug "run server_is_setup"

    local setup_flag="$1"

    # app 修改
    if [ "$setup_flag" == true ]; then
        sudo sed -r -i "s|is_setup: false|is_setup: true|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"
    else
        sudo sed -r -i "s|is_setup: true|is_setup: false|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"
    fi

    log_info "server 设置 is_setup=$setup_flag success"
}

# 设置 server es 是否使用用户自定义 ca 证书
server_set_es_use_ca_cert() {
    log_debug "run server_set_es_use_ca_cert"

    local setup_flag="$1"

    # app 修改
    if [ "$setup_flag" == true ]; then
        sudo sed -r -i "s|use_ca_cert: false|use_ca_cert: true|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"
    else
        sudo sed -r -i "s|use_ca_cert: true|use_ca_cert: false|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"
    fi

    log_info "server 设置 es use_ca_cert=$setup_flag success"
}

# 设置 server es jwt secret key
server_update_jwt_secret_key() {
    log_debug "run server_update_jwt_secret_key"
    # 生成一个随机64位的 secret key
    local secret_key
    secret_key="$(openssl rand -hex 32)"
    log_debug "generated jwt secret key: $secret_key"

    # 使用单引号包围整个sed表达式，并且正确转义双引号
    sudo sed -i "s%secret_key:[[:space:]]*\"[^\"]*\"%secret_key: \"$secret_key\"%" "$DATA_VOLUME_DIR/blog-server/config/jwt.yaml"
}

# 更新 server 配置文件中的数据库密码
server_update_password_key() {
    log_debug "run server_update_password_key"

    local config_dir="$DATA_VOLUME_DIR/blog-server/config"

    # pgsql 密码更新
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$POSTGRES_PASSWORD\"%" "$config_dir/pgsql.yaml"

    # redis 密码更新(所有节点)
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$REDIS_PASSWORD\"%" "$config_dir/redis.yaml"

    # es 密码更新
    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$ELASTIC_PASSWORD\"%" "$config_dir/es.yaml"

    log_info "server 更新数据库密码配置 success"
}

# 设置 server 主机地址
server_set_host() {
    log_debug "run server_is_setup"

    local host_addr="$1"

    # 替换 host 地址带有双引号的情况
    sudo sed -r -i "s|host: \"http[s]*://[a-z0-9.:]*\"|host: \"$host_addr\"|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"

    # 替换 host 地址不带双引号的情况
    sudo sed -r -i "s|host: http[s]*://[a-z0-9.:]*|host: $host_addr|g" "$DATA_VOLUME_DIR/blog-server/config/app.yaml"

    log_info "server 设置 host=$host_addr success"
}

# 复制 blog_server 配置文件
copy_server_config() {
    log_debug "run copy_server_config"
    # 是否已经使用当前工具安装数据库, 默认是
    local web_set_db="${1-n}"

    log_debug "web_set_db=$web_set_db"

    dir_server="$DATA_VOLUME_DIR/blog-server/config"

    sudo rm -rf "$dir_server"

    # shellcheck disable=SC2329
    run_copy_config() {
        # 复制配置文件到 volume 目录 不能使用 sudo docker compose cp，因为yaml中设置了 volume 会覆盖掉
        sudo docker cp temp_container_blog_server:/home/blog-server/config "$dir_server" # 复制配置文件
    }

    docker_create_server_temp_container run_copy_config "latest"

    # 将配置文件中ip地址替换为服务器内网ip地址(s双引号)
    # 严格匹配 IPv4(避免匹配空串)
    sudo sed -r -i "s|^([[:space:]]*host:[[:space:]]*)(\"?)[0-9]{1,3}(\.[0-9]{1,3}){3}(\"?)|\1\2$HOST_INTRANET_IP\4|g" "$DATA_VOLUME_DIR/blog-server/config/pgsql.yaml"

    # redis 配置修改
    sudo sed -r -i "s|^([[:space:]]*-[[:space:]]*host:[[:space:]]*)(\"?)[0-9]{1,3}(\.[0-9]{1,3}){3}(\"?)|\1\2$HOST_INTRANET_IP\4|g" "$DATA_VOLUME_DIR/blog-server/config/redis.yaml"

    # es 配置修改
    sudo sed -r -i "s|- \"https://[0-9.:]*\"|- \"https://$HOST_INTRANET_IP:9200\"|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"
    sudo sed -r -i "s|- https://[0-9.:]*|- \"https://$HOST_INTRANET_IP:9200\"|g" "$DATA_VOLUME_DIR/blog-server/config/es.yaml"

    # 更新 jwt secret key
    server_update_jwt_secret_key

    # 更新数据库密码配置
    server_update_password_key

    # app 设置
    if [ "$web_set_db" == "y" ]; then
        server_set_is_setup false
    else
        server_set_is_setup true

        # 将 es 的 ca.crt 文件内容更新到 es.yaml 文件中
        if [ -f "$CA_CERT_DIR/ca.crt" ]; then
            update_yaml_block "$DATA_VOLUME_DIR/blog-server/config/es.yaml" "ca_cert: |" "$CA_CERT_DIR/ca.crt"
        fi

        # 设置 es 使用 ca 证书
        server_set_es_use_ca_cert true
    fi

    # 设置 host 地址
    server_set_host "https://$DOMAIN_NAME"

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$SERVER_UID" "$SERVER_GID" 755 "$DATA_VOLUME_DIR/blog-server"

    log_info "server 复制配置文件到 volume success"
}

### content from server/deploy.sh
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

### content from server/log.sh
# 查看 blog-server 日志
blog_server_logs() {
    log_debug "run blog_server_logs"

    printf "========================================\n"
    printf "    [ 1 ] 查看 blog-server 常规日志\n"
    printf "    [ 2 ] 查看 blog-server 验证码日志\n"
    # printf "    [ 3 ] 查看 blog-server 错误日志\n"
    printf "========================================\n"
    local user_input
    user_input=$(read_user_input "请输入对应数字查看日志 [1-2]? " "1")

    local log_file filter_cmd

    case "$user_input" in
    1)
        # 常规日志
        log_file="$DATA_VOLUME_DIR/blog-server/logs/app.log"
        filter_cmd=()
        ;;
    2)
        # 验证码日志
        log_file="$DATA_VOLUME_DIR/blog-server/logs/app.log"
        filter_cmd=("grep" "发送验证码")
        ;;
    # 3)
    #     # 错误日志
    #     log_file="$DATA_VOLUME_DIR/blog-server/logs/error.log"
    #     filter_cmd=()
    #     ;;
    *)
        # 无效输入
        log_warn "无效输入：$user_input"
        return 1
        ;;
    esac

    # 检查日志文件是否存在
    if [ ! -f "$log_file" ]; then
        log_warn "$log_file, 日志文件不存在或当前无日志可查看"
        return 1
    fi

    # 构建命令：tail -f + 可选过滤
    if [ ${#filter_cmd[@]} -eq 0 ]; then
        tail -f "$log_file"
    else
        tail -f "$log_file" | "${filter_cmd[@]}"
    fi
}

### content from client/compose.sh
# 创建 client docker compose文件
create_docker_compose_client() {
  log_debug "run create_docker_compose_client"

  # 参数
  # $1 版本号, 默认 latest
  local version="${1:-latest}"

  # 如果存在 docker-compose.yaml 文件就删除
  local docker_compose_file="$DOCKER_COMPOSE_FILE_CLIENT"
  if [ -f "$docker_compose_file" ]; then
    sudo rm -f "$docker_compose_file"
  fi

  local img_prefix
  img_prefix=$(get_img_prefix)
  # 创建新的 docker-compose-server-client.yaml 文件
  cat >"$docker_compose_file" <<-EOM
# 博客项目前后端分离部署 docker compose 配置文件
# 运行命令:sudo docker compose -f $docker_compose_file up -d

services:
  blog-client:
    image: $img_prefix/blog-client:$version
    container_name: blog-client
    restart: always
    user: '$CLIENT_UID:$CLIENT_GID' # 使用 nginx 默认用户 101:101
    # stdin_open: true # 标准输入打开
    # tty: true # 终端打开
    # privileged: true # 拥有容器内命令执行的权限
    # depends_on: # 添加依赖关系
    #   - blog-server # client 依赖于 server
    volumes:
      - $DATA_VOLUME_DIR/blog-client/nginx:/etc/nginx
    ports:
      - '80:80' # http 端口
      - '443:443' # https 端口
    networks: # docker 网络设置
      $BRIDGE_CLIENT: # 网络名称
        ipv4_address: $IPV4_BASE_CLIENT.3 # IP地址

networks: # 网络配置
  $BRIDGE_CLIENT: # 网络名称
    driver: bridge # 网络驱动
    name: $BRIDGE_CLIENT # 网络名称
    ipam: # IP地址管理
      config: # IP地址配置
        - subnet: "$SUBNET_CLIENT" # 子网
          gateway: "$GATEWAY_CLIENT" # 网关
EOM

  # 打印日志
  log_info "$docker_compose_file 创建成功"
}

### content from client/config.sh
# 复制 blog_client 配置文件
copy_client_config() {

    log_debug "run copy_client_config"

    dir_client="$DATA_VOLUME_DIR/blog-client/nginx"

    sudo rm -rf "$dir_client"

    # shellcheck disable=SC2329
    run_copy_config() {
        # 复制配置文件到 volume 目录
        sudo docker cp temp_container_blog_client:/etc/nginx "$DATA_VOLUME_DIR/blog-client" # 复制配置文件
    }

    docker_create_client_temp_container run_copy_config "latest"

    # 如果当前目录下 certs_nginx 文件夹不存在则输出提示
    if [ ! -d "$CERTS_NGINX" ]; then
        echo "========================================"
        echo "    请将证书 $CERTS_NGINX 文件夹放到当前目录"
        echo "    证书文件夹结构如下:"
        echo "    $CERTS_NGINX"
        echo "    ├── cert.key"
        echo "    └── cert.pem"
        echo "========================================"
        log_error "请将证书 $CERTS_NGINX 文件夹放到当前目录"
        exit 1
    fi

    # 目录已经存在，主要是修改权限
    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        # 如果不存在则创建
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$CLIENT_UID" "$CLIENT_GID" 755 \
        "$DATA_VOLUME_DIR/blog-client" \
        "$DATA_VOLUME_DIR/blog-client/nginx" \
        "$DATA_VOLUME_DIR/blog-client/nginx/ssl"

    # 判断当前目录是否为空
    if [ -z "$(ls -A "$CERTS_NGINX")" ]; then
        log_error "证书目录 $CERTS_NGINX 为空, 请添加证书文件"

        ssl_msg "$RED"
        exit 1
    fi

    # 将证书 certs_nginx 目录复制到 volume/blog-client/nginx/ssl 目录
    # **注意这里的引号不要将星号包裹,否则会报错 cp: 对 '/path/to/volume/certs_nginx/*' 调用 stat 失败: 没有那个文件或目录**
    sudo cp -r "$CERTS_NGINX"/* "$DATA_VOLUME_DIR/blog-client/nginx/ssl/"

    # 修改证书目录权限
    setup_directory "$CLIENT_UID" "$CLIENT_GID" 755 "$DATA_VOLUME_DIR/blog-client/nginx/ssl/"

    # 修改 nginx.conf 配置文件中的 blog-server 地址为宿主机内网 IP 地址
    sudo sed -r -i \
        "s/http:\/\/blog-server:5426/http:\/\/$HOST_INTRANET_IP:5426/g" \
        "$DATA_VOLUME_DIR/blog-client/nginx/nginx.conf"

    log_info "client 复制配置文件到 volume success"
}

### content from client/deploy.sh
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

main() {
    # 免责声明
    disclaimer_msg
    # 检查
    check

    # 没有参数情况显示选项
    if [ $# -eq 0 ]; then
        # 显示 logo 欢迎界面
        show_logo

        # 打印选项
        print_options "$DISPLAY_COLS" "${OPTIONS_ALL[@]}"

        # 处理用户输入
        handle_user_input "${OPTIONS_ALL[@]}"
    else
        # 校验是否是有效函数,
        for arg in "$@"; do
            if func=$(is_valid_func OPTIONS_ALL[@] "$arg"); then
                exec_func "$func"
            else
                echo "未找到与输入匹配的函数名称: $arg"
            fi
        done
    fi
}

# 调用主函数
main "$@"
