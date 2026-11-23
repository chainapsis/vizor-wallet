#!/usr/bin/env bash
set -euo pipefail
out="${1:?supply an output binary path}"
mode="${2:-stock}"
case "$mode" in
  stock|--regtest) ;;
  *) echo "usage: $0 output-path [--regtest]" >&2; exit 2 ;;
esac
firmware="${KEYSTONE_FIRMWARE_DIR:-$HOME/keplr-workspace/refs/keystone3-signer-check}"
revision=f74496eedd0978a0de5c43fefd8291b201674e8e
if [[ ! -e "$firmware" ]]; then
  mkdir -p "$(dirname "$firmware")"
  git clone --depth 1 --branch 3.2.2 https://github.com/KeystoneHQ/keystone3-firmware.git "$firmware"
fi
if [[ "$(git -C "$firmware" rev-parse HEAD)" != "$revision" ]] ||
   [[ -n "$(git -C "$firmware" status --porcelain --untracked-files=no)" ]]; then
  echo "Expected a clean Keystone 3.2.2 checkout at $firmware" >&2
  exit 1
fi
set --
if [[ "$mode" == --regtest ]]; then
  # Keep the production checkout pristine and build only the host simulator.
  scratch="$(mktemp -d "$HOME/keplr-workspace/refs/keystone-regtest.XXXXXX")"
  trap 'rm -rf "$scratch"' EXIT
  git clone --quiet --local --no-checkout "$firmware" "$scratch/firmware"
  firmware="$scratch/firmware"
  git -C "$firmware" checkout --quiet --detach "$revision"
  git -C "$firmware" apply - < "$(dirname "$0")/regtest.patch"
  set -- -DKEYSTONE_ZEBRA_REGTEST
fi
# Keep the firmware archive separate from the wallet fixture's Cargo target.
(cd "$firmware/rust" && CARGO_TARGET_DIR=target cargo build --locked --release -p rust_c --no-default-features --features simulator-cypherpunk)
cc "$@" -Wall -Wextra -Werror -I"$firmware/rust/rust_c/bindings/simulator-cypherpunk" \
  "$(dirname "$0")/signer.c" "$firmware/rust/target/release/librust_c.a" \
  -framework CoreFoundation -framework CoreGraphics -framework Security -framework SystemConfiguration \
  -lresolv -o "$out"
