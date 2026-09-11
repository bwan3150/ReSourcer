#!/usr/bin/env bash
# 只读状态快照：看进度不用翻日志。默认看 overnight worktree，加 . 看当前目录。
ORCH_DIR="${ORCH_DIR:-$HOME/Documents/GitHub/实验场/Ralph-Loop-Test/structure}"
TARGET="${1:-$HOME/.overnight/ReSourcer}"
[ -d "$TARGET/.ai" ] || TARGET="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ORCH_DIR/status.sh" "$TARGET" "${@:2}"
