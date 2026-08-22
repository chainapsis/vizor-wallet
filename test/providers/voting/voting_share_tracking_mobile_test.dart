@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_restorer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mobile unlock starts persisted vote share recovery', () async {
    var discoveryCount = 0;
    final security = _MobileVotingSecurityNotifier(
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: false),
    );
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(() => security),
        accountProvider.overrideWith(_MobileVotingAccountNotifier.new),
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

    container.read(votingShareTrackingRestorerProvider);
    await pumpEventQueue();
    expect(discoveryCount, 0);

    security.setUnlocked(true);
    await pumpEventQueue();

    expect(discoveryCount, 1);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await pumpEventQueue();

    expect(discoveryCount, 2);
  });
}

class _MobileVotingAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
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

class _MobileVotingSecurityNotifier extends AppSecurityNotifier {
  _MobileVotingSecurityNotifier(this.initialState);

  final AppSecurityState initialState;

  @override
  AppSecurityState build() => initialState;

  void setUnlocked(bool value) {
    state = state.copyWith(isUnlocked: value);
  }
}
