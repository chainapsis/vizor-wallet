import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/input/caps_lock_monitor.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  Future<void> nativeState(bool? state) async {
    await messenger.handlePlatformMessage(
      CapsLockMonitor.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onStateChanged', state),
      ),
      (_) {},
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(CapsLockMonitor.channel, null);
  });

  test('initial state is read without a key event', () async {
    messenger.setMockMethodCallHandler(
      CapsLockMonitor.channel,
      (_) async => true,
    );
    final monitor = CapsLockMonitor(enabled: true);
    addTearDown(monitor.dispose);
    await monitor.refresh();
    expect(monitor.value, isTrue);
  });

  test(
    'native changes override an older query and support unknown state',
    () async {
      final pending = Completer<bool>();
      messenger.setMockMethodCallHandler(
        CapsLockMonitor.channel,
        (_) => pending.future,
      );
      final monitor = CapsLockMonitor(enabled: true);
      addTearDown(monitor.dispose);
      final query = monitor.refresh();
      await nativeState(false);
      pending.complete(true);
      await query;
      expect(monitor.value, isFalse);
      await nativeState(true);
      expect(monitor.value, isTrue);
      await nativeState(null);
      expect(monitor.value, isNull);
    },
  );

  test(
    'blur hides state and discards pending reads and native events',
    () async {
      final pending = Completer<bool>();
      messenger.setMockMethodCallHandler(
        CapsLockMonitor.channel,
        (_) => pending.future,
      );
      final monitor = CapsLockMonitor(enabled: true);
      addTearDown(monitor.dispose);
      final query = monitor.refresh();
      monitor.onWindowBlur();
      await nativeState(true);
      pending.complete(true);
      await query;
      expect(monitor.value, isNull);
      messenger.setMockMethodCallHandler(
        CapsLockMonitor.channel,
        (_) async => true,
      );
      monitor.onWindowFocus();
      await monitor.refresh();
      expect(monitor.value, isTrue);
      monitor.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(monitor.value, isNull);
    },
  );

  test('missing native implementation does not block input', () async {
    final monitor = CapsLockMonitor(enabled: true);
    addTearDown(monitor.dispose);
    await monitor.refresh();
    expect(monitor.value, isNull);
  });

  test('disabled monitor never queries the platform', () async {
    var queries = 0;
    messenger.setMockMethodCallHandler(CapsLockMonitor.channel, (_) async {
      queries++;
      return true;
    });
    final monitor = CapsLockMonitor(enabled: false);
    addTearDown(monitor.dispose);
    await monitor.refresh();
    expect(queries, 0);
  });

  test('disposal ignores an outstanding query', () async {
    final pending = Completer<bool>();
    messenger.setMockMethodCallHandler(
      CapsLockMonitor.channel,
      (_) => pending.future,
    );
    final monitor = CapsLockMonitor(enabled: true);
    final query = monitor.refresh();
    monitor.dispose();
    pending.complete(true);
    await query;
    expect(monitor.value, isNull);
  });

  testWidgets('remapped keys cause an OS query without toggling local state', (
    tester,
  ) async {
    var state = false;
    messenger.setMockMethodCallHandler(
      CapsLockMonitor.channel,
      (_) async => state,
    );
    final monitor = CapsLockMonitor(enabled: true, refreshOnKeyEvents: true);
    addTearDown(monitor.dispose);
    await monitor.refresh();
    state = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    expect(monitor.value, isTrue);
    // A Caps Lock key used for language switching need not change the OS flag.
    state = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.capsLock);
    await tester.pump();
    expect(monitor.value, isFalse);
  });
}
