import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

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
  // `initializeDesktopWindow`; the acrylic setup is only effective once
  // that window exists.
  log('main: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    log('main: initializing flutter_acrylic + transparent effect');
    await _configureTransparentWindow();
    // `enableFullSizeContentView()` flips the NSWindow styleMask;
    // window_manager's setAspectRatio writes to `contentAspectRatio` vs
    // `aspectRatio` depending on that bit. Re-pin constraints now so they
    // land on the post-flip property and the resize / AppLayoutNotifier
    // reconciliation behaves correctly.
    await reapplyDesktopWindowConstraints();
  }
  log('main: launching app');
  runApp(const ProviderScope(child: ZcashWalletApp()));
}

/// Wire the native window for the acrylic blur effect.
///
/// On macOS, we talk to `WindowManipulator` directly rather than through
/// `flutter_acrylic`'s `Window.*` helpers. flutter_acrylic 1.1.4's macOS
/// wrappers fire-and-forget the underlying platform-channel futures
/// (e.g. `Window.setEffect(...)` synchronously returns before
/// `WindowManipulator.setMaterial` finishes natively), so the `await`s
/// in our setup do not actually serialize the calls. Driving
/// `WindowManipulator` directly gives us real awaited barriers, which
/// the follow-up `reapplyDesktopWindowConstraints()` depends on to see
/// the post-`enableFullSizeContentView` styleMask.
///
/// Windows and Linux still go through `Window.setEffect` — that path
/// already awaits its single method-channel call correctly.
Future<void> _configureTransparentWindow() async {
  if (Platform.isMacOS) {
    await WindowManipulator.initialize();
  } else {
    await Window.initialize();
  }
  await _applyDesktopAcrylic();
  if (Platform.isMacOS) {
    // Grey out the green (zoom) traffic-light so clicking it is a no-op
    // visually. macOS fullscreen still has a few other entry points
    // (View menu, Cmd+Ctrl+F, title-bar double-click in some
    // preferences), so the fullscreen event-channel toggle below stays
    // as a defensive safety net against those paths.
    await WindowManipulator.disableZoomButton();
    // macOS-only: subscribe to `willEnter` / `willExit` fullscreen events
    // pushed from native Swift via an event channel. We avoid
    // `WindowManipulator.addNSWindowDelegate` here because it would
    // clobber `window_manager`'s own NSWindow.delegate, breaking
    // `AppLayoutNotifier`'s resize / fullscreen reconciliation. On
    // Windows and Linux the desktop wallpaper stays behind a fullscreen
    // window, so the acrylic blur keeps working and no toggle is needed.
    _installMacOSFullscreenEffectToggle();
  }
}

/// Apply the per-platform acrylic / transparent setup. Idempotent, so the
/// fullscreen-leave listener below can call it to re-apply the effect
/// after temporarily disabling it for fullscreen.
///
/// macOS: `WindowEffect.acrylic` in flutter_acrylic maps to the
/// `NSVisualEffectViewMaterial.fullScreenUI` material per the package's
/// own converter; the `MacOSBlurViewState.active` enum maps to
/// `NSVisualEffectViewState.active`.
Future<void> _applyDesktopAcrylic() async {
  if (Platform.isMacOS) {
    // Clear the NSWindow background and fold the Flutter content into the
    // title strip so the acrylic material applies to one continuous
    // surface. Traffic-light controls stay visible and draggable.
    await WindowManipulator.setWindowBackgroundColorToClear();
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.enableFullSizeContentView();
    await WindowManipulator.setMaterial(
      NSVisualEffectViewMaterial.fullScreenUI,
    );
    // Pin the NSVisualEffectView to the active state so the material
    // doesn't desaturate when the window loses focus. Default is
    // `followsWindowActiveState`.
    await WindowManipulator.setNSVisualEffectViewState(
      NSVisualEffectViewState.active,
    );
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
/// Dropping the material to `windowBackground` (flutter_acrylic's
/// `WindowEffect.disabled`) is not enough on its own: our startup path
/// cleared the NSWindow background, so the Space backdrop would still
/// bleed through. Resetting the window background to the default opaque
/// color alongside the material flip makes the window solid throughout
/// the transition; on exit we re-clear the background and re-apply the
/// acrylic recipe.
void _installMacOSFullscreenEffectToggle() {
  const channel = EventChannel('app.zcash/fullscreen_events');
  channel.receiveBroadcastStream().listen((event) async {
    if (event == 'willEnter') {
      await WindowManipulator.setWindowBackgroundColorToDefaultColor();
      await WindowManipulator.setMaterial(
        NSVisualEffectViewMaterial.windowBackground,
      );
    } else if (event == 'willExit') {
      await _applyDesktopAcrylic();
    }
  });
}
