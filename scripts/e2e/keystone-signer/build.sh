#!/usr/bin/env bash
set -euo pipefail
out="${1:?supply a simulator output directory}"
mode="${2:?supply stock or regtest}"
here="$(cd "$(dirname "$0")" && pwd)"
case "$mode" in
  stock|regtest) ;;
  *) echo "usage: $0 simulator-directory stock|regtest" >&2; exit 2 ;;
esac
firmware="${KEYSTONE_FIRMWARE_DIR:-$HOME/keplr-workspace/refs/keystone3-signer-check}"
revision=f74496eedd0978a0de5c43fefd8291b201674e8e
if [[ ! -e "$firmware" ]]; then
  mkdir -p "$(dirname "$firmware")"
  git clone --depth 1 --branch 3.2.2 https://github.com/KeystoneHQ/keystone3-firmware.git "$firmware"
fi
firmware="$(CDPATH= cd -- "$firmware" && pwd)"
if [[ "$(git -C "$firmware" rev-parse HEAD)" != "$revision" ]] ||
   [[ -n "$(git -C "$firmware" status --porcelain --untracked-files=no)" ]]; then
  echo "Expected a clean Keystone 3.2.2 checkout at $firmware" >&2
  exit 1
fi
rust_firmware="$firmware"
set --
# Keep the production checkout pristine and build only the host simulator.
scratch="$(mktemp -d "$(dirname "$firmware")/keystone-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
git clone --quiet --local --no-checkout "$firmware" "$scratch/firmware"
firmware="$scratch/firmware"
git -C "$firmware" checkout --quiet --detach "$revision"
if [[ "$mode" == regtest ]]; then
  git -C "$firmware" apply "$here/regtest.patch"
  rust_firmware="$firmware"
  set -- -DKEYSTONE_ZEBRA_REGTEST
fi
if [[ -n "${KEYSTONE_IOS_SIMULATOR_UDID:-}" ]]; then
  git -C "$firmware" apply "$here/gui/ios-camera.patch"
  rust_firmware="$firmware"
fi
# Keep the firmware archive separate from the wallet fixture's Cargo target.
(cd "$rust_firmware/rust" && CARGO_TARGET_DIR=target cargo build --locked --release -p rust_c --no-default-features --features simulator-cypherpunk)
cc "$@" -Wall -Wextra -Werror -I"$rust_firmware/rust/rust_c/bindings/simulator-cypherpunk" \
  "$here/export_account.c" "$rust_firmware/rust/target/release/librust_c.a" \
  -framework CoreFoundation -framework CoreGraphics -framework Security -framework SystemConfiguration \
  -lresolv -o "$scratch/export-account"
"$here/gui/build.sh" "$out" "$firmware" "$rust_firmware/rust"
"$scratch/export-account" > "$out/account.ur"
