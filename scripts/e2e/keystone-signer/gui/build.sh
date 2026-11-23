#!/usr/bin/env bash
set -euo pipefail

# build.sh for the stock signer has already checked the revision and built Rust.
out="${1:?supply a new simulator output directory}"
mkdir "$out"
firmware="${KEYSTONE_FIRMWARE_DIR:-$HOME/keplr-workspace/refs/keystone3-signer-check}"
here="$(cd "$(dirname "$0")" && pwd)"
src="$(mktemp -d "$HOME/keplr-workspace/refs/keystone-gui.XXXXXX")"
trap 'rm -rf "$src"' EXIT
git clone --quiet --local "$firmware" "$src"
git -C "$src" submodule update --init --depth 1 external/ctaes
git -C "$src" apply "$here/simulator.patch"
lib="$src/ui_simulator/lib/rust-builds"
mkdir -p "$lib"
ln -s "$firmware/rust/target/release/librust_c.a" "$lib/"
cp "$firmware/rust/rust_c/bindings/simulator-cypherpunk/librust_c.h" "$lib/"
cmake -S "$src" -B "$src/build" -DBUILD_TYPE=Simulator -DCYPHERPUNK=ON \
  -DCMAKE_BUILD_TYPE=Debug -DVIZOR_GUI_DRIVER="$here/driver.m"
cmake --build "$src/build" --target simulator --parallel 8
mkdir -p "$out/ui_simulator/assets/sd"
cp "$src/build/simulator" "$out/simulator"
(cd "$out" && ./simulator --provision)
