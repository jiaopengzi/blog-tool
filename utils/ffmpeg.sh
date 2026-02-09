#!/bin/bash
# FilePath    : blog-tool/utils/ffmpeg.sh
# Author      : jiaopengzi
# Blog        : https://jiaopengzi.com
# Copyright   : Copyright (c) 2025 by jiaopengzi, All Rights Reserved.
# Description : ffmpeg 工具 安装预编译版 FFmpeg(来自 BtbN/FFmpeg-Builds); 安装到：/usr/local/bin

# 定义变量
DOWNLOAD_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.0-latest-linux64-gpl-8.0.tar.xz" # BtbN 官方最新预编译版下载地址
TEMP_DIR="/tmp/ffmpeg_install"                                                                                          # 临时下载和解压目录
INSTALL_DIR="/usr/local/bin"                                                                                            # 安装目录

# 安装 ffmpeg
install_ffmpeg() {
    log_debug "run install_ffmpeg"
    log_info "开始安装预编译版 FFmpeg(来自 BtbN 官方构建)"
    log_info "下载地址: $DOWNLOAD_URL"
    log_info "安装目录: $INSTALL_DIR"

    # 创建临时目录
    sudo mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    # 下载 FFmpeg 预编译包
    echo "[1/6] 正在下载 FFmpeg 预编译二进制包..."
    sudo wget -O ffmpeg.tar.xz "$DOWNLOAD_URL"

    if [ ! -f "ffmpeg.tar.xz" ]; then
        log_error "下载失败, 请检查网络连接或下载地址是否有效"
        exit 1
    fi

    # 解压
    echo "[2/6] 正在解压 ffmpeg.tar.xz..."
    sudo tar -xvf ffmpeg.tar.xz

    # 通常解压后得到一个文件夹, 如：ffmpeg-n8.0-linux64-gpl
    # 我们查找解压出来的目录(一般包含 ffmpeg 可执行文件)
    FFMPEG_EXTRACTED_DIR=$(sudo find . -type d -name "*linux64-gpl*" | sudo head -n 1)

    if [ -z "$FFMPEG_EXTRACTED_DIR" ]; then
        log_error "未找到解压后的 FFmpeg 目录"
        ls -l
        exit 1
    fi

    echo "[3/6] 解压到的目录: $FFMPEG_EXTRACTED_DIR"

    # 如果目录不存在则创建
    if [ ! -d "$INSTALL_DIR" ]; then
        log_info "创建安装目录: $INSTALL_DIR"
        sudo mkdir -p "$INSTALL_DIR"
    fi

    # 复制 ffmpeg 可执行文件到安装目录
    echo "[4/6] 正在复制 FFmpeg 可执行文件到 $INSTALL_DIR ..."
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffmpeg" "$INSTALL_DIR/"
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffprobe" "$INSTALL_DIR/"
    sudo cp "$FFMPEG_EXTRACTED_DIR/bin/ffplay" "$INSTALL_DIR/"

    echo "[5/6] 赋权并完成安装..."
    # 设置可执行权限(通常已设置, 但再确保一次)
    sudo chmod +x "$INSTALL_DIR/ffmpeg"
    sudo chmod +x "$INSTALL_DIR/ffprobe"
    sudo chmod +x "$INSTALL_DIR/ffplay"

    # 清理临时文件
    echo "[6/6] 清理临时文件..."
    cd /tmp || exit 1
    sudo rm -rf "$TEMP_DIR"

    log_info "FFmpeg 预编译版 安装完成！"
    log_info "📍 FFmpeg 安装位置: $INSTALL_DIR"
    log_info "🔗 全局命令: ffmpeg, ffprobe, ffplay; 可通过以下命令验证：ffmpeg -version | which ffmpeg"
}

# 卸载 ffmpeg
uninstall_ffmpeg() {
    log_debug "run uninstall_ffmpeg"
    log_info "开始卸载 FFmpeg 预编译版..."

    # 删除 ffmpeg 可执行文件
    sudo rm -f "$INSTALL_DIR/ffmpeg"
    sudo rm -f "$INSTALL_DIR/ffprobe"
    sudo rm -f "$INSTALL_DIR/ffplay"

    log_info "FFmpeg 预编译版 已卸载！"
}
