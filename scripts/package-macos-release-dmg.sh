#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Vizor"
VOLUME_NAME="Install Vizor Wallet"
BACKGROUND_PATH="$ROOT_DIR/macos/Packaging/DMG/background@2x.png"
APP_PATH=""
DMG_PATH=""

WINDOW_WIDTH=600
WINDOW_HEIGHT=400
WINDOW_LEFT=160
WINDOW_TOP=120
ICON_SIZE=80

# Coordinates are content-area centers, matching the Figma installer node.
APP_ICON_X=133
APP_ICON_Y=235
APPLICATIONS_ICON_X=462
APPLICATIONS_ICON_Y=235

usage() {
  cat <<USAGE
Usage: scripts/package-macos-release-dmg.sh \\
  --app-path <path/to/Vizor.app> \\
  --output <path/to/Vizor-x.y.z-macos.dmg> \\
  [--app-name Vizor] \\
  [--volume-name "Install Vizor Wallet"] \\
  [--background macos/Packaging/DMG/background@2x.png]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      DMG_PATH="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    --background)
      BACKGROUND_PATH="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$DMG_PATH" ]]; then
  echo "--app-path and --output are required" >&2
  usage >&2
  exit 2
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
DMG_DIR="$(dirname "$DMG_PATH")"
mkdir -p "$DMG_DIR"
DMG_PATH="$(cd "$DMG_DIR" && pwd)/$(basename "$DMG_PATH")"
BACKGROUND_PATH="$(cd "$(dirname "$BACKGROUND_PATH")" && pwd)/$(basename "$BACKGROUND_PATH")"
BACKGROUND_FILE="$(basename "$BACKGROUND_PATH")"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle at $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  echo "Missing DMG background: $BACKGROUND_PATH" >&2
  exit 1
fi

rm -f "$DMG_PATH"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vizor-release-dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
RW_DMG="$WORK_DIR/${APP_NAME}-rw.dmg"
MOUNT_DIR="$WORK_DIR/mount"
ATTACH_PLIST="$WORK_DIR/attach.plist"
DEVICE=""
VERIFY_DEVICE=""

cleanup() {
  if [[ -n "$VERIFY_DEVICE" ]]; then
    hdiutil detach "$VERIFY_DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/.background" "$MOUNT_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$BACKGROUND_PATH" "$STAGING_DIR/.background/$BACKGROUND_FILE"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -plist > "$ATTACH_PLIST"

for index in {0..20}; do
  MOUNT_DIR="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$ATTACH_PLIST" 2>/dev/null || true)"
  if [[ -n "$MOUNT_DIR" ]]; then
    DEVICE="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:dev-entry" "$ATTACH_PLIST")"
    break
  fi
done

if [[ -z "$DEVICE" || -z "$MOUNT_DIR" ]]; then
  echo "Failed to mount temporary DMG" >&2
  exit 1
fi

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_DIR" as alias

  open dmgFolder
  delay 1

  tell folder dmgFolder
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $((WINDOW_LEFT + WINDOW_WIDTH)), $((WINDOW_TOP + WINDOW_HEIGHT))}

    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set background picture of viewOptions to file ".background:$BACKGROUND_FILE"

    set position of item "$APP_NAME.app" to {$APP_ICON_X, $APP_ICON_Y}
    set position of item "Applications" to {$APPLICATIONS_ICON_X, $APPLICATIONS_ICON_Y}

    update without registering applications
    delay 2
    close container window
  end tell
end tell
APPLESCRIPT

find "$MOUNT_DIR" -mindepth 1 -maxdepth 1 -name '.*' \
  ! -name '.DS_Store' \
  ! -name '.background' \
  -exec rm -rf {} +

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_PATH" >/dev/null

image_info="$(hdiutil imageinfo "$DMG_PATH")"
if [[ "$image_info" != *"Format: UDZO"* ]]; then
  echo "Expected UDZO disk image format" >&2
  exit 1
fi

if [[ "$image_info" != *"partition-hint: Apple_HFS"* ]]; then
  echo "Expected Apple_HFS filesystem in DMG" >&2
  exit 1
fi

VERIFY_MOUNT_DIR="$WORK_DIR/verify-mount"
VERIFY_PLIST="$WORK_DIR/verify-attach.plist"
mkdir -p "$VERIFY_MOUNT_DIR"
hdiutil attach "$DMG_PATH" -readonly -noverify -noautoopen -mountpoint "$VERIFY_MOUNT_DIR" -plist > "$VERIFY_PLIST"

for index in {0..20}; do
  verify_mount="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$VERIFY_PLIST" 2>/dev/null || true)"
  if [[ -n "$verify_mount" ]]; then
    VERIFY_DEVICE="$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:dev-entry" "$VERIFY_PLIST")"
    break
  fi
done

if [[ -z "$VERIFY_DEVICE" ]]; then
  echo "Failed to mount final DMG for verification" >&2
  exit 1
fi

if [[ ! -d "$VERIFY_MOUNT_DIR/$APP_NAME.app" ]]; then
  echo "Final DMG is missing $APP_NAME.app" >&2
  exit 1
fi

if [[ "$(readlink "$VERIFY_MOUNT_DIR/Applications")" != "/Applications" ]]; then
  echo "Final DMG is missing Applications symlink" >&2
  exit 1
fi

if [[ ! -f "$VERIFY_MOUNT_DIR/.background/$BACKGROUND_FILE" ]]; then
  echo "Final DMG is missing background asset" >&2
  exit 1
fi

while IFS= read -r hidden_entry; do
  hidden_name="$(basename "$hidden_entry")"
  case "$hidden_name" in
    .DS_Store|.background)
      ;;
    *)
      echo "Unexpected top-level hidden entry in final DMG: $hidden_name" >&2
      exit 1
      ;;
  esac
done < <(find "$VERIFY_MOUNT_DIR" -mindepth 1 -maxdepth 1 -name '.*' -print | sort)

hdiutil detach "$VERIFY_DEVICE" -quiet
VERIFY_DEVICE=""

echo "Created $DMG_PATH"
