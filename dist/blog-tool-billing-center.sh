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
LOG_LEVEL="info"

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
# shellcheck disable=SC2034

RUN_MODE="pro"

DATA_VOLUME_DIR="$ROOT_DIR/volume"

BLOG_TOOL_ENV="$DATA_VOLUME_DIR/blog_tool_env"

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

IS_INSTALL_SOFTWARE=""

DOCKER_CE_SOURCES=(
    "https://mirrors.aliyun.com/docker-ce|阿里云公网"
    "http://mirrors.cloud.aliyuncs.com|阿里云内网"
    "http://mirrors.aliyuncs.com|阿里云内网经典"
    "https://mirrors.163.com/docker-ce|网易云"
    "https://mirrors.cernet.edu.cn/docker-ce|中国教育网"
    "https://mirrors.tuna.tsinghua.edu.cn/docker-ce|清华大学"
    "https://mirrors.huaweicloud.com/docker-ce|华为云"
    "https://mirrors.cmecloud.cn/docker-ce|中国移动云"
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

DOCKER_HUB_REGISTRY="docker.io" # docker hub 仓库地址
DOCKER_HUB_OWNER="jiaopengzi"   # docker hub 用户名

START_TIME=$(date +%s) # 记录开始时间
APP_NAME="jpz"         # 应用名称 不能包含大写字母和字符
DISPLAY_COLS=3         # 输出显示的列数, 用于输出对齐, 一般为 3, 可以根据实际情况调整

if command -v ifconfig >/dev/null 2>&1; then
    HOST_INTRANET_IP=$(ifconfig | sed -n '/^[eE]/,+3p' | grep 'inet ' | awk '{print $2}')

    HOST_INTRANET_MARK=$(ifconfig | sed -n '/^[eE]/,+3p' | grep 'inet ' | awk '{print $4}')
else
    HOST_INTRANET_IP="127.0.0.1"
    HOST_INTRANET_MARK="255.0.0.0"
fi

CA_CERT_DIR="$DATA_VOLUME_DIR/certs_ca"
CERT_DAYS_VALID=3650

IMG_VERSION_REDIS="8.4.0"    # redis 版本
IMG_VERSION_PGSQL="18.1"     # pgsql 版本
IMG_VERSION_PGSQL_MAJOR="18" # pgsql主要版本号

IMG_VERSION_ES="9.2.4"     # 7.17.28 8.18.1
IMG_VERSION_KIBANA="9.2.4" # 与 es 保持版本一致

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

BRIDGE_REGISTRY="$APP_NAME-registry$IMG_VERSION_REGISTRY-bridge-net" # 私有仓库 网桥
IPV4_BASE_REGISTRY="178.18.10"                                       # 私有仓库 内网起始 IP 段
SUBNET_REGISTRY="$IPV4_BASE_REGISTRY.0/24"                           # 私有仓库 子网网段
GATEWAY_REGISTRY="$IPV4_BASE_REGISTRY.1"                             # 私有仓库 网关

BRIDGE_PGSQL="$APP_NAME-pgsql-bridge-net" # pgsql 网桥
IPV4_BASE_PGSQL="178.18.11"               # pgsql 内网起始 IP 段
SUBNET_PGSQL="$IPV4_BASE_PGSQL.0/24"      # pgsql 子网网段
GATEWAY_PGSQL="$IPV4_BASE_PGSQL.1"        # pgsql 网关

POSTGRES_DOCKER_NAME="pgsql-$IMG_VERSION_PGSQL" # 服务名称

IPV4_ADDRESS_START=2
POSTGRES_IP="$IPV4_BASE_PGSQL.$((IPV4_ADDRESS_START % 256))" # 自增 从 2 开始, 1 为网关

BRIDGE_PGSQL_BILLING_CENTER="$APP_NAME-billing-center-pgsql-bridge-net" # pgsql 网桥
IPV4_BASE_PGSQL_BILLING_CENTER="178.18.12"                              # pgsql 内网起始 IP 段
SUBNET_PGSQL_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.0/24"      # pgsql 子网网段
GATEWAY_PGSQL_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.1"        # pgsql 网关

POSTGRES_DOCKER_NAME_BILLING_CENTER="pgsql-$IMG_VERSION_PGSQL-billing-center" # 服务名称

POSTGRES_IP_BILLING_CENTER="$IPV4_BASE_PGSQL_BILLING_CENTER.$((IPV4_ADDRESS_START % 256))" # 自增 从 2 开始, 1 为网关

MASTER_COUNT=3                            # 主节点数量
SLAVE_COUNT=3                             # 从节点数量
BRIDGE_REDIS="$APP_NAME-redis-bridge-net" # redis 网桥
IPV4_BASE_REDIS="178.18.13"               # redis 内网起始 IP 段
SUBNET_REDIS="$IPV4_BASE_REDIS.0/24"      # redis 子网网段
GATEWAY_REDIS="$IPV4_BASE_REDIS.1"        # redis 网关

REDIS_START_IP=$IPV4_BASE_REDIS.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
REDIS_END_IP=$IPV4_BASE_REDIS.$(((MASTER_COUNT + SLAVE_COUNT + 1) % 256))

BRIDGE_REDIS_BILLING_CENTER="$APP_NAME-redis-billing-center-bridge-net" # redis 网桥
IPV4_BASE_REDIS_BILLING_CENTER="178.18.14"                              # redis 内网起始 IP 段
SUBNET_REDIS_BILLING_CENTER="$IPV4_BASE_REDIS_BILLING_CENTER.0/24"      # redis 子网网段
GATEWAY_REDIS_BILLING_CENTER="$IPV4_BASE_REDIS_BILLING_CENTER.1"        # redis 网关

REDIS_START_IP_BILLING_CENTER=$IPV4_BASE_REDIS_BILLING_CENTER.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
REDIS_END_IP_BILLING_CENTER=$IPV4_BASE_REDIS_BILLING_CENTER.$(((MASTER_COUNT + SLAVE_COUNT + 1) % 256))

BRIDGE_ES="$APP_NAME-es-bridge-net" # es 网桥
IPV4_BASE_ES="178.18.15"            # es 内网起始 IP 段
SUBNET_ES="$IPV4_BASE_ES.0/24"      # es 子网网段
GATEWAY_ES="$IPV4_BASE_ES.1"        # es 网关

ES_START_IP=$IPV4_BASE_ES.$((2 % 256)) # ip_node 自增 从 2 开始, 1 为网关
ES_END_IP=$IPV4_BASE_ES.$(((ES_NODE_COUNT + 1) % 256))

ES_CLUSTER_NAME=docker-cluster # 集群名称
ES_LICENSE=basic               # 设置 es 的许可证, 默认为 basic
ES_PORT=9200                   # es 端口, 如果使用 127.0.0.1:9200 则表示只能本地访问
KIBANA_PORT=5601               # kibana 端口

MEM_LIMIT_ES="mem_limit: 1288490188"     # 内存限制 es (bytes)
MEM_LIMIT_KIBANA="mem_limit: 1073741824" # 内存限制 kibana

ES_JAVA_OPTS_ENV="- ES_JAVA_OPTS=-Xms512m -Xmx512m"

BRIDGE_SERVER="$APP_NAME-bridge-server" # server 网桥
IPV4_BASE_SERVER="178.18.16"            # SERVER 内网起始 IP 段
SUBNET_SERVER="$IPV4_BASE_SERVER.0/24"  # server 子网网段
GATEWAY_SERVER="$IPV4_BASE_SERVER.1"    # server 网关

BRIDGE_BILLING_CENTER="$APP_NAME-bridge-billing-center" # server 网桥
IPV4_BASE_BILLING_CENTER="178.18.17"                    # SERVER 内网起始 IP 段
SUBNET_BILLING_CENTER="$IPV4_BASE_BILLING_CENTER.0/24"  # server 子网网段
GATEWAY_BILLING_CENTER="$IPV4_BASE_BILLING_CENTER.1"    # server 网关

BRIDGE_CLIENT="$APP_NAME-bridge-client"    # client 网桥
IPV4_BASE_CLIENT="178.18.18"               # CLIENT 内网起始 IP 段
SUBNET_CLIENT="$IPV4_BASE_CLIENT.0/24"     # client 子网网段
GATEWAY_CLIENT="$IPV4_BASE_CLIENT.1"       # client 网关
CERTS_NGINX="$DATA_VOLUME_DIR/certs_nginx" # nginx 证书

DOCKER_COMPOS_DIR="$DATA_VOLUME_DIR/docker_compose_files"
DOCKER_COMPOSE_FILE_PGSQL="$DOCKER_COMPOS_DIR/compose-pgsql.yaml"
DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-pgsql-billing-center.yaml"
DOCKER_COMPOSE_FILE_REDIS="$DOCKER_COMPOS_DIR/compose-redis.yaml"
DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-redis-billing-center.yaml"
DOCKER_COMPOSE_FILE_ES="$DOCKER_COMPOS_DIR/compose-es.yaml"
DOCKER_COMPOSE_FILE_SERVER="$DOCKER_COMPOS_DIR/compose-server.yaml"
DOCKER_COMPOSE_FILE_BILLING_CENTER="$DOCKER_COMPOS_DIR/compose-billing-center.yaml"
DOCKER_COMPOSE_FILE_CLIENT="$DOCKER_COMPOS_DIR/compose-client.yaml"

DOCKER_COMPOSE_PROJECT_NAME_SERVER="$APP_NAME-server"
DOCKER_COMPOSE_PROJECT_NAME_PGSQL="$APP_NAME-pgsql"
DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER="$APP_NAME-pgsql-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_REDIS="$APP_NAME-redis"
DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER="$APP_NAME-redis-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_ES="$APP_NAME-es"
DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER="$APP_NAME-billing-center"
DOCKER_COMPOSE_PROJECT_NAME_CLIENT="$APP_NAME-client"

PY_SCRIPT_FILE="/tmp/embedded_python_main.py"

WEB_INSTALL_SERVER_TIPS="当前需要全新安装 server 服务，会使用初始化覆盖原有配置，是否进行全新安装 \n默认选择n [y|n]? "
WEB_SET_DB_TIPS="\n================================\n是否使用前端网页填写数据库信息?\n\n说明\n  如果自行单独设置数据就选择 y.\n  如果使用当前脚本工具安装了数据就选择 n.\n默认选择n [y|n]? "

# shellcheck disable=SC2034

OPTIONS_BILLING_CENTER=(
    "安装依赖软件:install_common_software"
    "新增必要运行用户:add_group_user"

    "安装 docker:install_docker"

    "拉取生产数据库镜像:pull_docker_image_pro_db_billing_center"
    "安装所有数据库-计费中心:install_database_billing_center"
    "删除所有数据库-计费中心:delete_database_billing_center"

    "拉取 billing center 镜像:docker_pull_billing_center"

    "安装 billing center 服务:docker_billing_center_install"
    "打印计费中心 CA 证书:ca_cert_byte_print"

    "启动 billing center 服务:docker_billing_center_start"
    "停止 billing center 服务:docker_billing_center_stop"
    "重启 billing center 服务:docker_billing_center_restart"

    "升级或回滚 billing center:start_or_rollback_billing_center_by_version"

    "删除 billing center 服务:docker_billing_center_delete"

    "删除 billing center 镜像:docker_rmi_billing_center"

    "监控 billing center 日志:billing_center_logs"

    "清理 docker:docker_clear_cache"

    "退出:exit_script"
)

OPTIONS_BILLING_CENTER_NOT_SHOW=(
    "手动安装 docker:manual_install_docker"
    "最快 docker ce 源:find_fastest_docker_mirror"
    "设置 daemon:set_daemon_config"
    "卸载 docker:uninstall_docker"

    "创建 billing center 配置目录:mkdir_billing_center_volume"
    "删除 billing center 配置目录:remove_billing_center_volume"

    "安装 pgsql 计费中心:install_db_pgsql_billing_center"
    "删除 pgsql 计费中心:delete_db_pgsql_billing_center"
    "安装 redis 计费中心:install_db_redis_billing_center"
    "删除 redis 计费中心:delete_db_redis_billing_center"
)

OPTIONS_BILLING_CENTER_VALID=(
    "${OPTIONS_BILLING_CENTER[@]}"
    "${OPTIONS_BILLING_CENTER_NOT_SHOW[@]}"
)

gen_ca_cert() {
    log_debug "run gen_ca_cert"

    local ca_cert_dir="$1"                   # CA 证书存放目录
    local days_valid="$2"                    # 证书有效期
    local ca_key_file="$ca_cert_dir/ca.key"  # CA 私钥文件
    local ca_cert_file="$ca_cert_dir/ca.crt" # CA 证书文件

    log_info "生成私有 CA 证书..."

    sudo openssl genpkey -algorithm RSA -out "$ca_key_file"

    sudo openssl req -x509 -new -nodes \
        -key "$ca_key_file" \
        -sha256 \
        -days "$days_valid" \
        -out "$ca_cert_file" \
        -subj "/C=CN/ST=Sichuan/L=Chengdu/O=jpz/OU=dev/CN=$HOST_INTRANET_IP"

    sudo rm -f "$ca_cert_dir/ca.srl"

    log_info "CA 证书和私钥已生成并保存在 $ca_cert_dir 目录中。"
}

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

    sudo openssl genpkey -algorithm RSA -out "$cert_dir/$name.key"

    sudo openssl req -new -key "$cert_dir/$name.key" -out "$cert_dir/$name.csr" -subj "/C=CN/ST=Sichuan/L=Chengdu/O=jpz/OU=it/CN=$cert_cn"

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

    local i
    IFS=',' read -ra dns_arr <<<"$dns_list"
    for i in "${!dns_arr[@]}"; do
        echo "DNS.$((i + 1)) = ${dns_arr[$i]}" | sudo tee -a "$cert_dir/$name.cnf"
    done

    IFS=',' read -ra ip_arr <<<"$ip_list"
    for i in "${!ip_arr[@]}"; do
        echo "IP.$((i + 1)) = ${ip_arr[$i]}" | sudo tee -a "$cert_dir/$name.cnf"
    done

    sudo openssl x509 -req -in "$cert_dir/$name.csr" \
        -CA "$ca_cert_file" \
        -CAkey "$ca_key_file" \
        -CAcreateserial \
        -out "$cert_dir/$name.crt" \
        -days "$days_valid" \
        -sha256 \
        -extfile "$cert_dir/$name.cnf" \
        -extensions v3_req

    sudo rm -f "$cert_dir/$name.cnf"
    sudo rm -f "$cert_dir/$name.csr"

    local ca_cert_dir
    ca_cert_dir=$(dirname "$ca_cert_file")
    sudo rm -f "$ca_cert_dir/ca.srl"

    log_info "$name 证书和私钥已生成并保存在 $cert_dir 目录中。"
}

