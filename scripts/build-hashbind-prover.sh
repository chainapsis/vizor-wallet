#!/usr/bin/env bash
# Builds native/hashbind_prover into VizorHashbindProver.xcframework for the
# Apple platforms the app ships (iOS device, iOS simulator, macOS), so the
# zwap b2z/z2b hashbind proof is generated ON DEVICE.
#
# Output: native/hashbind_prover/apple/VizorHashbindProver.xcframework
# (gitignored — prebuilt binaries stay out of the repo). Run this once per
# checkout (and after bumping the provekit rev), then `pod install` in ios/
# and macos/. Requires the nightly toolchain pinned in
# native/hashbind_prover/rust-toolchain.toml (rustup installs it on demand).
#
# Android (aarch64-linux-android) is a follow-up: the crate builds for it,
# but packaging needs an NDK toolchain — see native/hashbind_prover/README.md.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/native/hashbind_prover"
OUT="$CRATE/apple"
NAME="VizorHashbindProver"
LIB="libvizor_hashbind_prover.dylib"
PROFILE="release-mobile"
TOOLCHAIN="$(sed -n 's/^channel = "\(.*\)"/\1/p' "$CRATE/rust-toolchain.toml")"

IOS_TARGET="aarch64-apple-ios"
SIM_TARGETS=("aarch64-apple-ios-sim")
MAC_TARGETS=("aarch64-apple-darwin" "x86_64-apple-darwin")

echo "==> toolchain $TOOLCHAIN"
for t in "$IOS_TARGET" "${SIM_TARGETS[@]}" "${MAC_TARGETS[@]}"; do
  rustup target add --toolchain "$TOOLCHAIN" "$t" >/dev/null
done

build() { # target
  echo "==> cargo build --target $1 ($PROFILE)"
  (cd "$CRATE" && IPHONEOS_DEPLOYMENT_TARGET=15.0 MACOSX_DEPLOYMENT_TARGET=11.0 \
    cargo build --profile "$PROFILE" --target "$1")
}

for t in "$IOS_TARGET" "${SIM_TARGETS[@]}" "${MAC_TARGETS[@]}"; do build "$t"; done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
dylib() { echo "$CRATE/target/$1/$PROFILE/$LIB"; }

# iOS-style shallow framework (device + simulator slices).
make_ios_framework() { # dylib-path out-dir platform-name
  local fw="$2/$NAME.framework"
  mkdir -p "$fw/Headers" "$fw/Modules"
  cp "$1" "$fw/$NAME"
  install_name_tool -id "@rpath/$NAME.framework/$NAME" "$fw/$NAME"
  cp "$CRATE/include/vizor_hashbind.h" "$fw/Headers/"
  printf 'framework module %s {\n  header "vizor_hashbind.h"\n  export *\n}\n' "$NAME" \
    > "$fw/Modules/module.modulemap"
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>xyz.vizor.hashbindprover</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
PLIST
}

# macOS versioned framework bundle.
make_macos_framework() { # dylib-path out-dir
  local fw="$2/$NAME.framework"
  mkdir -p "$fw/Versions/A/Headers" "$fw/Versions/A/Modules" "$fw/Versions/A/Resources"
  cp "$1" "$fw/Versions/A/$NAME"
  install_name_tool -id "@rpath/$NAME.framework/Versions/A/$NAME" "$fw/Versions/A/$NAME"
  cp "$CRATE/include/vizor_hashbind.h" "$fw/Versions/A/Headers/"
  printf 'framework module %s {\n  header "vizor_hashbind.h"\n  export *\n}\n' "$NAME" \
    > "$fw/Versions/A/Modules/module.modulemap"
  cat > "$fw/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>xyz.vizor.hashbindprover</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
PLIST
  ln -s A "$fw/Versions/Current"
  ln -s Versions/Current/$NAME "$fw/$NAME"
  ln -s Versions/Current/Headers "$fw/Headers"
  ln -s Versions/Current/Modules "$fw/Modules"
  ln -s Versions/Current/Resources "$fw/Resources"
}

mkdir -p "$STAGE/ios" "$STAGE/sim" "$STAGE/macos"
make_ios_framework "$(dylib "$IOS_TARGET")" "$STAGE/ios" ios

SIM_DYLIB="$(dylib "${SIM_TARGETS[0]}")"
if [ "${#SIM_TARGETS[@]}" -gt 1 ]; then
  lipo -create $(for t in "${SIM_TARGETS[@]}"; do dylib "$t"; done) -output "$STAGE/sim-$LIB"
  SIM_DYLIB="$STAGE/sim-$LIB"
fi
make_ios_framework "$SIM_DYLIB" "$STAGE/sim" ios-simulator

lipo -create $(for t in "${MAC_TARGETS[@]}"; do dylib "$t"; done) -output "$STAGE/mac-$LIB"
make_macos_framework "$STAGE/mac-$LIB" "$STAGE/macos"

rm -rf "$OUT/$NAME.xcframework"
mkdir -p "$OUT"
xcodebuild -create-xcframework \
  -framework "$STAGE/ios/$NAME.framework" \
  -framework "$STAGE/sim/$NAME.framework" \
  -framework "$STAGE/macos/$NAME.framework" \
  -output "$OUT/$NAME.xcframework"

echo "ok: $OUT/$NAME.xcframework"
du -sh "$OUT/$NAME.xcframework"
echo "next: (cd ios && pod install) and (cd macos && pod install)"
