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
import 'package:zcash_wallet/src/features/ledger/ledger_error_messages.dart';
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
  for (final counts in [
    [10, 0],
    [11, 1, 1, 0],
    [23, 13, 13, 3, 3, 0],
  ]) {
    testWidgets('shields in bounded rounds: $counts', (tester) async {
      final operations = _FakeLedgerSignedOperationService();
      var completed = false;
      var reads = 0;
      await tester.pumpWidget(
        _harness(
          operationService: operations,
          sync: _FakeSyncNotifier(),
          ledgerSigner: (_) async => [7, 8, 9],
          onComplete: () => completed = true,
          progressReader:
              ({
                required dbPath,
                required network,
                required accountUuid,
              }) async => LedgerShieldingProgress(
                inputCount: counts[reads++],
                inputLimit: 10,
                belowThreshold: false,
              ),
        ),
      );
      await _pumpUntil(tester, () => completed);
      expect(completed, isTrue);
      expect(operations.broadcasts.length, counts.length ~/ 2);
      expect(
        operations.checkpoints.map((c) => c.operationId).toSet().length,
        counts.length ~/ 2,
      );
    });
  }

  for (final problem in ['unchanged', 'unknown', 'below threshold']) {
    testWidgets('pauses shielding for $problem remainder', (tester) async {
      final operations = _FakeLedgerSignedOperationService();
      var reads = 0;
      await tester.pumpWidget(
        _harness(
          operationService: operations,
          sync: _FakeSyncNotifier(),
          ledgerSigner: (_) async => [7, 8, 9],
          onComplete: () => fail('must not report completion'),
          progressReader:
              ({
                required dbPath,
                required network,
                required accountUuid,
              }) async {
                if (++reads > 1 && problem == 'unknown') {
                  throw StateError('DB unavailable');
                }
                return LedgerShieldingProgress(
                  inputCount: 11,
                  inputLimit: 10,
                  belowThreshold: reads > 1 && problem == 'below threshold',
                );
              },
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Shielding paused').evaluate().isNotEmpty,
      );
      expect(find.text('Shielding paused'), findsOneWidget);
      expect(operations.broadcasts, hasLength(1));
      expect(find.text('Try again'), findsNothing);
    });
  }

  testWidgets('checkpoint retry retains signature and operation identity', (
    tester,
  ) async {
    final operations = _FakeLedgerSignedOperationService()
      ..failCheckpointOnce = true;
    var signatures = 0;
    var completed = false;
    await tester.pumpWidget(
      _harness(
        operationService: operations,
        sync: _FakeSyncNotifier(),
        ledgerSigner: (_) async {
          signatures++;
          return [7, 8, 9];
        },
        onComplete: () => completed = true,
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('Try again').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Try again'));
    await _pumpUntil(tester, () => completed);
    expect(completed, isTrue);
    expect(signatures, 1);
    expect(operations.checkpoints, hasLength(2));
    expect(
      operations.checkpoints.first.operationId,
      operations.checkpoints.last.operationId,
    );
    expect(operations.broadcasts, hasLength(1));
  });
  testWidgets('status 0x6a80 asks for a new request without blaming the user', (
    tester,
  ) async {
    final operations = _FakeLedgerSignedOperationService();
    var signatures = 0;
    await tester.pumpWidget(
      _harness(
        operationService: operations,
        sync: _FakeSyncNotifier(),
        ledgerSigner: (_) async {
          signatures++;
          throw StateError(
            'ledger_status_6a80: Ledger rejected the PCZT data or key path',
          );
        },
        onComplete: () => fail('must not complete'),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text(kLedgerHostRequestRejectedMessage).evaluate().isNotEmpty,
    );

    expect(find.text('Ledger signing failed'), findsOneWidget);
    expect(find.textContaining('rejected on your Ledger'), findsNothing);
    expect(
      find.byKey(const ValueKey('ledger_device_app_prompt_mainnet')),
      findsNothing,
    );
    expect(find.text('Try again'), findsNothing);
    expect(signatures, 1);
    expect(operations.checkpoints, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
    'status 0x6a80 after a broadcast round does not claim nothing was sent',
    (tester) async {
      final operations = _FakeLedgerSignedOperationService();
      var signatures = 0;
      var reads = 0;
      await tester.pumpWidget(
        _harness(
          operationService: operations,
          sync: _FakeSyncNotifier(),
          ledgerSigner: (_) async {
            if (++signatures == 2) {
              throw StateError(
                'ledger_status_6a80: Ledger rejected the PCZT data or key path',
              );
            }
            return [7, 8, 9];
          },
          onComplete: () => fail('must not complete'),
          progressReader:
              ({
                required dbPath,
                required network,
                required accountUuid,
              }) async => LedgerShieldingProgress(
                inputCount: reads++ == 0 ? 11 : 1,
                inputLimit: 10,
                belowThreshold: false,
              ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find
            .textContaining('earlier approvals in this session')
            .evaluate()
            .isNotEmpty,
      );

      expect(signatures, 2);
      expect(operations.broadcasts, hasLength(1));
      expect(find.text(kLedgerHostRequestRejectedMessage), findsNothing);
      expect(find.textContaining('Nothing was sent'), findsNothing);
      expect(find.text('Try again'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'cancelling a rejected second round preserves the first broadcast',
    (tester) async {
      final operations = _FakeLedgerSignedOperationService();
      var signatures = 0;
      var cancelled = false;
      var reads = 0;
      await tester.pumpWidget(
        _harness(
          operationService: operations,
          sync: _FakeSyncNotifier(),
          ledgerSigner: (_) async {
            if (++signatures == 2) throw StateError(_deviceRejected);
            return [7, 8, 9];
          },
          onComplete: () => fail('must not complete'),
          onCancel: () => cancelled = true,
          progressReader:
              ({
                required dbPath,
                required network,
                required accountUuid,
              }) async => LedgerShieldingProgress(
                inputCount: reads++ == 0 ? 11 : 1,
                inputLimit: 10,
                belowThreshold: false,
              ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Try again').evaluate().isNotEmpty,
      );
      expect(signatures, 2);
      expect(operations.broadcasts, hasLength(1));
      await tester.tap(find.text('Back to wallet'));
      await tester.pump();
      expect(cancelled, isTrue);
      expect(operations.broadcasts, hasLength(1));
    },
  );

  testWidgets(
    'broadcast retry reuses the checkpoint without another approval',
    (tester) async {
      final operations = _FakeLedgerSignedOperationService()
        ..failBroadcastOnce = true;
      var signatures = 0;
      var completed = false;
      await tester.pumpWidget(
        _harness(
          operationService: operations,
          sync: _FakeSyncNotifier(),
          ledgerSigner: (_) async {
            signatures++;
            return [7, 8, 9];
          },
          onComplete: () => completed = true,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Try again').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Try again'));
      await _pumpUntil(tester, () => completed);
      expect(completed, isTrue);
      expect(signatures, 1);
      expect(operations.checkpoints, hasLength(1));
      expect(operations.broadcasts, hasLength(2));
      expect(operations.broadcasts.toSet(), hasLength(1));
    },
  );
  testWidgets(
    'account change while signing cannot checkpoint or retry the old request',
    (tester) async {
      final operations = _FakeLedgerSignedOperationService();
      final signed = Completer<List<int>>();
      var started = false;
      await tester.pumpWidget(
        _harness(
          operationService: operations,
          sync: _FakeSyncNotifier(),
          ledgerSigner: (_) {
            started = true;
            return signed.future;
          },
          onComplete: () => fail('must not complete'),
        ),
      );
      await _pumpUntil(tester, () => started);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LedgerShieldSigningOverlay)),
      );
      (container.read(walletProvider.notifier) as _FakeWalletNotifier)
          .switchForTest();
      signed.complete([7, 8, 9]);
      await _pumpUntil(
        tester,
        () => find.text('Try again').evaluate().isNotEmpty,
      );
      expect(operations.checkpoints, isEmpty);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Shielding paused'), findsOneWidget);
      expect(operations.checkpoints, isEmpty);
      expect(operations.broadcasts, isEmpty);
    },
  );
}

Widget _harness({
  required _FakeLedgerSignedOperationService operationService,
  required _FakeSyncNotifier sync,
  required Future<List<int>> Function(List<int> pcztBytes) ledgerSigner,
  required VoidCallback onComplete,
  LedgerShieldingProgressReader? progressReader,
  VoidCallback? onCancel,
}) {
  return ProviderScope(
    overrides: [
      if (progressReader != null)
        ledgerShieldingProgressReaderProvider.overrideWithValue(progressReader),
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
      home: LedgerShieldSigningOverlay(
        onCancel: onCancel ?? () {},
        onComplete: onComplete,
      ),
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
  void switchForTest() => state = const AsyncData(
    WalletState(
      hasWallet: true,
      unifiedAddress: 'u1other',
      network: 'main',
      activeAccountUuid: 'account-2',
    ),
  );

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
  bool failCheckpointOnce = false;
  bool failBroadcastOnce = false;
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
    if (failCheckpointOnce) {
      failCheckpointOnce = false;
      throw StateError('Temporary checkpoint failure');
    }
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts.add(operationId);
    if (failBroadcastOnce) {
      failBroadcastOnce = false;
      throw StateError('temporary broadcast error');
    }
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
  Future<LedgerShieldingProgress> crateApiSyncGetLedgerShieldingProgress({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => LedgerShieldingProgress(
    inputCount: createShieldCalls == 0 ? 1 : 0,
    inputLimit: 10,
    belowThreshold: false,
  );

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

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

const _deviceRejected =
    'ledger_status_6985: Ledger request was rejected or the PCZT was not finalized';
