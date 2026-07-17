import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  setUpAll(() async {
    const fonts = <String, List<String>>{
      'Geist': [
        'assets/fonts/Geist-Regular.ttf',
        'assets/fonts/Geist-Medium.ttf',
        'assets/fonts/Geist-SemiBold.ttf',
        'assets/fonts/Geist-Bold.ttf',
      ],
      'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('option selection does not move card content', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_migrationOptionsHarness());
    await tester.pumpAndSettle();

    final privateTitle = find.text('Private Migration');
    final fastTitle = find.text('Fast Migration');
    expect(privateTitle, findsOneWidget);
    expect(fastTitle, findsOneWidget);

    final privateTitleInitialTopLeft = tester.getTopLeft(privateTitle);
    final fastTitleInitialTopLeft = tester.getTopLeft(fastTitle);

    await tester.tap(fastTitle);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(privateTitle), privateTitleInitialTopLeft);
    expect(tester.getTopLeft(fastTitle), fastTitleInitialTopLeft);

    await tester.tap(privateTitle);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(privateTitle), privateTitleInitialTopLeft);
    expect(tester.getTopLeft(fastTitle), fastTitleInitialTopLeft);
  });

  testWidgets('private selection opens review screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_migrationOptionsHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select & Review'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Review Migration Plan'), findsOneWidget);
    expect(find.text('1 Planned batches'), findsOneWidget);
    expect(find.text('Authorize & Start'), findsOneWidget);
  });

  testWidgets('private review shows plan without preparing a transaction', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/private/review'),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 Planned batches'), findsOneWidget);
    expect(find.text('~144 blocks'), findsOneWidget);
    expect(find.text('Fees (estimate)'), findsOneWidget);
    expect(find.text('Total, ~0.0001 ZEC'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ironwood_migration_schedule_view')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Migration schedule'), findsOneWidget);
    expect(find.text('Batch 1'), findsOneWidget);
    expect(find.text('0.1 ZEC  ·  +144 blocks'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('ironwood_migration_schedule_close')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Migration schedule'), findsNothing);
  });

  testWidgets('private review starts software migration and opens status', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? startedAccountUuid;
    List<rust_sync.MigrationScheduledTransfer>? startedSchedule;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_status());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(_privatePlan());
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => defaultRpcEndpointConfig('main'),
      getSessionPassword: () => 'test-password',
      getMnemonicBytesForAccount: (_) async => [1, 2, 3, 4],
      isMacOS: () => false,
      startSoftwareMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required approvedSchedule,
            required mnemonicBytes,
            required password,
            required saltBase64,
          }) {
            startedAccountUuid = accountUuid;
            startedSchedule = approvedSchedule;
            return Future.value(_migrationResult());
          },
    );

    await tester.pumpWidget(
      _migrationOptionsHarness(
        initialLocation: '/migration/private/review',
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    final prepareButton = find.widgetWithText(AppButton, 'Authorize & Start');
    expect(prepareButton, findsOneWidget);
    expect(tester.widget<AppButton>(prepareButton).onPressed, isNotNull);

    await tester.tap(prepareButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(startedAccountUuid, 'account-1');
    expect(startedSchedule, _privatePlan().scheduledTransfers);
    expect(find.text('Preparing...'), findsOneWidget);
  });

  testWidgets(
    'private review opens status when post-start status is unavailable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var startCount = 0;
      final service = _migrationServiceForStart(
        onStart: ({required accountUuid}) async {
          startCount += 1;
          return _migrationResult();
        },
      );

      await tester.pumpWidget(
        _migrationOptionsHarness(
          initialLocation: '/migration/private/review',
          migrationService: service,
          realStatusRoute: true,
          statusGetter:
              ({required dbPath, required network, required accountUuid}) {
                return Future.error(Exception('status unavailable'));
              },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Authorize & Start'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(startCount, 1);
      expect(find.byType(IronwoodMigrationPrivateStatusScreen), findsOneWidget);
      expect(find.text("Couldn't start migration. Try again."), findsNothing);
    },
  );

  testWidgets('private review resumes a run persisted before start failed', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _migrationServiceForStart(
      onStart: ({required accountUuid}) {
        return Future.error(Exception('sendtransaction failed'));
      },
    );

    await tester.pumpWidget(
      _migrationOptionsHarness(
        initialLocation: '/migration/private/review',
        migrationService: service,
        realStatusRoute: true,
        statusGetter:
            ({required dbPath, required network, required accountUuid}) async {
              return _status();
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Authorize & Start'));
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsOneWidget);
    expect(
      find.text("Couldn't broadcast the migration transaction. Try again."),
      findsNothing,
    );
  });

  test(
    'Keystone migration scan error asks for firmware update on legacy sign result',
    () {
      final legacyMessage = ironwoodMigrationKeystoneScanErrorMessage(
        Exception(
          'Unexpected UR type: got "zcash-sign-result", '
          'expected "zcash-batch-sig-result"',
        ),
      );
      final wrongQrMessage = ironwoodMigrationKeystoneScanErrorMessage(
        Exception(
          'Unexpected UR type: got "zcash-pczt", '
          'expected "zcash-batch-sig-result"',
        ),
      );

      expect(
        legacyMessage,
        'Update Keystone firmware to sign Ironwood migrations, then try again.',
      );
      expect(
        wrongQrMessage,
        'Open the signed migration QR on Keystone, then scan again.',
      );
    },
  );

  test('Keystone migration proof helpers distinguish pending states', () {
    const pending = rust_sync.KeystoneMigrationProofStatus(
      readyCount: 1,
      totalCount: 3,
      isReady: false,
      isFailed: false,
    );
    const ready = rust_sync.KeystoneMigrationProofStatus(
      readyCount: 3,
      totalCount: 3,
      isReady: true,
      isFailed: false,
    );
    const failed = rust_sync.KeystoneMigrationProofStatus(
      readyCount: 1,
      totalCount: 3,
      isReady: false,
      isFailed: true,
      message: 'Proof generation failed.',
    );

    expect(ironwoodMigrationKeystoneProofShouldWait(null), isTrue);
    expect(ironwoodMigrationKeystoneProofShouldWait(pending), isTrue);
    expect(ironwoodMigrationKeystoneProofShouldWait(ready), isFalse);
    expect(ironwoodMigrationKeystoneProofShouldWait(failed), isFalse);
    expect(ironwoodMigrationKeystoneProofReady(ready), isTrue);
    expect(ironwoodMigrationKeystoneProofFailed(failed), isTrue);
    expect(
      ironwoodMigrationKeystoneProofWaitingMessage(pending),
      'Signature captured. Vizor is still preparing local proofs (1/3). '
      'Keep this screen open.',
    );
    expect(
      ironwoodMigrationKeystoneProofFailureMessage(failed),
      'Proof generation failed.',
    );
  });

  testWidgets(
    'private review routes Keystone accounts to denomination signing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var softwareStarted = false;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_status());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(_privatePlan());
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => defaultRpcEndpointConfig('main'),
        getSessionPassword: () => 'test-password',
        getMnemonicBytesForAccount: (_) async => [1, 2, 3, 4],
        isMacOS: () => false,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) {
              softwareStarted = true;
              return Future.value(_migrationResult());
            },
      );

      await tester.pumpWidget(
        _migrationOptionsHarness(
          initialLocation: '/migration/private/review',
          migrationService: service,
          activeAccountIsHardware: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Authorize & Start'));
      await tester.pumpAndSettle();

      expect(softwareStarted, isFalse);
      expect(
        find.text('keystone-denomination-sign-route:1:144'),
        findsOneWidget,
      );
    },
  );

  testWidgets('legacy review route redirects to private review', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/review'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Review Migration Plan'), findsOneWidget);
    expect(find.text('1 Planned batches'), findsOneWidget);
  });

  testWidgets('private status shows resume progress state', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/private/status'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('Transaction splits submitted'), findsOneWidget);
    expect(find.text('Waiting for confirmation ...'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Back to Home'), findsNothing);
  });

  testWidgets('private status maps migration phases to actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cases = [
      _StatusUiCase(status: _status(), title: 'Preparing...'),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationReadyToMigratePhase,
          activeRunId: 'run-1',
        ),
        title: 'Ready to Migrate',
        buttonLabel: 'Continue migration',
        buttonEnabled: true,
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
        ),
        title: 'Broadcast Scheduled',
        buttonLabel: 'Continue migration',
        buttonEnabled: true,
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastingPhase,
          activeRunId: 'run-1',
        ),
        title: 'Migrating...',
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          activeRunId: 'run-1',
        ),
        title: 'Migrating...',
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationFailedRecoverablePhase,
          activeRunId: 'run-1',
        ),
        title: 'Migration Needs Attention',
        buttonLabel: 'Retry migration',
        buttonEnabled: true,
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationCompletePhase,
          activeRunId: 'run-1',
        ),
        title: 'Migration Complete',
        buttonLabel: 'Back home',
        buttonEnabled: true,
      ),
    ];

    for (final uiCase in cases) {
      await tester.pumpWidget(_privateStatusHarness(status: uiCase.status));
      await tester.pumpAndSettle();

      expect(find.text(uiCase.title), findsOneWidget);
      if (uiCase.buttonLabel == null) {
        expect(find.widgetWithText(AppButton, 'Back to Home'), findsNothing);
        expect(
          find.widgetWithText(AppButton, 'Continue migration'),
          findsNothing,
        );
      } else {
        _expectStatusButton(
          tester,
          label: uiCase.buttonLabel!,
          enabled: uiCase.buttonEnabled,
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('private status restarts planning after an invalid run retires', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(phase: kIronwoodMigrationReadyPhase),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('intro-route'), findsOneWidget);
  });

  testWidgets(
    'private transfer status uses confirmed progress while confirming',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _privateStatusHarness(
          status: _migrationStatus(
            phase: kIronwoodMigrationWaitingConfirmationsPhase,
            activeRunId: 'run-1',
            targetValuesZatoshi: const [10_000_000, 20_000_000, 30_000_000],
            broadcastedTxCount: 2,
            confirmedTxCount: 1,
            totalCount: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('33%'), findsOneWidget);
      expect(find.text('Left to transfer: ~0.4 ZEC'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('~0.2 ZEC'), findsOneWidget);
      expect(find.text('Confirming'), findsOneWidget);
      expect(find.text('~6 min'), findsNothing);
    },
  );

  testWidgets('private transfer status waits for trusted completion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000, 20_000_000, 30_000_000],
          broadcastedTxCount: 3,
          confirmedTxCount: 3,
          totalCount: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('99%'), findsOneWidget);
    expect(find.text('Left to transfer: ~0.006 ZEC'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.text('Left to transfer: 0 ZEC'), findsNothing);
    expect(find.text('Confirming'), findsOneWidget);
  });

  testWidgets('private transfer ETA uses the next scheduled broadcast', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastingPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000, 20_000_000, 30_000_000],
          broadcastedTxCount: 1,
          totalCount: 3,
          scheduledBroadcasts: [
            rust_sync.MigrationScheduledBroadcast(
              txidHex: 'broadcasted',
              valueZatoshi: BigInt.from(10_000_000),
              scheduledAtMs: 0,
              scheduledHeight: 800,
              status: 'broadcasted',
            ),
            rust_sync.MigrationScheduledBroadcast(
              txidHex: 'next',
              valueZatoshi: BigInt.from(20_000_000),
              scheduledAtMs: 0,
              scheduledHeight: 900,
              status: 'scheduled',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Block 900'), findsOneWidget);
    expect(find.text('Block 800'), findsNothing);
  });

  testWidgets('private status continues due software migration', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? continuedAccountUuid;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_status());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(_privatePlan());
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => defaultRpcEndpointConfig('main'),
      getSessionPassword: () => 'test-password',
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) {
            continuedAccountUuid = accountUuid;
            return Future.value(_migrationResult());
          },
    );

    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: _migrationStatus(
            phase: kIronwoodMigrationReadyToMigratePhase,
            activeRunId: 'run-1',
          ),
        ),
        initialLocation: '/migration/private/status',
        realStatusRoute: true,
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    final continueButton = find.widgetWithText(AppButton, 'Continue migration');
    expect(continueButton, findsOneWidget);
    expect(tester.widget<AppButton>(continueButton).onPressed, isNotNull);

    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(continuedAccountUuid, 'account-1');
  });

  testWidgets('private status auto advances software migration on timer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var continueCount = 0;
    final service = _migrationServiceForContinue(
      onContinue: ({required accountUuid}) {
        continueCount += 1;
        expect(accountUuid, 'account-1');
        return Future.value(_migrationResult());
      },
    );

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
        ),
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    expect(continueCount, 0);

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(continueCount, 1);
  });

  testWidgets('private status refreshes while software migration advances', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var status = _migrationStatus(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      activeRunId: 'run-1',
      pendingSplitStageCount: 1,
    );
    final continued = Completer<rust_sync.IronwoodMigrationResult>();
    var continueCount = 0;
    final service = _migrationServiceForContinue(
      onContinue: ({required accountUuid}) {
        continueCount += 1;
        return continued.future;
      },
    );

    await tester.pumpWidget(
      _privateStatusHarness(
        status: status,
        statusGetter:
            ({required dbPath, required network, required accountUuid}) async {
              return status;
            },
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(continueCount, 1);

    status = _migrationStatus(
      phase: kIronwoodMigrationBroadcastingPhase,
      activeRunId: 'run-1',
      targetValuesZatoshi: const [10_000_000],
      broadcastedTxCount: 1,
      totalCount: 1,
    );
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    await tester.pump();

    expect(find.text('1 Planned batches'), findsOneWidget);
    expect(continueCount, 1);

    continued.complete(_migrationResult());
    await tester.pump();
  });

  testWidgets(
    'private status retries a persisted denomination broadcast on timer',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var continueCount = 0;
      final service = _migrationServiceForContinue(
        onContinue: ({required accountUuid}) {
          continueCount += 1;
          expect(accountUuid, 'account-1');
          return Future.value(_migrationResult());
        },
      );

      await tester.pumpWidget(
        _privateStatusHarness(
          status: _migrationStatus(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
            activeRunId: 'run-1',
            pendingSplitStageCount: 1,
          ),
          migrationService: service,
        ),
      );
      await tester.pumpAndSettle();

      expect(continueCount, 0);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(continueCount, 1);
    },
  );

  testWidgets(
    'private status cancels auto advance when pending split stages clear',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var status = _migrationStatus(
        phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        activeRunId: 'run-1',
        pendingSplitStageCount: 1,
      );
      var statusReadCount = 0;
      var continueCount = 0;
      final service = _migrationServiceForContinue(
        onContinue: ({required accountUuid}) async {
          continueCount += 1;
          return _migrationResult();
        },
      );

      await tester.pumpWidget(
        _privateStatusHarness(
          status: status,
          statusGetter:
              ({
                required dbPath,
                required network,
                required accountUuid,
              }) async {
                statusReadCount += 1;
                return status;
              },
          migrationService: service,
        ),
      );
      await tester.pumpAndSettle();

      status = _migrationStatus(
        phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        activeRunId: 'run-1',
        pendingSplitStageCount: 0,
      );
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      expect(statusReadCount, greaterThanOrEqualTo(2));

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(continueCount, 0);
    },
  );

  testWidgets('private status auto advances software migration on resume', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var continueCount = 0;
    final service = _migrationServiceForContinue(
      onContinue: ({required accountUuid}) {
        continueCount += 1;
        expect(accountUuid, 'account-1');
        return Future.value(_migrationResult());
      },
    );

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationReadyToMigratePhase,
          activeRunId: 'run-1',
        ),
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(continueCount, 1);
  });

  testWidgets('private status routes Keystone ready state to batch signing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var softwareContinued = false;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_status());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(_privatePlan());
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => defaultRpcEndpointConfig('main'),
      getSessionPassword: () => 'test-password',
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) {
            softwareContinued = true;
            return Future.value(_migrationResult());
          },
    );

    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: _migrationStatus(
            phase: kIronwoodMigrationReadyToMigratePhase,
            activeRunId: 'run-1',
          ),
        ),
        initialLocation: '/migration/private/status',
        realStatusRoute: true,
        migrationService: service,
        activeAccountIsHardware: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(softwareContinued, isFalse);
    expect(find.text('Ready to Migrate'), findsOneWidget);
    expect(find.text('keystone-batch-sign-route'), findsNothing);

    await tester.tap(find.widgetWithText(AppButton, 'Continue migration'));
    await tester.pumpAndSettle();

    expect(softwareContinued, isFalse);
    expect(find.text('keystone-batch-sign-route'), findsOneWidget);
  });

  testWidgets('private status shows continue errors only for manual action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var continueCount = 0;
    final service = _migrationServiceForContinue(
      onContinue: ({required accountUuid}) {
        continueCount += 1;
        return Future.error(Exception('sendtransaction failed'));
      },
    );

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
        ),
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(continueCount, 1);
    expect(
      find.text("Couldn't broadcast the migration transaction. Try again."),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(AppButton, 'Continue migration'));
    await tester.pumpAndSettle();

    expect(continueCount, 2);
    expect(
      find.text("Couldn't broadcast the migration transaction. Try again."),
      findsOneWidget,
    );
  });

  testWidgets('migration entry routes start state to intro', (tester) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.start(
          network: 'test',
          accountUuid: 'account-1',
          status: _migrationStatus(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('intro-route'), findsOneWidget);
  });

  testWidgets('migration entry routes resume state to private status', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'test',
          accountUuid: 'account-1',
          status: _migrationStatus(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
            activeRunId: 'run-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('private-status-route'), findsOneWidget);
  });

  testWidgets('private status reads status directly when route CTA is stale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.start(
          network: 'test',
          accountUuid: 'account-1',
          status: _migrationStatus(),
        ),
        routeStatus: _migrationStatus(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000],
          pendingTxCount: 1,
          broadcastedTxCount: 1,
          confirmedTxCount: 0,
          totalCount: 1,
        ),
        initialLocation: '/migration/private/status',
        realStatusRoute: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('intro-route'), findsNothing);
    expect(find.text('Migrating...'), findsOneWidget);
  });

  testWidgets('migration entry routes every resume phase to private status', (
    tester,
  ) async {
    const resumePhases = [
      kIronwoodMigrationWaitingDenomConfirmationsPhase,
      kIronwoodMigrationReadyToMigratePhase,
      kIronwoodMigrationBroadcastScheduledPhase,
      kIronwoodMigrationBroadcastingPhase,
      kIronwoodMigrationWaitingConfirmationsPhase,
      kIronwoodMigrationPausedPhase,
      kIronwoodMigrationFailedRecoverablePhase,
    ];

    for (final phase in resumePhases) {
      await tester.pumpWidget(
        _migrationEntryHarness(
          ctaState: IronwoodHomeMigrationCtaState.resume(
            network: 'test',
            accountUuid: 'account-1',
            status: _migrationStatus(phase: phase, activeRunId: 'run-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('private-status-route'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('migration entry routes hidden state home', (tester) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: const IronwoodHomeMigrationCtaState.hidden(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home-route'), findsOneWidget);
  });

  testWidgets('private status fails closed when status lookup fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: const IronwoodHomeMigrationCtaState.hidden(),
        initialLocation: '/migration/private/status',
        routeError: Exception('status unavailable'),
        realStatusRoute: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration status unavailable'), findsOneWidget);
    expect(find.text('intro-route'), findsNothing);
    expect(find.text('home-route'), findsNothing);
  });

  test(
    'private plan provider calls the migration service for active inputs',
    () async {
      String? seenNetwork;
      String? seenAccountUuid;
      final expected = _privatePlan();
      final container = ProviderContainer(
        overrides: [
          ironwoodMigrationFlowDataProvider.overrideWith(
            (ref) async => IronwoodMigrationFlowData(
              amountZatoshi: BigInt.from(10_000_000),
              accountName: 'Account 1',
              profilePictureId: kDefaultProfilePictureId,
            ),
          ),
          ironwoodMigrationInputsProvider.overrideWithValue(
            IronwoodMigrationInputs(
              ironwoodActiveAtTip: true,
              network: 'test',
              accountUuid: 'account-1',
              accountName: 'Account 1',
              profilePictureId: kDefaultProfilePictureId,
              hasAccountScopedData: true,
              isSyncing: false,
              isBackgroundMode: false,
              hasSyncFailure: false,
              orchardBalance: BigInt.from(10_000_000),
              orchardPendingBalance: BigInt.zero,
              ironwoodBalance: BigInt.zero,
              ironwoodPendingBalance: BigInt.zero,
            ),
          ),
          ironwoodMigrationServiceProvider.overrideWithValue(
            IronwoodMigrationService(
              getWalletDbPath: () async => '/tmp/wallet.db',
              getStatus:
                  ({required dbPath, required network, required accountUuid}) {
                    return Future.value(_migrationStatus());
                  },
              getPrivatePlan:
                  ({required dbPath, required network, required accountUuid}) {
                    seenNetwork = network;
                    seenAccountUuid = accountUuid;
                    return Future.value(expected);
                  },
              secureStore: AppSecureStore.testing(
                storage: const FlutterSecureStorage(),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final plan = await container.read(
        ironwoodMigrationPrivatePlanProvider.future,
      );

      expect(plan, expected);
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
  );

  test(
    'private plan stays stable when volatile migration inputs change',
    () async {
      final inputsProvider =
          NotifierProvider<_MigrationInputsNotifier, IronwoodMigrationInputs>(
            _MigrationInputsNotifier.new,
          );
      var planCallCount = 0;
      final expected = _privatePlan();
      final container = ProviderContainer(
        overrides: [
          ironwoodMigrationInputsProvider.overrideWith(
            (ref) => ref.watch(inputsProvider),
          ),
          ironwoodMigrationServiceProvider.overrideWithValue(
            IronwoodMigrationService(
              getWalletDbPath: () async => '/tmp/wallet.db',
              getStatus:
                  ({required dbPath, required network, required accountUuid}) {
                    return Future.value(_migrationStatus());
                  },
              getPrivatePlan:
                  ({required dbPath, required network, required accountUuid}) {
                    planCallCount += 1;
                    return Future.value(expected);
                  },
              secureStore: AppSecureStore.testing(
                storage: const FlutterSecureStorage(),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationPrivatePlanProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(
        await container.read(ironwoodMigrationPrivatePlanProvider.future),
        expected,
      );
      container.read(inputsProvider.notifier).setSyncing(true);
      await Future<void>.delayed(Duration.zero);

      expect(
        await container.read(ironwoodMigrationPrivatePlanProvider.future),
        expected,
      );
      expect(planCallCount, 1);
    },
  );
}

class _MigrationInputsNotifier extends Notifier<IronwoodMigrationInputs> {
  @override
  IronwoodMigrationInputs build() => IronwoodMigrationInputs(
    ironwoodActiveAtTip: true,
    network: 'test',
    accountUuid: 'account-1',
    accountName: 'Account 1',
    profilePictureId: kDefaultProfilePictureId,
    hasAccountScopedData: true,
    isSyncing: false,
    isBackgroundMode: false,
    hasSyncFailure: false,
    orchardBalance: BigInt.from(10_000_000),
    orchardPendingBalance: BigInt.zero,
    ironwoodBalance: BigInt.zero,
    ironwoodPendingBalance: BigInt.zero,
  );

  void setSyncing(bool value) {
    state = IronwoodMigrationInputs(
      ironwoodActiveAtTip: state.ironwoodActiveAtTip,
      network: state.network,
      accountUuid: state.accountUuid,
      accountName: state.accountName,
      profilePictureId: state.profilePictureId,
      hasAccountScopedData: state.hasAccountScopedData,
      isSyncing: value,
      isBackgroundMode: state.isBackgroundMode,
      hasSyncFailure: state.hasSyncFailure,
      orchardBalance: state.orchardBalance,
      orchardPendingBalance: state.orchardPendingBalance,
      ironwoodBalance: state.ironwoodBalance,
      ironwoodPendingBalance: state.ironwoodPendingBalance,
    );
  }
}

Widget _migrationOptionsHarness({
  String initialLocation = '/migration/options',
  IronwoodMigrationService? migrationService,
  bool activeAccountIsHardware = false,
  bool realStatusRoute = false,
  OrchardMigrationStatusGetter? statusGetter,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/migration/options',
        builder: (_, _) => IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.options,
          previewData: IronwoodMigrationFlowData(
            amountZatoshi: BigInt.from(10_000_000),
            accountName: 'Account 1',
            profilePictureId: kDefaultProfilePictureId,
          ),
        ),
      ),
      GoRoute(
        path: '/migration/review',
        redirect: (_, _) => '/migration/private/review',
      ),
      GoRoute(
        path: '/migration/private/review',
        builder: (_, _) => IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.review,
          previewData: IronwoodMigrationFlowData(
            amountZatoshi: BigInt.from(10_000_000),
            accountName: 'Account 1',
            profilePictureId: kDefaultProfilePictureId,
          ),
          previewPrivatePlan: _privatePlan(),
        ),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => realStatusRoute
            ? const IronwoodMigrationPrivateStatusScreen()
            : IronwoodMigrationPrivateStatusScreen(previewStatus: _status()),
      ),
      GoRoute(
        path: '/migration/private/keystone/denominations/sign',
        builder: (_, state) {
          final schedule =
              state.extra! as List<rust_sync.MigrationScheduledTransfer>;
          return Text(
            'keystone-denomination-sign-route:${schedule.length}:'
            '${schedule.first.blockOffset}',
          );
        },
      ),
      GoRoute(
        path: '/migration/private/keystone/batch/sign',
        builder: (_, _) => const Text('keystone-batch-sign-route'),
      ),
      GoRoute(
        path: '/migration/how-it-works',
        builder: (_, _) => const Text('how it works'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      GoRoute(path: '/swap', builder: (_, _) => const Text('swap')),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting')),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account'),
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const Text('unlock')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrapFor(activeAccountIsHardware: activeAccountIsHardware),
      ),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncedSyncState)),
      swapFeatureEnabledProvider.overrideWithValue(true),
      if (statusGetter != null) ...[
        ironwoodMigrationInputsProvider.overrideWithValue(
          IronwoodMigrationInputs(
            ironwoodActiveAtTip: true,
            network: 'main',
            accountUuid: 'account-1',
            accountName: 'Account 1',
            profilePictureId: kDefaultProfilePictureId,
            hasAccountScopedData: true,
            isSyncing: false,
            isBackgroundMode: false,
            hasSyncFailure: false,
            orchardBalance: BigInt.from(10_000_000),
            orchardPendingBalance: BigInt.zero,
            ironwoodBalance: BigInt.zero,
            ironwoodPendingBalance: BigInt.zero,
          ),
        ),
        walletDbPathGetterProvider.overrideWithValue(
          () async => '/tmp/wallet.db',
        ),
        orchardMigrationStatusGetterProvider.overrideWithValue(statusGetter),
      ],
      if (migrationService != null)
        ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
        child: AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
}

Widget _privateStatusHarness({
  required rust_sync.MigrationStatus status,
  OrchardMigrationStatusGetter? statusGetter,
  IronwoodMigrationService? migrationService,
  bool activeAccountIsHardware = false,
}) {
  return _migrationEntryHarness(
    ctaState: IronwoodHomeMigrationCtaState.resume(
      network: 'main',
      accountUuid: 'account-1',
      status: status,
    ),
    initialLocation: '/migration/private/status',
    realStatusRoute: true,
    statusGetter: statusGetter,
    migrationService: migrationService,
    activeAccountIsHardware: activeAccountIsHardware,
  );
}

Widget _migrationEntryHarness({
  required IronwoodHomeMigrationCtaState ctaState,
  String initialLocation = '/migration',
  Object? routeError,
  bool realStatusRoute = false,
  rust_sync.MigrationStatus? routeStatus,
  OrchardMigrationStatusGetter? statusGetter,
  IronwoodMigrationService? migrationService,
  bool activeAccountIsHardware = false,
}) {
  final network = ctaState.network ?? 'test';
  final accountUuid = ctaState.accountUuid ?? 'account-1';
  final status = routeStatus ?? ctaState.status ?? _migrationStatus();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/migration',
        builder: (_, _) => const IronwoodMigrationEntryScreen(),
      ),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => const Text('intro-route'),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => realStatusRoute
            ? const IronwoodMigrationPrivateStatusScreen()
            : const Text('private-status-route'),
      ),
      GoRoute(
        path: '/migration/private/keystone/batch/sign',
        builder: (_, _) => const Text('keystone-batch-sign-route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
    ],
  );

  return ProviderScope(
    overrides: [
      ironwoodMigrationRouteCtaProvider.overrideWith((ref) async {
        final error = routeError;
        if (error != null) throw error;
        return ctaState;
      }),
      ironwoodMigrationInputsProvider.overrideWithValue(
        IronwoodMigrationInputs(
          ironwoodActiveAtTip: true,
          network: network,
          accountUuid: accountUuid,
          accountName: 'Account 1',
          profilePictureId: kDefaultProfilePictureId,
          hasAccountScopedData: true,
          isSyncing: false,
          isBackgroundMode: false,
          hasSyncFailure: false,
          orchardBalance: BigInt.from(10_000_000),
          orchardPendingBalance: BigInt.zero,
          ironwoodBalance: BigInt.zero,
          ironwoodPendingBalance: BigInt.zero,
        ),
      ),
      walletDbPathGetterProvider.overrideWithValue(
        () async => '/tmp/wallet.db',
      ),
      orchardMigrationStatusGetterProvider.overrideWith(
        (ref) =>
            ({required dbPath, required network, required accountUuid}) async {
              final error = routeError;
              if (error != null) throw error;
              final getter = statusGetter;
              if (getter != null) {
                return getter(
                  dbPath: dbPath,
                  network: network,
                  accountUuid: accountUuid,
                );
              }
              return status;
            },
      ),
      appBootstrapProvider.overrideWithValue(
        _bootstrapFor(activeAccountIsHardware: activeAccountIsHardware),
      ),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncedSyncState)),
      swapFeatureEnabledProvider.overrideWithValue(true),
      if (migrationService != null)
        ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

void _expectStatusButton(
  WidgetTester tester, {
  required String label,
  required bool enabled,
}) {
  final button = find.widgetWithText(AppButton, label);
  expect(button, findsOneWidget);
  expect(
    tester.widget<AppButton>(button).onPressed,
    enabled ? isNotNull : isNull,
  );
}

typedef _ContinueMigrationCallback =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String accountUuid,
    });

typedef _StartMigrationCallback =
    Future<rust_sync.IronwoodMigrationResult> Function({
      required String accountUuid,
    });

IronwoodMigrationService _migrationServiceForStart({
  required _StartMigrationCallback onStart,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus: ({required dbPath, required network, required accountUuid}) {
      return Future.value(_status());
    },
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) {
          return Future.value(_privatePlan());
        },
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => defaultRpcEndpointConfig('main'),
    getSessionPassword: () => 'test-password',
    getMnemonicBytesForAccount: (_) async => [1, 2, 3, 4],
    isMacOS: () => false,
    startSoftwareMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required approvedSchedule,
          required mnemonicBytes,
          required password,
          required saltBase64,
        }) {
          return onStart(accountUuid: accountUuid);
        },
  );
}

IronwoodMigrationService _migrationServiceForContinue({
  required _ContinueMigrationCallback onContinue,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus: ({required dbPath, required network, required accountUuid}) {
      return Future.value(_status());
    },
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) {
          return Future.value(_privatePlan());
        },
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => defaultRpcEndpointConfig('main'),
    getSessionPassword: () => 'test-password',
    broadcastDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) {
          return onContinue(accountUuid: accountUuid);
        },
  );
}

