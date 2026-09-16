#!/usr/bin/env bash
# Capture only debug Ledger metadata; do not clear the device's existing logs.
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <adb-device-id> [output.log]" >&2
  exit 2
fi
DEVICE_ID="$1"
OUTPUT="${2:-/tmp/ledger-nano-x-$(date +%Y%m%d-%H%M%S).log}"
ADB="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}/platform-tools/adb"
if [[ ! -x "$ADB" ]]; then ADB="$(command -v adb)"; fi
"$ADB" -s "$DEVICE_ID" get-state >/dev/null
mkdir -p "$(dirname "$OUTPUT")"
if [[ -e "$OUTPUT" ]]; then
  echo "Output already exists; choose a new filename: $OUTPUT" >&2
  exit 2
fi
{
  echo "[LedgerTrace][capture] utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for prop in ro.product.model ro.build.version.release ro.build.version.sdk; do
    echo "[LedgerTrace][capture] $prop=$("$ADB" -s "$DEVICE_ID" shell getprop "$prop" | tr -d '\r')"
  done
} | tee "$OUTPUT"
echo "Recording Ledger diagnostics to $OUTPUT. Reproduce in the debug app, then press Ctrl-C." >&2
# Native timing lines remain available even when Dart is waiting or stalls.
"$ADB" -s "$DEVICE_ID" logcat -T 1 -v threadtime LedgerTrace:I flutter:I '*:S' |
  rg --line-buffered '\[LedgerTrace\]' | tee -a "$OUTPUT"
