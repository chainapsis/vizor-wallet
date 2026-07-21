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
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
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

    final privateTitle = find.text('Privacy optimized');
    final fastTitle = find.text('Faster but less private');
    expect(privateTitle, findsOneWidget);
    expect(fastTitle, findsOneWidget);
    expect(find.text('Customize'), findsNothing);
    expect(find.text('Customise'), findsNothing);

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

    expect(find.text('Review migration plan'), findsOneWidget);
    expect(find.textContaining('1 note', findRichText: true), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Start migration'), findsOneWidget);
  });

  testWidgets('private review keeps analyzing visible for minimum duration', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(
        initialLocation: '/migration/private/review',
        analyzingMinimumDuration: const Duration(seconds: 6),
        disableAnimations: false,
      ),
    );

    expect(
      find.byKey(const ValueKey('ironwood_migration_analyzing_screen')),
      findsOneWidget,
    );
    expect(find.text('Analyzing your balance...'), findsOneWidget);
    expect(find.text('Review migration plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1919));
    expect(find.text('Analyzing your balance...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Finding private batches...'), findsOneWidget);
    expect(find.text('Review migration plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1590));
    expect(find.text('Finding private batches...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Preparing your migration plan...'), findsOneWidget);
    expect(find.text('Review migration plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1590));
    expect(
      find.byKey(const ValueKey('ironwood_migration_analyzing_screen')),
      findsOneWidget,
    );
    expect(find.text('Review migration plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 81));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('ironwood_migration_analyzing_screen')),
      findsNothing,
    );
    expect(find.text('Review migration plan'), findsOneWidget);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('1 note', findRichText: true), findsOneWidget);
    expect(find.text('~3 hrs'), findsOneWidget);
    expect(find.text('Fees (estimate)'), findsOneWidget);
    expect(find.text('~0.0001 ZEC'), findsOneWidget);
    expect(find.text('Part 1'), findsOneWidget);
    expect(find.text('Review shuffle'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Start migration'), findsOneWidget);
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

    await _openShuffleReview(tester);
    final prepareButton = find.widgetWithText(AppButton, 'Start migration');
    expect(prepareButton, findsOneWidget);
    expect(tester.widget<AppButton>(prepareButton).onPressed, isNotNull);

    await tester.tap(prepareButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(startedAccountUuid, 'account-1');
    expect(startedSchedule, _privatePlan().scheduledTransfers);
    expect(find.text('Migration in Progress'), findsOneWidget);
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

      await _openShuffleReview(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Start migration'));
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

    await _openShuffleReview(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Start migration'));
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
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

      await _openShuffleReview(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Start migration'));
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

    expect(find.text('Review migration plan'), findsOneWidget);
    expect(find.textContaining('1 note', findRichText: true), findsOneWidget);
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

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Note split'), findsOneWidget);
    expect(find.text('Split notes into 1 migration part'), findsOneWidget);
    expect(find.text('Wait 1 block for confirmation'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('ironwood_migration_prepare_step_split_complete'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('ironwood_migration_prepare_step_confirmations_active'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Migration will start automatically once note split is complete.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('You can leave this screen, but keep Vizor open & running.'),
      findsOneWidget,
    );
    expect(find.text('Scheduled'), findsNothing);
    expect(find.text('2'), findsNothing);
    expect(find.text('Currently Spendable Balance'), findsNothing);
    expect(find.text('You can leave this screen.'), findsNothing);
    expect(find.text('But keep Vizor open & running.'), findsNothing);
    expect(find.text('shown before send'), findsNothing);
    expect(find.text('Shown before each send'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Go home'), findsOneWidget);
  });

  testWidgets(
    'private status treats denomination confirmation wait as split complete',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _privateStatusHarness(
          status: _migrationStatus(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
            activeRunId: 'run-1',
            targetValuesZatoshi: const [
              1_000_000_000,
              200_000_000,
              50_000_000,
              20_000_000,
              10_000_000,
              2_000_000,
            ],
            pendingSplitStageCount: 6,
            denominationConfirmationCount: 0,
            denominationConfirmationTarget: 3,
            denominationSplitCompletedCount: 0,
            denominationSplitTotalCount: 6,
            totalCount: 6,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Split notes into 6 migration parts'), findsOneWidget);
      expect(find.text('Wait 3 blocks for confirmation'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('ironwood_migration_prepare_step_split_complete'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'ironwood_migration_prepare_step_confirmations_active',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('private preparing status uses independent part progress', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000, 10_000_000],
          pendingSplitStageCount: 1,
          denominationConfirmationCount: 0,
          denominationConfirmationTarget: 3,
          denominationSplitCompletedCount: 1,
          denominationSplitTotalCount: 2,
          totalCount: 2,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.preparing,
            ),
            _migrationPart(
              1,
              10_000_000,
              rust_sync.MigrationPartState.confirming,
              confirmationCount: 2,
              confirmationTarget: 3,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final firstTrackWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_track_0')),
        )
        .width;
    final secondTrackWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_track_1')),
        )
        .width;
    final firstFillWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_fill_0')),
        )
        .width;
    final secondFillWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_fill_1')),
        )
        .width;

    expect(firstTrackWidth, closeTo(secondTrackWidth, 1));
    expect(secondFillWidth, greaterThan(firstFillWidth * 4));
    expect(find.text('Preparing'), findsOneWidget);
    expect(find.text('Confirming...'), findsOneWidget);
  });

  testWidgets(
    'private ready-to-migrate status does not treat prepared denominations as completed transfers',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _privateStatusHarness(
          status: _migrationStatus(
            phase: kIronwoodMigrationReadyToMigratePhase,
            activeRunId: 'run-1',
            targetValuesZatoshi: const [1_000_000_000, 200_000_000],
            totalCount: 2,
            denominationConfirmationCount: 3,
            denominationConfirmationTarget: 3,
            denominationSplitCompletedCount: 2,
            denominationSplitTotalCount: 2,
            parts: [
              _migrationPart(
                0,
                1_000_000_000,
                rust_sync.MigrationPartState.completed,
              ),
              _migrationPart(
                1,
                200_000_000,
                rust_sync.MigrationPartState.completed,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Note split'), findsNothing);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Preparing'), findsNWidgets(2));
      expect(find.text('Currently Spendable Balance'), findsOneWidget);
      expect(find.text('0 ZEC'), findsOneWidget);
      expect(find.text('~2 mins'), findsNothing);
    },
  );

  testWidgets('private status keeps scheduled batches on the transfer UI', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000],
          totalCount: 1,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduleStartHeight: 700,
              scheduledHeight: 800,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Note split'), findsNothing);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Currently Spendable Balance'), findsOneWidget);
  });

  testWidgets('status can return home while background migration advances', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(status: _status(), coordinatorAdvancing: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final button = find.byKey(
      const ValueKey('ironwood_migration_status_action_button'),
    );
    expect(button, findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Go home'), findsOneWidget);
    expect(find.text('Updating...'), findsNothing);
    expect(tester.widget<AppButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('home-route'), findsOneWidget);
  });

  testWidgets('status does not return to intro for a stale pre-run response', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(phase: kIronwoodMigrationReadyPhase),
        coordinatorStatus: _status(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('intro-route'), findsNothing);
  });

  testWidgets('private status maps migration phases to actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cases = [
      _StatusUiCase(
        status: _status(),
        title: 'Migration in Progress',
        buttonLabel: 'Go home',
        buttonEnabled: true,
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationReadyToMigratePhase,
          activeRunId: 'run-1',
        ),
        title: 'Migration in Progress',
        buttonLabel: 'Go home',
        buttonEnabled: true,
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
        ),
        title: 'Migration in Progress',
        buttonLabel: 'Go home',
        buttonEnabled: true,
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastingPhase,
          activeRunId: 'run-1',
        ),
        title: 'Migration in Progress',
        buttonLabel: 'Go home',
        buttonEnabled: true,
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          activeRunId: 'run-1',
        ),
        title: 'Migration in Progress',
        buttonLabel: 'Go home',
        buttonEnabled: true,
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
        title: 'Migration in Progress',
        buttonLabel: 'Go home',
        buttonEnabled: true,
      ),
    ];

    for (final uiCase in cases) {
      await tester.pumpWidget(_privateStatusHarness(status: uiCase.status));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

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

    expect(find.text('Migration status unavailable'), findsOneWidget);
    expect(find.text('intro-route'), findsNothing);
  });

  testWidgets('private complete status uses all-completed transfer UI', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationCompletePhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000, 20_000_000, 30_000_000],
          broadcastedTxCount: 1,
          confirmedTxCount: 1,
          totalCount: 3,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.completed,
            ),
            _migrationPart(
              1,
              20_000_000,
              rust_sync.MigrationPartState.migrating,
            ),
            _migrationPart(
              2,
              30_000_000,
              rust_sync.MigrationPartState.scheduled,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Migration Complete'), findsNothing);
    expect(find.text('Back home'), findsNothing);
    expect(find.text('Migrating...'), findsNothing);
    expect(find.text('Scheduled'), findsNothing);
    expect(find.text('Completed'), findsAtLeastNWidgets(3));
    expect(find.text('Currently Spendable Balance'), findsOneWidget);
    expect(find.text('0.6 ZEC'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Go home'), findsOneWidget);
  });

  testWidgets('private transfer status uses authoritative per-part states', (
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
          broadcastedTxCount: 2,
          confirmedTxCount: 1,
          totalCount: 3,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.completed,
            ),
            _migrationPart(
              1,
              20_000_000,
              rust_sync.MigrationPartState.migrating,
            ),
            _migrationPart(
              2,
              30_000_000,
              rust_sync.MigrationPartState.scheduled,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Currently Spendable Balance'), findsOneWidget);
    expect(find.text('0.1 ZEC'), findsOneWidget);
  });

  testWidgets('private transfer status distinguishes mined from completed', (
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
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.confirming,
              confirmationCount: 1,
            ),
            _migrationPart(
              1,
              20_000_000,
              rust_sync.MigrationPartState.confirming,
              confirmationCount: 2,
            ),
            _migrationPart(
              2,
              30_000_000,
              rust_sync.MigrationPartState.completed,
              confirmationCount: 3,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Confirming...'), findsNWidgets(2));
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Scheduled'), findsNothing);
    expect(find.text('Currently Spendable Balance'), findsOneWidget);
    expect(find.text('0.3 ZEC'), findsOneWidget);
    expect(find.text('~3 mins'), findsOneWidget);
  });

  testWidgets('private transfer ETA estimates total completion time', (
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
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 897,
          chainTipHeight: 1000,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.text('Scheduled'), findsNWidgets(2));
    expect(find.text('~8 mins'), findsOneWidget);
    expect(find.text('Currently Spendable Balance'), findsOneWidget);
  });

  testWidgets('scheduled note progress follows remaining block height', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000],
          totalCount: 1,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduleStartHeight: 700,
              scheduledHeight: 800,
            ),
          ],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 750,
          chainTipHeight: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trackWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_track_0')),
        )
        .width;
    final fillWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_fill_0')),
        )
        .width;

    expect(fillWidth, closeTo(trackWidth * 0.35, 1));
  });

  testWidgets('note progress keeps dust migration parts readable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const values = [
      1_000_000_000,
      200_000_000,
      50_000_000,
      20_000_000,
      10_000_000,
      2_000_000,
    ];
    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: values,
          totalCount: values.length,
          parts: [
            for (var i = 0; i < values.length; i++)
              _migrationPart(
                i,
                values[i],
                rust_sync.MigrationPartState.scheduled,
                scheduleStartHeight: 700,
                scheduledHeight: 800,
              ),
          ],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 700,
          chainTipHeight: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstTrackWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_track_0')),
        )
        .width;
    final dustTrackWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_track_5')),
        )
        .width;

    expect(dustTrackWidth, greaterThanOrEqualTo(16));
    expect(firstTrackWidth, greaterThan(dustTrackWidth));
  });

  testWidgets(
    'scheduled note progress does not shrink when sync height drops',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harnessKey = GlobalKey<_MutablePrivateStatusHarnessState>();
      await tester.pumpWidget(
        _MutablePrivateStatusHarness(
          key: harnessKey,
          status: _migrationStatus(
            phase: kIronwoodMigrationBroadcastScheduledPhase,
            activeRunId: 'run-1',
            targetValuesZatoshi: const [10_000_000],
            totalCount: 1,
            parts: [
              _migrationPart(
                0,
                10_000_000,
                rust_sync.MigrationPartState.scheduled,
                scheduleStartHeight: 700,
                scheduledHeight: 800,
              ),
            ],
          ),
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 750,
            chainTipHeight: 1000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstFillWidth = tester
          .getSize(
            find.byKey(const ValueKey('ironwood_migration_segment_fill_0')),
          )
          .width;

      harnessKey.currentState!.setSyncState(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 710,
          chainTipHeight: 1000,
        ),
      );
      await tester.pumpAndSettle();

      final secondFillWidth = tester
          .getSize(
            find.byKey(const ValueKey('ironwood_migration_segment_fill_0')),
          )
          .width;

      expect(secondFillWidth, greaterThanOrEqualTo(firstFillWidth));
    },
  );

  testWidgets('migrating note progress does not shrink when advancing stops', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harnessKey = GlobalKey<_MutablePrivateStatusHarnessState>();
    await tester.pumpWidget(
      _MutablePrivateStatusHarness(
        key: harnessKey,
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastingPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000],
          totalCount: 1,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.migrating,
              scheduleStartHeight: 700,
              scheduledHeight: 800,
            ),
          ],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 800,
          chainTipHeight: 1000,
        ),
        coordinatorAdvancing: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final firstFillWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_fill_0')),
        )
        .width;

    harnessKey.currentState!.setCoordinatorAdvancing(false);
    await tester.pump();

    final secondFillWidth = tester
        .getSize(
          find.byKey(const ValueKey('ironwood_migration_segment_fill_0')),
        )
        .width;

    expect(secondFillWidth, greaterThanOrEqualTo(firstFillWidth));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(softwareContinued, isFalse);
    expect(find.text('Needs input'), findsOneWidget);
    expect(find.text('keystone-batch-sign-route'), findsNothing);

    await tester.tap(find.widgetWithText(AppButton, 'Sign with Keystone'));
    await tester.pumpAndSettle();

    expect(softwareContinued, isFalse);
    expect(find.text('keystone-batch-sign-route'), findsOneWidget);
  });

  testWidgets('private status retries a recoverable error on request', (
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
          phase: kIronwoodMigrationFailedRecoverablePhase,
          activeRunId: 'run-1',
        ),
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    expect(continueCount, 0);
    await tester.tap(find.widgetWithText(AppButton, 'Retry migration'));
    await tester.pumpAndSettle();

    expect(continueCount, 1);
  });

  testWidgets('migration entry routes start state to prepare', (tester) async {
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

    expect(find.text('prepare-route'), findsOneWidget);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

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

  testWidgets('migration entry keeps hidden state in migration flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: const IronwoodHomeMigrationCtaState.hidden(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('prepare-route'), findsOneWidget);
    expect(find.text('home-route'), findsNothing);
  });

  testWidgets('migration entry does not wait for route CTA loading', (
    tester,
  ) async {
    final pendingCta = Completer<IronwoodHomeMigrationCtaState>();

    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: const IronwoodHomeMigrationCtaState.hidden(),
        routeCtaFuture: pendingCta.future,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('prepare-route'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('home-route'), findsNothing);
  });

  testWidgets('prepare stays in loading state while sync is running', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationPrepareHarness(
        inputs: _migrationInputs(isSyncing: true, isSyncComplete: false),
        statusGetter:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(_migrationStatus());
            },
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('intro-route'), findsNothing);
    expect(find.text('home-route'), findsNothing);
  });

  testWidgets('prepare opens intro after confirming migration is startable', (
    tester,
  ) async {
    var statusCalls = 0;

    await tester.pumpWidget(
      _migrationPrepareHarness(
        statusGetter:
            ({required dbPath, required network, required accountUuid}) {
              statusCalls += 1;
              return Future.value(
                _migrationStatus(phase: kIronwoodMigrationReadyPhase),
              );
            },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('intro-route'), findsOneWidget);
    expect(statusCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('prepare opens status when migration already has an active run', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationPrepareHarness(
        statusGetter:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(
                _migrationStatus(
                  phase: kIronwoodMigrationBroadcastScheduledPhase,
                  activeRunId: 'run-1',
                ),
              );
            },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('private-status-route'), findsOneWidget);
  });

  testWidgets(
    'migration flow does not redirect home when data is unavailable',
    (tester) async {
      await tester.pumpWidget(_migrationFlowDataHarness(flowData: null));
      await tester.pump();

      expect(find.text('Zcash Network Upgrade'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('home-route'), findsNothing);
    },
  );

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
            (ref) => IronwoodMigrationFlowData(
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
              isSyncComplete: true,
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

Future<void> _openShuffleReview(WidgetTester tester) async {
  expect(find.text('Review shuffle'), findsNothing);
  expect(find.widgetWithText(AppButton, 'Start migration'), findsOneWidget);
}

class _MigrationInputsNotifier extends Notifier<IronwoodMigrationInputs> {
  @override
  IronwoodMigrationInputs build() => _migrationInputs();

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
      isSyncComplete: state.isSyncComplete,
      hasSyncFailure: state.hasSyncFailure,
      orchardBalance: state.orchardBalance,
      orchardPendingBalance: state.orchardPendingBalance,
      ironwoodBalance: state.ironwoodBalance,
      ironwoodPendingBalance: state.ironwoodPendingBalance,
    );
  }
}

IronwoodMigrationInputs _migrationInputs({
  bool ironwoodActiveAtTip = true,
  String network = 'test',
  String? accountUuid = 'account-1',
  bool hasAccountScopedData = true,
  bool isSyncing = false,
  bool isBackgroundMode = false,
  bool isSyncComplete = true,
  bool hasSyncFailure = false,
  BigInt? orchardBalance,
  BigInt? orchardPendingBalance,
  BigInt? ironwoodBalance,
  BigInt? ironwoodPendingBalance,
}) {
  return IronwoodMigrationInputs(
    ironwoodActiveAtTip: ironwoodActiveAtTip,
    network: network,
    accountUuid: accountUuid,
    accountName: 'Account 1',
    profilePictureId: kDefaultProfilePictureId,
    hasAccountScopedData: hasAccountScopedData,
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    isSyncComplete: isSyncComplete,
    hasSyncFailure: hasSyncFailure,
    orchardBalance: orchardBalance ?? BigInt.from(10_000_000),
    orchardPendingBalance: orchardPendingBalance ?? BigInt.zero,
    ironwoodBalance: ironwoodBalance ?? BigInt.zero,
    ironwoodPendingBalance: ironwoodPendingBalance ?? BigInt.zero,
  );
}

Widget _migrationOptionsHarness({
  String initialLocation = '/migration/options',
  IronwoodMigrationService? migrationService,
  bool activeAccountIsHardware = false,
  bool realStatusRoute = false,
  OrchardMigrationStatusGetter? statusGetter,
  bool coordinatorAdvancing = false,
  rust_sync.MigrationStatus? coordinatorStatus,
  Duration analyzingMinimumDuration = Duration.zero,
  bool disableAnimations = true,
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
      ironwoodMigrationAnalyzingMinimumDurationProvider.overrideWithValue(
        analyzingMinimumDuration,
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _ScreenTestMigrationCoordinator(
          migrationService,
          advancing: coordinatorAdvancing,
          status: coordinatorStatus,
        ),
      ),
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
            isSyncComplete: true,
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
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.noScaling,
        ),
        child: AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
}

class _ScreenTestMigrationCoordinator extends IronwoodMigrationCoordinator {
  _ScreenTestMigrationCoordinator(
    this.service, {
    this.advancing = false,
    this.status,
  });

  final IronwoodMigrationService? service;
  final bool advancing;
  final rust_sync.MigrationStatus? status;

  @override
  IronwoodMigrationCoordinatorState build() =>
      IronwoodMigrationCoordinatorState(
        statuses: status == null ? const {} : {'account-1': status!},
        advancingAccounts: advancing ? const {'account-1'} : const {},
      );

  @override
  Future<void> startSoftwareMigration({
    required String accountUuid,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) async {
    await service?.startSoftwarePrivateMigration(
      accountUuid: accountUuid,
      approvedSchedule: approvedSchedule,
    );
  }

  @override
  Future<void> retry(String accountUuid) async {
    await service?.continueSoftwarePrivateMigration(accountUuid: accountUuid);
  }
}

class _MutableScreenTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  _MutableScreenTestMigrationCoordinator({required this.advancing});

  final bool advancing;

  @override
  IronwoodMigrationCoordinatorState build() =>
      IronwoodMigrationCoordinatorState(
        advancingAccounts: advancing ? const {'account-1'} : const {},
      );

  void setAdvancing(bool advancing) {
    state = state.copyWith(
      advancingAccounts: advancing ? const {'account-1'} : const {},
    );
  }
}

class _MutableSyncNotifier extends SyncNotifier {
  _MutableSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;

  void setSyncState(SyncState nextState) {
    state = AsyncData(nextState);
  }
}

class _MutablePrivateStatusHarness extends StatefulWidget {
  const _MutablePrivateStatusHarness({
    super.key,
    required this.status,
    required this.syncState,
    this.coordinatorAdvancing = false,
  });

  final rust_sync.MigrationStatus status;
  final SyncState syncState;
  final bool coordinatorAdvancing;

  @override
  State<_MutablePrivateStatusHarness> createState() =>
      _MutablePrivateStatusHarnessState();
}

class _MutablePrivateStatusHarnessState
    extends State<_MutablePrivateStatusHarness> {
  final _scopeKey = GlobalKey();
  late rust_sync.MigrationStatus _status;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
  }

  ProviderContainer get _container =>
      ProviderScope.containerOf(_scopeKey.currentContext!, listen: false);

  void setStatus(rust_sync.MigrationStatus status) {
    setState(() => _status = status);
  }

  void setSyncState(SyncState syncState) {
    (_container.read(syncProvider.notifier) as _MutableSyncNotifier)
        .setSyncState(syncState);
  }

  void setCoordinatorAdvancing(bool advancing) {
    (_container.read(ironwoodMigrationCoordinatorProvider.notifier)
            as _MutableScreenTestMigrationCoordinator)
        .setAdvancing(advancing);
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/migration/private/status',
      routes: [
        GoRoute(
          path: '/migration/private/status',
          builder: (_, _) =>
              IronwoodMigrationPrivateStatusScreen(previewStatus: _status),
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
          _bootstrapFor(activeAccountIsHardware: false),
        ),
        syncProvider.overrideWith(() => _MutableSyncNotifier(widget.syncState)),
        ironwoodMigrationCoordinatorProvider.overrideWith(
          () => _MutableScreenTestMigrationCoordinator(
            advancing: widget.coordinatorAdvancing,
          ),
        ),
        swapFeatureEnabledProvider.overrideWithValue(true),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
      ],
      child: Builder(
        key: _scopeKey,
        builder: (context) => MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.noScaling,
            ),
            child: AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      ),
    );
  }
}

