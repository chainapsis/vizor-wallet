#!/usr/bin/env bash
# Real Rust/SQLite and encryption with disposable wallet data and fake OS storage.
set -euo pipefail
setup_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
setup_mobile=false
if [[ "${1:-}" == '--mobile' ]]; then
  setup_mobile=true
  shift
fi
cd "$setup_project_root/rust"
cargo build --lib
setup_target_dir="$(cargo metadata --no-deps --format-version 1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_directory"])')"
case "$(uname -s)" in
  Darwin) setup_library="$setup_target_dir/debug/librust_lib_zcash_wallet.dylib" ;;
  Linux) setup_library="$setup_target_dir/debug/librust_lib_zcash_wallet.so" ;;
  MINGW*|MSYS*|CYGWIN*) setup_library="$setup_target_dir/debug/rust_lib_zcash_wallet.dll" ;;
  *) echo 'Unsupported native test host.' >&2; exit 1 ;;
esac
cd "$setup_project_root"
setup_args=(--no-pub "--dart-define=VIZOR_RECOVERY_NATIVE_LIBRARY=$setup_library")
if "$setup_mobile"; then
  setup_args+=(--dart-define=VIZOR_FORM_FACTOR=mobile --tags mobile --run-skipped test/features/onboarding/mobile_wallet_setup_native_test.dart)
else
  setup_args+=(test/core/storage/wallet_setup_native_test.dart)
fi
fvm flutter test "${setup_args[@]}" "$@"
