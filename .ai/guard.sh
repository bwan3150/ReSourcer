#!/usr/bin/env bash
# ReSourcer 守卫 —— 由 Orchestrator 在每个 Developer step 之后强制执行。
#
#   Developer / Tester 不准修改本文件。
#   Reviewer 只能新增 / 收紧检查；删除或放宽必须走人工确认。
#   退出码 0 = PASS，非 0 = FAIL（任务打回 Developer 重做）。
#
# 单跑：./.ai/guard.sh          刷新棘轮基线：RATCHET_REFRESH=1 ./.ai/guard.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FAILED=0
# 解释器显式化：guard 是评判标准，不该受 conda / fnm / PATH 变动影响
PY="${GUARD_PYTHON:-/usr/bin/python3}"
command -v "$PY" >/dev/null 2>&1 || PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "✗ 找不到 python3，guard 无法运行"; exit 1; }
RATCHET="$ROOT/.ai/checks/ratchet.py"

check() {
  local name="$1"; shift
  local t0=$SECONDS
  if ( eval "$@" ) >/tmp/guard-$$.log 2>&1; then   # 子 shell：不让 cd 泄漏到后续检查
    printf '── %-20s PASS  (%ss)\n' "$name" "$((SECONDS-t0))"
  else
    printf '── %-20s FAIL  (%ss)\n' "$name" "$((SECONDS-t0))"
    sed 's/^/      /' /tmp/guard-$$.log | tail -25
    FAILED=1
  fi
  rm -f /tmp/guard-$$.log
}

# ══ 编译 ══════════════════════════════════════════════
check "server-check"  "cargo check --manifest-path server/Cargo.toml --quiet"
check "server-test"   "cargo test  --manifest-path server/Cargo.toml --quiet"
if [ -d web/node_modules ]; then
  check "web-build" "cd web && npm run build"
else
  printf '── %-20s FAIL  (web/node_modules 缺失，先跑 .ai/preflight.sh)\n' "web-build"
  FAILED=1
fi

# ══ 架构约束（project.md 的硬化）══════════════════════
# web 的 HTTP 请求必须走 api/ 层（棘轮：存量豁免，新增拦死）
"$PY" "$RATCHET" grep --name no-bare-fetch \
  --baseline "$ROOT/.ai/baseline/bare-fetch.txt" \
  --pattern 'fetch\(|axios\.' \
  --paths 'web/src/*.vue' 'web/src/*.js' --exclude 'web/src/api/' || FAILED=1

# 不准新增硬编码绝对路径
check "no-hardcoded-path" '
  ! git diff HEAD -- server/src iOS web/src 2>/dev/null \
    | grep -E "^\+" | grep -vE "^\+\+\+" \
    | grep -E "\"/opt/|\"/volume[0-9]|\"/share/|\"/Users/" | grep .'

# 密钥不准进仓库
check "no-secrets" '
  ! git diff HEAD 2>/dev/null | grep -E "^\+" \
    | grep -inE "(api[_-]?key|secret|password|token)[\"'"'"']?\s*[:=]\s*[\"'"'"'][^\"'"'"']{16,}" | grep .'

# 改了路由就必须同步 API 文档
check "api-doc-sync" '
  if git diff HEAD --name-only 2>/dev/null | grep -q "server/src/.*/mod\.rs"; then
    git diff HEAD --name-only | grep -q "docs/API.md"
  else true; fi'

# ══ 棘轮：超阈文件只许变短 ════════════════════════════
# 不是洁癖 —— 越长越没人敢拆，越没人拆越长。基线不是用来让守卫闭嘴的。
# 用 python 而不是 shell：同样的扫描 bash 要 2.4 秒（每个文件 fork 一次 wc），
# 这里 50 毫秒；更要紧的是 shell 版扫不到文件时会静默返回空 = 假绿。
"$PY" "$RATCHET" lines --limit 500 \
  --baseline "$ROOT/.ai/baseline/linecount.txt" \
  --paths 'server/src/*.rs' 'web/src/*.vue' 'web/src/*.js' 'iOS/ReSourcer/*.swift' || FAILED=1

exit $FAILED
