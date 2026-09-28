#!/usr/bin/env bash
set -euo pipefail
# Requires GTK 3 development files, g++, Xvfb, xauth, D-Bus, Openbox,
# xdotool, Weston (X11 backend), and Python 3. No wallet/Flutter engine runs.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_dir="$repo_root/linux/runner"
test_output="$(mktemp -d /tmp/vizor-caps-test.XXXXXX)"
read -r -a gtk_flags <<< "$(pkg-config --cflags --libs gtk+-3.0)"
"${CXX:-c++}" -std=c++14 -Wall -Werror \
  -I"$runner_dir/tests/stubs" -I"$runner_dir" \
  '-DAPPLICATION_ID="app.keplr.vizor.caps_test"' '-DAPP_DISPLAY_NAME="Vizor caps test"' \
  '-DAPP_ICON_NAME="app.keplr.vizor"' '-DAPP_ICON_THEME_PATH="/nonexistent"' \
  "$runner_dir/main.cc" "$runner_dir/my_application.cc" \
  "$runner_dir/single_instance.cc" "$runner_dir/caps_lock_channel.cc" \
  "$runner_dir/tests/flutter_stub.cc" -Wl,--wrap=gtk_dialog_run \
  "${gtk_flags[@]}" -o "$test_output/runner"
xvfb-run -a -s '-screen 0 1600x1000x24' dbus-run-session -- \
  python3 "$runner_dir/tests/test_caps_lock.py" "$test_output"
echo "Evidence: $test_output"
