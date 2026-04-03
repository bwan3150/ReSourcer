#!/bin/bash
set -e

# ReSourcer 后端一键部署脚本
# 用法: curl -sSL https://raw.githubusercontent.com/bwan3150/ReSourcer/main/deploy/setup.sh | sudo bash

GITHUB_REPO="bwan3150/ReSourcer"
INSTALL_DIR="/opt/re-sourcer"
SERVICE_NAME="re-sourcer"
S3_BASE="https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) error "Unsupported architecture: $arch" ;;
    esac
}

# 检测操作系统
detect_os() {
    local os=$(uname -s)
    case "$os" in
        Linux)  echo "linux" ;;
        Darwin) echo "macos" ;;
        *) error "Unsupported OS: $os" ;;
    esac
}

# 检查依赖
check_deps() {
    for cmd in curl; do
        command -v "$cmd" >/dev/null 2>&1 || error "$cmd is required"
    done
}

# 获取最新版本号
get_latest_version() {
    curl -sSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
        | grep '"tag_name"' | head -1 | cut -d'"' -f4
}

# 下载最新二进制
download_binary() {
    local os=$(detect_os)
    local arch=$(detect_arch)
    local asset_name="re-sourcer-${os}-${arch}"

    info "Platform: ${os} ${arch}"
    info "Fetching latest version..."

    local version=$(get_latest_version)
    if [ -z "$version" ]; then
        error "Cannot fetch latest version"
    fi
    info "Latest version: ${version}"

    local download_url="https://github.com/${GITHUB_REPO}/releases/latest/download/${asset_name}"

    info "Downloading ${asset_name}..."
    curl -sSL --fail -o "${INSTALL_DIR}/re-sourcer" "$download_url" \
        || error "Download failed: ${download_url}"

    chmod +x "${INSTALL_DIR}/re-sourcer"
    info "Binary installed: ${INSTALL_DIR}/re-sourcer"
}

# 下载 ffmpeg 和 ffprobe 到 tools/
download_tools() {
    local os=$(detect_os)
    local arch=$(detect_arch)

    # ffmpeg — URL 格式: ffmpeg-linux-x86_64 / ffmpeg-macos
    local ffmpeg_path="${INSTALL_DIR}/tools/ffmpeg"
    if [ -f "$ffmpeg_path" ]; then
        info "ffmpeg already exists, skipping"
    else
        local ffmpeg_suffix="${os}"
        [ "$os" = "linux" ] && ffmpeg_suffix="${os}-${arch}"
        local ffmpeg_url="${S3_BASE}/ffmpeg/ffmpeg-${ffmpeg_suffix}"
        info "Downloading ffmpeg..."
        curl -sSL --fail -o "$ffmpeg_path" "$ffmpeg_url" \
            || warn "ffmpeg download failed (will auto-download on first use)"
        [ -f "$ffmpeg_path" ] && chmod +x "$ffmpeg_path"
    fi

    # ffprobe
    local ffprobe_path="${INSTALL_DIR}/tools/ffprobe"
    if [ -f "$ffprobe_path" ]; then
        info "ffprobe already exists, skipping"
    else
        local ffprobe_suffix="${os}"
        [ "$os" = "linux" ] && ffprobe_suffix="${os}-${arch}"
        local ffprobe_url="${S3_BASE}/ffprobe/ffprobe-${ffprobe_suffix}"
        info "Downloading ffprobe..."
        curl -sSL --fail -o "$ffprobe_path" "$ffprobe_url" \
            || warn "ffprobe download failed (will auto-download on first use)"
        [ -f "$ffprobe_path" ] && chmod +x "$ffprobe_path"
    fi
}

# 创建目录结构
create_dirs() {
    info "Creating directory structure..."
    mkdir -p "${INSTALL_DIR}/config"
    mkdir -p "${INSTALL_DIR}/tools"
    mkdir -p "${INSTALL_DIR}/sqlite"

    info "  ${INSTALL_DIR}/"
    info "  ├── re-sourcer           # server binary"
    info "  ├── config/              # app.json, secret.json, tools.json"
    info "  ├── tools/               # ffmpeg, ffprobe, yt-dlp"
    info "  └── sqlite/              # data.db (auto-created)"
}

# 安装 systemd 服务
install_service() {
    if [ "$(detect_os)" = "macos" ]; then
        warn "macOS: no systemd, run manually: ${INSTALL_DIR}/re-sourcer"
        return
    fi

    info "Installing systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=ReSourcer API Server
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/re-sourcer
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl restart "${SERVICE_NAME}"

    info "Service started and enabled on boot"
}

# 显示 API Key
show_api_key() {
    local secret_file="${INSTALL_DIR}/config/secret.json"
    if [ -f "$secret_file" ]; then
        local key=$(grep -o '"apikey":"[^"]*"' "$secret_file" | cut -d'"' -f4)
        if [ -n "$key" ]; then
            info "API Key: ${key}"
        fi
    else
        info "API Key will be auto-generated on first start"
        info "Check: cat ${INSTALL_DIR}/config/secret.json"
    fi
}

# 主流程
main() {
    echo ""
    echo "  =============================="
    echo "   ReSourcer Setup"
    echo "  =============================="
    echo ""

    # 检查 root 权限 (Linux)
    if [ "$(detect_os)" = "linux" ] && [ "$(id -u)" -ne 0 ]; then
        error "Please run with sudo"
    fi

    check_deps

    # 如果已安装，提示更新
    if [ -f "${INSTALL_DIR}/re-sourcer" ]; then
        warn "Existing installation detected, updating..."
        if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
            info "Stopping service..."
            systemctl stop "${SERVICE_NAME}"
        fi
    fi

    create_dirs
    download_binary
    download_tools
    install_service

    echo ""
    info "=============================="
    info "Setup complete!"
    info "=============================="
    info ""
    local lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    info "API Server: http://${lan_ip}:1234"
    show_api_key
    info ""
    info "Commands:"
    info "  Status:  systemctl status ${SERVICE_NAME}"
    info "  Logs:    journalctl -u ${SERVICE_NAME} -f"
    info "  Update:  re-run this script"
    echo ""
}

main "$@"
