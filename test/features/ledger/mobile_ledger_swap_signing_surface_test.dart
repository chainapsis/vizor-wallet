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
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_hardware_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_ledger_completion_service.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_ledger_sign_screen.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_ledger_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

void main() {
  for (final scenario in ['fresh', 'removed', 'cached', 'checkpoint']) {
    final leaveRoute = scenario == 'removed';
    final cached = scenario == 'cached';
    testWidgets('mobile Ledger persists before ack ($scenario)', (
      tester,
    ) async {
      final checkpointGate = scenario == 'checkpoint'
          ? Completer<void>()
          : null;
      final broadcast = Completer<LedgerSignedOperationBroadcastResult>();
      final operationService = _OperationService(
        broadcast.future,
        cachedResult: cached,
        checkpointGate: checkpointGate,
      );
      final persistence = Completer<void>();
      var cancelCalls = 0;
      SwapHardwareBroadcastResult? completed;
      late BuildContext signingContext;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => TextButton(
              onPressed: () async {
                final result = await context.push<MobileSwapLedgerSignSuccess>(
                  '/sign',
                );
                completed = result?.broadcast;
              },
              child: const Text('Open signing'),
            ),
          ),
          GoRoute(
            path: '/sign',
            builder: (context, _) {
              signingContext = context;
              return MobileSwapLedgerSignScreen(
                args: MobileSwapLedgerSignArgs(intent: _intent),
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap),
            ledgerDepositResultPersistenceProvider.overrideWithValue(
              (_, _) => persistence.future,
            ),
            ledgerPcztSignerProvider.overrideWithValue(
              (_, _) async => const [3],
            ),
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

      expect(operationService.checkpointCalls, cached ? 0 : 1);
      expect(
        operationService.broadcastCalls,
        cached || checkpointGate != null ? 0 : 1,
      );
      expect(
        find.text(
          checkpointGate == null && !cached
              ? 'Finishing transaction'
              : 'Finishing transaction',
        ),
        findsOneWidget,
      );
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(
        find.text(
          checkpointGate == null && !cached
              ? 'Finishing transaction'
              : 'Finishing transaction',
        ),
        findsOneWidget,
      );
      expect(cancelCalls, 0);

      final lifecycle = ProviderScope.containerOf(
        signingContext,
      ).read(ledgerOperationLifecycleProvider);
      var drained = false;
      final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
      if (checkpointGate != null) {
        await tester.pump();
        expect(drained, isFalse);
        checkpointGate.complete();
        await tester.pump();
        expect(operationService.broadcastCalls, 1);
        expect(drained, isFalse);
      }
      if (leaveRoute) {
        router.go('/');
        await tester.pumpAndSettle();
      }
      broadcast.complete(
        const LedgerSignedOperationBroadcastResult(
          operationId: 'swap_deposit:account-1:swap-1',
          txid: 'txid-1',
          status: 'broadcasted',
          requiresAck: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(drained, isFalse);
      expect(operationService.acknowledged, isFalse);
      persistence.complete();
      await tester.pumpAndSettle();

      await drain;
      expect(drained, isTrue);
      lifecycle.resume();
      expect(completed?.txHash, leaveRoute ? isNull : 'txid-1');
      expect(operationService.acknowledged, isTrue);
      expect(find.text('Open signing'), findsOneWidget);
    });
  }
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
  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async => SwapHardwarePcztDraft(
    accountUuid: accountUuid,
    pcztBytes: const [1],
    needsSaplingParams: false,
    feeZatoshi: BigInt.one,
    proposalId: BigInt.one,
    sendFlowId: 'flow-1',
  );

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
  Future<List<int>> decodeSigningResponse({
    required SwapHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) => throw StateError('Ledger signing must not decode Keystone responses.');

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
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
    this.cachedResult = false,
    this.checkpointGate,
  });

  final Completer<void>? checkpointGate;

  final bool cachedResult;

  final Future<LedgerSignedOperationBroadcastResult> broadcastResult;
  var checkpointCalls = 0;
  var broadcastCalls = 0;
  var acknowledged = false;

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
    await checkpointGate?.future;
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    broadcastCalls++;
    return broadcastResult;
  }

  @override
  Future<void> acknowledge(String operationId) async {
    acknowledged = true;
  }

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => [
    if (cachedResult)
      const LedgerSignedOperationMetadata(
        operationId: 'swap_deposit:account-1:swap-1',
        accountUuid: 'account-1',
        kind: LedgerSignedOperationKind.swapDeposit,
        externalRef: 'swap-1',
        state: 'result_pending_ack',
        txid: 'txid-1',
        status: 'broadcasted',
      ),
  ];
}
