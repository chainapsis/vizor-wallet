import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  ExternalActionGuardNotifier notifier() =>
      container.read(externalActionGuardProvider.notifier);
  ExternalActionGuardState state() =>
      container.read(externalActionGuardProvider);

  test('starts without holds or pending navigation', () {
    expect(state().activeHoldCount, 0);
    expect(state().pendingNavigationCount, 0);
    expect(state().canProtect, isTrue);
    for (final action in ExternalAction.values) {
      expect(state().blocks(action), isFalse);
    }
  });

  test('signing holds preserve their action-specific protection', () {
    final lease = notifier().acquire();
    expect(state().blocks(ExternalAction.paymentRequest), isTrue);
    expect(state().blocks(ExternalAction.appReview), isTrue);
    expect(state().blocks(ExternalAction.navigation), isFalse);
    expect(state().blocks(ExternalAction.updatePrompt), isFalse);
    lease.release();
    expect(state().activeHoldCount, 0);
  });

  test('double release cannot steal an overlapping holder', () {
    final departing = notifier().acquire();
    final remaining = notifier().acquire();
    departing.release();
    departing.release();
    expect(state().activeHoldCount, 1);
    expect(state().blocks(ExternalAction.paymentRequest), isTrue);
    remaining.release();
    expect(state().activeHoldCount, 0);
  });

  test('releasing protection preserves an independent signing hold', () {
    final signing = notifier().acquire();
    final persistence = notifier().tryProtect()!;
    for (final action in ExternalAction.values) {
      expect(state().blocks(action), isTrue);
    }
    expect(notifier().tryProtect(), isNull);
    expect(notifier().tryBeginNavigation(), isNull);
    persistence.release();
    expect(state().activeHoldCount, 1);
    expect(state().blocks(ExternalAction.navigation), isFalse);
    expect(state().blocks(ExternalAction.paymentRequest), isTrue);
    signing.release();
  });

  test(
    'accepted navigation prevents persistence until every owner settles',
    () {
      final first = notifier().tryBeginNavigation()!;
      final second = notifier().tryBeginNavigation()!;
      expect(state().pendingNavigationCount, 2);
      expect(notifier().tryProtect(), isNull);
      first.release();
      first.release();
      expect(state().pendingNavigationCount, 1);
      expect(notifier().tryProtect(), isNull);
      second.release();
      final persistence = notifier().tryProtect()!;
      expect(notifier().tryBeginNavigation(), isNull);
      persistence.release();
      expect(state().canProtect, isTrue);
    },
  );

  test('releaseAfterNavigation protects the current lifecycle turn', () async {
    final lease = notifier().acquire();
    lease.releaseAfterNavigation();
    expect(state().activeHoldCount, 1);
    await Future<void>.delayed(Duration.zero);
    expect(state().activeHoldCount, 0);
  });

  test(
    'deferred and repeated release leaves a replacement owner alone',
    () async {
      final departing = notifier().acquire();
      departing.releaseAfterNavigation();
      departing.releaseAfterNavigation();
      final incoming = notifier().acquire();
      await Future<void>.delayed(Duration.zero);
      departing.release();
      expect(state().activeHoldCount, 1);
      incoming.release();
    },
  );

  test(
    'leases can finish after their provider container is disposed',
    () async {
      final scoped = ProviderContainer();
      final guard = scoped.read(externalActionGuardProvider.notifier);
      final signing = guard.acquire();
      final navigation = guard.tryBeginNavigation()!;
      signing.releaseAfterNavigation();
      scoped.dispose();
      navigation.release();
      await Future<void>.delayed(Duration.zero);
      signing.release();
    },
  );
}
