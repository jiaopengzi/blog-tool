# FilePath    : blog-tool/python/test_extract_changelog_block.py
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 测试 extract_changelog_block.py 中的 extract_changelog_block 函数

import unittest
import tempfile
import os
from main import extract_changelog_block, extract_changelog_version_date


class TestMain(unittest.TestCase):
    """
    测试 main.py 中的函数:
        extract_changelog_block
        extract_changelog_version_date
    """

    def setUp(self):
        """
        在每个测试方法运行前执行, 准备一个模拟的 changelog 文件内容,
        包含多个版本, 如 1.2.3、1.2.2、1.2.1 等
        """
        self.changelog_content = """# Changelog

本文件将记录本项目的所有重要变更。

该格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), 
本项目遵循 [语义化版本控制](https://semver.org/spec/v2.0.0.html)。
测试用例分别有以下版本记录：

## [1.2.4] - 2024-06-01
数字版本无链接
### Fixed
- 修复文章列表加载慢的问题

## [v1.2.3](https://github.com/jiaopengzi/blog-server/releases/tag/v1.0.5) - 2024-06-01
数字版本包含链接
### Added
- 新增用户评论功能 [#123](https://github.com/jiaopengzi/test-changelog/issues/123)

## [v1.0.1] - 2024-06-01
包含前缀 v 的版本无链接
### Changed
- 优化数据库查询性能

## [v1.0.0-stable+251112] - 2024-06-01
包含前缀 v 和release/build 后缀的版本无链接+元数据
### Added
- 支持 Markdown 格式的文章编辑

## [v0.5.1-beta+251112] - 2024-06-01
包含前缀 v 和 pre-release / build 后缀的版本无链接+元数据
### Fixed
- 修复图片上传失败的问题

## [v0.4.1-alpha+251112] - 2024-06-01
包含前缀 v 和 pre-release / build 后缀的版本无链接+元数据
### Changed
- 更新依赖库至最新版本

## [v0.3.1-rc+251112] - 2024-06-01
包含前缀 v 和 pre-release / build 后缀的版本无链接+元数据
### Added
- 增加站内搜索功能
- 改进用户界面设计

## [v0.2.1-nightly+251112] - 2024-06-01
包含前缀 v 和 pre-release / build 后缀的版本无链接+元数据
### Changed
- 重构了用户权限模块
- 新增文章点赞功能

## [v0.1.1-dev+251112] - 2024-06-01
包含前缀 v 和 pre-release / build 后缀的版本无链接+元数据
### Added
- 初始开发版本
"""

    # 1.2.4
    def test_提取存在的版本_1_2_4_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            # 调用函数
            result = extract_changelog_block(temp_file_path, "1.2.4")
            # 校验结果
            self.assertIn("数字版本无链接", result)
            self.assertIn("修复文章列表加载慢的问题", result)

            # 验证标题是否正确
            self.assertIn(
                "## [1.2.4] - 2024-06-01",
                result,
            )
        finally:
            # 删除临时文件
            os.unlink(temp_file_path)

    # v1.2.3
    def test_提取存在的版本_1_2_3_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            # 调用函数
            result = extract_changelog_block(temp_file_path, "v1.2.3")
            # 校验结果
            self.assertIn(
                "新增用户评论功能 [#123](https://github.com/jiaopengzi/test-changelog/issues/123)",
                result,
            )

            # 验证标题是否正确
            self.assertIn(
                "## [v1.2.3](https://github.com/jiaopengzi/blog-server/releases/tag/v1.0.5) - 2024-06-01",
                result,
            )
        finally:
            # 删除临时文件
            os.unlink(temp_file_path)

    # v1.0.1
    def test_提取存在的版本_v1_0_1_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "v1.0.1")
            self.assertIn("优化数据库查询性能", result)
            self.assertIn("## [v1.0.1] - 2024-06-01", result)
        finally:
            os.unlink(temp_file_path)

    # v1.0.0-stable+251112
    def test_提取存在的版本_v1_0_0_stable_带构建元数据_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "v1.0.0-stable+251112")
            self.assertIn("支持 Markdown 格式的文章编辑", result)
            self.assertIn("## [v1.0.0-stable+251112] - 2024-06-01", result)
        finally:
            os.unlink(temp_file_path)

    # v0.5.1-beta+251112
    def test_提取存在的版本_v0_5_1_beta_带构建元数据_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "v0.5.1-beta+251112")
            self.assertIn("修复图片上传失败的问题", result)
            self.assertIn("## [v0.5.1-beta+251112] - 2024-06-01", result)
        finally:
            os.unlink(temp_file_path)

    # v0.4.1-alpha+251112
    def test_提取存在的版本_v0_4_1_alpha_带构建元数据_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "v0.4.1-alpha+251112")
            self.assertIn("更新依赖库至最新版本", result)
            self.assertIn("## [v0.4.1-alpha+251112] - 2024-06-01", result)
        finally:
            os.unlink(temp_file_path)

    # v0.3.1-rc+251112
    def test_提取存在的版本_v0_3_1_rc_带构建元数据_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "v0.3.1-rc+251112")
            self.assertIn("增加站内搜索功能", result)
            self.assertIn("改进用户界面设计", result)
            self.assertIn("## [v0.3.1-rc+251112] - 2024-06-01", result)
        finally:
            os.unlink(temp_file_path)

    # v0.2.1-nightly+251112
    def test_提取存在的版本_v0_1_1_dev_带构建元数据_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "v0.1.1-dev+251112")
            self.assertIn("初始开发版本", result)
            self.assertIn("## [v0.1.1-dev+251112] - 2024-06-01", result)
        finally:
            os.unlink(temp_file_path)

    # v0.2.1-nightly+251112
    def test_提取存在的版本_v0_2_1_nightly_带构建元数据_应返回正确内容块(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "v0.2.1-nightly+251112")
            self.assertIn("重构了用户权限模块", result)
            self.assertIn("新增文章点赞功能", result)
            self.assertIn("## [v0.2.1-nightly+251112] - 2024-06-01", result)
        finally:
            os.unlink(temp_file_path)

    def test_提取不存在的版本号_如_9_9_9_应返回空字符串(self):
        """
        测试传入一个不存在的版本号, 比如 "9.9.9", 应该返回空字符串 ""
        """
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_block(temp_file_path, "9.9.9")
            self.assertEqual(result, "")  # 不存在则返回空
        finally:
            os.unlink(temp_file_path)

    def test_传入不存在的_changelog_文件路径_应抛出异常(self):
        """
        测试当传入一个不存在的 changelog 文件路径时, 应该抛出 FileNotFoundError 异常
        """
        with self.assertRaises(FileNotFoundError):
            extract_changelog_block("这个文件肯定不存在.txt", "1.2.3")

    def test_提取所有版本号及其发布日期_应返回正确列表(self):
        with tempfile.NamedTemporaryFile(
            mode="w+", encoding="utf-8", suffix=".md", delete=False
        ) as temp_file:
            temp_file.write(self.changelog_content)
            temp_file_path = temp_file.name

        try:
            result = extract_changelog_version_date(temp_file_path)
            expected = [
                ("1.2.4", "2024-06-01"),
                ("v1.2.3", "2024-06-01"),
                ("v1.0.1", "2024-06-01"),
                ("v1.0.0-stable+251112", "2024-06-01"),
                ("v0.5.1-beta+251112", "2024-06-01"),
                ("v0.4.1-alpha+251112", "2024-06-01"),
                ("v0.3.1-rc+251112", "2024-06-01"),
                ("v0.2.1-nightly+251112", "2024-06-01"),
                ("v0.1.1-dev+251112", "2024-06-01"),
            ]
            self.assertEqual(result, expected)
        finally:
            os.unlink(temp_file_path)


if __name__ == "__main__":
    unittest.main()
