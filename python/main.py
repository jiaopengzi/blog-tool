# FilePath    : blog-tool/python/main.py
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : python 相关工具集合

import argparse
import re
from datetime import datetime


"""
版本号二级标题的 markdown 示例：
## [1.3.0](https://github.com/jiaopengzi/blog-server/releases/tag/v1.0.5) - 2024-06-01
## [1.2.4] - 2024-06-01
## [v1.2.3](https://github.com/jiaopengzi/blog-server/releases/tag/v1.0.5) - 2024-06-01
## [v1.0.1] - 2024-06-01
## [v1.0.0-stable+251112] - 2024-06-01
## [v0.5.1-beta+251112] - 2024-06-01
## [v0.4.1-alpha+251112] - 2024-06-01
## [v0.3.1-rc+251112] - 2024-06-01
## [v0.2.1-nightly+251112] - 2024-06-01
## [v0.1.1-dev+251112] - 2024-06-01
"""


def extract_changelog_block(changelog_path, version):
    """按照输入版本号提取遵循 [keep a changelog](https://keepachangelog.com/) 规范的 changelog 文件中对应版本的更新内容块

    Args:
        changelog_path (string): changelog 的路径
        version (string): 版本号, 例如 "1.2.3" "v1.2.3" "v1.0.0-alpha+123"

    Returns:
        string: 返回该版本更新内容
    """

    # 读取 changelog 文件内容
    with open(changelog_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 使用正则表达式提取指定版本的内容
    # 支持版本前缀 v 或不带 v(例如 1.2.3 或 v1.2.3)，并能匹配带有 pre-release / build 后缀与可选链接的标题
    ver = version.strip().lstrip("vV")

    # 匹配形如: ## [v1.0.0-alpha+123](...) - 2024-06-01 捕获从该标题到下一个 "## [" 或文件末尾的内容
    pattern = rf"^(##\s*\[\s*(?:v?{re.escape(ver)})[^\]]*\]\s*(?:\([^\)]*\))?.*?)(?=^##\s*\[|\Z)"

    # 查找匹配的版本块
    match = re.search(pattern, content, re.DOTALL | re.IGNORECASE | re.MULTILINE)

    # 返回匹配的内容, 去除前后空白
    return match.group(1).strip() if match else ""


def extract_changelog_version_date(changelog_path):
    """提取遵循 [keep a changelog](https://keepachangelog.com/) 规范的 changelog 文件中的所有版本号及其发布日期

    Args:
        changelog_path (string): changelog 的路径

    Returns:
        string: 返回数组, 按照发布日期降序排列 包含所有版本号及其发布日期, 格式为 [(date, version), ...]
    """

    # 读取 changelog 文件内容
    with open(changelog_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 支持版本前缀 v 或不带 v(例如 1.2.3 或 v1.2.3)，并能匹配带有 pre-release / build 后缀与可选链接的标题
    # 匹配形如: ## [v1.0.0-alpha+123](...) - 2024-06-01
    pattern = r"^##\s*\[\s*(v?\d+\.\d+\.\d+(?:-[\w\.\+]+)?)\s*\](?:\([^\)]*\))?\s*-\s*(\d{4}-\d{2}-\d{2})"
    matches = re.findall(pattern, content, re.IGNORECASE | re.MULTILINE)

    # 按照发布日期降序排列
    matches.sort(key=lambda x: x[1], reverse=True)

    # 将日期格式化为 YYYY-MM-DD 格式
    matches = [
        (version, datetime.strptime(date_str, "%Y-%m-%d").strftime("%Y-%m-%d"))
        for version, date_str in matches
    ]

    return matches  # 返回版本号及其发布日期列表


if __name__ == "__main__":
    # 多函数命令行工具入口, 支持添加更多 python 相关工具函数
    # 第一个参数为子命令即函数名称, 后续参数为该函数的参数
    parser = argparse.ArgumentParser(description="Python 相关工具集合")
    subparsers = parser.add_subparsers(dest="command", help="可用命令")

    # 添加 extract_changelog_block 子命令
    parser_changelog = subparsers.add_parser(
        "extract_changelog_block", help="提取 changelog 文件中指定版本的更新内容块"
    )
    parser_changelog.add_argument("changelog_path", type=str, help="changelog 文件路径")
    parser_changelog.add_argument(
        "version", type=str, help="版本号 (例如: 1.2.3 或 v1.2.3)"
    )

    # 添加 extract_changelog_version_date 子命令
    parser_version_date = subparsers.add_parser(
        "extract_changelog_version_date",
        help="提取 changelog 文件中的所有版本号及其发布日期",
    )
    parser_version_date.add_argument(
        "changelog_path", type=str, help="changelog 文件路径"
    )

    # 解析命令行参数
    args = parser.parse_args()
    if args.command == "extract_changelog_block":
        result = extract_changelog_block(args.changelog_path, args.version)
        if result:
            print(result)
        else:
            print("")

    elif args.command == "extract_changelog_version_date":
        result = extract_changelog_version_date(args.changelog_path)
        for version, date in result:
            print(f"{version} {date}")
