# blog-tool

博客系统一键部署工具，通过 Docker 在 Debian Ubuntu 服务器上自动化部署完整的博客系统。

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

如果需要在全新服务器上跳过命令面板和确认提示, 可以使用 `--auto` 模式：

```bash
sudo bash blog-tool.sh --auto
```

也可以直接下载、保存并立即执行, 省去手动下载后再运行的步骤。

#### Gitee (国内用户)

```bash
curl -fsSL https://gitee.com/jiaopengzi/blog-tool/raw/main/dist/blog-tool.sh | tee blog-tool.sh | sudo bash -s -- --auto
```

#### GitHub

```bash
curl -fsSL https://raw.githubusercontent.com/jiaopengzi/blog-tool/main/dist/blog-tool.sh | tee blog-tool.sh | sudo bash -s -- --auto
```

如果需要传入可选参数, 将参数追加到 `--auto` 后即可：

```bash
curl -fsSL https://gitee.com/jiaopengzi/blog-tool/raw/main/dist/blog-tool.sh | tee blog-tool.sh | sudo bash -s -- --auto --domain=example.com --project_name=blog-server
```

`--auto` 会自动接受免责声明, 安装基础依赖和 Docker, 拉取生产镜像, 初始化数据库, 并安装
`blog-server` 与 `blog-client`。如果当前机器已经安装 Docker, 脚本会直接退出, 避免覆盖已有
Docker 环境。

零交互完整示例：

```bash
sudo bash blog-tool.sh --auto \
 --domain=example.com \
 --project_name=blog-server \
 --public_ip=1.2.3.4 \
 --cert=/your/path/cert.pem \
 --cert_key=/your/path/cert.key \
 --admin_username=admin01 \
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

- `--domain`、`--project_name`、`--public_ip` 不传时, 脚本会优先读取 `blog_tool_env` 中已有配置;
 没有配置文件时使用默认值继续安装, 不会进入交互输入。
- `--cert` 和 `--cert_key` 都不传时, 脚本跳过 nginx 证书复制; 只传其中一个会报错退出。
- `--admin_username`、`--admin_email`、`--admin_password` 都不传时, 脚本跳过管理员自动注册;
 只传其中任意一个会报错退出。
- 管理员用户名必须是 6-20 位小写字母或数字; 管理员密码必须是 6-64 位, 且包含大写字母,
 小写字母和数字。
- `--auto` 拉取生产镜像时默认包含 PostgreSQL、Redis、Elasticsearch 数据库镜像。

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
