#!/bin/bash
# FilePath    : blog-tool/client/_.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 统一导出

# shellcheck disable=SC1091
CLIENT_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$CLIENT_SCRIPT_DIR/compose.sh"
source "$CLIENT_SCRIPT_DIR/config.sh"
source "$CLIENT_SCRIPT_DIR/deploy.sh"
