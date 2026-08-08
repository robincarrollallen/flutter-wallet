#!/bin/bash
# Flutter 钱包 App 驱动器（iOS 模拟器）。
# 用法见同目录 SKILL.md。所有坐标为**设备像素**（iPhone 17 Pro = 1206x2622）。
set -euo pipefail

BUNDLE=com.crypto.wallet.flutter.wallet
SIM_NAME="iPhone 17 Pro"
DEV_W=1206; DEV_H=2622
TITLEBAR=58          # 经验标定值，勿改成 28——见 SKILL.md「坐标标定」
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${WALLET_RUN_OUT:-/tmp/wallet-run}"
mkdir -p "$OUT"

udid() { xcrun simctl list devices available | awk -F'[()]' "/$SIM_NAME \(/{print \$2; exit}"; }

_bin() {  # 首次使用时编译 click.swift
  [ -x "$HERE/click" ] && return
  swiftc -O -o "$HERE/click" "$HERE/click.swift"
}

_win() { osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of window 1' | tr ',' ' '; }

_front() {  # Simulator 必须是前台窗口，否则点击落到别的 App 上（静默失败）。
            # 但 activate 后必须等足 ~1.2s——延时太短会把紧接着的第一次点击吞掉。
  [ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')" = Simulator ] && return
  osascript -e 'tell application "Simulator" to activate'; sleep 1.2
}

_map() {  # 设备像素 -> 屏幕坐标
  read -r WX WY WW WH < <(_win)
  python3 -c "
T=$TITLEBAR; dw,dh=$DEV_W,$DEV_H
s=min($WW/dw,($WH-T)/dh); ox=$WX+($WW-dw*s)/2; oy=$WY+T
v=[$(echo "$@" | tr ' ' ',')]
print(' '.join(str(round(ox+v[i]*s)) if i%2==0 else str(round(oy+v[i]*s)) for i in range(len(v))))"
}

_plist() {
  echo "$(xcrun simctl get_app_container booted $BUNDLE data)/Library/Preferences/$BUNDLE.plist"
}

case "${1:-}" in
  boot)
    U=$(udid); xcrun simctl boot "$U" 2>/dev/null || true
    open -a Simulator; sleep 8; xcrun simctl list devices booted | tail -2 ;;

  run)   # 全量构建并启动（首次 ~45s）。日志落在 $OUT/run.log
    U=$(udid)
    flutter run -d "$U" --debug > "$OUT/run.log" 2>&1 &
    until grep -qE "Flutter run key commands|Error|error:" "$OUT/run.log" 2>/dev/null; do sleep 5; done
    sleep 8; tail -3 "$OUT/run.log" ;;

  restart)  # 比点返回键可靠得多——顶部小控件命中率低，回首页一律用这个
    xcrun simctl terminate booted $BUNDLE >/dev/null 2>&1 || true; sleep 2
    xcrun simctl launch booted $BUNDLE >/dev/null; sleep 6 ;;

  tap)   _bin; _front; read -r X Y < <(_map "$2" "$3"); "$HERE/click" "$X" "$Y" ;;
  drag)  _bin; _front; read -r -a C < <(_map "$2" "$3" "$4" "$5"); "$HERE/click" drag "${C[@]}" ;;
  type)  _front; osascript -e "tell application \"System Events\" to keystroke \"$2\"" ;;

  shot)  # shot <名字> —— 原图 + 可读缩略图
    N="${2:-shot}"
    xcrun simctl io booted screenshot "$OUT/$N.png" >/dev/null 2>&1
    sips -Z 700 --out "$OUT/${N}_view.png" "$OUT/$N.png" >/dev/null 2>&1
    echo "$OUT/${N}_view.png" ;;

  crop)  # crop <名字> <设备y起> <高> —— 精确定位控件坐标用
    sips -c "$4" $DEV_W --cropOffset "$3" 0 --out "$OUT/_crop.png" "$OUT/$2.png" >/dev/null 2>&1
    sips -Z 1000 "$OUT/_crop.png" >/dev/null 2>&1
    echo "$OUT/_crop.png  (设备 y $3..$(($3+$4)), 显示宽1000, 换算 x$(python3 -c "print(round($DEV_W/1000,3))"))" ;;

  cache) # 断言用：各币种行情缓存 + 链图标缓存的写入时刻
    plutil -convert json -o - "$(_plist)" | python3 -c "
import sys,json,datetime
d=json.load(sys.stdin)
print('计价币种:', json.loads(d.get('flutter.fiat_currency','{}')).get('code','?'))
for k in sorted(x for x in d if 'cache' in x):
    try:
        v=json.loads(d[k])
        print(f'  {k[8:]:22s} {datetime.datetime.fromtimestamp(v[\"at\"]/1000):%H:%M:%S}  条目={len(v[\"data\"])}')
    except Exception: pass
print('  现在                   ', datetime.datetime.now().strftime('%H:%M:%S'))" ;;

  changed)  # changed <A> <B> —— 裁掉状态栏再比对；否则时钟每分钟变化会造成假阳性
    for n in "$2" "$3"; do
      sips -c 2300 $DEV_W --cropOffset 320 0 --out "$OUT/_h_$n.png" "$OUT/$n.png" >/dev/null 2>&1
    done
    [ "$(md5 -q "$OUT/_h_$2.png")" != "$(md5 -q "$OUT/_h_$3.png")" ] && echo changed || echo same ;;

  *) sed -n '2,4p' "${BASH_SOURCE[0]}"; echo
     echo "命令: boot | run | restart | tap X Y | drag X1 Y1 X2 Y2 | type TEXT"
     echo "      shot NAME | crop NAME Y H | cache | changed A B" ;;
esac
