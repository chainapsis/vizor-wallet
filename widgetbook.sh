#!/bin/bash
# Run the Zcash design-system Widgetbook.
#
# Usage:
#   ./widgetbook.sh            # macOS host, desktop tokens (default)
#   ./widgetbook.sh --mobile   # macOS host, mobile tokens
#
# --mobile adds --dart-define=VIZOR_FORM_FACTOR=mobile. Widgetbook is exempt
# from the main.dart form-factor/platform match check, so previewing the
# mobile token set on the desktop host is supported.
#
# Web (`-d chrome`) is NOT supported: the app pulls in dart:ffi (the Rust
# bridge) and 64-bit int literals (keccak256) that cannot compile to
# JavaScript, and the project has no web/ platform folder. Use --mobile on the
# macOS host and a Widgetbook device frame to preview mobile dimensions.
#
# Any other arguments are forwarded to `flutter run`
# (e.g. --release, -d <device>).

set -e

usage() {
  cat <<'EOF'
Run the Zcash design-system Widgetbook.

Usage:
  ./widgetbook.sh            macOS host, desktop tokens (default)
  ./widgetbook.sh --mobile   macOS host, mobile tokens

Flags:
  -m, --mobile   add --dart-define=VIZOR_FORM_FACTOR=mobile
  -h, --help     show this help

Any other arguments are forwarded to `flutter run` (e.g. --release, -d <device>).
Web (-d chrome) is unsupported — the app cannot compile to JavaScript.
EOF
}

DEFINE=()
DEVICE=()
EXTRA=()

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--mobile)
      DEFINE=(--dart-define=VIZOR_FORM_FACTOR=mobile)
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      EXTRA+=("$1")
      ;;
  esac
  shift
done

# Default to the macOS host unless the caller forwarded their own device.
case " ${EXTRA[*]} " in
  *" -d "*|*" --device-id "*) ;;
  *) DEVICE=(-d macos) ;;
esac

exec fvm flutter run -t lib/widgetbook.dart "${DEVICE[@]}" "${DEFINE[@]}" "${EXTRA[@]}"
