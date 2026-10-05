import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/core/feedback/app_review_host.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/core/feedback/app_review.dart';

class MemoryReviewStore implements AppReviewStore {
  MemoryReviewStore(this.value);
  AppReviewHistory value;
  bool fail = false;
  void Function(AppReviewHistory)? onSave;
  @override
  Future<AppReviewHistory> load() async => value;
  @override
  Future<void> save(AppReviewHistory history) async {
    if (fail) throw StateError('Storage unavailable');
    value = history;
    onSave?.call(history);
  }
}

class FakeReviewNative implements AppReviewNative {
  int preparations = 0;
  int requests = 0;
  int cancellations = 0;
  bool available = true;
  bool accepted = true;
  bool throwOnRequest = false;
  Completer<bool>? preparation;
  @override
  Future<bool> prepare() async {
    preparations++;
    return preparation == null ? available : await preparation!.future;
  }

  @override
  Future<bool> request() async {
    requests++;
    if (throwOnRequest) throw StateError('Response lost');
    return accepted;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

class _UnlockedSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _ExistingWallet extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(hasWallet: true);
}

void main() {
  late MemoryReviewStore store;
  late FakeReviewNative native;
  late AppReviewController controller;
  late DateTime now;
  setUp(() {
    now = DateTime.utc(2026, 10, 1);
    store = MemoryReviewStore(const AppReviewHistory(launches: 2));
    native = FakeReviewNative();
    controller = AppReviewController(
      store: store,
      native: native,
      now: () => now,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'counts one foreground cold launch per process, including concurrent callers',
    () async {
      await Future.wait([controller.recordLaunch(), controller.recordLaunch()]);
      expect(store.value.launches, 3);
      await controller.recordLaunch();
      expect(store.value.launches, 3);
    },
  );

  test('requires the third launch and explicit usage', () async {
    store.value = const AppReviewHistory(launches: 1);
    await controller.recordLaunch();
    controller.recordUse();
    await controller.requestIfDue(() => true);
    expect(native.requests, 0);
    final nextProcess = AppReviewController(
      store: store,
      native: native,
      now: () => now,
    );
    await nextProcess.recordLaunch();
    await nextProcess.requestIfDue(() => true);
    expect(native.requests, 0);
    nextProcess.recordUse();
    await nextProcess.requestIfDue(() => true);
    expect(native.requests, 1);
    nextProcess.dispose();
  });

  test(
    'existing wallet users can request on their first launch after usage',
    () async {
      store.value = const AppReviewHistory();
      await controller.recordLaunch(hadWalletAtStartup: true);
      expect(store.value.launches, 1);
      expect(store.value.existingUser, isTrue);
      await controller.requestIfDue(() => true);
      expect(native.requests, 0);
      controller.recordUse();
      await controller.requestIfDue(() => false);
      expect(native.requests, 0);
      await controller.requestIfDue(() => true);
      expect(native.requests, 1);
      expect(
        AppReviewHistory.decode(store.value.encode()).existingUser,
        isTrue,
      );
    },
  );

  test(
    'new wallet creation does not promote a new installation on restart',
    () async {
      store.value = const AppReviewHistory();
      await controller.recordLaunch(hadWalletAtStartup: false);
      await controller.recordLaunch(hadWalletAtStartup: true);
      expect(store.value.existingUser, isFalse);
      store.value = AppReviewHistory.decode(store.value.encode());
      final nextProcess = AppReviewController(store: store, native: native);
      addTearDown(nextProcess.dispose);
      await nextProcess.recordLaunch(hadWalletAtStartup: true);
      nextProcess.recordUse();
      await nextProcess.requestIfDue(() => true);
      expect(store.value.launches, 2);
      expect(store.value.existingUser, isFalse);
      expect(native.requests, 0);
      final thirdProcess = AppReviewController(store: store, native: native);
      addTearDown(thirdProcess.dispose);
      await thirdProcess.recordLaunch(hadWalletAtStartup: true);
      thirdProcess.recordUse();
      await thirdProcess.requestIfDue(() => true);
      expect(native.requests, 1);
      expect(store.value.existingUser, isFalse);
    },
  );

  test(
    'existing users retain the seven-day cooldown and two-attempt limit',
    () async {
      store.value = const AppReviewHistory();
      await controller.recordLaunch(hadWalletAtStartup: true);
      controller.recordUse();
      await controller.requestIfDue(() => true);
      now = now
          .add(const Duration(days: 7))
          .subtract(const Duration(milliseconds: 1));
      controller.recordUse();
      await controller.requestIfDue(() => true);
      expect(native.requests, 1);
      now = now.add(const Duration(milliseconds: 1));
      await controller.requestIfDue(() => true);
      expect(native.requests, 2);
      now = now.add(const Duration(days: 400));
      controller.recordUse();
      await controller.requestIfDue(() => true);
      expect(native.requests, 2);
    },
  );

  test(
    'legacy history is classified without resetting attempts or dates',
    () async {
      store.value = AppReviewHistory.decode(
        '{"launches":1,"requests":1,"lastRequest":"2026-09-30T00:00:00Z"}',
      );
      final lastRequest = store.value.lastRequest;
      await controller.recordLaunch(hadWalletAtStartup: true);
      expect(store.value.existingUser, isTrue);
      expect(store.value.requests, 1);
      expect(store.value.lastRequest, lastRequest);
      controller.recordUse();
      await controller.requestIfDue(() => true);
      expect(native.requests, 0);
      now = lastRequest!.add(const Duration(days: 7));
      await controller.requestIfDue(() => true);
      expect(native.requests, 1);
      expect(store.value.requests, 2);
    },
  );

  test(
    'stored existing-user decision survives wallet removal and restart',
    () async {
      store.value = const AppReviewHistory(existingUser: true, launches: 1);
      await controller.recordLaunch(hadWalletAtStartup: false);
      controller.recordUse();
      await controller.requestIfDue(() => true);
      expect(native.requests, 1);
      expect(store.value.existingUser, isTrue);
    },
  );

  test(
    'legacy exhausted and damaged histories cannot receive a new budget',
    () async {
      for (final value in [
        '{"launches":1,"requests":2,"lastRequest":"2026-09-01T00:00:00Z"}',
        '{"launches":1,"requests":0,"existingUser":"yes"}',
        'broken',
      ]) {
        final historyStore = MemoryReviewStore(AppReviewHistory.decode(value));
        final nextProcess = AppReviewController(
          store: historyStore,
          native: native,
        );
        await nextProcess.recordLaunch(hadWalletAtStartup: true);
        nextProcess.recordUse();
        await nextProcess.requestIfDue(() => true);
        expect(historyStore.value.requests, 2);
        expect(native.requests, 0);
        nextProcess.dispose();
      }
    },
  );

  test(
    'two API attempts total, second at seven days with renewed usage',
    () async {
      await controller.recordLaunch();
      controller.recordUse();
      await controller.requestIfDue(() => true);
      expect(store.value.requests, 1);
      now = now
          .add(const Duration(days: 7))
          .subtract(const Duration(milliseconds: 1));
      controller.recordUse();
      await controller.requestIfDue(() => true);
      expect(native.requests, 1);
      now = now.add(const Duration(milliseconds: 1));
      await controller.requestIfDue(() => true);
      expect(native.requests, 2);
      now = now.add(const Duration(days: 400));
      controller.recordUse();
      await controller.requestIfDue(() => true);
      expect(native.requests, 2);
      expect(store.value.requests, 2);
    },
  );

  test('no impression result is needed to persist the attempt', () async {
    await controller.recordLaunch();
    controller.recordUse();
    await controller.requestIfDue(() => true);
    expect(store.value.lastRequest, now);
    expect(controller.isDue, false);
    now = now.add(const Duration(days: 7));
    expect(controller.isDue, false);
    controller.recordUse();
    expect(controller.isDue, true);
  });

  test(
    'history survives a new process without a version/account reset',
    () async {
      store.value = AppReviewHistory(
        launches: 3,
        requests: 2,
        lastRequest: now,
      );
      await controller.recordLaunch();
      controller.recordUse();
      expect(controller.isDue, false);
      expect(AppReviewHistory.decode(store.value.encode()).requests, 2);
    },
  );

  test('unsafe surface defers without consuming usage or budget', () async {
    await controller.recordLaunch();
    controller.recordUse();
    await controller.requestIfDue(() => false);
    expect(native.preparations, 0);
    expect(store.value.requests, 0);
    await controller.requestIfDue(() => true);
    expect(native.requests, 1);
  });

  test(
    'navigation during native preparation cancels without an attempt',
    () async {
      await controller.recordLaunch();
      controller.recordUse();
      native.preparation = Completer<bool>();
      var safe = true;
      final pending = controller.requestIfDue(() => safe);
      safe = false;
      native.preparation!.complete(true);
      await pending;
      expect(native.requests, 0);
      expect(store.value.requests, 0);
      expect(native.cancellations, 1);
      expect(controller.isDue, true);
    },
  );

  test('navigation during persistence rolls back the reservation', () async {
    await controller.recordLaunch();
    controller.recordUse();
    var safe = true;
    store.onSave = (value) {
      if (value.requests == 1) safe = false;
    };
    await controller.requestIfDue(() => safe);
    expect(native.requests, 0);
    expect(store.value.requests, 0);
    expect(controller.isDue, true);
  });

  test('native foreground rejection restores the request budget', () async {
    await controller.recordLaunch();
    controller.recordUse();
    native.accepted = false;
    await controller.requestIfDue(() => true);
    expect(store.value.requests, 0);
    expect(controller.isDue, true);
  });

  test(
    'concurrent attempts are serialized and history is reserved before dispatch',
    () async {
      await controller.recordLaunch();
      controller.recordUse();
      native.preparation = Completer<bool>();
      final first = controller.requestIfDue(() => true);
      await controller.requestIfDue(() => true);
      expect(native.preparations, 1);
      native.preparation!.complete(true);
      await first;
      expect(native.requests, 1);
      expect(store.value.requests, 1);
    },
  );

  test('unavailable native preparation does not consume an attempt', () async {
    await controller.recordLaunch();
    controller.recordUse();
    native.available = false;
    await controller.requestIfDue(() => true);
    expect(native.requests, 0);
    expect(store.value.requests, 0);
  });

  test('ambiguous native failure preserves the cap', () async {
    await controller.recordLaunch();
    controller.recordUse();
    native.throwOnRequest = true;
    await controller.requestIfDue(() => true);
    expect(store.value.requests, 1);
    expect(controller.isDue, false);
  });

  test('failed persistence prevents native dispatch', () async {
    await controller.recordLaunch();
    controller.recordUse();
    store.fail = true;
    await controller.requestIfDue(() => true);
    expect(native.requests, 0);
  });

  test('damaged history cannot grant another review budget', () {
    for (final value in ['broken', '{}', '{"launches":3,"requests":1}']) {
      expect(AppReviewHistory.decode(value).requests, 2);
    }
  });

  test(
    'only an explicitly visited screen followed by home qualifies',
    () async {
      await controller.recordLaunch();
      controller.observePath('/receive');
      controller.observePath('/home');
      expect(controller.isDue, false);
      controller.expectVisit('/receive');
      controller.observePath('/accounts');
      controller.observePath('/home');
      expect(controller.isDue, false);
      controller.expectVisit('/receive');
      controller.observePath('/receive');
      expect(controller.isDue, false);
      controller.observePath('/home');
      expect(controller.isDue, true);
    },
  );

  test(
    'overlapping important actions keep the busy guard until both end',
    () async {
      final one = Completer<void>();
      final two = Completer<void>();
      final first = controller.duringBusy(() => one.future);
      final second = controller.duringBusy(() => two.future);
      expect(controller.isBusy, true);
      one.complete();
      await first;
      expect(controller.isBusy, true);
      two.complete();
      await second;
      expect(controller.isBusy, false);
    },
  );
  test(
    'returning from a restored nested tab counts as explicit usage',
    () async {
      await controller.recordLaunch();
      controller.expectVisit('/settings');
      controller.observePath('/settings/security');
      controller.observePath('/home');
      expect(controller.isDue, true);
    },
  );
  test('sync privacy lock blocks home while the wallet remains unlocked', () {
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_UnlockedSecurity.new),
        walletProvider.overrideWith(_ExistingWallet.new),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      appReviewSurfaceSafeProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(container.read(appReviewSurfaceSafeProvider), true);
    container.read(syncKeepAwakePrivacyLockProvider.notifier).lock();
    expect(container.read(appSecurityProvider).isUnlocked, true);
    expect(container.read(appReviewSurfaceSafeProvider), false);
    container.read(syncKeepAwakePrivacyLockProvider.notifier).clear();
    expect(container.read(appReviewSurfaceSafeProvider), true);
  });
}
