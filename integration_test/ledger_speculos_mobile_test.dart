@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_ledger_shield_screen.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_ledger_send_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/sapling_params.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_deposit_transaction_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_max_amount_estimator.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_ledger_sign_screen.dart';
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;
import 'package:zcash_wallet/src/generated/service.pbgrpc.dart' as service_grpc;
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart' as rust_ledger;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'imports with Ledger through Speculos',
    _runMobileImportScenario,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'sends with Ledger through Speculos',
    _runMobileSendScenario,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'sends to TEX with two Ledger approvals through Speculos',
    _runMobileTexSendScenario,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'shields transparent balance with Ledger through Speculos',
    _runMobileShieldScenario,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'pays with Ledger through Speculos',
    (tester) => _runMobileSwapScenario(tester, _LedgerSwapScenario.pay),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'swaps with Ledger through Speculos',
    (tester) => _runMobileSwapScenario(tester, _LedgerSwapScenario.swap),
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'signs sequential voting bundles with Ledger through Speculos',
    _runMobileVotingSigningScenario,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'signs Orchard to Ironwood crossing through Speculos',
    _runMobilePostIronwoodOrchardSigningScenario,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _runMobilePostIronwoodOrchardSigningScenario(
  WidgetTester tester,
) async {
  final fixture = _Fixture.load();
  final dbPath = await _copyFixtureDb(fixture);
  final ble = _SpeculosLedgerMobileBleService(fixture.signingApiUrl);
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _ledgerBootstrap(fixture, 'http://127.0.0.1:1'),
      ),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
      ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ledgerWalletDbPathProvider.overrideWithValue(() async => dbPath),
    ],
  );
  addTearDown(container.dispose);
  await container.read(accountProvider.future);

  final unsigned = fixture.orchardToIronwoodV6Pczt;
  final signed = container.read(ledgerPcztSignerProvider)(
    fixture.accountUuid,
    unsigned,
  );
  expect(
    await _approveNextReviewWhilePumping(tester, fixture.signingApiUrl),
    isTrue,
  );
  final signedBytes = await signed;
  expect(signedBytes, isNotEmpty);
  expect(signedBytes, isNot(equals(unsigned)));
}

Future<void> _runMobileVotingSigningScenario(WidgetTester tester) async {
  final fixture = _Fixture.load();
  final dbPath = await _copyFixtureDb(fixture);
  final ble = _SpeculosLedgerMobileBleService(fixture.signingApiUrl);
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _ledgerBootstrap(fixture, 'http://127.0.0.1:1'),
      ),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
      ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ledgerWalletDbPathProvider.overrideWithValue(() async => dbPath),
    ],
  );
  addTearDown(container.dispose);
  await container.read(accountProvider.future);

  final signaturesByBundle = <int, LedgerVotingSignature>{};
  for (var bundleIndex = 0; bundleIndex < 2; bundleIndex++) {
    final pczt = await rust_sync.redactPcztForSigner(
      pcztBytes: fixture.votingBundlePczts[bundleIndex],
    );
    final signatures = container.read(ledgerVotingPcztSignerProvider)(
      fixture.accountUuid,
      pczt,
    );
    expect(
      await _approveNextReviewWhilePumping(tester, fixture.signingApiUrl),
      isTrue,
    );
    signaturesByBundle[bundleIndex] = requireMatchingLedgerVotingSignature(
      signatures: await signatures,
      actionIndex: fixture.votingActionIndexes[bundleIndex],
    );
  }

  expect(signaturesByBundle.keys, [0, 1]);
  expect(signaturesByBundle[0]!.pool, 1);
  expect(signaturesByBundle[1]!.pool, 1);
  expect(
    signaturesByBundle[0]!.signature,
    isNot(equals(signaturesByBundle[1]!.signature)),
  );
}

Future<void> _runMobileImportScenario(WidgetTester tester) async {
  final fixture = _Fixture.load();
  final importService = _SpeculosLedgerMobileBleService(fixture.ufvkApiUrl);
  final sandboxDirectory = await Directory.systemTemp.createTemp(
    'vizor-ledger-mobile-first-account-e2e.',
  );
  addTearDown(() => sandboxDirectory.delete(recursive: true));
  final firstAccountDbPath = '${sandboxDirectory.path}/wallet.db';
  final security = _LedgerFirstAccountSecurityNotifier();
  final firstAccountImport = _RecordingLedgerFirstAccountImport(
    firstAccountDbPath,
  );
  final router = GoRouter(
    initialLocation: '/welcome',
    routes: [
      ...mobileOnboardingRoutes(),
      GoRoute(
        path: '/home',
        builder: (_, _) =>
            const SizedBox(key: ValueKey('mobile_ledger_first_account_home')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      key: const ValueKey('mobile_ledger_speculos_import_scope'),
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        appSecurityProvider.overrideWith(() => security),
        biometricUnlockProvider.overrideWith(_AvailableBiometricNotifier.new),
        syncProvider.overrideWith(_EmptySyncNotifier.new),
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
        ledgerMobileBleServiceProvider.overrideWithValue(importService),
        ledgerOperationCancellerProvider.overrideWithValue(() async {}),
        ledgerAccountImporterProvider.overrideWithValue(
          firstAccountImport.call,
        ),
        rpcEndpointFailoverProvider.overrideWith(
          _LedgerOnboardingRpcFailoverNotifier.new,
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('mobile_welcome_get_started')),
    findsOneWidget,
  );
  await tester.tap(find.byKey(const ValueKey('mobile_welcome_get_started')));
  await tester.pumpAndSettle();
  final ledgerEntry = find.byKey(const ValueKey('mobile_welcome_ledger'));
  expect(ledgerEntry, findsOneWidget);
  await tester.ensureVisible(ledgerEntry);
  await tester.tap(ledgerEntry);
  await tester.pumpAndSettle();

  await tester.tap(
    find.byKey(const ValueKey('mobile_ledger_select_device_button')),
  );
  await _pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_ledger_device_speculos'))),
    description: 'Speculos Ledger discovery',
    timeout: const Duration(seconds: 30),
  );
  await tester.tap(find.byKey(const ValueKey('mobile_ledger_device_speculos')));
  await _pumpUntil(
    tester,
    () => !tester.any(find.byKey(const ValueKey('mobile_ledger_device_sheet'))),
    description: 'Speculos Ledger selection',
    timeout: const Duration(seconds: 30),
  );

  final importButton = find.byKey(
    const ValueKey('mobile_ledger_import_button'),
  );
  await tester.tap(importButton);
  await tester.pump();
  final importSpinner = find.byKey(
    const ValueKey('mobile_ledger_import_spinner'),
  );
  expect(importSpinner, findsOneWidget);
  expect(
    tester.getCenter(importSpinner).dx,
    greaterThan(tester.getCenter(importButton).dx),
  );

  final importApproval = _approveNextReview(fixture.ufvkApiUrl);
  await _pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    ),
    description: 'mobile Ledger birthday route',
    timeout: const Duration(minutes: 2),
  );
  expect(await importApproval, isTrue);

  await tester.tap(
    find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('mobile_import_birthday_height')),
    '2500000',
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const ValueKey('mobile_import_birthday_continue')),
  );
  await tester.pumpAndSettle();

  expect(find.text('Create Passcode'), findsOneWidget);
  await _enterMobilePasscode(tester, '123456');
  await _enterMobilePasscode(tester, '123456');
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('mobile_customise_account_name_field')),
    'Speculos Ledger',
  );
  await tester.tap(
    find.byKey(const ValueKey('mobile_customise_account_continue')),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('mobile_biometrics_not_now'))),
    description: 'mobile biometrics choice after Ledger import',
    timeout: const Duration(minutes: 2),
  );
  await tester.tap(find.byKey(const ValueKey('mobile_biometrics_not_now')));
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('mobile_ledger_first_account_home')),
    findsOneWidget,
  );
  final exported = firstAccountImport.account;
  expect(exported, isNotNull);
  expect(exported!.ufvk, fixture.ufvk);
  expect(exported.seedFingerprint, fixture.seedFingerprint);
  expect(exported.accountIndex, fixture.accountIndex);
  expect(exported.appVersion, '3.9.2');
  expect(exported.transport, LedgerConnectionTransport.bluetooth);
  expect(exported.device?.id, 'speculos');
  expect(firstAccountImport.name, 'Speculos Ledger');
  expect(firstAccountImport.birthdayHeight, 2500000);
  expect(security.preparedPassword, '123456');
  expect(security.commitCount, 1);
  expect(security.rollbackCount, 0);

  final storedAccounts = await rust_wallet.listAccounts(
    dbPath: firstAccountDbPath,
    network: 'main',
  );
  expect(storedAccounts, hasLength(1));
  expect(storedAccounts.single.name, 'Speculos Ledger');
  expect(storedAccounts.single.isHardware, isTrue);
  expect(storedAccounts.single.hardwareSignerKind, 'ledger');
  expect(storedAccounts.single.zip32AccountIndex, fixture.accountIndex);
  expect(storedAccounts.single.birthdayHeight, 2500000);
}

