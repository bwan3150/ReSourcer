#!/usr/bin/env bash
# RS-002 API 测试：起服务 → toggle/list/status → kill → 重启 → 验证持久化 → kill
# 用法: bash .ai/reports/RS-002/api.sh   （日志同时写到 api.log）
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BIN="$ROOT/server/target/debug/re-sourcer"
BASE="http://127.0.0.1:1234"
WORK="$(mktemp -d /tmp/rs002.XXXXXX)"
DATA="$WORK/data"; SRC="$WORK/src"
mkdir -p "$DATA" "$SRC"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check(){ local desc="$1" cond="$2"; if eval "$cond"; then ok "$desc"; else bad "$desc"; fi; }

# 造几个真实文件
printf 'PNG-a' > "$SRC/alpha.png"; printf 'JPG-b' > "$SRC/beta.jpg"; printf 'MP4-c' > "$SRC/gamma.mp4"
SRC_REAL="$(cd "$SRC" && pwd -P)"   # macOS /tmp -> /private/tmp
echo "WORK=$WORK  SRC_REAL=$SRC_REAL"

SERVER_PID=""
start_server() {
  if lsof -iTCP:1234 -sTCP:LISTEN >/dev/null 2>&1; then echo "!! 端口 1234 已被占用，拒绝启动"; exit 2; fi
  RESOURCER_DIR="$DATA" nohup "$BIN" > "$WORK/server-$1.log" 2>&1 &
  SERVER_PID=$!; disown
  echo "-- 启动 server pid=$SERVER_PID (run $1)"
  for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "X-API-Key: $KEY" "$BASE/api/health" 2>/dev/null || true)
    if [ "$code" = "200" ]; then echo "-- health 200 after $((i*500))ms"; return 0; fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then echo "!! server 进程已退出"; cat "$WORK/server-$1.log"; return 1; fi
    sleep 0.5
  done
  echo "!! 45s 内未就绪"; return 1
}
stop_server() {
  echo "-- kill server pid=$SERVER_PID"
  kill "$SERVER_PID" 2>/dev/null; for i in $(seq 1 40); do kill -0 "$SERVER_PID" 2>/dev/null || break; sleep 0.25; done
  kill -9 "$SERVER_PID" 2>/dev/null || true
  for i in $(seq 1 20); do lsof -iTCP:1234 -sTCP:LISTEN >/dev/null 2>&1 || break; sleep 0.25; done
  lsof -iTCP:1234 -sTCP:LISTEN >/dev/null 2>&1 && { echo "!! 端口 1234 仍被占用"; exit 2; }
  echo "-- 进程已退出，端口已释放"
}
trap 'kill $SERVER_PID 2>/dev/null; true' EXIT

# 首次启动前 KEY 未知：先起服务（health 是否需要 key 未知，先用空）
KEY=""
start_server 1 || exit 1
KEY=$(python3 -c "import json;print(json.load(open('$DATA/config/secret.json'))['apikey'])")
echo "-- API key 读取自 $DATA/config/secret.json: ${KEY:0:8}..."
H=(-H "X-API-Key: $KEY" -H "Content-Type: application/json")
J() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

echo; echo "===== 准备：加源文件夹 + 扫描 + 取 uuid ====="
r=$(curl -s -w '\n%{http_code}' "${H[@]}" -X POST "$BASE/api/config/sources/add" -d "{\"folder_path\":\"$SRC_REAL\"}"); echo "$r"
r=$(curl -s -w '\n%{http_code}' "${H[@]}" -X POST "$BASE/api/indexer/scan" -d "{\"source_folder\":\"$SRC_REAL\",\"force\":true}"); echo "$r"
sleep 2
files_json=$(curl -s "${H[@]}" "$BASE/api/indexer/files?folder_path=$SRC_REAL")
echo "$files_json" | head -c 600; echo
UUIDS=( $(echo "$files_json" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['uuid']) for f in sorted(d['files'], key=lambda f: f['file_name'])]") )
check "扫描后拿到 3 个文件 uuid" '[ "${#UUIDS[@]}" -eq 3 ]' || { echo "$files_json"; exit 1; }
A=${UUIDS[0]}; B=${UUIDS[1]}; C=${UUIDS[2]}
echo "A(alpha.png)=$A  B(beta.jpg)=$B  C(gamma.mp4)=$C"

