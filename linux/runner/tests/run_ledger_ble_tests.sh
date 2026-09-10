#!/usr/bin/env zsh
# Builds and runs the Linux Ledger BLE tests on Linux or macOS. Needs glib,
# gio and dbus-daemon (Homebrew: glib, dbus) and the Flutter engine sources
# that ship with the SDK (fvm/flutter >= 3.38 keeps them under engine/src).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

FLUTTER_ROOT=${FLUTTER_ROOT:-$(fvm flutter --version --machine 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["flutterRoot"])')}
ENGINE="$FLUTTER_ROOT/engine/src"
LINUX="$ENGINE/flutter/shell/platform/linux"
[[ -f "$LINUX/fl_value.cc" ]] || { echo "Flutter engine sources not found under $ENGINE" >&2; exit 1; }

if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gio-2.0 gmodule-2.0; then
  GLIB_CFLAGS=("${(@f)$(pkg-config --cflags gio-2.0 gmodule-2.0 | tr ' ' '\n')}")
  GLIB_LIBS=("${(@f)$(pkg-config --libs gio-2.0 gmodule-2.0 | tr ' ' '\n')}")
else
  GLIB=$(brew --prefix glib)
  GLIB_CFLAGS=(-I"$GLIB/include/glib-2.0" -I"$GLIB/lib/glib-2.0/include" -I"$(brew --prefix gettext)/include" -I"$(brew --prefix pcre2)/include")
  GLIB_LIBS=(-L"$GLIB/lib" -L"$(brew --prefix gettext)/lib" -lgio-2.0 -lgobject-2.0 -lgmodule-2.0 -lglib-2.0 -lintl)
fi

OUT=${TMPDIR:-/tmp}/vizor-ledger-ble-tests
mkdir -p "$OUT"
CXX=${CXX:-c++}
COMMON=(-std=c++17 -pthread "${GLIB_CFLAGS[@]}")

echo "== transport test"
"$CXX" "${COMMON[@]}" -Wall -Wextra -Werror \
  linux/runner/tests/ledger_bluez_transport_test.cc linux/runner/ledger_bluez_transport.cc \
  "${GLIB_LIBS[@]}" -o "$OUT/transport"
"$OUT/transport"

echo "== handler test"
ENGINE_SOURCES=(fl_value fl_message_codec fl_method_call fl_method_response fl_method_codec fl_standard_message_codec fl_standard_method_codec fl_method_channel fl_event_channel)
OBJECTS=()
for name in "${ENGINE_SOURCES[@]}"; do
  "$CXX" "${COMMON[@]}" -w -DFLUTTER_LINUX_COMPILATION -I"$ENGINE" -c "$LINUX/$name.cc" -o "$OUT/$name.o"
  OBJECTS+=("$OUT/$name.o")
done
"$CXX" "${COMMON[@]}" -Wall -Wextra -Werror -Ilinux/runner/tests/channel_shim -I"$ENGINE" \
  linux/runner/tests/ledger_ble_handler_test.cc linux/runner/tests/test_binary_messenger.cc \
  linux/runner/ledger_ble_handler.cc linux/runner/ledger_bluez_transport.cc \
  "${OBJECTS[@]}" "${GLIB_LIBS[@]}" -o "$OUT/handler"
"$OUT/handler"