Widget _privateStatusHarness({
  required rust_sync.MigrationStatus status,
  OrchardMigrationStatusGetter? statusGetter,
  IronwoodMigrationService? migrationService,
  bool activeAccountIsHardware = false,
  bool coordinatorAdvancing = false,
  rust_sync.MigrationStatus? coordinatorStatus,
  SyncState? syncState,
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
    coordinatorAdvancing: coordinatorAdvancing,
    coordinatorStatus: coordinatorStatus,
    syncState: syncState,
  );
}

Widget _migrationFlowDataHarness({
  required IronwoodMigrationFlowData? flowData,
}) {
  final router = GoRouter(
    initialLocation: '/migration/intro',
    routes: [
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => const IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.intro,
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
    ],
  );

  return ProviderScope(
    overrides: [
      ironwoodMigrationFlowDataProvider.overrideWith((ref) => flowData),
      appBootstrapProvider.overrideWithValue(
        _bootstrapFor(activeAccountIsHardware: false),
      ),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncedSyncState)),
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        const IronwoodHomeMigrationCtaState.hidden(),
      ),
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

Widget _migrationPrepareHarness({
  IronwoodMigrationInputs? inputs,
  OrchardMigrationStatusGetter? statusGetter,
  Object? routeError,
}) {
  final router = GoRouter(
    initialLocation: '/migration/prepare',
    routes: [
      GoRoute(
        path: '/migration/prepare',
        builder: (_, _) => const IronwoodMigrationPrepareScreen(),
      ),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => const Text('intro-route'),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => const Text('private-status-route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
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
      ironwoodMigrationInputsProvider.overrideWithValue(
        inputs ?? _migrationInputs(),
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
              return _migrationStatus();
            },
      ),
      appBootstrapProvider.overrideWithValue(
        _bootstrapFor(activeAccountIsHardware: false),
      ),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncedSyncState)),
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        const IronwoodHomeMigrationCtaState.hidden(),
      ),
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

