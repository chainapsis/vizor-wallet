import 'package:flutter/services.dart';
import 'dart:io';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_recovery.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_hardware_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_ledger_completion_service.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_ledger_signing_overlay.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

const _captureBoundaryKey = ValueKey('ledger_repro_capture');

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final error in <Object>[
    const LedgerMobileException(
      LedgerMobileFailure.pairingInvalid,
      'pairing diagnostic',
    ),
    const LedgerMobileException(
      LedgerMobileFailure.permissionDenied,
      'permission denied',
    ),
    StateError('unknown signer error'),
  ]) {
    testWidgets('desktop swap displays device recovery for $error', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(kLedgerMobileMethodChannel),
        (call) async => call.method == 'bluetoothAccessStatus'
            ? {'permission': 'granted'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(kLedgerMobileMethodChannel),
          null,
        ),
      );
      final accessRecovery =
          ledgerFailureGuidance(error)?.bluetoothRecovery == true;
      final operations = _StatefulOperationService();
      await _pumpOverlay(
        tester,
        intent: _intent(),
        operations: operations,
        signing: _HardwareSigningService(),
        sign: (_, _) async => throw error,
        persist: (_, _) async {},
        onCompleted: (_) async {},
      );
      await _pumpUntil(
        tester,
        () => find
            .text(
              ledgerFailureGuidance(error)?.pairingRecovery == true
                  ? 'Find my Ledger'
                  : accessRecovery
                  ? 'Reconnect'
                  : 'Try again',
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.text(
          ledgerFailureGuidance(error)?.pairingRecovery == true
              ? 'Couldn’t connect to your Ledger'
              : accessRecovery
              ? 'Ready to reconnect'
              : ledgerFailureGuidance(error)?.message ??
                    'Ledger signing could not be completed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open the Zcash app'), findsNothing);
      expect(operations.checkpointCalls, 0);
      expect(operations.broadcastCalls, 0);
    });
  }

  for (final payMode in [false, true]) {
    final flowName = payMode ? 'Pay' : 'Swap';
    testWidgets(
      'desktop Ledger $flowName retries provider persistence after broadcast '
      'without signing or broadcasting again',
      (tester) async {
        final operations = _StatefulOperationService();
        final signing = _HardwareSigningService();
        var signerCalls = 0;
        var persistenceCalls = 0;
        var completionCalls = 0;

        await _pumpOverlay(
          tester,
          intent: _intent(payMode: payMode),
          operations: operations,
          signing: signing,
          sign: (_, _) async {
            signerCalls++;
            return const [3];
          },
          persist: (_, _) async {
            persistenceCalls++;
            if (persistenceCalls == 1) {
              throw StateError(
                'Injected provider persistence failure after broadcast',
              );
            }
          },
          onCompleted: (_) async => completionCalls++,
        );
        await _pumpUntil(
          tester,
          () => find.text('Retry saving').evaluate().isNotEmpty,
        );

        expect(find.text('Transaction sent'), findsOneWidget);
        expect(
          find.text(
            'The transaction was sent, but Vizor could not finish saving it.',
          ),
          findsOneWidget,
        );
        expect(find.text('Open the Zcash app'), findsNothing);
        expect(
          find.byKey(const ValueKey('ledger_usb_only_connection')),
          findsNothing,
        );
        expect(signerCalls, 1);
        expect(operations.checkpointCalls, 1);
        expect(operations.broadcastCalls, 1);
        expect(operations.acceptedSubmissions, 1);
        expect(persistenceCalls, 1);
        expect(operations.acknowledgeCalls, 0);

        if (payMode) await _captureReproIfRequested(tester);
        await tester.tap(find.text('Retry saving'));
        await _pumpUntil(tester, () => completionCalls == 1);

        expect(signerCalls, 1);
        expect(operations.checkpointCalls, 1);
        expect(operations.broadcastCalls, 1);
        expect(operations.acceptedSubmissions, 1);
        expect(persistenceCalls, 2);
        expect(operations.acknowledgeCalls, 1);
        expect(
          operations.lastCheckpointKind,
          payMode
              ? LedgerSignedOperationKind.payDeposit
              : LedgerSignedOperationKind.swapDeposit,
        );
      },
    );
  }

  testWidgets(
    'desktop Ledger retries post-broadcast draft settlement before completion',
    (tester) async {
      final operations = _StatefulOperationService();
      final signing = _HardwareSigningService(
        failFirstBroadcastSettlement: true,
      );
      var signerCalls = 0;
      var persistenceCalls = 0;
      var completionCalls = 0;

      Future<void> pump() => _pumpOverlay(
        tester,
        intent: _intent(payMode: true),
        operations: operations,
        signing: signing,
        sign: (_, _) async {
          signerCalls++;
          return const [3];
        },
        persist: (_, _) async => persistenceCalls++,
        onCompleted: (_) async => completionCalls++,
      );

      await pump();
      await _pumpUntil(
        tester,
        () => find.text('Retry saving').evaluate().isNotEmpty,
      );

      expect(operations.broadcastCalls, 1);
      expect(operations.acceptedSubmissions, 1);
      expect(signing.settleCalls, 1);
      expect(signerCalls, 1);
      expect(operations.checkpointCalls, 1);
      expect(persistenceCalls, 0);
      expect(operations.acknowledgeCalls, 0);
      expect(operations.state, 'result_pending_ack');
      expect(find.text('Transaction sent'), findsOneWidget);
      expect(find.text('Ledger signing failed'), findsNothing);

      await tester.tap(find.text('Retry saving'));
      await _pumpUntil(tester, () => completionCalls == 1);

      expect(signing.settleCalls, 2);
      expect(signerCalls, 1);
      expect(operations.checkpointCalls, 1);
      expect(operations.broadcastCalls, 1);
      expect(operations.acceptedSubmissions, 1);
      expect(persistenceCalls, 1);
      expect(operations.acknowledgeCalls, 1);
      expect(operations.state, 'completed');
    },
  );

  testWidgets(
    'Back requests recovery after releasing a checkpointed operation claim',
    (tester) async {
      final operations = _StatefulOperationService();
      final signing = _HardwareSigningService(settlementFailures: 1);
      var signerCalls = 0;
      var persistenceCalls = 0;
      var cancelCalls = 0;

      final container = await _pumpOverlay(
        tester,
        intent: _intent(payMode: true),
        operations: operations,
        signing: signing,
        sign: (_, _) async {
          signerCalls++;
          return const [3];
        },
        persist: (_, _) async => persistenceCalls++,
        onCompleted: (_) async => fail('Back must leave recovery in charge.'),
        onCancelled: () => cancelCalls++,
      );
      await _pumpUntil(
        tester,
        () => find.text('Retry saving').evaluate().isNotEmpty,
      );

      await container
          .read(ledgerOperationRecoveryCoordinatorProvider)
          .recover();
      expect(persistenceCalls, 0);
      expect(operations.acknowledgeCalls, 0);

      await tester.tap(find.text('Back to activity'));
      await _pumpUntil(tester, () => operations.state == 'completed');

      expect(cancelCalls, 1);
      expect(signing.settlementStatuses, [
        SwapDepositBroadcastStatus.broadcasted,
        SwapDepositBroadcastStatus.broadcasted,
      ]);
      expect(signerCalls, 1);
      expect(operations.checkpointCalls, 1);
      expect(operations.broadcastCalls, 1);
      expect(persistenceCalls, 1);
      expect(operations.acknowledgeCalls, 1);
    },
  );

  testWidgets(
    'desktop Ledger retries acknowledgement without signing or broadcasting '
    'again',
    (tester) async {
      final operations = _StatefulOperationService(
        status: SwapDepositBroadcastStatus.broadcastedStorageFailed,
        acknowledgeFailures: 1,
      );
      final signing = _HardwareSigningService();
      var signerCalls = 0;
      var persistenceCalls = 0;
      var completionCalls = 0;

      await _pumpOverlay(
        tester,
        intent: _intent(payMode: true),
        operations: operations,
        signing: signing,
        sign: (_, _) async {
          signerCalls++;
          return const [3];
        },
        persist: (_, _) async => persistenceCalls++,
        onCompleted: (_) async => completionCalls++,
      );
      await _pumpUntil(
        tester,
        () => find.text('Retry saving').evaluate().isNotEmpty,
      );

      expect(find.text('Transaction sent'), findsOneWidget);
      expect(operations.broadcastCalls, 1);
      expect(operations.acceptedSubmissions, 1);
      expect(persistenceCalls, 1);
      expect(operations.acknowledgeCalls, 1);

      await tester.tap(find.text('Retry saving'));
      await _pumpUntil(tester, () => completionCalls == 1);

      expect(signerCalls, 1);
      expect(operations.broadcastCalls, 1);
      expect(operations.acceptedSubmissions, 1);
      expect(persistenceCalls, 2);
      expect(operations.acknowledgeCalls, 2);
    },
  );

  testWidgets(
    'desktop Ledger shows an unconfirmed broadcast result as status pending',
    (tester) async {
      final operations = _StatefulOperationService(
        status: SwapDepositBroadcastStatus.broadcastUnknown,
      );
      var persistenceCalls = 0;
      var completionCalls = 0;

      await _pumpOverlay(
        tester,
        intent: _intent(),
        operations: operations,
        signing: _HardwareSigningService(),
        sign: (_, _) async => const [3],
        persist: (_, _) async {
          persistenceCalls++;
          if (persistenceCalls == 1) {
            throw StateError('Injected pending-result persistence failure');
          }
        },
        onCompleted: (_) async => completionCalls++,
      );
      await _pumpUntil(
        tester,
        () => find.text('Retry saving').evaluate().isNotEmpty,
      );

      expect(find.text('Transaction status pending'), findsOneWidget);
      expect(
        find.text(
          'Vizor could not confirm whether the transaction was sent, and still needs to save its status.',
        ),
        findsOneWidget,
      );
      expect(find.text('Transaction sent'), findsNothing);
      expect(find.text('Open the Zcash app'), findsNothing);
      expect(
        find.byKey(const ValueKey('ledger_usb_only_connection')),
        findsNothing,
      );

      await tester.tap(find.text('Retry saving'));
      await _pumpUntil(tester, () => completionCalls == 1);
      expect(operations.broadcastCalls, 1);
      expect(operations.acceptedSubmissions, 1);
      expect(persistenceCalls, 2);
    },
  );

  testWidgets(
    'desktop Ledger retry reloads a durable pending result when the broadcast '
    'response was lost',
    (tester) async {
      final operations = _StatefulOperationService(
        status: SwapDepositBroadcastStatus.broadcastUnknown,
        failBroadcastResponseAfterAccept: true,
      );
      var signerCalls = 0;
      var persistenceCalls = 0;
      var completionCalls = 0;

      await _pumpOverlay(
        tester,
        intent: _intent(payMode: true),
        operations: operations,
        signing: _HardwareSigningService(),
        sign: (_, _) async {
          signerCalls++;
          return const [3];
        },
        persist: (_, _) async => persistenceCalls++,
        onCompleted: (_) async => completionCalls++,
      );
      await _pumpUntil(
        tester,
        () => find.text('Try again').evaluate().isNotEmpty,
      );

      expect(operations.state, 'result_pending_ack');
      expect(operations.broadcastCalls, 1);
      expect(operations.acceptedSubmissions, 1);
      expect(persistenceCalls, 0);

      await tester.tap(find.text('Try again'));
      await _pumpUntil(tester, () => completionCalls == 1);

      expect(signerCalls, 1);
      expect(operations.checkpointCalls, 1);
      expect(operations.broadcastCalls, 1);
      expect(operations.acceptedSubmissions, 1);
      expect(persistenceCalls, 1);
      expect(operations.acknowledgeCalls, 1);
      expect(operations.state, 'completed');
    },
  );

  testWidgets('desktop Ledger closes an initially expired deposit result', (
    tester,
  ) async {
    final operations = _StatefulOperationService(status: 'expired');
    var cancelCalls = 0;
    var persistenceCalls = 0;
    var completionCalls = 0;

    await _pumpOverlay(
      tester,
      intent: _intent(),
      operations: operations,
      signing: _HardwareSigningService(),
      sign: (_, _) async => const [3],
      persist: (_, _) async => persistenceCalls++,
      onCompleted: (_) async => completionCalls++,
      onCancelled: () => cancelCalls++,
    );
    await _pumpUntil(tester, () => cancelCalls == 1);

    expect(operations.broadcastCalls, 1);
    expect(operations.acknowledgeCalls, 1);
    expect(persistenceCalls, 0);
    expect(completionCalls, 0);
    expect(find.text('Retry saving'), findsNothing);
  });

  testWidgets(
    'desktop Ledger retries expired draft cleanup before acknowledgement',
    (tester) async {
      final operations = _StatefulOperationService(status: 'expired');
      final signing = _HardwareSigningService(settlementFailures: 2);
      var signerCalls = 0;
      var cancelCalls = 0;
      var persistenceCalls = 0;

      await _pumpOverlay(
        tester,
        intent: _intent(payMode: true),
        operations: operations,
        signing: signing,
        sign: (_, _) async {
          signerCalls++;
          return const [3];
        },
        persist: (_, _) async => persistenceCalls++,
        onCompleted: (_) async => fail('Expired result must not complete.'),
        onCancelled: () => cancelCalls++,
      );
      await _pumpUntil(
        tester,
        () => find.text('Retry cleanup').evaluate().isNotEmpty,
      );

      expect(find.text('Transaction expired'), findsOneWidget);
      expect(find.text('Open the Zcash app'), findsNothing);
      expect(signing.settlementStatuses, ['expired']);
      expect(operations.acknowledgeCalls, 0);
      expect(cancelCalls, 0);
      expect(persistenceCalls, 0);

      await tester.tap(find.text('Back to activity'));
      await _pumpUntil(tester, () => signing.settlementStatuses.length == 2);

      expect(find.text('Retry cleanup'), findsOneWidget);
      expect(signing.settlementStatuses, ['expired', 'expired']);
      expect(operations.acknowledgeCalls, 0);
      expect(cancelCalls, 0);

      await tester.tap(find.text('Retry cleanup'));
      await _pumpUntil(tester, () => cancelCalls == 1);

      expect(signing.settlementStatuses, ['expired', 'expired', 'expired']);
      expect(signerCalls, 1);
      expect(operations.broadcastCalls, 1);
      expect(operations.acknowledgeCalls, 1);
      expect(persistenceCalls, 0);
    },
  );

  testWidgets(
    'desktop Ledger retries expired acknowledgement without cleanup again',
    (tester) async {
      final operations = _StatefulOperationService(
        status: 'expired',
        acknowledgeFailures: 1,
      );
      final signing = _HardwareSigningService();
      var cancelCalls = 0;
      var persistenceCalls = 0;

      await _pumpOverlay(
        tester,
        intent: _intent(),
        operations: operations,
        signing: signing,
        sign: (_, _) async => const [3],
        persist: (_, _) async => persistenceCalls++,
        onCompleted: (_) async => fail('Expired result must not complete.'),
        onCancelled: () => cancelCalls++,
      );
      await _pumpUntil(
        tester,
        () => find.text('Retry cleanup').evaluate().isNotEmpty,
      );

      expect(signing.settlementStatuses, ['expired']);
      expect(operations.acknowledgeCalls, 1);
      expect(cancelCalls, 0);

      await tester.tap(find.text('Retry cleanup'));
      await _pumpUntil(tester, () => cancelCalls == 1);

      expect(signing.settlementStatuses, ['expired']);
      expect(operations.broadcastCalls, 1);
      expect(operations.acknowledgeCalls, 2);
      expect(persistenceCalls, 0);
    },
  );

  testWidgets(
    'desktop Ledger retries uncertain-result lock retention before saving',
    (tester) async {
      final operations = _StatefulOperationService(
        status: SwapDepositBroadcastStatus.broadcastUnknown,
      );
      final signing = _HardwareSigningService(settlementFailures: 1);
      var signerCalls = 0;
      var persistenceCalls = 0;
      var completionCalls = 0;

      await _pumpOverlay(
        tester,
        intent: _intent(),
        operations: operations,
        signing: signing,
        sign: (_, _) async {
          signerCalls++;
          return const [3];
        },
        persist: (_, _) async => persistenceCalls++,
        onCompleted: (_) async => completionCalls++,
      );
      await _pumpUntil(
        tester,
        () => find.text('Retry saving').evaluate().isNotEmpty,
      );

      expect(signing.settlementStatuses, [
        SwapDepositBroadcastStatus.broadcastUnknown,
      ]);
      expect(persistenceCalls, 0);
      expect(operations.acknowledgeCalls, 0);

      await tester.tap(find.text('Retry saving'));
      await _pumpUntil(tester, () => completionCalls == 1);

      expect(signing.settlementStatuses, [
        SwapDepositBroadcastStatus.broadcastUnknown,
        SwapDepositBroadcastStatus.broadcastUnknown,
      ]);
      expect(signerCalls, 1);
      expect(operations.broadcastCalls, 1);
      expect(persistenceCalls, 1);
      expect(operations.acknowledgeCalls, 1);
    },
  );

  testWidgets('desktop Ledger retry closes a recovered expired result', (
    tester,
  ) async {
    final operations = _StatefulOperationService(
      status: 'expired',
      failBroadcastResponseAfterAccept: true,
    );
    var cancelCalls = 0;
    var persistenceCalls = 0;
    var completionCalls = 0;

    await _pumpOverlay(
      tester,
      intent: _intent(payMode: true),
      operations: operations,
      signing: _HardwareSigningService(),
      sign: (_, _) async => const [3],
      persist: (_, _) async => persistenceCalls++,
      onCompleted: (_) async => completionCalls++,
      onCancelled: () => cancelCalls++,
    );
    await _pumpUntil(
      tester,
      () => find.text('Try again').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Try again'));
    await _pumpUntil(tester, () => cancelCalls == 1);

    expect(operations.broadcastCalls, 1);
    expect(operations.acknowledgeCalls, 1);
    expect(persistenceCalls, 0);
    expect(completionCalls, 0);
  });

  testWidgets('desktop Ledger reopening closes a saved expired result', (
    tester,
  ) async {
    final operations = _StatefulOperationService(status: 'expired')
      ..seedPendingResult(payMode: true);
    var signerCalls = 0;
    var cancelCalls = 0;
    var persistenceCalls = 0;
    var completionCalls = 0;

    await _pumpOverlay(
      tester,
      intent: _intent(payMode: true),
      operations: operations,
      signing: _HardwareSigningService(),
      sign: (_, _) async {
        signerCalls++;
        return const [3];
      },
      persist: (_, _) async => persistenceCalls++,
      onCompleted: (_) async => completionCalls++,
      onCancelled: () => cancelCalls++,
    );
    await _pumpUntil(tester, () => cancelCalls == 1);

    expect(signerCalls, 0);
    expect(operations.checkpointCalls, 0);
    expect(operations.broadcastCalls, 0);
    expect(operations.acknowledgeCalls, 1);
    expect(persistenceCalls, 0);
    expect(completionCalls, 0);
  });
}

