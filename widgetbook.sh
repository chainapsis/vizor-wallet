#!/bin/bash
# Run the Zcash design-system Widgetbook.
# Defaults to `-d macos` when no args are given; otherwise forwards args
# through to `flutter run` (e.g. `-d chrome`, `--release`).

set -e

if [ $# -eq 0 ]; then
  exec fvm flutter run -t lib/widgetbook.dart -d macos
fi

exec fvm flutter run -t lib/widgetbook.dart "$@"
