import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/lifecycle/signing_shutdown_host.dart';

void main() {
  test('overlapping exit requests drain once', () async {
    final gate = Completer<void>();
    var calls = 0;
    var starts = 0;
    final coordinator = SigningShutdownCoordinator(
      onExitStarted: () => starts++,
      releaseReservations: () {
        expect(starts, 1);
        calls++;
        return gate.future;
      },
    );
    final first = coordinator.prepareExit();
    final second = coordinator.prepareExit();
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    expect(starts, 1);
    gate.complete();
    await Future.wait([first, second]);
  });

  test('slow cleanup cannot block exit indefinitely', () async {
    final gate = Completer<void>();
    Object? failure;
    final coordinator = SigningShutdownCoordinator(
      releaseReservations: () => gate.future,
      timeout: const Duration(milliseconds: 10),
      onError: (error, _) => failure = error,
    );
    await coordinator.prepareExit();
    expect(failure, isA<TimeoutException>());
    gate.complete();
  });

  for (final failHide in [false, true]) {
    testWidgets(
      'desktop hides before cleanup finishes (hide failure: $failHide)',
      (tester) async {
        final calls = <String>[];
        final errors = <Object>[];
        final gate = Completer<void>();
        var cleanups = 0;
        const channel = MethodChannel('window_manager');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            if (call.method == 'hide' && failHide) {
              throw PlatformException(code: 'hide failed');
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          SigningShutdownHost(
            desktop: true,
            coordinator: SigningShutdownCoordinator(
              onExitStarted: () => calls.add('stop work'),
              releaseReservations: () {
                cleanups++;
                return gate.future;
              },
              onError: (error, _) => errors.add(error),
            ),
            child: const SizedBox(),
          ),
        );
        windowManager.listeners.single.onWindowClose();
        windowManager.listeners.single.onWindowClose();
        await tester.pump();
        expect(calls.indexOf('stop work'), lessThan(calls.indexOf('hide')));
        expect(calls, isNot(contains('destroy')));
        expect(cleanups, 1);
        // macOS may request application exit while the window close is pending.
        final exit = tester.binding.handleRequestAppExit();
        await tester.pump(const Duration(milliseconds: 299));
        expect(calls, isNot(contains('destroy')));
        await tester.pump(const Duration(milliseconds: 1));
        expect(await exit, AppExitResponse.exit);
        expect(calls.where((x) => x == 'hide'), hasLength(1));
        expect(calls.where((x) => x == 'destroy'), hasLength(1));
        expect(errors.whereType<TimeoutException>(), hasLength(1));
        expect(
          errors.whereType<PlatformException>(),
          hasLength(failHide ? 1 : 0),
        );
        gate.complete();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('a stalled hide does not extend the cleanup deadline', (
    tester,
  ) async {
    final hide = Completer<void>();
    final cleanup = Completer<void>();
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'hide') await hide.future;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      SigningShutdownHost(
        desktop: true,
        coordinator: SigningShutdownCoordinator(
          releaseReservations: () => cleanup.future,
        ),
        child: const SizedBox(),
      ),
    );
    windowManager.listeners.single.onWindowClose();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('destroy'));
    hide.complete();
    cleanup.complete();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native destroy failure restores the window and permits retry', (
    tester,
  ) async {
    final calls = <String>[];
    var attempts = 0;
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'isMinimized') return false;
      if (call.method == 'destroy' && attempts++ == 0) {
        throw PlatformException(code: 'destroy failed');
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      SigningShutdownHost(
        desktop: true,
        coordinator: SigningShutdownCoordinator(
          releaseReservations: () async {},
        ),
        child: const SizedBox(),
      ),
    );
    windowManager.listeners.single.onWindowClose();
    await tester.pump();
    expect(calls, contains('show'));
    windowManager.listeners.single.onWindowClose();
    await tester.pump();
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'macOS hides through the guarded native exit channel',
    (tester) async {
      const exitChannel = MethodChannel('com.zcash.wallet/desktop_exit');
      const windowChannel = MethodChannel('window_manager');
      final calls = <String>[];
      final gate = Completer<void>();
      for (final channel in [exitChannel, windowChannel]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add('${channel.name}:${call.method}');
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
      }
      await tester.pumpWidget(
        SigningShutdownHost(
          desktop: true,
          coordinator: SigningShutdownCoordinator(
            releaseReservations: () => gate.future,
          ),
          child: const SizedBox(),
        ),
      );
      final exit = tester.binding.handleRequestAppExit();
      await tester.pump();
      expect(calls, contains('com.zcash.wallet/desktop_exit:hideForExit'));
      expect(calls, isNot(contains('window_manager:hide')));
      gate.complete();
      expect(await exit, AppExitResponse.exit);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('backgrounding preserves signing; an exit request releases it', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      SigningShutdownHost(
        coordinator: SigningShutdownCoordinator(
          releaseReservations: () async => calls++,
        ),
        desktop: false,
        child: const SizedBox(),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls, 0);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