Future<void> _enterMobilePasscode(WidgetTester tester, String passcode) async {
  for (final digit in passcode.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
}

Future<void> _runMobileShieldScenario(WidgetTester tester) async {
  final fixture = _Fixture.load();
  final dbPath = await _copyFixtureDb(fixture);
  final lightwalletd = _AcceptingLightwalletd();
  await lightwalletd.start();
  addTearDown(lightwalletd.stop);
  final operationService = _TrackingLedgerSignedOperationService(
    RustLedgerSignedOperationService(
      network: 'main',
      lightwalletdUrl: lightwalletd.url,
      loadWalletDbPath: () async => dbPath,
    ),
  );
  final ble = _SpeculosLedgerMobileBleService(fixture.signingApiUrl);
  final router = GoRouter(
    initialLocation: '/home/ledger-shield',
    routes: [
      GoRoute(
        path: '/home/ledger-shield',
        builder: (_, _) => const MobileLedgerShieldScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) =>
            const SizedBox(key: ValueKey('mobile_ledger_shield_complete')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final approval = _approveNextReview(fixture.signingApiUrl);

  await tester.pumpWidget(
    _mobileLedgerHarness(
      fixture: fixture,
      lightwalletdUrl: lightwalletd.url,
      router: router,
      ble: ble,
      operationService: operationService,
      walletDbPath: dbPath,
    ),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval')),
    description: 'mobile Ledger shield approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(
    find.byKey(const ValueKey('mobile_ledger_shield_signing_surface')),
    findsOneWidget,
  );
  expect(await approval, isTrue);
  await _pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_ledger_shield_complete'))),
    description: 'mobile Ledger shield completion',
    timeout: const Duration(minutes: 2),
  );

  expect(operationService.callOrder, ['checkpoint', 'broadcast']);
  expect(operationService.checkpointCount, 1);
  expect(operationService.broadcastCount, 1);
  expect(
    operationService.lastOperationId,
    startsWith('shield:${fixture.accountUuid}:'),
  );
  expect(operationService.lastBroadcastResult?.status, 'broadcasted');
  expect(lightwalletd.sendTransactionCount, 1);
  expect(lightwalletd.lastRawTransaction, isNotEmpty);
  expect(await operationService.list(), isEmpty);
}

Future<void> _runMobileSendScenario(WidgetTester tester) async {
  final fixture = _Fixture.load();
  final dbPath = await _copyFixtureDb(fixture);
  final lightwalletd = _AcceptingLightwalletd();
  await lightwalletd.start();
  addTearDown(lightwalletd.stop);
  final operationService = _TrackingLedgerSignedOperationService(
    RustLedgerSignedOperationService(
      network: 'main',
      lightwalletdUrl: lightwalletd.url,
      loadWalletDbPath: () async => dbPath,
    ),
  );
  final ble = _SpeculosLedgerMobileBleService(fixture.signingApiUrl);
  final args = SendReviewArgs(
    proposalId: BigInt.one,
    sendFlowId: 'ledger-mobile-speculos-send',
    proposalAccountUuid: fixture.accountUuid,
    address: fixture.transparentAddress,
    addressType: 'transparent',
    amountZatoshi: BigInt.from(990000),
    feeZatoshi: BigInt.from(10000),
    needsSaplingParams: false,
  );
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, _) => _MobileSendLauncher(args: args),
      ),
      GoRoute(
        path: '/send/ledger-sign',
        builder: (_, state) => MobileLedgerSendSignScreen(
          args: state.extra! as SendReviewArgs,
          loadWalletDbPath: () async => dbPath,
          loadSaplingParams: () async => _completeSaplingParams,
          createPczt:
              ({
                required dbPath,
                required lightwalletdUrl,
                required network,
                required proposalId,
                required sendFlowId,
              }) async => fixture.pcztBytes,
          redactPczt: rust_sync.redactPcztForSigner,
          addProofs: rust_sync.addProofsToPczt,
          discardProposal: () async {},
        ),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) {
          final ledger = state.extra! as LedgerBroadcastArgs;
          return MobileSendStatusScreen(
            args: ledger.reviewArgs,
            ledger: ledger,
          );
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  final approval = _approveNextReview(fixture.signingApiUrl);

  await tester.pumpWidget(
    _mobileLedgerHarness(
      fixture: fixture,
      lightwalletdUrl: lightwalletd.url,
      router: router,
      ble: ble,
      operationService: operationService,
      walletDbPath: dbPath,
    ),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval')),
    description: 'mobile Send Ledger approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(await approval, isTrue);
  await _pumpUntil(
    tester,
    () =>
        tester.any(
          find.byKey(const ValueKey('mobile_send_status_succeeded')),
        ) ||
        operationService.lastBroadcastResult != null,
    description: 'mobile Ledger Send broadcast result',
    timeout: const Duration(minutes: 2),
  );
  final broadcastResult = operationService.lastBroadcastResult;
  expect(broadcastResult, isNotNull);
  expect(
    broadcastResult!.status,
    'broadcasted',
    reason: broadcastResult.message,
  );
  await _pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_send_status_succeeded'))),
    description: 'mobile Ledger Send success screen',
    timeout: const Duration(seconds: 10),
  );

  expect(operationService.checkpointCount, 1);
  expect(operationService.broadcastCount, 1);
  expect(lightwalletd.sendTransactionCount, 1);
  expect(lightwalletd.lastRawTransaction, isNotEmpty);
  expect(await operationService.list(), isEmpty);
}

Future<void> _runMobileTexSendScenario(WidgetTester tester) async {
  final fixture = _Fixture.load();
  final dbPath = await _copyFixtureDb(fixture);
  final lightwalletd = _AcceptingLightwalletd();
  await lightwalletd.start();
  addTearDown(lightwalletd.stop);
  final operationService = _TrackingLedgerSignedOperationService(
    RustLedgerSignedOperationService(
      network: 'main',
      lightwalletdUrl: lightwalletd.url,
      loadWalletDbPath: () async => dbPath,
    ),
  );
  final ble = _SpeculosLedgerMobileBleService(fixture.signingApiUrl);
  final args = SendReviewArgs(
    proposalId: BigInt.two,
    sendFlowId: 'ledger-mobile-speculos-tex-send',
    proposalAccountUuid: fixture.accountUuid,
    address: fixture.texAddress,
    addressType: 'tex',
    amountZatoshi: BigInt.from(1980000),
    feeZatoshi: BigInt.from(20000),
    needsSaplingParams: false,
  );
  String? requestedLightwalletdUrl;
  String? requestedNetwork;
  BigInt? requestedProposalId;
  String? requestedSendFlowId;
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, _) => _MobileSendLauncher(args: args),
      ),
      GoRoute(
        path: '/send/ledger-sign',
        builder: (_, state) => MobileLedgerSendSignScreen(
          args: state.extra! as SendReviewArgs,
          loadWalletDbPath: () async => dbPath,
          loadSaplingParams: () async => _completeSaplingParams,
          createTexPczts:
              ({
                required dbPath,
                required lightwalletdUrl,
                required network,
                required proposalId,
                required sendFlowId,
              }) async {
                requestedLightwalletdUrl = lightwalletdUrl;
                requestedNetwork = network;
                requestedProposalId = proposalId;
                requestedSendFlowId = sendFlowId;
                return rust_sync.TexPcztPairResult(
                  pczts: [
                    Uint8List.fromList(fixture.texStep1PcztBytes),
                    Uint8List.fromList(fixture.texStep2PcztBytes),
                  ],
                  signerPczts: const [],
                );
              },
          redactPczt: rust_sync.redactPcztForSigner,
          addProofs: rust_sync.addProofsToPczt,
          discardProposal: () async {},
        ),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) {
          final ledger = state.extra! as LedgerBroadcastArgs;
          return MobileSendStatusScreen(
            args: ledger.reviewArgs,
            ledger: ledger,
          );
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    _mobileLedgerHarness(
      fixture: fixture,
      lightwalletdUrl: lightwalletd.url,
      router: router,
      ble: ble,
      operationService: operationService,
      walletDbPath: dbPath,
    ),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval · 1 of 2')),
    description: 'mobile Ledger TEX first approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(requestedLightwalletdUrl, lightwalletd.url);
  expect(requestedNetwork, 'main');
  expect(requestedProposalId, args.proposalId);
  expect(requestedSendFlowId, args.sendFlowId);
  expect(
    await _approveNextReviewWhilePumping(tester, fixture.signingApiUrl),
    isTrue,
  );

  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval · 2 of 2')),
    description: 'mobile Ledger TEX second approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(
    await _approveNextReviewWhilePumping(tester, fixture.signingApiUrl),
    isTrue,
  );
  await _pumpUntil(
    tester,
    () =>
        tester.any(
          find.byKey(const ValueKey('mobile_send_status_succeeded')),
        ) ||
        operationService.lastBroadcastResult != null,
    description: 'mobile Ledger TEX broadcast result',
    timeout: const Duration(minutes: 2),
  );
  final broadcastResult = operationService.lastBroadcastResult;
  expect(broadcastResult, isNotNull);
  expect(
    broadcastResult!.status,
    'broadcasted',
    reason: broadcastResult.message,
  );
  await _pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('mobile_send_status_succeeded'))),
    description: 'mobile Ledger TEX success screen',
    timeout: const Duration(seconds: 10),
  );

  expect(operationService.checkpointCount, 1);
  expect(operationService.batchCheckpointCount, 1);
  expect(operationService.broadcastCount, 1);
  expect(lightwalletd.sendTransactionCount, 2);
  expect(lightwalletd.lastRawTransaction, isNotEmpty);
  expect(await operationService.list(), isEmpty);
}

