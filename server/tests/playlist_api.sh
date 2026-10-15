#!/usr/bin/env bash
# Backend API tests: /api/playlist (sequential / list_loop / shuffle)
# Invoked by cargo test (tests/playlist_api.rs) or directly:
#   RESOURCER_BIN=./target/debug/re-sourcer bash server/tests/playlist_api.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${RESOURCER_BIN:-$ROOT/server/target/debug/re-sourcer}"
BASE="http://127.0.0.1:1234"
WORK="$(mktemp -d /tmp/resourcer-playlist-api.XXXXXX)"
DATA="$WORK/data"
SRC="$WORK/src"
mkdir -p "$DATA/tools" "$SRC"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check(){ local desc="$1"; shift; if eval "$@"; then ok "$desc"; else bad "$desc"; fi; }

for tool in ffmpeg ffprobe; do
  cat > "$DATA/tools/$tool" <<'EOF'
#!/bin/sh
echo "$0 version test-stub"
exit 0
EOF
  chmod +x "$DATA/tools/$tool"
done

# 8 files so sequential windows and shuffle have room
for i in $(seq -w 0 7); do
  printf 'PNG-%s' "$i" > "$SRC/file$i.png"
done
SRC_REAL="$(cd "$SRC" && pwd -P)"
DATA_REAL="$(cd "$DATA" && pwd -P)"

if [ ! -x "$BIN" ]; then
  echo "!! binary not found/executable: $BIN"
  echo "   build with: cargo build --manifest-path server/Cargo.toml"
  exit 2
fi

if command -v lsof >/dev/null 2>&1 && lsof -iTCP:1234 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "!! port 1234 is in use; stop the other server before running API tests"
  exit 2
fi

SERVER_PID=""
cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "-- WORK=$WORK"
echo "-- BIN=$BIN"
RESOURCER_DIR="$DATA_REAL" nohup "$BIN" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
disown

ready=0
for i in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/health" 2>/dev/null || true)
  if [ "$code" = "200" ]; then
    echo "-- health 200 after ~$((i*500))ms"
    ready=1
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "!! server exited early"; cat "$WORK/server.log"; exit 1
  fi
  sleep 0.5
done
check "health endpoint reachable" '[ "$ready" = "1" ]' || { cat "$WORK/server.log"; exit 1; }

KEY=$(python3 -c "import json;print(json.load(open('$DATA_REAL/config/secret.json'))['apikey'])")
echo "-- API key ${KEY:0:8}..."
H=(-H "X-API-Key: $KEY" -H "Content-Type: application/json")

echo; echo "===== seed source + scan ====="
curl -s "${H[@]}" -X POST "$BASE/api/config/sources/add" -d "{\"folder_path\":\"$SRC_REAL\"}" >/dev/null
curl -s "${H[@]}" -X POST "$BASE/api/indexer/scan" -d "{\"source_folder\":\"$SRC_REAL\",\"force\":true}" >/dev/null
for i in $(seq 1 40); do
  st=$(curl -s "${H[@]}" "$BASE/api/indexer/status")
  scanning=$(echo "$st" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_scanning', True))" 2>/dev/null || echo True)
  [ "$scanning" = "False" ] && break
  sleep 0.25
done
files_json=$(curl -s "${H[@]}" "$BASE/api/indexer/files?folder_path=$SRC_REAL&sort=name_asc")
UUIDS=()
while IFS= read -r line; do
  [ -n "$line" ] && UUIDS+=("$line")
done < <(echo "$files_json" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['uuid']) for f in sorted(d.get('files',[]), key=lambda f: f['file_name'])]")
check "indexed 8 files (got ${#UUIDS[@]})" '[ "${#UUIDS[@]}" -eq 8 ]' || { echo "$files_json"; exit 1; }

MID="${UUIDS[3]}"
FIRST="${UUIDS[0]}"
LAST="${UUIDS[7]}"
FOLDER_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$SRC_REAL', safe=''))")

echo; echo "===== sequential (no wrap) ====="
seq_json=$(curl -s "${H[@]}" "$BASE/api/playlist?uuid=$MID&folder_path=$FOLDER_ENC&mode=sequential&sort=name_asc")
check "sequential mid returns items" "echo '$seq_json' | python3 -c \"import sys,json; d=json.load(sys.stdin); assert len(d['items'])>=3; assert d['at_start'] is False; assert d['at_end'] is False\""

seq_first=$(curl -s "${H[@]}" "$BASE/api/playlist?uuid=$FIRST&folder_path=$FOLDER_ENC&mode=sequential&sort=name_asc")
check "sequential first sets at_start" "echo '$seq_first' | python3 -c \"import sys,json; d=json.load(sys.stdin); assert d['at_start'] is True; assert d['current_index']==0\""

seq_last=$(curl -s "${H[@]}" "$BASE/api/playlist?uuid=$LAST&folder_path=$FOLDER_ENC&mode=sequential&sort=name_asc")
check "sequential last sets at_end" "echo '$seq_last' | python3 -c \"import sys,json; d=json.load(sys.stdin); assert d['at_end'] is True\""

echo; echo "===== list_loop (wrap) ====="
loop_first=$(curl -s "${H[@]}" "$BASE/api/playlist?uuid=$FIRST&folder_path=$FOLDER_ENC&mode=list_loop&sort=name_asc")
check "list_loop first wraps prior items" "echo '$loop_first' | python3 -c \"import sys,json; d=json.load(sys.stdin); assert d['current_index']>0\""

echo; echo "===== shuffle fresh vs sequential neighbors ====="
# Capture sequential neighbor set
seq_neighbors=$(echo "$seq_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(i['uuid'] for i in d['items'] if i['uuid']!='$MID'))")

differed=0
for _ in $(seq 1 15); do
  sh_json=$(curl -s "${H[@]}" "$BASE/api/playlist?uuid=$MID&folder_path=$FOLDER_ENC&mode=shuffle")
  sh_neighbors=$(echo "$sh_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(i['uuid'] for i in d['items'] if i['uuid']!='$MID'))")
  if [ "$sh_neighbors" != "$seq_neighbors" ]; then
    differed=1
    break
  fi
done
check "fresh shuffle differs from sequential neighbors" '[ "$differed" = "1" ]'

# Navigating with current_queue should preserve relative order of kept items
fresh=$(curl -s "${H[@]}" "$BASE/api/playlist?uuid=$MID&folder_path=$FOLDER_ENC&mode=shuffle")
QUEUE=$(echo "$fresh" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(i['uuid'] for i in d['items']))")
NEXT=$(echo "$fresh" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['items'][d['current_index']+1]['uuid'])")
QUEUE_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$QUEUE', safe=''))")
moved=$(curl -s "${H[@]}" "$BASE/api/playlist?uuid=$NEXT&folder_path=$FOLDER_ENC&mode=shuffle&current_queue=$QUEUE_ENC")
check "shuffle nav preserves prior current before next" "echo '$moved' | python3 -c \"
import sys,json
d=json.load(sys.stdin)
ids=[i['uuid'] for i in d['items']]
assert '$MID' in ids and '$NEXT' in ids
assert ids.index('$MID') < ids.index('$NEXT')
\""

echo
echo "===== summary: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
