// path_provider and flutter_secure_storage fakes back the wallet DB path used
// while preparing the shield PCZT.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
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
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/widgets/ledger_shield_signing_overlay.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  final rustApi = _RustApiFake();
  late PathProviderPlatform originalPathProvider;

  setUpAll(() {
    RustLib.initMock(api: rustApi);
  });

  tearDownAll(RustLib.dispose);

  setUp(() async {
    rustApi.reset();
    FlutterSecureStorage.setMockInitialValues({});
    originalPathProvider = PathProviderPlatform.instance;
    final tempDir = await Directory.systemTemp.createTemp(
      'ledger_shield_overlay_test',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    addTearDown(() async {
      PathProviderPlatform.instance = originalPathProvider;
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
  });

  testWidgets('checkpoints Ledger shield signatures before broadcasting', (
    tester,
  ) async {
    final operationService = _FakeLedgerSignedOperationService();
    final sync = _FakeSyncNotifier();
    final signerInputs = <List<int>>[];
    var completed = false;

    await tester.pumpWidget(
      _harness(
        operationService: operationService,
        sync: sync,
        ledgerSigner: (pcztBytes) async {
          signerInputs.add([...pcztBytes]);
          return [7, 8, 9];
        },
        onComplete: () => completed = true,
      ),
    );
    await tester.pump();

    for (var i = 0; i < 100 && !completed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }

    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .join(' | ');
    expect(
      completed,
      isTrue,
      reason:
          'create=${rustApi.createShieldCalls}, '
          'proofs=${rustApi.addProofsCalls}, '
          'checkpoints=${operationService.checkpoints.length}, '
          'broadcasts=${operationService.broadcasts.length}, '
          'text=$visibleText',
    );
    expect(rustApi.createShieldCalls, 1);
    expect(rustApi.addProofsCalls, 1);
    expect(signerInputs, [
      [1, 2, 3],
    ]);
    expect(operationService.checkpoints, hasLength(1));
    final checkpoint = operationService.checkpoints.single;
    expect(checkpoint.operationId, startsWith('shield:account-1:'));
    expect(checkpoint.accountUuid, 'account-1');
    expect(checkpoint.kind, LedgerSignedOperationKind.shield);
    expect(checkpoint.proofs, [4, 5, 6]);
    expect(checkpoint.signatures, [7, 8, 9]);
    expect(operationService.broadcasts, [checkpoint.operationId]);
    expect(operationService.acknowledged, isEmpty);
    expect(sync.refreshCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Widget _harness({
  required _FakeLedgerSignedOperationService operationService,
  required _FakeSyncNotifier sync,
  required Future<List<int>> Function(List<int> pcztBytes) ledgerSigner,
  required VoidCallback onComplete,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      walletProvider.overrideWith(_FakeWalletNotifier.new),
      syncProvider.overrideWith(() => sync),
      ledgerPcztSignerProvider.overrideWithValue(
        (_, pcztBytes) => ledgerSigner(pcztBytes),
      ),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      ledgerSignedOperationServiceProvider.overrideWithValue(operationService),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: LedgerShieldSigningOverlay(onCancel: () {}, onComplete: onComplete),
    ),
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

class _FakeWalletNotifier extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(
    hasWallet: true,
    unifiedAddress: 'u1ledger',
    network: 'main',
    activeAccountUuid: 'account-1',
  );
}

class _FakeSyncNotifier extends SyncNotifier {
  int refreshCount = 0;

  @override
  Future<SyncState> build() async =>
      SyncState(accountUuid: 'account-1', hasAccountScopedData: true);

  @override
  Future<void> refreshAfterSend() async {
    refreshCount++;
  }
}

class _Checkpoint {
  const _Checkpoint({
    required this.operationId,
    required this.accountUuid,
    required this.kind,
    required this.proofs,
    required this.signatures,
  });

  final String operationId;
  final String accountUuid;
  final LedgerSignedOperationKind kind;
  final List<int> proofs;
  final List<int> signatures;
}

class _FakeLedgerSignedOperationService
    implements LedgerSignedOperationService {
  final checkpoints = <_Checkpoint>[];
  final broadcasts = <String>[];
  final acknowledged = <String>[];

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => const [];

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    checkpoints.add(
      _Checkpoint(
        operationId: operationId,
        accountUuid: accountUuid,
        kind: kind,
        proofs: [...pcztWithProofsBytes],
        signatures: [...pcztWithSignaturesBytes],
      ),
    );
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts.add(operationId);
    return LedgerSignedOperationBroadcastResult(
      operationId: operationId,
      txid: 'txid-1',
      status: 'broadcasted',
      requiresAck: false,
    );
  }

  @override
  Future<void> acknowledge(String operationId) async {
    acknowledged.add(operationId);
  }
}

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _RustApiFake implements RustLibApi {
  int createShieldCalls = 0;
  int addProofsCalls = 0;

  void reset() {
    createShieldCalls = 0;
    addProofsCalls = 0;
  }

  @override
  Future<ShieldTransparentPcztResult> crateApiSyncCreateShieldTransparentPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
  }) async {
    createShieldCalls++;
    return ShieldTransparentPcztResult(
      pcztBytes: Uint8List.fromList([1, 2, 3]),
      feeZatoshi: BigInt.from(10_000),
      shieldedZatoshi: BigInt.from(99_990_000),
      needsSaplingParams: false,
    );
  }

  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    addProofsCalls++;
    expect(pcztBytes, [1, 2, 3]);
    return Uint8List.fromList([4, 5, 6]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
