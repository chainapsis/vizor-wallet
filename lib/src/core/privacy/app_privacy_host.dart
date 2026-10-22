import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Native lifecycle owners render the cover; Flutter only registers solid scopes.
/// This policy is independent of foreground capture exclusion.
abstract final class AppPrivacyPolicy {
  static const _channel = MethodChannel('com.zcash.wallet/app_privacy');
  static final _solidScopes = <Object>{};
  static final _hosts = <Object>{};
  static bool _ready = false;
  static bool? _lastSent;
  static int? _pendingFrame;
  static int _epoch = 0;
  static bool _downgradeScheduled = false;
  static bool _listening = false;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  static bool get _solid => !_ready || _solidScopes.isNotEmpty;

  static void setSolidScope(Object token, bool solid) {
    if (solid) {
      _solidScopes.add(token);
      _sync();
    } else if (_solidScopes.remove(token)) {
      // Replacement routes may register another solid scope in this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  static void _sync({bool force = false}) {
    if (!_supported) return;
    if (_solid) {
      _epoch++;
      _downgradeScheduled = false;
      _stopTimings();
      if (force || _lastSent != true) {
        _lastSent = true;
        unawaited(_send(true));
      }
      return;
    }
    if (_lastSent == false) {
      if (force) unawaited(_send(false));
      return;
    }
    if (_downgradeScheduled || _pendingFrame != null) return;
    _downgradeScheduled = true;
    final epoch = _epoch;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (epoch != _epoch || _solid) return;
      _downgradeScheduled = false;
      // Post-frame means Dart painting finished, not that the raster thread
      // replaced the last secret frame. Match the engine's raw build timestamp.
      _pendingFrame = binding.currentSystemFrameTimeStamp.inMicroseconds;
      if (!_listening) {
        _listening = true;
        binding.addTimingsCallback(_onTimings);
      }
      // The just-painted frame may already have rasterized before reporting
      // was enabled. Request one more so even a static screen can reach blur.
      binding.scheduleFrame();
    });
    binding.scheduleFrame();
  }

  static void _onTimings(List<FrameTiming> timings) {
    final pending = _pendingFrame;
    if (pending == null || _solid) return;
    if (!timings.any(
      (frame) =>
          frame.timestampInMicroseconds(FramePhase.buildStart) >= pending,
    )) {
      return;
    }
    _stopTimings();
    _lastSent = false;
    unawaited(_send(false));
  }

  static void _stopTimings() {
    _pendingFrame = null;
    if (_listening) {
      WidgetsBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
    }
  }

  static Future<void> _send(bool solid) async {
    try {
      await _channel.invokeMethod<void>('setSolidBackground', {'solid': solid});
    } catch (_) {
      _lastSent = null;
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _epoch++;
    _downgradeScheduled = false;
    _stopTimings();
    _solidScopes.clear();
    _hosts.clear();
    _ready = false;
    _lastSent = null;
  }
}

/// Before the app's first frame, native defaults to solid.
class AppPrivacyHost extends StatefulWidget {
  const AppPrivacyHost({required this.child, super.key});
  final Widget child;

  @override
  State<AppPrivacyHost> createState() => _AppPrivacyHostState();
}

class _AppPrivacyHostState extends State<AppPrivacyHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppPrivacyPolicy._hosts.add(this);
    AppPrivacyPolicy._sync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppPrivacyPolicy._ready = true;
      AppPrivacyPolicy._sync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppPrivacyPolicy._sync(force: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppPrivacyPolicy._hosts.remove(this);
    if (AppPrivacyPolicy._hosts.isEmpty) {
      AppPrivacyPolicy._ready = false;
      AppPrivacyPolicy._sync();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