enum _LedgerSwapScenario { pay, swap }

extension on _LedgerSwapScenario {
  bool get isPay => this == _LedgerSwapScenario.pay;

  String get label => isPay ? 'pay' : 'swap';

  String get intentId => 'ledger-mobile-$label-intent';

  LedgerSignedOperationKind get operationKind => isPay
      ? LedgerSignedOperationKind.payDeposit
      : LedgerSignedOperationKind.swapDeposit;

  SwapActivityReturnTarget get returnTarget =>
      isPay ? SwapActivityReturnTarget.pay : SwapActivityReturnTarget.swap;
}

Future<void> _runMobileSwapScenario(
  WidgetTester tester,
  _LedgerSwapScenario scenario,
) async {
  final fixture = _Fixture.load();
  final dbPath = await _copyFixtureDb(fixture);
  final lightwalletd = _AcceptingLightwalletd();
  await lightwalletd.start();
  addTearDown(lightwalletd.stop);
  final intent = _mobileSwapIntent(fixture, scenario);
  final swapProvider = _DeterministicSwapProvider(
    scenario: scenario,
    depositAddress: fixture.transparentAddress,
  );
  final operationService = _TrackingLedgerSignedOperationService(
    RustLedgerSignedOperationService(
      network: 'main',
      lightwalletdUrl: lightwalletd.url,
      loadWalletDbPath: () async => dbPath,
    ),
  );
  final hardwareSigningService = _SpeculosSwapHardwareSigningService(
    pcztBytes: fixture.pcztBytes,
  );
  final persistenceStore = _MemorySwapPersistenceStore();
  final ble = _SpeculosLedgerMobileBleService(fixture.signingApiUrl);
  final router = GoRouter(
    initialLocation: '/swap/ledger-sign',
    routes: [
      GoRoute(
        path: '/swap/ledger-sign',
        builder: (_, _) => MobileSwapLedgerSignScreen(
          args: MobileSwapLedgerSignArgs.fromReview(
            intent: intent,
            returnTarget: scenario.returnTarget,
          ),
        ),
      ),
      GoRoute(
        path: '/activity/swap/:swapId',
        builder: (_, _) =>
            const SizedBox(key: ValueKey('mobile_ledger_swap_complete')),
      ),
      GoRoute(
        path: '/pay/submitted/:swapId',
        builder: (_, _) =>
            const SizedBox(key: ValueKey('mobile_ledger_pay_complete')),
      ),
      GoRoute(path: '/swap', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/pay', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  final approval = _approveNextReview(fixture.signingApiUrl);

  await tester.pumpWidget(
    _mobileLedgerHarness(
      fixture: fixture,
      lightwalletdUrl: lightwalletd.url,
      router: router,
      ble: ble,
      operationService: operationService,
      walletDbPath: dbPath,
      extraOverrides: [
        swapIntentProvider.overrideWithValue(swapProvider),
        swapDepositSenderProvider.overrideWithValue(
          _FixtureSwapDepositSender(),
        ),
        swapMaxAmountEstimatorProvider.overrideWithValue(
          const _FixtureSwapMaxAmountEstimator(),
        ),
        swapHardwareSigningServiceProvider.overrideWithValue(
          hardwareSigningService,
        ),
        swapActivityStoreProvider.overrideWithValue(persistenceStore),
        swapComposerPreferencesStoreProvider.overrideWithValue(
          persistenceStore,
        ),
        paySelectedAssetStoreProvider.overrideWithValue(persistenceStore),
        swapZecStagingAddressServiceProvider.overrideWithValue(
          SwapZecStagingAddressService(
            loadCurrentShieldedAddress: ({required accountUuid}) async =>
                'u1ledgerrefundaddress',
          ),
        ),
        payDepositTransactionLoaderProvider.overrideWithValue(
          ({required accountUuid, required walletTxid}) async => null,
        ),
        swapStatusPollIntervalProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
        swapPriceRefreshIntervalProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
        rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
          (_) async => 'inert-no-failover',
        ),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_) async => BigInt.zero,
        ),
      ],
    ),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval')),
    description: 'mobile ${scenario.label} Ledger approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(await approval, isTrue);
  await _pumpUntil(
    tester,
    () => operationService.acknowledgeCount == 1,
    description: 'mobile ${scenario.label} Ledger broadcast acknowledgement',
    timeout: const Duration(minutes: 2),
  );
  final completionKey = ValueKey(
    scenario.isPay
        ? 'mobile_ledger_pay_complete'
        : 'mobile_ledger_swap_complete',
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(completionKey)),
    description: 'mobile ${scenario.label} completion route',
    timeout: const Duration(seconds: 10),
  );

  expect(operationService.checkpointCount, 1);
  expect(operationService.broadcastCount, 1);
  expect(operationService.acknowledgeCount, 1);
  expect(
    operationService.lastOperationId,
    '${scenario.operationKind.wireName}:${fixture.accountUuid}:${scenario.intentId}',
  );
  expect(swapProvider.submittedDepositCount, 1);
  expect(lightwalletd.sendTransactionCount, 1);
  expect(lightwalletd.lastRawTransaction, isNotEmpty);
  expect(hardwareSigningService.draftCount, 1);
  expect(hardwareSigningService.proofCount, 1);
  expect(hardwareSigningService.settleCount, 1);
  expect(find.byKey(completionKey), findsOneWidget);
  final record = persistenceStore.recordFor(
    accountUuid: fixture.accountUuid,
    intentId: scenario.intentId,
  );
  expect(record, isNotNull);
  expect(record!.payMode, scenario.isPay);
  expect(record.status, SwapIntentStatus.depositObserved);
  expect(record.depositTxHash, swapProvider.lastSubmittedTxHash);
}

