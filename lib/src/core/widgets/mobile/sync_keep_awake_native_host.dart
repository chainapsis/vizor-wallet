import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../layout/app_form_factor.dart';
import '../../../providers/sync_keep_awake_provider.dart';
import '../../../services/native_screen_awake.dart';

class SyncKeepAwakeNativeHost extends ConsumerStatefulWidget {
  const SyncKeepAwakeNativeHost({
    required this.child,
    this.bridge = const NativeScreenAwakeBridge(),
    super.key,
  });

  final Widget child;
  final NativeScreenAwakeBridge bridge;

  @override
  ConsumerState<SyncKeepAwakeNativeHost> createState() =>
      _SyncKeepAwakeNativeHostState();
}

class _SyncKeepAwakeNativeHostState
    extends ConsumerState<SyncKeepAwakeNativeHost> {
  bool _lastRequestedEnabled = false;
  bool _lastAppliedEnabled = false;
  Future<void> _nativeQueue = Future<void>.value();

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor == AppFormFactor.mobile) {
      _requestNativeState(ref.watch(syncKeepAwakeActiveProvider));
    }
    return widget.child;
  }

  @override
  void dispose() {
    if (_lastRequestedEnabled || _lastAppliedEnabled) {
      _requestNativeState(false, force: true);
    }
    super.dispose();
  }

  void _requestNativeState(bool enabled, {bool force = false}) {
    if (!force && _lastRequestedEnabled == enabled) return;
    _lastRequestedEnabled = enabled;
    final bridge = widget.bridge;
    _nativeQueue = _nativeQueue.then(
      (_) => _applyNativeState(bridge, enabled, force: force),
    );
  }

  Future<void> _applyNativeState(
    NativeScreenAwakeBridge bridge,
    bool enabled, {
    required bool force,
  }) async {
    if (!force && _lastAppliedEnabled == enabled) return;
    try {
      await bridge.setEnabled(enabled);
      _lastAppliedEnabled = enabled;
    } catch (error) {
      debugPrint(
        'SyncKeepAwakeNativeHost: setEnabled($enabled) failed: $error',
      );
    }
  }
}
