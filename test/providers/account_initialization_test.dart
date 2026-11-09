import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/home/providers/home_initialization_provider.dart';
import 'package:zcash_wallet/src/providers/account_initialization_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  test(
    'a stream snapshot cannot complete accounts added later or after reset',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(accountInitializationProvider.notifier);
      n.register('a', AccountInitializationKind.restored);
      final old = n.pendingTokens();
      n.register('b', AccountInitializationKind.created);
      n.observeScan(old, completed: true);
      expect(c.read(accountInitializationProvider)['a']!.scanCompleted, isTrue);
      expect(
        c.read(accountInitializationProvider)['b']!.scanCompleted,
        isFalse,
      );
      n.clear();
      n.register('a', AccountInitializationKind.restored);
      n.observeScan(old, completed: true);
      n.reportReads('a', old['a'], available: true);
      expect(
        c.read(accountInitializationProvider)['a']!.scanCompleted,
        isFalse,
      );
      n.remove('a');
      n.reportReads('a', old['a'], available: true);
      expect(c.read(accountInitializationProvider), isEmpty);
    },
  );

  test(
    'a created account never enters importing for a one-block initial scan',
    () async {
      final h = await _Harness.start(AccountInitializationKind.created);
      for (final remaining in [null, 1, 0]) {
        h.sync.emit(
          SyncState(
            accountUuid: 'a',
            isSyncing: true,
            remainingScanBlocks: remaining,
          ),
        );
        await _flush();
        expect(h.presentation.showImporting, isFalse);
        expect(
          h.c.read(syncProvider).requireValue.hasRecentTransactionsData,
          isFalse,
        );
      }
    },
  );

  test(
    'restore waits for completion, accepted account reads and prewarmed local indexes',
    () async {
      final gate = Completer<GiftCardActivityIndex>();
      final h = await _Harness.start(
        AccountInitializationKind.restored,
        cards: () => gate.future,
      );
      expect(h.presentation.showImporting, isTrue);
      expect(h.localLoads, 1);
      // A first partial/zero DB summary must not be mistaken for completed restore.
      h.sync.emit(
        SyncState(
          accountUuid: 'a',
          isSyncing: true,
          hasAccountScopedData: true,
          remainingScanBlocks: 1000,
        ),
      );
      h.registry.reportReads('a', h.token, available: true);
      await _flush();
      expect(h.presentation.showImporting, isTrue);
      h.sync.emit(
        SyncState(
          accountUuid: 'a',
          isSyncing: true,
          hasAccountScopedData: true,
          remainingScanBlocks: 0,
          percentage: 1,
        ),
      );
      await _flush();
      expect(h.presentation.showImporting, isTrue);
      h.registry.observeScan(h.registry.pendingTokens(), completed: true);
      h.registry.reportReads('a', h.token, available: true);
      await _flush();
      expect(h.presentation.showImporting, isTrue);
      gate.complete(GiftCardActivityIndex.empty);
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      expect(h.localLoads, 1);
      // Later index invalidation and another sync never replace usable Home.
      final next = Completer<GiftCardActivityIndex>();
      h.cards = () => next.future;
      h.c.invalidate(giftCardActivityIndexProvider('a'));
      h.sync.emit(
        SyncState(accountUuid: 'a', isSyncing: true, remainingScanBlocks: 100),
      );
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      next.complete(GiftCardActivityIndex.empty);
    },
  );

  test(
    'unknown restored sessions enter on real pending work and do not bounce at zero',
    () async {
      final h = await _Harness.start(AccountInitializationKind.unknown);
      expect(h.presentation.showImporting, isFalse);
      h.registry.observeScan(h.registry.pendingTokens(), completed: false);
      h.sync.emit(
        SyncState(accountUuid: 'a', isSyncing: true, remainingScanBlocks: 5),
      );
      await _flush();
      expect(h.presentation.showImporting, isTrue);
      h.sync.emit(
        SyncState(accountUuid: 'a', isSyncing: true, remainingScanBlocks: 0),
      );
      await _flush();
      expect(h.presentation.showImporting, isTrue);
    },
  );

  test(
    'local read failure exits importing and recovery does not reenter it',
    () async {
      final h = await _Harness.start(AccountInitializationKind.restored);
      h.registry.observeScan(h.registry.pendingTokens(), completed: true);
      h.registry.reportReads('a', h.token, available: false);
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      expect(h.presentation.activityUnavailable, isTrue);
      h.registry.reportReads('a', h.token, available: true);
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      expect(h.presentation.activityUnavailable, isFalse);
    },
  );

  test(
    'a failed local card index releases completed restoration to unavailable Home',
    () async {
      final h = await _Harness.start(
        AccountInitializationKind.restored,
        cards: () async => throw StateError('local records unavailable'),
      );
      h.registry.observeScan(h.registry.pendingTokens(), completed: true);
      h.registry.reportReads('a', h.token, available: true);
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      expect(h.presentation.activityUnavailable, isTrue);
    },
  );

  test(
    'network failure is actionable and retry can resume the restore screen',
    () async {
      final h = await _Harness.start(AccountInitializationKind.restored);
      h.sync.emit(
        SyncState(
          accountUuid: 'a',
          failure: classifySyncFailure('network: timeout'),
        ),
      );
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      h.sync.emit(SyncState(accountUuid: 'a', isSyncing: true));
      await _flush();
      expect(h.presentation.showImporting, isTrue);
    },
  );

  test(
    'account switch and lock retain presentation ownership without leaking another account',
    () async {
      final h = await _Harness.start(AccountInitializationKind.restored);
      h.registry.register('b', AccountInitializationKind.created);
      h.accounts.select('b');
      h.sync.emit(
        SyncState(accountUuid: 'b', isSyncing: true, remainingScanBlocks: 1000),
      );
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      h.accounts.select('a');
      await _flush();
      expect(h.presentation.showImporting, isTrue);
      h.security.setLocked(true);
      await _flush();
      expect(h.presentation.showImporting, isFalse);
      expect(
        h.c.read(accountInitializationProvider)['a']!.token,
        same(h.token),
      );
      h.security.setLocked(false);
      await _flush();
      expect(h.presentation.showImporting, isTrue);
    },
  );
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Harness {
  final accounts = _Accounts();
  final sync = _Sync();
  final security = _Security();
  late final ProviderContainer c;
  Future<GiftCardActivityIndex> Function() cards = () async =>
      GiftCardActivityIndex.empty;
  int localLoads = 0;
  late Object token;
  AccountInitializationNotifier get registry =>
      c.read(accountInitializationProvider.notifier);
  HomeInitializationPresentation get presentation =>
      c.read(homeInitializationPresentationProvider);

  static Future<_Harness> start(
    AccountInitializationKind kind, {
    Future<GiftCardActivityIndex> Function()? cards,
  }) async {
    final h = _Harness();
    if (cards != null) h.cards = cards;
    h.c = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(() => h.accounts),
        syncProvider.overrideWith(() => h.sync),
        appSecurityProvider.overrideWith(() => h.security),
        swapFeatureEnabledProvider.overrideWithValue(false),
        giftCardActivityIndexProvider.overrideWith((ref, uuid) {
          h.localLoads++;
          return h.cards();
        }),
      ],
    );
    addTearDown(h.c.dispose);
    h.registry.register('a', kind);
    h.token = h.c.read(accountInitializationProvider)['a']!.token;
    h.c.listen(homeInitializationPresentationProvider, (_, _) {});
    await h.c.read(accountProvider.future);
    await h.c.read(syncProvider.future);
    await _flush();
    return h;
  }
}

class _Accounts extends AccountNotifier {
  @override
  Future<AccountState> build() async => const AccountState(
    accounts: [
      AccountInfo(uuid: 'a', name: 'A', order: 0),
      AccountInfo(uuid: 'b', name: 'B', order: 1),
    ],
    activeAccountUuid: 'a',
  );
  void select(String uuid) =>
      state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
}

class _Sync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(accountUuid: 'a');
  void emit(SyncState next) => state = AsyncData(next);
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  void setLocked(bool value) =>
      state = AppSecurityState(isPasswordConfigured: true, isUnlocked: !value);
}
