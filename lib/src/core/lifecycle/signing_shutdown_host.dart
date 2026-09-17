import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Normal exit is a best-effort optimization. Rust's startup recovery also
/// handles forced termination, so a slow DB must never trap the user on exit.
class SigningShutdownCoordinator {
  SigningShutdownCoordinator({
    required this.releaseReservations,
    this.timeout = const Duration(seconds: 2),
    this.onError,
  });

  final Future<void> Function() releaseReservations;
  final Duration timeout;
  final void Function(Object, StackTrace)? onError;
  Future<void>? _pending;

  Future<void> prepareExit() => _pending ??= _prepareExit();

  Future<void> _prepareExit() async {
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

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.coordinator.prepareExit();
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
      await widget.coordinator.prepareExit();
      await windowManager.destroy();
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