echo; echo "===== AC2: toggle 同一 uuid 两次 ====="
r1=$(curl -s -w '\n%{http_code}' "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"favorite\"}")
body1=$(echo "$r1" | sed '$d'); code1=$(echo "$r1" | tail -1); echo "1st: $code1 $body1"
check "第一次 toggle → 200" '[ "$code1" = 200 ]'
check "第一次 toggle → favorited=true, uuid/level 回显" '[ "$(echo "$body1" | J "d[\"favorited\"], d[\"uuid\"]==\"$A\", d[\"level\"]")" = "True True favorite" ]'
s=$(curl -s "${H[@]}" "$BASE/api/favorite/status?uuids=$A"); echo "status after 1st: $s"
check "第一次后 status 显示 favorite" '[ "$(echo "$s" | J "d.get(\"$A\")")" = favorite ]'
r2=$(curl -s -w '\n%{http_code}' "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"favorite\"}")
body2=$(echo "$r2" | sed '$d'); code2=$(echo "$r2" | tail -1); echo "2nd: $code2 $body2"
check "第二次 toggle → 200" '[ "$code2" = 200 ]'
check "第二次 toggle → favorited=false" '[ "$(echo "$body2" | J "d[\"favorited\"]")" = False ]'
s=$(curl -s "${H[@]}" "$BASE/api/favorite/status?uuids=$A"); echo "status after 2nd: $s"
check "第二次后 status 里不再有该 uuid" '[ "$s" = "{}" ]'
echo "-- 级别切换：favorite → featured 应覆盖而非取消"
r3=$(curl -s "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"favorite\"}"); echo "3rd(favorite): $r3"
r4=$(curl -s "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"featured\"}"); echo "4th(featured): $r4"
check "favorite→featured 返回 favorited=true level=featured" '[ "$(echo "$r4" | J "d[\"favorited\"], d[\"level\"]")" = "True featured" ]'
s=$(curl -s "${H[@]}" "$BASE/api/favorite/status?uuids=$A"); echo "status: $s"
check "status 显示 featured（覆盖，非双记录）" '[ "$(echo "$s" | J "d.get(\"$A\")")" = featured ]'
r5=$(curl -s "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"featured\"}"); echo "5th(featured again → 取消): $r5"
check "同级再点取消 favorited=false" '[ "$(echo "$r5" | J "d[\"favorited\"]")" = False ]'
echo "-- 非法 level"
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"bogus\"}")
check "level=bogus → 400 (got $rc)" '[ "$rc" = 400 ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\"}")
check "缺 level → 400 (got $rc)" '[ "$rc" = 400 ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' -H "Content-Type: application/json" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"favorite\"}")
check "无 API key → 401 (got $rc)" '[ "$rc" = 401 ]'

