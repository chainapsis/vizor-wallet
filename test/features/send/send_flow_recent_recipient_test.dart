// path_provider / plugin platform fakes back the broadcast flow's wallet DB
// path resolution.
// ignore_for_file: depend_on_referenced_packages
@Tags(['mobile'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/send/services/recent_send_recipients.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

const _account = 'test-account';
const _recipient = 'u1recipient000000000000000000000000000000';

void main() {
  final rustApi = _ProposalRustApi();
  setUpAll(() => RustLib.initMock(api: rustApi));
  tearDownAll(RustLib.dispose);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('send_recents_test');
    addTearDown(() => root.delete(recursive: true));
    PathProviderPlatform.instance = _FakePathProviderPlatform(root.path);
  });

  Future<_MemoryRecentStore> broadcast(
    WidgetTester tester, {
    String status = 'broadcasted',
    bool keystone = false,
    bool software = false,
    SendFlowKind flowKind = SendFlowKind.send,
    bool isPaymentRequest = false,
  }) async {
    rustApi.status = status;
    final store = _MemoryRecentStore();
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrap(isHardware: !software),
          ),
          accountProvider.overrideWith(_FakeAccountNotifier.new),
          appSecurityProvider.overrideWith(_FakeAppSecurityNotifier.new),
          syncProvider.overrideWith(_FakeSyncNotifier.new),
          ledgerSignedOperationServiceProvider.overrideWithValue(
            _FakeLedgerSignedOperationService(status),
          ),
          sendRecentRecipientStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          home: Consumer(
            builder: (_, ref, _) {
              widgetRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final args = SendReviewArgs(
      proposalId: BigInt.one,
      sendFlowId: 'test-send-flow',
      proposalAccountUuid: _account,
      address: _recipient,
      addressType: 'unified',
      amountZatoshi: BigInt.from(100000),
      feeZatoshi: BigInt.from(10000),
      needsSaplingParams: false,
      flowKind: flowKind,
      isPaymentRequest: isPaymentRequest,
    );
    await tester.runAsync(
      () => runSendBroadcast(
        ref: widgetRef,
        args: args,
        keystone: keystone
            ? KeystoneBroadcastArgs(
                reviewArgs: args,
                pcztWithProofs: const [
                  [3, 3, 3],
                ],
                pcztWithSignatures: const [
                  [9, 9],
                ],
              )
            : null,
        ledger: keystone || software
            ? null
            : LedgerBroadcastArgs(
                reviewArgs: args,
                operationId: 'send:$_account:test-send-flow',
              ),
        confirmSaplingParamsDownload: () async => false,
      ),
    );
    return store;
  }

  for (final keystone in [false, true]) {
    final wallet = keystone ? 'Keystone' : 'Ledger';

    testWidgets('a completed $wallet send records its recipient', (
      tester,
    ) async {
      final store = await broadcast(tester, keystone: keystone);

      expect(store.records, [(_account, _recipient, true)]);
    });

    testWidgets('a $wallet send that is still queued records nothing', (
      tester,
    ) async {
      final status = keystone ? 'partial_broadcast' : 'pending';
      final store = await broadcast(tester, keystone: keystone, status: status);

      expect(store.records, isEmpty);
    });
  }

  testWidgets('a completed software send records its recipient', (
    tester,
  ) async {
    final store = await broadcast(tester, software: true);

    expect(store.records, [(_account, _recipient, true)]);
  });

  testWidgets('an expired send records nothing', (tester) async {
    final store = await broadcast(tester, status: 'expired');

    expect(store.records, isEmpty);
  });

  testWidgets('a donation records nothing', (tester) async {
    final store = await broadcast(tester, flowKind: SendFlowKind.donation);

    expect(store.records, isEmpty);
  });

  testWidgets('a payment request records nothing', (tester) async {
    final store = await broadcast(tester, isPaymentRequest: true);

    expect(store.records, isEmpty);
  });
}

class _MemoryRecentStore implements SendRecentRecipientStore {
  final records = <(String, String, bool)>[];

  @override
  Future<List<SendRecentRecipient>> load({required String accountUuid}) async =>
      const [];

  @override
  Future<void> record({
    required String accountUuid,
    required SendRecentRecipient recipient,
  }) async {
    records.add((accountUuid, recipient.address, recipient.isShielded));
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {}
}

AppBootstrapState _bootstrap({required bool isHardware}) {
  return AppBootstrapState(
    initialLocation: '/send/status',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: _account,
          name: 'Account 1',
          order: 0,
          isHardware: isHardware,
        ),
      ],
      activeAccountUuid: _account,
      activeAddress: 'u1activeaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

class _FakeAccountNotifier extends AccountNotifier {
  // The send path zeroizes the buffer, so each request gets a fresh one.
  @override
  Future<Uint8List?> getMnemonicBytesForAccount(String uuid) async =>
      Uint8List.fromList(const [1, 2, 3]);
}

class _FakeAppSecurityNotifier extends AppSecurityNotifier {
  @override
  String requireSessionPasswordForNativeSecretUse() => 'test-password';
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async =>
      SyncState(accountUuid: _account, hasAccountScopedData: true);

  @override
  Future<void> refreshAfterSend() async {}

  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {}

  @override
  Future<void> restartSync() async {}
}

class _FakeLedgerSignedOperationService
    implements LedgerSignedOperationService {
  _FakeLedgerSignedOperationService(this.status);

  final String status;

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {}

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => const [];

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => LedgerSignedOperationBroadcastResult(
    operationId: operationId,
    txid: 'aa' * 32,
    status: status,
    requiresAck: false,
  );

  @override
  Future<void> acknowledge(String operationId) async {}
}

// Ledger broadcasts through the signed-operation service; Keystone and
// software sends broadcast through Rust.
class _ProposalRustApi extends Fake implements RustLibApi {
  String status = 'broadcasted';

  ExecuteProposalResult get _executed => ExecuteProposalResult(
    txids: 'aa' * 32,
    status: status,
    broadcastedCount: status == 'broadcasted' ? 1 : 0,
    totalCount: 1,
  );

  @override
  Future<ExecuteProposalResult> crateApiSyncExecuteProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required BigInt proposalId,
    required String sendFlowId,
    required List<int> mnemonicBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => _executed;

  @override
  Future<ExecuteProposalResult>
  crateApiSyncExecuteProposalWithMacosStoredMnemonic({
    required String dbPath,
    required String lightwalletdUrl,
    required BigInt proposalId,
    required String sendFlowId,
    required String password,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => _executed;

  @override
  Future<StoreAndBroadcastPcztsResult>
  crateApiSyncStoreAndBroadcastPcztsWithKeystoneSignaturesForProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
    required List<Uint8List> pcztWithProofs,
    required List<Uint8List> signatureBlobs,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => StoreAndBroadcastPcztsResult(
    txids: 'aa' * 32,
    status: status,
    broadcastedCount: status == 'broadcasted' ? 1 : 0,
    totalCount: 1,
  );

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {}

  @override
  Future<void> crateApiSyncRetainProposalLockUntilExpiry({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {}
}

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
