# blog-tool

博客系统一键部署工具，通过 Docker 在 Debian 服务器上自动化部署完整的博客系统。

## 系统要求

- **操作系统**: Debian 13 (Trixie)+
- **架构**: x86_64 (amd64)
- **权限**: root 或具有 sudo 权限的用户

## 快速开始

### 1. 获取工具

#### GitHub

```bash
curl -fsSL -o blog-tool.sh https://raw.githubusercontent.com/jiaopengzi/blog-tool/main/dist/blog-tool.sh
```

#### Gitee (国内用户)

```bash
curl -fsSL -o blog-tool.sh https://gitee.com/jiaopengzi/blog-tool/raw/main/dist/blog-tool.sh
```

### 2. 工具使用

```bash
sudo bash blog-tool.sh
```

工具下载好后直接使用如上命令执行即可看到命令面板。

<img width="800" alt="image" src="https://github.com/user-attachments/assets/3724fa21-6bb3-43ae-854f-f747ea89ddfe" />

## 技术栈

| 组件 | 技术 | 说明 |
| --- | --- | --- |
| 后端 | blog-server (Go) | Docker 容器化部署 |
| 前端 | blog-client (Nginx) | Docker 容器化部署 |
| 数据库 | PostgreSQL 18+ | 支持自定义配置 |
| 缓存 | Redis 8.4+ | 支持单节点和集群模式 |
| 搜索引擎 | Elasticsearch 9.2+ | 支持多节点集群、IK 分词器、Kibana |
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

## 许可证

[MIT](LICENSE) © 焦棚子
