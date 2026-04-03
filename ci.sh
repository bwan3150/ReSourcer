#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read current versions
SERVER_VER=$(grep -m1 '^version' "$SCRIPT_DIR/server/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')
WEB_VER=$(grep '"version"' "$SCRIPT_DIR/web/package.json" | head -1 | sed 's/.*: "\(.*\)".*/\1/')
IOS_VER=$(grep -m1 'MARKETING_VERSION' "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

echo ""
echo -e "${CYAN}=== ReSourcer CI ===${NC}"
echo ""
echo -e "  Server  ${DIM}${SERVER_VER}${NC}"
echo -e "  Web     ${DIM}${WEB_VER}${NC}"
echo -e "  iOS     ${DIM}${IOS_VER}${NC}"
echo ""
echo "  1) Server only"
echo "  2) iOS only (+ Pgyer)"
echo "  3) All (Server + iOS + Pgyer)"
echo "  4) Release (bump versions + tag + build all)"
echo ""
echo -e "${YELLOW}Select [1-4]:${NC}"
read -e -r choice

case "$choice" in
  1)
    echo -e "${GREEN}Triggering server build...${NC}"
    gh workflow run release.yml -f build_ios=false -f upload_pgyer=false
    echo -e "${GREEN}Done. Watch: gh run list --workflow=release.yml${NC}"
    exit 0
    ;;
  2)
    echo -e "${GREEN}Triggering iOS build + Pgyer...${NC}"
    gh workflow run release.yml -f build_ios=true -f upload_pgyer=true
    echo -e "${GREEN}Done. Watch: gh run list --workflow=release.yml${NC}"
    exit 0
    ;;
  3)
    echo -e "${GREEN}Triggering full build...${NC}"
    gh workflow run release.yml -f build_ios=true -f upload_pgyer=true
    echo -e "${GREEN}Done. Watch: gh run list --workflow=release.yml${NC}"
    exit 0
    ;;
  4)
    ;; # continue to release flow
  *)
    echo -e "${RED}Invalid choice${NC}"
    exit 1
    ;;
esac

# === Release flow ===
echo ""
echo -e "${GREEN}=== Existing tags ===${NC}"
git tag -l | sort -V | tail -10
echo ""

# Bump versions — ask for each component
echo -e "${CYAN}Bump versions (press Enter to skip):${NC}"
echo ""

echo -e "  Server ${DIM}[current: ${SERVER_VER}]${NC}:"
read -e -r NEW_SERVER_VER
echo -e "  Web    ${DIM}[current: ${WEB_VER}]${NC}:"
read -e -r NEW_WEB_VER
echo -e "  iOS    ${DIM}[current: ${IOS_VER}]${NC}:"
read -e -r NEW_IOS_VER
echo ""

# Release tag
echo -e "${YELLOW}Release tag (e.g. v0.4.0):${NC}"
read -e -r NEW_TAG

if [ -z "$NEW_TAG" ]; then
    echo -e "${RED}Error: tag cannot be empty${NC}"
    exit 1
fi

if git tag -l | grep -q "^${NEW_TAG}$"; then
    echo -e "${RED}Error: tag ${NEW_TAG} already exists${NC}"
    exit 1
fi

# Apply version bumps
CHANGED=false
echo ""
echo -e "${GREEN}=== Updating ===${NC}"

if [ -n "$NEW_SERVER_VER" ]; then
    sed -i '' "s/^version = \"${SERVER_VER}\"/version = \"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/Cargo.toml"
    sed -i '' "s/\"version\":\"${SERVER_VER}\"/\"version\":\"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/config/app.json"
    echo -e "  Server  ${SERVER_VER} → ${GREEN}${NEW_SERVER_VER}${NC}"
    CHANGED=true
fi

if [ -n "$NEW_WEB_VER" ]; then
    sed -i '' "s/\"version\": \"${WEB_VER}\"/\"version\": \"${NEW_WEB_VER}\"/" "$SCRIPT_DIR/web/package.json"
    echo -e "  Web     ${WEB_VER} → ${GREEN}${NEW_WEB_VER}${NC}"
    CHANGED=true
fi

if [ -n "$NEW_IOS_VER" ]; then
    sed -i '' "s/MARKETING_VERSION = ${IOS_VER};/MARKETING_VERSION = ${NEW_IOS_VER};/g" "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"
    echo -e "  iOS     ${IOS_VER} → ${GREEN}${NEW_IOS_VER}${NC}"
    CHANGED=true
fi

if [ "$CHANGED" = false ]; then
    echo "  (no version changes)"
fi

echo ""

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${YELLOW}Pending changes:${NC}"
    git status --short
    echo ""
fi

echo -e "${YELLOW}Commit and push tag ${NEW_TAG}? (y/n):${NC}"
read -e -r confirm

if [ "$confirm" != "y" ]; then
    echo -e "${RED}Cancelled (revert modified files manually if needed)${NC}"
    exit 0
fi

echo -e "${GREEN}=== Committing ===${NC}"

# Stage version files
[ -n "$NEW_SERVER_VER" ] && git add "$SCRIPT_DIR/server/Cargo.toml" "$SCRIPT_DIR/server/config/app.json"
[ -n "$NEW_WEB_VER" ] && git add "$SCRIPT_DIR/web/package.json"
[ -n "$NEW_IOS_VER" ] && git add "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"

# Check for other changes
if ! git diff --quiet; then
    echo -e "${YELLOW}Include other unstaged changes? (y/n):${NC}"
    read -e -r add_all
    if [ "$add_all" = "y" ]; then
        git add -A
    fi
fi

# Build commit message
MSG="release: ${NEW_TAG}"
[ -n "$NEW_SERVER_VER" ] && MSG="${MSG}, server ${NEW_SERVER_VER}"
[ -n "$NEW_WEB_VER" ] && MSG="${MSG}, web ${NEW_WEB_VER}"
[ -n "$NEW_IOS_VER" ] && MSG="${MSG}, iOS ${NEW_IOS_VER}"

git commit -m "$MSG" || true
git push || { echo -e "${RED}Push failed${NC}"; exit 1; }

echo -e "${GREEN}=== Creating tag ===${NC}"
git tag "$NEW_TAG"
git push origin "$NEW_TAG" || { echo -e "${RED}Tag push failed${NC}"; exit 1; }

echo ""
echo -e "${GREEN}Released ${NEW_TAG}${NC}"
echo -e "${CYAN}CI will build: Server + iOS + Pgyer${NC}"
