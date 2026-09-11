#!/usr/bin/env bash
# 开跑前的环境预热。worktree 是干净的，没有 target/ 和 node_modules，
# 不预热的话：guard 第一次要 100 秒以上，web-build 直接 FAIL。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN="${MAIN_WORKTREE:-$HOME/Documents/GitHub/ReSourcer}"
cd "$ROOT"

echo "预热 $ROOT"

# node_modules：软链主工作树的，省掉一次 npm ci
if [ ! -d web/node_modules ]; then
  if [ -d "$MAIN/web/node_modules" ] && [ "$MAIN" != "$ROOT" ]; then
    ln -s "$MAIN/web/node_modules" web/node_modules
    echo "  ✓ node_modules → 软链自主工作树"
  else
    ( cd web && npm ci --silent ) && echo "  ✓ node_modules → npm ci"
  fi
else
  echo "  · node_modules 已存在"
fi

# cargo：共享 target，避免每个 worktree 从头编译
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/resourcer-overnight-target}"
mkdir -p "$CARGO_TARGET_DIR"
echo "  · CARGO_TARGET_DIR=$CARGO_TARGET_DIR"
echo "  编译预热中（首次可能几分钟）..."
cargo check --manifest-path server/Cargo.toml --quiet && echo "  ✓ cargo 预热完成"

echo "校验 guard 是否为绿（不绿就别开跑，第一轮就会卡死）"
if bash ./.ai/guard.sh >/tmp/preflight-guard.log 2>&1; then
  echo "  ✓ guard PASS"
else
  echo "  ✗ guard 当前是红的，先修："; sed 's/^/    /' /tmp/preflight-guard.log | tail -20; exit 1
fi
