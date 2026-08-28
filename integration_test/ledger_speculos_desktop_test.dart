import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/home/widgets/ledger_shield_signing_overlay.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/pay/screens/pay_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/send_review_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/send_status_screen.dart';
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
import 'package:zcash_wallet/src/features/swap/screens/swap_review_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;
import 'package:zcash_wallet/src/generated/service.pbgrpc.dart' as service_grpc;
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'imports and sends with Ledger through Speculos',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixture = _Fixture.load();
      final sandboxDirectory = await Directory.systemTemp.createTemp(
        'vizor-ledger-speculos-e2e.',
      );
      final dbPath = '${sandboxDirectory.path}/wallet.db';
      await File(
        dbPath,
      ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);
      final security = _LedgerFirstAccountSecurityNotifier();
      final firstAccountDbPath =
          '${sandboxDirectory.path}/first-account-wallet.db';
      final firstAccountImport = _RecordingLedgerFirstAccountImport(
        firstAccountDbPath,
      );

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('ledger_speculos_import_scope'),
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            appSecurityProvider.overrideWith(() => security),
            syncProvider.overrideWith(
              () => _FakeSyncNotifier(fixture.accountUuid),
            ),
            ledgerTargetPlatformProvider.overrideWithValue(
              TargetPlatform.macOS,
            ),
            ledgerOperationCancellerProvider.overrideWithValue(() async {}),
            ledgerAccountImporterProvider.overrideWithValue(
              firstAccountImport.call,
            ),
            rpcEndpointFailoverProvider.overrideWith(
              _LedgerOnboardingRpcFailoverNotifier.new,
            ),
          ],
          child: const _LedgerFirstAccountOnboardingHarness(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('welcome_connect_ledger_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('welcome_connect_ledger_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect Ledger'), findsWidgets);
      expect(
        find.byKey(const ValueKey('ledger_connect_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('ledger_connect_button')));
      await tester.pump();
      final connectSpinner = find.byKey(
        const ValueKey('ledger_connect_spinner'),
      );
      expect(connectSpinner, findsOneWidget);
      expect(
        tester.getCenter(connectSpinner).dx,
        greaterThan(
          tester
              .getCenter(find.byKey(const ValueKey('ledger_connect_button')))
              .dx,
        ),
      );
      final importApproval = _approveNextReview(fixture.ufvkApiUrl);
      await _pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('import_birthday_submit_button')),
        ),
        description: 'Ledger birthday route',
        timeout: const Duration(minutes: 2),
      );
      expect(await importApproval, isTrue);

      await tester.tap(find.text('Enter the block height'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '2500000');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('import_birthday_submit_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('set_password_password_field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('set_password_password_field')),
        'LedgerE2e1!',
      );
      await tester.enterText(
        find.byKey(const ValueKey('set_password_confirm_field')),
        'LedgerE2e1!',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('set_password_submit_button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('customise_account_name_field')),
        'Speculos Ledger',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('customise_account_finish_button')),
      );
      await _pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('ledger_first_account_home'))),
        description: 'Home after first Ledger account creation',
        timeout: const Duration(minutes: 2),
      );

      final exported = firstAccountImport.account;
      expect(exported, isNotNull);
      expect(exported!.ufvk, fixture.ufvk);
      expect(exported.seedFingerprint, fixture.seedFingerprint);
      expect(exported.accountIndex, fixture.accountIndex);
      expect(exported.appVersion, '3.9.2');
      expect(firstAccountImport.name, 'Speculos Ledger');
      expect(firstAccountImport.birthdayHeight, 2500000);
      expect(security.preparedPassword, 'LedgerE2e1!');
      expect(security.commitCount, 1);
      expect(security.rollbackCount, 0);
      final storedFirstAccounts = await rust_wallet.listAccounts(
        dbPath: firstAccountDbPath,
        network: 'main',
      );
      expect(storedFirstAccounts, hasLength(1));
      expect(storedFirstAccounts.single.name, 'Speculos Ledger');
      expect(storedFirstAccounts.single.isHardware, isTrue);
      expect(storedFirstAccounts.single.hardwareSignerKind, 'ledger');
      expect(
        storedFirstAccounts.single.zip32AccountIndex,
        fixture.accountIndex,
      );
      expect(storedFirstAccounts.single.birthdayHeight, 2500000);

      final lightwalletd = _AcceptingLightwalletd();
      await lightwalletd.start();
      addTearDown(lightwalletd.stop);
      final reviewArgs = SendReviewArgs(
        proposalId: BigInt.one,
        sendFlowId: 'ledger-speculos-send',
        proposalAccountUuid: fixture.accountUuid,
        address: fixture.transparentAddress,
        addressType: 'transparent',
        amountZatoshi: BigInt.from(990000),
        feeZatoshi: BigInt.from(10000),
        needsSaplingParams: false,
      );
      final operationService = _TrackingLedgerSignedOperationService(
        RustLedgerSignedOperationService(
          network: 'main',
          lightwalletdUrl: lightwalletd.url,
          loadWalletDbPath: () async => dbPath,
        ),
      );
      final sendRouter = GoRouter(
        initialLocation: '/send/review?flow=${reviewArgs.sendFlowId}',
        initialExtra: reviewArgs,
        routes: [
          GoRoute(path: '/send', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
          GoRoute(
            path: '/send/review',
            builder: (_, state) =>
                SendReviewScreen(args: state.extra! as SendReviewArgs),
          ),
          GoRoute(
            path: '/send/status',
            builder: (_, state) {
              final payload = state.extra! as LedgerBroadcastArgs;
              return SendStatusScreen(
                args: payload.reviewArgs,
                ledger: payload,
              );
            },
          ),
        ],
      );
      addTearDown(sendRouter.dispose);

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('ledger_speculos_send_scope'),
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _ledgerBootstrap(
                fixture,
                lightwalletd.url,
                initialLocation: '/send/review',
              ),
            ),
            syncProvider.overrideWith(
              () => _FakeSyncNotifier(fixture.accountUuid),
            ),
            addressBookRepositoryProvider.overrideWithValue(
              _EmptyAddressBookRepository(),
            ),
            zecMarketDataSourceProvider.overrideWithValue(
              const _EmptyMarketDataSource(),
            ),
            zecMarketDataCacheProvider.overrideWithValue(
              _MemoryMarketDataCache(),
            ),
            ledgerTargetPlatformProvider.overrideWithValue(
              TargetPlatform.macOS,
            ),
            ledgerWalletDbPathProvider.overrideWithValue(() async => dbPath),
            ledgerSendBasePcztCreatorProvider.overrideWithValue(({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required proposalId,
              required sendFlowId,
            }) async {
              expect(dbPath, endsWith('/wallet.db'));
              expect(lightwalletdUrl, lightwalletd.url);
              expect(network, 'main');
              expect(proposalId, reviewArgs.proposalId);
              expect(sendFlowId, reviewArgs.sendFlowId);
              return Uint8List.fromList(fixture.pcztBytes);
            }),
            ledgerSignedOperationServiceProvider.overrideWithValue(
              operationService,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: sendRouter,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review send'), findsOneWidget);
      expect(find.byKey(const ValueKey('send_confirm_button')), findsOneWidget);

      final signingApproval = _approveNextReview(fixture.signingApiUrl);
      await tester.tap(find.byKey(const ValueKey('send_confirm_button')));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => tester.any(find.text('Waiting for approval')),
        description: 'Ledger device approval prompt',
        timeout: const Duration(minutes: 2),
      );
      await _pumpUntil(
        tester,
        () => tester.any(find.byKey(const ValueKey('send_status_completed'))),
        description: 'Ledger Send status completion',
        timeout: const Duration(minutes: 2),
      );
      expect(await signingApproval, isTrue);
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(operationService.checkpointCount, 1);
      expect(operationService.broadcastCount, 1);
      expect(
        operationService.lastOperationId,
        'send:${fixture.accountUuid}:ledger-speculos-send',
      );
      expect(lightwalletd.sendTransactionCount, 1);
      expect(lightwalletd.lastRawTransaction, isNotEmpty);
      expect(await operationService.list(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'sends to TEX with two Ledger approvals through Speculos',
    _runLedgerTexSendScenario,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'shields transparent balance with Ledger through Speculos',
    _runLedgerShieldScenario,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'pays with Ledger through Speculos',
    (tester) => _runLedgerSwapScenario(tester, _LedgerSwapScenario.pay),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'swaps with Ledger through Speculos',
    (tester) => _runLedgerSwapScenario(tester, _LedgerSwapScenario.swap),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'signs sequential voting bundles with Ledger through Speculos',
    _runLedgerVotingSigningScenario,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'signs sequential Ledger operations in one app lifecycle',
    (tester) async {
      final fixture = _Fixture.load();
      final sandboxDirectory = await Directory.systemTemp.createTemp(
        'vizor-ledger-sequential-speculos-e2e.',
      );
      final dbPath = '${sandboxDirectory.path}/wallet.db';
      await File(
        dbPath,
      ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _ledgerBootstrap(
              fixture,
              'http://127.0.0.1:1',
              initialLocation: '/home',
            ),
          ),
          ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
          ledgerWalletDbPathProvider.overrideWithValue(() async => dbPath),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      Future<void> signRound() async {
        final approval = _approveNextReview(fixture.signingApiUrl);
        final signed = container.read(ledgerPcztSignerProvider)(
          fixture.accountUuid,
          fixture.pcztBytes,
        );
        expect(await approval, isTrue);
        expect(await signed, isNotEmpty);
      }

      await signRound();
      await signRound();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _runLedgerVotingSigningScenario(WidgetTester tester) async {
  final fixture = _Fixture.load();
  final sandboxDirectory = await Directory.systemTemp.createTemp(
    'vizor-ledger-voting-speculos-e2e.',
  );
  addTearDown(() => sandboxDirectory.delete(recursive: true));
  final dbPath = '${sandboxDirectory.path}/wallet.db';
  await File(
    dbPath,
  ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _ledgerBootstrap(
          fixture,
          'http://127.0.0.1:1',
          initialLocation: '/home',
        ),
      ),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
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
    final approval = _approveNextReview(fixture.signingApiUrl);
    final signatures = container.read(ledgerVotingPcztSignerProvider)(
      fixture.accountUuid,
      pczt,
    );
    expect(await approval, isTrue);
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

final _desktopOnboardingRoutesProvider = Provider(appDesktopOnboardingRoutes);

class _LedgerFirstAccountOnboardingHarness extends ConsumerStatefulWidget {
  const _LedgerFirstAccountOnboardingHarness();

  @override
  ConsumerState<_LedgerFirstAccountOnboardingHarness> createState() =>
      _LedgerFirstAccountOnboardingHarnessState();
}

class _LedgerFirstAccountOnboardingHarnessState
    extends ConsumerState<_LedgerFirstAccountOnboardingHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        ...ref.read(_desktopOnboardingRoutesProvider),
        GoRoute(
          path: '/home',
          builder: (_, _) =>
              const SizedBox(key: ValueKey('ledger_first_account_home')),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    );
  }
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

enum _LedgerSwapScenario { pay, swap }

extension on _LedgerSwapScenario {
  bool get isPay => this == _LedgerSwapScenario.pay;

  String get label => isPay ? 'pay' : 'swap';

  String get intentId => 'ledger-$label-intent';

  LedgerSignedOperationKind get operationKind => isPay
      ? LedgerSignedOperationKind.payDeposit
      : LedgerSignedOperationKind.swapDeposit;
}

Future<void> _runLedgerShieldScenario(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final fixture = _Fixture.load();
  final sandboxDirectory = await Directory.systemTemp.createTemp(
    'vizor-ledger-shield-speculos-e2e.',
  );
  addTearDown(() => sandboxDirectory.delete(recursive: true));
  final dbPath = '${sandboxDirectory.path}/wallet.db';
  await File(
    dbPath,
  ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);
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
  final router = GoRouter(
    initialLocation: '/shield',
    routes: [
      GoRoute(
        path: '/shield',
        builder: (context, _) => LedgerShieldSigningOverlay(
          onCancel: () => context.go('/home'),
          onComplete: () => context.go('/complete'),
        ),
      ),
      GoRoute(
        path: '/complete',
        builder: (_, _) =>
            const SizedBox(key: ValueKey('ledger_shield_complete')),
      ),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  final approval = _approveNextReview(fixture.signingApiUrl);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _ledgerBootstrap(
            fixture,
            lightwalletd.url,
            initialLocation: '/shield',
          ),
        ),
        networkPrivacyProvider.overrideWith(_DirectNetworkPrivacyNotifier.new),
        syncProvider.overrideWith(() => _FakeSyncNotifier(fixture.accountUuid)),
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        ledgerWalletDbPathProvider.overrideWithValue(() async => dbPath),
        ledgerOperationCancellerProvider.overrideWithValue(() async {}),
        ledgerSignedOperationServiceProvider.overrideWithValue(
          operationService,
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval')),
    description: 'Ledger shield approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(
    find.byKey(const ValueKey('ledger_shield_signing_overlay_surface')),
    findsOneWidget,
  );
  expect(await approval, isTrue);
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('ledger_shield_complete'))),
    description: 'Ledger shield completion',
    timeout: const Duration(minutes: 2),
  );

  expect(operationService.callOrder, ['checkpoint', 'broadcast']);
  expect(operationService.checkpointCount, 1);
  expect(operationService.broadcastCount, 1);
  expect(
    operationService.lastOperationId,
    startsWith('shield:${fixture.accountUuid}:'),
  );
  expect(lightwalletd.sendTransactionCount, 1);
  expect(lightwalletd.lastRawTransaction, isNotEmpty);
  expect(await operationService.list(), isEmpty);
}

Future<void> _runLedgerTexSendScenario(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final fixture = _Fixture.load();
  final sandboxDirectory = await Directory.systemTemp.createTemp(
    'vizor-ledger-tex-speculos-e2e.',
  );
  final dbPath = '${sandboxDirectory.path}/wallet.db';
  await File(
    dbPath,
  ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);
  final lightwalletd = _AcceptingLightwalletd();
  await lightwalletd.start();
  addTearDown(lightwalletd.stop);

  final reviewArgs = SendReviewArgs(
    proposalId: BigInt.two,
    sendFlowId: 'ledger-speculos-tex-send',
    proposalAccountUuid: fixture.accountUuid,
    address: fixture.texAddress,
    addressType: 'tex',
    amountZatoshi: BigInt.from(1980000),
    feeZatoshi: BigInt.from(20000),
    needsSaplingParams: false,
  );
  final operationService = _TrackingLedgerSignedOperationService(
    RustLedgerSignedOperationService(
      network: 'main',
      lightwalletdUrl: lightwalletd.url,
      loadWalletDbPath: () async => dbPath,
    ),
  );
  final router = GoRouter(
    initialLocation: '/send/review?flow=${reviewArgs.sendFlowId}',
    initialExtra: reviewArgs,
    routes: [
      GoRoute(path: '/send', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
      GoRoute(
        path: '/send/review',
        builder: (_, state) =>
            SendReviewScreen(args: state.extra! as SendReviewArgs),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) {
          final payload = state.extra! as LedgerBroadcastArgs;
          return SendStatusScreen(args: payload.reviewArgs, ledger: payload);
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      key: const ValueKey('ledger_speculos_tex_send_scope'),
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _ledgerBootstrap(
            fixture,
            lightwalletd.url,
            initialLocation: '/send/review',
          ),
        ),
        syncProvider.overrideWith(() => _FakeSyncNotifier(fixture.accountUuid)),
        addressBookRepositoryProvider.overrideWithValue(
          _EmptyAddressBookRepository(),
        ),
        zecMarketDataSourceProvider.overrideWithValue(
          const _EmptyMarketDataSource(),
        ),
        zecMarketDataCacheProvider.overrideWithValue(_MemoryMarketDataCache()),
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        ledgerWalletDbPathProvider.overrideWithValue(() async => dbPath),
        ledgerSendTexPcztsCreatorProvider.overrideWithValue(({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required proposalId,
          required sendFlowId,
        }) async {
          expect(lightwalletdUrl, lightwalletd.url);
          expect(network, 'main');
          expect(proposalId, reviewArgs.proposalId);
          expect(sendFlowId, reviewArgs.sendFlowId);
          return rust_sync.TexPcztPairResult(
            pczts: [
              Uint8List.fromList(fixture.texStep1PcztBytes),
              Uint8List.fromList(fixture.texStep2PcztBytes),
            ],
            signerPczts: const [],
          );
        }),
        ledgerSignedOperationServiceProvider.overrideWithValue(
          operationService,
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
  expect(find.text('Review send'), findsOneWidget);
  expect(find.text('TEX'), findsOneWidget);

  final firstApproval = _approveNextReview(fixture.signingApiUrl);
  await tester.tap(find.byKey(const ValueKey('send_confirm_button')));
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval · 1 of 2')),
    description: 'Ledger TEX first approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(await firstApproval, isTrue);

  final secondApproval = _approveNextReview(fixture.signingApiUrl);
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval · 2 of 2')),
    description: 'Ledger TEX second approval prompt',
    timeout: const Duration(minutes: 2),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('send_status_completed'))),
    description: 'Ledger TEX Send status completion',
    timeout: const Duration(minutes: 2),
  );
  expect(await secondApproval, isTrue);
  expect(find.text('Sent successfully'), findsOneWidget);
  expect(operationService.checkpointCount, 1);
  expect(operationService.batchCheckpointCount, 1);
  expect(operationService.broadcastCount, 1);
  expect(lightwalletd.sendTransactionCount, 2);
  expect(await operationService.list(), isEmpty);
}

Future<void> _runLedgerSwapScenario(
  WidgetTester tester,
  _LedgerSwapScenario scenario,
) async {
  await tester.binding.setSurfaceSize(const Size(1512, 982));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final fixture = _Fixture.load();
  final sandboxDirectory = await Directory.systemTemp.createTemp(
    'vizor-ledger-${scenario.label}-speculos-e2e.',
  );
  final dbPath = '${sandboxDirectory.path}/wallet.db';
  await File(
    dbPath,
  ).writeAsBytes(gzip.decode(fixture.dbGzipBytes), flush: true);

  final lightwalletd = _AcceptingLightwalletd();
  await lightwalletd.start();
  addTearDown(lightwalletd.stop);
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
  final router = _ledgerSwapRouter(scenario);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    _ledgerSwapHarness(
      fixture: fixture,
      lightwalletdUrl: lightwalletd.url,
      dbPath: dbPath,
      router: router,
      swapProvider: swapProvider,
      operationService: operationService,
      hardwareSigningService: hardwareSigningService,
      persistenceStore: persistenceStore,
      initialLocation: scenario.isPay ? '/pay' : '/swap',
    ),
  );
  await tester.pumpAndSettle();

  late final Finder startButton;
  if (scenario.isPay) {
    final amountInput = find.byKey(const ValueKey('pay_amount_input'));
    await _pumpUntil(
      tester,
      () => tester.any(amountInput),
      description: 'Pay amount input',
      timeout: const Duration(seconds: 30),
    );
    await tester.enterText(amountInput, '0.693');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay_amount_continue_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pay_recipient_search_field')),
      _externalRecipient,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay_select_recipient_button')));
    await _pumpUntil(
      tester,
      () => tester.any(find.byKey(const ValueKey('pay_review_step'))),
      description: 'Pay review step',
      timeout: const Duration(seconds: 30),
    );
    startButton = find.byKey(const ValueKey('pay_confirm_button'));
  } else {
    final amountInput = find.byKey(const ValueKey('swap_amount_field'));
    await _pumpUntil(
      tester,
      () => tester.any(amountInput),
      description: 'Swap amount input',
      timeout: const Duration(seconds: 30),
    );
    await tester.enterText(amountInput, '0.0099');
    await _enterSwapDestination(tester, _externalRecipient);
    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await _pumpUntil(
      tester,
      () => tester.any(find.byKey(const ValueKey('swap_start_button'))),
      description: 'Swap review start button',
      timeout: const Duration(seconds: 30),
    );
    startButton = find.byKey(const ValueKey('swap_start_button'));
  }

  await tester.ensureVisible(startButton);
  await tester.pump();
  final signingApproval = _approveNextReview(fixture.signingApiUrl);
  await tester.tap(startButton);
  await tester.pump();
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Waiting for approval')),
    description: '${scenario.label} Ledger approval prompt',
    timeout: const Duration(minutes: 2),
  );
  expect(await signingApproval, isTrue);
  await _pumpUntil(
    tester,
    () => operationService.acknowledgeCount == 1,
    description: '${scenario.label} Ledger broadcast acknowledgement',
    timeout: const Duration(minutes: 2),
  );

  final operationId =
      '${scenario.operationKind.wireName}:${fixture.accountUuid}:${scenario.intentId}';
  expect(operationService.checkpointCount, 1);
  expect(operationService.broadcastCount, 1);
  expect(operationService.acknowledgeCount, 1);
  expect(operationService.lastOperationId, operationId);
  expect(await operationService.list(), isEmpty);
  expect(hardwareSigningService.draftCount, 1);
  expect(hardwareSigningService.proofCount, 1);
  expect(hardwareSigningService.settleCount, 1);
  expect(swapProvider.startedIntentCount, 1);
  expect(swapProvider.submittedDepositCount, 1);
  expect(swapProvider.lastSubmittedTxHash, isNotEmpty);
  expect(lightwalletd.sendTransactionCount, 1);
  expect(lightwalletd.lastRawTransaction, isNotEmpty);

  final record = persistenceStore.recordFor(
    accountUuid: fixture.accountUuid,
    intentId: scenario.intentId,
  );
  expect(record, isNotNull);
  expect(record!.payMode, scenario.isPay);
  expect(record.depositTxHash, swapProvider.lastSubmittedTxHash);
  expect(record.status, SwapIntentStatus.depositObserved);
  expect(
    find.byKey(const ValueKey('swap_ledger_signing_overlay_surface')),
    findsNothing,
  );
  expect(
    find.byKey(const ValueKey('swap_activity_detail_page')),
    findsOneWidget,
  );
  expect(
    find.text(scenario.isPay ? 'Pay in progress...' : 'Swap in progress...'),
    findsWidgets,
  );
}

