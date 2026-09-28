import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../layout/app_form_factor.dart';

/// Native observation is enabled by production bootstrap, not preview fixtures.
final capsLockMonitoringEnabledProvider = Provider<bool>((ref) => false);

final capsLockMonitorProvider = Provider.autoDispose<CapsLockMonitor>((ref) {
  final monitor = CapsLockMonitor(
    enabled:
        ref.watch(capsLockMonitoringEnabledProvider) &&
        kAppFormFactor == AppFormFactor.desktop &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux),
    refreshOnKeyEvents: Platform.isWindows,
  );
  ref.onDispose(monitor.dispose);
  return monitor;
});

/// Native lock state, never inferred from key presses or password characters.
/// A null value means unavailable or inactive, not a confirmed unlocked state.
class CapsLockMonitor extends ValueNotifier<bool?>
    with WidgetsBindingObserver, WindowListener {
  CapsLockMonitor({required this.enabled, this.refreshOnKeyEvents = false})
    : super(null) {
    if (!enabled) return;
    channel.setMethodCallHandler(_handleNativeCall);
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    if (refreshOnKeyEvents) HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(refresh());
  }

  static const channel = MethodChannel('com.zcash.wallet/caps_lock');
  final bool enabled;
  final bool refreshOnKeyEvents;
  bool _active = true;
  bool _disposed = false;
  int _revision = 0;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onStateChanged' || _disposed) return;
    _revision++;
    value = _active && call.arguments is bool ? call.arguments as bool : null;
  }

  Future<void> refresh() async {
    if (!enabled || !_active || _disposed) return;
    final revision = ++_revision;
    bool? next;
    try {
      next = await channel
          .invokeMethod<bool>('getCapsLockState')
          .timeout(const Duration(milliseconds: 300));
    } catch (_) {
      // This convenience must never interfere with authentication.
    }
    if (!_disposed && _active && revision == _revision) value = next;
  }

  bool _onKey(KeyEvent event) {
    // Re-query for all keys so OS remapping is not tied to a physical key.
    // Never consume input or toggle our own copy of the lock bit.
    unawaited(refresh());
    return false;
  }

  void _setActive(bool active) {
    if (_disposed) return;
    _revision++;
    _active = active;
    value = null;
    if (active) unawaited(refresh());
  }

  @override
  void onWindowFocus() => _setActive(true);
  @override
  void onWindowBlur() => _setActive(false);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _setActive(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    if (enabled) {
      channel.setMethodCallHandler(null);
      WidgetsBinding.instance.removeObserver(this);
      windowManager.removeListener(this);
      if (refreshOnKeyEvents) HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }
}
