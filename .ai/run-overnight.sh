#!/usr/bin/env bash
# ReSourcer 的 overnight 启动封装。
#
#   ./.ai/run-overnight.sh [任务数]
#
# 做了这几件事（都是踩过的坑）：
#   - 在独立 git worktree 里跑，绝不碰你的主工作树和 main 分支
#   - 共享 CARGO_TARGET_DIR，否则 guard 每次冷编译要 100 秒以上
#   - 软链 node_modules，否则 web-build 直接 FAIL
#   - caffeinate 防锁屏，否则 iOS/web 的 UI 自动化整夜全红
#   - SRC_PATHS 覆盖三端源码，Tester 碰任何一处都会被回滚判 FAIL
set -uo pipefail
MAX_TASKS="${1:-6}"
MAIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="${ORCH:-$HOME/Documents/GitHub/实验场/Ralph-Loop-Test/structure/orchestrator.sh}"
WT="${WT:-$HOME/.overnight/ReSourcer}"
BRANCH="overnight/$(date +%m%d-%H%M)"

[ -x "$ORCH" ] || { echo "✗ 找不到 orchestrator: $ORCH"; exit 1; }

if [ ! -d "$WT" ]; then
  echo "建 worktree: $WT ($BRANCH)"
  mkdir -p "$(dirname "$WT")"
  git -C "$MAIN" worktree add -b "$BRANCH" "$WT" || exit 1
else
  echo "复用已有 worktree: $WT（分支 $(git -C "$WT" rev-parse --abbrev-ref HEAD)）"
fi

export CARGO_TARGET_DIR="$HOME/.cache/resourcer-overnight-target"
MAIN_WORKTREE="$MAIN" bash "$WT/.ai/preflight.sh" || exit 1

echo
echo "开跑：最多 $MAX_TASKS 个任务，日志 $WT/.ai/nightly.log"
echo "早上看：git -C $WT log --oneline / $WT/.ai/reports/ / $WT/.ai/usage.jsonl"
echo

exec caffeinate -dimsu env \
  SRC_PATHS="server/src web/src iOS/ReSourcer E-ink/app/src" \
  MODEL="${MODEL:-opus}" \
  REVIEW_EVERY=3 MAX_ATTEMPTS=3 \
  bash "$ORCH" "$WT" "$MAX_TASKS" 2>&1 | tee "$WT/.ai/nightly.log"
