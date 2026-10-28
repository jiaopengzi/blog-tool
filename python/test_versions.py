# FilePath    : blog-tool/python/test_versions.py
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Description : 检查依赖清单, Docker 构建传参与发行版嵌入, 不执行真实 Docker 命令.

import base64
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BUILD_ARGS = {
    "NODE_VERSION": "IMG_VERSION_NODE",
    "UBUNTU_VERSION": "IMG_VERSION_UBUNTU",
    "POSTGRES_VERSION": "IMG_VERSION_PGSQL",
    "POSTGRES_MAJOR": "IMG_VERSION_PGSQL_MAJOR",
    "REDIS_VERSION": "IMG_VERSION_REDIS",
    "ELASTICSEARCH_VERSION": "IMG_VERSION_ES",
    "NGINX_VERSION": "DEP_VERSION_NGINX",
    "UBUNTU_CODENAME": "SINGLE_UBUNTU_CODENAME",
    "NGINX_PACKAGE_SUFFIX": "SINGLE_NGINX_PACKAGE_SUFFIX",
}


class TestVersions(unittest.TestCase):
    """检查版本维护链路, 不访问网络, Docker 或现有业务数据."""

    def run_bash(self, script):
        """运行隔离 Bash 检查并返回输出, 执行失败时抛出异常.

        Args:
            script: 要执行的 Bash 代码.

        Returns:
            标准输出字符串.
        """
        return subprocess.run(
            ["bash", "-c", "set -eu\n" + script],
            cwd=ROOT, check=True, capture_output=True, text=True,
        ).stdout

    def test_关联版本_应由唯一声明派生(self):
        """检查派生关系与源码加载顺序, 不一致时断言失败."""
        self.run_bash("""
source config/versions.sh
[[ "$IMG_VERSION_PGSQL_MAJOR" == "${IMG_VERSION_PGSQL%%.*}" ]]
[[ "$IMG_VERSION_KIBANA" == "$IMG_VERSION_ES" ]]
[[ "$IMG_VERSION_GOLANG" == "${DEP_VERSION_GOLANG}-alpine" ]]
[[ "$IMG_VERSION_NGINX" == "${DEP_VERSION_NGINX}-alpine" ]]
[[ "$SINGLE_NGINX_PACKAGE_SUFFIX" == "1~${SINGLE_UBUNTU_CODENAME}" ]]
""")
        loader = (ROOT / "config/_.sh").read_text()
        self.assertLess(loader.index("/versions.sh"), loader.index("/dev.sh"))
        self.assertLess(loader.index("/versions.sh"), loader.index("/internal.sh"))
        for filename in ("config/dev.sh", "config/internal.sh"):
            self.assertNotRegex(
                (ROOT / filename).read_text(),
                r"(?m)^IMG_VERSION_[A-Z_]+=",
            )

    def test_构建参数_应跟随清单并保留原命令选项(self):
        """以模拟 sudo 捕获构建参数, 缺失或未跟随配置时断言失败."""
        overrides = "\n".join(
            f'{variable}="probe-{argument.lower()}"'
            for argument, variable in BUILD_ARGS.items()
        )
        output = self.run_bash("""
ROOT_DIR="$PWD"
source config/versions.sh
source single/build.sh
SINGLE_CONTEXT_DIR="$PWD"
log_debug() { :; }
log_info() { :; }
single_has_local_image() { return 1; }
sudo() { printf '%s\\n' "$@"; }
""" + overrides + '\nsingle_build_env_image "true"\n')
        arguments = output.splitlines()
        for argument in BUILD_ARGS:
            value = f"{argument}=probe-{argument.lower()}"
            self.assertIn(value, arguments)
            self.assertEqual(arguments[arguments.index(value) - 1], "--build-arg")
        self.assertEqual(arguments[:5], [
            "DOCKER_BUILDKIT=1", "docker", "build", "--no-cache", "--progress=plain",
        ])

    def test_Dockerfile_应只声明依赖参数而不维护版本默认值(self):
        """检查依赖参数与 Node 库文件自动匹配, 漏声明或重复写版本时断言失败."""
        for filename in ("Dockerfile", "env.Dockerfile"):
            content = (ROOT / "single/docker" / filename).read_text()
            with self.subTest(filename=filename):
                for argument in BUILD_ARGS:
                    self.assertRegex(content, rf"(?m)^ARG {argument}$")
                    self.assertNotRegex(content, rf"(?m)^ARG {argument}=")
                self.assertIn("${UBUNTU_CODENAME}-pgdg", content)
                self.assertIn("${NGINX_VERSION}-${NGINX_PACKAGE_SUFFIX}", content)
                self.assertIn(
                    "COPY --from=node-runtime /usr/lib/libgcc_s.so.1 "
                    "/usr/lib/libstdc++.so.6* /usr/lib/", content,
                )
                self.assertNotIn("NODE_LIBSTDCXX_VERSION", content)

    def test_下载地址_应跟随清单且保留浮动策略(self):
        """检查 Cosign 通道引用, 不一致时断言失败."""
        self.assertIn(
            "releases/${COSIGN_RELEASE_CHANNEL}",
            (ROOT / "system/software.sh").read_text(),
        )

    def test_三种发行版_应先嵌入版本清单且保留Docker资产(self):
        """在临时仓库构建并检查发行版, 不读写真实 dist 或上级发行脚本."""
        assignments = re.findall(
            r"(?m)^[A-Z][A-Z_]*=.*$", (ROOT / "config/versions.sh").read_text(),
        )
        with tempfile.TemporaryDirectory(prefix="blog-tool-versions-") as temp_dir:
            project = Path(temp_dir) / "blog-tool"
            project.mkdir()
            for filename in ("build.sh", "LICENSE"):
                shutil.copy2(ROOT / filename, project / filename)
            for directory in (
                "config", "options", "utils", "system", "docker", "db",
                "billing-center", "server", "client", "single", "python",
            ):
                shutil.copytree(
                    ROOT / directory, project / directory,
                    ignore=shutil.ignore_patterns("__pycache__", "*.bak"),
                )
            subprocess.run(
                ["bash", "build.sh"], cwd=project, check=True,
                capture_output=True, text=True,
                env={**os.environ, "OUTPUT_DIR": str(project / "out")},
            )
            for filename in (
                "blog-tool-dev.sh", "blog-tool.sh", "blog-tool-billing-center.sh",
            ):
                artifact = project / "out" / filename
                content = artifact.read_text()
                with self.subTest(filename=filename):
                    subprocess.run(["bash", "-n", str(artifact)], check=True)
                    for assignment in assignments:
                        self.assertEqual(content.splitlines().count(assignment), 1)
                    self.assertEqual(content.count('IMG_VERSION_REDIS="'), 1)
                    self.assertLess(
                        content.index('IMG_VERSION_PGSQL="'),
                        content.index('POSTGRES_DOCKER_NAME="'),
                    )
                    self.assertIn('IMG_VERSION_PGSQL_MAJOR="${IMG_VERSION_PGSQL%%.*}"', content)
                    self.assertIn('IMG_VERSION_KIBANA="$IMG_VERSION_ES"', content)
                    self.assertNotIn("install_ffmpeg()", content)
                    self.assertNotIn("DEP_VERSION_FFMPEG", content)
                    self.assertNotIn("FFMPEG_RELEASE_TAG", content)
                    self.assertNotIn("NODE_LIBSTDCXX_VERSION", content)
            dev_content = (project / "out/blog-tool-dev.sh").read_text()
            encoded = re.search(r"(?m)^SINGLE_DOCKER_BASE64='([^']+)'", dev_content)
            self.assertIsNotNone(encoded)
            with tarfile.open(fileobj=io.BytesIO(base64.b64decode(encoded[1])), mode="r:gz") as archive:
                for filename in ("Dockerfile", "env.Dockerfile"):
                    embedded = archive.extractfile(f"single/docker/{filename}").read()
                    self.assertEqual(embedded, (ROOT / "single/docker" / filename).read_bytes())


if __name__ == "__main__":
    unittest.main()