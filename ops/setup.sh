#!/bin/bash
set -e

# ReSourcer 后端一键部署脚本
# 用法: curl -sSL https://raw.githubusercontent.com/bwan3150/ReSourcer/main/ops/setup.sh | sudo bash

GITHUB_REPO="bwan3150/ReSourcer"
INSTALL_DIR="/opt/re-sourcer"
SERVICE_NAME="re-sourcer"
S3_BASE="https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries"

# 持久化数据目录（sqlite/config/backups），由 resolve_data_dir() 在 main() 里填充。
# 必须与 INSTALL_DIR 分开：INSTALL_DIR 是程序目录，NAS 系统更新可能整体清空重装；
# DATA_DIR 必须指向一个不会被这种更新清空的位置（比如群晖/QNAP 的持久化卷）。
DATA_DIR=""

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

# 解析持久化数据目录：
#   1. 环境变量 RESOURCER_DATA_DIR（非交互场景，例如脚本化部署）
#   2. 交互式询问（脚本可能是 curl | sudo bash 起的，标准输入被脚本占用，得从 /dev/tty 读），
#      必须显式输入一个 INSTALL_DIR 之外的路径，不提供安全的“默认值”
#   3. 都拿不到，或拿到的路径仍在 INSTALL_DIR 内 → 直接装不上（exit 1），
#      宁可装不上，也不要静默装成一个会被 NAS 系统更新清空的配置
# 找出上一次装的时候用的是哪个数据目录（重装 / 升级时沿用，不再重复问）
#   1. INSTALL_DIR/data.json
#   2. systemd unit 里的 Environment=RESOURCER_DATA_DIR=
detect_existing_data_dir() {
    local found=""
    if [ -f "${INSTALL_DIR}/data.json" ]; then
        found=$(sed -n 's/.*"data_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "${INSTALL_DIR}/data.json" | head -1)
    fi
    if [ -z "$found" ] && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        found=$(sed -n 's/^Environment=RESOURCER_DATA_DIR=\(.*\)$/\1/p' \
            "/etc/systemd/system/${SERVICE_NAME}.service" | head -1)
    fi
    echo "$found"
}

resolve_data_dir() {
    if [ -n "${RESOURCER_DATA_DIR:-}" ]; then
        DATA_DIR="$RESOURCER_DATA_DIR"
        if [ "$DATA_DIR" = "$INSTALL_DIR" ] || [[ "$DATA_DIR" == "$INSTALL_DIR"/* ]]; then
            warn "RESOURCER_DATA_DIR (${DATA_DIR}) is inside ${INSTALL_DIR} — a NAS OS update can still wipe your data."
        fi
        info "Persistent data dir (from env): ${DATA_DIR}"
        return
    fi

    # 已经装过就直接沿用，升级时不该再追问一遍（答错会把老数据孤立掉）
    local existing
    existing=$(detect_existing_data_dir)
    if [ -n "$existing" ] && [ "$existing" != "$INSTALL_DIR" ] && [[ "$existing" != "$INSTALL_DIR"/* ]]; then
        DATA_DIR="$existing"
        info "Persistent data dir (existing install): ${DATA_DIR}"
        return
    fi

    if [ -r /dev/tty ]; then
        local input=""
        echo ""
        info "Where should ReSourcer keep its persistent data (database, config, backups)?"
        info "This must be OUTSIDE ${INSTALL_DIR} — NAS system updates can wipe that directory."
        info "Example (Synology): /volume1/docker/re-sourcer   Example (QNAP): /share/re-sourcer-data"
        read -r -p "Data directory (required): " input < /dev/tty || true
        if [ -n "$input" ] && [ "$input" != "$INSTALL_DIR" ] && [[ "$input" != "$INSTALL_DIR"/* ]]; then
            DATA_DIR="$input"
            return
        fi
        error "A persistent data directory outside ${INSTALL_DIR} is required. Re-run and provide one (e.g. /volume1/docker/re-sourcer)."
    fi

    error "Non-interactive install and RESOURCER_DATA_DIR is not set. Re-run with RESOURCER_DATA_DIR=/your/persistent/path (e.g. /volume1/docker/re-sourcer on Synology, /share/re-sourcer-data on QNAP)."
}

# 获取最新版本号
#
# 不能用 /releases/latest：这个仓库里服务端（server-v*）和网页端（web-v*）
# 各自发版，latest 只给全仓库最新的那条。取到网页端的 tag 会导致下面
# 找不到 re-sourcer-linux-* 产物而装不上。
get_latest_version() {
    curl -sSL "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=30" \
        | grep '"tag_name"' | cut -d'"' -f4 | grep '^server-v' | head -1
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
    local ffmpeg_path="${DATA_DIR}/tools/ffmpeg"
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
    local ffprobe_path="${DATA_DIR}/tools/ffprobe"
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
    mkdir -p "${DATA_DIR}/tools"
    mkdir -p "${INSTALL_DIR}/tmp"
    # config/、sqlite/、backups/ 由程序自己在 DATA_DIR 下创建（含迁移逻辑），这里只是先建好挂载点
    mkdir -p "${DATA_DIR}"

    info "  ${INSTALL_DIR}/           # program (safe to wipe/reinstall)"
    info "  ├── re-sourcer           # server binary"
    info "  └── data.json            # points at the data dir below"
    info "  ${DATA_DIR}/              # persistent data"
    info "  ├── config/              # app.json, secret.json, tools.json (auto-created)"
    info "  ├── sqlite/              # data.db (auto-created)"
    info "  ├── tools/               # ffmpeg, ffprobe, yt-dlp"
    info "  └── backups/             # periodic data.db snapshots (auto-created)"
}

# 在程序目录写一份 data.json
#
# systemd unit 里的 Environment 只在以服务方式启动时生效；手动运行二进制、
# macOS、或容器里跑的时候读的就是这个文件。两边写同一个值，谁先生效都一样。
write_data_pointer() {
    cat > "${INSTALL_DIR}/data.json" << EOF
{
  "data_dir": "${DATA_DIR}"
}
EOF
    info "Wrote ${INSTALL_DIR}/data.json -> ${DATA_DIR}"
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
# TMPDIR: PyInstaller (yt-dlp) extracts .so files to TMPDIR at runtime.
# Many NAS systems mount /tmp with noexec, which blocks .so loading.
# Point TMPDIR to a writable+exec directory instead.
Environment=TMPDIR=${INSTALL_DIR}/tmp
# RESOURCER_DATA_DIR: sqlite/config/backups live here, kept outside INSTALL_DIR
# so a NAS OS update (which can wipe INSTALL_DIR) never touches your data.
Environment=RESOURCER_DATA_DIR=${DATA_DIR}
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
    local secret_file="${DATA_DIR}/config/secret.json"
    if [ -f "$secret_file" ]; then
        local key=$(grep -o '"apikey":"[^"]*"' "$secret_file" | cut -d'"' -f4)
        if [ -n "$key" ]; then
            info "API Key: ${key}"
        fi
    else
        info "API Key will be auto-generated on first start"
        info "Check: cat ${secret_file}"
    fi
}

# 主流程
main() {
    echo ""
    echo '╔══════════════════════════════════════════════════════════════════════════════╗'
    echo '║                                                                              ║'
    echo '║  ██████╗ ███████╗███████╗ ██████╗ ██╗   ██╗██████╗  ██████╗███████╗██████╗   ║'
    echo '║  ██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔════╝██╔══██╗  ║'
    echo '║  ██████╔╝█████╗  ███████╗██║   ██║██║   ██║██████╔╝██║     █████╗  ██████╔╝  ║'
    echo '║  ██╔══██╗██╔══╝  ╚════██║██║   ██║██║   ██║██╔══██╗██║     ██╔══╝  ██╔══██╗  ║'
    echo '║  ██║  ██║███████╗███████║╚██████╔╝╚██████╔╝██║  ██║╚██████╗███████╗██║  ██║  ║'
    echo '║  ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝  ╚═╝  ║'
    echo '║                                                                              ║'
    echo '║                                  S E T U P                                   ║'
    echo '╚══════════════════════════════════════════════════════════════════════════════╝'
    echo ""

    # 检查 root 权限 (Linux)
    if [ "$(detect_os)" = "linux" ] && [ "$(id -u)" -ne 0 ]; then
        error "Please run with sudo"
    fi

    check_deps
    resolve_data_dir

    # 如果已安装，提示更新
    if [ -f "${INSTALL_DIR}/re-sourcer" ]; then
        warn "Existing installation detected, updating..."
        if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
            info "Stopping service..."
            systemctl stop "${SERVICE_NAME}"
        fi
    fi

    create_dirs
    write_data_pointer
    download_binary
    download_tools
    install_service

    echo ""
    info "=============================="
    info "Setup complete!"
    info "=============================="
    info ""
    # hostname -I 在部分 NAS 上会成功返回空串（不是报错），所以 || 接不住，
    # 得单独判空；再退一步用 ip route 取出站网卡的地址
    local lan_ip
    lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$lan_ip" ] && lan_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
    [ -z "$lan_ip" ] && lan_ip="localhost"
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
