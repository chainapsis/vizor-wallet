#!/bin/bash
# Run the Zcash design-system Widgetbook.
# Forwards any extra args to `flutter run` (e.g. `-d chrome`, `--release`).

set -e
exec fvm flutter run -t lib/widgetbook.dart "$@"