Future<String> _copyFixtureDb(_Fixture fixture) async {
  final directory = await Directory.systemTemp.createTemp(
    'vizor-ledger-mobile-speculos-e2e.',
  );
  addTearDown(() => directory.delete(recursive: true));
  final dbPath = '${directory.path}/wallet.db';
  await File(
    dbPath,
  ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);
  return dbPath;
}

const _completeSaplingParams = SaplingParamsStatus(
  spendPath: '/tmp/spend.params',
  outputPath: '/tmp/output.params',
  spendExists: true,
  outputExists: true,
);

Widget _mobileLedgerHarness({
  required _Fixture fixture,
  required String lightwalletdUrl,
  required GoRouter router,
  required _SpeculosLedgerMobileBleService ble,
  required _TrackingLedgerSignedOperationService operationService,
  required String walletDbPath,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _ledgerBootstrap(fixture, lightwalletdUrl),
      ),
      networkPrivacyProvider.overrideWith(_DirectNetworkPrivacyNotifier.new),
      syncProvider.overrideWith(() => _FakeSyncNotifier(fixture.accountUuid)),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.iOS),
      ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ledgerWalletDbPathProvider.overrideWithValue(() async => walletDbPath),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      ledgerSignedOperationServiceProvider.overrideWithValue(operationService),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.maybeOf(context);
        final themed = AppTheme(data: AppThemeData.light, child: child!);
        if (media == null) return themed;
        return MediaQuery(
          data: media.copyWith(disableAnimations: true),
          child: themed,
        );
      },
    ),
  );
}

