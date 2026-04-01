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
        *) error "不支持的架构: $arch" ;;
    esac
}

# 检测操作系统
detect_os() {
    local os=$(uname -s)
    case "$os" in
        Linux)  echo "linux" ;;
        Darwin) echo "macos" ;;
        *) error "不支持的操作系统: $os" ;;
    esac
}

# 检查依赖
check_deps() {
    for cmd in curl; do
        command -v "$cmd" >/dev/null 2>&1 || error "需要 $cmd，请先安装"
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

    info "检测到系统: ${os} ${arch}"
    info "正在获取最新版本..."

    local version=$(get_latest_version)
    if [ -z "$version" ]; then
        error "无法获取最新版本信息，请检查网络连接"
    fi
    info "最新版本: ${version}"

    local download_url="https://github.com/${GITHUB_REPO}/releases/latest/download/${asset_name}"

    info "正在下载 ${asset_name}..."
    curl -sSL -o "${INSTALL_DIR}/re-sourcer" "$download_url" \
        || error "下载失败，请检查 ${download_url} 是否存在"

    chmod +x "${INSTALL_DIR}/re-sourcer"
    info "二进制文件已下载到 ${INSTALL_DIR}/re-sourcer"
}

# 下载 ffmpeg 和 ffprobe 到 tools/
download_tools() {
    local os=$(detect_os)

    # ffmpeg
    local ffmpeg_path="${INSTALL_DIR}/tools/ffmpeg"
    if [ -f "$ffmpeg_path" ]; then
        info "ffmpeg 已存在，跳过下载"
    else
        local ffmpeg_url="${S3_BASE}/ffmpeg/ffmpeg-${os}"
        info "正在下载 ffmpeg..."
        curl -sSL -o "$ffmpeg_path" "$ffmpeg_url" \
            || error "下载 ffmpeg 失败"
        chmod +x "$ffmpeg_path"
        info "ffmpeg 已下载"
    fi

    # ffprobe
    local ffprobe_path="${INSTALL_DIR}/tools/ffprobe"
    if [ -f "$ffprobe_path" ]; then
        info "ffprobe 已存在，跳过下载"
    else
        local ffprobe_url="${S3_BASE}/ffprobe/ffprobe-${os}"
        info "正在下载 ffprobe..."
        curl -sSL -o "$ffprobe_path" "$ffprobe_url" \
            || error "下载 ffprobe 失败"
        chmod +x "$ffprobe_path"
        info "ffprobe 已下载"
    fi
}

# 创建目录结构
create_dirs() {
    info "创建目录结构..."
    mkdir -p "${INSTALL_DIR}/config"
    mkdir -p "${INSTALL_DIR}/tools"
    mkdir -p "${INSTALL_DIR}/credentials"
    mkdir -p "${INSTALL_DIR}/sqlite"

    info "目录结构:"
    info "  ${INSTALL_DIR}/"
    info "  ├── re-sourcer           # 后端二进制"
    info "  ├── config/              # 配置文件 (app.json, secret.json 等)"
    info "  ├── tools/               # yt-dlp, ffmpeg, ffprobe"
    info "  ├── credentials/         # 下载凭证 (x, pixiv 等)"
    info "  └── sqlite/              # SQLite 数据库 (data.db, 自动创建)"
}

# 安装 systemd 服务
install_service() {
    # macOS 不使用 systemd
    if [ "$(detect_os)" = "macos" ]; then
        warn "macOS 不支持 systemd，请手动运行: ${INSTALL_DIR}/re-sourcer"
        return
    fi

    info "安装 systemd 服务..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=ReSourcer API Server
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/re-sourcer
WorkingDirectory=${INSTALL_DIR}
Environment=HOME=${INSTALL_DIR}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"

    info "服务已启动并设为开机自启"
}

# 主流程
main() {
    echo ""
    echo "  =============================="
    echo "   ReSourcer 后端部署脚本"
    echo "  =============================="
    echo ""

    # 检查 root 权限 (Linux)
    if [ "$(detect_os)" = "linux" ] && [ "$(id -u)" -ne 0 ]; then
        error "请使用 sudo 运行此脚本"
    fi

    check_deps

    # 如果已安装，提示更新
    if [ -f "${INSTALL_DIR}/re-sourcer" ]; then
        warn "检测到已有安装，将更新二进制文件"
        if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
            info "停止现有服务..."
            systemctl stop "${SERVICE_NAME}"
        fi
    fi

    create_dirs
    download_binary
    download_tools
    install_service

    echo ""
    info "=============================="
    info "部署完成！"
    info "=============================="
    info ""
    info "后端 API: http://localhost:1234"
    info "查看状态: systemctl status ${SERVICE_NAME}"
    info "查看日志: journalctl -u ${SERVICE_NAME} -f"
    info "重新部署: 再次运行此脚本即可更新"
    info ""
    info "下一步: 部署前端 Docker (可选)"
    info "  cd docker && docker compose up -d"
    echo ""
}

main "$@"
