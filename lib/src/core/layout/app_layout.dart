import 'dart:io' show Platform;

import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_form_factor.dart';

export 'app_form_factor.dart';

const bool kE2eHiddenDesktopWindow = bool.fromEnvironment(
  'VIZOR_E2E_HIDDEN_WINDOW',
);
const _windowAppearanceChannel = MethodChannel(
  'com.zcash.wallet/window_appearance',
);

/// Two desktop window shapes the app can boot into or infer from the
/// current size.
///
/// - [large]: landscape default, 1080×720
/// - [small]: portrait default, 416×851
///
/// Mobile and web are permanently [small]. On desktop the OS window
/// starts at [defaultSize] with [minimumSize] as the drag-resize floor.
/// After launch, width and height resize independently — the window is
/// not locked to [aspectRatio].
enum AppLayoutMode {
  large,
  small;

  /// Width / height for this layout's default size. Used only to infer
  /// the current mode from an observed window; it is not enforced.
  double get aspectRatio {
    switch (this) {
      case AppLayoutMode.large:
        return 1080.0 / 720.0;
      case AppLayoutMode.small:
        return (50.0 * 1.3) / 133.0;
    }
  }

  /// Default window size applied at startup.
  Size get defaultSize {
    switch (this) {
      case AppLayoutMode.large:
        return const Size(1080, 720);
      case AppLayoutMode.small:
        return const Size(416, 851);
    }
  }

  /// Minimum allowed drag-resize size.
  ///
  /// Large-mode width is 75% of the 1080 Figma canvas so the window can
  /// sit closer to the 420px content column. Height stays at the design
  /// canvas (720).
  Size get minimumSize {
    switch (this) {
      case AppLayoutMode.large:
        return const Size(810, 720);
      case AppLayoutMode.small:
        return const Size(416, 851);
    }
  }
}

/// Decision boundary for inferring the current layout mode from the
/// window's width/height ratio — the midpoint between the two
/// configured aspect ratios. Above it the window is "landscape enough"
/// to imply [AppLayoutMode.large]; below it it's "portrait enough" to
/// imply [AppLayoutMode.small].
const double _largeRatioThreshold = (1080.0 / 720.0 + (50.0 * 1.3) / 133.0) / 2;
const double _windowsContentTopInset = 0.0;

/// Initialize the OS window for desktop at startup.
///
/// Must be called after `WidgetsFlutterBinding.ensureInitialized()` and
/// before `runApp`. No-op on mobile/web.
Future<void> initializeDesktopWindow({
  AppLayoutMode initialMode = AppLayoutMode.large,
}) async {
  if (!isDesktopLayoutPlatform) return;

  await windowManager.ensureInitialized();

  final options = Platform.isWindows
      ? WindowOptions(title: 'Vizor')
      : WindowOptions(
          size: initialMode.defaultSize,
          minimumSize: initialMode.minimumSize,
          center: true,
          title: 'Vizor',
        );

  await windowManager.waitUntilReadyToShow(options);
  if (Platform.isWindows) {
    await _applyWindowsClientAreaLayout(initialMode, center: true);
  } else {
    await windowManager.setMinimumSize(initialMode.minimumSize);
    // 0 clears any leftover ratio lock so drag-resize is free on both axes.
    await windowManager.setAspectRatio(0);
    await windowManager.setSize(initialMode.defaultSize, animate: false);
  }
}

/// Show and focus the desktop window after all native bootstrap steps finish.
Future<void> showDesktopWindow() async {
  if (!isDesktopLayoutPlatform) return;
  if (kE2eHiddenDesktopWindow) {
    // A fully transparent macOS window is treated as occluded and stops
    // receiving the frame callbacks that integration-test pumps await.
    await windowManager.setOpacity(0.001);
    await windowManager.setIgnoreMouseEvents(true);
    await windowManager.setAlwaysOnTop(true);
    if (Platform.isMacOS) {
      await _windowAppearanceChannel.invokeMethod<void>('showInactive');
    } else {
      await windowManager.show(inactive: true);
    }
    return;
  }
  await windowManager.show();
  await windowManager.focus();
}

@immutable
class AppLayoutState {
  final AppLayoutMode mode;
  const AppLayoutState(this.mode);
}

/// Riverpod notifier that owns the current layout mode.
///
/// Startup sizes the window once. After that, the user resizes freely;
/// [setMode] does not snap the window back to a default size. Window
/// listener events only infer [AppLayoutMode] from the observed ratio
/// so screens that still call [setMode] stay in sync without reshaping
/// the window.
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
    // Geometry is user-controlled after [initializeDesktopWindow]. Keep
    // the recorded mode in sync without resetting size or aspect ratio.
    state = AppLayoutState(mode);
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
      final size = Platform.isWindows
          ? await DesktopWindowBootstrap.getWindowsClientAreaSize()
          : await windowManager.getSize();
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

Future<void> _applyWindowsClientAreaLayout(
  AppLayoutMode mode, {
  bool resize = true,
  bool center = false,
}) async {
  await DesktopWindowBootstrap.applyWindowsClientAreaLayout(
    windowSize: mode.defaultSize,
    minimumWindowSize: mode.minimumSize,
    // Windows targets the redesigned content area directly. Its native frame is
    // added by the plugin after the Flutter client-area size is selected.
    contentTopInset: _windowsContentTopInset,
    enforceAspectRatio: false,
    resize: resize,
    center: center,
  );
}
