#!/usr/bin/env bash
# 模拟器测试辅助：安装、写入 SharedPreferences、启动、截图、取 DAV 请求统计。
#
#   tool/emu_test.sh deploy
#   tool/emu_test.sh prefs baby-500 http://10.0.2.2:8088/
#   tool/emu_test.sh start
#   tool/emu_test.sh shot baseline
#   tool/emu_test.sh stats
#   tool/emu_test.sh logcat 120
set -euo pipefail

ADB=${ADB:-$HOME/Android/Sdk/platform-tools/adb}
PKG=com.growth_diary.app
ACT=com.growth_diary.app.MainActivity
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DAV=${DAV:-http://127.0.0.1:8088}

cmd=${1:-help}
shift || true

case "$cmd" in
  deploy)
    "$ADB" install -r -g "$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
    ;;
  prefs)
    id=${1:?config id 必填}
    url=${2:-http://10.0.2.2:8088/}
    tmp=$(mktemp)
    python3 - "$id" "$url" >"$tmp" <<'PY'
import html, json, sys
cid, url = sys.argv[1], sys.argv[2]
cfg = {
    "id": cid,
    "webdavUrl": url,
    "username": "tester",
    "password": "secret",
    "babyName": "小星星" if cid != "baby-2000" else "压力测试宝宝",
    "babyBirthDate": "2022-03-08T00:00:00.000",
    "babyConceptionDate": "2021-06-01T00:00:00.000",
    "babyCoverImagePath": None,
    "videoCompressionThreshold": 10,
    "webdavMirrors": [{"url": url, "wifiSsid": None}],
}
prefs = {
    "app_configs": json.dumps({cid: cfg}, ensure_ascii=False),
    "current_config_id": cid,
}
print("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>")
print("<map>")
for k, v in prefs.items():
    print(f'    <string name="flutter.{k}">{html.escape(v)}</string>')
print("</map>")
PY
    "$ADB" shell am force-stop "$PKG"
    "$ADB" push "$tmp" /data/local/tmp/dsh_prefs.xml >/dev/null
    "$ADB" shell run-as "$PKG" mkdir -p shared_prefs
    "$ADB" shell run-as "$PKG" cp /data/local/tmp/dsh_prefs.xml \
      shared_prefs/FlutterSharedPreferences.xml
    "$ADB" shell rm -f /data/local/tmp/dsh_prefs.xml
    rm -f "$tmp"
    echo "prefs written: $id -> $url"
    ;;
  start)
    "$ADB" shell am force-stop "$PKG"
    "$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null
    echo "started"
    ;;
  shot)
    name=${1:-shot}
    "$ADB" exec-out screencap -p >"$ROOT/build/emu/$name.png"
    echo "saved build/emu/$name.png"
    ;;
  stats)
    curl -s "$DAV/__stats"
    echo
    ;;
  reset)
    curl -s "$DAV/__reset" >/dev/null
    echo "dav stats reset"
    ;;
  chaos)
    curl -s "$DAV/__chaos?$*"
    echo
    ;;
  logcat)
    n=${1:-100}
    "$ADB" logcat -d -s flutter:I | tail -n "$n"
    ;;
  clear-log)
    "$ADB" logcat -c
    ;;
  *)
    sed -n '2,12p' "$0"
    ;;
esac
