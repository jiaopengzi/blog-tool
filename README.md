# blog-tool

博客系统部署工具，通过 Docker 在 Debian Ubuntu 服务器上自动化部署完整的博客系统。

**实际应用案例：[https://jiaopengzi.com](https://jiaopengzi.com)**

## 系统要求

- **操作系统**: Debian 13 (Trixie)+ | Ubuntu 24.04+
- **架构**: x86_64 (amd64)
- **权限**: root 或具有 sudo 权限的用户

## 快速开始

### 1. 获取工具

#### Gitee (国内用户)

```bash
curl -fsSL -o blog-tool.sh https://gitee.com/jiaopengzi/blog-tool/raw/main/dist/blog-tool.sh
```

#### GitHub

```bash
curl -fsSL -o blog-tool.sh https://raw.githubusercontent.com/jiaopengzi/blog-tool/main/dist/blog-tool.sh
```

### 2. 工具使用

```bash
sudo bash blog-tool.sh
```

工具下载好后直接使用如上命令执行即可看到命令面板。

<img width="800" alt="image" src="https://github.com/user-attachments/assets/3724fa21-6bb3-43ae-854f-f747ea89ddfe" />

### 3. 零交互一键安装

如果需要在全新服务器上跳过命令面板和确认提示, 可以使用 `--auto` 模式，推荐在自己没有域名内网使用：

```bash
sudo bash blog-tool.sh --auto
```

也可以直接下载、保存并立即执行, 省去手动下载后再运行的步骤。

#### Gitee (国内用户)

```bash
curl -fsSL -o blog-tool.sh https://gitee.com/jiaopengzi/blog-tool/raw/main/dist/blog-tool.sh && sudo bash blog-tool.sh --auto
```

#### GitHub

```bash
curl -fsSL -o blog-tool.sh https://raw.githubusercontent.com/jiaopengzi/blog-tool/main/dist/blog-tool.sh && sudo bash blog-tool.sh --auto
```

如果需要传入可选参数, 将参数追加到 `--auto` 后即可：

```bash
curl -fsSL -o blog-tool.sh https://gitee.com/jiaopengzi/blog-tool/raw/main/dist/blog-tool.sh && sudo bash blog-tool.sh --auto --domain=example.com --project_name=blog-server
```

`--auto` 会自动接受免责声明, 安装基础依赖和 Docker, 拉取生产镜像, 初始化数据库, 并安装 `blog-server` 与 `blog-client`。如果当前机器已经安装 Docker, 脚本会直接退出, 避免覆盖已有 Docker 环境。

**零交互完整示例** 推荐自备域名和证书首次安装使用，先下载工具再执行如下零交互脚本（注意将参数内容换成自己的实际的内容）：

```bash
sudo bash blog-tool.sh --auto \
 --domain=example.com \
 --project_name=blog-server \
 --public_ip=1.2.3.4 \
 --cert=/your/path/cert.pem \
 --cert_key=/your/path/cert.key \
 --admin_username=admin \
 --admin_email=admin@example.com \
 --admin_password='Password123'
```

参数说明：

| 参数 | 是否必填 | 说明 |
| --- | --- | --- |
| `--domain` | 否 | 访问域名, 不要带 `http://` 或 `https://` |
| `--project_name` | 否 | 项目名称, 仅允许字母, 数字, 下划线和短横线 |
| `--public_ip` | 否 | 当前服务器公网 IPv4 地址 |
| `--cert` | 否 | nginx HTTPS 证书文件路径, 提供时必须同时提供 `--cert_key` |
| `--cert_key` | 否 | nginx HTTPS 私钥文件路径, 提供时必须同时提供 `--cert` |
| `--admin_username` | 否 | 管理员用户名, 提供任一 `--admin_*` 参数时三项都必须提供 |
| `--admin_email` | 否 | 管理员邮箱, 提供任一 `--admin_*` 参数时三项都必须提供 |
| `--admin_password` | 否 | 管理员密码, 提供任一 `--admin_*` 参数时三项都必须提供 |

说明：

- `--domain`、`--project_name`、`--public_ip` 不传时, 脚本会优先读取 `blog_tool_env` 中已有配置; 没有配置文件时使用默认值继续安装, 不会进入交互输入。
- `--cert` 和 `--cert_key` 都不传时, 脚本跳过 nginx 证书复制; 只传其中一个会报错退出。
- `--admin_username`、`--admin_email`、`--admin_password` 都不传时, 脚本跳过管理员自动注册; 只传其中任意一个会报错退出。
- 管理员用户名必须是 6-20 位小写字母或数字; 管理员密码必须是 6-64 位, 且包含大写字母, 小写字母和数字。
- `--auto` 拉取生产镜像时默认包含 PostgreSQL、Redis、Elasticsearch 数据库镜像。

### 4. 卸载当前安装

用户版支持通过 `--uninstall` 卸载当前 `blog-tool.sh` 安装的项目：

```bash
sudo bash blog-tool.sh --uninstall
```

执行后脚本会先逐项询问您是否需要执行以下清理动作, 再按您的选择依次执行：

- 停止并删除当前项目容器
- 删除当前项目涉及的 Docker 镜像
- 删除当前项目 volume 数据目录
- 卸载 Docker 软件
- 删除 `blog-tool` 日志文件

说明：

- `--uninstall` 仅支持用户版 `blog-tool.sh`, 不支持 `blog-tool-dev.sh` 和 `blog-tool-billing-center.sh`。
- 删除 volume 时会移除当前工具的数据根目录, 因此会一并删除数据库数据、服务配置、证书、docker compose 文件和 `blog_tool_env` 状态文件。
- 为避免镜像删除失败, 卸载流程会额外清理本工具可能残留的临时容器和项目网络。
- 卸载完成后, 脚本会提示当前脚本文件路径; 脚本文件本身不会自删, 需要您手动删除。

## 技术栈

| 组件 | 技术 | 说明 |
| --- | --- | --- |
| 后端 | blog-server (Go) | Docker 容器化部署 |
| 前端 | blog-client (Nginx) | Docker 容器化部署 |
| 数据库 | PostgreSQL 18.3 | 支持自定义配置 |
| 缓存 | Redis 8.6.2 | 支持单节点和集群模式 |
| 搜索引擎 | Elasticsearch 9.3.3 | 支持多节点集群、IK 分词器、Kibana |
| 证书 | 自签名 CA + SSL/TLS | 自动生成 |

## 构建版本

项目通过 `build.sh` 将模块化脚本合并为单文件发行版：

| 版本 | 文件 | 说明 |
| --- | --- | --- |
| 用户版 | `blog-tool.sh` | 博客部署，面向最终用户 |
| 计费中心版 | `blog-tool-billing-center.sh` | 计费中心部署 |
| 开发版 | `blog-tool-dev.sh` | 含全部功能，面向开发者 |

## 单镜像构建

开发版 `--build-single` 命令, 用于将 `blog-client`、`blog-server-dev`、PostgreSQL、Redis、Elasticsearch 打包为一个独立镜像 `blog`。

### 1. 构建并推送单镜像

按 `env -> build -> push` 分阶段执行:

```bash
sudo bash blog-tool-dev.sh --env-single
sudo bash blog-tool-dev.sh --build-single --version v1.0.0
sudo bash blog-tool-dev.sh --push-single --version v1.0.0
```

单镜像的目标机部署只依赖 Docker, 不需要再安装 `blog-tool-dev.sh`。

也可以单独执行 `--build-single` 或 `--push-single`, 如果未传 `--version`, 脚本会提示输入单镜像版本号。

默认 `--push-single` 只推送到 `REGISTRY_REMOTE_SERVER_PUBLIC/blog`。如果需要额外推送腾讯云或 Docker Hub, 需要显式加参数:

```bash
sudo bash blog-tool-dev.sh --push-single --version v1.0.0 --push-tencent
sudo bash blog-tool-dev.sh --push-single --version v1.0.0 --push-docker-hub
sudo bash blog-tool-dev.sh --push-single --version v1.0.0 --push-tencent --push-docker-hub
```

推送顺序如下:

1. 默认推送到 `REGISTRY_REMOTE_SERVER_PUBLIC/blog`。
2. 仅在显式传入 `--push-tencent` 时, 才尝试增量推送到 `REGISTRY_REMOTE_SERVER_TENCENT/blog`。
3. 仅在显式传入 `--push-docker-hub` 时, 才尝试增量推送到 `docker.io/jiaopengzi/blog`。

当腾讯云或 Docker Hub 凭据未配置时, 对应增量推送会自动跳过, 不影响默认公开仓库推送。

### 2. 运行单镜像

单镜像约定只挂载一个总目录, 默认使用 HTTPS, 并在首次启动时自动生成 CA 证书与 HTTPS 证书。若第二次启动发现证书已存在, 则不会重复生成。

single 镜像会根据可见内存自动选择更保守的 ES、PostgreSQL、Nginx 参数。若是 4G 左右机器, 建议在启动容器前, 直接在部署宿主机执行一次如下命令。

```bash
sudo sysctl vm.overcommit_memory=1
```

如需手动覆盖自动档位, 可在 `docker run` 时传入以下环境变量:

- `BLOG_MEMORY_PROFILE=small`
- `BLOG_ES_JAVA_OPTS=-Xms384m -Xmx384m`
- `BLOG_PG_SHARED_BUFFERS=64MB`
- `BLOG_PG_MAX_CONNECTIONS=40`

使用宿主机内网 IP 部署。

```bash
HOST_IP="$(hostname -I | awk '{print $1}')" && sudo docker run -d \
  --name blog \
  -p 443:443 \
  -v /data/blog:/data \
  -e BLOG_PUBLIC_HOST="$HOST_IP" \
  jiaopengzi/blog:latest
```

首次启动后, 可从宿主机挂载目录导出 CA 证书:

```bash
/data/blog/certs/internal-ca/ca.crt
```

使用自定义证书以及和域名

```bash
sudo docker run -d \
  --name blog \
  -p 443:443 \
  -v /data/blog:/data \
  -v /your/path/cert.pem:/data/blog-client/nginx/ssl/cert.pem \
  -v /your/path/cert.key:/data/blog-client/nginx/ssl/cert.key \
  -e BLOG_PUBLIC_HOST=blog.example.com \
  jiaopengzi/blog:latest
```

启动收可以使用查看状态

```bash
sudo docker ps -a | grep blog

sudo docker log blog
```

同时使用如下 curl 校验是否通畅

在部署机执行 `curl -vk https://127.0.0.1:443`，先确认宿主机本地 HTTPS 是否通。

在外部机器执行 `curl -vk https://blog.example.com/`，再看是 DNS、链路还是证书链问题。

如果您更习惯先把证书整理到数据目录, 也可以预先放到
`/data/blog/blog-client/nginx/ssl/cert.pem` 和
`/data/blog/blog-client/nginx/ssl/cert.key`, 再只挂载 `-v /data/blog:/data` 启动。

常用运行时环境变量:

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `BLOG_PUBLIC_HOST` | `localhost` | 对外访问域名或 IP, 用于生成默认证书和后端 host |
| `BLOG_HTTPS_PORT` | `443` | 容器内 HTTPS 监听端口 |
| `BLOG_PG_PORT` | `15432` | 容器内 PostgreSQL 监听端口 |
| `BLOG_REDIS_PORT` | `16379` | 容器内 Redis 监听端口 |
| `BLOG_ES_PORT` | `19200` | 容器内 Elasticsearch HTTPS 监听端口 |

说明:

- 仅执行 `sudo docker run -d blog:latest` 不会自动发布宿主机端口, 仍需显式添加 `-p 443:443`, 否则无法从宿主机或局域网访问; 启动摘要也会用 warning 明确提示这一点。
- 数据库默认不占用容器内常见端口, 如果需要对外连接数据库, 请自行增加端口映射, 例如 `-p 5432:15432`。
- Elasticsearch 内置 IK 分词器, 默认保留空的 `my.dic`, 可在挂载目录中按需维护。

## 项目结构

```text
├── build.sh                # 构建脚本
├── config/                 # 配置文件
│   ├── internal.sh         # 内部配置 (不可修改)
│   ├── user.sh             # 用户配置
│   └── dev.sh              # 开发配置
├── options/                # 菜单选项定义
├── system/                 # 系统工具 (apt、软件安装、SSH)
├── docker/                 # Docker 安装与管理
├── db/                     # 数据库 (PostgreSQL、Redis、ES)
├── server/                 # 后端服务部署
├── client/                 # 前端服务部署
├── billing-center/         # 计费中心部署
└── utils/                  # 工具函数集合
```

## 版本管理

项目遵循[语义化版本控制](https://semver.org/lang/zh-CN/)，版本号格式为 `vX.Y.Z`。

## 获取指定版本工具

### Gitee (国内用户)

```bash

curl -fsSL -o blog-tool.sh https://gitee.com/jiaopengzi/blog-tool/raw/v0.4.1/dist/blog-tool.sh
```

### GitHub

```bash
curl -fsSL -o blog-tool.sh https://raw.githubusercontent.com/jiaopengzi/blog-tool/v0.4.1/dist/blog-tool.sh
```

## 许可证

[MIT](LICENSE) © 焦棚子
