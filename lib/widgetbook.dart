// ignore_for_file: depend_on_referenced_packages
// widgetbook is a dev-only dependency; this entry point is not part of the
// production app bundle.

import 'package:flutter/widgets.dart';

import 'widgetbook/widgetbook_app.dart';

/// Widgetbook entry point.
///
/// Run with: `fvm flutter run -t lib/widgetbook.dart`.
void main() {
  runApp(const WidgetbookApp());
}
