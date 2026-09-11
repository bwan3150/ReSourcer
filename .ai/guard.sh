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
BASE="$ROOT/.ai/baseline/linecount.txt"

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

# 通用棘轮：<名称> <基线文件> <输出违规文件列表的命令>
# 存量豁免、新增拦死。基线只许变短 —— 不是用来让守卫闭嘴的。
ratchet() {
  local name="$1" basefile="$ROOT/.ai/baseline/$2"; shift 2
  local now; now=$(mktemp)
  ( eval "$@" ) 2>/dev/null | sort -u > "$now"
  mkdir -p "$(dirname "$basefile")"
  if [ "${RATCHET_REFRESH:-0}" = "1" ]; then
    { echo "# $name 的存量违规，只许减少。"; cat "$now"; } > "$basefile"
    printf '↻ [%s] 基线：%s 项\n' "$name" "$(grep -cv '^#' "$basefile")"
    rm -f "$now"; return 0
  fi
  [ -f "$basefile" ] || : > "$basefile"
  local new; new=$(comm -23 "$now" <(grep -v '^#' "$basefile" | sort -u))
  if [ -n "$new" ]; then
    printf '── %-20s FAIL\n' "$name"
    echo "$new" | sed 's/^/      ❌ 新增违规: /'
    FAILED=1
  else
    printf '── %-20s PASS\n' "$name"
  fi
  rm -f "$now"
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
ratchet "no-bare-fetch" "bare-fetch.txt" \
  'git ls-files --cached --others --exclude-standard "web/src/*.vue" "web/src/*.js" | grep -v "web/src/api/" | xargs grep -ln "fetch(\|axios\." 2>/dev/null'

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
LIMIT=500
now=$(mktemp); trap 'rm -f "$now"' EXIT
git ls-files --cached --others --exclude-standard 'server/src/*.rs' 'web/src/*.vue' 'web/src/*.js' 'iOS/ReSourcer/*.swift' 2>/dev/null \
  | while read -r f; do
      [ -f "$f" ] || continue
      n=$(wc -l < "$f" | tr -d ' ')
      [ "$n" -gt "$LIMIT" ] && printf '%s\t%s\n' "$f" "$n"
    done | sort > "$now"

if [ "${RATCHET_REFRESH:-0}" = "1" ]; then
  mkdir -p "$(dirname "$BASE")"
  { echo "# 超过 ${LIMIT} 行的存量文件，只许变短。RATCHET_REFRESH=1 ./.ai/guard.sh 重新生成。"
    echo "# 刷新基线 = 认可这些文件又长了，需要人工确认，不是 Agent 自己能做的事。"
    cat "$now"; } > "$BASE"
  echo "↻ [linecount] 基线已刷新：$(grep -cv '^#' "$BASE") 个超阈文件 → $BASE"
  exit 0
fi

mkdir -p "$(dirname "$BASE")"; [ -f "$BASE" ] || : > "$BASE"
lc_fail=0
while IFS=$'\t' read -r f n; do
  [ -n "$f" ] || continue
  was=$(awk -F'\t' -v k="$f" '$1==k{print $2}' "$BASE")
  if [ -z "$was" ]; then
    echo "      ❌ $f: $n 行，首次超过 $LIMIT 行"
    echo "         → 按职责拆成新文件，不要按行数硬切"
    lc_fail=1
  elif [ "$n" -gt "$was" ]; then
    echo "      ❌ $f: $n 行，比基线 $was 行更长了（+$((n-was))）"
    echo "         → 超阈文件只许变短。先把它拆开，再往拆出来的地方加"
    lc_fail=1
  fi
done < "$now"
if [ $lc_fail -eq 0 ]; then printf '── %-20s PASS\n' "linecount"
else printf '── %-20s FAIL\n' "linecount"; FAILED=1; fi

exit $FAILED
