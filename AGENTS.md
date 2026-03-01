# AGENTS.md — blog-tool 代码库指南

本文件为在此仓库中运行的 AI 代理(如你自己)提供构建命令、测试方法和代码风格规范。

---

## 项目概览

`blog-tool` 是一个 Bash 脚本工具集, 通过 Docker 在 Debian/Ubuntu 服务器上自动化部署博客系统。
`build.sh` 将模块化脚本合并为三个单文件发行版, 输出到 `dist/` 目录。
`python/` 目录包含辅助工具脚本(changelog 解析), 通过 gzip+base64 嵌入到最终 Shell 脚本中。

---

## 构建命令

```bash
# 构建全部三个发行版(dev / user / billing_center), 输出到 dist/
bash build.sh

# 指定输出目录(可选, 默认为 dist/)
OUTPUT_DIR=/tmp/out bash build.sh
```

构建产物：

| 文件 | 说明 |
| --- | --- |
| `dist/blog-tool-dev.sh` | 开发版, 包含全部功能 |
| `dist/blog-tool.sh` | 用户版, 面向最终用户 |
| `dist/blog-tool-billing-center.sh` | 计费中心版 |

构建脚本同时会将产物复制到上级目录(`../`)。

---

## 测试命令

### Python 单元测试(推荐优先运行)

```bash
# 运行全部测试
cd python && python3 -m pytest test_main.py -v

# 使用 unittest 运行(无需安装 pytest)
cd python && python3 -m unittest test_main.py -v

# 运行单个测试方法(按名称匹配)
cd python && python3 -m unittest test_main.TestMain.test_提取存在的版本_1_2_4_应返回正确内容块 -v

# 运行名称含关键词的测试
cd python && python3 -m pytest test_main.py -k "1_2_4" -v
```

### Shell 脚本语法检查

```bash
# 检查单个脚本(需安装 shellcheck)
shellcheck utils/log.sh

# 批量检查所有脚本
find . -name "*.sh" -not -path "./dist/*" -not -path "./.git/*" | xargs shellcheck
```

### CI 构建(GitHub Actions)

- 触发条件：向 `main` 分支推送且 `CHANGELOG.md` 有变更, 或手动触发 `workflow_dispatch`
- 工作流文件：`.github/workflows/build.yaml`
- 流程：版本号校验 → `bash build.sh` → 提交 dist → 打 git tag

---

## 代码风格规范

### Shell 脚本(`.sh` 文件)

#### 文件头注释(每个文件必须)

```bash
#!/bin/bash
# FilePath    : blog-tool/<相对路径>/<文件名>.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : <简要说明>
```

#### Shebang 与 set

- 所有可执行脚本第一行必须为 `#!/bin/bash`
- 发行版脚本(`dist/` 内)使用 `set -e`, 源模块文件不使用
- 使用 `# shellcheck disable=SC1091` 抑制 source 路径检查
- 使用 `# shellcheck disable=SC2034` 抑制未使用变量警告(配置文件常用)

#### 变量命名

- 全局/配置变量：`UPPER_SNAKE_CASE`(如 `ROOT_DIR`、`LOG_LEVEL`、`DOCKER_HUB_OWNER`)
- 局部变量：`lower_snake_case`, **必须**使用 `local` 声明
- 数组：`UPPER_SNAKE_CASE`, 以 `OPTIONS_` 或描述性前缀开头
- 布尔标志：使用 `true` / `false` 字符串, 而非 `0` / `1`

```bash
# 正确
local file_path="$1"
local -a missing_commands=()

# 错误
filePath="$1"   # 未用 local, 命名风格也不对
```

#### 函数命名与结构

- 函数名：`lower_snake_case`
- 函数参数：用注释标注, 格式为 `# 参数: $1: <说明>`
- 复杂参数用注释块说明；简单参数内联注释即可
- 函数体内先声明所有局部变量, 再执行逻辑

```bash
# 示例函数风格
my_function() {
    local target_file=$1
    local build_type="${2:-dev}"  # 带默认值

    # 校验参数
    if [[ ! -f "$target_file" ]]; then
        echo "❌ 错误：文件 ${target_file} 不存在" >&2
        exit 1
    fi

    # 函数逻辑...
}
```

#### 错误处理

- 错误信息必须输出到 `stderr`(使用 `>&2`)
- 使用 emoji 前缀区分消息类型：`❌` 错误, `⚠️` 警告, `✅` 成功, `ℹ️` 信息
- 遇到不可恢复错误, 直接 `exit 1`；允许用户选择时使用 `exit 0`
- 使用日志函数而非裸 `echo`：`log_error`、`log_warn`、`log_info`、`log_debug`
- 日志函数会自动携带调用位置(文件名:行号), **不要**二次封装这些函数

