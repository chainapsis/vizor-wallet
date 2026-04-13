import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/core/layout/app_layout.dart';
import 'src/rust/frb_generated.dart';

void log(String message) => debugPrint('[zcash] $message');

Future<void> main() async {
  log('main: starting');
  WidgetsFlutterBinding.ensureInitialized();
  log('main: initializing RustLib');
  await RustLib.init();
  // Order matters: window_manager creates and shows the NSWindow inside
  // `initializeDesktopWindow`; flutter_acrylic / macos_window_utils calls
  // (setEffect, setWindowBackgroundColorToClear, …) are only effective
  // once that window exists.
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    log('main: initializing flutter_acrylic + transparent effect');
    await _configureTransparentWindow();
    // flutter_acrylic's `enableFullSizeContentView()` flips the NSWindow
    // styleMask; window_manager's setAspectRatio writes to
    // `contentAspectRatio` vs `aspectRatio` depending on that bit. Re-pin
    // constraints now so they land on the post-flip property and the
    // resize / AppLayoutNotifier reconciliation behaves correctly.
    await reapplyDesktopWindowConstraints();
  }
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}

/// Wire the native window for the acrylic blur effect using
/// flutter_acrylic's own APIs. Acrylic is a frosted-glass blur that lets
/// the desktop behind show through with a tinted blur. Windows / macOS
/// support it natively; Linux has no matching material so it falls back
/// to plain transparent. Per-platform recipe lifted from the
/// flutter_acrylic example and README.
Future<void> _configureTransparentWindow() async {
  await Window.initialize();
  await _applyDesktopAcrylic();
  // macOS-only: subscribe to `willEnter` / `willExit` fullscreen events
  // pushed from native Swift via an event channel. We avoid
  // `WindowManipulator.addNSWindowDelegate` here because it would clobber
  // `window_manager`'s own NSWindow.delegate, breaking
  // `AppLayoutNotifier`'s resize / fullscreen reconciliation. On Windows
  // and Linux the desktop wallpaper stays behind a fullscreen window, so
  // the acrylic blur keeps working and no toggle is needed.
  if (Platform.isMacOS) {
    _installMacOSFullscreenEffectToggle();
  }
}

/// Apply the per-platform acrylic / transparent setup. Idempotent, so the
/// fullscreen-leave listener below can call it to re-apply the effect
/// after temporarily disabling it for fullscreen.
Future<void> _applyDesktopAcrylic() async {
  if (Platform.isMacOS) {
    // Clear the NSWindow background and fold the Flutter content into the
    // title strip so the acrylic material applies to one continuous
    // surface. Traffic-light controls stay visible and draggable.
    await Window.setWindowBackgroundColorToClear();
    await Window.makeTitlebarTransparent();
    await Window.enableFullSizeContentView();
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      color: Colors.transparent,
    );
    // Pin the NSVisualEffectView to the active state so the material
    // doesn't desaturate when the window loses focus. Default is
    // `followsWindowActiveState`.
    await Window.setBlurViewState(MacOSBlurViewState.active);
  } else if (Platform.isWindows) {
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      // Acrylic needs a tint color to blend with the blur result. Matches
      // the flutter_acrylic example's dark preset.
      color: const Color(0xCC222222),
      dark: true,
    );
  } else {
    // Linux — acrylic is not available; transparent is the closest thing
    // the plugin exposes there.
    await Window.setEffect(effect: WindowEffect.transparent);
  }
}

/// Subscribes to the native fullscreen notification stream set up in
/// `macos/Runner/MainFlutterWindow.swift`. The Swift side observes
/// `NSWindow.willEnterFullScreenNotification` /
/// `willExitFullScreenNotification` via `NotificationCenter` — that path
/// does not touch the NSWindow.delegate slot, so it coexists cleanly
/// with `window_manager`.
///
/// Dropping the material to `disabled` is not enough on its own: our
/// startup path called `setWindowBackgroundColorToClear`, so the NSWindow
/// is still transparent and the Space backdrop bleeds through even after
/// the material change. Resetting the window background to the default
/// opaque color alongside the material flip makes the window solid
/// throughout the transition; on exit we re-clear the background and
/// re-apply the acrylic recipe.
void _installMacOSFullscreenEffectToggle() {
  const channel = EventChannel('app.zcash/fullscreen_events');
  channel.receiveBroadcastStream().listen((event) {
    if (event == 'willEnter') {
      Window.setWindowBackgroundColorToDefaultColor();
      Window.setEffect(effect: WindowEffect.disabled);
    } else if (event == 'willExit') {
      _applyDesktopAcrylic();
    }
  });
}
