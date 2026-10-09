import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _RustApi()));

  test(
    'new sync clears the completed queue before asynchronous preflight',
    () async {
      final dbPath = Completer<String>();
      final notifier = _StartTestSyncNotifier(dbPath);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_AccountNotifier.new),
          syncProvider.overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);

      notifier.startSync();

      final preparing = container.read(syncProvider).requireValue;
      expect(preparing.isSyncing, isTrue);
      expect(preparing.phase, kSyncPhasePreflight);
      expect(preparing.scannedHeight, 2000);
      expect(preparing.chainTipHeight, 2000);
      expect(preparing.remainingScanBlocks, isNull);
      expect(preparing.pendingScanStartHeight, isNull);
      expect(isSyncKeepAwakeActiveSync(preparing), isTrue);
    },
  );
}

class _StartTestSyncNotifier extends SyncNotifier {
  _StartTestSyncNotifier(Completer<String> dbPath)
    : super(walletDbPathResolver: () => dbPath.future);

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: 2000,
    chainTipHeight: 2000,
    remainingScanBlocks: 0,
  );
}

class _AccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  );
}

class _RustApi extends RustLibApi {
  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
