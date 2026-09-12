#!/usr/bin/env bash
# 原地长按不移动: $1=x $2=y (pt) $3=holdMs
S=$(curl -s -m 5 http://127.0.0.1:8150/status | python3 -c "import sys,json;print(json.load(sys.stdin)['sessionId'])")
curl -s -m 30 -X POST http://127.0.0.1:8150/session/$S/actions -H 'Content-Type: application/json' -d "{\"actions\":[{\"type\":\"pointer\",\"id\":\"finger1\",\"parameters\":{\"pointerType\":\"touch\"},\"actions\":[
 {\"type\":\"pointerMove\",\"duration\":0,\"x\":$1,\"y\":$2},
 {\"type\":\"pointerDown\",\"button\":0},
 {\"type\":\"pause\",\"duration\":$3},
 {\"type\":\"pointerUp\",\"button\":0}]}]}"
