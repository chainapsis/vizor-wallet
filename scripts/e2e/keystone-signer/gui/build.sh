#!/usr/bin/env bash
set -euo pipefail

# The caller owns this disposable firmware checkout and its matching Rust archive.
out="${1:?supply a new simulator output directory}"
src="${2:?supply an isolated firmware checkout}"
rust="${3:?supply the compiled firmware Rust directory}"
mkdir "$out"
here="$(cd "$(dirname "$0")" && pwd)"
git -C "$src" submodule update --init --depth 1 external/ctaes
git -C "$src" apply "$here/simulator.patch"
lib="$src/ui_simulator/lib/rust-builds"
mkdir -p "$lib"
ln -s "$rust/target/release/librust_c.a" "$lib/"
cp "$rust/rust_c/bindings/simulator-cypherpunk/librust_c.h" "$lib/"
cmake -S "$src" -B "$src/build" -DBUILD_TYPE=Simulator -DCYPHERPUNK=ON \
  -DCMAKE_BUILD_TYPE=Debug -DVIZOR_GUI_DRIVER="$here/driver.m"
cmake --build "$src/build" --target simulator --parallel 8
mkdir -p "$out/ui_simulator/assets/sd"
cp "$src/build/simulator" "$out/simulator"
(cd "$out" && ./simulator --provision)