gen_my_ca_cert() {
    log_debug "run gen_my_ca_cert"

    # shellcheck disable=SC2153
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CA_CERT_DIR"

    if [ ! -f "$CA_CERT_DIR/ca.crt" ]; then
        gen_ca_cert "$CA_CERT_DIR" "$CERT_DAYS_VALID"
    else
        log_warn "CA 证书已存在, 跳过生成."
    fi
}

gen_client_nginx_cert() {
    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CERTS_NGINX"

    if [ ! -f "$CERTS_NGINX/cert.pem" ]; then
        generate_instance_cert "cert" \
            "localhost,127.0.0.1,$HOST_INTRANET_IP,$PUBLIC_IP_ADDRESS" \
            "127.0.0.1,$HOST_INTRANET_IP,$PUBLIC_IP_ADDRESS" \
            "$CERTS_NGINX" \
            "$CERT_DAYS_VALID" \
            "$CA_CERT_DIR/ca.crt" \
            "$CA_CERT_DIR/ca.key" \
            "$HOST_INTRANET_IP"

        sudo mv "$CERTS_NGINX/cert.crt" "$CERTS_NGINX/cert.pem"
    else
        log_warn "前端 nginx 证书已存在, 跳过生成."
    fi
}

# shellcheck disable=SC2034

export LC_ALL=C.UTF-8

check_is_root() {
    log_debug "run check_is_root"

    if [ $UID -ne 0 ]; then
        log_error "请使用 root 或者 sudo 运行此脚本."
        exit 1
    fi
}

check_character() {
    log_debug "run check_is_character"

    read -r chn_chars eng_chars <<<"$(count_chars "测试Test中文字符English123456")"

    if [[ $chn_chars -ne 6 || $eng_chars -ne 17 ]]; then
        log_warn "当前环境下字符计算异常, 请设置系统语言为 UTF-8 编码格式."
    fi
}

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
        printf '\n环境变量 PATH 中缺少以下路径: %s\n\n' "${missing_paths[*]}"
        is_add=$(read_user_input "是否将它们添加到 PATH 中以确保脚本正常运行.(默认n) [y|n]? " "n")
        if [ "$is_add" == "y" ]; then
            export_cmd="export PATH=\$PATH$(printf ':%s' "${missing_paths[@]}")"
            printf '%s\n' "$export_cmd" >>"$HOME/.bashrc"
            printf '%s\n' "$export_cmd" >>"/root/.bashrc"

            log_info "已将以下路径添加到环境变量 PATH 中: ${missing_paths[*]}"
            log_warn "请重新登录终端或运行 'source ~/.bashrc' 以使更改生效."
            exit 0
        else
            log_warn "未将缺少的路径: ${missing_paths[*]} 添加到环境变量 PATH 中, 脚本无法正常运行."
        fi
    fi
}

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
    local missing_commands=()
    for cmd in "${which_software_list[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

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

load_interactive_config() {
    local var_name=$1
    local config_file=$2
    local prompt_msg=$3
    local default_value=$4

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
            printf "\n%s (默认: %s), 回车使用默认值: " "$prompt_msg" "$default_value"
            read -r user_input
            if [ -z "$user_input" ]; then
                printf -v "$var_name" '%s' "$default_value"
            else
                printf -v "$var_name" '%s' "$user_input"
            fi
        fi
    fi

    echo "${!var_name}" | sudo tee "$config_file" >/dev/null
}

