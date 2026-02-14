#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# 检查是否有未提交的更改
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${YELLOW}检测到未提交的更改:${NC}"
    git status --short
    echo ""
    echo -e "${YELLOW}是否先提交这些更改? (y/n):${NC}"
    read -e -r commit_confirm
    if [ "$commit_confirm" = "y" ]; then
        git add -A
        git commit -m "Update: changes before ${NEW_TAG}"
        git push
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: git push失败${NC}"
            exit 1
        fi
    fi
fi

# 确认
echo -e "${YELLOW}确认创建并推送tag ${NEW_TAG}? (y/n):${NC}"
read -e -r confirm

if [ "$confirm" != "y" ]; then
    echo -e "${RED}已取消${NC}"
    exit 0
fi

# Git操作
echo -e "${GREEN}=== 执行Git操作 ===${NC}"

git tag "$NEW_TAG"
git push origin "$NEW_TAG"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}成功创建并推送tag: $NEW_TAG${NC}"
else
    echo -e "${RED}错误: tag推送失败${NC}"
    exit 1
fi
