#!/bin/bash

# 从 GitHub Releases 下载对应平台的 re-sourcer 二进制文件

set -e

REPO="bwan3150/ReSourcer"
BIN_DIR="src-tauri/bin"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download"

echo "🔍 检测当前平台..."

# 创建 bin 目录
mkdir -p "${BIN_DIR}"

# 检测操作系统和架构
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
    Darwin*)
        # macOS
        echo "📥 下载 macOS (aarch64) 版本..."
        curl -L "${DOWNLOAD_URL}/re-sourcer-macos-aarch64" -o "${BIN_DIR}/re-sourcer-aarch64-apple-darwin"
        chmod +x "${BIN_DIR}/re-sourcer-aarch64-apple-darwin"
        echo "✅ macOS 二进制文件下载完成"
        ;;
    Linux*)
        # Linux
        echo "📥 下载 Linux (x86_64) 版本..."
        curl -L "${DOWNLOAD_URL}/re-sourcer-linux-x86_64" -o "${BIN_DIR}/re-sourcer-x86_64-unknown-linux-gnu"
        chmod +x "${BIN_DIR}/re-sourcer-x86_64-unknown-linux-gnu"
        echo "✅ Linux 二进制文件下载完成"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        # Windows
        echo "📥 下载 Windows (x86_64) 版本..."
        curl -L "${DOWNLOAD_URL}/re-sourcer-windows-x86_64.exe" -o "${BIN_DIR}/re-sourcer-x86_64-pc-windows-msvc.exe"
        echo "✅ Windows 二进制文件下载完成"
        ;;
    *)
        echo "❌ 不支持的操作系统: $OS"
        exit 1
        ;;
esac

echo ""
echo "已下载的文件："
ls -lh "${BIN_DIR}/"
