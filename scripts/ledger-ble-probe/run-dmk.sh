#!/bin/zsh
# Official DMK test fixture only. Never installs/replaces the Vizor wallet.
set -euo pipefail
serial=${1:?Usage: run-dmk.sh emulator-SERIAL}
activity=${2:-DmkProbe}
[[ "$activity" == DmkProbe || "$activity" == HandlerProbe ]] || { print -u2 'Unknown probe'; exit 1; }
wait_ms=${3:-100}
rediscover=${4:-false}
[[ "$rediscover" == true || "$rediscover" == false ]] || { print -u2 'rediscover must be true or false'; exit 1; }
[[ "$wait_ms" == <-> ]] || { print -u2 'wait milliseconds must be nonnegative'; exit 1; }
[[ "$serial" == emulator-* ]] || { print -u2 'Refusing a physical device'; exit 1; }
src=${0:A:h}
repo=${src:h:h}
sdk=${ANDROID_SDK_ROOT:-/Users/rowan/Library/Android/sdk}
jdk=${PROBE_JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}
JAVA_HOME="$jdk" ANDROID_HOME="$sdk" "$repo/android/gradlew" -p "$src/dmk" assembleDebug --console=plain
"$sdk/platform-tools/adb" -s "$serial" install --no-incremental -r -g "$src/dmk/build/outputs/apk/debug/LedgerDmkBleProbe-debug.apk"
"$sdk/platform-tools/adb" -s "$serial" shell am start -n "app.vizor.dmkprobe/.$activity" --el waitMs "$wait_ms" --ez rediscover "$rediscover"
probe_pid=''
for attempt in {1..5}; do
  probe_pid=$("$sdk/platform-tools/adb" -s "$serial" shell pidof app.vizor.dmkprobe | tr -d '\r' || true)
  [[ -n "$probe_pid" ]] && break
  sleep 1
done
[[ -n "$probe_pid" ]] || { print -u2 'SDK probe did not start'; exit 1; }
for attempt in {1..50}; do
  logs=$("$sdk/platform-tools/adb" -s "$serial" logcat -d --pid="$probe_pid" -s VizorDmkProbe:I AndroidRuntime:E)
  if print -r -- "$logs" | rg -q 'FAIL |FATAL EXCEPTION'; then
    print -r -- "$logs"
    exit 1
  fi
  if print -r -- "$logs" | rg -q 'PASS ALL'; then
    print -r -- "$logs"
    exit 0
  fi
  sleep 1
done
print -u2 'No terminal SDK probe result within 50 seconds'
exit 1
