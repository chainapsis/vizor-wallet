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
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_loading_icon.dart';
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

  testWidgets('what-to-expect screen shows the four migration expectations', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/what-to-expect'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migrations can take a long time'), findsOneWidget);
    expect(find.text('You can spend as funds arrive'), findsOneWidget);
    expect(find.text('Use VPN for an extra privacy'), findsOneWidget);
    expect(find.text('Keep Vizor running'), findsOneWidget);
    expect(find.textContaining('VPN/network privacy layer'), findsOneWidget);
    expect(
      find.textContaining('send the next migration transaction'),
      findsOneWidget,
    );
    expect(find.textContaining('continues while minimized'), findsNothing);

    final expectationImages = find.byWidgetPredicate((widget) {
      if (widget is! Image || widget.image is! AssetImage) return false;
      final assetName = (widget.image as AssetImage).assetName;
      return assetName.startsWith(
        'assets/illustrations/ironwood_migration_expect_',
      );
    });
    expect(expectationImages, findsNWidgets(4));

    await tester.tap(find.widgetWithText(AppButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Immediate'), findsOneWidget);
  });

  testWidgets('option selection does not move card content', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_migrationOptionsHarness());
    await tester.pumpAndSettle();

    final privateTitle = find.text('Private');
    final fastTitle = find.text('Immediate');
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

    await tester.tap(find.text('Select & review'));
    await tester.pumpAndSettle();

    expect(find.text('Ironwood Migration'), findsOneWidget);
    expect(find.text('Amount to migrate'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Start migration'), findsOneWidget);
  });

  testWidgets('immediate selection opens the explicit privacy warning', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_migrationOptionsHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Immediate'));
    await tester.tap(find.text('Select & review'));
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Privacy trade-off'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Authorise anyway'), findsOneWidget);
  });

  testWidgets('offers Immediate migration to Keystone accounts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(activeAccountIsHardware: true),
    );
    await tester.pumpAndSettle();

    final immediateOption = find.byKey(
      const ValueKey('ironwood_migration_fast_option'),
    );
    final immediateGesture = find.descendant(
      of: immediateOption,
      matching: find.byType(GestureDetector),
    );
    expect(tester.widget<GestureDetector>(immediateGesture).onTap, isNotNull);

    await tester.tap(find.text('Immediate'));
    await tester.tap(find.text('Select & review'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppButton, 'Authorise anyway'), findsOneWidget);
    expect(find.text('Privacy trade-off'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Authorise anyway'));
    await tester.pumpAndSettle();
    expect(find.text('keystone-immediate-sign-route:9990000'), findsOneWidget);
  });

  testWidgets('Immediate review reports an unavailable plan', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(
        initialLocation: '/migration/immediate/review',
        useImmediatePreview: false,
        migrationService: _immediatePlanService(() async => null),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No spendable Orchard balance is available for Immediate migration.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(AppButton, 'Unavailable'), findsOneWidget);
  });

  testWidgets('Immediate review retries a failed plan calculation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var callCount = 0;
    var failPlan = true;
    await tester.pumpWidget(
      _migrationOptionsHarness(
        initialLocation: '/migration/immediate/review',
        useImmediatePreview: false,
        migrationService: _immediatePlanService(() async {
          callCount++;
          if (failPlan) throw Exception('plan failed');
          return _immediatePlan();
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Couldn't calculate the Immediate migration plan. Sync and try again.",
      ),
      findsOneWidget,
    );
    failPlan = false;
    await tester.tap(find.widgetWithText(AppButton, 'Retry calculation'));
    await tester.pumpAndSettle();

    expect(callCount, greaterThanOrEqualTo(2));
    expect(find.widgetWithText(AppButton, 'Authorise anyway'), findsOneWidget);
    expect(find.text('0.0999 ZEC'), findsOneWidget);
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
    expect(find.text('Ironwood Migration'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1919));
    expect(find.text('Analyzing your balance...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Finding private batches...'), findsOneWidget);
    expect(find.text('Ironwood Migration'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1590));
    expect(find.text('Finding private batches...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Preparing your migration plan...'), findsOneWidget);
    expect(find.text('Ironwood Migration'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1590));
    expect(
      find.byKey(const ValueKey('ironwood_migration_analyzing_screen')),
      findsOneWidget,
    );
    expect(find.text('Ironwood Migration'), findsNothing);

    await tester.pump(const Duration(milliseconds: 81));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('ironwood_migration_analyzing_screen')),
      findsNothing,
    );
    expect(find.text('Ironwood Migration'), findsOneWidget);
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

    expect(find.text('Amount to migrate'), findsOneWidget);
    expect(find.text('Est. preparation completion'), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 700));

    expect(startedAccountUuid, 'account-1');
    expect(startedSchedule, _privatePlan().scheduledTransfers);
    expect(find.text('Next split'), findsOneWidget);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Next split'), findsOneWidget);
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

  test(
    'Keystone migration explains a signed QR from another signing round',
    () {
      final message = ironwoodMigrationKeystoneSigningErrorMessage(
        Exception(
          'Keystone batch result request id does not match the request',
        ),
      );

      expect(
        message,
        'This signed QR is from another round. Go back, scan the current '
        'request with Keystone, then scan its new signed QR.',
      );
    },
  );

  testWidgets(
    'desktop Keystone scanner back returns to the current request QR',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final request = rust_sync.KeystoneMigrationSigningRequest(
        requestId: 'preview-request',
        messages: [
          rust_sync.KeystoneMigrationMessage(
            id: 'split-1',
            redactedPczt: Uint8List.fromList([1]),
          ),
          rust_sync.KeystoneMigrationMessage(
            id: 'split-2',
            redactedPczt: Uint8List.fromList([2]),
          ),
        ],
        signingBatchLimit: 1,
      );
      await tester.pumpWidget(
        _migrationOptionsHarness(
          initialLocation: '/migration/private/keystone/sign',
          activeAccountIsHardware: true,
          previewCombinedSigningRequest: request,
          previewCombinedSigningUrParts: const ['UR:ZCASH-SIGN-BATCH/PREVIEW'],
        ),
      );
      await tester.pump();

      expect(find.text('Step 1 of 2'), findsNothing);
      expect(find.text('Round 1 of 2'), findsOneWidget);
      expect(find.text('Scan request with Keystone'), findsOneWidget);
      expect(
        find.text(
          'Scan this request QR with Keystone. Keystone will show a new '
          'signed QR when it finishes.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('1 transaction to sign · click QR to enlarge'),
        findsOneWidget,
      );

      final enlargeQr = find.byKey(
        const ValueKey('keystone_migration_enlarge_qr'),
      );
      expect(enlargeQr, findsOneWidget);
      await tester.tap(enlargeQr);
      await tester.pumpAndSettle();

      final enlargedQr = find.byKey(
        const ValueKey('keystone_migration_enlarged_qr'),
      );
      expect(enlargedQr, findsOneWidget);
      expect(tester.getSize(enlargedQr), const Size.square(520));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(enlargedQr, findsNothing);

      await tester.tap(
        find.widgetWithText(AppButton, 'Scan Keystone signature'),
      );
      await tester.pump();

      expect(find.text('Step 2 of 2'), findsNothing);
      expect(find.text('Round 1 of 2'), findsOneWidget);
      expect(find.text('Scan Keystone signature'), findsOneWidget);
      expect(
        find.text('Scan the new signed QR shown on Keystone.'),
        findsOneWidget,
      );
      expect(find.text('Back to QR'), findsNothing);

      final back = find.bySemanticsLabel('Back to Review migration');
      await tester.tap(back);
      await tester.pump();

      expect(find.text('Step 1 of 2'), findsNothing);
      expect(find.text('Scan request with Keystone'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ironwood_migration_review_screen')),
        findsNothing,
      );

      await tester.tap(back);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ironwood_migration_review_screen')),
        findsOneWidget,
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

  testWidgets('private review routes Keystone accounts to combined signing', (
    tester,
  ) async {
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
    expect(find.text('keystone-combined-sign-route:1:144'), findsOneWidget);
  });

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

    expect(find.text('Ironwood Migration'), findsOneWidget);
    expect(find.text('Amount to migrate'), findsOneWidget);
  });

  testWidgets('private status shows resume progress state', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/private/status'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Next split'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ironwood_migration_preparation_ring')),
      findsOneWidget,
    );
    expect(find.text('Splits remaining'), findsOneWidget);
    expect(find.text('Est. completion'), findsOneWidget);
    expect(find.text('Current block'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'View Schedule'), findsOneWidget);
    expect(find.text('Note split'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Go home'), findsNothing);
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

      expect(find.text('Next split'), findsOneWidget);
      final loader = tester.widget<AppIcon>(
        find.byKey(const ValueKey('ironwood_migration_preparation_loader')),
      );
      expect(loader.name, AppIcons.loader);
      expect(loader.size, AppIconSize.large);
      expect(find.text('Split 1 of 6'), findsOneWidget);
      expect(find.textContaining('confirmations'), findsNothing);
      expect(
        find.bySemanticsLabel('Preparing migration notes.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('preparation status shows only the active substep', (
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
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          activeRunId: 'run-1',
          denominationConfirmationCount: 0,
          denominationConfirmationTarget: 3,
          denominationSplitCompletedCount: 2,
          denominationSplitTotalCount: 8,
          totalCount: 8,
        ),
        syncState: _syncedSyncState,
      ),
    );
    await tester.pump();

    expect(find.text('Split 3 of 8'), findsOneWidget);
    expect(find.textContaining('confirmations'), findsNothing);

    harnessKey.currentState!.setStatus(
      _migrationStatus(
        phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        activeRunId: 'run-1',
        denominationConfirmationCount: 1,
        denominationConfirmationTarget: 3,
        denominationSplitCompletedCount: 2,
        denominationSplitTotalCount: 8,
        totalCount: 8,
      ),
    );
    await tester.pump();

    expect(find.text('Split 3 of 8'), findsOneWidget);
    expect(find.text('Schedule pending'), findsOneWidget);
  });

  testWidgets('preparation ring remains available with reduced motion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(status: _status(), disableAnimations: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('ironwood_migration_preparation_ring')),
      findsOneWidget,
    );
    expect(find.text('Next split'), findsOneWidget);
    final loader = find.descendant(
      of: find.byKey(const ValueKey('ironwood_migration_preparation_loader')),
      matching: find.byType(AppLoadingIcon),
    );
    expect(loader, findsOneWidget);
    expect(MediaQuery.maybeDisableAnimationsOf(tester.element(loader)), isTrue);
  });

  testWidgets('private preparing status does not expose note progress', (
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

    expect(
      find.byKey(const ValueKey('ironwood_migration_preparation_ring')),
      findsOneWidget,
    );
    expect(find.text('Preparing'), findsNothing);
    expect(find.text('Confirming...'), findsNothing);
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
            proofReady: false,
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
      expect(find.text('Ironwood Migration'), findsOneWidget);
      expect(find.text('Next migration'), findsOneWidget);
      expect(find.text('10 ZEC'), findsOneWidget);
      expect(find.text('12 ZEC'), findsOneWidget);
      expect(find.text('Left to migrate'), findsOneWidget);
      expect(find.text('Schedule pending'), findsNWidgets(2));
      expect(find.text('~2 mins'), findsNothing);
    },
  );

  testWidgets(
    'private ready-to-migrate status preserves completed migration notes',
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
            proofReady: true,
            targetValuesZatoshi: const [1_000_000_000, 200_000_000],
            totalCount: 2,
            confirmedTxCount: 1,
            parts: [
              _migrationPart(
                0,
                1_000_000_000,
                rust_sync.MigrationPartState.completed,
              ),
              _migrationPart(
                1,
                200_000_000,
                rust_sync.MigrationPartState.preparing,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Next migration'), findsOneWidget);
      expect(find.text('2 ZEC'), findsNWidgets(2));
      expect(find.text('Left to migrate'), findsOneWidget);
      expect(find.text('Schedule pending'), findsNWidgets(2));
    },
  );

  testWidgets('anchor wait shows the next migration window and batch amount', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationReadyToMigratePhase,
          activeRunId: 'run-1',
          proofReady: false,
          signedChildPcztCount: 2,
          nextActionHeight: 1_144,
          nextProofWindowHeight: 1_144,
          nextProofWindowPartIndices: const [1, 2],
          targetValuesZatoshi: const [1_000_000_000, 200_000_000, 300_000_000],
          totalCount: 3,
          parts: [
            _migrationPart(
              0,
              1_000_000_000,
              rust_sync.MigrationPartState.completed,
              scheduleOrder: 0,
            ),
            _migrationPart(
              1,
              200_000_000,
              rust_sync.MigrationPartState.preparing,
              scheduleOrder: 1,
              scheduledHeight: 1_150,
            ),
            _migrationPart(
              2,
              300_000_000,
              rust_sync.MigrationPartState.preparing,
              scheduleOrder: 2,
              scheduledHeight: 1_160,
            ),
          ],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 1_000,
          chainTipHeight: 1_000,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Next migration window'), findsOneWidget);
    expect(find.text('5 ZEC'), findsNWidgets(2));
    expect(find.text('Expected at'), findsOneWidget);
    expect(find.text('1,144'), findsOneWidget);
  });

  testWidgets(
    'reached migration window reports wallet sync while proof is unavailable',
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
            proofReady: false,
            signedChildPcztCount: 1,
            nextActionHeight: 1_144,
            nextProofWindowHeight: 1_144,
            nextProofWindowPartIndices: const [0],
            targetValuesZatoshi: const [200_000_000],
            totalCount: 1,
            parts: [
              _migrationPart(
                0,
                200_000_000,
                rust_sync.MigrationPartState.preparing,
                scheduledHeight: 1_150,
              ),
            ],
          ),
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 1_144,
            chainTipHeight: 1_144,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Opening migration window'), findsOneWidget);
      expect(find.text('Waiting for wallet sync'), findsOneWidget);
    },
  );

  testWidgets(
    'an earlier broadcast takes priority over the next proof window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _privateStatusHarness(
          status: _migrationStatus(
            phase: kIronwoodMigrationBroadcastScheduledPhase,
            activeRunId: 'run-1',
            proofReady: false,
            pendingTxCount: 1,
            signedChildPcztCount: 1,
            nextActionHeight: 1_100,
            nextProofWindowHeight: 1_144,
            nextProofWindowPartIndices: const [1],
            targetValuesZatoshi: const [100_000_000, 200_000_000],
            totalCount: 2,
            parts: [
              _migrationPart(
                0,
                100_000_000,
                rust_sync.MigrationPartState.scheduled,
                scheduledHeight: 1_100,
              ),
              _migrationPart(
                1,
                200_000_000,
                rust_sync.MigrationPartState.preparing,
                scheduledHeight: 1_200,
              ),
            ],
          ),
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 1_000,
            chainTipHeight: 1_000,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Next migration'), findsOneWidget);
      expect(find.text('Next migration window'), findsNothing);
      expect(find.text('1,100'), findsOneWidget);
    },
  );

  testWidgets('an overdue migration is shown as sending now', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
          nextActionHeight: 510,
          nextProofWindowHeight: 566,
          nextProofWindowPartIndices: const [1],
          targetValuesZatoshi: const [5_000_000_000, 2_000_000_000],
          totalCount: 2,
          pendingTxCount: 1,
          signedChildPcztCount: 1,
          parts: [
            _migrationPart(
              0,
              5_000_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduledHeight: 510,
            ),
            _migrationPart(
              1,
              2_000_000_000,
              rust_sync.MigrationPartState.preparing,
              scheduledHeight: 615,
            ),
          ],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 550,
          chainTipHeight: 550,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Sending migration'), findsOneWidget);
    expect(find.text('Sending now'), findsOneWidget);
    expect(find.text('50 ZEC'), findsOneWidget);
    expect(find.text('510'), findsNothing);
    expect(find.text('Next migration window'), findsNothing);
  });

  testWidgets('preparing and scheduled notes use the same ring color', (
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
          targetValuesZatoshi: const [100_000_000, 200_000_000],
          totalCount: 2,
          pendingTxCount: 1,
          signedChildPcztCount: 1,
          parts: [
            _migrationPart(
              0,
              100_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduledHeight: 1_100,
            ),
            _migrationPart(
              1,
              200_000_000,
              rust_sync.MigrationPartState.preparing,
              scheduledHeight: 1_200,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ironwood_migration_ring_paint')),
    );
    final dynamic painter = paint.painter;
    final segments = painter.segments as List<dynamic>;
    expect(segments[0].color, segments[1].color);
  });

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
    expect(find.text('Ironwood Migration'), findsOneWidget);
    expect(find.text('Next migration'), findsOneWidget);
    expect(find.text('0.1 ZEC'), findsNWidgets(2));
    expect(find.text('800'), findsOneWidget);
    expect(find.text('Left to migrate'), findsOneWidget);
  });

  testWidgets('ring center shows the next scheduled note, not batch totals', (
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
          targetValuesZatoshi: const [
            3_000_000_000,
            1_000_000_000,
            2_000_000_000,
          ],
          totalCount: 3,
          estimatedCompletionHeight: 1016,
          parts: [
            _migrationPart(
              0,
              3_000_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduleOrder: 2,
              scheduledHeight: 1010,
            ),
            _migrationPart(
              1,
              1_000_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduleOrder: 0,
              scheduledHeight: 1002,
            ),
            _migrationPart(
              2,
              2_000_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduleOrder: 1,
              scheduledHeight: 1006,
            ),
          ],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 1000,
          chainTipHeight: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next migration'), findsOneWidget);
    expect(find.text('10 ZEC'), findsOneWidget);
    expect(find.text('1,002'), findsOneWidget);
    expect(find.text('60 ZEC'), findsOneWidget);
    expect(find.text('in ~20 minutes'), findsOneWidget);
  });

  testWidgets('preparing status opens its separate schedule', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(status: _status(), coordinatorAdvancing: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('ironwood_migration_status_action_button')),
      findsNothing,
    );
    expect(find.widgetWithText(AppButton, 'Go home'), findsNothing);
    expect(find.text('Next split'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'View Schedule'), findsOneWidget);
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

    expect(find.text('Next split'), findsOneWidget);
    expect(find.text('intro-route'), findsNothing);
  });

  testWidgets('private status keeps cached state when status refresh fails', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cachedStatus = _status();
    await tester.pumpWidget(
      _privateStatusHarness(
        status: cachedStatus,
        statusGetter:
            ({required dbPath, required network, required accountUuid}) =>
                Future.error(Exception('database is locked')),
        coordinatorStatus: cachedStatus,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Next split'), findsOneWidget);
    expect(find.text('Migration status unavailable'), findsNothing);
  });

  testWidgets('private status maps migration phases to actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cases = [
      _StatusUiCase(status: _status(), title: 'Next split'),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationReadyToMigratePhase,
          activeRunId: 'run-1',
        ),
        title: 'Ironwood Migration',
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
        ),
        title: 'Ironwood Migration',
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastingPhase,
          activeRunId: 'run-1',
        ),
        title: 'Ironwood Migration',
      ),
      _StatusUiCase(
        status: _migrationStatus(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          activeRunId: 'run-1',
        ),
        title: 'Ironwood Migration',
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
        title: 'Your\n0 ZEC\nare on Ironwood!',
        buttonLabel: 'Done',
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

    expect(find.text('Your\n0.6 ZEC\nare on Ironwood!'), findsOneWidget);
    expect(find.text('Back home'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Done'), findsOneWidget);
  });

  testWidgets('private complete fallback without run details returns home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(phase: kIronwoodMigrationCompletePhase),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home-route'), findsOneWidget);
    expect(find.text('0 ZEC'), findsNothing);
    expect(find.text('Completed'), findsNothing);
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

    expect(find.text('Next migration'), findsOneWidget);
    expect(find.text('0.3 ZEC'), findsOneWidget);
    expect(find.text('Left to migrate'), findsOneWidget);
    expect(find.text('0.5 ZEC'), findsOneWidget);
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

    expect(find.text('Confirming'), findsOneWidget);
    expect(find.text('2 notes awaiting confirmation'), findsOneWidget);
    expect(find.text('Left to migrate'), findsOneWidget);
    expect(find.text('0.3 ZEC'), findsNWidgets(2));
    expect(find.text('~3 mins'), findsNothing);
    expect(
      find.textContaining('The next signing window will open'),
      findsNothing,
    );
  });

  testWidgets('ring center summarizes notes after every note is broadcast', (
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
          broadcastedTxCount: 3,
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
              rust_sync.MigrationPartState.migrating,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Next migration'), findsNothing);
    expect(find.text('Awaiting mining'), findsOneWidget);
    expect(find.text('2 notes broadcast'), findsOneWidget);
    expect(find.text('0.5 ZEC'), findsNWidgets(2));
  });

  testWidgets('private transfer status omits completion estimate footer', (
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

    expect(find.text('Ironwood Migration'), findsOneWidget);
    expect(find.text('~8 mins'), findsNothing);
    expect(
      find.textContaining('The next signing window will open'),
      findsNothing,
    );
    expect(find.text('Next migration'), findsOneWidget);
    expect(find.text('0.2 ZEC'), findsOneWidget);
    expect(find.text('900'), findsOneWidget);
    expect(find.text('Left to migrate'), findsOneWidget);
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

    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
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

    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
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

      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));

      harnessKey.currentState!.setSyncState(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 710,
          chainTipHeight: 1000,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
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

    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));

    harnessKey.currentState!.setCoordinatorAdvancing(false);
    await tester.pump();

    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'preparation ring morphs in place into processing-ordered note segments',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harnessKey = GlobalKey<_MutablePrivateStatusHarnessState>();
      await tester.pumpWidget(
        _MutablePrivateStatusHarness(
          key: harnessKey,
          status: _status(),
          syncState: _syncedSyncState,
          disableAnimations: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 450));

      final activeStatus = find.byKey(
        const ValueKey('ironwood_migration_active_status'),
      );
      expect(activeStatus, findsOneWidget);
      final activeStatusElement = tester.element(activeStatus);
      final ringCenter = find.byKey(
        const ValueKey('ironwood_migration_ring_center'),
      );
      final ringCenterElement = tester.element(ringCenter);
      await _captureMigrationTransitionGolden(activeStatus, 0);
      expect(
        find.bySemanticsLabel('Preparing migration notes.'),
        findsOneWidget,
      );

      harnessKey.currentState!.setStatus(
        _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-1',
          targetValuesZatoshi: const [10_000_000, 20_000_000, 30_000_000],
          totalCount: 3,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.scheduled,
              scheduleOrder: 1,
              scheduledHeight: 300,
            ),
            _migrationPart(
              1,
              20_000_000,
              rust_sync.MigrationPartState.completed,
              scheduleOrder: 2,
              scheduledHeight: 100,
            ),
            _migrationPart(
              2,
              30_000_000,
              rust_sync.MigrationPartState.confirming,
              scheduleOrder: 0,
              scheduledHeight: 200,
            ),
          ],
        ),
      );

      var frameIndex = 1;
      final confirmingMotionStrengths = <double>[];
      for (final frame in const [0, 230, 230, 230, 230]) {
        await tester.pump(Duration(milliseconds: frame));
        expect(activeStatus, findsOneWidget);
        expect(tester.element(activeStatus), same(activeStatusElement));
        expect(tester.element(ringCenter), same(ringCenterElement));
        expect(tester.takeException(), isNull);
        final dynamic painter = tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('ironwood_migration_ring_paint')),
            )
            .painter;
        final segments = painter.segments as List<dynamic>;
        confirmingMotionStrengths.add(segments[1].motionStrength as double);
        await _captureMigrationTransitionGolden(activeStatus, frameIndex++);
      }

      expect(confirmingMotionStrengths.first, 0);
      expect(confirmingMotionStrengths[1], allOf(greaterThan(0), lessThan(1)));
      expect(confirmingMotionStrengths.last, 1);
      expect(
        find.bySemanticsLabel(
          'Migration notes in expected processing order. '
          'Note 1: 0.2 ZEC, completed. '
          'Note 2: 0.3 ZEC, confirming. '
          'Note 3: 0.1 ZEC, scheduled.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('many tiny note segments render without overlap exceptions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final values = List<int>.generate(
      48,
      (index) => index == 0 ? 1_000_000_000 : 1_000_000 + index,
    );
    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'run-many',
          targetValuesZatoshi: values,
          totalCount: values.length,
          parts: [
            for (var index = values.length - 1; index >= 0; index--)
              _migrationPart(
                index,
                values[index],
                rust_sync.MigrationPartState.scheduled,
                scheduleOrder: index,
              ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final ringPaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ironwood_migration_ring_paint')),
    );
    final dynamic ringPainter = ringPaint.painter;
    final segments = (ringPainter.segments as List<dynamic>);
    final weights = [
      for (final dynamic segment in segments) segment.weight as double,
    ];
    expect(weights, hasLength(values.length));
    expect(
      weights.fold<double>(0, (sum, weight) => sum + weight),
      closeTo(1, 1e-12),
    );
    expect(weights.skip(1), everyElement(greaterThanOrEqualTo(0.0025 - 1e-12)));
    final scheduleButton = find.byKey(
      const ValueKey('ironwood_migration_view_schedule_button'),
    );
    final scheduleLabel = find.text('View Schedule');
    final dynamic scheduleParagraph = tester.renderObject(scheduleLabel);
    final buttonRect = tester.getRect(scheduleButton);
    final labelRect = tester.getRect(scheduleLabel);
    final expectedLabelHeight =
        AppTypography.labelLarge.fontSize! * AppTypography.labelLarge.height!;
    expect(scheduleParagraph.didExceedMaxLines, isFalse);
    expect(labelRect.height, greaterThanOrEqualTo(expectedLabelHeight));
    expect(buttonRect.contains(labelRect.topLeft), isTrue);
    expect(buttonRect.contains(labelRect.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scheduled ring segments use the theme positive token at 20%', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final status = _migrationStatus(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      activeRunId: 'run-themed-ring',
      targetValuesZatoshi: const [10_000_000],
      totalCount: 1,
      parts: [
        _migrationPart(0, 10_000_000, rust_sync.MigrationPartState.scheduled),
      ],
    );

    for (final theme in [AppThemeData.light, AppThemeData.dark]) {
      await tester.pumpWidget(
        _MutablePrivateStatusHarness(
          status: status,
          syncState: _syncedSyncState,
          disableAnimations: false,
          themeData: theme,
        ),
      );
      await tester.pumpAndSettle();

      final ringPaint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('ironwood_migration_ring_paint')),
      );
      final dynamic ringPainter = ringPaint.painter;
      final dynamic segment = (ringPainter.segments as List<dynamic>).single;
      expect(
        segment.color,
        theme.colors.text.positiveStrong.withValues(alpha: 0.20),
      );
      expect(segment.motion.toString(), contains('none'));
      expect(ringPainter.motionPhase, 0);
    }
  });

  testWidgets('in-flight ring uses one running shimmer clock', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationBroadcastingPhase,
          activeRunId: 'run-shimmer',
          targetValuesZatoshi: const [10_000_000, 20_000_000],
          totalCount: 2,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.migrating,
            ),
            _migrationPart(
              1,
              20_000_000,
              rust_sync.MigrationPartState.confirming,
            ),
          ],
        ),
        disableAnimations: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    dynamic painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('ironwood_migration_ring_paint')),
        )
        .painter;
    final initialPhase = painter.motionPhase as double;
    final segments = painter.segments as List<dynamic>;
    expect(segments, hasLength(2));
    expect(
      segments,
      everyElement(
        predicate<dynamic>((segment) {
          return segment.motion.toString().contains('shimmer') &&
              segment.motionStrength == 1;
        }),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('ironwood_migration_ring_paint')),
        )
        .painter;
    expect(painter.motionPhase as double, greaterThan(initialPhase));
  });

  testWidgets('reduced motion freezes in-flight ring at a static fallback', (
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
          activeRunId: 'run-reduced-motion',
          targetValuesZatoshi: const [10_000_000],
          totalCount: 1,
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.migrating,
            ),
          ],
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    dynamic painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('ironwood_migration_ring_paint')),
        )
        .painter;
    final initialPhase = painter.motionPhase as double;
    expect(painter.reduceMotion, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('ironwood_migration_ring_paint')),
        )
        .painter;
    expect(painter.motionPhase, initialPhase);
  });

  testWidgets('Keystone input segment uses inverse token and blink motion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _privateStatusHarness(
        status: _migrationStatus(
          phase: kIronwoodMigrationReadyToMigratePhase,
          activeRunId: 'run-keystone-blink',
          targetValuesZatoshi: const [10_000_000],
          totalCount: 1,
          currentSigningPartIndices: const [0],
          parts: [
            _migrationPart(
              0,
              10_000_000,
              rust_sync.MigrationPartState.scheduled,
            ),
          ],
        ),
        activeAccountIsHardware: true,
        disableAnimations: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final ringPaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ironwood_migration_ring_paint')),
    );
    final dynamic ringPainter = ringPaint.painter;
    final dynamic segment = (ringPainter.segments as List<dynamic>).single;
    expect(segment.color, AppThemeData.light.colors.background.inverse);
    expect(segment.motion.toString(), contains('blink'));
    expect(segment.motionStrength, 1);
    expect(ringPainter.reduceMotion, isTrue);
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
            currentSigningPartIndices: const [0],
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
    expect(find.text('Sign Batch #1'), findsOneWidget);
    expect(find.text('keystone-batch-sign-route'), findsNothing);

    await tester.tap(find.widgetWithText(AppButton, 'Sign Batch #1'));
    await tester.pumpAndSettle();

    expect(softwareContinued, isFalse);
    expect(find.text('keystone-batch-sign-route'), findsOneWidget);
  });

  testWidgets(
    'private status waits for anchor after the final Keystone batch is signed',
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
            targetValuesZatoshi: const [10_000_000],
            totalCount: 1,
            signedChildPcztCount: 1,
            proofReady: false,
            currentSigningPartIndices: const [],
            parts: [
              _migrationPart(
                0,
                10_000_000,
                rust_sync.MigrationPartState.preparing,
              ),
            ],
          ),
          activeAccountIsHardware: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Next migration'), findsOneWidget);
      expect(find.text('Schedule pending'), findsNWidgets(2));
      expect(find.textContaining('Sign Batch #'), findsNothing);
      expect(
        find.byKey(const ValueKey('ironwood_migration_status_action_button')),
        findsNothing,
      );
    },
  );

  testWidgets('preparation schedule shows split transaction details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final status = _migrationStatus(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      activeRunId: 'run-1',
      denominationConfirmationTarget: 3,
      denominationSplitCompletedCount: 1,
      denominationSplitTotalCount: 5,
      preparationMeanDelayBlocks: 24,
      preparationTransactions: [
        _preparationTransaction(
          0,
          500_000_000,
          rust_sync.MigrationPreparationTransactionState.completed,
          outputs: [
            rust_sync.MigrationPreparationOutputStatus(
              valueZatoshi: BigInt.from(400_000_000),
              kind: rust_sync.MigrationPreparationOutputKind.continuation,
              nextRound: 2,
            ),
            rust_sync.MigrationPreparationOutputStatus(
              valueZatoshi: BigInt.from(99_990_000),
              kind: rust_sync.MigrationPreparationOutputKind.change,
            ),
          ],
          scheduledHeight: 980,
          minedHeight: 984,
          confirmationCount: 3,
        ),
        _preparationTransaction(
          1,
          400_000_000,
          rust_sync.MigrationPreparationTransactionState.confirming,
          scheduledHeight: 990,
          minedHeight: 999,
          confirmationCount: 2,
        ),
        _preparationTransaction(
          2,
          300_000_000,
          rust_sync.MigrationPreparationTransactionState.broadcasted,
          scheduledHeight: 1_144,
        ),
        _preparationTransaction(
          3,
          200_000_000,
          rust_sync.MigrationPreparationTransactionState.scheduled,
          scheduledHeight: 1_010,
        ),
        _preparationTransaction(
          4,
          100_000_000,
          rust_sync.MigrationPreparationTransactionState.awaitingInputs,
          round: 2,
          plannedHeight: 1_171,
          projectedHeight: 1_171,
          projectedCompletionHeight: 1_174,
        ),
      ],
    );
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'test',
          accountUuid: 'account-1',
          status: status,
        ),
        initialLocation: '/migration/private/preparation-schedule',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 1_000,
          chainTipHeight: 1_000,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparation Schedule'), findsOneWidget);
    expect(find.text('Current round'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Ready to migrate'), findsOneWidget);
    expect(find.text('Current block'), findsOneWidget);
    expect(find.text('1,000'), findsOneWidget);
    expect(find.text('#1,010'), findsOneWidget);
    expect(find.text('Expected by #1,171'), findsOneWidget);
    expect(find.text('Expected #1,171'), findsOneWidget);
    expect(find.text('3. 2 ZEC'), findsOneWidget);
    expect(find.text('4. 3 ZEC'), findsOneWidget);
    expect(find.text('Used in round 2'), findsOneWidget);
    expect(find.text('Stays in Orchard'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'Outputs: 4 ZEC, used in round 2; .* ZEC, stays in Orchard'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _privateStatusHarness(
        status: status,
        coordinatorStatus: status,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 1_000,
          chainTipHeight: 1_000,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Split 3 of 5'), findsOneWidget);
  });

  testWidgets('preparation ETA starts unscheduled delays at current height', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final status = _migrationStatus(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      activeRunId: 'run-1',
      denominationConfirmationTarget: 3,
      denominationSplitCompletedCount: 1,
      denominationSplitTotalCount: 2,
      preparationMeanDelayBlocks: 24,
      preparationTransactions: [
        _preparationTransaction(
          0,
          500_000_000,
          rust_sync.MigrationPreparationTransactionState.completed,
          scheduledHeight: 900,
          minedHeight: 904,
          confirmationCount: 3,
        ),
        _preparationTransaction(
          1,
          400_000_000,
          rust_sync.MigrationPreparationTransactionState.awaitingInputs,
          round: 2,
          plannedHeight: 1_024,
          projectedHeight: 1_024,
          projectedCompletionHeight: 1_027,
        ),
      ],
    );
    await tester.pumpWidget(
      _privateStatusHarness(
        status: status,
        coordinatorStatus: status,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 1_000,
          chainTipHeight: 1_000,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('~34 mins'), findsOneWidget);
    expect(find.text('~2 mins'), findsNothing);
  });

  testWidgets(
    'preparation schedule hides an overdue awaiting-input projection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final status = _migrationStatus(
        phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        activeRunId: 'run-1',
        denominationConfirmationTarget: 3,
        denominationSplitTotalCount: 1,
        preparationTransactions: [
          _preparationTransaction(
            0,
            400_000_000,
            rust_sync.MigrationPreparationTransactionState.awaitingInputs,
            plannedHeight: 990,
            projectedHeight: 990,
            projectedCompletionHeight: 993,
          ),
        ],
      );
      await tester.pumpWidget(
        _migrationEntryHarness(
          ctaState: IronwoodHomeMigrationCtaState.resume(
            network: 'test',
            accountUuid: 'account-1',
            status: status,
          ),
          initialLocation: '/migration/private/preparation-schedule',
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 1_000,
            chainTipHeight: 1_000,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready to migrate'), findsOneWidget);
      expect(find.text('Calculating'), findsOneWidget);
      expect(find.text('Recalculating'), findsOneWidget);
    },
  );

  testWidgets(
    'preparation ETA includes confirmation depth between dependent splits',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final status = _migrationStatus(
        phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        activeRunId: 'run-1',
        denominationConfirmationTarget: 3,
        denominationSplitCompletedCount: 1,
        denominationSplitTotalCount: 3,
        preparationMeanDelayBlocks: 4,
        preparationTransactions: [
          _preparationTransaction(
            0,
            500_000_000,
            rust_sync.MigrationPreparationTransactionState.completed,
            scheduledHeight: 900,
            minedHeight: 904,
            confirmationCount: 3,
          ),
          _preparationTransaction(
            1,
            400_000_000,
            rust_sync.MigrationPreparationTransactionState.awaitingInputs,
            round: 2,
            plannedHeight: 1_004,
            projectedHeight: 1_004,
            projectedCompletionHeight: 1_007,
          ),
          _preparationTransaction(
            2,
            300_000_000,
            rust_sync.MigrationPreparationTransactionState.awaitingInputs,
            round: 3,
            plannedHeight: 1_011,
            projectedHeight: 1_011,
            projectedCompletionHeight: 1_014,
          ),
        ],
      );
      await tester.pumpWidget(
        _privateStatusHarness(
          status: status,
          coordinatorStatus: status,
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 1_000,
            chainTipHeight: 1_000,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('~18 mins'), findsOneWidget);
      expect(find.text('~14 mins'), findsNothing);
    },
  );

  testWidgets('migration schedule retries after status lookup fails', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var failStatus = true;
    var callCount = 0;
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
        initialLocation: '/migration/private/schedule',
        statusGetter:
            ({required dbPath, required network, required accountUuid}) async {
              callCount += 1;
              if (failStatus) throw Exception('status unavailable');
              return _migrationStatus(
                phase: kIronwoodMigrationReadyToMigratePhase,
                activeRunId: 'run-1',
                targetValuesZatoshi: const [10_000_000],
                totalCount: 1,
                parts: [
                  _migrationPart(
                    0,
                    10_000_000,
                    rust_sync.MigrationPartState.scheduled,
                  ),
                ],
              );
            },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration schedule unavailable'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Retry'), findsOneWidget);

    failStatus = false;
    await tester.tap(find.widgetWithText(AppButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(callCount, greaterThanOrEqualTo(2));
    expect(find.text('Migration Schedule'), findsOneWidget);
    expect(find.text('Migration schedule unavailable'), findsNothing);
  });

  testWidgets('migration schedule keeps cached state when refresh fails', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cachedStatus = _migrationStatus(
      phase: kIronwoodMigrationReadyToMigratePhase,
      activeRunId: 'run-1',
      targetValuesZatoshi: const [10_000_000],
      totalCount: 1,
      parts: [
        _migrationPart(0, 10_000_000, rust_sync.MigrationPartState.scheduled),
      ],
    );
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: cachedStatus,
        ),
        initialLocation: '/migration/private/schedule',
        statusGetter:
            ({required dbPath, required network, required accountUuid}) =>
                Future.error(Exception('database is locked')),
        coordinatorStatus: cachedStatus,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Migration Schedule'), findsOneWidget);
    expect(find.text('Migration schedule unavailable'), findsNothing);
  });

  testWidgets(
    'migration schedule uses the authoritative anchor-aware completion height',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final status = _migrationStatus(
        phase: kIronwoodMigrationReadyToMigratePhase,
        activeRunId: 'run-1',
        targetValuesZatoshi: const [10_000_000],
        totalCount: 1,
        denominationConfirmationTarget: 3,
        nextActionHeight: 1_015,
        estimatedCompletionHeight: 1_120,
        proofReady: false,
        parts: [
          _migrationPart(
            0,
            10_000_000,
            rust_sync.MigrationPartState.preparing,
            scheduledHeight: 1_117,
          ),
        ],
      );
      await tester.pumpWidget(
        _migrationEntryHarness(
          ctaState: IronwoodHomeMigrationCtaState.resume(
            network: 'test',
            accountUuid: 'account-1',
            status: status,
          ),
          initialLocation: '/migration/private/schedule',
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 1_000,
            chainTipHeight: 1_000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('in ~2.5 hours'), findsOneWidget);
      expect(find.text('~4 mins'), findsNothing);
    },
  );

  testWidgets('migration schedule shows block heights and per-note states', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final status = _migrationStatus(
      phase: kIronwoodMigrationWaitingConfirmationsPhase,
      activeRunId: 'run-1',
      targetValuesZatoshi: const [10_000_000, 20_000_000, 30_000_000],
      totalCount: 3,
      estimatedCompletionHeight: 1_040,
      parts: [
        _migrationPart(
          0,
          10_000_000,
          rust_sync.MigrationPartState.completed,
          scheduledHeight: 1_010,
          confirmationCount: 3,
        ),
        _migrationPart(
          1,
          20_000_000,
          rust_sync.MigrationPartState.confirming,
          scheduledHeight: 1_020,
          confirmationCount: 1,
        ),
        _migrationPart(
          2,
          30_000_000,
          rust_sync.MigrationPartState.scheduled,
          scheduledHeight: 1_030,
        ),
      ],
    );
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'test',
          accountUuid: 'account-1',
          status: status,
        ),
        initialLocation: '/migration/private/schedule',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 1_000,
          chainTipHeight: 1_000,
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Left to migrate'), findsOneWidget);
    expect(find.text('0.5 ZEC'), findsOneWidget);
    expect(find.text('in ~50 minutes'), findsOneWidget);
    expect(find.text('1,010'), findsOneWidget);
    expect(find.text('1,020'), findsOneWidget);
    expect(find.text('1,030'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    expect(find.text('Scheduled'), findsNothing);
    expect(
      find.bySemanticsLabel('Note 1, 0.1 ZEC, block 1,010, completed.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Note 2, 0.2 ZEC, block 1,020, confirming, '
        '1 of 3 confirmations.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Note 3, 0.3 ZEC, block 1,030, scheduled.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'migration schedule does not invent a short ETA without a projection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final status = _migrationStatus(
        phase: kIronwoodMigrationReadyToMigratePhase,
        activeRunId: 'run-1',
        targetValuesZatoshi: const [10_000_000],
        totalCount: 1,
        denominationConfirmationTarget: 3,
        estimatedCompletionHeight: 1_120,
        proofReady: false,
        parts: [
          _migrationPart(0, 10_000_000, rust_sync.MigrationPartState.preparing),
        ],
      );
      await tester.pumpWidget(
        _migrationEntryHarness(
          ctaState: IronwoodHomeMigrationCtaState.resume(
            network: 'test',
            accountUuid: 'account-1',
            status: status,
          ),
          initialLocation: '/migration/private/schedule',
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 1_000,
            chainTipHeight: 1_000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Schedule pending'), findsOneWidget);
      expect(find.text('~4 mins'), findsNothing);
    },
  );

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
    expect(find.text('Ironwood Migration'), findsOneWidget);
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
  bool useImmediatePreview = true,
  rust_sync.KeystoneMigrationSigningRequest? previewCombinedSigningRequest,
  List<String> previewCombinedSigningUrParts = const [],
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/migration/what-to-expect',
        builder: (_, _) => IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.whatToExpect,
          previewData: IronwoodMigrationFlowData(
            amountZatoshi: BigInt.from(10_000_000),
            accountName: 'Account 1',
            profilePictureId: kDefaultProfilePictureId,
          ),
        ),
      ),
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
        path: '/migration/immediate/review',
        builder: (_, _) => IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.immediateReview,
          previewData: IronwoodMigrationFlowData(
            amountZatoshi: BigInt.from(10_000_000),
            accountName: 'Account 1',
            profilePictureId: kDefaultProfilePictureId,
          ),
          previewImmediatePlan: useImmediatePreview ? _immediatePlan() : null,
        ),
      ),
      GoRoute(
        path: '/migration/immediate/keystone/sign',
        builder: (_, state) {
          final plan = state.extra! as rust_sync.OrchardMigrationImmediatePlan;
          return Text('keystone-immediate-sign-route:${plan.migratedZatoshi}');
        },
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => realStatusRoute
            ? const IronwoodMigrationPrivateStatusScreen()
            : IronwoodMigrationPrivateStatusScreen(previewStatus: _status()),
      ),
      GoRoute(
        path: '/migration/private/keystone/sign',
        builder: (_, state) {
          final previewRequest = previewCombinedSigningRequest;
          if (previewRequest != null) {
            return IronwoodMigrationKeystoneCombinedSignScreen(
              approvedSchedule: const [],
              previewRequest: previewRequest,
              previewUrParts: previewCombinedSigningUrParts,
            );
          }
          final schedule =
              state.extra! as List<rust_sync.MigrationScheduledTransfer>;
          return Text(
            'keystone-combined-sign-route:${schedule.length}:'
            '${schedule.first.blockOffset}',
          );
        },
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
  Future<void> retry(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) async {
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

Future<void> _captureMigrationTransitionGolden(
  Finder statusContent,
  int frameIndex,
) async {
  const capture = bool.fromEnvironment(
    'VIZOR_CAPTURE_MIGRATION_TRANSITION',
    defaultValue: false,
  );
  if (!capture) return;
  await expectLater(
    statusContent,
    matchesGoldenFile(
      'migration_transition/frame-${frameIndex.toString().padLeft(2, '0')}.png',
    ),
  );
}

class _MutablePrivateStatusHarness extends StatefulWidget {
  const _MutablePrivateStatusHarness({
    super.key,
    required this.status,
    required this.syncState,
    this.coordinatorAdvancing = false,
    this.disableAnimations = true,
    this.themeData = AppThemeData.light,
  });

  final rust_sync.MigrationStatus status;
  final SyncState syncState;
  final bool coordinatorAdvancing;
  final bool disableAnimations;
  final AppThemeData themeData;

  @override
  State<_MutablePrivateStatusHarness> createState() =>
      _MutablePrivateStatusHarnessState();
}

class _MutablePrivateStatusHarnessState
    extends State<_MutablePrivateStatusHarness> {
  final _scopeKey = GlobalKey();
  late final ValueNotifier<rust_sync.MigrationStatus> _statusNotifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _statusNotifier = ValueNotifier(widget.status);
    _router = GoRouter(
      initialLocation: '/migration/private/status',
      routes: [
        GoRoute(
          path: '/migration/private/status',
          builder: (_, _) => ValueListenableBuilder(
            valueListenable: _statusNotifier,
            builder: (_, status, _) =>
                IronwoodMigrationPrivateStatusScreen(previewStatus: status),
          ),
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
  }

  ProviderContainer get _container =>
      ProviderScope.containerOf(_scopeKey.currentContext!, listen: false);

  void setStatus(rust_sync.MigrationStatus status) {
    _statusNotifier.value = status;
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
  void dispose() {
    _router.dispose();
    _statusNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          routerConfig: _router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: widget.disableAnimations,
              textScaler: TextScaler.noScaling,
            ),
            child: AppTheme(data: widget.themeData, child: child!),
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
  bool disableAnimations = false,
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
    disableAnimations: disableAnimations,
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
  bool disableAnimations = false,
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
        path: '/migration/private/schedule',
        builder: (_, _) => const IronwoodMigrationScheduleScreen(),
      ),
      GoRoute(
        path: '/migration/private/preparation-schedule',
        builder: (_, _) => const IronwoodMigrationPreparationScheduleScreen(),
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
    denominationSplitLayerCount: 0,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    proofReadinessDelayBlocks: 146,
    scheduledTransfers: [
      rust_sync.MigrationScheduledTransfer(
        partIndex: 0,
        valueZatoshi: BigInt.from(10_000_000),
        blockOffset: 144,
      ),
    ],
  );
}

rust_sync.OrchardMigrationImmediatePlan _immediatePlan() {
  return rust_sync.OrchardMigrationImmediatePlan(
    totalInputZatoshi: BigInt.from(10_000_000),
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(9_990_000),
    inputNoteCount: 1,
  );
}

IronwoodMigrationService _immediatePlanService(
  Future<rust_sync.OrchardMigrationImmediatePlan?> Function() getPlan,
) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            _migrationStatus(),
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            _privatePlan(),
    getImmediatePlan:
        ({required dbPath, required network, required accountUuid}) =>
            getPlan(),
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
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
  int signedChildPcztCount = 0,
  int? nextActionHeight,
  int? nextProofWindowHeight,
  List<int>? nextProofWindowPartIndices,
  int? estimatedCompletionHeight,
  int? preparationMeanDelayBlocks,
  bool? proofReady,
  List<int>? currentSigningPartIndices,
  List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts = const [],
  List<rust_sync.MigrationPreparationTransactionStatus>
      preparationTransactions =
      const [],
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
    signedChildPcztCount: signedChildPcztCount,
    pendingSplitStageCount: pendingSplitStageCount,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    nextActionHeight: nextActionHeight,
    nextProofWindowHeight: nextProofWindowHeight,
    nextProofWindowPartIndices: nextProofWindowPartIndices == null
        ? null
        : frb.Uint32List.fromList(nextProofWindowPartIndices),
    estimatedCompletionHeight: estimatedCompletionHeight,
    preparationMeanDelayBlocks: preparationMeanDelayBlocks,
    proofReady: proofReady,
    currentSigningPartIndices: currentSigningPartIndices == null
        ? null
        : frb.Uint32List.fromList(currentSigningPartIndices),
    scheduledBroadcasts: scheduledBroadcasts,
    preparationTransactions: preparationTransactions,
    parts: parts,
  );
}

rust_sync.MigrationPartStatus _migrationPart(
  int partIndex,
  int valueZatoshi,
  rust_sync.MigrationPartState state, {
  int? scheduleOrder,
  int confirmationCount = 0,
  int confirmationTarget = 3,
  int? scheduleStartHeight,
  int? scheduledHeight,
}) => rust_sync.MigrationPartStatus(
  partIndex: partIndex,
  scheduleOrder: scheduleOrder,
  valueZatoshi: BigInt.from(valueZatoshi),
  state: state,
  scheduleStartHeight: scheduleStartHeight,
  scheduledHeight: scheduledHeight,
  confirmationCount: confirmationCount,
  confirmationTarget: confirmationTarget,
);

rust_sync.MigrationPreparationTransactionStatus _preparationTransaction(
  int stageIndex,
  int approximateValueZatoshi,
  rust_sync.MigrationPreparationTransactionState state, {
  int round = 1,
  int feeZatoshi = 10_000,
  int? plannedHeight,
  int? projectedHeight,
  int? projectedCompletionHeight,
  List<rust_sync.MigrationPreparationOutputStatus> outputs = const [],
  int? scheduledHeight,
  int? minedHeight,
  int confirmationCount = 0,
  int confirmationTarget = 3,
}) => rust_sync.MigrationPreparationTransactionStatus(
  stageIndex: stageIndex,
  approximateValueZatoshi: BigInt.from(approximateValueZatoshi),
  round: round,
  feeZatoshi: BigInt.from(feeZatoshi),
  plannedHeight: plannedHeight ?? scheduledHeight ?? 0,
  projectedHeight: projectedHeight ?? scheduledHeight ?? 0,
  projectedCompletionHeight:
      projectedCompletionHeight ??
      (minedHeight ?? projectedHeight ?? scheduledHeight ?? 0) +
          confirmationTarget,
  outputs: outputs,
  state: state,
  scheduledHeight: scheduledHeight,
  minedHeight: minedHeight,
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
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
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
