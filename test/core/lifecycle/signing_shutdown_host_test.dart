import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/lifecycle/signing_shutdown_host.dart';

void main() {
  test('overlapping exit requests drain once', () async {
    final gate = Completer<void>();
    var calls = 0;
    final coordinator = SigningShutdownCoordinator(
      releaseReservations: () {
        calls++;
        return gate.future;
      },
    );
    final first = coordinator.prepareExit();
    final second = coordinator.prepareExit();
    expect(identical(first, second), isTrue);
    expect(calls, 1);
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