Future<ProviderContainer> _pumpOverlay(
  WidgetTester tester, {
  required SwapIntent intent,
  required _StatefulOperationService operations,
  required _HardwareSigningService signing,
  required LedgerPcztSigner sign,
  required LedgerDepositResultPersistence persist,
  required Future<void> Function(SwapHardwareBroadcastResult) onCompleted,
  VoidCallback? onCancelled,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      ledgerDepositResultPersistenceProvider.overrideWithValue(persist),
      ledgerDepositRecoveryProvider.overrideWithValue(
        ({required operation, required result}) => persist(
          intent,
          SwapHardwareBroadcastResult(
            txHash: result.txid,
            status: result.status,
            message: result.message,
          ),
        ),
      ),
      ledgerPcztSignerProvider.overrideWithValue(sign),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      ledgerSignedOperationServiceProvider.overrideWithValue(operations),
      swapHardwareSigningServiceProvider.overrideWithValue(signing),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: _captureBoundaryKey,
            child: AppTheme(
              data: AppThemeData.light,
              child: SwapLedgerSigningOverlay(
                intent: intent,
                onCancel: onCancelled ?? () {},
                onDepositBroadcast: onCompleted,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

Future<void> _captureReproIfRequested(WidgetTester tester) async {
  final path = Platform.environment['VIZOR_REPRO_SCREENSHOT_PATH'];
  if (path == null || path.trim().isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureBoundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

SwapIntent _intent({bool payMode = false}) => SwapIntent(
  id: payMode ? 'pay-1' : 'swap-1',
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
  payMode: payMode,
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
  _HardwareSigningService({
    bool failFirstBroadcastSettlement = false,
    int settlementFailures = 0,
  }) : settlementFailures =
           settlementFailures + (failFirstBroadcastSettlement ? 1 : 0);

  int settlementFailures;
  var settleCalls = 0;
  final settlementStatuses = <String?>[];

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
  Future<void> settlePcztDraftAfterLedgerBroadcast({
    required SwapHardwarePcztDraft draft,
    required String? status,
  }) async {
    settleCalls++;
    settlementStatuses.add(status);
    if (settlementFailures > 0) {
      settlementFailures--;
      throw StateError('Could not finish cancelling. Please try again.');
    }
  }

  @override
  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft}) async {}

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

class _StatefulOperationService implements LedgerSignedOperationService {
  _StatefulOperationService({
    this.status = SwapDepositBroadcastStatus.broadcasted,
    this.acknowledgeFailures = 0,
    this.failBroadcastResponseAfterAccept = false,
  });

  final String status;
  int acknowledgeFailures;
  final bool failBroadcastResponseAfterAccept;
  var checkpointCalls = 0;
  var broadcastCalls = 0;
  var acceptedSubmissions = 0;
  var acknowledgeCalls = 0;
  String? state;
  String? operationId;
  String? accountUuid;
  String? externalRef;
  LedgerSignedOperationKind? lastCheckpointKind;

  void seedPendingResult({required bool payMode}) {
    operationId = payMode
        ? 'pay_deposit:account-1:pay-1'
        : 'swap_deposit:account-1:swap-1';
    accountUuid = 'account-1';
    externalRef = payMode ? 'pay-1' : 'swap-1';
    lastCheckpointKind = payMode
        ? LedgerSignedOperationKind.payDeposit
        : LedgerSignedOperationKind.swapDeposit;
    state = 'result_pending_ack';
  }

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
    this.operationId = operationId;
    this.accountUuid = accountUuid;
    this.externalRef = externalRef;
    lastCheckpointKind = kind;
    state = 'signed_pending_broadcast';
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcastCalls++;
    if (state != 'signed_pending_broadcast') {
      throw StateError(
        'Ledger operation $operationId is not pending broadcast on main',
      );
    }
    acceptedSubmissions++;
    state = 'result_pending_ack';
    if (failBroadcastResponseAfterAccept) {
      throw StateError('Connection closed after transaction submission');
    }
    return LedgerSignedOperationBroadcastResult(
      operationId: operationId,
      txid: 'txid-1',
      status: status,
      requiresAck: true,
    );
  }

  @override
  Future<void> acknowledge(String operationId) async {
    acknowledgeCalls++;
    if (acknowledgeFailures > 0) {
      acknowledgeFailures--;
      throw StateError('Injected acknowledgement failure');
    }
    state = 'completed';
  }

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => [
    if (state == 'signed_pending_broadcast' || state == 'result_pending_ack')
      LedgerSignedOperationMetadata(
        operationId: operationId!,
        accountUuid: accountUuid!,
        kind: lastCheckpointKind!,
        externalRef: externalRef,
        state: state!,
        txid: state == 'result_pending_ack' ? 'txid-1' : null,
        status: state == 'result_pending_ack' ? status : null,
      ),
  ];
}
