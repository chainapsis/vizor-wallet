// ignore_for_file: depend_on_referenced_packages
// widgetbook is a dev-only dependency; this entry point is not part of the
// production app bundle.

import 'package:flutter/widgets.dart';

import 'src/core/layout/app_layout.dart';
import 'widgetbook/widgetbook_app.dart';

/// Widgetbook entry point.
///
/// Run with: `fvm flutter run -t lib/widgetbook.dart`.
///
/// On desktop, window_manager ships an NSWindow that starts hidden
/// (see `macos/Runner/MainFlutterWindow.swift` → `hiddenWindowAtLaunch()`),
/// so the Dart side must explicitly `show()` it. The production
/// `main.dart` does this via `initializeDesktopWindow()`; we reuse the
/// same helper here so the Widgetbook window lands at the same default
/// size as the real app. Skipping the acrylic + transparent
/// setup on purpose — Widgetbook doesn't need window effects, and the
/// opaque chrome is better for inspecting flat component previews.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    await showDesktopWindow();
  }
  runApp(
    GestureDetector(
      onTap: _unfocusPrimaryLeaf,
      behavior: HitTestBehavior.translucent,
      child: WidgetbookApp(),
    ),
  );
}

void _unfocusPrimaryLeaf() {
  // Leaf-only: skip when the primary focus is a `FocusScopeNode` rather than
  // a concrete `FocusNode`. Unfocusing the scope itself strips the scope's
  // "most-recently-focused child" memory, which leaves the next Tab with no
  // deterministic starting point.
  final primary = FocusManager.instance.primaryFocus;
  if (primary != null && primary is! FocusScopeNode) {
    primary.unfocus();
  }
}
