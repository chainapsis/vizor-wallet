import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_recovery.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';

void main() {
  test(
    'recovery broadcasts a pending send without device interaction',
    () async {
      final operationService = _FakeLedgerSignedOperationService([
        _operation(kind: LedgerSignedOperationKind.send),
      ]);
      final sync = _RecoverySyncNotifier();
      final recoveredDeposits = <String>[];
      final container = _container(
        operationService: operationService,
        sync: sync,
        recoveredDeposits: recoveredDeposits,
      );
      addTearDown(container.dispose);
      await container.read(walletProvider.future);

      await container
          .read(ledgerOperationRecoveryCoordinatorProvider)
          .recover();

      expect(operationService.broadcasts, ['operation-1']);
      expect(operationService.acknowledged, isEmpty);
      expect(recoveredDeposits, isEmpty);
      expect(sync.refreshCount, 1);
    },
  );

  test(
    'recovery checkpoints a saved swap result before acknowledging',
    () async {
      final operationService = _FakeLedgerSignedOperationService([
        _operation(
          kind: LedgerSignedOperationKind.swapDeposit,
          state: 'result_pending_ack',
          externalRef: 'intent-1',
          txid: 'txid-1',
          status: 'broadcasted',
        ),
      ]);
      final recoveredDeposits = <String>[];
      final container = _container(
        operationService: operationService,
        sync: _RecoverySyncNotifier(),
        recoveredDeposits: recoveredDeposits,
      );
      addTearDown(container.dispose);
      await container.read(walletProvider.future);

      await container
          .read(ledgerOperationRecoveryCoordinatorProvider)
          .recover();

      expect(operationService.broadcasts, isEmpty);
      expect(recoveredDeposits, ['intent-1:txid-1']);
      expect(operationService.acknowledged, ['operation-1']);
    },
  );

  test('recovery keeps swap result when activity checkpoint fails', () async {
    final operationService = _FakeLedgerSignedOperationService([
      _operation(
        kind: LedgerSignedOperationKind.payDeposit,
        state: 'result_pending_ack',
        externalRef: 'intent-1',
        txid: 'txid-1',
        status: 'broadcasted',
      ),
    ]);
    final container = _container(
      operationService: operationService,
      sync: _RecoverySyncNotifier(),
      depositRecovery: ({required operation, required result}) async {
        throw StateError('activity storage unavailable');
      },
    );
    addTearDown(container.dispose);
    await container.read(walletProvider.future);

    await container.read(ledgerOperationRecoveryCoordinatorProvider).recover();

    expect(operationService.acknowledged, isEmpty);
  });
}

ProviderContainer _container({
  required _FakeLedgerSignedOperationService operationService,
  required _RecoverySyncNotifier sync,
  List<String>? recoveredDeposits,
  LedgerDepositRecovery? depositRecovery,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ledgerSignedOperationServiceProvider.overrideWithValue(operationService),
      syncProvider.overrideWith(() => sync),
      ledgerDepositRecoveryProvider.overrideWithValue(
        depositRecovery ??
            ({required operation, required result}) async {
              recoveredDeposits?.add('${operation.externalRef}:${result.txid}');
            },
      ),
    ],
  );
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: AccountState(
      accounts: const [
        AccountInfo(
          uuid: 'account-1',
          name: 'Ledger',
          order: 0,
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1ledger',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

LedgerSignedOperationMetadata _operation({
  required LedgerSignedOperationKind kind,
  String state = 'signed_pending_broadcast',
  String? externalRef,
  String? txid,
  String? status,
}) {
  return LedgerSignedOperationMetadata(
    operationId: 'operation-1',
    accountUuid: 'account-1',
    kind: kind,
    externalRef: externalRef,
    state: state,
    txid: txid,
    status: status,
  );
}

class _FakeLedgerSignedOperationService
    implements LedgerSignedOperationService {
  _FakeLedgerSignedOperationService(this.operations);

  final List<LedgerSignedOperationMetadata> operations;
  final broadcasts = <String>[];
  final acknowledged = <String>[];

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => operations;

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts.add(operationId);
    final operation = operations.singleWhere(
      (candidate) => candidate.operationId == operationId,
    );
    return LedgerSignedOperationBroadcastResult(
      operationId: operationId,
      txid: operation.txid ?? 'txid-1',
      status: operation.status ?? 'broadcasted',
      requiresAck:
          operation.kind == LedgerSignedOperationKind.swapDeposit ||
          operation.kind == LedgerSignedOperationKind.payDeposit,
    );
  }

  @override
  Future<void> acknowledge(String operationId) async {
    acknowledged.add(operationId);
  }

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) => throw UnimplementedError();
}

class _RecoverySyncNotifier extends SyncNotifier {
  int refreshCount = 0;

  @override
  Future<SyncState> build() async =>
      SyncState(accountUuid: 'account-1', hasAccountScopedData: true);

  @override
  Future<void> refreshAfterSend() async {
    refreshCount++;
  }
}
