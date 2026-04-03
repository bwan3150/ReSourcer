#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 选择构建目标
echo ""
echo -e "${CYAN}=== ReSourcer CI ===${NC}"
echo ""
echo "  1) Server only"
echo "  2) iOS only (+ Pgyer upload)"
echo "  3) All (Server + iOS + Pgyer)"
echo "  4) Tag release (push tag → auto build all)"
echo ""
echo -e "${YELLOW}Select [1-4]:${NC}"
read -e -r choice

case "$choice" in
  1)
    echo -e "${GREEN}Triggering server-only build...${NC}"
    gh workflow run release.yml -f build_ios=false -f upload_pgyer=false
    echo -e "${GREEN}Done. Check: gh run list --workflow=release.yml${NC}"
    exit 0
    ;;
  2)
    echo -e "${GREEN}Triggering iOS build + Pgyer upload...${NC}"
    gh workflow run release.yml -f build_ios=true -f upload_pgyer=true
    echo -e "${GREEN}Done. Check: gh run list --workflow=release.yml${NC}"
    exit 0
    ;;
  3)
    echo -e "${GREEN}Triggering full build (Server + iOS + Pgyer)...${NC}"
    gh workflow run release.yml -f build_ios=true -f upload_pgyer=true
    echo -e "${GREEN}Done. Check: gh run list --workflow=release.yml${NC}"
    exit 0
    ;;
  4)
    ;; # continue to tag release flow below
  *)
    echo -e "${RED}Invalid choice${NC}"
    exit 1
    ;;
esac

# === Tag release flow ===
echo ""
echo -e "${GREEN}=== Existing tags ===${NC}"
git tag -l | sort -V | tail -10
echo ""

echo -e "${YELLOW}New tag:${NC}"
read -e -r NEW_TAG

if [ -z "$NEW_TAG" ]; then
    echo -e "${RED}Error: tag cannot be empty${NC}"
    exit 1
fi

if git tag -l | grep -q "^${NEW_TAG}$"; then
    echo -e "${RED}Error: tag ${NEW_TAG} already exists${NC}"
    exit 1
fi

VERSION="${NEW_TAG#v}"
CURRENT_VERSION=$(grep -m1 '^version' "$SCRIPT_DIR/server/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')
echo -e "${GREEN}Version: ${CURRENT_VERSION} → ${VERSION}${NC}"

# Update version numbers
echo -e "${GREEN}=== Updating versions ===${NC}"

sed -i '' "s/^version = \"${CURRENT_VERSION}\"/version = \"${VERSION}\"/" "$SCRIPT_DIR/server/Cargo.toml"
echo "  server/Cargo.toml ✓"

sed -i '' "s/\"version\":\"${CURRENT_VERSION}\"/\"version\":\"${VERSION}\"/" "$SCRIPT_DIR/server/config/app.json"
echo "  server/config/app.json ✓"

sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"${VERSION}\"/" "$SCRIPT_DIR/web/package.json"
echo "  web/package.json ✓"

echo ""

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${YELLOW}Pending changes:${NC}"
    git status --short
    echo ""
fi

echo -e "${YELLOW}Commit and push tag ${NEW_TAG}? (y/n):${NC}"
read -e -r confirm

if [ "$confirm" != "y" ]; then
    echo -e "${RED}Cancelled (version files already modified, revert manually)${NC}"
    exit 0
fi

echo -e "${GREEN}=== Committing ===${NC}"
git add \
    "$SCRIPT_DIR/server/Cargo.toml" \
    "$SCRIPT_DIR/server/config/app.json" \
    "$SCRIPT_DIR/web/package.json"

if ! git diff --quiet; then
    echo -e "${YELLOW}Include other unstaged changes? (y/n):${NC}"
    read -e -r add_all
    if [ "$add_all" = "y" ]; then
        git add -A
    fi
fi

git commit -m "release: v${VERSION}"
git push || { echo -e "${RED}Push failed${NC}"; exit 1; }

echo -e "${GREEN}=== Creating tag ===${NC}"
git tag "$NEW_TAG"
git push origin "$NEW_TAG" || { echo -e "${RED}Tag push failed${NC}"; exit 1; }

echo -e "${GREEN}Released v${VERSION} — tag ${NEW_TAG} pushed${NC}"
echo -e "${CYAN}CI will build: Server + iOS + Pgyer (triggered by tag)${NC}"
