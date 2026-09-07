#!/bin/zsh
# Build/install only the disposable probe package, never the Vizor wallet.
set -euo pipefail
serial=${1:?Usage: run-android.sh emulator-SERIAL output-directory}
out=${2:?Provide a dedicated output directory}
[[ "$serial" == emulator-* ]] || { print -u2 'Refusing a physical device'; exit 1; }
sdk=${ANDROID_SDK_ROOT:-/Users/rowan/Library/Android/sdk}
jdk=${PROBE_JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}
src=${0:A:h}
bt="$sdk/build-tools/36.0.0"
jar="$sdk/platforms/android-36/android.jar"
mkdir -p "$out/classes" "$out/dex"
"$jdk/bin/javac" -source 8 -target 8 -classpath "$jar" -d "$out/classes" "$src/Probe.java"
JAVA_HOME="$jdk" "$bt/d8" --lib "$jar" --output "$out/dex" "$out"/classes/app/vizor/bleprobe/*.class
"$bt/aapt2" link -o "$out/probe.apk" -I "$jar" --manifest "$src/AndroidManifest.xml"
zip -j "$out/probe.apk" "$out/dex/classes.dex"
if [[ ! -f "$out/debug.jks" ]]; then
  "$jdk/bin/keytool" -genkeypair -keystore "$out/debug.jks" -storepass android -keypass android -alias probe -dname 'CN=Vizor BLE Probe' -keyalg RSA -validity 2
fi
JAVA_HOME="$jdk" "$bt/apksigner" sign --ks "$out/debug.jks" --ks-pass pass:android "$out/probe.apk"
"$sdk/platform-tools/adb" -s "$serial" install --no-incremental -r -g "$out/probe.apk"
"$sdk/platform-tools/adb" -s "$serial" shell svc bluetooth enable
"$sdk/platform-tools/adb" -s "$serial" shell am start -n app.vizor.bleprobe/.Probe
probe_pid=''
for attempt in {1..5}; do
  probe_pid=$("$sdk/platform-tools/adb" -s "$serial" shell pidof app.vizor.bleprobe | tr -d '\r' || true)
  [[ -n "$probe_pid" ]] && break
  sleep 1
done
[[ -n "$probe_pid" ]] || { print -u2 'Probe did not start'; exit 1; }
for attempt in {1..50}; do
  logs=$("$sdk/platform-tools/adb" -s "$serial" logcat -d --pid="$probe_pid" -s VizorBleProbe:I AndroidRuntime:E)
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
print -u2 'No terminal probe result within 50 seconds'
exit 1
