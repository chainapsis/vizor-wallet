import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _accountUuid = 'account-1';

class _Api extends RustLibApi {
  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  void crateApiSyncCancelFullSync() {}

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
  );
}

/// Resolves the wallet path from [path] and records each backup mark. No mark
/// completes, so a sync start goes no further than marking: nothing reaches
/// the endpoint preflight or Rust.
class _MarkingSync extends SyncNotifier {
  _MarkingSync(String Function() path, List<String> marked)
    : super(
        walletDbPathResolver: () async => path(),
        excludeCompanionsFromBackup: (dbPath) {
          marked.add(dbPath);
          return Completer<void>().future;
        },
      );

  @override
  Future<SyncState> build() async => SyncState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _Api()));
  tearDownAll(RustLib.dispose);

  test('a sync start keeps each wallet\'s companions out of backups', () async {
    // Creating or importing a first wallet deletes the directory startup
    // marked, and a reset names a new wallet, so startup's mark is not
    // enough: the sync that will write companions marks its wallet first.
    var path = '/wallets/first.db';
    final marked = <String>[];
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        syncProvider.overrideWith(() => _MarkingSync(() => path, marked)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    final sync = container.read(syncProvider.notifier);

    sync.startSync();
    await pumpEventQueue();
    expect(marked, ['/wallets/first.db']);

    // A reset stops sync, forgets the wallet path, and the next wallet gets
    // a new one.
    sync.stopSync();
    sync.clearCachedWalletDbPath();
    path = '/wallets/after-reset.db';
    sync.startSync();
    await pumpEventQueue();
    expect(marked, ['/wallets/first.db', '/wallets/after-reset.db']);
  });
}
