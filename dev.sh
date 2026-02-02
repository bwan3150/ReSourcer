#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 获取脚本所在目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/server"

update_dependencies() {
    print_status "Checking dependencies..."

    # 根据当前操作系统选择对应的 yt-dlp 二进制文件
    OS_TYPE=$(uname -s)
    case "$OS_TYPE" in
        Linux*)
            YTDLP_BIN="${SCRIPT_DIR}/bin/yt-dlp-linux"
            ;;
        Darwin*)
            YTDLP_BIN="${SCRIPT_DIR}/bin/yt-dlp-macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            YTDLP_BIN="${SCRIPT_DIR}/bin/yt-dlp-windows.exe"
            ;;
        *)
            print_error "Unsupported OS: $OS_TYPE"
            YTDLP_VERSION="unsupported OS"
            YTDLP_BIN=""
            ;;
    esac

    # 检查 yt-dlp 版本
    if [ -n "$YTDLP_BIN" ] && [ -f "$YTDLP_BIN" ]; then
        YTDLP_VERSION=$($YTDLP_BIN --version 2>/dev/null || echo "unknown")
        print_status "yt-dlp version: $YTDLP_VERSION (from $YTDLP_BIN)"
    else
        YTDLP_VERSION="not found"
        print_warning "yt-dlp binary not found at $YTDLP_BIN"
    fi

    # 获取当前时间戳
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 更新 config/dependencies.json
    cat > "${SERVER_DIR}/config/dependencies.json" << EOF
{
  "yt-dlp": {
    "version": "$YTDLP_VERSION",
    "last_checked": "$TIMESTAMP"
  }
}
EOF

    print_status "Dependencies config updated"
}

main() {
    print_status "Starting re-sourcer rebuild process..."

    print_status "Looking for and terminating existing re-sourcer processes..."
    if pkill -f re-sourcer; then
        print_status "Terminated existing processes"
        sleep 1
    else
        print_warning "No running re-sourcer processes found"
    fi

    # 更新依赖版本信息
    update_dependencies

    print_status "Building project (release mode)..."
    if cargo build --release --manifest-path "${SERVER_DIR}/Cargo.toml"; then
        print_status "Build successful"
    else
        print_error "Build failed"
        exit 1
    fi

    print_status "Launching re-sourcer..."
    if [ -f "${SERVER_DIR}/target/release/re-sourcer" ]; then
        "${SERVER_DIR}/target/release/re-sourcer"
    else
        print_error "Executable not found: ${SERVER_DIR}/target/release/re-sourcer"
        exit 1
    fi
}

main "$@"