echo; echo "===== AC3: list?level=favorite 返回完整文件信息 ====="
curl -s "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"favorite\"}" >/dev/null
sleep 1.1   # created_at 秒级以上分辨率不确定，拉开时间保证排序可判
curl -s "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$B\",\"level\":\"featured\"}" >/dev/null
sleep 1.1
curl -s "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$C\",\"level\":\"favorite\"}" >/dev/null
l=$(curl -s -w '\n%{http_code}' "${H[@]}" "$BASE/api/favorite/list?level=favorite"); lb=$(echo "$l" | sed '$d'); lc=$(echo "$l" | tail -1)
echo "$lc $lb"
check "list?level=favorite → 200" '[ "$lc" = 200 ]'
check "total=2, files 长度 2" '[ "$(echo "$lb" | J "d[\"total\"], len(d[\"files\"])")" = "2 2" ]'
check "包含 alpha.png 与 gamma.mp4，不含 beta.jpg(featured)" '[ "$(echo "$lb" | J "sorted(f[\"file_name\"] for f in d[\"files\"])")" = "['"'"'alpha.png'"'"', '"'"'gamma.mp4'"'"']" ]'
check "每个文件含完整 IndexedFile 字段" '[ "$(echo "$lb" | J "all(set([\"uuid\",\"fingerprint\",\"current_path\",\"folder_path\",\"file_name\",\"file_type\",\"extension\",\"file_size\",\"created_at\",\"modified_at\",\"indexed_at\",\"source_url\"]) <= set(f) for f in d[\"files\"])")" = True ]'
check "按 created_at DESC：gamma.mp4 在前" '[ "$(echo "$lb" | J "d[\"files\"][0][\"file_name\"]")" = gamma.mp4 ]'
check "current_path 指向真实路径" '[ "$(echo "$lb" | J "d[\"files\"][0][\"current_path\"]")" = "$SRC_REAL/gamma.mp4" ]'
l2=$(curl -s "${H[@]}" "$BASE/api/favorite/list?level=featured"); echo "featured: $l2" | head -c 300; echo
check "list?level=featured → 仅 beta.jpg" '[ "$(echo "$l2" | J "[f[\"file_name\"] for f in d[\"files\"]]")" = "['"'"'beta.jpg'"'"']" ]'
l3=$(curl -s "${H[@]}" "$BASE/api/favorite/list"); 
check "list 不带 level → 全部 3 条" '[ "$(echo "$l3" | J "d[\"total\"], len(d[\"files\"])")" = "3 3" ]'
l4=$(curl -s "${H[@]}" "$BASE/api/favorite/list?limit=2&offset=0"); echo "page1: $(echo "$l4" | J "[f[\"file_name\"] for f in d[\"files\"]], d[\"has_more\"], d[\"total\"]")"
check "分页 limit=2 offset=0 → 2 条 has_more=true" '[ "$(echo "$l4" | J "len(d[\"files\"]), d[\"has_more\"]")" = "2 True" ]'
l5=$(curl -s "${H[@]}" "$BASE/api/favorite/list?limit=2&offset=2"); echo "page2: $(echo "$l5" | J "[f[\"file_name\"] for f in d[\"files\"]], d[\"has_more\"], d[\"total\"]")"
check "分页 limit=2 offset=2 → 1 条 has_more=false" '[ "$(echo "$l5" | J "len(d[\"files\"]), d[\"has_more\"]")" = "1 False" ]'
check "两页合并无重复且覆盖全部" '[ "$(python3 -c "import json; a=json.loads('"'"'$l4'"'"'); b=json.loads('"'"'$l5'"'"'); s=[f[\"uuid\"] for f in a[\"files\"]+b[\"files\"]]; print(len(s)==3 and len(set(s))==3)")" = True ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$BASE/api/favorite/list?level=bogus")
check "list?level=bogus → 400 (got $rc)" '[ "$rc" = 400 ]'
l6=$(curl -s "${H[@]}" "$BASE/api/favorite/list?limit=9999")
check "limit=9999 被钳到 200" '[ "$(echo "$l6" | J "d[\"limit\"]")" = 200 ]'

echo; echo "===== AC4: status 批量 ====="
GHOST="00000000-0000-0000-0000-000000000000"
s=$(curl -s -w '\n%{http_code}' "${H[@]}" "$BASE/api/favorite/status?uuids=$A,$B,$C,$GHOST"); sb=$(echo "$s" | sed '$d'); sc=$(echo "$s" | tail -1)
echo "$sc $sb"
check "status 4 个 uuid → 200" '[ "$sc" = 200 ]'
check "一次返回 A=favorite B=featured C=favorite" '[ "$(echo "$sb" | J "d.get(\"$A\"), d.get(\"$B\"), d.get(\"$C\")")" = "favorite featured favorite" ]'
check "未收藏 uuid 不出现" '[ "$(echo "$sb" | J "\"$GHOST\" in d")" = False ]'
s2=$(curl -s "${H[@]}" "$BASE/api/favorite/status?uuids=%20$A%20,,$B%20"); echo "带空白/空项: $s2"
check "uuids 含空白与空项仍正常解析" '[ "$(echo "$s2" | J "len(d)")" = 2 ]'
s3=$(curl -s -w '\n%{http_code}' "${H[@]}" "$BASE/api/favorite/status?uuids="); echo "空 uuids: $s3"
check "uuids= 空 → 200 {}" '[ "$(echo "$s3" | head -1)" = "{}" ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$BASE/api/favorite/status")
check "缺 uuids 参数 → 400 (got $rc)" '[ "$rc" = 400 ]'

echo; echo "===== 孤儿记录容忍：删掉 gamma.mp4 再扫描 ====="
rm "$SRC/gamma.mp4"
curl -s "${H[@]}" -X POST "$BASE/api/indexer/scan" -d "{\"source_folder\":\"$SRC_REAL\",\"force\":true}" >/dev/null; sleep 2
sqlite3 "$DATA/sqlite/data.db" "select uuid, current_path from file_index where uuid='$C';" | sed 's/^/  file_index: /'
sqlite3 "$DATA/sqlite/data.db" "select * from favorites where file_uuid='$C';" | sed 's/^/  favorites: /'
l7=$(curl -s -w '\n%{http_code}' "${H[@]}" "$BASE/api/favorite/list?level=favorite"); l7b=$(echo "$l7" | sed '$d'); l7c=$(echo "$l7" | tail -1)
echo "$l7c $(echo "$l7b" | J "[f[\"file_name\"] for f in d[\"files\"]], d[\"total\"]")"
check "删文件后 list 仍 200 不崩" '[ "$l7c" = 200 ]'
check "删文件后 list 不再含 gamma.mp4，total 同步" '[ "$(echo "$l7b" | J "[f[\"file_name\"] for f in d[\"files\"]], d[\"total\"]")" = "['"'"'alpha.png'"'"'] 1" ]'

echo; echo "===== 回归：既有接口 ====="
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$BASE/api/playlist?uuid=$A&folder_path=$SRC_REAL&mode=sequential"); check "GET /api/playlist (uuid+folder_path+mode) 仍 200 (got $rc)" '[ "$rc" = 200 ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$BASE/api/playlist"); check "GET /api/playlist 无 uuid 仍 400 既有契约 (got $rc)" '[ "$rc" = 400 ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$BASE/api/tag/list?source_folder=$SRC_REAL"); check "GET /api/tag/list 仍可用 (got $rc)" '[ "$rc" = 200 ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$BASE/api/config/state"); check "GET /api/config/state 仍 200 (got $rc)" '[ "$rc" = 200 ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X POST "$BASE/api/browser/browse" -d "{\"path\":\"$SRC_REAL\"}"); check "POST /api/browser/browse 仍 200 (got $rc)" '[ "$rc" = 200 ]'
fj=$(curl -s "${H[@]}" "$BASE/api/indexer/files?folder_path=$SRC_REAL"); check "indexer/files 仍返回 2 个现存文件" '[ "$(echo "$fj" | J "len(d[\"files\"])")" = 2 ]'
sqlite3 "$DATA/sqlite/data.db" ".schema tags" | grep -q "CREATE TABLE" && ok "tags/file_tags 表仍在" || bad "tags 表缺失"

echo; echo "===== AC5: 重启进程后收藏仍在 ====="
sqlite3 "$DATA/sqlite/data.db" "select file_uuid, level from favorites order by level;" | sed 's/^/  db before restart: /'
stop_server
start_server 2 || exit 1
s=$(curl -s -w '\n%{http_code}' "${H[@]}" "$BASE/api/favorite/status?uuids=$A,$B,$C"); sb=$(echo "$s" | sed '$d'); sc=$(echo "$s" | tail -1)
echo "$sc $sb"
check "重启后 status 仍返回 A=favorite B=featured C=favorite" '[ "$(echo "$sb" | J "d.get(\"$A\"), d.get(\"$B\"), d.get(\"$C\")")" = "favorite featured favorite" ]'
l8=$(curl -s "${H[@]}" "$BASE/api/favorite/list"); echo "list after restart: $(echo "$l8" | J "[f[\"file_name\"] for f in d[\"files\"]], d[\"total\"]")"
check "重启后 list 仍返回 alpha.png + beta.jpg（gamma 已删）" '[ "$(echo "$l8" | J "sorted(f[\"file_name\"] for f in d[\"files\"]), d[\"total\"]")" = "['"'"'alpha.png'"'"', '"'"'beta.jpg'"'"'] 2" ]'
r=$(curl -s "${H[@]}" -X POST "$BASE/api/favorite/toggle" -d "{\"uuid\":\"$A\",\"level\":\"favorite\"}"); echo "toggle after restart: $r"
check "重启后同级 toggle 是取消（说明状态确实来自磁盘）" '[ "$(echo "$r" | J "d[\"favorited\"]")" = False ]'
stop_server

echo; echo "===== 汇总: PASS=$PASS FAIL=$FAIL ====="
echo "WORK dir 保留: $WORK"
[ "$FAIL" -eq 0 ]
