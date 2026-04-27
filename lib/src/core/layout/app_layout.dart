import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Two fixed-aspect-ratio layouts the desktop app supports.
///
/// - [large]: landscape, width:height = 1080:720 (3:2 = 1.5, wider than tall)
/// - [small]: portrait,  width:height =  65:133  (≈ 0.489, taller than wide)
///
/// Mobile and web are permanently [small]. On desktop the OS window is
/// reshaped to the selected ratio and its aspect ratio is enforced for
/// user drag-resize.
enum AppLayoutMode {
  large,
  small;

  /// Width / height for this layout.
  double get aspectRatio {
    switch (this) {
      case AppLayoutMode.large:
        return 1080.0 / 720.0;
      case AppLayoutMode.small:
        return (50.0 * 1.3) / 133.0;
    }
  }

  /// Default window size applied at startup and on explicit toggle.
  Size get defaultSize {
    switch (this) {
      case AppLayoutMode.large:
        return const Size(1080, 720);
      case AppLayoutMode.small:
        return const Size(416, 851);
    }
  }

  /// Minimum allowed drag-resize size — prevents the window from
  /// collapsing below the design system's large desktop canvas.
  Size get minimumSize {
    switch (this) {
      case AppLayoutMode.large:
        return const Size(1080, 720);
      case AppLayoutMode.small:
        return const Size(416, 851);
    }
  }
}

/// True on the desktop platforms that `window_manager` supports and where
/// layout switching is meaningful.
bool get isDesktopLayoutPlatform {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// Decision boundary for inferring the current layout mode from the
/// window's width/height ratio — the midpoint between the two
/// configured aspect ratios. Above it the window is "landscape enough"
/// to imply [AppLayoutMode.large]; below it it's "portrait enough" to
/// imply [AppLayoutMode.small].
const double _largeRatioThreshold = (1080.0 / 720.0 + (50.0 * 1.3) / 133.0) / 2;

/// Initialize the OS window for desktop at startup.
///
/// Must be called after `WidgetsFlutterBinding.ensureInitialized()` and
/// before `runApp`. No-op on mobile/web.
Future<void> initializeDesktopWindow({
  AppLayoutMode initialMode = AppLayoutMode.large,
}) async {
  if (!isDesktopLayoutPlatform) return;

  await windowManager.ensureInitialized();

  final options = WindowOptions(
    size: initialMode.defaultSize,
    minimumSize: initialMode.minimumSize,
    center: true,
    title: 'Vizor',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setMinimumSize(initialMode.minimumSize);
    await windowManager.setAspectRatio(initialMode.aspectRatio);
    await windowManager.setSize(initialMode.defaultSize, animate: false);
  });
}

/// Show and focus the desktop window after all native bootstrap steps finish.
Future<void> showDesktopWindow() async {
  if (!isDesktopLayoutPlatform) return;
  await windowManager.show();
  await windowManager.focus();
}

/// Re-pin window_manager's per-mode constraints after another layer flips
/// the NSWindow styleMask.
///
/// The current startup path sets `.fullSizeContentView` natively before Dart
/// runs, so this helper is not needed during initial launch. It remains useful
/// for any future path that mutates the styleMask after window_manager has
/// already applied constraints.
///
/// `setMinimumSize` doesn't strictly need the re-issue (window_manager
/// writes `mainWindow.minSize` directly with no styleMask branch), but
/// it's grouped here as a cheap belt-and-suspenders that keeps the
/// "constraints" set conceptually atomic.
///
/// Pure constraint refresh — does NOT touch the window's current size,
/// so it is safe to call from any future styleMask-changing path
/// without snapping a user-resized window back to a default.
Future<void> reapplyDesktopWindowConstraints({
  AppLayoutMode mode = AppLayoutMode.large,
}) async {
  if (!isDesktopLayoutPlatform) return;
  await windowManager.setMinimumSize(mode.minimumSize);
  await windowManager.setAspectRatio(mode.aspectRatio);
}

@immutable
class AppLayoutState {
  final AppLayoutMode mode;
  const AppLayoutState(this.mode);
}

/// Riverpod notifier that owns the current layout mode and, on desktop,
/// drives the OS window to match.
///
/// Observes [WindowListener] events so that when the user breaks out of
/// the configured aspect-ratio constraint (macOS green-button zoom,
/// Windows maximize/snap, manual drag past the limit) — or restores
/// the window back to the other ratio's shape — the notifier infers
/// the current layout from the observed window ratio using a single
/// midpoint threshold.
///
/// The inference is idempotent, so the listener doesn't need a
/// re-entrancy guard against the notifier's own `setSize` events:
/// `setSize(large default)` → observed ratio ≈ 1.33 → infers large →
/// state was already large → no-op. `setSize(small default)` → observed
/// ratio ≈ 0.489 → infers small → state was already small → no-op.
class AppLayoutNotifier extends Notifier<AppLayoutState> with WindowListener {
  @override
  AppLayoutState build() {
    if (isDesktopLayoutPlatform) {
      windowManager.addListener(this);
      ref.onDispose(() => windowManager.removeListener(this));
    }
    // Mobile is fixed at `small`. Desktop boots in `large` to match
    // the initial window size applied by [initializeDesktopWindow].
    return AppLayoutState(
      isDesktopLayoutPlatform ? AppLayoutMode.large : AppLayoutMode.small,
    );
  }

  Future<void> setMode(AppLayoutMode mode) async {
    if (!isDesktopLayoutPlatform) return;
    if (state.mode == mode) return;
    state = AppLayoutState(mode);
    try {
      await windowManager.setMinimumSize(mode.minimumSize);
      await windowManager.setAspectRatio(mode.aspectRatio);
      await windowManager.setSize(mode.defaultSize, animate: false);
    } catch (e, st) {
      // On platform-call failure, log and fall back to the assumption
      // that the window is in [large]. The auto-switch listener will
      // subsequently correct this if the window is actually shaped
      // like small.
      debugPrint('AppLayoutNotifier.setMode($mode) failed: $e\n$st');
      state = const AppLayoutState(AppLayoutMode.large);
    }
  }

  Future<void> toggle() => setMode(
    state.mode == AppLayoutMode.large
        ? AppLayoutMode.small
        : AppLayoutMode.large,
  );

  @override
  void onWindowResize() => _reconcileLayoutWithWindow();

  @override
  void onWindowMaximize() => _reconcileLayoutWithWindow();

  @override
  void onWindowUnmaximize() => _reconcileLayoutWithWindow();

  @override
  void onWindowEnterFullScreen() => _reconcileLayoutWithWindow();

  @override
  void onWindowLeaveFullScreen() => _reconcileLayoutWithWindow();

  Future<void> _reconcileLayoutWithWindow() async {
    try {
      final size = await windowManager.getSize();
      if (size.height <= 0) return;
      final ratio = size.width / size.height;
      final inferred = ratio >= _largeRatioThreshold
          ? AppLayoutMode.large
          : AppLayoutMode.small;
      if (state.mode != inferred) {
        state = AppLayoutState(inferred);
      }
    } catch (e) {
      debugPrint('AppLayoutNotifier auto-reconcile failed: $e');
    }
  }
}

final appLayoutProvider = NotifierProvider<AppLayoutNotifier, AppLayoutState>(
  AppLayoutNotifier.new,
);
