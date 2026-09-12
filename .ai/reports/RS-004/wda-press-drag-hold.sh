#!/usr/bin/env bash
# 按下→(可选停顿)→慢速拖动→拖完停住→松手: $1=fromX $2=fromY $3=toX $4=toY (pt) $5=holdBeforeMs $6=moveMs $7=holdAfterMs
S=$(curl -s -m 5 http://127.0.0.1:8150/status | python3 -c "import sys,json;print(json.load(sys.stdin)['sessionId'])")
curl -s -m 30 -X POST http://127.0.0.1:8150/session/$S/actions -H 'Content-Type: application/json' -d "{\"actions\":[{\"type\":\"pointer\",\"id\":\"finger1\",\"parameters\":{\"pointerType\":\"touch\"},\"actions\":[
 {\"type\":\"pointerMove\",\"duration\":0,\"x\":$1,\"y\":$2},
 {\"type\":\"pointerDown\",\"button\":0},
 {\"type\":\"pause\",\"duration\":$5},
 {\"type\":\"pointerMove\",\"duration\":$6,\"x\":$3,\"y\":$4},
 {\"type\":\"pause\",\"duration\":$7},
 {\"type\":\"pointerUp\",\"button\":0}]}]}"
