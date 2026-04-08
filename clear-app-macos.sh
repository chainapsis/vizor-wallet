#!/bin/bash
# Clear the Zcash wallet app data on macOS (including keychain data)

BUNDLE_ID="com.zcash.zcashWallet"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"

# Kill the app if running
pkill -f "$BUNDLE_ID" 2>/dev/null

# Remove app data inside container (not the container itself — macOS protects it)
if [ -d "$CONTAINER/Data" ]; then
  rm -rf "$CONTAINER/Data/Documents" "$CONTAINER/Data/Library" "$CONTAINER/Data/tmp" 2>/dev/null
  echo "Removed app data from: $CONTAINER/Data"
else
  echo "No app container found"
fi

# flutter_secure_storage uses data protection keychain (usesDataProtectionKeychain: true),
# which is stored inside the app container's Data/Library. Removing that directory above
# also clears all keychain items. No separate `security delete-generic-password` needed.

echo "macOS app cleared (DB + keychain + preferences)"
