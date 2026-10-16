#!/usr/bin/env bash
# Backend API tests: GET /api/file/metadata?path=
# Invoked by cargo test (tests/file_metadata_api.rs) or directly:
#   RESOURCER_BIN=./target/debug/re-sourcer bash server/tests/file_metadata_api.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${RESOURCER_BIN:-$ROOT/server/target/debug/re-sourcer}"
BASE="http://127.0.0.1:1234"
WORK="$(mktemp -d /tmp/resourcer-metadata-api.XXXXXX)"
DATA="$WORK/data"
SRC="$WORK/src"
FIX="$ROOT/server/tests/fixtures"
mkdir -p "$DATA/tools" "$SRC"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
check(){ local desc="$1"; shift; if eval "$@"; then ok "$desc"; else bad "$desc"; fi; }

# Prefer real ffmpeg/ffprobe from PATH for HEIC dims; fall back to stubs
for tool in ffmpeg ffprobe; do
  if command -v "$tool" >/dev/null 2>&1; then
    ln -sf "$(command -v "$tool")" "$DATA/tools/$tool"
  else
    cat > "$DATA/tools/$tool" <<'EOF'
#!/bin/sh
echo "$0 version test-stub"
exit 0
EOF
    chmod +x "$DATA/tools/$tool"
  fi
done

cp "$FIX/meta_with_exif.jpg" "$SRC/IMG_4821.jpg"
cp "$FIX/meta_with_exif.heic" "$SRC/IMG_4821.HEIC"
cp "$FIX/meta_sparse.png" "$SRC/plain.png"
SRC_REAL="$(cd "$SRC" && pwd -P)"
DATA_REAL="$(cd "$DATA" && pwd -P)"

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
echo "-- API key ${KEY:0:8}..."
H=(-H "X-API-Key: $KEY")
J() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

echo; echo "===== auth required ====="
rc=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/file/metadata?path=$SRC_REAL/IMG_4821.jpg")
check "metadata without key → 401 (got $rc)" '[ "$rc" = "401" ]'

echo; echo "===== missing path param ====="
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$BASE/api/file/metadata")
check "metadata missing path → 400 (got $rc)" '[ "$rc" = "400" ]'

echo; echo "===== missing file ====="
rc=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" \
  "$BASE/api/file/metadata?path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$SRC_REAL/nope.jpg'))")")
check "metadata missing file → 404 (got $rc)" '[ "$rc" = "404" ]'

enc() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"; }

echo; echo "===== JPEG with EXIF GPS + capture time ====="
body=$(curl -s "${H[@]}" "$BASE/api/file/metadata?path=$(enc "$SRC_REAL/IMG_4821.jpg")")
echo "$body" | python3 -m json.tool | head -40
check "jpeg format=JPEG" '[ "$(echo "$body" | J "d.get(\"format\")")" = "JPEG" ]'
check "jpeg has capture_time" '[ -n "$(echo "$body" | J "d.get(\"capture_time\") or \"\"")" ]'
check "jpeg has gps.lat" '[ "$(echo "$body" | J "d.get(\"gps\",{}).get(\"lat\") is not None")" = "True" ]'
check "jpeg has width" '[ "$(echo "$body" | J "d.get(\"width\")")" = "1200" ]'
check "jpeg has height" '[ "$(echo "$body" | J "d.get(\"height\")")" = "800" ]'
check "jpeg omits null duration key" '[ "$(echo "$body" | J "\"duration\" in d")" = "False" ]'
if command -v exiftool >/dev/null 2>&1; then
  check "jpeg make=Apple" '[ "$(echo "$body" | J "d.get(\"make\")")" = "Apple" ]'
  check "jpeg model=iPhone 15 Pro" '[ "$(echo "$body" | J "d.get(\"model\")")" = "iPhone 15 Pro" ]'
  check "jpeg iso=50" '[ "$(echo "$body" | J "d.get(\"iso\")")" = "50" ]'
fi

echo; echo "===== sparse PNG hides GPS/capture ====="
body=$(curl -s "${H[@]}" "$BASE/api/file/metadata?path=$(enc "$SRC_REAL/plain.png")")
echo "$body" | python3 -m json.tool | head -30
check "png format=PNG" '[ "$(echo "$body" | J "d.get(\"format\")")" = "PNG" ]'
check "png no gps key" '[ "$(echo "$body" | J "\"gps\" in d")" = "False" ]'
check "png no capture_time key" '[ "$(echo "$body" | J "\"capture_time\" in d")" = "False" ]'
check "png no make key" '[ "$(echo "$body" | J "\"make\" in d")" = "False" ]'
check "png no model key" '[ "$(echo "$body" | J "\"model\" in d")" = "False" ]'
check "png no iso key" '[ "$(echo "$body" | J "\"iso\" in d")" = "False" ]'
check "png has filename" '[ "$(echo "$body" | J "d.get(\"filename\")")" = "plain.png" ]'
check "png has size" '[ "$(echo "$body" | J "int(d.get(\"size\") or 0) > 0")" = "True" ]'

echo; echo "===== HEIC with EXIF (via exiftool when available) ====="
body=$(curl -s "${H[@]}" "$BASE/api/file/metadata?path=$(enc "$SRC_REAL/IMG_4821.HEIC")")
echo "$body" | python3 -m json.tool | head -40
check "heic format=HEIC" '[ "$(echo "$body" | J "d.get(\"format\")")" = "HEIC" ]'
check "heic has filename" '[ "$(echo "$body" | J "d.get(\"filename\")")" = "IMG_4821.HEIC" ]'
# capture/gps/camera depend on exiftool being on PATH — soft assert when present
if command -v exiftool >/dev/null 2>&1; then
  check "heic has capture_time (exiftool)" '[ -n "$(echo "$body" | J "d.get(\"capture_time\") or \"\"")" ]'
  check "heic has gps (exiftool)" '[ "$(echo "$body" | J "d.get(\"gps\") is not None")" = "True" ]'
  check "heic make=Apple" '[ "$(echo "$body" | J "d.get(\"make\")")" = "Apple" ]'
  check "heic model=iPhone 15 Pro" '[ "$(echo "$body" | J "d.get(\"model\")")" = "iPhone 15 Pro" ]'
  check "heic iso=50" '[ "$(echo "$body" | J "d.get(\"iso\")")" = "50" ]'
else
  ok "heic exiftool soft-skip (not installed)"
fi

echo
echo "===== summary: PASS=$PASS FAIL=$FAIL ====="
[ "$FAIL" -eq 0 ]