class _StatusUiCase {
  const _StatusUiCase({
    required this.status,
    required this.title,
    this.buttonLabel,
    this.buttonEnabled = false,
  });

  final rust_sync.MigrationStatus status;
  final String title;
  final String? buttonLabel;
  final bool buttonEnabled;
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/migration/options',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1testaddress',
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

AppBootstrapState _bootstrapFor({required bool activeAccountIsHardware}) {
  if (!activeAccountIsHardware) return _bootstrap;
  return AppBootstrapState(
    initialLocation: _bootstrap.initialLocation,
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: 'Account 1',
          order: 0,
          isHardware: true,
          profilePictureId: kDefaultProfilePictureId,
        ),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1testaddress',
    ),
    initialSyncSnapshot: _bootstrap.initialSyncSnapshot,
    network: _bootstrap.network,
    rpcEndpointConfig: _bootstrap.rpcEndpointConfig,
    themeMode: _bootstrap.themeMode,
    privacyModeEnabled: _bootstrap.privacyModeEnabled,
    isPasswordConfigured: _bootstrap.isPasswordConfigured,
    isUnlocked: _bootstrap.isUnlocked,
    passwordRotationRecoveryFailed: _bootstrap.passwordRotationRecoveryFailed,
  );
}

final _syncedSyncState = SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
);

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}