AppBootstrapState _ledgerBootstrap(_Fixture fixture, String lightwalletdUrl) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: fixture.accountUuid,
          name: 'Speculos Ledger',
          order: 0,
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
          zip32AccountIndex: fixture.accountIndex,
          ledgerConnectionPreference: LedgerConnectionPreference.bluetooth,
          ledgerDeviceId: _SpeculosLedgerMobileBleService.device.id,
          ledgerDeviceName: _SpeculosLedgerMobileBleService.device.name,
          ledgerDeviceModel: _SpeculosLedgerMobileBleService.device.model,
        ),
      ],
      activeAccountUuid: fixture.accountUuid,
      activeAddress: fixture.transparentAddress,
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: lightwalletdUrl,
      presetId: kCustomRpcEndpointPresetId,
    ),
    themeMode: ThemeMode.light,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

class _MobileSendLauncher extends StatefulWidget {
  const _MobileSendLauncher({required this.args});

  final SendReviewArgs args;

  @override
  State<_MobileSendLauncher> createState() => _MobileSendLauncherState();
}

class _MobileSendLauncherState extends State<_MobileSendLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSigning());
  }

  Future<void> _openSigning() async {
    final ledger = await context.push<LedgerBroadcastArgs>(
      '/send/ledger-sign',
      extra: widget.args,
    );
    if (!mounted || ledger == null) return;
    context.go('/send/status', extra: ledger);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox(key: ValueKey('mobile_ledger_send_launcher')),
    );
  }
}

SwapIntent _mobileSwapIntent(_Fixture fixture, _LedgerSwapScenario scenario) {
  final now = DateTime.now().toUtc();
  return SwapIntent(
    id: scenario.intentId,
    pair: 'ZEC → USDC',
    sellAmount: '0.0099 ZEC',
    receiveEstimate: '0.693 USDC',
    provider: 'Ledger E2E provider',
    status: SwapIntentStatus.awaitingDeposit,
    nextAction: 'Sign and send the ZEC deposit with Ledger.',
    sellAmountBaseUnits: BigInt.from(990000),
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: fixture.transparentAddress,
    providerQuoteId: 'ledger-mobile-${scenario.label}-quote',
    swapFeeText: 'Network fee included',
    minimumReceiveText: '0.689535 USDC',
    oneClickRecipient: _externalRecipient,
    oneClickRefundTo: 'u1ledgerrefundaddress',
    depositDeadline: now.add(const Duration(minutes: 10)),
    accountUuid: fixture.accountUuid,
    payMode: scenario.isPay,
    createdAt: now,
    updatedAt: now,
  );
}

const _externalRecipient = '0x52908400098527886e0f7030069857d2e4169ee7';

class _DirectNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}

class _LedgerFirstAccountSecurityNotifier extends AppSecurityNotifier {
  String? preparedPassword;
  var commitCount = 0;
  var rollbackCount = 0;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);

  @override
  Future<void> preparePasswordSetup(String password) async {
    preparedPassword = password;
  }

  @override
  void commitPasswordSetup() {
    commitCount++;
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  @override
  Future<void> rollbackPasswordSetup() async {
    rollbackCount++;
  }
}

class _RecordingLedgerFirstAccountImport {
  _RecordingLedgerFirstAccountImport(this.dbPath);

  final String dbPath;
  LedgerDeviceAccount? account;
  String? name;
  int? birthdayHeight;

  Future<void> call({
    required String name,
    required LedgerDeviceAccount account,
    required int birthdayHeight,
    required String profilePictureId,
  }) async {
    await rust_wallet.importHardwareAccount(
      dbPath: dbPath,
      network: 'main',
      name: name,
      ufvkString: account.ufvk,
      seedFingerprint: account.seedFingerprint,
      zip32Index: account.accountIndex,
      birthdayHeight: BigInt.from(birthdayHeight),
      hardwareSignerKind: HardwareSignerKind.ledger.name,
    );
    this.account = account;
    this.name = name;
    this.birthdayHeight = birthdayHeight;
  }
}

class _AvailableBiometricNotifier extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async => const BiometricUnlockState(
    availability: BiometricAvailability(
      supported: true,
      enrolled: false,
      kind: BiometricKind.face,
    ),
    enabled: false,
  );
}

class _LedgerOnboardingRpcFailoverNotifier extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() {
    final endpoint = defaultRpcEndpointConfig('main');
    return RpcEndpointFailoverState(
      primary: endpoint,
      current: endpoint,
      fallbackCandidates: const [],
    );
  }

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    if (operation == 'import birthday metadata') {
      return ImportBirthdayMetadata(
            saplingActivationHeight: 419200,
            saplingActivationDate: DateTime(2016, 10, 28),
            tipHeight: 3336000,
            tipDate: DateTime(2026, 5, 11),
          )
          as T;
    }
    return action(state.current);
  }
}

class _Fixture {
  const _Fixture({
    required this.ufvkApiUrl,
    required this.signingApiUrl,
    required this.ufvk,
    required this.seedFingerprint,
    required this.accountUuid,
    required this.accountIndex,
    required this.transparentAddress,
    required this.texAddress,
    required this.pcztBytes,
    required this.texStep1PcztBytes,
    required this.texStep2PcztBytes,
    required this.votingBundlePczts,
    required this.votingActionIndexes,
    required this.orchardToIronwoodV6Pczt,
    required this.dbGzipBytes,
  });

  final String ufvkApiUrl;
  final String signingApiUrl;
  final String ufvk;
  final List<int> seedFingerprint;
  final String accountUuid;
  final int accountIndex;
  final String transparentAddress;
  final String texAddress;
  final List<int> pcztBytes;
  final List<int> texStep1PcztBytes;
  final List<int> texStep2PcztBytes;
  final List<List<int>> votingBundlePczts;
  final List<int> votingActionIndexes;
  final List<int> orchardToIronwoodV6Pczt;
  final List<int> dbGzipBytes;

