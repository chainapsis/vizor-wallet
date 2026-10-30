@Tags(['mobile'])
library;

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
import 'package:zcash_wallet/src/providers/pending_activity_evidence_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_procedure.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/shield_hardware_motion.dart';

void main() {
  final api = _ShieldApi();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(api.reset);

  testWidgets('saving stays in step 3 until the broadcast begins', (
    tester,
  ) async {
    final operations = _SigningOperations();
    final container = await _mountSigning(
      tester,
      operations,
      (_) async => [7, 8, 9],
    );
    await _until(tester, () => operations.checkpointCalls == 1);
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<LedgerProcedure>(find.byType(LedgerProcedure)).currentStep,
      2,
    );
    expect(find.text('Saving the signed transaction.'), findsOneWidget);
    expect(find.text('Cancel shielding'), findsNothing);
    expect(
      tester.widget<MobileShieldScene>(find.byType(MobileShieldScene)).phase,
      MobileShieldPhase.hardware,
    );
    operations.checkpointed.complete();
    await _until(tester, () => operations.broadcastCalls == 1);
    expect(
      tester.widget<MobileShieldScene>(find.byType(MobileShieldScene)).phase,
      MobileShieldPhase.working,
    );
    expect(
      tester
          .widget<ShieldHardwarePresentation>(
            find.byType(ShieldHardwarePresentation),
          )
          .interactive,
      isFalse,
    );
    operations.broadcasted.complete();
    await _until(
      tester,
      () =>
          tester
              .widget<MobileShieldScene>(find.byType(MobileShieldScene))
              .phase ==
          MobileShieldPhase.succeeded,
    );
    container.read(pendingActivityEvidenceProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final recoveredAmount in [BigInt.from(1970000), null]) {
    for (final precedingRound in [false, true]) {
      testWidgets('resumed shielding preserves amount $recoveredAmount '
          '(preceding round: $precedingRound)', (tester) async {
        final operations = _SigningOperations()
          ..pending = precedingRound ? [] : [_checkpoint(recoveredAmount)]
          ..recoverAfterFirstBroadcast = precedingRound
              ? _checkpoint(recoveredAmount)
              : null;
        operations.checkpointed.complete();
        final container = await _mountSigning(
          tester,
          operations,
          (_) async => [7, 8, 9],
          readProgress:
              ({
                required dbPath,
                required network,
                required accountUuid,
              }) async => LedgerShieldingProgress(
                inputCount: precedingRound
                    ? 2 - operations.successfulBroadcasts
                    : 0,
                inputLimit: 32,
                belowThreshold: false,
              ),
        );
        await _until(tester, () => operations.broadcastCalls == 1);
        expect(api.creates, precedingRound ? 1 : 0);
        operations.broadcasted.complete();
        await _until(
          tester,
          () =>
              tester
                  .widget<MobileShieldScene>(find.byType(MobileShieldScene))
                  .phase ==
              MobileShieldPhase.succeeded,
        );
        final scene = tester.widget<MobileShieldScene>(
          find.byType(MobileShieldScene),
        );
        expect(operations.successfulBroadcasts, precedingRound ? 2 : 1);
        expect(api.creates, precedingRound ? 1 : 0);
        expect(scene.showResultAmount, recoveredAmount != null);
        if (recoveredAmount != null) {
          expect(scene.resultAmount, precedingRound ? '0.0296' : '0.0197');
        }
        container.read(pendingActivityEvidenceProvider.notifier).clear();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'resumed operation still pauses if remaining input reduction is unconfirmed',
    (tester) async {
      final operations = _SigningOperations()
        ..pending = [_checkpoint(BigInt.from(1970000))];
      final container = await _mountSigning(
        tester,
        operations,
        (_) async => throw StateError('must not sign again'),
        readProgress:
            ({required dbPath, required network, required accountUuid}) async =>
                LedgerShieldingProgress(
                  inputCount: 1,
                  inputLimit: 32,
                  belowThreshold: false,
                ),
      );
      await _until(tester, () => operations.broadcastCalls == 1);
      operations.broadcasted.complete();
      await _until(
        tester,
        () =>
            tester
                .widget<MobileShieldScene>(find.byType(MobileShieldScene))
                .phase ==
            MobileShieldPhase.failed,
      );
      expect(api.creates, 0);
      expect(operations.successfulBroadcasts, 1);
      expect(
        tester
            .widget<MobileShieldScene>(find.byType(MobileShieldScene))
            .resultAmount,
        '0.0197',
      );
      container.read(pendingActivityEvidenceProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'resumed broadcast failure retries without losing or doubling amount',
    (tester) async {
      final operations = _SigningOperations()
        ..pending = [_checkpoint(BigInt.from(1970000))]
        ..failNextBroadcast = true;
      final container = await _mountSigning(
        tester,
        operations,
        (_) async => throw StateError('must not sign again'),
      );
      await _until(tester, () => operations.broadcastCalls == 1);
      operations.broadcasted.complete();
      await _until(
        tester,
        () =>
            tester
                .widget<MobileShieldScene>(find.byType(MobileShieldScene))
                .phase ==
            MobileShieldPhase.failed,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Try again'));
      await _until(
        tester,
        () =>
            tester
                .widget<MobileShieldScene>(find.byType(MobileShieldScene))
                .phase ==
            MobileShieldPhase.succeeded,
      );
      final scene = tester.widget<MobileShieldScene>(
        find.byType(MobileShieldScene),
      );
      expect(operations.broadcastCalls, 2);
      expect(operations.successfulBroadcasts, 1);
      expect(scene.showResultAmount, isTrue);
      expect(scene.resultAmount, '0.0197');
      expect(api.creates, 0);
      container.read(pendingActivityEvidenceProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('declined approval retries step 2 with the existing proofs', (
    tester,
  ) async {
    final operations = _SigningOperations();
    var attempts = 0;
    final signed = Completer<List<int>>();
    await _mountSigning(tester, operations, (ref) {
      ref.read(ledgerSigningProgressProvider.notifier).begin('account-1');
      if (++attempts == 1) {
        throw const LedgerMobileException(
          LedgerMobileFailure.rejected,
          'Rejected',
        );
      }
      return signed.future;
    });
    await _until(
      tester,
      () => find.text('Request declined').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<LedgerProcedure>(find.byType(LedgerProcedure)).currentStep,
      1,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(attempts, 2);
    expect(
      tester.widget<LedgerProcedure>(find.byType(LedgerProcedure)).currentStep,
      1,
    );
    expect(api.creates, 1);
    expect(api.proofs, 1);
    expect(operations.checkpointCalls, 0);
    expect(operations.broadcastCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    signed.complete([7, 8, 9]);
    await tester.pump();
    expect(operations.checkpointCalls, 0);
  });

  testWidgets('cancellation shows progress and drains exactly once', (
    tester,
  ) async {
    final operations = _SigningOperations();
    final signed = Completer<List<int>>();
    final drained = Completer<void>();
    var cancelCalls = 0, closed = 0, started = false;
    await _mountSigning(
      tester,
      operations,
      (_) {
        started = true;
        return signed.future;
      },
      cancel: () {
        cancelCalls++;
        return drained.future;
      },
      onClose: () => closed++,
    );
    await _until(tester, () => started);
    await tester.pump(const Duration(seconds: 2));
    final close = tester
        .widget<MobileShieldScene>(find.byType(MobileShieldScene))
        .onClose!;
    await tester.tap(find.text('Cancel shielding'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    close();
    expect(cancelCalls, 1);
    expect(closed, 0);
    expect(find.text('Cancelling request'), findsOneWidget);
    expect(find.text('Cancel shielding'), findsNothing);
    expect(
      tester.widget<MobileShieldScene>(find.byType(MobileShieldScene)).canLeave,
      isFalse,
    );
    signed.complete([7, 8, 9]);
    await tester.pump();
    expect(operations.checkpointCalls, 0);
    drained.complete();
    await tester.pump();
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an empty Ledger round never celebrates an unsubmitted transaction',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('vizor-shield-test'),
      ))!;
      final original = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(dir.path);
      addTearDown(() async {
        PathProviderPlatform.instance = original;
        await dir.delete(recursive: true);
      });
      var completed = 0;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          syncProvider.overrideWith(_Sync.new),
          walletProvider.overrideWith(_Wallet.new),
          ledgerOperationCancellerProvider.overrideWithValue(() async {}),
          ledgerSignedOperationServiceProvider.overrideWithValue(_Operations()),
          ledgerShieldingProgressReaderProvider.overrideWithValue(
            ({required dbPath, required network, required accountUuid}) async =>
                LedgerShieldingProgress(
                  inputCount: 0,
                  inputLimit: 32,
                  belowThreshold: false,
                ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
      await container.read(walletProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppTheme(
            data: AppThemeData.light,
            child: MaterialApp(
              home: LedgerShieldSigningOverlay(
                mobile: true,
                onCancel: () {},
                onComplete: () => completed++,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final slide = find.byKey(const ValueKey('mobile_shield_slide'));
      await tester.dragFrom(
        tester.getTopLeft(slide) + const Offset(35, 30),
        const Offset(280, 0),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Shielding paused'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Cancel shielding'), findsNothing);
      expect(
        find.textContaining('No spendable transparent funds remain'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(
        find.byKey(const ValueKey('mobile_shield_complete')),
        findsNothing,
      );
      expect(completed, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(done(), isTrue);
}

Future<ProviderContainer> _mountSigning(
  WidgetTester tester,
  _SigningOperations operations,
  Future<List<int>> Function(Ref) signer, {
  Future<void> Function()? cancel,
  VoidCallback? onClose,
  LedgerShieldingProgressReader? readProgress,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('shield-procedure-'),
  ))!;
  final original = PathProviderPlatform.instance;
  PathProviderPlatform.instance = _Paths(dir.path);
  addTearDown(() async {
    PathProviderPlatform.instance = original;
    await dir.delete(recursive: true);
  });
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(_Sync.new),
      walletProvider.overrideWith(_Wallet.new),
      ledgerOperationCancellerProvider.overrideWithValue(cancel ?? () async {}),
      ledgerSignedOperationServiceProvider.overrideWithValue(operations),
      ledgerPcztSignerProvider.overrideWith(
        (ref) =>
            (_, _) => signer(ref),
      ),
      ledgerShieldingProgressReaderProvider.overrideWithValue(
        readProgress ??
            ({required dbPath, required network, required accountUuid}) async =>
                LedgerShieldingProgress(
                  inputCount: operations.successfulBroadcasts == 0 ? 1 : 0,
                  inputLimit: 32,
                  belowThreshold: false,
                ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(syncProvider.future);
  await container.read(walletProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: LedgerShieldSigningOverlay(
          mobile: true,
          onCancel: onClose ?? () {},
          onComplete: () {},
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  final slide = find.byKey(const ValueKey('mobile_shield_slide'));
  await tester.dragFrom(
    tester.getTopLeft(slide) + const Offset(35, 30),
    const Offset(280, 0),
  );
  return container;
}

LedgerSignedOperationMetadata _checkpoint(BigInt? amount) =>
    LedgerSignedOperationMetadata(
      operationId: 'recovered-shield',
      accountUuid: 'account-1',
      kind: LedgerSignedOperationKind.shield,
      state: 'signed_pending_broadcast',
      shieldedZatoshi: amount,
    );

class _SigningOperations extends _Operations {
  final checkpointed = Completer<void>();
  final broadcasted = Completer<void>();
  int checkpointCalls = 0, broadcastCalls = 0, successfulBroadcasts = 0;
  bool failNextBroadcast = false;
  List<LedgerSignedOperationMetadata> pending = [];
  LedgerSignedOperationMetadata? recoverAfterFirstBroadcast;
  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => pending;
  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) {
    checkpointCalls++;
    return checkpointed.future;
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcastCalls++;
    await broadcasted.future;
    if (failNextBroadcast) {
      failNextBroadcast = false;
      throw StateError('broadcast failed');
    }
    successfulBroadcasts++;
    pending = successfulBroadcasts == 1 && recoverAfterFirstBroadcast != null
        ? [recoverAfterFirstBroadcast!]
        : [];
    return LedgerSignedOperationBroadcastResult(
      operationId: operationId,
      txid: 'preview-shield',
      status: 'broadcasted',
      requiresAck: false,
    );
  }
}

class _ShieldApi extends RustLibApi {
  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {}
  int creates = 0, proofs = 0;
  void reset() {
    creates = 0;
    proofs = 0;
  }

  @override
  Future<ShieldTransparentPcztResult> crateApiSyncCreateShieldTransparentPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String sendFlowId,
  }) async {
    creates++;
    return ShieldTransparentPcztResult(
      proposalId: BigInt.from(77),
      pcztBytes: Uint8List.fromList([1, 2, 3]),
      feeZatoshi: BigInt.from(10000),
      shieldedZatoshi: BigInt.from(990000),
      needsSaplingParams: false,
    );
  }

  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    proofs++;
    return Uint8List.fromList([4, 5, 6]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Operations extends Fake implements LedgerSignedOperationService {
  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => [];
}

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Sync extends SyncNotifier {
  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {}
  @override
  Future<void> refreshAfterSend() async {}
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    transparentBalance: BigInt.from(1000000),
  );
}

class _Wallet extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(
    hasWallet: true,
    unifiedAddress: 'u1test',
    network: 'main',
    activeAccountUuid: 'account-1',
  );
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home/ledger-shield',
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
    activeAddress: 'u1test',
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
