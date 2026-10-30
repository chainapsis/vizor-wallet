import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/activity/public_details_load.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/public_details_loads_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

class _Route extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() => const RpcEndpointFailoverState(
    primary: RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://primary.example:443',
    ),
    // Sync switched to a working fallback after the primary failed.
    current: RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://Fallback.example',
    ),
    fallbackCandidates: [],
  );
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  void lockWallet() => state = state.copyWith(isUnlocked: false);
}

class _Call {
  _Call(this.lightwalletdUrl, this.cancelEpoch);
  final String lightwalletdUrl;
  final BigInt cancelEpoch;
}

void main() {
  late List<_Call> calls;
  late int rustCancels;
  late BigInt rustEpoch;
  late ProviderContainer container;

  setUp(() {
    calls = [];
    rustCancels = 0;
    rustEpoch = BigInt.from(7);
    container = ProviderContainer(
      overrides: [
        rpcEndpointFailoverProvider.overrideWith(_Route.new),
        appSecurityProvider.overrideWith(_Security.new),
        publicDetailsLoadsProvider.overrideWithValue(
          PublicDetailsLoads(
            cancelInRust: () {
              rustCancels++;
              rustEpoch += BigInt.one;
            },
            epochInRust: () => rustEpoch,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> enhance({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
    required String accountUuid,
    required String txidHex,
    required BigInt cancelEpoch,
  }) async {
    calls.add(_Call(lightwalletdUrl, cancelEpoch));
  }

  Future<void> load({Future<String?> Function()? dbPath}) =>
      loadTransactionDetailsPublicly(
        container.read,
        accountUuid: 'account-1',
        txidHex: 'ab' * 32,
        existingWalletDbPath: dbPath ?? () async => '/wallet.db',
        enhance: enhance,
      );

  test('uses the endpoint sync currently uses, normalized', () async {
    await load();
    expect(calls.single.lightwalletdUrl, 'https://fallback.example:443');
  });

  test('passes the cancellation epoch read when the load registered', () async {
    final path = Completer<String?>();
    final running = load(dbPath: () => path.future);
    // A cancellation with nothing registered moves no epoch; this load's
    // epoch was read when it registered.
    rustEpoch = BigInt.from(9);
    path.complete('/wallet.db');
    await running;
    expect(calls.single.cancelEpoch, BigInt.from(7));
  });

  test('a lock while the wallet path is read sends nothing', () async {
    final path = Completer<String?>();
    var followups = 0;
    container.listen(syncFollowupProvider, (_, _) => followups++);
    final running = load(dbPath: () => path.future);
    await pumpEventQueue();

    (container.read(appSecurityProvider.notifier) as _Security).lockWallet();
    container.read(publicDetailsLoadsProvider).cancel();
    expect(rustCancels, 1, reason: 'Rust is told even before the load');
    path.complete('/wallet.db');

    await expectLater(running, throwsStateError);
    expect(calls, isEmpty, reason: 'the native load never starts');
    expect(followups, 0);
  });

  test('a locked wallet starts nothing', () async {
    (container.read(appSecurityProvider.notifier) as _Security).lockWallet();
    await expectLater(load(), throwsStateError);
    expect(calls, isEmpty);
  });

  test('a stored result reloads receipts and Activity feeds', () async {
    var followups = 0;
    container.listen(syncFollowupProvider, (_, _) => followups++);
    await load();
    expect(followups, 1);
  });

  test('a failed load notifies nothing', () async {
    var followups = 0;
    container.listen(syncFollowupProvider, (_, _) => followups++);
    await expectLater(
      loadTransactionDetailsPublicly(
        container.read,
        accountUuid: 'account-1',
        txidHex: 'ab' * 32,
        existingWalletDbPath: () async => '/wallet.db',
        enhance:
            ({
              required dbPath,
              required network,
              required lightwalletdUrl,
              required accountUuid,
              required txidHex,
              required cancelEpoch,
            }) async => throw StateError('lookup failed'),
      ),
      throwsStateError,
    );
    expect(followups, 0);
  });
}