  static _Fixture load() {
    const ufvkApiUrl = String.fromEnvironment('VIZOR_LEDGER_E2E_UFVK_API_URL');
    const signingApiUrl = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_SIGNING_API_URL',
    );
    const ufvk = String.fromEnvironment('VIZOR_LEDGER_E2E_UFVK');
    const seedFingerprint = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_SEED_FINGERPRINT',
    );
    const accountUuid = String.fromEnvironment('VIZOR_LEDGER_E2E_ACCOUNT_UUID');
    const transparentAddress = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_TRANSPARENT_ADDRESS',
    );
    const texAddress = String.fromEnvironment('VIZOR_LEDGER_E2E_TEX_ADDRESS');
    const pcztBase64 = String.fromEnvironment('VIZOR_LEDGER_E2E_PCZT_BASE64');
    const texStep1PcztBase64 = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_TEX_STEP_1_PCZT_BASE64',
    );
    const texStep2PcztBase64 = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_TEX_STEP_2_PCZT_BASE64',
    );
    const votingBundle1PcztBase64 = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_VOTING_BUNDLE_1_PCZT_BASE64',
    );
    const votingBundle2PcztBase64 = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_VOTING_BUNDLE_2_PCZT_BASE64',
    );
    const orchardToIronwoodV6PcztBase64 = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_ORCHARD_TO_IRONWOOD_V6_PCZT_BASE64',
    );
    const votingBundle1ActionIndex = int.fromEnvironment(
      'VIZOR_LEDGER_E2E_VOTING_BUNDLE_1_ACTION_INDEX',
      defaultValue: -1,
    );
    const votingBundle2ActionIndex = int.fromEnvironment(
      'VIZOR_LEDGER_E2E_VOTING_BUNDLE_2_ACTION_INDEX',
      defaultValue: -1,
    );
    const dbGzipBase64 = String.fromEnvironment(
      'VIZOR_LEDGER_E2E_DB_GZIP_BASE64',
    );
    if (ufvkApiUrl.isEmpty ||
        signingApiUrl.isEmpty ||
        ufvk.isEmpty ||
        seedFingerprint.isEmpty ||
        accountUuid.isEmpty ||
        transparentAddress.isEmpty ||
        texAddress.isEmpty ||
        pcztBase64.isEmpty ||
        texStep1PcztBase64.isEmpty ||
        texStep2PcztBase64.isEmpty ||
        votingBundle1PcztBase64.isEmpty ||
        votingBundle2PcztBase64.isEmpty ||
        orchardToIronwoodV6PcztBase64.isEmpty ||
        votingBundle1ActionIndex < 0 ||
        votingBundle2ActionIndex < 0 ||
        dbGzipBase64.isEmpty) {
      throw StateError(
        'Ledger mobile fixture dart-defines are missing. Run the Speculos E2E script.',
      );
    }
    return _Fixture(
      ufvkApiUrl: ufvkApiUrl,
      signingApiUrl: signingApiUrl,
      ufvk: ufvk,
      seedFingerprint: _decodeHex(seedFingerprint),
      accountUuid: accountUuid,
      accountIndex: 0,
      transparentAddress: transparentAddress,
      texAddress: texAddress,
      pcztBytes: base64Decode(pcztBase64),
      texStep1PcztBytes: base64Decode(texStep1PcztBase64),
      texStep2PcztBytes: base64Decode(texStep2PcztBase64),
      votingBundlePczts: [
        base64Decode(votingBundle1PcztBase64),
        base64Decode(votingBundle2PcztBase64),
      ],
      votingActionIndexes: [votingBundle1ActionIndex, votingBundle2ActionIndex],
      orchardToIronwoodV6Pczt: base64Decode(orchardToIronwoodV6PcztBase64),
      dbGzipBytes: base64Decode(dbGzipBase64),
    );
  }
}

class _DeterministicSwapProvider implements SwapProvider, SwapPricingProvider {
  _DeterministicSwapProvider({
    required this.scenario,
    required this.depositAddress,
  });

  final _LedgerSwapScenario scenario;
  final String depositAddress;
  int submittedDepositCount = 0;
  String lastSubmittedTxHash = '';

  @override
  String get providerLabel => 'Ledger E2E provider';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return const [SwapAsset.usdc];
  }

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) async {
    return SwapPricingSnapshot(
      usdPrices: {SwapAsset.zec: 70, SwapAsset.usdc: 1},
    );
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 10));
    final estimate = SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      amount: request.amount,
      mode: request.mode,
      externalPerZec: 70,
      slippageBps: request.slippageBps ?? 50,
      quoteExpiresAt: expiresAt,
      depositDeadline: expiresAt,
    );
    return SwapQuote(
      direction: estimate.direction,
      sellAsset: estimate.sellAsset,
      receiveAsset: estimate.receiveAsset,
      externalAsset: estimate.externalAsset,
      mode: estimate.mode,
      sellAmount: 0.0099,
      receiveAmount: 0.693,
      minimumReceiveAmount: 0.689535,
      providerLabel: providerLabel,
      feeLabel: estimate.feeLabel,
      expiryLabel: '10:00',
      quoteExpiresAt: expiresAt,
      providerQuoteId: 'ledger-mobile-${scenario.label}-quote',
      sellAmountBaseUnits: BigInt.from(990000),
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: depositAddress,
        expiresInLabel: '10:00',
        reuseWarning: 'Do not reuse this address',
        deadline: expiresAt,
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    return _snapshot(SwapIntentStatus.awaitingDeposit);
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    return _snapshot(SwapIntentStatus.depositObserved);
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    if (depositAddress != this.depositAddress) {
      throw StateError('Ledger mobile E2E deposit address changed.');
    }
    submittedDepositCount++;
    lastSubmittedTxHash = txHash;
    return _snapshot(
      SwapIntentStatus.depositObserved,
      originChainTxHash: txHash,
    );
  }

  SwapIntentSnapshot _snapshot(
    SwapIntentStatus status, {
    String? originChainTxHash,
  }) {
    final deadline = DateTime.now().toUtc().add(const Duration(minutes: 10));
    return SwapIntentSnapshot(
      id: scenario.intentId,
      providerLabel: providerLabel,
      pairText: 'ZEC → USDC',
      sellAmountText: '0.0099 ZEC',
      receiveEstimateText: '0.693 USDC',
      status: status,
      nextAction: status == SwapIntentStatus.depositObserved
          ? 'Deposit detected'
          : 'Send the ZEC deposit',
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: depositAddress,
        expiresInLabel: '10:00',
        reuseWarning: 'Do not reuse this address',
        deadline: deadline,
      ),
      sellAmountBaseUnits: BigInt.from(990000),
      minimumReceiveText: '0.689535 USDC',
      originChainTxHash: originChainTxHash,
    );
  }
}

