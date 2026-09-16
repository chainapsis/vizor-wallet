import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(api.reset);

  ProviderContainer container({Future<String> Function()? loadDb}) {
    final result = ProviderContainer(
      overrides: [
        rpcEndpointProvider.overrideWith(_Primary.new),
        syncProvider.overrideWith(_Sync.new),
        ledgerWalletDbPathProvider.overrideWithValue(
          loadDb ?? () async => '/wallet.db',
        ),
        rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
          (_) async => 'main',
        ),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_, _) async => BigInt.from(100),
        ),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  Future<void> failCurrent(ProviderContainer container) async {
    final endpoint = container.read(rpcEndpointFailoverProvider).current;
    expect(
      await container
          .read(rpcEndpointFailoverProvider.notifier)
          .switchToFallbackFor(
            'connection refused',
            endpoint: endpoint,
            operation: 'test',
          ),
      isTrue,
    );
  }

  test(
    'retained service follows fallback and voting observes the same route',
    () async {
      final c = container();
      final service = c.read(ledgerSignedOperationServiceProvider);
      final primary = c.read(rpcEndpointProvider).normalizedLightwalletdUrl;
      await failCurrent(c);
      final fallback = c
          .read(rpcEndpointFailoverProvider)
          .current
          .normalizedLightwalletdUrl;
      expect(fallback, isNot(primary));
      for (final kind in LedgerSignedOperationKind.values) {
        await service.broadcast(operationId: kind.wireName);
      }
      expect(api.urls, List.filled(4, fallback));
      expect(
        c.read(votingRpcEndpointConfigProvider).normalizedLightwalletdUrl,
        fallback,
      );
      await failCurrent(c);
      final next = c
          .read(rpcEndpointFailoverProvider)
          .current
          .normalizedLightwalletdUrl;
      await service.broadcast(operationId: 'recovery');
      expect(api.urls.last, next);
      expect(next, isNot(fallback));
      expect(
        c.read(votingRpcEndpointConfigProvider).normalizedLightwalletdUrl,
        next,
      );
    },
  );

  test('selects route after asynchronous DB loading', () async {
    final db = Completer<String>();
    final c = container(loadDb: () => db.future);
    final pending = c
        .read(ledgerSignedOperationServiceProvider)
        .broadcast(operationId: 'send');
    await failCurrent(c);
    final expected = c
        .read(rpcEndpointFailoverProvider)
        .current
        .normalizedLightwalletdUrl;
    db.complete('/wallet.db');
    await pending;
    expect(api.urls, [expected]);
  });

  test(
    'failure changes route for next attempt without replaying this call',
    () async {
      final c = container();
      final service = c.read(ledgerSignedOperationServiceProvider);
      api.error = StateError('connection refused');
      await expectLater(
        service.broadcast(operationId: 'send'),
        throwsStateError,
      );
      expect(api.urls, [c.read(rpcEndpointProvider).normalizedLightwalletdUrl]);
      expect(c.read(rpcEndpointFailoverProvider).isUsingFallback, isTrue);
      api.error = null;
      await service.broadcast(operationId: 'send');
      expect(
        api.urls.last,
        c.read(rpcEndpointFailoverProvider).current.normalizedLightwalletdUrl,
      );
      expect(api.urls.length, 2);
    },
  );

  for (final status in [
    'broadcast_unknown',
    'partial_broadcast',
    'broadcasted_storage_failed',
  ]) {
    test('$status preserves durable outcome and never replays', () async {
      final c = container();
      api.status = status;
      api.message = 'connection refused';
      final result = await c
          .read(ledgerSignedOperationServiceProvider)
          .broadcast(operationId: 'send');
      expect(api.urls.length, 1);
      expect(result.status, status);
      expect(result.requiresAck, isTrue);
      expect(c.read(rpcEndpointFailoverProvider).isUsingFallback, isTrue);
    });
  }

  test(
    'late failure is attributed to actual endpoint, not new current',
    () async {
      final c = container();
      api.gate = Completer<void>();
      final pending = c
          .read(ledgerSignedOperationServiceProvider)
          .broadcast(operationId: 'send');
      final expectation = expectLater(pending, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await failCurrent(c);
      final fallback = c.read(rpcEndpointFailoverProvider).current;
      api.error = StateError('connection refused');
      api.gate!.complete();
      await expectation;
      expect(c.read(rpcEndpointFailoverProvider).current, same(fallback));
    },
  );

  test(
    'network change rejects retained operation before Rust broadcast',
    () async {
      final service = RustLedgerSignedOperationService(
        network: 'main',
        lightwalletdUrl: 'https://primary.example:443',
        loadWalletDbPath: () async => '/wallet.db',
        readBroadcastEndpoint: () => defaultRpcEndpointConfig('test'),
      );
      await expectLater(
        service.broadcast(operationId: 'send'),
        throwsStateError,
      );
      expect(api.urls, isEmpty);
    },
  );
}

class _Primary extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
}

class _Api extends RustLibApi {
  final urls = <String>[];
  Object? error;
  Completer<void>? gate;
  String status = 'broadcasted';
  String? message;
  void reset() {
    urls.clear();
    error = null;
    gate = null;
    status = 'broadcasted';
    message = null;
  }

  @override
  Future<rust.LedgerSignedOperationBroadcastResult>
  crateApiLedgerLedgerBroadcastSignedOperation({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    urls.add(lightwalletdUrl);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return rust.LedgerSignedOperationBroadcastResult(
      operationId: operationId,
      txid: 'txid',
      status: status,
      message: message,
      requiresAck: status != 'broadcasted',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
  @override
  Future<void> restartSync() async {}
}
