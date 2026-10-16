#!/usr/bin/env bash
# Backend API tests: path-mirrored `.thumb` persistence
# Invoked by cargo test (tests/thumbnail_persist_api.rs) or directly:
#   RESOURCER_BIN=./target/debug/re-sourcer bash server/tests/thumbnail_persist_api.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${RESOURCER_BIN:-$ROOT/server/target/debug/re-sourcer}"
BASE="http://127.0.0.1:1234"
WORK="$(mktemp -d /tmp/resourcer-thumb-persist.XXXXXX)"
DATA="$WORK/data"
SRC="$WORK/src"
mkdir -p "$DATA" "$SRC/abc/123"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check(){ local desc="$1"; shift; if eval "$@"; then ok "$desc"; else bad "$desc"; fi; }

# Minimal 64x64 PNG (stdlib only — no Pillow required for seed)
write_png() {
  local out="$1" r="$2" g="$3" b="$4"
  OUT="$out" R="$r" G="$g" B="$b" python3 - <<'PY'
import os, struct, zlib, pathlib
def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
w = h = 64
pixel = bytes([int(os.environ['R']), int(os.environ['G']), int(os.environ['B'])])
raw = b''.join(b'\x00' + pixel * w for _ in range(h))
ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
path = pathlib.Path(os.environ['OUT'])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(png)
print("wrote", path, "bytes", len(png), "rgb", pixel)
PY
}
write_png "$SRC/abc/123/test.png" 20 140 220

SRC_REAL="$(cd "$SRC" && pwd -P)"
DATA_REAL="$(cd "$DATA" && pwd -P)"
MEDIA="$SRC_REAL/abc/123/test.png"
THUMB_DEFAULT="$SRC_REAL/.thumb/abc/123/test.png.thumb"
THUMB_640="$SRC_REAL/.thumb/abc/123/test.png.s640.thumb"

if [ ! -x "$BIN" ]; then
  echo "!! binary not found/executable: $BIN"
  echo "   build with: cargo build --manifest-path server/Cargo.toml"
  exit 2
fi

LOCK=/tmp/resourcer-api-test-port-1234.lock
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  if ! flock -w 180 9; then
    echo "!! could not acquire port 1234 test lock"
    exit 2
  fi
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
H=(-H "X-API-Key: $KEY")

echo; echo "===== seed source + scan ====="
curl -s "${H[@]}" -H "Content-Type: application/json" -X POST "$BASE/api/config/sources/add" \
  -d "{\"folder_path\":\"$SRC_REAL\"}" >/dev/null
curl -s "${H[@]}" -H "Content-Type: application/json" -X POST "$BASE/api/indexer/scan" \
  -d "{\"source_folder\":\"$SRC_REAL\",\"force\":true}" >/dev/null
