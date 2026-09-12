#!/usr/bin/env bash
# RS-004 boot: 起 server（临时数据目录）+ 加源文件夹 + 扫描，供 iOS 模拟器连接
set -uo pipefail
W=/tmp/rs004-work; DATA=$W/data; SRC=$(cd $W/media && pwd -P)
BIN=server/target/debug/re-sourcer; BASE=http://127.0.0.1:1234
if lsof -iTCP:1234 -sTCP:LISTEN >/dev/null 2>&1; then echo "!! 端口 1234 已被占用"; lsof -iTCP:1234 -sTCP:LISTEN; exit 2; fi
cargo build --manifest-path server/Cargo.toml --quiet 2>&1 | tail -3
RESOURCER_DIR=$DATA nohup $BIN > $W/server.log 2>&1 &
PID=$!; disown; echo "server pid=$PID"; echo $PID > $W/server.pid
for i in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' $BASE/api/health || true)
  [ "$code" = 200 ] && { echo "health 200 after $((i*500))ms"; break; }
  kill -0 $PID 2>/dev/null || { echo "!! server exited"; cat $W/server.log; exit 1; }
  sleep 0.5
done
KEY=$(python3 -c "import json;print(json.load(open('$DATA/config/secret.json'))['apikey'])")
echo "$KEY" > $W/apikey; echo "apikey=$KEY"
H=(-H "X-API-Key: $KEY" -H "Content-Type: application/json")
echo "-- sources/add"; curl -s -w ' [%{http_code}]\n' "${H[@]}" -X POST $BASE/api/config/sources/add -d "{\"folder_path\":\"$SRC\"}"
echo "-- indexer/scan"; curl -s -w ' [%{http_code}]\n' "${H[@]}" -X POST $BASE/api/indexer/scan -d "{\"source_folder\":\"$SRC\",\"force\":true}"
sleep 2
echo "-- indexer/files"; curl -s "${H[@]}" "$BASE/api/indexer/files?folder_path=$SRC" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f['file_name'], f['file_type'] if 'file_type' in f else '', f['uuid']) for f in d['files']]"
echo "-- config/state"; curl -s "${H[@]}" $BASE/api/config/state | head -c 400; echo
