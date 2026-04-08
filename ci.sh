#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Arrow-key menu selector ──────────────────────────────────
# Usage: menu_select result_var "prompt" "option1" "option2" ...
# Returns selected index (0-based) in the named variable
menu_select() {
    local _var_name=$1
    local prompt="$2"
    shift 2
    local options=("$@")
    local count=${#options[@]}
    local selected=0

    # Hide cursor
    tput civis 2>/dev/null

    echo -e "$prompt"
    echo ""

    # Draw initial menu
    for i in "${!options[@]}"; do
        if [[ $i -eq $selected ]]; then
            echo -e "  ${GREEN}▸ ${options[$i]}${NC}"
        else
            echo -e "    ${DIM}${options[$i]}${NC}"
        fi
    done

    while true; do
        # Read a keypress
        IFS= read -rsn1 key
        # If escape sequence, read the rest
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 rest
            key+="$rest"
        fi

        case "$key" in
            $'\x1b[A' | $'\x1b[D')  # Up / Left
                ((selected = (selected - 1 + count) % count))
                ;;
            $'\x1b[B' | $'\x1b[C')  # Down / Right
                ((selected = (selected + 1) % count))
                ;;
            '')  # Enter
                break
                ;;
            *)
                continue
                ;;
        esac

        # Redraw: move cursor up $count lines and overwrite
        tput cuu "$count" 2>/dev/null
        for i in "${!options[@]}"; do
            tput el 2>/dev/null  # clear line
            if [[ $i -eq $selected ]]; then
                echo -e "  ${GREEN}▸ ${options[$i]}${NC}"
            else
                echo -e "    ${DIM}${options[$i]}${NC}"
            fi
        done
    done

    # Show cursor
    tput cnorm 2>/dev/null
    eval "$_var_name=\$selected"
}

# ── Yes/No selector ──────────────────────────────────────────
# Usage: confirm_select result_var "prompt"
# Sets result_var to "y" or "n"
confirm_select() {
    local _var_name=$1
    local prompt="$2"
    local sel=0  # 0=Yes, 1=No

    tput civis 2>/dev/null
    echo -e "$prompt"
    echo ""

    # Draw
    local opts=("Yes" "No")
    for i in 0 1; do
        if [[ $i -eq $sel ]]; then
            echo -e "  ${GREEN}▸ ${opts[$i]}${NC}"
        else
            echo -e "    ${DIM}${opts[$i]}${NC}"
        fi
    done

    while true; do
        IFS= read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 rest
            key+="$rest"
        fi

        case "$key" in
            $'\x1b[A' | $'\x1b[B' | $'\x1b[C' | $'\x1b[D')
                sel=$(( 1 - sel ))
                ;;
            '')
                break
                ;;
            *) continue ;;
        esac

        tput cuu 2 2>/dev/null
        for i in 0 1; do
            tput el 2>/dev/null
            if [[ $i -eq $sel ]]; then
                echo -e "  ${GREEN}▸ ${opts[$i]}${NC}"
            else
                echo -e "    ${DIM}${opts[$i]}${NC}"
            fi
        done
    done

    tput cnorm 2>/dev/null
    [[ $sel -eq 0 ]] && eval "$_var_name=y" || eval "$_var_name=n"
}

# ── Auto-bump: increment last numeric segment ────────────────
# e.g. "0.3.11-beta" → "0.3.12-beta",  "1.2.3" → "1.2.4"
bump_version() {
    local ver="$1"
    # Split into numeric prefix and optional suffix (e.g. "-beta")
    local base suffix
    if [[ "$ver" =~ ^([0-9.]+)(-.+)$ ]]; then
        base="${BASH_REMATCH[1]}"
        suffix="${BASH_REMATCH[2]}"
    else
        base="$ver"
        suffix=""
    fi
    # Increment last number
    local last="${base##*.}"
    local prefix="${base%.*}"
    local new_last=$((last + 1))
    echo "${prefix}.${new_last}${suffix}"
}

# ── Ensure cursor is restored on exit ────────────────────────
trap 'tput cnorm 2>/dev/null' EXIT

