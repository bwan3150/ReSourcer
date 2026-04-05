#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SERVER_VER=$(grep -m1 '^version' "$SCRIPT_DIR/server/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')
IOS_VER=$(grep -m1 'MARKETING_VERSION' "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

echo ""
echo -e "${CYAN}=== ReSourcer CI ===${NC}"
echo ""
echo -e "  Server  ${DIM}v${SERVER_VER}${NC}"
echo -e "  iOS     ${DIM}v${IOS_VER}${NC}"
echo ""
echo "  1) Server release     (bump version + tag + build)"
echo "  2) iOS release        (bump version + build + Pgyer)"
echo "  3) All                (bump both + tag + build all)"
echo ""
echo -e "${YELLOW}Select [1-3]:${NC}"
read -e -r choice

BUMP_SERVER=false
BUMP_IOS=false
NEW_SERVER_VER=""
NEW_IOS_VER=""

case "$choice" in
  1) BUMP_SERVER=true ;;
  2) BUMP_IOS=true ;;
  3) BUMP_SERVER=true; BUMP_IOS=true ;;
  *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
esac

# Collect version numbers
if [ "$BUMP_SERVER" = true ]; then
    echo ""
    echo -e "${YELLOW}New server version (current: ${SERVER_VER}):${NC}"
    read -e -r NEW_SERVER_VER
    if [ -z "$NEW_SERVER_VER" ]; then
        echo -e "${RED}Error: version cannot be empty${NC}"
        exit 1
    fi
    SERVER_TAG="server-v${NEW_SERVER_VER}"
    if git tag -l | grep -q "^${SERVER_TAG}$"; then
        echo -e "${YELLOW}Tag ${SERVER_TAG} already exists. Re-tag and rebuild? (y/n):${NC}"
        read -e -r retag
        if [ "$retag" = "y" ]; then
            git tag -d "$SERVER_TAG" 2>/dev/null
            git push origin --delete "$SERVER_TAG" 2>/dev/null
            echo -e "${GREEN}Old tag deleted${NC}"
        else
            exit 0
        fi
    fi
fi

if [ "$BUMP_IOS" = true ]; then
    echo ""
    echo -e "${YELLOW}New iOS version (current: ${IOS_VER}):${NC}"
    read -e -r NEW_IOS_VER
    if [ -z "$NEW_IOS_VER" ]; then
        echo -e "${RED}Error: version cannot be empty${NC}"
        exit 1
    fi
    IOS_TAG="ios-v${NEW_IOS_VER}"
    if git tag -l | grep -q "^${IOS_TAG}$"; then
        echo -e "${YELLOW}Tag ${IOS_TAG} already exists. Re-tag and rebuild? (y/n):${NC}"
        read -e -r retag
        if [ "$retag" = "y" ]; then
            git tag -d "$IOS_TAG" 2>/dev/null
            git push origin --delete "$IOS_TAG" 2>/dev/null
            echo -e "${GREEN}Old tag deleted${NC}"
        else
            exit 0
        fi
    fi
fi

# Confirm
echo ""
echo -e "${GREEN}=== Plan ===${NC}"
[ -n "$NEW_SERVER_VER" ] && echo -e "  Server  ${SERVER_VER} → ${GREEN}${NEW_SERVER_VER}${NC}  (tag: ${SERVER_TAG})"
[ -n "$NEW_IOS_VER" ] && echo -e "  iOS     ${IOS_VER} → ${GREEN}${NEW_IOS_VER}${NC}  (tag: ${IOS_TAG})"
echo ""
echo -e "${YELLOW}Proceed? (y/n):${NC}"
read -e -r confirm

if [ "$confirm" != "y" ]; then
    echo -e "${RED}Cancelled${NC}"
    exit 0
fi

# Include other unstaged changes in the first commit
if ! git diff --quiet; then
    echo -e "${YELLOW}Include other unstaged changes? (y/n):${NC}"
    read -e -r add_all
    [ "$add_all" = "y" ] && git add -A && git commit -m "chore: pending changes" && git push
fi

# === iOS release (first, so server commit is latest for server tag) ===
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
        git add "$SCRIPT_DIR/server/Cargo.toml" "$SCRIPT_DIR/server/config/app.json"
        git commit -m "release: server v${NEW_SERVER_VER}"
        git push || { echo -e "${RED}Push failed${NC}"; exit 1; }
    fi

    git tag "$SERVER_TAG"
    git push origin "$SERVER_TAG" || { echo -e "${RED}Server tag push failed${NC}"; exit 1; }
    echo -e "${GREEN}Tag ${SERVER_TAG} pushed → CI: server build + GitHub Release${NC}"
fi

echo ""
echo -e "${GREEN}Done.${NC}"
