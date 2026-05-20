#!/bin/bash
# FilePath    : blog-tool/single/_.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : single 模块统一导出.

# shellcheck disable=SC1091
SINGLE_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SINGLE_SCRIPT_DIR/build.sh"