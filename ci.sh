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
IOS_VER=$(grep -m1 'MARKETING_VERSION' "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

echo ""
echo -e "${CYAN}=== ReSourcer CI ===${NC}"
echo ""
echo -e "  Server  ${DIM}v${SERVER_VER}${NC}"
echo -e "  iOS     ${DIM}v${IOS_VER}${NC}"
echo ""
echo "  1) Server only        (build server binary)"
echo "  2) iOS only            (build IPA + upload Pgyer)"
echo "  3) Release             (bump server version + tag + build all)"
echo ""
echo -e "${YELLOW}Select [1-3]:${NC}"
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
    ;; # continue to release flow
  *)
    echo -e "${RED}Invalid choice${NC}"
    exit 1
    ;;
esac

# === Release flow ===
echo ""
echo -e "${GREEN}=== Tags ===${NC}"
git tag -l | sort -V | tail -10
echo ""

# Server version = release tag
echo -e "${YELLOW}New server version (current: ${SERVER_VER}):${NC}"
read -e -r NEW_SERVER_VER

if [ -z "$NEW_SERVER_VER" ]; then
    echo -e "${RED}Error: version cannot be empty${NC}"
    exit 1
fi

NEW_TAG="v${NEW_SERVER_VER}"

if git tag -l | grep -q "^${NEW_TAG}$"; then
    echo -e "${RED}Error: tag ${NEW_TAG} already exists${NC}"
    exit 1
fi

# Optional: bump iOS version too
echo -e "${YELLOW}Bump iOS version? (current: ${IOS_VER}, Enter to skip):${NC}"
read -e -r NEW_IOS_VER

# Apply changes
echo ""
echo -e "${GREEN}=== Updating ===${NC}"

sed -i '' "s/^version = \"${SERVER_VER}\"/version = \"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/Cargo.toml"
sed -i '' "s/\"version\":\"${SERVER_VER}\"/\"version\":\"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/config/app.json"
echo -e "  Server  ${SERVER_VER} → ${GREEN}${NEW_SERVER_VER}${NC}"

if [ -n "$NEW_IOS_VER" ]; then
    sed -i '' "s/MARKETING_VERSION = ${IOS_VER};/MARKETING_VERSION = ${NEW_IOS_VER};/g" "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"
    echo -e "  iOS     ${IOS_VER} → ${GREEN}${NEW_IOS_VER}${NC}"
fi

echo ""

if ! git diff --quiet || ! git diff --cached --quiet; then
    git status --short
    echo ""
fi

echo -e "${YELLOW}Commit, tag ${NEW_TAG}, and push? (y/n):${NC}"
read -e -r confirm

if [ "$confirm" != "y" ]; then
    echo -e "${RED}Cancelled (revert modified files manually)${NC}"
    exit 0
fi

# Stage and commit
git add "$SCRIPT_DIR/server/Cargo.toml" "$SCRIPT_DIR/server/config/app.json"
[ -n "$NEW_IOS_VER" ] && git add "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"

if ! git diff --quiet; then
    echo -e "${YELLOW}Include other unstaged changes? (y/n):${NC}"
    read -e -r add_all
    [ "$add_all" = "y" ] && git add -A
fi

MSG="release: ${NEW_TAG}"
[ -n "$NEW_IOS_VER" ] && MSG="${MSG}, iOS ${NEW_IOS_VER}"

git commit -m "$MSG" || true
git push || { echo -e "${RED}Push failed${NC}"; exit 1; }

git tag "$NEW_TAG"
git push origin "$NEW_TAG" || { echo -e "${RED}Tag push failed${NC}"; exit 1; }

echo ""
echo -e "${GREEN}Released ${NEW_TAG}${NC}"
echo -e "${CYAN}CI: Server build + iOS build + Pgyer upload${NC}"
