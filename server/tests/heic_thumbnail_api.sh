#!/usr/bin/env bash
# Backend API tests: HEIC tiled thumbnail generation
# Invoked by cargo test (tests/heic_thumbnail_api.rs) or directly:
#   RESOURCER_BIN=./target/debug/re-sourcer bash server/tests/heic_thumbnail_api.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${RESOURCER_BIN:-$ROOT/server/target/debug/re-sourcer}"
BASE="http://127.0.0.1:1234"
WORK="$(mktemp -d /tmp/resourcer-heic-api.XXXXXX)"
DATA="$WORK/data"
SRC="$WORK/src"
FIXTURE="$ROOT/server/tests/fixtures/tiled_heic_c007.heic"
mkdir -p "$DATA/tools" "$SRC"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check(){ local desc="$1"; shift; if eval "$@"; then ok "$desc"; else bad "$desc"; fi; }

if [ ! -f "$FIXTURE" ]; then
  echo "!! missing fixture: $FIXTURE"
  exit 2
fi

install_tool() {
  local name="$1"
  local url="$2"
  local dest="$DATA/tools/$name"
  if [ -x "/tmp/heic-test/${name}-bundled" ]; then
    cp "/tmp/heic-test/${name}-bundled" "$dest"
  elif [ -x "$ROOT/server/tools/$name" ]; then
    # Prefer repo-bundled tools on Mac (API script historically hardcoded linux URLs).
    cp "$ROOT/server/tools/$name" "$dest"
  else
    echo "-- downloading $name ..."
    curl -sSL -o "$dest" "$url"
  fi
  chmod +x "$dest"
}

# Platform URL is a last resort; prefer /tmp/heic-test/*-bundled or server/tools/.
if [ "$(uname -s)" = "Darwin" ]; then
  FFMPEG_URL="https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffmpeg/ffmpeg-macos"
  FFPROBE_URL="https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffprobe/ffprobe-macos"
else
  FFMPEG_URL="https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffmpeg/ffmpeg-linux-x86_64"
  FFPROBE_URL="https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffprobe/ffprobe-linux-x86_64"
fi
install_tool ffmpeg "$FFMPEG_URL"
install_tool ffprobe "$FFPROBE_URL"

cp "$FIXTURE" "$SRC/IMG_0792.HEIC"

SRC_REAL="$(cd "$SRC" && pwd -P)"
DATA_REAL="$(cd "$DATA" && pwd -P)"

if [ ! -x "$BIN" ]; then
  echo "!! binary not found/executable: $BIN"
  echo "   build with: cargo build --manifest-path server/Cargo.toml"
  exit 2
fi

# Serialize against other API tests that also bind :1234
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
echo "-- API key ${KEY:0:8}..."
H=(-H "X-API-Key: $KEY")

echo; echo "===== seed HEIC + scan ====="
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

UUID=$(curl -s "${H[@]}" "$BASE/api/indexer/files?folder_path=$SRC_REAL" | python3 -c "
import sys,json
files=json.load(sys.stdin).get('files',[])
for f in files:
  name=f.get('file_name','')
  if name.upper().endswith('.HEIC') and 'IMG_0792' in name:
    print(f['uuid']); break
")
check "indexed tiled HEIC uuid" '[ -n "$UUID" ]'
echo "-- uuid=$UUID"

ENC_PATH=$(python3 -c "import urllib.parse;print(urllib.parse.quote('$SRC_REAL/IMG_0792.HEIC'))")

echo; echo "===== thumbnail by path ====="
OUT="$WORK/thumb_path.jpg"
HDR="$WORK/thumb_path.hdr"
code=$(curl -sS -D "$HDR" -o "$OUT" -w '%{http_code}' "${H[@]}" \
  "$BASE/api/preview/thumbnail?path=${ENC_PATH}&size=300&tv=2")
check "thumbnail path HTTP 200" '[ "$code" = "200" ]'
check "Content-Type image/jpeg" 'grep -qi "content-type: image/jpeg" "$HDR"'
check "X-Thumbnail-Version 2" 'grep -qi "x-thumbnail-version: 2" "$HDR"'

THUMB_OUT="$OUT" python3 - <<'PY'
import os, sys
try:
    from PIL import Image
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '-q', 'pillow'])
    from PIL import Image
img = Image.open(os.environ['THUMB_OUT'])
w, h = img.size
print(f"-- path thumb size {w}x{h}")
assert w == 300 and h == 169, f"expected 300x169 got {w}x{h}"
pixels = list(img.getdata())
samples = [pixels[y * w + x] for y in (10, h // 2, h - 10) for x in (10, w // 2, w - 10)]
uniq = len(set(samples))
print(f"-- distinct corner/center samples: {uniq}")
assert uniq >= 3, "thumbnail looks too uniform (likely single tile / grey blob)"
print("OK path thumb")
PY
if [ $? -eq 0 ]; then ok "path thumb dimensions + detail"; else bad "path thumb dimensions + detail"; fi

echo; echo "===== thumbnail by uuid ====="
OUT2="$WORK/thumb_uuid.jpg"
code=$(curl -sS -o "$OUT2" -w '%{http_code}' "${H[@]}" \
  "$BASE/api/preview/thumbnail?uuid=${UUID}&size=300&tv=2")
check "thumbnail uuid HTTP 200" '[ "$code" = "200" ]'
THUMB_OUT="$OUT2" python3 - <<'PY'
import os
from PIL import Image
img = Image.open(os.environ['THUMB_OUT'])
assert img.size == (300, 169), img.size
print("OK uuid thumb", img.size)
PY
if [ $? -eq 0 ]; then ok "uuid thumb dimensions"; else bad "uuid thumb dimensions"; fi

echo; echo "===== summary: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