# ── Read versions ─────────────────────────────────────────────
SERVER_VER=$(grep -m1 '^version' "$SCRIPT_DIR/server/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')
WEB_VER=$(grep '"version"' "$SCRIPT_DIR/web/package.json" | head -1 | sed 's/.*: "\(.*\)".*/\1/')
IOS_VER=$(grep -m1 'MARKETING_VERSION' "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

echo ""
echo -e "${CYAN}╔══════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}      ${BOLD}ReSourcer CI${NC}            ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════╝${NC}"
echo ""
echo -e "  Server  ${DIM}v${SERVER_VER}${NC}"
echo -e "  Web     ${DIM}v${WEB_VER}${NC}"
echo -e "  iOS     ${DIM}v${IOS_VER}${NC}"
echo ""

# ── Choose release target ─────────────────────────────────────
choice=0
menu_select choice \
    "${YELLOW}Select release target:${NC}" \
    "Server     → GitHub Release" \
    "Web        → Docker Image" \
    "iOS        → Pgyer" \
    "All        → All of the above"

BUMP_SERVER=false
BUMP_WEB=false
BUMP_IOS=false
NEW_SERVER_VER=""
NEW_WEB_VER=""
NEW_IOS_VER=""

case "$choice" in
    0) BUMP_SERVER=true ;;
    1) BUMP_WEB=true ;;
    2) BUMP_IOS=true ;;
    3) BUMP_SERVER=true; BUMP_WEB=true; BUMP_IOS=true ;;
esac

echo ""

# ── Collect version numbers ──────────────────────────────────
if [ "$BUMP_SERVER" = true ]; then
    DEFAULT_SERVER_VER=$(bump_version "$SERVER_VER")
    echo -ne "${YELLOW}New server version ${DIM}(current: ${SERVER_VER}, enter=${DEFAULT_SERVER_VER})${NC}${YELLOW}:${NC} "
    read -e -r NEW_SERVER_VER
    [ -z "$NEW_SERVER_VER" ] && NEW_SERVER_VER="$DEFAULT_SERVER_VER"
    echo -e "  → ${GREEN}${NEW_SERVER_VER}${NC}"
    SERVER_TAG="server-v${NEW_SERVER_VER}"
    if git tag -l | grep -q "^${SERVER_TAG}$"; then
        retag=""
        confirm_select retag "${YELLOW}Tag ${SERVER_TAG} already exists. Re-tag and rebuild?${NC}"
        if [ "$retag" = "y" ]; then
            git tag -d "$SERVER_TAG" 2>/dev/null
            git push origin --delete "$SERVER_TAG" 2>/dev/null
            echo -e "${GREEN}Old tag deleted${NC}"
        else
            exit 0
        fi
    fi
fi

if [ "$BUMP_WEB" = true ]; then
    echo ""
    DEFAULT_WEB_VER=$(bump_version "$WEB_VER")
    echo -ne "${YELLOW}New web version ${DIM}(current: ${WEB_VER}, enter=${DEFAULT_WEB_VER})${NC}${YELLOW}:${NC} "
    read -e -r NEW_WEB_VER
    [ -z "$NEW_WEB_VER" ] && NEW_WEB_VER="$DEFAULT_WEB_VER"
    echo -e "  → ${GREEN}${NEW_WEB_VER}${NC}"
    WEB_TAG="web-v${NEW_WEB_VER}"
    if git tag -l | grep -q "^${WEB_TAG}$"; then
        retag=""
        confirm_select retag "${YELLOW}Tag ${WEB_TAG} already exists. Re-tag and rebuild?${NC}"
        if [ "$retag" = "y" ]; then
            git tag -d "$WEB_TAG" 2>/dev/null
            git push origin --delete "$WEB_TAG" 2>/dev/null
            echo -e "${GREEN}Old tag deleted${NC}"
        else
            exit 0
        fi
    fi
fi

if [ "$BUMP_IOS" = true ]; then
    echo ""
    DEFAULT_IOS_VER=$(bump_version "$IOS_VER")
    echo -ne "${YELLOW}New iOS version ${DIM}(current: ${IOS_VER}, enter=${DEFAULT_IOS_VER})${NC}${YELLOW}:${NC} "
    read -e -r NEW_IOS_VER
    [ -z "$NEW_IOS_VER" ] && NEW_IOS_VER="$DEFAULT_IOS_VER"
    echo -e "  → ${GREEN}${NEW_IOS_VER}${NC}"
    IOS_TAG="ios-v${NEW_IOS_VER}"
    if git tag -l | grep -q "^${IOS_TAG}$"; then
        retag=""
        confirm_select retag "${YELLOW}Tag ${IOS_TAG} already exists. Re-tag and rebuild?${NC}"
        if [ "$retag" = "y" ]; then
            git tag -d "$IOS_TAG" 2>/dev/null
            git push origin --delete "$IOS_TAG" 2>/dev/null
            echo -e "${GREEN}Old tag deleted${NC}"
        else
            exit 0
        fi
    fi
