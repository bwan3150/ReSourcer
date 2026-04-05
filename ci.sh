#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

dispatch_workflow() {
    local WORKFLOW="$1"
    local PAYLOAD='{"ref":"main"}'
    if command -v gh &>/dev/null; then
        gh workflow run "$WORKFLOW"
    else
        REPO=$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/' | sed 's/.*github.com[:/]\(.*\)/\1/')
        echo -e "${YELLOW}GitHub Personal Access Token (workflow scope):${NC}"
        read -s -r GH_TOKEN
        echo ""
        curl -sf -X POST \
            "https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW}/dispatches" \
            -H "Authorization: token ${GH_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "$PAYLOAD" \
            && echo -e "${GREEN}Triggered.${NC}" \
            || echo -e "${RED}Failed. Trigger manually on GitHub Actions.${NC}"
    fi
}

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

# Bump server version
if [ "$BUMP_SERVER" = true ]; then
    echo ""
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
fi

# Bump iOS version
if [ "$BUMP_IOS" = true ]; then
    echo ""
    echo -e "${YELLOW}New iOS version (current: ${IOS_VER}):${NC}"
    read -e -r NEW_IOS_VER
    if [ -z "$NEW_IOS_VER" ]; then
        echo -e "${RED}Error: version cannot be empty${NC}"
        exit 1
    fi
fi

# Apply changes
echo ""
echo -e "${GREEN}=== Updating ===${NC}"

if [ -n "$NEW_SERVER_VER" ]; then
    sed -i '' "s/^version = \"${SERVER_VER}\"/version = \"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/Cargo.toml"
    sed -i '' "s/\"version\":\"${SERVER_VER}\"/\"version\":\"${NEW_SERVER_VER}\"/" "$SCRIPT_DIR/server/config/app.json"
    echo -e "  Server  ${SERVER_VER} → ${GREEN}${NEW_SERVER_VER}${NC}"
fi

if [ -n "$NEW_IOS_VER" ]; then
    sed -i '' "s/MARKETING_VERSION = ${IOS_VER};/MARKETING_VERSION = ${NEW_IOS_VER};/g" "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"
    echo -e "  iOS     ${IOS_VER} → ${GREEN}${NEW_IOS_VER}${NC}"
fi

echo ""
git status --short
echo ""

# Build commit message
MSG="release:"
[ -n "$NEW_SERVER_VER" ] && MSG="${MSG} server v${NEW_SERVER_VER}"
[ -n "$NEW_IOS_VER" ] && MSG="${MSG} iOS v${NEW_IOS_VER}"

echo -e "${YELLOW}Commit: ${MSG}${NC}"
echo -e "${YELLOW}Proceed? (y/n):${NC}"
read -e -r confirm

if [ "$confirm" != "y" ]; then
    echo -e "${RED}Cancelled (revert modified files manually)${NC}"
    exit 0
fi

# Stage version files
[ -n "$NEW_SERVER_VER" ] && git add "$SCRIPT_DIR/server/Cargo.toml" "$SCRIPT_DIR/server/config/app.json"
[ -n "$NEW_IOS_VER" ] && git add "$SCRIPT_DIR/iOS/ReSourcer.xcodeproj/project.pbxproj"

# Other unstaged changes
if ! git diff --quiet; then
    echo -e "${YELLOW}Include other unstaged changes? (y/n):${NC}"
    read -e -r add_all
    [ "$add_all" = "y" ] && git add -A
fi

git commit -m "$MSG" || true
git push || { echo -e "${RED}Push failed${NC}"; exit 1; }

# Tag + trigger full CI (only when server is bumped)
if [ -n "$NEW_SERVER_VER" ]; then
    git tag "$NEW_TAG"
    git push origin "$NEW_TAG" || { echo -e "${RED}Tag push failed${NC}"; exit 1; }
    echo -e "${GREEN}Tag ${NEW_TAG} pushed → CI: server build + GitHub Release${NC}"
fi

# iOS build via manual dispatch (always separate workflow)
if [ "$BUMP_IOS" = true ]; then
    echo -e "${GREEN}Triggering iOS build + Pgyer...${NC}"
    dispatch_workflow "ios.yml"
fi

echo ""
echo -e "${GREEN}Done.${NC}"
