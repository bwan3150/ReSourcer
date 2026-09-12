#!/usr/bin/env bash
# AC6 trial runner (round 2): 打开预览 → WDA 慢速移动后停住 → 看有没有被踢回 Gallery
# 用法: ac6-trial.sh <label> <thumbX_px> <thumbY_px> <waitText> <fromX> <fromY> <toX> <toY> <moveMs> <holdMs> <trials> [burst]
export PATH="$HOME/.toolkit/tke/bin:$PATH"
D=sim:575B910A-8F00-40D9-A501-C28C7A3199F0; UDID=575B910A-8F00-40D9-A501-C28C7A3199F0
L=~/.toolkit/tke/logs/RS-004-r2/
LABEL=$1; TX=$2; TY=$3; WT=$4; FX=$5; FY=$6; X2=$7; Y2=$8; MV=$9; HD=${10}; N=${11}; BURST=${12:-}
OUT=/Users/ericwang/Documents/GitHub/ReSourcer/.ai/reports/RS-004/ac6-r2-trials.txt
for i in $(seq 1 $N); do
  tke -d $D --no-raw-pages steps "点击 [坐标@($TX,$TY)] # AC6 [$LABEL] trial ${i} - 打开预览" "等到 [$WT, 5s]" --log $L >/tmp/rs004-work/r2/nav.log 2>&1 || { echo "$i | $LABEL | NAV-FAIL"; tail -3 /tmp/rs004-work/r2/nav.log | tee -a $OUT; continue; }
  if [ -n "$BURST" ]; then
    ( for t in 3 6 9 12 16 20; do xcrun simctl io $UDID screenshot /tmp/rs004-work/r2/${BURST}-t$(printf %02d $t).png >/dev/null 2>&1; sleep 0.25; done ) &
  fi
  bash /Users/ericwang/Documents/GitHub/ReSourcer/.ai/reports/RS-004/wda-move-hold.sh $FX $FY $X2 $Y2 $MV $HD >/dev/null
  wait
  sleep 1
  tbl=$(tke -d $D refresh 2>/dev/null)
  if echo "$tbl" | grep -q "MP4"; then r=DISMISSED; else r=stayed; fi
  echo "$i | $LABEL | move ${MV}ms then hold ${HD}ms | $r" | tee -a $OUT
  if [ "$r" = stayed ]; then
    # 清理：长按退出回 Gallery（AC2 已验证可用）；失败就点关闭按钮
    tke -d $D --no-raw-pages steps "按压 [坐标@(603,1300), 1000] # trial $i 收尾：长按退出" "等到 [MP4, 5s]" --log $L >/dev/null 2>&1 || {
      echo "   !! 长按退出失败，改用关闭按钮" | tee -a $OUT
      tke -d $D --no-raw-pages steps '如果没看到 [返回, 0s] 就 点击 [坐标@(603,1300)]' '点击 [坐标@(105,270)]' '等到 [MP4, 5s]' --log $L >/dev/null 2>&1 || echo "   !! 关闭按钮也失败" | tee -a $OUT; }
  fi
done
