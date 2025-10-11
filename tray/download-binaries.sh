#!/bin/bash

# 从 GitHub Releases 下载最新的 re-sourcer 二进制文件
# 用于在构建 Tauri 应用前准备所需的二进制文件

set -e

REPO="bwan3150/ReSourcer"
BIN_DIR="src-tauri/bin"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download"

echo "🔍 正在准备下载最新的 re-sourcer 二进制文件..."

# 创建 bin 目录
mkdir -p "${BIN_DIR}"

# 下载 macOS arm64 版本
echo "📥 下载 macOS (aarch64) 版本..."
curl -L "${DOWNLOAD_URL}/re-sourcer-macos-aarch64" -o "${BIN_DIR}/re-sourcer-aarch64-apple-darwin"
chmod +x "${BIN_DIR}/re-sourcer-aarch64-apple-darwin"

# 下载 Linux x86_64 版本
echo "📥 下载 Linux (x86_64) 版本..."
curl -L "${DOWNLOAD_URL}/re-sourcer-linux-x86_64" -o "${BIN_DIR}/re-sourcer-x86_64-unknown-linux-gnu"
chmod +x "${BIN_DIR}/re-sourcer-x86_64-unknown-linux-gnu"

# 下载 Windows x86_64 版本
echo "📥 下载 Windows (x86_64) 版本..."
curl -L "${DOWNLOAD_URL}/re-sourcer-windows-x86_64.exe" -o "${BIN_DIR}/re-sourcer-x86_64-pc-windows-msvc.exe"

echo "✅ 所有二进制文件下载完成！"
echo ""
echo "已下载的文件："
ls -lh "${BIN_DIR}/"
