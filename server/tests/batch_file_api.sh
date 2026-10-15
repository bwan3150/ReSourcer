#!/usr/bin/env bash
# Backend API tests: /api/file/batch/move + /api/file/batch/delete
# Invoked by cargo test (tests/batch_file_api.rs) or directly:
#   RESOURCER_BIN=./target/debug/re-sourcer bash server/tests/batch_file_api.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${RESOURCER_BIN:-$ROOT/server/target/debug/re-sourcer}"
BASE="http://127.0.0.1:1234"
WORK="$(mktemp -d /tmp/resourcer-batch-api.XXXXXX)"
DATA="$WORK/data"
SRC="$WORK/src"
mkdir -p "$DATA/tools" "$SRC/Album"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check(){ local desc="$1"; shift; if eval "$@"; then ok "$desc"; else bad "$desc"; fi; }

# Stub tools so preflight_check does not block on network downloads
for tool in ffmpeg ffprobe; do
  cat > "$DATA/tools/$tool" <<'EOF'
#!/bin/sh
echo "$0 version test-stub"
exit 0
EOF
  chmod +x "$DATA/tools/$tool"
done

printf 'PNG-a' > "$SRC/alpha.png"
printf 'JPG-b' > "$SRC/beta.jpg"
printf 'GIF-c' > "$SRC/gamma.gif"
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

# Wait for health (no auth required)
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
J() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

echo; echo "===== seed source + scan ====="
curl -s "${H[@]}" -X POST "$BASE/api/config/sources/add" -d "{\"folder_path\":\"$SRC_REAL\"}" >/dev/null
curl -s "${H[@]}" -X POST "$BASE/api/indexer/scan" -d "{\"source_folder\":\"$SRC_REAL\",\"force\":true}" >/dev/null
for i in $(seq 1 40); do
  st=$(curl -s "${H[@]}" "$BASE/api/indexer/status")
  scanning=$(echo "$st" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_scanning', True))" 2>/dev/null || echo True)
  [ "$scanning" = "False" ] && break
  sleep 0.25
done
files_json=$(curl -s "${H[@]}" "$BASE/api/indexer/files?folder_path=$SRC_REAL")
mapfile -t UUIDS < <(echo "$files_json" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['uuid']) for f in sorted(d.get('files',[]), key=lambda f: f['file_name'])]")
check "indexed 3 files (got ${#UUIDS[@]})" '[ "${#UUIDS[@]}" -eq 3 ]' || { echo "$files_json"; exit 1; }
A=${UUIDS[0]}; B=${UUIDS[1]}; C=${UUIDS[2]}
echo "A=$A B=$B C=$C"

echo; echo "===== empty uuids rejected ====="
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X POST "$BASE/api/file/batch/move" \
  -d "{\"uuids\":[],\"target_folder\":\"$SRC_REAL/Album\"}")
check "batch/move empty uuids → 400 (got $rc)" '[ "$rc" = "400" ]'
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" -X POST "$BASE/api/file/batch/delete" \
  -d '{"uuids":[]}')
check "batch/delete empty uuids → 400 (got $rc)" '[ "$rc" = "400" ]'

echo; echo "===== auth required ====="
rc=$(curl -s -o /dev/null -w '%{http_code}' -H "Content-Type: application/json" \
  -X POST "$BASE/api/file/batch/move" -d "{\"uuids\":[\"$A\"],\"target_folder\":\"$SRC_REAL/Album\"}")
check "batch/move without key → 401 (got $rc)" '[ "$rc" = "401" ]'

echo; echo "===== batch move success ====="
body=$(curl -s "${H[@]}" -X POST "$BASE/api/file/batch/move" \
  -d "{\"uuids\":[\"$A\",\"$B\"],\"target_folder\":\"$SRC_REAL/Album\"}")
echo "$body"
check "batch move status=success" '[ "$(echo "$body" | J "d.get(\"status\")")" = "success" ]'
check "batch move success_count=2" '[ "$(echo "$body" | J "d.get(\"success_count\")")" = "2" ]'
album_count=$(ls -1 "$SRC_REAL/Album" 2>/dev/null | wc -l | tr -d ' ')
check "Album has 2 files (got $album_count)" '[ "$album_count" = "2" ]'

echo; echo "===== batch move partial (one missing) ====="
body=$(curl -s "${H[@]}" -X POST "$BASE/api/file/batch/move" \
  -d "{\"uuids\":[\"$C\",\"missing-uuid\"],\"target_folder\":\"$SRC_REAL/Album\"}")
echo "$body"
check "batch move partial status" '[ "$(echo "$body" | J "d.get(\"status\")")" = "partial" ]'
check "batch move partial success_count=1" '[ "$(echo "$body" | J "d.get(\"success_count\")")" = "1" ]'
check "batch move partial failure_count=1" '[ "$(echo "$body" | J "d.get(\"failure_count\")")" = "1" ]'

echo; echo "===== batch delete to recycle ====="
body=$(curl -s "${H[@]}" -X POST "$BASE/api/file/batch/delete" -d "{\"uuids\":[\"$A\",\"$B\"]}")
echo "$body"
check "batch delete status=success" '[ "$(echo "$body" | J "d.get(\"status\")")" = "success" ]'
check "recycle bin created" '[ -d "$SRC_REAL/_Recycle" ]'
recycle_count=$(ls -1 "$SRC_REAL/_Recycle" 2>/dev/null | wc -l | tr -d ' ')
check "recycle has ≥2 files (got $recycle_count)" '[ "$recycle_count" -ge 2 ]'

echo; echo "===== batch delete rejects recycle occupants ====="
body=$(curl -s "${H[@]}" -X POST "$BASE/api/file/batch/delete" -d "{\"uuids\":[\"$A\"]}")
echo "$body"
check "delete-in-recycle status=error" '[ "$(echo "$body" | J "d.get(\"status\")")" = "error" ]'
check "delete-in-recycle failure_count=1" '[ "$(echo "$body" | J "d.get(\"failure_count\")")" = "1" ]'

echo
echo "===== summary: PASS=$PASS FAIL=$FAIL ====="
[ "$FAIL" -eq 0 ]
