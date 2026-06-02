#!/bin/bash
# Clear the Vizor app from iOS simulator (including keychain data)

BUNDLE_ID="com.keplr.vizor"

DEVICE=$(xcrun simctl list devices booted -j | python3 -c "import sys,json; ds=[d for r in json.load(sys.stdin)['devices'].values() for d in r if d['state']=='Booted']; print(ds[0]['udid'] if ds else '')")

if [ -z "$DEVICE" ]; then
  echo "No booted iOS simulator found"
  exit 1
fi

echo "Device: $DEVICE"
xcrun simctl keychain "$DEVICE" reset
xcrun simctl privacy "$DEVICE" reset all "$BUNDLE_ID"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" 2>/dev/null
echo "App cleared (keychain + state + uninstall)"