fi

# ── Confirm plan ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}         ${BOLD}Plan${NC}                 ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════╝${NC}"
[ -n "$NEW_SERVER_VER" ] && echo -e "  Server  ${SERVER_VER} → ${GREEN}${NEW_SERVER_VER}${NC}  (tag: ${SERVER_TAG})"
[ -n "$NEW_WEB_VER" ] && echo -e "  Web     ${WEB_VER} → ${GREEN}${NEW_WEB_VER}${NC}  (tag: ${WEB_TAG})"
[ -n "$NEW_IOS_VER" ] && echo -e "  iOS     ${IOS_VER} → ${GREEN}${NEW_IOS_VER}${NC}  (tag: ${IOS_TAG})"
echo ""

confirm=""
confirm_select confirm "${YELLOW}Proceed?${NC}"
if [ "$confirm" != "y" ]; then
    echo -e "${RED}Cancelled${NC}"
    exit 0
fi

# ── Include unstaged changes ──────────────────────────────────
if ! git diff --quiet; then
    echo ""
    add_all=""
    confirm_select add_all "${YELLOW}Include other unstaged changes?${NC}"
    [ "$add_all" = "y" ] && git add -A && git commit -m "chore: pending changes" && git push
fi

# === Web release ===
if [ -n "$NEW_WEB_VER" ]; then
    echo ""
    echo -e "${GREEN}=== Web v${NEW_WEB_VER} ===${NC}"

    if [ "$NEW_WEB_VER" != "$WEB_VER" ]; then
        sed -i '' "s/\"version\": \"${WEB_VER}\"/\"version\": \"${NEW_WEB_VER}\"/" "$SCRIPT_DIR/web/package.json"
        git add "$SCRIPT_DIR/web/package.json"
        git commit -m "release: web v${NEW_WEB_VER}"
        git push || { echo -e "${RED}Push failed${NC}"; exit 1; }
    fi

    git tag "$WEB_TAG"
    git push origin "$WEB_TAG" || { echo -e "${RED}Web tag push failed${NC}"; exit 1; }
    echo -e "${GREEN}Tag ${WEB_TAG} pushed → CI: Docker image ghcr.io${NC}"
fi

# === iOS release ===
if [ -n "$NEW_IOS_VER" ]; then
    echo ""
    echo -e "${GREEN}=== iOS v${NEW_IOS_VER} ===${NC}"

    if [ "$NEW_IOS_VER" != "$IOS_VER" ]; then
        sed -i '' "s/MARKETING_VERSION = ${IOS_VER};/MARKETING_VERSION = ${NEW_IOS_VER};/g" "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"
        git add "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"
        git commit -m "release: iOS v${NEW_IOS_VER}"
        git push || { echo -e "${RED}Push failed${NC}"; exit 1; }
    fi

    git tag "$IOS_TAG"
    git push origin "$IOS_TAG" || { echo -e "${RED}iOS tag push failed${NC}"; exit 1; }
    echo -e "${GREEN}Tag ${IOS_TAG} pushed → CI: iOS build + Pgyer${NC}"
fi

# === Server release ===
if [ -n "$NEW_SERVER_VER" ]; then
    echo ""
    echo -e "${GREEN}=== Server v${NEW_SERVER_VER} ===${NC}"

    if [ "$NEW_SERVER_VER" != "$SERVER_VER" ]; then
        sed -i '' "s/^version = \"${SERVER_VER}\"/version = \"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/Cargo.toml"
        sed -i '' "s/\"version\":\"${SERVER_VER}\"/\"version\":\"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/config/app.json"
        git add "$SCRIPT_DIR/server/Cargo.toml" "$SCRIPT_DIR/server/Cargo.lock" "$SCRIPT_DIR/server/config/app.json"
        git commit -m "release: server v${NEW_SERVER_VER}"
        git push || { echo -e "${RED}Push failed${NC}"; exit 1; }
    fi

    git tag "$SERVER_TAG"
    git push origin "$SERVER_TAG" || { echo -e "${RED}Server tag push failed${NC}"; exit 1; }
    echo -e "${GREEN}Tag ${SERVER_TAG} pushed → CI: server build + GitHub Release${NC}"
fi

echo ""
echo -e "${GREEN}Done.${NC}"
