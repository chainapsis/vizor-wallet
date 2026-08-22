@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_restorer_provider.dart';

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() {
    return const AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: 'Account 1',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: 'account-1',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mobile submission sessions own automatic share tracking', () {
    expect(automaticVotingShareTrackingEnabled(), isTrue);
  });

  test('mobile builds run vote share recovery discovery', () async {
    var discoveryCount = 0;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_FakeAccountNotifier.new),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          discoveryCount++;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);

    final restorer = container.read(votingShareTrackingRestorerProvider);
    await restorer.restore();
    expect(discoveryCount, 1);

    // Backgrounding pauses tracked work so iOS suspension cannot interrupt a
    // share submission mid-flight...
    await restorer.pause();
    final registry = container.read(votingShareTrackingRegistryProvider);
    expect(registry.beginDiscovery(), isNull);

    // ...and foregrounding undoes the quiesce and re-runs discovery.
    await restorer.resume();
    await pumpEventQueue();
    expect(discoveryCount, 2);
  });
}