class _FixtureSwapDepositSender implements SwapDepositSender {
  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    return BigInt.from(10000);
  }

  @override
  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) {
    throw StateError('Ledger E2E must not use the mnemonic deposit sender.');
  }
}

class _FixtureSwapMaxAmountEstimator implements SwapMaxAmountEstimator {
  const _FixtureSwapMaxAmountEstimator();

  @override
  Future<BigInt> estimateMaxZecSellAmount({required String accountUuid}) async {
    return BigInt.from(990000);
  }
}

class _SpeculosSwapHardwareSigningService
    implements SwapHardwareSigningService {
  _SpeculosSwapHardwareSigningService({required List<int> pcztBytes})
    : _pcztBytes = List<int>.unmodifiable(pcztBytes);

  final List<int> _pcztBytes;
  int draftCount = 0;
  int proofCount = 0;
  int settleCount = 0;

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    draftCount++;
    return SwapHardwarePcztDraft(
      pcztBytes: _pcztBytes,
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
      proposalId: BigInt.one,
      sendFlowId: 'ledger-mobile-${intent.payMode ? 'pay' : 'swap'}-e2e',
    );
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    proofCount++;
    return rust_sync.addProofsToPczt(pcztBytes: draft.pcztBytes);
  }

  @override
  Future<void> settlePcztDraftAfterLedgerBroadcast({
    required SwapHardwarePcztDraft draft,
    required String? status,
  }) async {
    settleCount++;
  }

  @override
  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft}) async {}

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) {
    throw StateError('Ledger E2E must not use Keystone UR encoding.');
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    throw StateError('Ledger E2E must use the durable operation service.');
  }
}

class _MemorySwapPersistenceStore
    implements
        SwapActivityStore,
        SwapComposerPreferencesStore,
        PaySelectedAssetStore {
  final _records = <String, List<SwapIntentRecord>>{};
  final _preferences = <String, SwapComposerPreferences>{};
  final _payAssets = <String, SwapAsset>{};

  SwapIntentRecord? recordFor({
    required String accountUuid,
    required String intentId,
  }) {
    for (final record in _records[accountUuid] ?? const []) {
      if (record.id == intentId) return record;
    }
    return null;
  }

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return List<SwapIntentRecord>.from(_records[accountUuid] ?? const []);
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    _records[accountUuid] = List<SwapIntentRecord>.from(records);
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    _records.remove(accountUuid);
  }

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async {
    return _preferences[accountUuid];
  }

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {
    _preferences[accountUuid] = preferences;
  }

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    return _payAssets[accountUuid];
  }

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {
    _payAssets[accountUuid] = asset;
  }
}

class _TrackingLedgerSignedOperationService
    implements
        LedgerSignedOperationService,
        LedgerSignedOperationBatchCheckpointService {
  _TrackingLedgerSignedOperationService(this.delegate);

  final LedgerSignedOperationService delegate;
  int checkpointCount = 0;
  int batchCheckpointCount = 0;
  int broadcastCount = 0;
  int acknowledgeCount = 0;
  String? lastOperationId;
  LedgerSignedOperationBroadcastResult? lastBroadcastResult;
  final callOrder = <String>[];

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    callOrder.add('checkpoint');
    checkpointCount++;
    lastOperationId = operationId;
    await delegate.checkpoint(
      operationId: operationId,
      accountUuid: accountUuid,
      kind: kind,
      pcztWithProofsBytes: pcztWithProofsBytes,
      pcztWithSignaturesBytes: pcztWithSignaturesBytes,
      externalRef: externalRef,
    );
  }

  @override
  Future<void> checkpointBatch({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<List<int>> pcztsWithProofs,
    required List<List<int>> pcztsWithSignatures,
    String? externalRef,
  }) async {
    callOrder.add('checkpointBatch');
    checkpointCount++;
    batchCheckpointCount++;
    lastOperationId = operationId;
    await (delegate as LedgerSignedOperationBatchCheckpointService)
        .checkpointBatch(
          operationId: operationId,
          accountUuid: accountUuid,
          kind: kind,
          pcztsWithProofs: pcztsWithProofs,
          pcztsWithSignatures: pcztsWithSignatures,
          externalRef: externalRef,
        );
  }

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    callOrder.add('broadcast');
    broadcastCount++;
    lastOperationId = operationId;
    final result = await delegate.broadcast(
      operationId: operationId,
      spendParamsPath: spendParamsPath,
      outputParamsPath: outputParamsPath,
    );
    lastBroadcastResult = result;
    return result;
  }

  @override
  Future<List<LedgerSignedOperationMetadata>> list() => delegate.list();

  @override
  Future<void> acknowledge(String operationId) async {
    acknowledgeCount++;
    lastOperationId = operationId;
    await delegate.acknowledge(operationId);
  }
}

class _AcceptingLightwalletd extends service_grpc.CompactTxStreamerServiceBase {
  grpc.Server? _server;
  int sendTransactionCount = 0;
  List<int> lastRawTransaction = const [];

  String get url {
    final port = _server?.port;
    if (port == null) throw StateError('Test lightwalletd is not running.');
    return 'http://127.0.0.1:$port';
  }

  Future<void> start() async {
    _server = grpc.Server.create(services: [this]);
    await _server!.serve(address: InternetAddress.loopbackIPv4, port: 0);
  }

  Future<void> stop() async {
    await _server?.shutdown();
    _server = null;
  }

  @override
  Future<service.BlockID> getLatestBlock(
    grpc.ServiceCall call,
    service.ChainSpec request,
  ) async {
    return service.BlockID(height: Int64(1));
  }

