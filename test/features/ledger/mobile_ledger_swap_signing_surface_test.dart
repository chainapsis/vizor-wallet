@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_hardware_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_ledger_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

void main() {
  for (final payMode in [false, true]) {
    testWidgets(
      'capacity failure preserves the quote and blocks retry (pay=$payMode)',
      (tester) async {
        final operations = _OperationService(
          Completer<LedgerSignedOperationBroadcastResult>().future,
        );
        final intent = _intent.copyWith(payMode: payMode);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appBootstrapProvider.overrideWithValue(_bootstrap),
              ledgerPcztSignerProvider.overrideWithValue(
                (_, _) async => throw StateError(
                  'Ledger supports at most 32 shielded actions; found 33',
                ),
              ),
              ledgerOperationCancellerProvider.overrideWithValue(() async {}),
              ledgerSignedOperationServiceProvider.overrideWithValue(
                operations,
              ),
              swapHardwareSigningServiceProvider.overrideWithValue(
                _HardwareSigningService(),
              ),
              syncProvider.overrideWith(
                () => FakeSyncNotifier(
                  SyncState(
                    accountUuid: 'account-1',
                    hasAccountScopedData: true,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              builder: (_, child) =>
                  AppTheme(data: AppThemeData.light, child: child!),
              home: SwapLedgerSigningOverlay(
                mobile: true,
                intent: intent,
                onCancel: () {},
                onDepositBroadcast: (_) async =>
                    fail('Oversized deposit must not complete'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ledger requires a smaller transfer'), findsOneWidget);
        expect(
          find.textContaining(
            payMode ? 'Do not send a smaller amount' : 'review the new quote',
          ),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsNothing);
        expect(operations.checkpointCalls, 0);
        expect(operations.broadcastCalls, 0);
        expect(intent.sellAmountBaseUnits, _intent.sellAmountBaseUnits);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('mobile Ledger broadcast blocks back until durable completion', (
    tester,
  ) async {
    final broadcast = Completer<LedgerSignedOperationBroadcastResult>();
    final operationService = _OperationService(broadcast.future);
    var cancelCalls = 0;
    SwapHardwareBroadcastResult? completed;
    late BuildContext signingContext;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => TextButton(
            onPressed: () => context.push('/sign'),
            child: const Text('Open signing'),
          ),
        ),
        GoRoute(
          path: '/sign',
          builder: (context, _) {
            signingContext = context;
            return SwapLedgerSigningOverlay(
              mobile: true,
              intent: _intent,
              onCancel: () => context.pop(),
              onDepositBroadcast: (result) async {
                completed = result;
                if (signingContext.mounted) signingContext.pop();
              },
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap),
          ledgerPcztSignerProvider.overrideWithValue((_, _) async => const [3]),
          ledgerOperationCancellerProvider.overrideWithValue(() async {
            cancelCalls++;
          }),
          ledgerSignedOperationServiceProvider.overrideWithValue(
            operationService,
          ),
          swapHardwareSigningServiceProvider.overrideWithValue(
            _HardwareSigningService(),
          ),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );
    await tester.tap(find.text('Open signing'));
    for (var i = 0; i < 10 && operationService.broadcastCalls == 0; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();

    expect(operationService.checkpointCalls, 1);
    expect(operationService.broadcastCalls, 1);
    expect(find.text('Sending transaction'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    expect(find.text('Sending transaction'), findsOneWidget);
    expect(cancelCalls, 0);

    broadcast.complete(
      const LedgerSignedOperationBroadcastResult(
        operationId: 'swap_deposit:account-1:swap-1',
        txid: 'txid-1',
        status: 'broadcasted',
        requiresAck: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(completed?.txHash, 'txid-1');
    expect(operationService.acknowledged, isTrue);
    expect(find.text('Open signing'), findsOneWidget);
  });

  testWidgets(
    'mobile Ledger swap explains unavailable legacy Orchard recovery',
    (tester) async {
      final operationService = _OperationService(
        Completer<LedgerSignedOperationBroadcastResult>().future,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => TextButton(
              onPressed: () => context.push('/sign'),
              child: const Text('Open signing'),
            ),
          ),
          GoRoute(
            path: '/sign',
            builder: (context, _) => SwapLedgerSigningOverlay(
              mobile: true,
              intent: _intent,
              onCancel: () => context.pop(),
              onDepositBroadcast: (_) async {},
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap),
            ledgerPcztSignerProvider.overrideWithValue(
              (_, _) async => throw StateError(
                '$kLedgerLegacyOrchardRecoveryErrorCode: test fixture',
              ),
            ),
            ledgerOperationCancellerProvider.overrideWithValue(() async {}),
            ledgerSignedOperationServiceProvider.overrideWithValue(
              operationService,
            ),
            swapHardwareSigningServiceProvider.overrideWithValue(
              _HardwareSigningService(),
            ),
            syncProvider.overrideWith(
              () => FakeSyncNotifier(
                SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.tap(find.text('Open signing'));
      await tester.pumpAndSettle();

      expect(find.text('Ledger app update required'), findsOneWidget);
      expect(
        find.text(kLedgerLegacyOrchardRecoveryUnavailableMessage),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      expect(operationService.checkpointCalls, 0);
      expect(operationService.broadcastCalls, 0);
    },
  );

  testWidgets(
    'mobile Ledger swap does not sign after the deposit window closed',
    (tester) async {
      final operations = _OperationService(
        Completer<LedgerSignedOperationBroadcastResult>().future,
      );
      final signing = _HardwareSigningService();
      var signerCalls = 0;
      await tester.pumpWidget(
        _overlayApp(
          intent: _intent.copyWith(
            depositDeadline: DateTime.now().subtract(
              const Duration(minutes: 1),
            ),
          ),
          operations: operations,
          signing: signing,
          signer: (_, _) async {
            signerCalls++;
            return const [3];
          },
          onDepositBroadcast: (_) async =>
              fail('Expired deposit must not send'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deposit window closed'), findsOneWidget);
      expect(find.textContaining('Nothing was sent'), findsWidgets);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Back to activity'), findsOneWidget);
      expect(signing.createCalls, 0);
      expect(signerCalls, 0);
      expect(operations.checkpointCalls, 0);
      expect(operations.broadcastCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile Ledger swap discards a signed deposit whose window closed',
    (tester) async {
      const operationId = 'swap_deposit:account-1:swap-1';
      final operations = _OperationService(
        Completer<LedgerSignedOperationBroadcastResult>().future,
        existing: [
          LedgerSignedOperationMetadata(
            operationId: operationId,
            accountUuid: 'account-1',
            kind: LedgerSignedOperationKind.swapDeposit,
            externalRef: 'swap-1',
            state: 'signed_pending_broadcast',
          ),
        ],
      );
      await tester.pumpWidget(
        _overlayApp(
          intent: _intent.copyWith(
            depositDeadline: DateTime.now().subtract(
              const Duration(minutes: 1),
            ),
          ),
          operations: operations,
          signing: _HardwareSigningService(),
          signer: (_, _) async =>
              fail('A checkpointed deposit is never re-signed'),
          onDepositBroadcast: (_) async =>
              fail('Expired deposit must not send'),
        ),
      );
      await tester.pumpAndSettle();

      expect(operations.discarded, [operationId]);
      expect(operations.broadcastCalls, 0);
      expect(find.text('Deposit window closed'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final payMode in [false, true]) {
    testWidgets(
      'mobile Ledger deposit stays queued when broadcast fails (pay=$payMode)',
      (tester) async {
        final operations = _OperationService(
          Completer<LedgerSignedOperationBroadcastResult>().future,
          broadcastError: StateError('lightwalletd unavailable'),
        );
        await tester.pumpWidget(
          _overlayApp(
            intent: _intent.copyWith(payMode: payMode),
            operations: operations,
            signing: _HardwareSigningService(),
            signer: (_, _) async => const [3],
            onDepositBroadcast: (_) async => fail('Broadcast did not happen'),
          ),
        );
        await tester.pumpAndSettle();

        expect(operations.checkpointCalls, 1);
        expect(operations.broadcastCalls, 1);
        expect(operations.discarded, isEmpty);
        expect(
          find.text(payMode ? 'Payment queued' : 'ZEC deposit queued'),
          findsOneWidget,
        );
        expect(find.text('Will retry'), findsOneWidget);
        expect(find.textContaining('will retry automatically'), findsOneWidget);
        expect(find.text('Ledger signing failed'), findsNothing);
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Back to activity'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'mobile Ledger swap blocks leaving while the deposit checkpoints',
    (tester) async {
      final checkpointGate = Completer<void>();
      final broadcast = Completer<LedgerSignedOperationBroadcastResult>();
      final operations = _OperationService(
        broadcast.future,
        checkpointGate: checkpointGate,
      );
      var cancelCalls = 0;
      SwapHardwareBroadcastResult? completed;
      late BuildContext signingContext;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => TextButton(
              onPressed: () => context.push('/sign'),
              child: const Text('Open signing'),
            ),
          ),
          GoRoute(
            path: '/sign',
            builder: (context, _) {
              signingContext = context;
              return SwapLedgerSigningOverlay(
                mobile: true,
                intent: _intent,
                onCancel: () => context.pop(),
                onDepositBroadcast: (result) async {
                  completed = result;
                  if (signingContext.mounted) signingContext.pop();
                },
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap),
            ledgerPcztSignerProvider.overrideWithValue(
              (_, _) async => const [3],
            ),
            ledgerOperationCancellerProvider.overrideWithValue(() async {
              cancelCalls++;
            }),
            ledgerSignedOperationServiceProvider.overrideWithValue(operations),
            swapHardwareSigningServiceProvider.overrideWithValue(
              _HardwareSigningService(),
            ),
            syncProvider.overrideWith(
              () => FakeSyncNotifier(
                SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.tap(find.text('Open signing'));
      for (var i = 0; i < 10 && operations.checkpointCalls == 0; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();

      // The device has approved but the checkpoint has not landed yet.
      expect(operations.checkpointCalls, 1);
      expect(operations.broadcastCalls, 0);
      expect(find.text('Sending transaction'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(find.text('Sending transaction'), findsOneWidget);
      expect(cancelCalls, 0);

      checkpointGate.complete();
      for (var i = 0; i < 10 && operations.broadcastCalls == 0; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(operations.broadcastCalls, 1);
      broadcast.complete(
        const LedgerSignedOperationBroadcastResult(
          operationId: 'swap_deposit:account-1:swap-1',
          txid: 'txid-1',
          status: 'broadcasted',
          requiresAck: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(completed?.txHash, 'txid-1');
      expect(find.text('Open signing'), findsOneWidget);
    },
  );
}

Widget _overlayApp({
  required SwapIntent intent,
  required _OperationService operations,
  required _HardwareSigningService signing,
  required Future<List<int>> Function(String accountUuid, List<int> pczt)
  signer,
  Future<void> Function(SwapHardwareBroadcastResult)? onDepositBroadcast,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      ledgerPcztSignerProvider.overrideWithValue(signer),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      ledgerSignedOperationServiceProvider.overrideWithValue(operations),
      swapHardwareSigningServiceProvider.overrideWithValue(signing),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      ),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: SwapLedgerSigningOverlay(
        mobile: true,
        intent: intent,
        onCancel: () {},
        onDepositBroadcast: onDepositBroadcast ?? (_) async {},
      ),
    ),
  );
}

final _intent = SwapIntent(
  id: 'swap-1',
  pair: 'ZEC -> USDC',
  sellAmount: '0.003 ZEC',
  receiveEstimate: '0.20 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Deposit ZEC',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1deposit',
  accountUuid: 'account-1',
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Ledger',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1active',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _HardwareSigningService implements SwapHardwareSigningService {
  var createCalls = 0;

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    createCalls++;
    return SwapHardwarePcztDraft(
      pcztBytes: const [1],
      needsSaplingParams: false,
      feeZatoshi: BigInt.one,
      proposalId: BigInt.one,
      sendFlowId: 'flow-1',
    );
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => const [2];

  @override
  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft}) async {}

  @override
  Future<void> settlePcztDraftAfterLedgerBroadcast({
    required SwapHardwarePcztDraft draft,
    required String? status,
  }) async {}

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<List<int>> decodeSigningResponse({
    required SwapHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) => throw UnimplementedError();

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => throw UnimplementedError();
}

class _OperationService implements LedgerSignedOperationService {
  _OperationService(
    this.broadcastResult, {
    this.existing = const [],
    this.checkpointGate,
    this.broadcastError,
  });

  final Future<LedgerSignedOperationBroadcastResult> broadcastResult;
  final List<LedgerSignedOperationMetadata> existing;
  final Completer<void>? checkpointGate;
  final Object? broadcastError;
  var checkpointCalls = 0;
  var broadcastCalls = 0;
  var acknowledged = false;
  final discarded = <String>[];

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    checkpointCalls++;
    final gate = checkpointGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcastCalls++;
    final error = broadcastError;
    if (error != null) throw error;
    return broadcastResult;
  }

  @override
  Future<void> acknowledge(String operationId) async {
    acknowledged = true;
  }

  @override
  Future<void> discard(String operationId) async {
    discarded.add(operationId);
  }

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => existing;
}
