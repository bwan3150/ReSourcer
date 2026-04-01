#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/server"

main() {
    info "Starting re-sourcer development build..."

    # 终止已有进程
    if pkill -f re-sourcer 2>/dev/null; then
        info "Terminated existing processes"
        sleep 1
    else
        warn "No running re-sourcer processes found"
    fi

    # 编译
    info "Building project (release mode)..."
    cargo build --release --manifest-path "${SERVER_DIR}/Cargo.toml" \
        || error "Build failed"
    info "Build successful"

    # 启动
    echo ""
    info "Launching re-sourcer API server (port 1234)..."
    info "Frontend: cd web && python3 -m http.server 8080"
    echo ""

    # 开发模式：app_dir() 指向 server/，config/、tools/、sqlite/ 等都在这下面
    RESOURCER_DIR="${SERVER_DIR}" "${SERVER_DIR}/target/release/re-sourcer"
}

main "$@"
