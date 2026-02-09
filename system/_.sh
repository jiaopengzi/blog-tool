#!/bin/bash
# FilePath    : blog-tool/system/_.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : 统一导出

# shellcheck disable=SC1091
SYSTEM_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SYSTEM_SCRIPT_DIR/apt.sh"
source "$SYSTEM_SCRIPT_DIR/software.sh"
source "$SYSTEM_SCRIPT_DIR/ssh.sh"
source "$SYSTEM_SCRIPT_DIR/sys.sh"
source "$SYSTEM_SCRIPT_DIR/upgrade.sh"
source "$SYSTEM_SCRIPT_DIR/user.sh"