  @override
  Future<service.SendResponse> sendTransaction(
    grpc.ServiceCall call,
    service.RawTransaction request,
  ) async {
    sendTransactionCount++;
    lastRawTransaction = List<int>.unmodifiable(request.data);
    return service.SendResponse(errorCode: 0, errorMessage: '');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpeculosLedgerMobileBleService implements LedgerMobileBleService {
  _SpeculosLedgerMobileBleService(this.apiUrl);

  static const device = LedgerBleDevice(
    id: 'speculos',
    name: 'Speculos Ledger',
    model: 'Nano X',
  );

  final String apiUrl;

  @override
  String? connectedDeviceId;

  @override
  Future<void> cancelSigning() async {}

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectedDeviceId = device.id;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    _requireConnected();
    final response = await _exchangeRaw(
      rust_ledger.LedgerApduCommand(
        cla: 0xb0,
        ins: 0x01,
        p1: 0,
        p2: 0,
        data: Uint8List(0),
      ),
    );
    _requireSuccess(response);
    final payload = response.sublist(0, response.length - 2);
    if (payload.isEmpty || payload.first != 1) {
      throw const LedgerMobileException(
        LedgerMobileFailure.unavailable,
        'Speculos returned invalid app metadata.',
      );
    }
    var index = 1;
    String readString() {
      if (index >= payload.length) {
        throw const LedgerMobileException(
          LedgerMobileFailure.unavailable,
          'Speculos returned truncated app metadata.',
        );
      }
      final length = payload[index++];
      final end = index + length;
      if (end > payload.length) {
        throw const LedgerMobileException(
          LedgerMobileFailure.unavailable,
          'Speculos returned truncated app metadata.',
        );
      }
      final value = utf8.decode(payload.sublist(index, end));
      index = end;
      return value;
    }

    return LedgerMobileAppInfo(name: readString(), version: readString());
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() async* {
    yield const LedgerDevicesDiscovered([device]);
  }

  @override
  Future<void> disconnect() async {
    connectedDeviceId = null;
  }

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<rust_ledger.LedgerApduCommand> commands,
  ) async {
    _requireConnected();
    final responses = <Uint8List>[];
    for (final command in commands) {
      final response = await _exchangeRaw(command);
      responses.add(response);
      if (!_hasSuccessStatus(response)) break;
    }
    return responses;
  }

  @override
  Future<List<Uint8List>> exchangeUfvk(
    rust_ledger.LedgerUfvkApduPlan plan,
  ) async {
    _requireConnected();
    final responses = <Uint8List>[];
    final first = await _exchangeRaw(plan.first);
    responses.add(first);
    if (!_hasSuccessStatus(first) || first.length < 4) return responses;

    final expectedPayloadLength = 2 + (first[0] << 8) + first[1];
    var payloadLength = first.length - 2;
    while (payloadLength < expectedPayloadLength) {
      final response = await _exchangeRaw(plan.continuation);
      responses.add(response);
      if (!_hasSuccessStatus(response) || response.length == 2) break;
      payloadLength += response.length - 2;
    }
    return responses;
  }

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() => currentApp();

  @override
  Future<void> stopDiscovery() async {}

  void _requireConnected() {
    if (connectedDeviceId == null) {
      throw const LedgerMobileException(
        LedgerMobileFailure.disconnected,
        'Speculos Ledger is disconnected.',
      );
    }
  }

  Future<Uint8List> _exchangeRaw(rust_ledger.LedgerApduCommand command) async {
    if (command.data.length > 255) {
      throw const LedgerMobileException(
        LedgerMobileFailure.unavailable,
        'Speculos APDU payload exceeds 255 bytes.',
      );
    }
    final bytes = <int>[
      command.cla,
      command.ins,
      command.p1,
      command.p2,
      command.data.length,
      ...command.data,
    ];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$apiUrl/apdu'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'data': _encodeHex(bytes)}));
      final response = await request.close().timeout(
        const Duration(minutes: 2),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Speculos APDU returned HTTP ${response.statusCode}: $body',
        );
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return Uint8List.fromList(_decodeHex(decoded['data']! as String));
    } finally {
      client.close(force: true);
    }
  }
}

List<int> _decodeHex(String value) {
  if (value.length.isOdd) {
    throw StateError('Speculos returned invalid hex.');
  }
  return [
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
}

String _encodeHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

bool _hasSuccessStatus(List<int> response) =>
    response.length >= 2 &&
    response[response.length - 2] == 0x90 &&
    response.last == 0;

void _requireSuccess(List<int> response) {
  if (!_hasSuccessStatus(response)) {
    throw const LedgerMobileException(
      LedgerMobileFailure.unavailable,
      'Speculos Ledger returned a failed status.',
    );
  }
}

Future<bool> _approveNextReview(String apiUrl) async {
  final client = HttpClient();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var reviewStarted = false;
  try {
    while (DateTime.now().isBefore(deadline)) {
      final screen = await _currentScreenText(client, apiUrl);
      final normalized = screen.toLowerCase();
      if (normalized.contains('review') ||
          normalized.contains('export') ||
          normalized.contains('viewing key')) {
        reviewStarted = true;
      }
      if (reviewStarted) {
        if (normalized.contains('approve') ||
            normalized.contains('accept') ||
            normalized.contains('confirm') ||
            normalized.contains('sign transaction')) {
          await _pressButton(client, apiUrl, 'both');
          return true;
        }
        await _pressButton(
          client,
          apiUrl,
          normalized.contains('cancel') ? 'left' : 'right',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException('Speculos review did not become approvable.');
  } finally {
    client.close();
  }
}

Future<bool> _approveNextReviewWhilePumping(
  WidgetTester tester,
  String apiUrl,
) async {
  bool? approved;
  Object? failure;
  StackTrace? failureStackTrace;
  unawaited(
    _approveNextReview(apiUrl).then<void>(
      (value) => approved = value,
      onError: (Object error, StackTrace stackTrace) {
        failure = error;
        failureStackTrace = stackTrace;
      },
    ),
  );
  await _pumpUntil(
    tester,
    () => approved != null || failure != null,
    description: 'Speculos Ledger approval',
    timeout: const Duration(minutes: 2),
  );
  if (failure case final error?) {
    Error.throwWithStackTrace(error, failureStackTrace!);
  }
  return approved!;
}

Future<String> _currentScreenText(HttpClient client, String apiUrl) async {
  final request = await client.getUrl(
    Uri.parse('$apiUrl/events?currentscreenonly=true'),
  );
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Speculos events returned HTTP ${response.statusCode}.',
    );
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final events = decoded['events']! as List<dynamic>;
  return events
      .cast<Map<String, dynamic>>()
      .map((event) => event['text'])
      .whereType<String>()
      .join(' ');
}

Future<void> _pressButton(
  HttpClient client,
  String apiUrl,
  String button,
) async {
  final request = await client.postUrl(Uri.parse('$apiUrl/button/$button'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'action': 'press-and-release'}));
  final response = await request.close();
  await response.drain<void>();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Speculos button returned HTTP ${response.statusCode}.',
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Timed out waiting for $description.');
}

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.accountUuid);

  final String accountUuid;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: accountUuid,
    hasAccountScopedData: true,
    chainTipHeight: 4000000,
    spendableBalance: BigInt.from(100000000),
    displaySpendableBalance: BigInt.from(100000000),
    totalBalance: BigInt.from(100000000),
  );
}

class _EmptySyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(chainTipHeight: 4000000);
}
