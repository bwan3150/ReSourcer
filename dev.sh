#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/server"
WEB_DIR="${SCRIPT_DIR}/web"

MODE="${1:-server}"  # server | web | release

# ── Prefixed output helper ────────────────────────────────────
prefix_output() {
    local tag="$1" color="$2"
    while IFS= read -r line; do
        echo -e "${color}[${tag}]${NC} ${line}"
    done
}

# ── Kill all managed processes ────────────────────────────────
kill_all() {
    # Kill cargo and re-sourcer processes
    pkill -f "cargo run.*re-sourcer" 2>/dev/null
    pkill -f "target/(debug|release)/re-sourcer" 2>/dev/null
    # Kill vite processes from our web dir
    pkill -f "node.*vite" 2>/dev/null
    sleep 0.5
    # Force kill if still around
    pkill -9 -f "target/(debug|release)/re-sourcer" 2>/dev/null
    pkill -9 -f "node.*vite" 2>/dev/null
}

cleanup() {
    echo ""
    info "Shutting down..."
    kill_all
    info "All processes stopped."
    exit 0
}
trap cleanup INT TERM

# ── Start backend ─────────────────────────────────────────────
start_server() {
    if [[ "$MODE" == "release" ]]; then
        info "Building server (release mode)..."
        cargo build --release --manifest-path "${SERVER_DIR}/Cargo.toml" \
            || error "Release build failed"
        info "Starting release binary..."
        RESOURCER_DIR="${SERVER_DIR}" "${SERVER_DIR}/target/release/re-sourcer" 2>&1 \
            | prefix_output "SERVER" "$CYAN" &
    else
        info "Starting server (cargo run)..."
        RESOURCER_DIR="${SERVER_DIR}" cargo run --manifest-path "${SERVER_DIR}/Cargo.toml" 2>&1 \
            | prefix_output "SERVER" "$CYAN" &
    fi
}

# ── Start frontend ────────────────────────────────────────────
start_web() {
    if [[ "$MODE" == "release" ]]; then
        info "Building frontend (production)..."
        (cd "$WEB_DIR" && npm install --silent && npm run build) 2>&1 \
            | prefix_output "WEB" "$MAGENTA"
        info "Serving production build (npm run preview)..."
        (cd "$WEB_DIR" && npm run preview) 2>&1 \
            | prefix_output "WEB" "$MAGENTA" &
        sleep 2
        open_browser "http://localhost:4173/"
    else
        info "Installing web dependencies & starting dev server..."
        (cd "$WEB_DIR" && npm install --silent && npm run dev) 2>&1 \
            | prefix_output "WEB" "$MAGENTA" &
        sleep 2
        open_browser "http://localhost:5173/"
    fi
}

open_browser() {
    local url="$1"
    info "Opening ${url} in browser..."
    if command -v open &>/dev/null; then
        open "$url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$url"
    fi
}

# ── Reload (kill + restart) ──────────────────────────────────
reload() {
    warn "Reloading..."
    kill_all
    sleep 0.3
    start_server
    if [[ "$MODE" == "web" || "$MODE" == "release" ]]; then
        start_web
    fi
    info "Reload complete. Press ${YELLOW}r${NC} to reload, ${YELLOW}Ctrl+C${NC} to quit."
}

# ── Main ──────────────────────────────────────────────────────
main() {
    case "$MODE" in
        server)
            info "Mode: ${YELLOW}server-only${NC} (cargo run)"
            ;;
        web)
            info "Mode: ${YELLOW}full-stack dev${NC} (cargo run + vite dev)"
            ;;
        release)
            info "Mode: ${YELLOW}release test${NC} (release build + production frontend)"
            ;;
        *)
            echo "Usage: $0 [web|release]"
            echo "  (no arg)  — cargo run server only"
            echo "  web       — server + vite dev, open browser"
            echo "  release   — release build + production frontend"
            exit 1
            ;;
    esac

    # Kill existing re-sourcer processes
    if pkill -f re-sourcer 2>/dev/null; then
        info "Terminated existing re-sourcer processes"
        sleep 1
    fi

    start_server
    if [[ "$MODE" == "web" || "$MODE" == "release" ]]; then
        start_web
    fi

    info "Press ${YELLOW}r${NC} to reload, ${YELLOW}Ctrl+C${NC} to quit."

    while true; do
        read -rsn1 key
        if [[ "$key" == "r" || "$key" == "R" ]]; then
            reload
        fi
    done
}

main