rust_sync.OrchardMigrationPrivatePlan _privatePlan() {
  return rust_sync.OrchardMigrationPrivatePlan(
    targetValuesZatoshi: frb.Uint64List.fromList([10_000_000]),
    totalInputZatoshi: BigInt.from(10_010_000),
    totalMigratableZatoshi: BigInt.from(10_000_000),
    denominationSplitFeeZatoshi: BigInt.from(5_000),
    migrationFeeZatoshi: BigInt.from(5_000),
    estimatedTotalFeeZatoshi: BigInt.from(10_000),
    plannedBatchCount: 1,
    denominationSplitStageCount: 0,
    signingBatchLimit: 50,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    scheduledTransfers: [
      rust_sync.MigrationScheduledTransfer(
        valueZatoshi: BigInt.from(10_000_000),
        blockOffset: 144,
      ),
    ],
  );
}

rust_sync.MigrationStatus _migrationStatus({
  String phase = kIronwoodMigrationReadyPhase,
  String? activeRunId,
  List<int> targetValuesZatoshi = const [],
  int pendingTxCount = 0,
  int broadcastedTxCount = 0,
  int confirmedTxCount = 0,
  int totalCount = 0,
  int pendingSplitStageCount = 0,
  List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts = const [],
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList(targetValuesZatoshi),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: pendingTxCount,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: confirmedTxCount,
    totalCount: totalCount,
    signedChildPcztCount: 0,
    pendingSplitStageCount: pendingSplitStageCount,
    canAbandon: false,
    signingBatchLimit: 50,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: scheduledBroadcasts,
  );
}

rust_sync.MigrationStatus _status() {
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
    activeRunId: 'run-1',
    targetValuesZatoshi: frb.Uint64List.fromList([10_000_000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 2,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 1,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 3,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 50,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [],
  );
}

rust_sync.IronwoodMigrationResult _migrationResult() {
  return rust_sync.IronwoodMigrationResult(
    txids: 'txid',
    status: 'broadcasted',
    broadcastedCount: 1,
    totalCount: 1,
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(10_000_000),
  );
}
