#!/usr/bin/env bash
# Exercise recovery through real Rust/SQLite and Flutter, with a disposable
# app-support directory and an in-memory OS-storage backend. No wallet network
# connections or installed app data are used.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root/rust"
cargo build --lib
recovery_target_dir="$(cargo metadata --no-deps --format-version 1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_directory"])')"
case "$(uname -s)" in
  Darwin) recovery_library="$recovery_target_dir/debug/librust_lib_zcash_wallet.dylib" ;;
  Linux) recovery_library="$recovery_target_dir/debug/librust_lib_zcash_wallet.so" ;;
  MINGW*|MSYS*|CYGWIN*) recovery_library="$recovery_target_dir/debug/rust_lib_zcash_wallet.dll" ;;
  *) echo 'Unsupported host. Pass VIZOR_RECOVERY_NATIVE_LIBRARY directly to flutter test.' >&2; exit 1 ;;
esac

cd "$project_root"
fvm flutter test --no-pub \
  --dart-define="VIZOR_RECOVERY_NATIVE_LIBRARY=$recovery_library" \
  test/core/storage/wallet_recovery_native_test.dart "$@"
