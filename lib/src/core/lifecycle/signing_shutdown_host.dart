import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Normal exit is a best-effort optimization. Rust's startup recovery also
/// handles forced termination, so a slow DB must never trap the user on exit.
class SigningShutdownCoordinator {
  SigningShutdownCoordinator({
    required this.releaseReservations,
    this.timeout = const Duration(milliseconds: 300),
    this.onExitStarted,
    this.onError,
  });

  final Future<void> Function() releaseReservations;
  final Duration timeout;
  final VoidCallback? onExitStarted;
  final void Function(Object, StackTrace)? onError;
  Future<void>? _pending;

  Future<void> prepareExit() => _pending ??= _prepareExit();

  Future<void> _prepareExit() async {
    try {
      onExitStarted?.call();
    } catch (error, stack) {
      onError?.call(error, stack);
    }
    try {
      await releaseReservations().timeout(timeout);
    } catch (error, stack) {
      onError?.call(error, stack);
    }
  }
}

/// Mounted only by the production entrypoint, after Rust/window initialization.
/// Inactive/hidden lifecycle events deliberately do not end a signing session.
class SigningShutdownHost extends StatefulWidget {
  const SigningShutdownHost({
    required this.coordinator,
    required this.desktop,
    required this.child,
    super.key,
  });

  final SigningShutdownCoordinator coordinator;
  final bool desktop;
  final Widget child;

  @override
  State<SigningShutdownHost> createState() => _SigningShutdownHostState();
}

class _SigningShutdownHostState extends State<SigningShutdownHost>
    with WindowListener {
  late final AppLifecycleListener _lifecycle;
  bool _closingWindow = false;
  Future<void>? _exitPreparation;

  Future<void> _prepareExit() => _exitPreparation ??= _prepareExitOnce();

  Future<void> _hideWindowForExit() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      // Suppress last-window auto-quit while Flutter is awaiting this cleanup.
      // A second native terminate request can bypass Flutter's pending reply.
      return const MethodChannel(
        'com.zcash.wallet/desktop_exit',
      ).invokeMethod<void>('hideForExit');
    }
    return windowManager.hide();
  }

  Future<void> _prepareExitOnce() async {
    // Close the work gate synchronously, then hide and clean up concurrently.
    // A failed or stalled window method must not strand the process on exit.
    final cleanup = widget.coordinator.prepareExit();
    if (widget.desktop) {
      try {
        await _hideWindowForExit().timeout(widget.coordinator.timeout);
      } catch (error, stack) {
        widget.coordinator.onError?.call(error, stack);
      }
    }
    await cleanup;
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await _prepareExit();
        return AppExitResponse.exit;
      },
    );
    if (widget.desktop) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
  }

  @override
  void onWindowClose() {
    if (_closingWindow) return;
    _closingWindow = true;
    unawaited(() async {
      await _prepareExit();
      try {
        await windowManager.destroy();
      } catch (error, stack) {
        _closingWindow = false;
        widget.coordinator.onError?.call(error, stack);
        // Let the user retry closing if the native destroy request failed.
        try {
          await windowManager.show();
        } catch (error, stack) {
          widget.coordinator.onError?.call(error, stack);
        }
      }
    }());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (widget.desktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
