#!/usr/bin/env bash
set -euo pipefail

# Native Linux dependencies: a C++14 compiler, pkg-config, libgtk-3-dev,
# dbus-run-session, Xvfb/xvfb-run, xauth, openbox, xdotool, and Python 3.
if [[ "$(uname -s)" != Linux ]]; then
  echo 'Run this native test on Linux or inside a Linux container.' >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_dir="$repo_root/linux/runner"
output_parent="${VIZOR_SINGLE_INSTANCE_TEST_OUTPUT:-/tmp}"
mkdir -p "$output_parent"
test_output="$(mktemp -d "$output_parent/vizor-instance-test.XXXXXX")"
read -r -a gtk_flags <<< "$(pkg-config --cflags --libs gtk+-3.0)"

"${CXX:-c++}" -std=c++14 -Wall -Werror \
  -I"$runner_dir" "$runner_dir/single_instance.cc" \
  "$runner_dir/tests/guard_probe.cc" "${gtk_flags[@]}" \
  -o "$test_output/guard-probe"

for flavor in main testnet; do
  app_id=app.keplr.vizor
  binary=runner
  if [[ "$flavor" == testnet ]]; then
    app_id=app.keplr.vizor.testnet
    binary=runner-testnet
  fi
  "${CXX:-c++}" -std=c++14 -Wall -Werror \
    -I"$runner_dir/tests/stubs" -I"$runner_dir" \
    "-DAPPLICATION_ID=\"$app_id\"" '-DAPP_DISPLAY_NAME="Vizor"' \
    "-DAPP_ICON_NAME=\"$app_id\"" '-DAPP_ICON_THEME_PATH="/nonexistent"' \
    "$runner_dir/main.cc" "$runner_dir/my_application.cc" \
    "$runner_dir/single_instance.cc" "$runner_dir/tests/flutter_stub.cc" \
    -Wl,--wrap=gtk_dialog_run "${gtk_flags[@]}" -o "$test_output/$binary"
done

# Each run owns a display and D-Bus session, and opens no production wallet.
# Error dialogs are closed through GtkDialog responses in the test fixture.
# Xvfb/dbus-run-session clean up their own private session on completion.
xvfb-run -a -s '-screen 0 1280x800x24' dbus-run-session -- \
  bash -c 'openbox > "$1/openbox.log" 2>&1 &
    python3 "$2/tests/test_single_instance.py" "$1"' \
  bash "$test_output" "$runner_dir"
echo "Evidence: $test_output"