Widget _migrationEntryHarness({
  required IronwoodHomeMigrationCtaState ctaState,
  String initialLocation = '/migration',
  Future<IronwoodHomeMigrationCtaState>? routeCtaFuture,
  Object? routeError,
  bool realStatusRoute = false,
  rust_sync.MigrationStatus? routeStatus,
  OrchardMigrationStatusGetter? statusGetter,
  IronwoodMigrationService? migrationService,
  bool activeAccountIsHardware = false,
  bool coordinatorAdvancing = false,
  rust_sync.MigrationStatus? coordinatorStatus,
  SyncState? syncState,
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
        path: '/migration/prepare',
        builder: (_, _) => const Text('prepare-route'),
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
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(ctaState),
      ironwoodMigrationRouteCtaProvider.overrideWith((ref) async {
        final future = routeCtaFuture;
        if (future != null) return future;
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
          isSyncComplete: true,
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
      syncProvider.overrideWith(
        () => _FakeSyncNotifier(syncState ?? _syncedSyncState),
      ),
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _ScreenTestMigrationCoordinator(
          migrationService,
          advancing: coordinatorAdvancing,
          status: coordinatorStatus,
        ),
      ),
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
        partIndex: 0,
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
  int denominationConfirmationCount = 0,
  int denominationConfirmationTarget = 0,
  int denominationSplitCompletedCount = 0,
  int denominationSplitTotalCount = 0,
  List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts = const [],
  List<rust_sync.MigrationPartStatus> parts = const [],
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList(targetValuesZatoshi),
    preparedNoteCount: 0,
    denominationConfirmationCount: denominationConfirmationCount,
    denominationConfirmationTarget: denominationConfirmationTarget,
    denominationSplitCompletedCount: denominationSplitCompletedCount,
    denominationSplitTotalCount: denominationSplitTotalCount,
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
    parts: parts,
  );
}

rust_sync.MigrationPartStatus _migrationPart(
  int partIndex,
  int valueZatoshi,
  rust_sync.MigrationPartState state, {
  int confirmationCount = 0,
  int confirmationTarget = 3,
  int? scheduleStartHeight,
  int? scheduledHeight,
}) => rust_sync.MigrationPartStatus(
  partIndex: partIndex,
  valueZatoshi: BigInt.from(valueZatoshi),
  state: state,
  scheduleStartHeight: scheduleStartHeight,
  scheduledHeight: scheduledHeight,
  confirmationCount: confirmationCount,
  confirmationTarget: confirmationTarget,
);

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
    parts: const [],
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
