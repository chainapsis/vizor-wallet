import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/home/services/hardware_shielding_session.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  late _Sync sync;
  late LedgerOperationLifecycle lifecycle;
  late HardwareShieldingSession session;
  setUp(() {
    api.reset();
    sync = _Sync();
    lifecycle = LedgerOperationLifecycle();
    session = HardwareShieldingSession(
      accountUuid: 'account-1',
      sync: sync,
      lifecycle: lifecycle,
    );
  });

  Future<ShieldTransparentPcztResult> prepare() => session.prepare(
    dbPath: '/wallet.db',
    lightwalletdUrl: 'https://example.test',
    network: 'mainnet',
  );

  Future<ExtractAndBroadcastPcztResult> broadcast({
    String network = 'mainnet',
  }) => session.broadcast(
    dbPath: '/wallet.db',
    lightwalletdUrl: 'https://example.test',
    network: network,
    proofs: [1],
    signatures: [2],
  );

  test(
    'cancel drains late creation and releases its exact owner once',
    () async {
      final creating = prepare();
      final closing = session.close();
      expect(api.discarded, isEmpty);
      api.created.complete(_prepared);
      await creating;
      expect(await closing, isTrue);
      expect(await session.close(), isTrue);
      expect(api.discarded, [(BigInt.from(77), api.flow)]);
      expect(sync.refreshed, ['account-1']);
      await expectLater(broadcast(), throwsStateError);
      expect(api.broadcasts, 0);
    },
  );

  test(
    'dispose while saving preserves a completed signed checkpoint',
    () async {
      api.created.complete(_prepared);
      await prepare();
      final save = Completer<void>();
      final saving = session.checkpoint(() => save.future);
      final closing = session.close();
      save.complete();
      await saving;
      expect(await closing, isTrue);
      expect(api.discarded, isEmpty);
      expect(sync.refreshed, isEmpty);
    },
  );

  test('failed checkpoint leaves its process reservation releasable', () async {
    api.created.complete(_prepared);
    await prepare();
    final save = Completer<void>();
    final saving = session.checkpoint(() => save.future);
    final failure = expectLater(saving, throwsStateError);
    final closing = session.close();
    save.completeError(StateError('disk full'));
    await failure;
    expect(await closing, isTrue);
    expect(api.discarded, [(BigInt.from(77), session.flowId)]);
  });

  test(
    'cancel waits for a submitted broadcast outcome before cleanup',
    () async {
      api.created.complete(_prepared);
      await prepare();
      final sending = broadcast();
      final closing = session.close();
      await pumpEventQueue();
      expect(api.discarded, isEmpty);
      api.broadcasted.complete(
        const StoreAndBroadcastPcztsResult(
          txids: 'tx',
          status: 'broadcast_unknown',
          broadcastedCount: 0,
          totalCount: 1,
        ),
      );
      expect((await sending).status, 'broadcast_unknown');
      expect(await closing, isTrue);
      // Rust decides whether this owner is durable; cleanup never cancels HTTP.
      expect(api.discarded, [(BigInt.from(77), session.flowId)]);
    },
  );

  test('database or network changes cannot reuse a reservation', () async {
    api.created.complete(_prepared);
    await prepare();
    await expectLater(broadcast(network: 'testnet'), throwsStateError);
    await expectLater(
      session.prepare(
        dbPath: '/another.db',
        lightwalletdUrl: 'https://example.test',
        network: 'mainnet',
      ),
      throwsStateError,
    );
    expect(api.broadcasts, 0);
    expect(await session.close(), isTrue);
  });

  test(
    'wallet deletion drains creation and blocks subsequent DB cleanup',
    () async {
      final creating = prepare();
      final draining = lifecycle.quiesceAndDrain();
      final closing = session.close();
      api.created.complete(_prepared);
      await creating;
      await draining;
      expect(await closing, isFalse);
      expect(api.discarded, isEmpty);
      lifecycle.resume();
      expect(await session.close(), isTrue);
    },
  );

  test('failed balance reconciliation can be retried after release', () async {
    api.created.complete(_prepared);
    await prepare();
    sync.fail = true;
    expect(await session.close(), isFalse);
    sync.fail = false;
    expect(await session.close(), isTrue);
    expect(api.discarded.length, 2);
  });
}

final _prepared = ShieldTransparentPcztResult(
  proposalId: BigInt.from(77),
  pcztBytes: Uint8List.fromList([1]),
  feeZatoshi: BigInt.from(10000),
  shieldedZatoshi: BigInt.from(90000),
  needsSaplingParams: false,
);

class _Sync extends SyncNotifier {
  final refreshed = <String>[];
  bool fail = false;
  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {
    if (fail) throw StateError('refresh unavailable');
    refreshed.add(accountUuid);
  }
}

class _Api extends RustLibApi {
  var created = Completer<ShieldTransparentPcztResult>();
  var broadcasted = Completer<StoreAndBroadcastPcztsResult>();
  final discarded = <(BigInt, String)>[];
  String? flow;
  int broadcasts = 0;
  void reset() {
    created = Completer<ShieldTransparentPcztResult>();
    broadcasted = Completer<StoreAndBroadcastPcztsResult>();
    discarded.clear();
    flow = null;
    broadcasts = 0;
  }

  @override
  Future<ShieldTransparentPcztResult> crateApiSyncCreateShieldTransparentPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String sendFlowId,
  }) {
    flow = sendFlowId;
    return created.future;
  }

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async => discarded.add((proposalId, sendFlowId));
  @override
  Future<StoreAndBroadcastPcztsResult>
  crateApiSyncStoreAndBroadcastSignedPcztsForProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
    required List<Uint8List> pcztWithProofs,
    required List<Uint8List> pcztWithSignatures,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    expect((proposalId, sendFlowId), (BigInt.from(77), flow));
    broadcasts++;
    return broadcasted.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