const _externalRecipient = '0x52908400098527886e0f7030069857d2e4169ee7';

Future<void> _enterSwapDestination(
  WidgetTester tester,
  String destination,
) async {
  var field = find.byKey(const ValueKey('swap_destination_field'));
  if (!tester.any(field)) {
    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    field = find.byKey(const ValueKey('swap_destination_field'));
  }
  await tester.enterText(field, destination);
  await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
  await tester.pumpAndSettle();
}

GoRouter _ledgerSwapRouter(_LedgerSwapScenario scenario) {
  return GoRouter(
    initialLocation: scenario.isPay ? '/pay' : '/swap',
    routes: [
      GoRoute(path: '/pay', builder: (_, _) => const PayScreen()),
      GoRoute(
        path: '/swap',
        builder: (_, _) => const SwapScreen(),
        routes: [
          GoRoute(path: 'review', builder: (_, _) => const SwapReviewScreen()),
        ],
      ),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const SizedBox(),
        routes: [
          GoRoute(
            path: 'swap/:swapId',
            builder: (_, state) => SwapActivityDetailScreen(
              swapIntentId: state.pathParameters['swapId'] ?? '',
              returnTarget: SwapActivityReturnTarget.fromQueryValue(
                state.uri.queryParameters[swapActivityReturnQueryKey],
              ),
              autoSignZecDeposit:
                  state.uri.queryParameters[swapActivitySignQueryKey] ==
                  swapActivitySignZecDepositValue,
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _ledgerSwapHarness({
  required _Fixture fixture,
  required String lightwalletdUrl,
  required String dbPath,
  required GoRouter router,
  required _DeterministicSwapProvider swapProvider,
  required _TrackingLedgerSignedOperationService operationService,
  required _SpeculosSwapHardwareSigningService hardwareSigningService,
  required _MemorySwapPersistenceStore persistenceStore,
  required String initialLocation,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _ledgerBootstrap(
          fixture,
          lightwalletdUrl,
          initialLocation: initialLocation,
        ),
      ),
      networkPrivacyProvider.overrideWith(_DirectNetworkPrivacyNotifier.new),
      syncProvider.overrideWith(() => _FakeSyncNotifier(fixture.accountUuid)),
      addressBookRepositoryProvider.overrideWithValue(
        _EmptyAddressBookRepository(),
      ),
      zecMarketDataSourceProvider.overrideWithValue(
        const _EmptyMarketDataSource(),
      ),
      zecMarketDataCacheProvider.overrideWithValue(_MemoryMarketDataCache()),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ledgerWalletDbPathProvider.overrideWithValue(() async => dbPath),
      ledgerOperationCancellerProvider.overrideWithValue(() async {}),
      ledgerSignedOperationServiceProvider.overrideWithValue(operationService),
      swapIntentProvider.overrideWithValue(swapProvider),
      swapDepositSenderProvider.overrideWithValue(_FixtureSwapDepositSender()),
      swapMaxAmountEstimatorProvider.overrideWithValue(
        const _FixtureSwapMaxAmountEstimator(),
      ),
      swapHardwareSigningServiceProvider.overrideWithValue(
        hardwareSigningService,
      ),
      swapActivityStoreProvider.overrideWithValue(persistenceStore),
      swapComposerPreferencesStoreProvider.overrideWithValue(persistenceStore),
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
  final List<int> dbGzipBytes;

  static _Fixture load() {
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
    if (ufvk.isEmpty ||
        seedFingerprint.isEmpty ||
        accountUuid.isEmpty ||
        transparentAddress.isEmpty ||
        texAddress.isEmpty ||
        pcztBase64.isEmpty ||
        texStep1PcztBase64.isEmpty ||
        texStep2PcztBase64.isEmpty ||
        votingBundle1PcztBase64.isEmpty ||
        votingBundle2PcztBase64.isEmpty ||
        votingBundle1ActionIndex < 0 ||
        votingBundle2ActionIndex < 0 ||
        dbGzipBase64.isEmpty) {
      throw StateError(
        'Ledger fixture dart-defines are missing. Run the Speculos E2E script.',
      );
    }
    return _Fixture(
      ufvkApiUrl: _requiredEnvironment('VIZOR_LEDGER_SPECULOS_UFVK_API_URL'),
      signingApiUrl: _requiredEnvironment(
        'VIZOR_LEDGER_SPECULOS_SIGNING_API_URL',
      ),
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
  SwapQuote? _lastQuote;
  int startedIntentCount = 0;
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
    if (request.direction != SwapDirection.zecToExternal ||
        request.externalAsset != SwapAsset.usdc) {
      throw StateError('Ledger E2E only supports ZEC to USDC.');
    }
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
    final quote = SwapQuote(
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
      providerQuoteId: 'ledger-${scenario.label}-quote',
      sellAmountBaseUnits: BigInt.from(990000),
      sellAmountTextOverride: '0.0099 ZEC',
      receiveEstimateTextOverride: '0.693 USDC',
      minimumReceiveTextOverride: '0.689535 USDC',
      rateTextOverride: '1 ZEC = 70.00 USDC',
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: depositAddress,
        expiresInLabel: '10:00',
        reuseWarning: 'Do not reuse this address',
        deadline: expiresAt,
      ),
    );
    _lastQuote = quote;
    return quote;
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    startedIntentCount++;
    _lastQuote = quote;
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
      throw StateError('Ledger E2E deposit address changed.');
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
    final quote = _lastQuote;
    if (quote == null) throw StateError('Ledger E2E quote is missing.');
    return SwapIntentSnapshot(
      id: scenario.intentId,
      providerLabel: quote.providerLabel,
      pairText: quote.pairText,
      sellAmountText: quote.sellAmountText,
      receiveEstimateText: quote.receiveEstimateText,
      status: status,
      nextAction: status == SwapIntentStatus.depositObserved
          ? 'Deposit detected'
          : 'Send the ZEC deposit',
      depositInstruction: quote.depositInstruction,
      sellAmountBaseUnits: quote.sellAmountBaseUnits,
      swapFeeText: quote.feeLabel,
      minimumReceiveText: quote.minimumReceiveText,
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
      sendFlowId: 'ledger-${intent.payMode ? 'pay' : 'swap'}-e2e',
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

class _DirectNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}

AppBootstrapState _ledgerBootstrap(
  _Fixture fixture,
  String lightwalletdUrl, {
  required String initialLocation,
}) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: fixture.accountUuid,
          name: 'Speculos Ledger',
          order: 0,
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
          zip32AccountIndex: fixture.accountIndex,
          ledgerConnectionPreference: LedgerConnectionPreference.usb,
          ledgerLastTransport: LedgerConnectionTransport.usb,
          ledgerDeviceName: 'Speculos Nano S Plus',
          ledgerDeviceModel: 'Nano S Plus',
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
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
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
    return delegate.broadcast(
      operationId: operationId,
      spendParamsPath: spendParamsPath,
      outputParamsPath: outputParamsPath,
    );
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

class _EmptyAddressBookRepository implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

class _EmptyMarketDataSource implements ZecMarketDataSource {
  const _EmptyMarketDataSource();

  @override
  Future<ZecMarketData?> fetchMarketData() async => null;
}

class _MemoryMarketDataCache implements ZecMarketDataCache {
  CachedZecMarketData? value;

  @override
  Future<CachedZecMarketData?> read() async => value;

  @override
  Future<void> write(CachedZecMarketData value) async {
    this.value = value;
  }
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('$name must be set for the Ledger Speculos E2E.');
  }
  return value;
}

List<int> _decodeHex(String value) {
  if (value.length.isOdd) {
    throw StateError('Ledger fixture fingerprint has invalid hex.');
  }
  return [
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ];
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
