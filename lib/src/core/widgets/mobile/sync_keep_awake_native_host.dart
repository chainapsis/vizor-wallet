import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../layout/app_form_factor.dart';
import '../../../providers/sync_keep_awake_provider.dart';
import '../../../services/native_screen_awake.dart';

const kNativeScreenAwakeRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 4),
  Duration(seconds: 16),
];

class SyncKeepAwakeNativeHost extends ConsumerStatefulWidget {
  const SyncKeepAwakeNativeHost({
    required this.child,
    this.bridge = const NativeScreenAwakeBridge(),
    this.retryDelays = kNativeScreenAwakeRetryDelays,
    super.key,
  });

  final Widget child;
  final NativeScreenAwakeBridge bridge;
  final List<Duration> retryDelays;

  @override
  ConsumerState<SyncKeepAwakeNativeHost> createState() =>
      _SyncKeepAwakeNativeHostState();
}

class _SyncKeepAwakeNativeHostState
    extends ConsumerState<SyncKeepAwakeNativeHost> {
  AppLifecycleListener? _lifecycleListener;
  Timer? _retryTimer;
  bool _isInForeground = true;
  bool _desiredEnabled = false;
  bool _lastAppliedEnabled = false;
  bool _nativeStateUncertain = false;
  bool _isDisposed = false;
  int _requestGeneration = 0;
  Future<void> _nativeQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor != AppFormFactor.mobile) return;

    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isInForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _lifecycleListener = AppLifecycleListener(
      onResume: _handleLifecycleResume,
      onInactive: _handleLifecycleBackground,
      onHide: _handleLifecycleBackground,
      onPause: _handleLifecycleBackground,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor == AppFormFactor.mobile) {
      _requestNativeState(
        _isInForeground && ref.watch(syncKeepAwakeActiveProvider),
      );
    }
    return widget.child;
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _retryTimer?.cancel();
    _isDisposed = true;
    if (_desiredEnabled || _lastAppliedEnabled || _nativeStateUncertain) {
      _requestNativeState(false, force: true, allowDisposed: true);
    }
    super.dispose();
  }

  void _handleLifecycleBackground() {
    if (!_isInForeground) return;
    _isInForeground = false;
    _requestNativeState(false);
  }

  void _handleLifecycleResume() {
    if (_isInForeground) return;
    _isInForeground = true;
    _requestNativeState(ref.read(syncKeepAwakeActiveProvider));
  }

  void _requestNativeState(
    bool enabled, {
    bool force = false,
    bool allowDisposed = false,
  }) {
    if (_isDisposed && !allowDisposed) return;
    if (!force && _desiredEnabled == enabled) return;

    _desiredEnabled = enabled;
    _retryTimer?.cancel();
    _retryTimer = null;
    final generation = ++_requestGeneration;
    _enqueueNativeAttempt(
      enabled,
      generation: generation,
      failedAttempts: 0,
      force: force,
    );
  }

  void _enqueueNativeAttempt(
    bool enabled, {
    required int generation,
    required int failedAttempts,
    bool force = false,
  }) {
    final bridge = widget.bridge;
    final totalAttempts = widget.retryDelays.length + 1;
    _nativeQueue = _nativeQueue.then((_) async {
      if (!_isCurrentRequest(enabled, generation)) return;
      final applied = await _applyNativeState(
        bridge,
        enabled,
        force: force,
        attempt: failedAttempts + 1,
        totalAttempts: totalAttempts,
      );
      if (!applied) {
        _scheduleRetry(
          enabled,
          generation: generation,
          failedAttempts: failedAttempts + 1,
        );
      }
    });
  }

  bool _isCurrentRequest(bool enabled, int generation) {
    return generation == _requestGeneration && _desiredEnabled == enabled;
  }

  Future<bool> _applyNativeState(
    NativeScreenAwakeBridge bridge,
    bool enabled, {
    required bool force,
    required int attempt,
    required int totalAttempts,
  }) async {
    if (!force && !_nativeStateUncertain && _lastAppliedEnabled == enabled) {
      return true;
    }
    try {
      await bridge.setEnabled(enabled);
      _lastAppliedEnabled = enabled;
      _nativeStateUncertain = false;
      return true;
    } catch (error) {
      _nativeStateUncertain = true;
      debugPrint(
        'SyncKeepAwakeNativeHost: setEnabled($enabled) failed '
        '(attempt $attempt/$totalAttempts): $error',
      );
      return false;
    }
  }

  void _scheduleRetry(
    bool enabled, {
    required int generation,
    required int failedAttempts,
  }) {
    if (_isDisposed ||
        !_isCurrentRequest(enabled, generation) ||
        failedAttempts > widget.retryDelays.length) {
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = Timer(widget.retryDelays[failedAttempts - 1], () {
      _retryTimer = null;
      if (_isDisposed || !_isCurrentRequest(enabled, generation)) return;
      _enqueueNativeAttempt(
        enabled,
        generation: generation,
        failedAttempts: failedAttempts,
      );
    });
  }
}