load_config_from_file_and_validate() {
    local var_name=$1
    local config_file=$2
    local error_prefix=${3:-""}
    local must_exist=${4:-"true"}

    if [ -e "$config_file" ]; then
        if [ ! -r "$config_file" ]; then
            log_error "${error_prefix}${config_file} 存在但不可读, 请检查权限"
        fi

        local file_value
        IFS= read -r file_value <"$config_file"
        file_value="${file_value#"${file_value%%[![:space:]]*}"}"
        file_value="${file_value%"${file_value##*[![:space:]]}"}"

        if [ -z "$file_value" ]; then
            log_error "${error_prefix}${config_file} 文件为空, 请写入有效值"
        fi

        printf -v "$var_name" '%s' "$file_value"
        return
    fi

    if [ "$must_exist" = true ]; then
        log_error "${error_prefix}${config_file} 文件不存在, 请创建并写入有效值"
    fi
}

load_env_or_file_config() {
    local env_var_name=$1
    local var_name=$2
    local config_file=$3
    local error_prefix=${4:-""}

    if [ -n "${!env_var_name:-}" ]; then
        printf -v "$var_name" '%s' "${!env_var_name}"
    else
        load_config_from_file_and_validate "$var_name" "$config_file" "$error_prefix"
    fi
}

check_domain_ip() {
    log_debug "run check_domain_ip"

    if [ ! -d "$BLOG_TOOL_ENV" ]; then
        mkdir -p "$BLOG_TOOL_ENV"
    fi

    load_interactive_config \
        DOMAIN_NAME \
        "$BLOG_TOOL_ENV/domain_name" \
        "请输入您的域名如：example.com" \
        "$HOST_INTRANET_IP"

    load_interactive_config \
        PUBLIC_IP_ADDRESS \
        "$BLOG_TOOL_ENV/public_ip_address" \
        "请输入您的公网ip如：1.2.3.4" \
        "$HOST_INTRANET_IP"
}

check_dev_var() {
    log_debug "run check_dev_var"

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

    load_interactive_config \
        GIT_PREFIX_LOCAL \
        "$BLOG_TOOL_ENV/git_prefix_local" \
        "请输入内网 Git 地址前缀如：git@10.0.0.100" \
        "git@127.0.0.1"

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

update_run_mode() {
    if [ ! -d "$BLOG_TOOL_ENV" ]; then
        mkdir -p "$BLOG_TOOL_ENV"
    fi

    if [ -f "$BLOG_TOOL_ENV/run_mode" ]; then
        RUN_MODE=$(sudo cat "$BLOG_TOOL_ENV/run_mode")
    else
        echo "$RUN_MODE" | tee "$BLOG_TOOL_ENV/run_mode" >/dev/null
    fi

    if [[ "$RUN_MODE" == "pro" ]] && is_mem_greater_than 4; then
        ES_JAVA_OPTS_ENV="# $ES_JAVA_OPTS_ENV"
        MEM_LIMIT_ES="# $MEM_LIMIT_ES"
        MEM_LIMIT_KIBANA="# $MEM_LIMIT_KIBANA"
    fi
}

check_dir() {
    log_debug "run check_dir"

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    if [ ! -d "$BLOG_TOOL_ENV" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$BLOG_TOOL_ENV"
    fi

    if [ ! -d "$DOCKER_COMPOS_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DOCKER_COMPOS_DIR"
    fi

    if [ ! -d "$CA_CERT_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CA_CERT_DIR"
    fi

    if [ ! -d "$CERTS_NGINX" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$CERTS_NGINX"
    fi
}

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

    check_password_security

    decode_py_base64_main
}

install_database_billing_center() {
    log_debug "run install_database_billing_center"
    local remove_data_pgsql is_redis_cluster remove_data_redis

    if run_mode_is_dev; then
        remove_data_pgsql=$(read_user_input "[1/3]是否删除 pgsql_billing_center 数据库信息 (默认n) [y|n]? " "n")
        is_redis_cluster=$(read_user_input "[2/3]是否创建 redis_billing_center 集群 (默认n) [y|n]? " "n")
        remove_data_redis=$(read_user_input "[3/3]是否删除 redis_billing_center 数据库信息 (默认n) [y|n]? " "n")
    fi

    if run_mode_is_pro; then
        local pgsql_data_dir="$DATA_VOLUME_DIR/pgsql_billing_center"
        local redis_data_dir="$DATA_VOLUME_DIR/redis_billing_center"

        local has_data=true

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

delete_database_billing_center() {
    log_debug "run delete_database_billing_center"

    local is_delete # 是否删除历史数据 默认不删除
    is_delete=$(read_user_input "确认要删除计费中心数据库吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        echo "$is_delete" | delete_db_pgsql_billing_center
        echo "$is_delete" | delete_db_redis_billing_center

        log_info "删除计费中心数据库成功"
    else
        log_info "未删除计费中心数据库"
    fi
}

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
        if [ ! -d "$dir_name" ]; then
            sudo mkdir -p "$dir_name" # 创建目录
        fi
        sudo chown -R "$user":"$group" "$dir_name" # 重新设置用户和组
        sudo chmod -R "$permissions" "$dir_name"   # 设置权限
    done
}

over_write_set_owner() {
    log_debug "run over_write_set_owner"

    if [ $# -ne 5 ]; then # 参数个数必须为5
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

read_dir_basename_to_list() {
    log_debug "run read_dir_basename_to_list"

    local dir="$1"
    local files=()
    for f in "$dir"/*; do
        files+=("$(sudo basename "$f")")
    done
    printf "%s\n" "${files[@]}"
}

semver_to_docker_tag() {
    log_debug "run semver_to_docker_tag"

    local semver="$1"

    local docker_tag="${semver/\+/-}"

    log_debug "将原来 SemVer 风格的版本号: '$semver' 转换为 Docker 允许的 Tag: '$docker_tag'"

    echo "$docker_tag"
}

docker_tag_push_docker_hub() {
    log_debug "run docker_tag_push_docker_hub"
    local project=$1
    local version=$2

    log_debug "token 首尾3位: ${DOCKER_HUB_TOKEN:0:3}...${DOCKER_HUB_TOKEN: -3}"

    docker_login_retry "$DOCKER_HUB_REGISTRY" "$DOCKER_HUB_OWNER" "$DOCKER_HUB_TOKEN"

    if sudo docker manifest inspect "$DOCKER_HUB_OWNER/$project:$version" >/dev/null 2>&1; then
        log_warn "Docker Hub 镜像 $DOCKER_HUB_OWNER/$project:$version 已存在, 跳过推送"

        sudo docker logout "$DOCKER_HUB_REGISTRY" || true
        return 0
    fi

    local docker_tag_version
    docker_tag_version=$(semver_to_docker_tag "$version")

    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$DOCKER_HUB_OWNER/$project:$docker_tag_version"
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$DOCKER_HUB_OWNER/$project:latest"

    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "$docker_tag_version"

    waiting 5

    timeout_retry_docker_push "$DOCKER_HUB_OWNER" "$project" "latest"

    sudo docker logout "$DOCKER_HUB_REGISTRY" || true
}

docker_tag_push_private_registry() {
    log_debug "run docker_tag_push_private_registry"
    local project=$1
    local version=$2

    local docker_tag_version
    docker_tag_version=$(semver_to_docker_tag "$version")

    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$REGISTRY_REMOTE_SERVER/$project:$docker_tag_version"
    sudo docker tag "$REGISTRY_REMOTE_SERVER/$project:build" "$REGISTRY_REMOTE_SERVER/$project:latest"

    log_debug "密码 首尾3位: ${REGISTRY_PASSWORD:0:3}...${REGISTRY_PASSWORD: -3}"

    docker_login_retry "$REGISTRY_REMOTE_SERVER" "$REGISTRY_USER_NAME" "$REGISTRY_PASSWORD"

    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER" "$project" "$docker_tag_version"

    waiting 5

    timeout_retry_docker_push "$REGISTRY_REMOTE_SERVER" "$project" "latest"

    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
}

docker_private_registry_login_logout() {
    log_debug "run docker_private_registry_login_logout"

    local run_func="$1"

    log_debug "密码 首尾3位: ${REGISTRY_PASSWORD:0:3}...${REGISTRY_PASSWORD: -3}"

    sudo docker login "$REGISTRY_REMOTE_SERVER" -u "$REGISTRY_USER_NAME" --password-stdin <<<"$REGISTRY_PASSWORD"

    $run_func

    sudo docker logout "$REGISTRY_REMOTE_SERVER" || true
}

DOWNLOAD_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.0-latest-linux64-gpl-8.0.tar.xz" # BtbN 官方最新预编译版下载地址
TEMP_DIR="/tmp/ffmpeg_install"                                                                                          # 临时下载和解压目录
INSTALL_DIR="/usr/local/bin"                                                                                            # 安装目录

install_ffmpeg() {
    log_debug "run install_ffmpeg"
    log_info "开始安装预编译版 FFmpeg(来自 BtbN 官方构建)"
    log_info "下载地址: $DOWNLOAD_URL"
    log_info "安装目录: $INSTALL_DIR"

    sudo mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    echo "[1/6] 正在下载 FFmpeg 预编译二进制包..."
    sudo wget -O ffmpeg.tar.xz "$DOWNLOAD_URL"

    if [ ! -f "ffmpeg.tar.xz" ]; then
        log_error "下载失败, 请检查网络连接或下载地址是否有效"
        exit 1
    fi

    echo "[2/6] 正在解压 ffmpeg.tar.xz..."
    sudo tar -xvf ffmpeg.tar.xz

    FFMPEG_EXTRACTED_DIR=$(sudo find . -type d -name "*linux64-gpl*" | sudo head -n 1)

    if [ -z "$FFMPEG_EXTRACTED_DIR" ]; then
        log_error "未找到解压后的 FFmpeg 目录"
        ls -l
        exit 1
    fi

    echo "[3/6] 解压到的目录: $FFMPEG_EXTRACTED_DIR"

    if [ ! -d "$INSTALL_DIR" ]; then
        log_info "创建安装目录: $INSTALL_DIR"
        sudo mkdir -p "$INSTALL_DIR"
    fi

    echo "[4/6] 正在复制 FFmpeg 可执行文件到 $INSTALL_DIR ..."
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffmpeg" "$INSTALL_DIR/"
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffprobe" "$INSTALL_DIR/"
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffplay" "$INSTALL_DIR/"

    echo "[5/6] 赋权并完成安装..."
    sudo chmod +x "$INSTALL_DIR/ffmpeg"
    sudo chmod +x "$INSTALL_DIR/ffprobe"
    sudo chmod +x "$INSTALL_DIR/ffplay"

    echo "[6/6] 清理临时文件..."
    cd /tmp || exit 1
    sudo rm -rf "$TEMP_DIR"

    log_info "FFmpeg 预编译版 安装完成！"
    log_info "📍 FFmpeg 安装位置: $INSTALL_DIR"
    log_info "🔗 全局命令: ffmpeg, ffprobe, ffplay; 可通过以下命令验证：ffmpeg -version | which ffmpeg"
}

uninstall_ffmpeg() {
    log_debug "run uninstall_ffmpeg"
    log_info "开始卸载 FFmpeg 预编译版..."

    sudo rm -f "$INSTALL_DIR/ffmpeg"
    sudo rm -f "$INSTALL_DIR/ffprobe"
    sudo rm -f "$INSTALL_DIR/ffplay"

    log_info "FFmpeg 预编译版 已卸载！"
}

git_clone() {
    log_debug "run git_clone"
    local project_dir="$1"
    local git_prefix="${2:-$GIT_LOCAL}"

    log_debug "HOME $HOME"
    log_debug "whoami $(whoami)"
    log_debug "执行克隆命令: git clone $git_prefix/$project_dir.git"

    if [ -d "$project_dir" ]; then
        sudo rm -rf "$project_dir"
    fi

    sudo git clone "$git_prefix/$project_dir.git"

    log_debug "查看 git 仓库内容\n$(ls -la "$project_dir")\n"
}

git_clone_cd() {
    log_debug "run git_clone_cd"
    local project_dir="$1"
    local git_prefix="${2:-$GIT_LOCAL}"

    git_clone "$project_dir" "$git_prefix"

    cd "$project_dir" || exit
    log_debug "当前目录 $(pwd)"
}

git_add_commit_push() {
    log_debug "run git_add_commit_push"

    local commit_msg="$1"
    local force_push="${2:-false}"

    sudo git add .

    sudo git commit -m "$commit_msg"

    if [ "$force_push" = true ]; then
        sudo git push -f origin main
        log_warn "强制推送代码到远程仓库"
    else
        sudo git push origin main
        log_info "推送代码到远程仓库"
    fi
}

git_status_is_clean() {
    log_debug "run git_status_is_clean"
    if [ -z "$(git status --porcelain)" ]; then
        echo true
    else
        echo false
    fi
}

get_tag_version() {
    log_debug "run get_tag_version"
    local git_tag
    git_tag=sudo git describe --tags --abbrev=0 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' || echo "dev"
    echo "$git_tag"
}

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

    upload_url=$(echo "$release_res" | jq -r '.upload_url' | sed 's/{.*}//')

    echo "$release_id" "$upload_url"
}

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

    log_debug "token 首尾3位: ${token:0:3}...${token: -3}"

    local release_id
    local upload_url

    local release_json
    release_json=$(curl -s -H "Authorization: token $token" "$api_prefix/repos/${repo_owner}/${repo_name}/releases/tags/${tag}")

    local release_id=""
    if echo "$release_json" | grep -q '"id":'; then
        release_id=$(echo "$release_json" | jq -r '.id // empty')
    fi

    if [ -z "$release_id" ]; then
        log_info "创建新的 Release：$tag"

        local release_info
        release_info=$(create_release_id "$api_prefix" "$token" "$repo_owner" "$repo_name" "$tag" "$release_name" "$release_body" "$platform" "main")
        read -r __release_id __upload_url <<<"$release_info"
        log_debug "新创建的 Release ID: $release_id"

        release_id="$__release_id"
        upload_url="$__upload_url"
    else
        log_warn "Release 已存在：$tag (id：$release_id)，跳过创建 Release 步骤。"
        return
    fi

    for file_path in "${file_paths[@]}"; do
        if [ -z "$file_path" ]; then
            log_error "未指定有效的文件路径"
            exit 1
        fi
        if [ ! -f "$file_path" ]; then
            log_error "文件未找到：$file_path"
            exit 1
        fi

        if [ "$platform" = "github" ]; then
            upload_to_github_release "$api_prefix" "$token" "$tag" "$file_path" "$upload_url"
        elif [ "$platform" = "gitee" ]; then
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

    if $upload_func_name; then
        log_info "$platform_name: ✅ 上传成功"
        stop_spinner
    else
        stop_spinner
        log_error "$platform_name: ❌ 上传失败"
        return 1
    fi
}

upload_to_github_release() {
    local api_prefix="$1" # API 前缀
    local token="$2"      # token
    local tag="$3"        # Release 的 Tag 名称
    local file_path="$4"  # 要上传的文件路径
    local upload_url="$5" # 上传 URL

    local base_name
    base_name=$(basename "$file_path")

    local encoded_name
    encoded_name=$(jq -nr --arg v "$base_name" '$v|@uri')

    local final_upload_url
    final_upload_url="${upload_url}?name=${encoded_name}"

    log_debug "GitHub 上传 URL: $final_upload_url"

    # shellcheck disable=SC2329
    github_upload() {
        sudo curl -sS -X POST -H "Authorization: token $token" \
            -H "Accept: application/json" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @"$file_path" \
            "$final_upload_url"
    }

    common_upload_with_logging \
        "GitHub" \
        "📦 GitHub Release [$tag]" \
        github_upload
}

upload_to_gitee_release() {
    local api_prefix="$1" # API 前缀
    local token="$2"      # token
    local repo_owner="$3" # 仓库所有者
    local repo_name="$4"  # 仓库名称
    local release_id="$5" # Release ID
    local file_path="$6"  # 要上传的文件路径

    local base_name
    base_name=$(basename "$file_path")

    # shellcheck disable=SC2329
    gitee_upload() {
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

artifacts_releases_with_platform() {
    log_debug "run artifacts_releases_with_platform"

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

    artifacts_releases "$git_api_prefix" "$git_token" "$repo_owner" "$repo_name" "$tag" "$release_name" "$release_body" "$platform" "${file_paths[@]}"
}

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

sync_repo_by_tag() {
    log_debug "run sync_repo_by_tag"
    local project_dir="$1"
    local version="$2"
    local git_repo="${3:-$GIT_GITHUB}"

    git_clone "$project_dir-dev" "$GIT_LOCAL"

    if [ ! -f "$ROOT_DIR/$project_dir-dev/CHANGELOG.md" ]; then
        log_warn "$project_dir-dev 仓库中不存在 CHANGELOG.md 文件, 跳过更新"
        return
    fi

    git_clone_cd "$project_dir" "$git_repo"

    if sudo git rev-parse --verify "refs/tags/$version" >/dev/null 2>&1; then
        log_warn "Tag '$version' 已存在, 跳过更新 CHANGELOG.md"

        cd "$ROOT_DIR" || exit
        return
    else
        log_info "Tag '$version' 不存在, 继续更新 CHANGELOG.md"
    fi

    sudo cp -f "$ROOT_DIR/$project_dir-dev/CHANGELOG.md" "$ROOT_DIR/$project_dir/CHANGELOG.md"
    sudo cp -f "$ROOT_DIR/$project_dir-dev/LICENSE" "$ROOT_DIR/$project_dir/LICENSE"
    sudo cp -f "$ROOT_DIR/$project_dir-dev/README.md" "$ROOT_DIR/$project_dir/README.md"
    log_info "复制 CHANGELOG.md 到 $project_dir 仓库"

    cd "$ROOT_DIR/$project_dir" || exit
    log_debug "当前目录 $(pwd)"

    if [ "$(git_status_is_clean)" = true ]; then
        log_warn "CHANGELOG.md 无改动, 不需要提交"
    else
        git_add_commit_push "update to $version"
        log_info "更新 $project_dir 仓库的 CHANGELOG.md 完成"
    fi

    cd "$ROOT_DIR" || exit
}

releases_with_md_platform() {
    log_debug "run releases_with_md_platform"
    local project="$1"
    local version="$2"
    local zip_path="$3"
    local platform="${4:-github}"

    local md
    if [ "$platform" = "github" ]; then
        md=$(
            cat <<EOL
- 如何使用，请参考 [README.md](https://github.com/jiaopengzi/$project/blob/main/README.md)
- 更新内容，请参考 [CHANGELOG.md](https://github.com/jiaopengzi/$project/blob/main/CHANGELOG.md)
EOL
        )

    elif [ "$platform" = "gitee" ]; then
        md=$(
            cat <<EOL
- 如何使用，请参考 [README.md](https://gitee.com/jiaopengzi/$project/blob/main/README.md)
- 更新内容，请参考 [CHANGELOG.md](https://gitee.com/jiaopengzi/$project/blob/main/CHANGELOG.md)
EOL
        )

    fi

    artifacts_releases_with_platform "$GIT_USER" "$project" "$version" "$version" "$md" "$platform" "$zip_path"
}

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

    result=${result%,}

    echo "$result"
}

generate_items_all() {
    log_debug "run generate_items_all"
    
    local prefix=$1 # 前缀
    local count=$2  # 总的数量
    local result=""

    for ((i = 1; i <= count; i++)); do
        formattedI=$(printf "%02d" $i)
        result+="$prefix-$formattedI,"
    done

    result=${result%,}

    echo "$result"
}

run_mode_is_pro() {
    if [ "$RUN_MODE" == "pro" ]; then
        log_debug "run_mode_is_pro: 当前运行模式为生产环境"
        return 0
    else
        log_debug "run_mode_is_pro: 当前运行模式为开发环境"
        return 1
    fi
}

run_mode_is_dev() {
    if run_mode_is_pro; then
        return 1
    else
        return 0
    fi
}

get_img_prefix() {
    local img_prefix="$DOCKER_HUB_OWNER"

    if run_mode_is_dev; then
        img_prefix="$REGISTRY_REMOTE_SERVER"
    fi

    echo "$img_prefix"
}

version_is_pro() {
    local version="$1"

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

parsing_version() {
    local version="$1"
    local version_date is_dev

    version_date=$(date +%y%m%d%H%M)

    is_dev=true

    if version_is_pro "$version"; then
        is_dev=false
        echo "$version" "$is_dev"
        return
    fi

    if [[ "$version" == "dev" || -z "$version" ]]; then
        version="dev-$version_date"
    fi

    echo "$version" "$is_dev"
}

get_cidr() {
    local mask=$1

    if ! command -v bc >/dev/null 2>&1; then
        echo "24"
        return
    fi

    IFS='.' read -ra ADDR <<<"$mask"

    binary_mask=""

    for i in "${ADDR[@]}"; do
        binary_part=$(echo "obase=2; $i" | bc)
        binary_mask+=$binary_part
    done

    cidr=$(grep -o "1" <<<"$binary_mask" | wc -l)

    echo "$cidr"
}

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

check_url_accessible() {
    local url=$1
    local timeout=$2

    if [[ -z "$timeout" ]]; then
        timeout=5
    fi

    log_debug "正在检查 URL 可访问性: $url (超时: ${timeout}s)"
    start_spinner

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

# shellcheck disable=SC2034

generate_strong_password() {
	log_debug "run generate_strong_password"

	openssl rand -hex 32
}

is_weak_password() {
	log_debug "run is_weak_password"

	local password="$1"
	local password_length=${#password}

	if [[ -z "$password" ]]; then
		return 0
	fi

	if ((password_length < 16)); then
		return 0
	fi

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

	local first_char="${password:0:1}"
	local same_char_pattern
	same_char_pattern=$(printf '%*s' "$password_length" '' | tr ' ' "$first_char")
	if [[ "$password" == "$same_char_pattern" ]]; then
		return 0
	fi

	return 1
}

_handle_existing_password() {
	local var_name="$1"
	local config_file="$2"
	local description="$3"
	local password user_choice

	IFS= read -r password <"$config_file"

	if is_weak_password "$password"; then
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

	printf -v "$var_name" '%s' "$password"
}

_generate_new_password() {
	local var_name="$1"
	local config_file="$2"
	local description="$3"
	local password

	password=$(generate_strong_password)
	over_write_set_owner "$JPZ_UID" "$JPZ_GID" 600 "$password" "$config_file"
	log_info "✅ 已自动生成 $description 并写入 $config_file"

	printf -v "$var_name" '%s' "$password"
}

check_password_security() {
	log_debug "run check_password_security"

	if [[ ! -d "$BLOG_TOOL_ENV" ]]; then
		mkdir -p "$BLOG_TOOL_ENV"
	fi

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
		IFS=':' read -r var_name file_name description <<<"$entry"

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

export LC_ALL=C.UTF-8

count_chars() {
    local text="$1"

    local chn_chars
    chn_chars=$(echo -n "$text" | grep -oP '\p{Han}' | wc -l)

    local eng_chars
    eng_chars=$(echo -n "$text" | grep -oP '[a-zA-Z0-9]' | wc -l)

    echo "$chn_chars $eng_chars"
}

print_dividers() {
    local start_delimiter=$1 # 开始分隔符
    local col_length=$2      # 列宽
    local cols=$3            # 列数
    local delimiter=$4       # 分隔符
    local line=''            # 初始化分隔线

    line+="$start_delimiter"
    for ((c = 0; c < cols; c++)); do
        for ((i = 0; i < col_length; i++)); do
            line+="$delimiter"
        done
        line+="$start_delimiter"
    done

    printf '%s\n' "$line"
}

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

print_options() {
    local display_cols="$1"
    shift

    local options=("$@")                                      # 选项数组
    local count=${#options[@]}                                # 选项数量
    local rows=$(((count + display_cols - 1) / display_cols)) # 行数
    local cell_width=50                                       # 每个单元格的宽度
    local custom_width=6                                      # 自定义宽度 主要是为了显示序号和空格
    local col_length=$((cell_width + custom_width - 1))       # 列宽

    print_dividers "+" $col_length "$display_cols" "-"

    for ((row = 0; row < rows; row++)); do
        printf '|' # 每行开始打印左边框
        for ((col = 0; col < display_cols; col++)); do
            local idx=$((row + rows * col))
            if ((idx < count)); then
                local option="${options[$idx]}"
                local option_name="${option%%:*}" # 提取选项名称
                local chn_count
                read -r chn_count _ <<<"$(count_chars "$option_name")"

                if [ "$(check_utf8)" == true ]; then
                    words=$((cell_width + chn_count))
                else
                    words=$((cell_width + chn_count / 3)) # 一个中文字符占 3 个英文字符的位置 计算补齐占位符数量
                fi

                printf " %02d " $idx                    # 打印序号
                printf " %-*s|" "$words" "$option_name" # 左对齐内容

            else
                printf '%*s|' $col_length ""
            fi
        done
        echo
        if [ "$row" -lt "$((rows - 1))" ]; then
            print_dividers "+" $col_length "$display_cols" "-"
        fi
    done

    print_dividers "+" $col_length "$display_cols" "-"
    echo
}

exit_script() {
    rm -f "${PY_SCRIPT_FILE}"

    log_info "退出脚本"

    exit 0
}

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

exec_func() {
    local func="$1"
    if declare -f "$func" >/dev/null; then
        $func
    else
        log_error "找不到对应的函数：$func"
        exit 1
    fi
}

handle_user_input() {
    local options=("$@")
    read -r -p "请输入工具所在的序号[0-$((${#options[@]} - 1))] 或者直接输入函数名称: " raw_choice
    if [[ $raw_choice =~ ^0*[0-9]+$ ]]; then
        choice=$(printf "%d\n" $((10#$raw_choice)) 2>/dev/null)
        if ((choice < 0 || choice >= ${#options[@]})); then
            echo "请输入正确的选项序号"
            exit 1
        fi
        option="${options[$choice]}"
        func_name="${option##*:}" # 提取函数名称
    else
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
    exec_func "$func_name"
}

read_user_input() {
    local prompt_text=$1
    local default_value=$2
    local user_input=""

    local formatted_prompt="${prompt_text//\\n/$'\n'}"

    read -r -p "$formatted_prompt" user_input

    if [ -z "$user_input" ]; then
        user_input=$default_value
    fi

    user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

    echo "$user_input"
}

decode_py_base64_main() {
    log_debug "run decode_py_base64_main"
    echo "${PY_BASE64_MAIN}" | base64 -d | gzip -d >"${PY_SCRIPT_FILE}"
}

extract_changelog_block() {
    log_debug "run extract_changelog_block"

    local changelog_file="$1"
    local changelog_version="$2"

    if [[ ! -s "${PY_SCRIPT_FILE}" ]]; then
        log_error "解码后的 Python 脚本文件为空或不存在"
        exit 1
    fi

    log_debug "解码后的 Python 脚本文件已创建: ${PY_SCRIPT_FILE}"

    python3 "${PY_SCRIPT_FILE}" extract_changelog_block "$changelog_file" "$changelog_version"
}

extract_changelog_version_date() {
    log_debug "run extract_changelog_version_date"

    local changelog_file="$1"

    if [[ ! -s "${PY_SCRIPT_FILE}" ]]; then
        log_error "解码后的 Python 脚本文件为空或不存在"
        exit 1
    fi

    log_debug "解码后的 Python 脚本文件已创建: ${PY_SCRIPT_FILE}"

    python3 "${PY_SCRIPT_FILE}" extract_changelog_version_date "$changelog_file"
}

docker_run_registry_new() {
  log_debug "run docker_run_registry_new"

  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry"

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

  cp -r "$CERTS_NGINX" "$ROOT_DIR/registry/certs_nginx"

  cd "$ROOT_DIR/registry" || exit

  log_debug "当前目录 $(pwd)"

  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry/auth"
  sudo docker run --entrypoint htpasswd httpd:"$IMG_VERSION_HTTPD" -Bbn "$REGISTRY_USER_NAME" "$REGISTRY_PASSWORD" | sudo tee "$ROOT_DIR/registry/auth/htpasswd" >/dev/null # 创建用户密码文件

  sudo docker ps -a | grep httpd:"$IMG_VERSION_HTTPD" | awk '{print $1}' | xargs sudo docker rm -f

  setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$ROOT_DIR/registry/data"

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

  sudo docker compose up -d

  sudo docker login "$REGISTRY_REMOTE_SERVER" -u "$REGISTRY_USER_NAME" --password-stdin <<<"$REGISTRY_PASSWORD"
}

retry_with_backoff() {
    local run_func="$1"
    local max_retries=${2:-5}
    local delay=${3:-2}
    local success_msg="$4"
    local error_msg_prefix="$5"
    local retry_on_pattern="$6"

    local attempt=1
    local output
    local status

    start_spinner

    while true; do
        local tmpfile
        tmpfile=$(mktemp) || {
            stop_spinner
            log_error "创建临时文件失败"
            return 1
        }

        if "$run_func" >"$tmpfile" 2>&1; then
            stop_spinner

            cat "$tmpfile"
            rm -f "$tmpfile"

            log_info "$success_msg"
            return 0
        else
            status=$?

            output=$(cat "$tmpfile")

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
                stop_spinner
                log_error "${error_msg_prefix}: $output"
                return 1
            fi
        fi
    done
}

docker_login_retry() {

    log_debug "run docker_login_retry"
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

timeout_retry_docker_push() {
    log_debug "run timeout_retry_docker_push"
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

timeout_retry_docker_pull() {
    log_debug "run timeout_retry_docker_pull"
    local image_name=$1
    local version=$2

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

docker_build_push_start_server_client() {
    log_debug "run docker_build_push_start_server_client"
    docker_build_push_server_client
    docker_server_client_install
}

get_raw() {
    log_debug "run get_raw"
    local project="$1"
    local file="$2"
    local platform="${3:-github}"

    local raw_url
    if [ "$platform" = "github" ]; then
        raw_url="https://raw.githubusercontent.com/jiaopengzi/$project/refs/heads/main/$file"
    elif [ "$platform" = "gitee" ]; then
        raw_url="https://gitee.com/jiaopengzi/$project/raw/main/$file"
    fi

    echo "$raw_url"
}

get_service_versions() {
    log_debug "run get_service_versions"
    local service_name="${1-blog-client}"

    local raw_url

    start_spinner

    if [[ $(curl -s ipinfo.io/country) == "CN" ]]; then
        log_debug "检测到国内网络环境, 使用 gitee 获取 $service_name 版本"
        raw_url=$(get_raw "$service_name" "CHANGELOG.md" "gitee")
    else
        log_debug "检测到非国内网络环境, 使用 github 获取 $service_name 版本"
        raw_url=$(get_raw "$service_name" "CHANGELOG.md" "github")
    fi

    local changelog_temp_file
    changelog_temp_file=$(mktemp)
    curl -sSL "$raw_url" -o "$changelog_temp_file"

    stop_spinner

    extract_changelog_version_date "$changelog_temp_file"
}

show_service_versions() {
    log_debug "run show_service_versions"
    local service_name="${1-blog-client}"

    local versions
    versions=$(get_service_versions "$service_name")

    local formatted_versions=""
    local has_versions=false
    while IFS= read -r line; do
        local date_part version_part formatted_version
        version_part=$(echo "$line" | awk '{print $1}')
        date_part=$(echo "$line" | awk '{print $2}')

        formatted_version="$date_part\t$(semver_to_docker_tag "$version_part")"

        if run_mode_is_pro; then
            if (version_is_pro "$version_part"); then
                formatted_versions+="$formatted_version\n"
                has_versions=true
            fi
        else
            formatted_versions+="$formatted_version\n"
            has_versions=true
        fi

    done <<<"$versions"

    if [ "$has_versions" = false ]; then
        log_warn "服务 $service_name 暂无可用版本列表"
        exit 0
    fi

    formatted_versions=$(echo -e "发布日期\t版本号\n$formatted_versions" | column -t)

    log_info "\n\n服务 $service_name 可用版本列表如下:\n\n$formatted_versions\n"
}

check_service_version() {
    log_debug "run check_service_version"
    local service_name="${1-blog-server}"
    local version="$2"

    local versions
    versions=$(get_service_versions "$service_name")

    local version_exists=false

    while IFS= read -r line; do
        local v
        v=$(echo "$line" | awk '{print $1}')

        local formatted_v
        formatted_v=$(semver_to_docker_tag "$v")

        if [[ "$formatted_v" == "$version" ]]; then
            version_exists=true
            break
        fi
    done <<<"$versions"

    if [ "$version_exists" = false ]; then
        log_error "服务 $service_name 未找到版本 $version, 请检查后重试"
        exit 1
    fi

    if run_mode_is_pro && (version_is_dev "$version"); then
        log_error "当前运行模式为生产环境, 版本 $version 不符合生产环境版本规范, 请检查后重试"
        exit 1
    fi

    log_info "服务 $service_name 找到版本 $version"
}

get_cpu_logical() {
    grep -c '^processor[[:space:]]*:' /proc/cpuinfo
}

get_mem_gb() {
    awk '/^MemTotal:/ {printf "%.2f\n", $2/1024/1024}' /proc/meminfo
}

is_mem_greater_than() {
    local mem_gb
    mem_gb=$(get_mem_gb)

    log_debug "当前内存: ${mem_gb}GB, 阈值: ${1}GB"

    local threshold=$1
    awk -v mem="$mem_gb" -v thresh="$threshold" 'BEGIN {exit (mem > thresh) ? 0 : 1}'
}

log_timer() {
    local event run_func start_time end_time time_elapsed hours minutes seconds
    event=$1
    run_func=$2
    start_time=${3:-$(date +%s)}

    log_debug "开始执行: ${event}, 开始时间: $(date -d "@$start_time" +"%Y-%m-%d %H:%M:%S")"

    $run_func

    end_time=$(date +%s)
    time_elapsed=$((end_time - start_time))
    hours=$((time_elapsed / 3600))
    minutes=$(((time_elapsed / 60) % 60))
    seconds=$((time_elapsed % 60))
    log_info "${event}共计用时: ${hours}时${minutes}分${seconds}秒"
}

__spinner_pid=""

start_spinner() {
    if [ -n "$__spinner_pid" ]; then
        return
    fi

    local spinner_frames=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")

    local spin_index=0

    show_spinner() {
        while true; do
            printf "\r%s  " "${spinner_frames[$spin_index]}" >&2
            spin_index=$(((spin_index + 1) % ${#spinner_frames[@]}))
            sleep 0.2
        done
    }

    show_spinner &
    __spinner_pid=$!
}

stop_spinner() {
    if [ -n "$__spinner_pid" ]; then
        if kill -0 "$__spinner_pid" 2>/dev/null; then
            kill "$__spinner_pid" 2>/dev/null || true # kill 进程, 忽略错误防止脚本退出
            wait "$__spinner_pid" 2>/dev/null || true # 等待进程退出, 忽略错误防止脚本退出
        fi

        printf "\r  \r" >&2 # 清除残留帧
        __spinner_pid=""    # 清空PID以避免再次停止
    fi
}

waiting() {
    local duration=$1

    if [[ -z "$duration" || "$duration" -le 0 ]]; then
        return
    fi

    start_spinner

    sleep "$duration"

    stop_spinner
}

wait_file_write_complete() {
    log_debug "run wait_file_write_complete"

    log_warn "等待文件写入完成, 这可能需要几分钟时间... 请勿中断！"

    local run_func="$1"
    local file_path="$2"
    local timeout=${3:-300}

    local start_time
    start_time=$(date +%s)

    start_spinner

    $run_func

    until sudo [ -f "$file_path" ]; do
        sleep 1

        local current_time
        current_time=$(date +%s)

        local elapsed_time=$((current_time - start_time))

        if [ "$elapsed_time" -ge "$timeout" ]; then
            stop_spinner

            log_error "等待文件写入完成超时, 已超过 $timeout 秒, 请检查相关日志"
            exit 1
        fi
    done

    stop_spinner

    log_debug "文件 $file_path 写入完成."
}

update_yaml_block() {
    local YAML_FILE="$1"
    local YAML_KEY_LINE="$2"
    local NEW_CONTENT_FILE="$3"

    if [[ -z "$YAML_FILE" || -z "$YAML_KEY_LINE" || -z "$NEW_CONTENT_FILE" ]]; then
        echo "❌ 错误：请提供 YAML 文件路径、YAML key 行(如 'key: |')、以及新内容文件路径"
        echo "   用法: update_yaml_block \"yaml文件路径\" \"yaml_key_line\" \"新内容文件路径\""
        return 1
    fi

    if ! sudo test -f "$YAML_FILE"; then
        echo "❌ 错误：YAML 文件不存在: $YAML_FILE"
        return 1
    fi

    if ! sudo test -f "$NEW_CONTENT_FILE"; then
        echo "❌ 错误：新内容文件不存在: $NEW_CONTENT_FILE"
        return 1
    fi

    local KEY_LINE_NUM
    KEY_LINE_NUM=$(sudo grep -n "^${YAML_KEY_LINE}$" "$YAML_FILE" | sudo cut -d: -f1)

    if [[ -z "$KEY_LINE_NUM" ]]; then
        echo "❌ 错误：未找到 YAML key 行: '$YAML_KEY_LINE', 请确认格式与文件中完全一致(包括缩进！)"
        return 1
    fi

    local BLOCK_START_LINE=$((KEY_LINE_NUM + 1))
    local TOTAL_LINES
    TOTAL_LINES=$(sudo cat "$YAML_FILE" | wc -l | awk '{print $1}')

    if [[ $BLOCK_START_LINE -gt $TOTAL_LINES ]]; then
        echo "❌ 错误：未找到 YAML key 行: '$YAML_KEY_LINE'的下一行不存在, 可能格式错)"
        return 1
    fi

    local BLOCK_START_LINE_CONTENT
    BLOCK_START_LINE_CONTENT=$(sudo sed -n "${BLOCK_START_LINE}p" "$YAML_FILE")

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

    local NEW_CONTENT_RAW
    NEW_CONTENT_RAW=$(sudo cat "$NEW_CONTENT_FILE" 2>/dev/null)

    if [[ -z "$NEW_CONTENT_RAW" ]]; then
        echo "❌ 错误：无法读取新内容文件 '$NEW_CONTENT_FILE'，请检查文件权限"
        return 1
    fi

    local FORMATTED_BLOCK=""
    while IFS= read -r line; do
        FORMATTED_BLOCK+="${INDENT}${line}"$'\n'
    done <<<"$NEW_CONTENT_RAW"

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
            print new_cert
            in_cert_block = 1
            replaced = 1
        } else {
            print
        }
    }

    NR > start_line {
        if (in_cert_block == 1) {
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
            } else {
                in_cert_block = 0
                print $0
            }
        } else {
            print $0
        }
    }
    ' "$YAML_FILE" | sudo tee "$TMP_FILE" >/dev/null; then
        sudo cp "$YAML_FILE" "${YAML_FILE}.bak"
        sudo mv "$TMP_FILE" "$YAML_FILE"
        echo "✅ 成功更新 YAML 文件中到 YAML key 行: '$YAML_KEY_LINE' 的多行字符串块内容"
        echo "📂 原文件已备份为: ${YAML_FILE}.bak"
    else
        echo "❌ 替换失败"
        sudo rm -f "$TMP_FILE"
        return 1
    fi
}

apt_update() {
    log_debug "run apt_update"

    if command -v sudo >/dev/null 2>&1; then
        sudo apt update
    else
        apt update
    fi
}

apt_install_y() {
    log_debug "run apt_install_y"

    sudo apt install -y "$@"
}

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

get_system_family() {
	detect_system
	echo "$SYSTEM_FAMILY"
}

get_system_codename() {
	detect_system
	echo "$SYSTEM_CODENAME"
}

get_system_version_num() {
	detect_system
	echo "$SYSTEM_VERSION_NUM"
}

get_apt_source_base() {
	detect_system
	case "$SYSTEM_FAMILY" in
	debian) echo "http://deb.debian.org/debian" ;;
	ubuntu) echo "http://archive.ubuntu.com/ubuntu" ;;
	*) echo "http://deb.debian.org/debian" ;;
	esac
}

get_docker_repo_path() {
	detect_system
	case "$SYSTEM_FAMILY" in
	debian) echo "debian" ;;
	ubuntu) echo "ubuntu" ;;
	*) echo "debian" ;;
	esac
}

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

check_min_version() {
	local min_version="$1"
	detect_system
	[ -z "$SYSTEM_VERSION_NUM" ] && return 1
	[ "$SYSTEM_VERSION_NUM" -ge "$min_version" ] 2>/dev/null
	return $?
}

print_system_info() {
	detect_system
	echo "SYSTEM_FAMILY: $SYSTEM_FAMILY"
	echo "SYSTEM_CODENAME: $SYSTEM_CODENAME"
	echo "SYSTEM_VERSION_NUM: $SYSTEM_VERSION_NUM"
	echo "APT_SOURCE_BASE: $(get_apt_source_base)"
	echo "DOCKER_REPO_PATH: $(get_docker_repo_path)"
	echo "BACKPORTS_SOURCE: $(get_backports_source)"
}

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

install_common_software() {
    log_debug "run install_common_software"

    apt_update

    if command -v sudo >/dev/null 2>&1; then
        sudo apt install -y "${BASE_SOFTWARE_LIST[@]}"
    else
        apt install -y "${BASE_SOFTWARE_LIST[@]}"
    fi

    if ! grep -q "export HISTSIZE=*" "$HOME/.bashrc"; then
        echo 'export HISTSIZE=5000' | tee -a "$HOME/.bashrc"
    fi

    if ! grep -q "export HISTFILESIZE=*" "$HOME/.bashrc"; then
        echo 'export HISTFILESIZE=5000' | tee -a "$HOME/.bashrc"
    fi

}

update_apt_source() {
    log_debug "run update_apt_source"

    local sources_list="/etc/apt/sources.list"
    local sources_list_d="/etc/apt/sources.list.d"

    if [ -f "$sources_list" ]; then
        sudo cp "$sources_list" "$sources_list.bak_$(date +%Y%m%d%H%M%S)"
        sudo cp -r "$sources_list_d" "$sources_list_d.bak_$(date +%Y%m%d%H%M%S)"

        log_info "备份 sources.list 到 $sources_list.bak_$(date +%Y%m%d%H%M%S)"
        log_info "备份 sources.list.d 到 $sources_list_d.bak_$(date +%Y%m%d%H%M%S)"

        sudo sed -i "s/$OLD_SYS_VERSION/$NEW_SYS_VERSION/g" "$sources_list"
        sudo find /etc/apt/sources.list.d/ -name "*.list" -exec sed -i "s/$OLD_SYS_VERSION/$NEW_SYS_VERSION/g" {} \;
    fi
}

create_user_and_group_nologin() {
    log_debug "run create_user_and_group_nologin"

    local uid=$1  # 用户 id
    local gid=$2  # 用户组 id
    local name=$3 # 用户名 和 用户组名 相同

    if ! getent group "$gid" >/dev/null; then
        sudo groupadd -g "$gid" "$name"
        log_info "创建不登录用户组: $name, gid: $gid"
    else
        log_warn "用户组 gid:$gid 已经存在"
    fi

    if ! id -u "$uid" >/dev/null 2>&1; then
        sudo useradd -r -M -u "$uid" -g "$gid" "$name"
        sudo usermod -s /sbin/nologin "$name"

        log_info "创建不登录用户: $name, uid: $uid"
    else
        log_warn "用户 uid:$uid 已经存在"
    fi
}

add_group_user() {
    log_debug "run add_group_user"

    create_user_and_group_nologin "$DB_UID" "$DB_GID" "$APP_NAME-database"
    create_user_and_group_nologin "$CLIENT_UID" "$CLIENT_GID" "$APP_NAME-client"
    create_user_and_group_nologin "$SERVER_GID" "$SERVER_GID" "$APP_NAME-server"
    create_user_and_group_nologin "$JPZ_UID" "$JPZ_GID" "$APP_NAME-project"

}

docker_clear_cache() {
    log_debug "run docker_clear_cache"

    sudo docker container prune -f # 删除所有停止状态的容器
    sudo docker network prune -f   # 删除所有不使用的网络
    sudo docker image prune -f     # 删除所有不使用的镜像
    sudo docker builder prune -f   # 删除所有不使用的构建缓存

    sudo docker images | grep "<none>" | awk '{print $3}' | xargs sudo docker rmi -f || true
}

set_daemon_config() {
    log_debug "run set_daemon_config"

    local target_dir="/etc/docker"
    local target_file="/etc/docker/daemon.json"
    local validate_cmd="sudo dockerd --validate --config-file"

    if [ ! -f "$target_file" ]; then
        log_debug "docker daemon 配置文件不存在, 创建新文件"
        sudo mkdir -p "$target_dir"
        echo '{}' | sudo tee "$target_file" >/dev/null
    else
        log_debug "docker daemon 配置文件已存在, 进行备份"
        sudo cp "$target_file" "${target_file}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    local tmp_file="$target_file.tmp"

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

    cat >>"$tmp_file" <<'EOF'
}
EOF

    if $validate_cmd "$tmp_file" >/dev/null 2>&1; then
        log_debug "docker 日志配置语法验证通过"
    else
        log_error "docker 日志配置语法验证失败, 请检查 $tmp_file 文件"
        log_error "文件内容:"
        sudo cat "$tmp_file"
        sudo rm -f "$tmp_file"
        return 1
    fi

    sudo mv "$tmp_file" "$target_file"

    log_info "docker 正在重启..."
    sudo systemctl restart docker 2>/dev/null || sudo service docker restart 2>/dev/null

    log_info "如果您需要修改配置, 请编辑 $target_file 文件并重启 docker 服务"
}

pull_docker_image_pro_db_billing_center() {
    log_debug "run pull_docker_image_pro_db_billing_center"

    timeout_retry_docker_pull "redis" "$IMG_VERSION_REDIS"
    timeout_retry_docker_pull "postgres" "$IMG_VERSION_PGSQL"

    log_info "docker 生产环境数据库镜像拉取完成"
}

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

__install_docker() {
    log_debug "run __install_docker"

    local is_manual_install="${1-n}"

    docker_install_backup

    local script_url="https://get.docker.com"

    local script_file="./install-docker.sh"

    # shellcheck disable=SC2329
    run() {
        log_debug "下载命令: sudo curl -fsSL --connect-timeout 5 --max-time 10 $script_url -o $script_file"
        sudo curl -fsSL --connect-timeout 5 --max-time 10 "$script_url" -o "$script_file"
    }

    if ! retry_with_backoff "run" 5 2 "docker 安装脚本下载成功" "docker 安装脚本下载失败" ""; then
        log_error "下载 docker 安装脚本失败, 请检查网络连接"
        exit 1
    fi

    local fastest_docker_mirror
    if [[ "$is_manual_install" == "y" ]]; then
        fastest_docker_mirror=$(manual_select_docker_source)
    else
        fastest_docker_mirror=$(find_fastest_docker_mirror)
    fi

    if [[ -n "$fastest_docker_mirror" ]]; then
        log_info "使用最快的 Docker CE 镜像源: $fastest_docker_mirror"

        sudo sed -i "s|DOWNLOAD_URL=\"https://mirrors.aliyun.com/docker-ce\"|DOWNLOAD_URL=\"$fastest_docker_mirror\"|g" "$script_file"

        sudo sed -i "s|Aliyun|MyFastMirror|g" "$script_file"
    else
        log_warn "未找到可用的 Docker CE 镜像源, 将使用默认官方源进行安装，可能会因为网络问题导致安装失败"
    fi

    sudo chmod +x "$script_file"

    log_info "正在安装 docker, 请耐心等待..."

    if sudo bash "$script_file" --mirror MyFastMirror 2>&1 | tee -a ./install.log; then
        log_info "docker 安装脚本执行完成"

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

    set_daemon_config

    sudo rm -f "$script_file"

    sudo rm -f ./install.log
}

__uninstall_docker() {
    log_debug "run __uninstall_docker"

    sudo systemctl stop docker || true

    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

    sudo apt autoremove -y

    log_info "docker 卸载完成"

    is_remove=$(read_user_input "是否需要移除 docker 的历史数据 docker (默认n) [y|n]? " "n")

    if [[ "$is_remove" == "y" ]]; then
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd

        sudo rm /etc/apt/sources.list.d/docker.list
        sudo rm /etc/apt/keyrings/docker.asc

        log_info "已移除 docker 历史数据"
    else
        log_info "未移除 docker 历史数据"
    fi
}

uninstall_docker() {
    log_debug "run uninstall_docker"

    is_uninstall=$(read_user_input "是否卸载 docker (默认n) [y|n]? " "n")
    if [[ "$is_uninstall" == "y" ]]; then
        __uninstall_docker
    else
        log_info "未卸载 docker"
    fi
}

install_docker() {
    log_debug "run install_docker"
    local is_manual_install="${1-n}"

    if command -v docker >/dev/null 2>&1; then
        log_warn "检测到已安装 Docker"

        local is_install
        is_install=$(read_user_input "是否需要卸载后重新安装 docker (默认n) [y|n]? " "n")

        if [[ "$is_install" == "y" ]]; then
            log_debug "开始卸载 docker"

            __uninstall_docker

            __install_docker "$is_manual_install"
        else
            log_info "跳过 docker 重新安装步骤"
            return
        fi
    else
        __install_docker
    fi
}

manual_install_docker() {
    log_debug "run manual_install_docker"
    __install_docker "y"
}

DOCKER_CE_TEST_DOWNLOAD_FILE="linux/$(get_docker_repo_path)/gpg" # 测试文件路径(相对于镜像源根目录)

find_fastest_docker_mirror() {
    local temp_dir
    temp_dir=$(mktemp -d)

    trap 'rm -rf "$temp_dir"' EXIT

    declare -A pids_to_sources
    log_info "正在启动对所有 Docker CE 镜像源进行并发测速..."

    for item in "${DOCKER_CE_SOURCES[@]}"; do
        log_debug "启动测试任务 for source: $item"
        local source
        IFS='|' read -r source _ <<<"$item"

        local sanitized_source
        sanitized_source="${source//[!a-zA-Z0-9]/_}"
        local output_file="$temp_dir/${sanitized_source}.out"

        (
            trap - EXIT

            local test_url="${source}/${DOCKER_CE_TEST_DOWNLOAD_FILE}"
            local time_total
            time_total=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 3 -m 10 "$test_url" 2>/dev/null) || time_total=""

            if [[ "$time_total" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (($(echo "$time_total < 10" | bc -l 2>/dev/null || echo 0))); then
                echo "$time_total $source" >"$output_file"
            else
                echo "FAILED" >"$output_file"
            fi
        ) &

        local pid=$!
        pids_to_sources["$pid"]="$source"

        log_debug "已启动测试任务 PID: $pid -> $source"
    done

    log_debug "所有测试任务已启动, 共 ${#pids_to_sources[@]} 个。正在等待首个成功响应的源..."

    local fastest_source=""
    local fastest_time=""

    local timeout_counter=0
    local max_timeout=50 # 大约10秒 (50 * 0.2s)

    while [ ${#pids_to_sources[@]} -gt 0 ] && [ $timeout_counter -lt $max_timeout ]; do
        declare -A completed_this_round # 存储本轮完成的任务 PID -> Source
        for pid in "${!pids_to_sources[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                local source_url="${pids_to_sources[$pid]}"
                local sanitized_source
                sanitized_source="${source_url//[!a-zA-Z0-9]/_}"
                local output_file="$temp_dir/${sanitized_source}.out"

                if [ -f "$output_file" ]; then
                    read -r result <"$output_file"
                    unset "pids_to_sources[$pid]"
                    completed_this_round["$pid"]="$source_url|$result"
                fi
            fi
        done

        if [ ${#completed_this_round[@]} -gt 0 ]; then
            local best_time_in_round=""
            local best_source_in_round=""

            for pid in "${!completed_this_round[@]}"; do
                IFS='|' read -r source_url result <<<"${completed_this_round[$pid]}"

                if [[ "$result" != FAILED* ]]; then
                    used_time=$(echo "$result" | cut -d' ' -f1)

                    if [ -z "$best_time_in_round" ]; then
                        best_time_in_round="$used_time"
                        best_source_in_round=$(echo "$result" | cut -d' ' -f2-)
                    elif (($(echo "$used_time < $best_time_in_round" | bc -l))); then
                        best_time_in_round="$used_time"
                        best_source_in_round=$(echo "$result" | cut -d' ' -f2-)
                    fi
                fi
            done

            if [ -n "$best_source_in_round" ]; then
                fastest_time="$best_time_in_round"
                fastest_source="$best_source_in_round"

                log_debug "🎉 找到最快的 Docker CE 镜像源！"
                log_debug "镜像地址: $fastest_source"
                log_debug "响应时间: $(awk "BEGIN {printf \"%.0f\", $fastest_time * 1000}") ms"

                log_debug "终止其他正在进行的测试任务..."
                for remaining_pid in "${pids_to_sources[@]}"; do
                    log_debug "终止任务 PID: $remaining_pid"

                    sudo kill "$remaining_pid" 2>/dev/null || true
                done
                break 2 # 跳出内外层循环
            fi
        fi

        timeout_counter=$((timeout_counter + 1))
        sleep 0.2 # 每200ms轮询一次
    done

    if [ -z "$fastest_source" ]; then
        log_error "❌ 错误：在指定时间内未能找到任何可用的 Docker CE 镜像源。"
        log_error "   请检查网络连接或镜像列表 'DOCKER_CE_SOURCES' 是否正确。"
        return 1
    fi

    echo "$fastest_source"
}

docker_install_backup() {
    log_debug "run docker_install_backup"

    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    local docker_list_file="/etc/apt/sources.list.d/docker.list"

    if [ -f "$docker_list_file" ]; then
        local bak_dir="/etc/apt/sources.list.d/backup"
        if [ ! -d "$bak_dir" ]; then
            sudo mkdir -p "$bak_dir"
            log_debug "已创建备份目录 $bak_dir"
        fi

        sudo cp -a "$docker_list_file" "$bak_dir/docker.list.bak_$timestamp"
        log_info "已备份 $docker_list_file 到 $bak_dir/docker.list.bak_$timestamp"

        sudo rm -f "$docker_list_file"
        log_debug "已删除 $docker_list_file"
    else
        log_warn "未找到 $docker_list_file，跳过备份和删除"
    fi

    local docker_key_file="/etc/apt/keyrings/docker.asc"
    if [ -f "$docker_key_file" ]; then
        local bak_dir="/etc/apt/keyrings/backup"
        if [ ! -d "$bak_dir" ]; then
            sudo mkdir -p "$bak_dir"
            log_debug "已创建备份目录 $bak_dir"
        fi

        sudo cp -a "$docker_key_file" "$bak_dir/docker.asc.bak_$timestamp"
        log_info "已备份 $docker_key_file 到 $bak_dir/docker.asc.bak_$timestamp"

        sudo rm -f "$docker_key_file"
        log_debug "已删除 $docker_key_file"
    else
        log_warn "未找到 $docker_key_file，跳过备份和删除"
    fi
}

manual_select_docker_source() {
    log_debug "run __install_docker"
    echo "请选择一个 Docker CE 镜像源：" >&2
    for i in "${!DOCKER_CE_SOURCES[@]}"; do
        url="${DOCKER_CE_SOURCES[$i]%|*}"
        name="${DOCKER_CE_SOURCES[$i]#*|}"
        log_debug "选项 $((i + 1)): $name ($url)"
        printf "%2d) %s\n" $((i + 1)) "$name" >&2
    done

    read -rp "请输入序号（1-${#DOCKER_CE_SOURCES[@]}）: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#DOCKER_CE_SOURCES[@]}" ]; then
        log_error "无效的输入！请输入 1 到 ${#DOCKER_CE_SOURCES[@]} 之间的数字。"
        exit 1
    fi

    selected_item="${DOCKER_CE_SOURCES[$((choice - 1))]}"
    url="${selected_item%|*}"

    log_debug "用户选择的 Docker CE 镜像源: $url"

    log_info "您选择的是：${selected_item#*|}"
    echo "$url"
}

start_db_pgsql_billing_center() {
  log_debug "run start_db_pgsql_billing_center"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" up -d
}

stop_db_pgsql_billing_center() {
  log_debug "run stop_db_pgsql_billing_center"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL_BILLING_CENTER" down || true
}

restart_db_pgsql_billing_center() {
  log_debug "run restart_db_pgsql_billing_center"
  stop_db_pgsql_billing_center
  start_db_pgsql_billing_center
}

install_db_pgsql_billing_center() {
  log_debug "run install_db_pgsql_billing_center"
  # shellcheck disable=SC2329
  run() {
    local all_remove_data # 是否删除历史数据 默认不删除

    all_remove_data=$(read_user_input "是否删除 pgsql_billing_center 数据库信息(默认n) [y|n]? " "n")

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
      setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/pgsql_billing_center"

    local docker_compose_file="$DOCKER_COMPOSE_FILE_PGSQL_BILLING_CENTER"

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

    if [ "$all_remove_data" == "y" ]; then

      sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center"
      if [ ! -d "$DATA_VOLUME_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
      fi

      setup_directory "$DB_UID" "$DB_GID" 755 \
        "$DATA_VOLUME_DIR/pgsql_billing_center" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/data" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/conf" \
        "$DATA_VOLUME_DIR/pgsql_billing_center/log"

      local content_postgresql_conf
      local content_pg_hba_conf

      content_postgresql_conf=$(get_content_postgresql_conf "$POSTGRES_PORT_BILLING_CENTER")
      content_pg_hba_conf=$(get_content_pg_hba_conf "$SUBNET_PGSQL_BILLING_CENTER" "$SUBNET_BILLING_CENTER")

      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_postgresql_conf" "$DATA_VOLUME_DIR/pgsql_billing_center/conf/postgresql.conf"
      over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content_pg_hba_conf" "$DATA_VOLUME_DIR/pgsql_billing_center/conf/pg_hba.conf"

      log_info "已删除 pgsql_billing_center 历史数据"

    else
      log_info "未删除 pgsql_billing_center 历史数据"
    fi

    start_db_pgsql_billing_center

  }

  log_timer "pgsql_billing_center 启动" run

  log_info "pgsql_billing_center 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

delete_db_pgsql_billing_center() {
  log_debug "run delete_db_pgsql_billing_center"

  local is_delete
  is_delete=$(read_user_input "确认停止 pgsql_billing_center 服务并删除数据吗(默认n) [y|n] " "n")

  if [[ "$is_delete" == "y" ]]; then
    stop_db_pgsql_billing_center

    sudo rm -rf "$DATA_VOLUME_DIR/pgsql_billing_center"
  fi
}

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

  echo "$content_postgresql_conf"
}

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
  echo "$content_pg_hba_conf"
}

start_db_pgsql() {
  log_debug "run start_db_pgsql"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" up -d
}

stop_db_pgsql() {
  log_debug "run stop_db_pgsql"
  sudo docker compose -f "$DOCKER_COMPOSE_FILE_PGSQL" -p "$DOCKER_COMPOSE_PROJECT_NAME_PGSQL" down || true
}

restart_db_pgsql() {
  log_debug "run restart_db_pgsql"
  stop_db_pgsql
  start_db_pgsql
}

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

open_pgsql_access_by_pg_hba.conf() {
  log_debug "run open_pgsql_access_by_pg_hba.conf"

  sudo docker stop "$POSTGRES_DOCKER_NAME"                          # 停止容器 pgsql 容器
  toggle_pg_hba_conf open "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf" # 切换访问权限
  sudo docker start "$POSTGRES_DOCKER_NAME"                         # 重启容器
}

restrict_pgsql_access_by_pg_hba.conf() {
  log_debug "run restrict_pgsql_access_by_pg_hba.conf"

  sudo docker stop "$POSTGRES_DOCKER_NAME"                              # 停止容器 pgsql 容器
  toggle_pg_hba_conf restrict "$DATA_VOLUME_DIR/pgsql/conf/pg_hba.conf" # 切换访问权限
  sudo docker start "$POSTGRES_DOCKER_NAME"                             # 重启容器
}

start_db_redis_billing_center() {
    log_debug "run start_db_redis_billing_center"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER" up -d # 启动容器
}

stop_db_redis_billing_center() {
    log_debug "run stop_db_redis_billing_center"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER" down || true
}

restart_db_redis_billing_center() {
    log_debug "run restart_db_redis_billing_center"
    stop_db_redis_billing_center
    start_db_redis_billing_center
}

install_db_redis_billing_center() {
    log_debug "run install_db_redis_billing_center"
    # shellcheck disable=SC2329
    run() {
        local is_redis_cluster # 是否创建 redis 集群 默认不创建
        local all_remove_data  # 是否删除历史数据 默认不删除

        is_redis_cluster=$(read_user_input "[1/2]是否创建 redis_billing_center 集群(默认n) [y|n]? " "n")
        all_remove_data=$(read_user_input "[2/2]是否删除 redis_billing_center (默认n) [y|n]? " "n")

        if [ ! -d "$DATA_VOLUME_DIR" ]; then
            setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
        fi

        setup_directory "$DB_UID" "$DB_GID" 755 "$DATA_VOLUME_DIR/redis_billing_center"

        local docker_compose_file="$DOCKER_COMPOSE_FILE_REDIS_BILLING_CENTER"

        if [ -f "$docker_compose_file" ]; then
            sudo docker compose -f "$docker_compose_file" -p "$DOCKER_COMPOSE_PROJECT_NAME_REDIS_BILLING_CENTER" down || true # 删除容器
            touch "$docker_compose_file"
        fi
        cat >"$docker_compose_file" <<-EOM
services:
EOM

        if [ "$is_redis_cluster" == "n" ]; then
            MASTER_COUNT=1
            SLAVE_COUNT=0
        fi

        cluster_urls="" # 集群节点地址
        redis_ips=""    # ip地址拼接
        for ((port = REDIS_BASE_PORT_BILLING_CENTER; port < REDIS_BASE_PORT_BILLING_CENTER + MASTER_COUNT + SLAVE_COUNT; port++)); do
            port_cluster=$((port + 10000))                                                                   # port_cluster 自增 集群监控端口
            ip_node="$IPV4_BASE_REDIS_BILLING_CENTER.$(((port - REDIS_BASE_PORT_BILLING_CENTER + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关

            cluster_urls+="redis-$IMG_VERSION_REDIS-$port:$port " # 集群节点 名称
            redis_ips+="$ip_node "                                # 集群节点地址

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

        if [ "$all_remove_data" == "y" ]; then

            sudo rm -rf "$DATA_VOLUME_DIR/redis_billing_center"
            if [ ! -d "$DATA_VOLUME_DIR" ]; then
                setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
            fi

            setup_directory "$DB_UID" "$DB_GID" 755 \
                "$DATA_VOLUME_DIR/redis_billing_center" \
                "$DATA_VOLUME_DIR/redis_billing_center/data" \
                "$DATA_VOLUME_DIR/redis_billing_center/conf" \
                "$DATA_VOLUME_DIR/redis_billing_center/log"

            for ((port = REDIS_BASE_PORT_BILLING_CENTER; port < REDIS_BASE_PORT_BILLING_CENTER + MASTER_COUNT + SLAVE_COUNT; port++)); do

                ip_node="$IPV4_BASE_REDIS_BILLING_CENTER.$(((port - REDIS_BASE_PORT_BILLING_CENTER + 2) % 256))" # ip_node 自增 从 2 开始, 1 为网关
                setup_directory "$DB_UID" "$DB_GID" 755 \
                    "$DATA_VOLUME_DIR/redis_billing_center/data/$port" \
                    "$DATA_VOLUME_DIR/redis_billing_center/conf/$port" \
                    "$DATA_VOLUME_DIR/redis_billing_center/log/$port"

                config_cluster=""

                if [ "${is_redis_cluster,,}" = "y" ]; then
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

                over_write_set_owner "$DB_UID" "$DB_GID" 600 "$content" "$DATA_VOLUME_DIR/redis_billing_center/conf/$port/redis.conf"
            done

            log_info "已删除 redis_billing_center 历史数据"
        else
            log_info "未删除 redis_billing_center 历史数据"
        fi

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
        start_db_redis_billing_center

        if [ "$all_remove_data" == "y" ] && [ "$is_redis_cluster" = "y" ]; then
            log_info "redis 集群开启"
            redis_name="redis-$IMG_VERSION_REDIS-$REDIS_BASE_PORT_BILLING_CENTER"
            REDIS_CLI_COMMAND="echo yes | redis-cli -h $redis_name -p $REDIS_BASE_PORT_BILLING_CENTER -a $REDIS_PASSWORD_BILLING_CENTER --cluster-replicas 1 --cluster create $cluster_urls"

            log_debug "执行命令: sudo docker exec -it $redis_name /bin/bash -c \"$REDIS_CLI_COMMAND\""

            sudo docker exec -i "$redis_name" /bin/bash -c "$REDIS_CLI_COMMAND"
            log_info "redis 集群创建完成"
        fi
    }

    log_timer "redis 启动完毕" run

    log_info "redis_billing_center 安装完成, 请使用 sudo docker ps -a 查看容器明细"
}

delete_db_redis_billing_center() {
    log_debug "run delete_db_redis_billing_center"

    local is_delete
    is_delete=$(read_user_input "确认停止 redis_billing_center 服务并删除数据吗(默认n) [y|n]? " "n")

    if [[ "$is_delete" == "y" ]]; then
        stop_db_redis_billing_center

        sudo rm -rf "$DATA_VOLUME_DIR/redis_billing_center"
    fi
}

billing_center_cli() {
  log_debug "run billing_center_cli"

  local arg=$1

  log_debug "执行命令: sudo docker exec -it billing-center /bin/sh -c \"/home/billing-center/billing-center ${arg}\""

  sudo docker exec -it billing-center /bin/sh -c "/home/billing-center/billing-center ${arg}"

}

ca_cert_byte_print() {
  log_debug "run ca-cert-byte-print"
  billing_center_cli "ca-cert-byte-print -n 32"
}

create_docker_compose_billing_center() {
  log_debug "run create_docker_compose_billing_center"

  local version="${1:-latest}"

  local docker_compose_file="$DOCKER_COMPOSE_FILE_BILLING_CENTER"
  if [ -f "$docker_compose_file" ]; then
    sudo rm -f "$docker_compose_file"
  fi

  local img_prefix
  img_prefix=$(get_img_prefix)

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

  log_info "$docker_compose_file create success"
}

copy_billing_center_nginx_config() {

    log_debug "run copy_billing_center_nginx_config"

    dir_billing_center="$DATA_VOLUME_DIR/billing-center/nginx"

    sudo rm -rf "$dir_billing_center"

    # shellcheck disable=SC2329
    run_copy_config() {
        sudo docker cp temp_container_blog_billing_center:/etc/nginx "$DATA_VOLUME_DIR/billing-center" # 复制配置文件
    }

    docker_create_billing_center_temp_container run_copy_config "latest"

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

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 \
        "$DATA_VOLUME_DIR/billing-center" \
        "$DATA_VOLUME_DIR/billing-center/nginx" \
        "$DATA_VOLUME_DIR/billing-center/nginx/ssl"

    if [ -z "$(ls -A "$CERTS_NGINX")" ]; then
        log_error "证书目录 $CERTS_NGINX 为空, 请添加证书文件"

        ssl_msg "$RED"
        exit 1
    fi

    sudo cp -r "$CERTS_NGINX"/* "$DATA_VOLUME_DIR/billing-center/nginx/ssl/"

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR/billing-center/nginx/ssl/"

    log_info "billing-center 复制 nginx 配置文件到 volume success"
}

server_update_password_key_billing_center() {
    log_debug "run server_update_password_key_billing_center"

    local config_dir="$DATA_VOLUME_DIR/billing-center/config"

    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$POSTGRES_PASSWORD_BILLING_CENTER\"%" "$config_dir/pgsql.yaml"

    sudo sed -i "s%password:[[:space:]]*\"[^\"]*\"%password: \"$REDIS_PASSWORD_BILLING_CENTER\"%" "$config_dir/redis.yaml"

    log_info "billing-center 更新数据库密码配置 success"
}

copy_billing_center_server_config() {

    log_debug "run copy_billing_center_server_config"

    dir_billing_center="$DATA_VOLUME_DIR/billing-center/config"

    sudo rm -rf "$dir_billing_center"

    if [ ! -d "./bc-config" ]; then
        local msg=""
        msg+="\n请将 billing_center 配置文件准备好并放置到以下目录: "
        msg+="\n    ./bc-config (配置文件)"
        msg+="\n"
        log_warn "$msg"
        log_warn "bc-config 目录不存在, 请先准备好配置文件后再进行全新安装"
        exit 1
    fi

    cp -r "./bc-config/" "$DATA_VOLUME_DIR/billing-center/config/"

    server_update_password_key_billing_center

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR/billing-center/config/"

    log_info "billing-center 复制后端配置文件到 volume success"
}

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

mkdir_billing_center_volume() {
    log_debug "run mkdir_billing_center_volume"

    if [ ! -d "$DATA_VOLUME_DIR" ]; then
        setup_directory "$JPZ_UID" "$JPZ_GID" 755 "$DATA_VOLUME_DIR"
    fi

    setup_directory "$JPZ_UID" "$JPZ_GID" 755 \
        "$DATA_VOLUME_DIR/billing-center" \
        "$DATA_VOLUME_DIR/billing-center/logs"

    log_info "创建 billing_center volume 目录成功"
}

remove_billing_center_volume() {
    log_debug "run remove_billing_center_volume"

    local confirm
    confirm=$(read_user_input "是否删除 billing_center 相关 volume 数据 (默认n) [y|n]? " "n")
    if [ "$confirm" != "y" ]; then
        log_info "取消删除 billing_center volume 目录"
        return
    fi

    if [ -d "$DATA_VOLUME_DIR/billing-center" ]; then
        sudo rm -rf "$DATA_VOLUME_DIR/billing-center"
        log_info "删除 $DATA_VOLUME_DIR/billing-center 目录成功"
    fi
}

docker_build_billing_center() {
    log_debug "run docker_build_billing_center"

    # shellcheck disable=SC2329
    run() {
        cd "$ROOT_DIR" || exit

        git_clone_cd "billing-center"

        sudo docker build --no-cache -t "$REGISTRY_REMOTE_SERVER/billing-center:build" -f Dockerfile_dev .

        cd "$ROOT_DIR" || exit
        log_debug "脚本所在目录 $(pwd)"
    }

    log_timer "构建 billing-center 镜像" run
}

docker_create_billing_center_temp_container() {
    log_debug "run docker_create_billing_center_temp_container"

    local run_func="$1"
    local version="$2"

    if sudo docker ps -a --format '{{.Names}}' | grep -Eq "^temp_container_blog_billing_center\$"; then
        sudo docker rm -f temp_container_blog_billing_center >/dev/null 2>&1 || true
    fi

    sudo docker create -u "$JPZ_UID:$JPZ_GID" --name temp_container_blog_billing_center "$(get_img_prefix)/billing-center:$version" >/dev/null 2>&1 || true

    $run_func

    sudo docker rm -f temp_container_blog_billing_center >/dev/null 2>&1 || true
}

DIR_ARTIFACTS_BILLING_CENTER="$DATA_VOLUME_DIR/billing-center/artifacts"
DIR_APP_BILLING_CENTER="$DATA_VOLUME_DIR/billing-center/artifacts/billing-center"

billing_center_artifacts_copy_to_local() {
    log_debug "run billing_center_artifacts_copy_to_local"

    local dir_artifacts=$DIR_ARTIFACTS_BILLING_CENTER
    local dir_app=$DIR_APP_BILLING_CENTER

    log_debug "dir_artifacts=====> $dir_artifacts"
    log_debug "dir_app=====> $dir_app"

    if [ ! -d "$dir_artifacts" ]; then
        sudo mkdir -p "$dir_artifacts"
    fi

    if [ -d "$dir_app" ]; then
        sudo rm -rf "$dir_app"
    fi
    sudo mkdir -p "$dir_app"

    # shellcheck disable=SC2329
    run_copy_artifacts() {
        sudo docker cp temp_container_blog_billing_center:/home/billing-center "$dir_artifacts"
    }

    docker_create_billing_center_temp_container run_copy_artifacts "build"

    log_info "billing-center 产物复制到本地, 产物路径: $dir_app"

    log_debug "billing-center 版本: $(sudo cat "$dir_app/VERSION" 2>/dev/null)"
}

billing_center_artifacts_version() {
    local dir_app=$DIR_APP_BILLING_CENTER

    local version
    version=$(sudo cat "$dir_app/VERSION" 2>/dev/null)

    read -r version is_dev <<<"$(parsing_version "$version")"

    echo "$version" "$is_dev"
}

billing_center_artifacts_zip() {
    local version="$1"
    local dir_artifacts=$DIR_ARTIFACTS_BILLING_CENTER
    local dir_app=$DIR_APP_BILLING_CENTER

    local current_dir
    current_dir=$(pwd)

    cd "$dir_app" || exit

    zip_name="billing-center-$version.zip"

    log_debug "需要打包的目录 $(pwd)"

    if [ -z "$(ls -A .)" ]; then
        log_error "billing-center 产物目录为空, 无法打包"
        exit 1
    fi

    # shellcheck disable=SC2329
    run() {
        sudo zip -qr "../$zip_name" ./*
    }

    wait_file_write_complete run "../$zip_name"

    cd "$current_dir" || exit

    sudo rm -rf "$dir_app"

    echo "$dir_artifacts/$zip_name"
}

docker_push_billing_center() {
    log_debug "run docker_push_billing_center"

    billing_center_artifacts_copy_to_local

    local version_info
    version_info=$(billing_center_artifacts_version)
    read -r version is_dev <<<"$version_info"

    docker_tag_push_private_registry "billing-center" "$version"

    echo "不发布到生产环境, 仅推送到私有仓库"

}

docker_pull_billing_center() {
    log_debug "run docker_pull_billing_center"

    local version=${1-latest}

    # shellcheck disable=SC2329
    run() {
        timeout_retry_docker_pull "$REGISTRY_REMOTE_SERVER/billing-center" "$version"
    }
    docker_private_registry_login_logout run
}

wait_billing_center_start() {
    log_debug "run wait_billing_center_start"

    log_warn "等待 billing-center 启动, 这可能需要几分钟时间... 请勿中断！"

    local timeout=300
    local start_time
    start_time=$(date +%s)

    until sudo curl -sk "https://localhost/api/v1/helper/version" | grep -q "request_id"; do
        waiting 5

        local current_time
        current_time=$(date +%s)

        local elapsed_time=$((current_time - start_time))

        if [ "$elapsed_time" -ge "$timeout" ]; then
            log_error "billing-center 启动超时, 请检查日志排查问题."
            exit 1
        fi
    done

    waiting 5

    log_info "billing-center 启动完成"
}

docker_billing_center_start() {
    log_debug "run docker_billing_center_install"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER" up -d

    wait_billing_center_start
}

docker_billing_center_stop() {
    log_debug "run docker_billing_center_stop"
    sudo docker compose -f "$DOCKER_COMPOSE_FILE_BILLING_CENTER" -p "$DOCKER_COMPOSE_PROJECT_NAME_BILLING_CENTER" down || true
}

docker_billing_center_restart() {
    log_debug "run docker_billing_center_restart"
    docker_billing_center_stop
    docker_billing_center_start
}

docker_billing_center_install() {
    log_debug "run docker_billing_center_install"

    local is_install
    is_install=$(read_user_input "是否全新安装 billing_center (y/n)?" "n")

    if [ "$is_install" == "y" ]; then
        mkdir_billing_center_volume
        copy_billing_center_server_config
        copy_billing_center_nginx_config

        create_docker_compose_billing_center
        docker_billing_center_start

        log_info "billing_center 容器启动完成, 请使用 sudo docker ps -a 查看容器明细"

    else
        log_info "退出全新安装"
    fi
}

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

start_or_rollback_billing_center_by_version() {
    log_debug "run start_or_rollback_billing_center_by_version"

    read -r -p "请输入 billing_center 需要升级或回滚的版本号: " version

    if [ -z "$version" ]; then
        log_error "版本号不能为空, 请重新运行脚本并输入正确的版本号"
    fi

    docker_pull_billing_center "$version"

    docker_billing_center_stop

    create_docker_compose_billing_center "$version"

    docker_billing_center_restart

    log_info "服务 billing-center 已成功升级或回滚到版本 $version"
}

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
        log_file="$DATA_VOLUME_DIR/billing-center/logs/app.log"
        filter_cmd=()
        ;;
    2)
        log_file="$DATA_VOLUME_DIR/billing-center/logs/app.log"
        filter_cmd=("grep" "发送验证码")
        ;;
    *)
        log_warn "无效输入：$user_input"
        return 1
        ;;
    esac

    if [ ! -f "$log_file" ]; then
        log_warn "$log_file, 日志文件不存在或当前无日志可查看"
        return 1
    fi

    if [ ${#filter_cmd[@]} -eq 0 ]; then
        tail -f "$log_file"
    else
        tail -f "$log_file" | "${filter_cmd[@]}"
    fi
}

main() {
    disclaimer_msg
    check

    if [ $# -eq 0 ]; then
        show_logo

        print_options "$DISPLAY_COLS" "${OPTIONS_BILLING_CENTER[@]}"

        handle_user_input "${OPTIONS_BILLING_CENTER[@]}"
    else
        for arg in "$@"; do
            if func=$(is_valid_func OPTIONS_BILLING_CENTER_VALID[@] "$arg"); then
                exec_func "$func"
            else
                echo "未找到与输入匹配的函数名称: $arg"
            fi
        done
    fi
}

main "$@"
