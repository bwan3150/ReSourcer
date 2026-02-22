#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本所在目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 显示现有tags
echo -e "${GREEN}=== 现有标签 ===${NC}"
git tag -l | sort -V
echo ""

# 输入新tag
echo -e "${YELLOW}新版本tag号:${NC}"
read -e -r NEW_TAG

if [ -z "$NEW_TAG" ]; then
    echo -e "${RED}错误: tag不能为空${NC}"
    exit 1
fi

# 检查tag是否已存在
if git tag -l | grep -q "^${NEW_TAG}$"; then
    echo -e "${RED}错误: tag ${NEW_TAG} 已存在${NC}"
    exit 1
fi

# 去掉可能的 v 前缀，得到纯版本号
VERSION="${NEW_TAG#v}"

# 读取当前版本号（从 Cargo.toml）
CURRENT_VERSION=$(grep -m1 '^version' "$SCRIPT_DIR/server/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')
echo -e "${GREEN}当前版本: ${CURRENT_VERSION} → 新版本: ${VERSION}${NC}"

# 更新各文件中的版本号
echo -e "${GREEN}=== 更新版本号 ===${NC}"

# 1. Cargo.toml: version = "x.y.z"
sed -i '' "s/^version = \"${CURRENT_VERSION}\"/version = \"${VERSION}\"/" "$SCRIPT_DIR/server/Cargo.toml"
echo "  Cargo.toml ✓"

# 2. config/app.json: "version":"x.y.z"
sed -i '' "s/\"version\":\"${CURRENT_VERSION}\"/\"version\":\"${VERSION}\"/" "$SCRIPT_DIR/server/config/app.json"
echo "  config/app.json ✓"

# 3. static/login.html: ReSourcer vX.Y.Z
sed -i '' "s/ReSourcer v[0-9][0-9.a-zA-Z-]*/ReSourcer v${VERSION}/" "$SCRIPT_DIR/server/static/login.html"
echo "  static/login.html ✓"

# 4. static/index.html: ReSourcer vX.Y.Z
sed -i '' "s/ReSourcer v[0-9][0-9.a-zA-Z-]*/ReSourcer v${VERSION}/" "$SCRIPT_DIR/server/static/index.html"
echo "  static/index.html ✓"

echo ""

# 检查是否有未提交的更改（包括刚才的版本号更新）
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${YELLOW}检测到未提交的更改:${NC}"
    git status --short
    echo ""
fi

# 确认
echo -e "${YELLOW}确认提交版本更新并创建tag ${NEW_TAG}? (y/n):${NC}"
read -e -r confirm

if [ "$confirm" != "y" ]; then
    echo -e "${RED}已取消（版本号已修改，请手动还原）${NC}"
    exit 0
fi

# 提交版本号更新
echo -e "${GREEN}=== 提交版本更新 ===${NC}"
git add \
    "$SCRIPT_DIR/server/Cargo.toml" \
    "$SCRIPT_DIR/server/config/app.json" \
    "$SCRIPT_DIR/server/static/login.html" \
    "$SCRIPT_DIR/server/static/index.html"

# 如果有其他未暂存的更改也一并提交
if ! git diff --quiet; then
    echo -e "${YELLOW}还有其他未暂存的更改，是否一并提交? (y/n):${NC}"
    read -e -r add_all
    if [ "$add_all" = "y" ]; then
        git add -A
    fi
fi

git commit -m "Update: server side version to v${VERSION}"
git push
if [ $? -ne 0 ]; then
    echo -e "${RED}错误: git push失败${NC}"
    exit 1
fi

# 创建并推送 tag
echo -e "${GREEN}=== 创建并推送 tag ===${NC}"
git tag "$NEW_TAG"
git push origin "$NEW_TAG"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}成功: 版本更新到 v${VERSION}，tag ${NEW_TAG} 已推送${NC}"
else
    echo -e "${RED}错误: tag推送失败${NC}"
    exit 1
fi