```bash
# 正确
log_error "数据库连接失败"
echo "❌ 错误：文件 ${file} 不存在" >&2; exit 1

# 错误
echo "error: something failed"  # 不带 >&2, 不用日志函数
```

#### 字符串与引号

- 变量引用**始终**使用双引号：`"$var"`、`"${var}"`
- 数组元素用双引号展开：`"${arr[@]}"`
- 路径拼接使用变量展开, 而非字符串拼接
- heredoc 使用 `<<-EOM` 或 `<<-EOF`(支持缩进剥离)

#### 条件与循环

- 使用 `[[ ]]` 而非 `[ ]`(更安全, 支持正则)
- 数值比较使用 `-eq`、`-gt` 等, 而非 `==`(避免字符串/整数歧义)
- 算术运算使用 `(( ))`
- 读取文件逐行时, 使用 `while IFS= read -r line`

#### source 与模块化

- 每个目录有 `_.sh` 作为统一导出入口, 外部 `source` 只引用 `_.sh`
- 在模块文件内部, 用 `$UTILS_SCRIPT_DIR`(或同类变量)构造绝对路径后再 source

```bash
UTILS_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$UTILS_SCRIPT_DIR/log.sh"
```

#### 注释规范

- 函数级注释紧贴函数定义之前, 说明目的、参数、返回值
- 行内注释使用空格对齐, 放在代码右侧
- 注释语言：**中文**(本项目主语言为中文)
- 区块用 `#` 行与空行分隔, 避免大段连续注释淹没代码

---

### Python 脚本(`python/` 目录)

#### 文件头注释(与 Shell 保持一致)

```python
# FilePath    : blog-tool/python/<文件名>.py
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : <简要说明>
```

#### 代码风格

- 遵循 PEP 8；类型注解按需添加(工具脚本不强制)
- 函数使用 Google 风格 docstring, 参数与返回值均需说明
- 字符串引号：优先双引号
- 导入顺序：标准库 → 第三方库 → 本地模块, 各组之间空一行

#### 测试规范(`test_*.py`)

- 使用 `unittest.TestCase`
- 测试类名：`TestXxx`；测试方法名：`test_<描述>_应<预期结果>`(**中文**)
- 临时文件使用 `tempfile.NamedTemporaryFile`, 在 `finally` 中清理
- 构建时跳过 `test_*.py` 文件(`build.sh` 中已处理)

---

### Markdown 文档(`.md` 文件)

遵循 `.markdownlint.yaml` 配置：

- 列表缩进：4 个空格
- 单行最大长度：120 个字符
- 允许内联 HTML 标签：`<a>`、`<img>`
- 代码块需指定语言(MD040 本项目关闭)
- 允许多个同名标题(MD024 已关闭)

---

## 版本管理规范

- 版本号格式：`vX.Y.Z`, 遵循[语义化版本控制](https://semver.org/lang/zh-CN/)
- 版本号必须以小写 `v` 开头
- 每次发版**必须先更新** `CHANGELOG.md`, CI 会自动从中提取版本号并打 tag
- commit message 格式：`<Type>(<Scope>): <Subject>`(支持 Unicode/emoji Type)
- CHANGELOG 格式遵循 [Keep a Changelog](https://keepachangelog.com/) 规范

---

## 目录结构说明

```text
build.sh                # 构建脚本(将模块合并为发行版)
dist/                   # 构建产物(勿手动修改)
config/
  internal.sh           # 内部配置(不可修改, 除非你清楚后果)
  user.sh               # 用户可编辑配置
  dev.sh                # 开发环境配置
options/                # 菜单选项定义(OPTIONS_ALL / OPTIONS_USER 等数组)
utils/                  # 工具函数(log、print、check、docker、db 等)
  _.sh                  # 统一导出入口
system/                 # 系统工具(apt、ssh、用户管理)
docker/                 # Docker 安装与管理
db/                     # 数据库(PostgreSQL、Redis、ES)
server/                 # 后端服务部署
client/                 # 前端服务部署
billing-center/         # 计费中心部署
python/                 # Python 辅助工具(嵌入到发行版中)
  main.py               # 工具函数实现
  test_main.py          # 单元测试(构建时跳过)
```

---

## 关键约定

1. **不要修改 `dist/` 内的文件**, 它们由 `build.sh` 自动生成
2. **不要修改 `config/internal.sh`**, 除非你完全清楚影响范围
3. 新增功能函数需同时在 `options/all.sh` 的对应数组中注册
4. `utils/log.sh` 中的 `log_error/warn/info/debug` 依赖 `BASH_SOURCE` 取行号, **不能再次封装**
5. 所有 Shell 脚本必须通过 `shellcheck` 静态检查, 无 error 级别警告
6. Python 测试必须通过后才能合入, 确保 `python3 -m unittest test_main.py` 零失败