for i in $(seq 1 40); do
  st=$(curl -s "${H[@]}" "$BASE/api/indexer/status")
  scanning=$(echo "$st" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_scanning', True))" 2>/dev/null || echo True)
  [ "$scanning" = "False" ] && break
  sleep 0.25
done

ENC_PATH=$(python3 -c "import urllib.parse;print(urllib.parse.quote('$MEDIA'))")

echo; echo "===== first request writes .thumb mirror ====="
check "no thumb before first request" '[ ! -f "$THUMB_DEFAULT" ]'
OUT1="$WORK/t1.jpg"
HDR1="$WORK/t1.hdr"
code=$(curl -sS -D "$HDR1" -o "$OUT1" -w '%{http_code}' "${H[@]}" \
  "$BASE/api/preview/thumbnail?path=${ENC_PATH}&size=300&tv=2")
if [ "$code" != "200" ]; then
  echo "-- first thumb body/hdr:"; head -c 400 "$OUT1"; echo; cat "$HDR1"; echo; tail -40 "$WORK/server.log"
fi
check "first thumb HTTP 200" '[ "$code" = "200" ]'
check "X-Thumbnail-Version 2" 'grep -qi "x-thumbnail-version: 2" "$HDR1"'
check "default mirror created" '[ -f "$THUMB_DEFAULT" ]'
# File is header+JPEG; JPEG SOI should appear after header.
# Prefer Python over grep: macOS BSD grep can fail with "illegal byte sequence" on binary.
check "mirror contains JPEG SOI" 'python3 -c "import pathlib,sys; d=pathlib.Path(sys.argv[1]).read_bytes(); raise SystemExit(0 if b\"\\xff\\xd8\" in d else 1)" "$THUMB_DEFAULT"'

M1=$(stat -c %Y "$THUMB_DEFAULT" 2>/dev/null || stat -f %m "$THUMB_DEFAULT")

echo; echo "===== second request reuses disk ====="
sleep 1
OUT2="$WORK/t2.jpg"
code=$(curl -sS -o "$OUT2" -w '%{http_code}' "${H[@]}" \
  "$BASE/api/preview/thumbnail?path=${ENC_PATH}&size=300&tv=2")
check "second thumb HTTP 200" '[ "$code" = "200" ]'
M2=$(stat -c %Y "$THUMB_DEFAULT" 2>/dev/null || stat -f %m "$THUMB_DEFAULT")
check "mirror mtime unchanged on hit" '[ "$M1" = "$M2" ]'
check "JPEG bodies match" 'cmp -s "$OUT1" "$OUT2"'

echo; echo "===== multi-size naming .s640.thumb ====="
OUT640="$WORK/t640.jpg"
code=$(curl -sS -o "$OUT640" -w '%{http_code}' "${H[@]}" \
  "$BASE/api/preview/thumbnail?path=${ENC_PATH}&size=640&tv=2")
check "size 640 HTTP 200" '[ "$code" = "200" ]'
check "s640 mirror created" '[ -f "$THUMB_640" ]'
check "default mirror still present" '[ -f "$THUMB_DEFAULT" ]'

echo; echo "===== mtime invalidate rebuilds ====="
# Change source content so size and/or mtime differ (blue → red)
write_png "$MEDIA" 200 40 40
sleep 1
OUT3="$WORK/t3.jpg"
code=$(curl -sS -o "$OUT3" -w '%{http_code}' "${H[@]}" \
  "$BASE/api/preview/thumbnail?path=${ENC_PATH}&size=300&tv=2")
check "rebuild after source change HTTP 200" '[ "$code" = "200" ]'
M3=$(stat -c %Y "$THUMB_DEFAULT" 2>/dev/null || stat -f %m "$THUMB_DEFAULT")
check "mirror rewritten after invalidate" '[ -n "$M2" ] && [ -n "$M3" ] && [ "$M3" -ge "$M2" ]'
# Bodies should differ (blue vs red); compare JPEG bytes without Pillow
check "rebuild changes JPEG body" '! cmp -s "$OUT1" "$OUT3"'

echo; echo "===== .thumb excluded from indexer files ====="
# Drop a decoy *.thumb into a normal folder and ensure scan does not list it as media
cp "$OUT1" "$SRC_REAL/abc/123/decoy.thumb" 2>/dev/null || cp "$OUT1" "$SRC_REAL/abc/123/decoy.thumb"
curl -s "${H[@]}" -H "Content-Type: application/json" -X POST "$BASE/api/indexer/scan" \
  -d "{\"source_folder\":\"$SRC_REAL\",\"force\":true}" >/dev/null
for i in $(seq 1 40); do
  st=$(curl -s "${H[@]}" "$BASE/api/indexer/status")
  scanning=$(echo "$st" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_scanning', True))" 2>/dev/null || echo True)
  [ "$scanning" = "False" ] && break
  sleep 0.25
done
FILES_JSON=$(curl -s "${H[@]}" "$BASE/api/indexer/files?folder_path=$SRC_REAL/abc/123")
FILES_JSON="$FILES_JSON" python3 - <<'PY'
import os, json
data = json.loads(os.environ["FILES_JSON"])
names = [f.get("file_name","") for f in data.get("files",[])]
print("indexed names:", names)
assert "decoy.thumb" not in names, names
assert not any(n.endswith(".thumb") for n in names), names
assert any(n == "test.png" for n in names), names
print("OK scan excludes *.thumb")
PY
if [ $? -eq 0 ]; then ok "scan excludes *.thumb"; else bad "scan excludes *.thumb"; fi

echo; echo "===== orphan GC on full scan ====="
# Remove media; leave orphan under .thumb; scan should delete orphan
rm -f "$MEDIA"
# Keep default thumb as orphan
check "orphan thumb present before GC" '[ -f "$THUMB_DEFAULT" ]'
curl -s "${H[@]}" -H "Content-Type: application/json" -X POST "$BASE/api/indexer/scan" \
  -d "{\"source_folder\":\"$SRC_REAL\",\"force\":true}" >/dev/null
for i in $(seq 1 40); do
  st=$(curl -s "${H[@]}" "$BASE/api/indexer/status")
  scanning=$(echo "$st" | python3 -c "import sys,json; print(json.load(sys.stdin).get('is_scanning', True))" 2>/dev/null || echo True)
  [ "$scanning" = "False" ] && break
  sleep 0.25
done
check "orphan thumb removed by GC" '[ ! -f "$THUMB_DEFAULT" ]'

echo; echo "===== summary: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
