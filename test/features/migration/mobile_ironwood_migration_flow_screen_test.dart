@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart'
    as rust_keystone_wallet;

import '../../fakes/fake_sync_notifier.dart';

class _RustApiFake implements RustLibApi {
  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  Future<List<String>> crateApiKeystoneEncodeZcashSignBatchUrParts({
    required String requestId,
    required List<rust_keystone_wallet.ZcashBatchMessageInput> messages,
    required BigInt maxFragmentLen,
  }) async => ['UR:ZCASH-SIGN-BATCH/$requestId'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _data = IronwoodMigrationFlowData(
  amountZatoshi: BigInt.from(14_223_000_000),
  accountName: 'Wallet 1',
  profilePictureId: 'default',
);

rust_sync.OrchardMigrationPrivatePlan _planWith({
  int plannedBatchCount = 12,
  int denominationSplitStageCount = 1,
  int signingBatchLimit = 12,
}) => rust_sync.OrchardMigrationPrivatePlan(
  targetValuesZatoshi: frb.Uint64List.fromList([]),
  totalInputZatoshi: BigInt.from(14_223_000_000),
  totalMigratableZatoshi: BigInt.from(14_220_000_000),
  orchardChangeZatoshi: BigInt.from(90_000),
  denominationSplitFeeZatoshi: BigInt.from(20_000),
  migrationFeeZatoshi: BigInt.from(14_400_000),
  estimatedTotalFeeZatoshi: BigInt.from(14_420_000),
  plannedBatchCount: plannedBatchCount,
  denominationSplitStageCount: denominationSplitStageCount,
  signingBatchLimit: signingBatchLimit,
  scheduleMeanDelayBlocks: 144,
  scheduleMaxDelayBlocks: 576,
  maxPreparedNotesPerRun: 12,
  scheduledTransfers: [
    for (var i = 0; i < plannedBatchCount; i++)
      rust_sync.MigrationScheduledTransfer(
        partIndex: i,
        valueZatoshi: BigInt.from(
          i == plannedBatchCount - 1 ? 3_220_000_000 : 1_000_000_000,
        ),
        blockOffset: (i + 1) * 144,
      ),
  ],
);

rust_sync.OrchardMigrationPrivatePlan get _plan => _planWith();

rust_sync.MigrationStatus _status({
  required String phase,
  String? activeRunId = 'run-1',
  List<String>? broadcastStatuses,
  List<rust_sync.MigrationPartStatus> parts = const [],
  List<int> targetValues = const [412_000_000, 412_000_000, 412_000_000],
  int? nextActionHeight,
  int? estimatedCompletionHeight,
  int? nextActionPartIndex,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList(targetValues),
    preparedNoteCount: 3,
    denominationConfirmationCount: 2,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 3,
    pendingTxCount: 2,
    broadcastedTxCount: 1,
    confirmedTxCount: 1,
    totalCount: 3,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 2,
    canAbandon: false,
    signingBatchLimit: 12,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 12,
    nextActionHeight: nextActionHeight,
    estimatedCompletionHeight: estimatedCompletionHeight,
    nextActionPartIndex: nextActionPartIndex,
    scheduledBroadcasts: broadcastStatuses == null
        ? const []
        : [
            for (var index = 0; index < broadcastStatuses.length; index++)
              rust_sync.MigrationScheduledBroadcast(
                txidHex: 'tx-$index',
                valueZatoshi: BigInt.from(412_000_000),
                scheduledAtMs: DateTime(2026, 7, 20, 10).millisecondsSinceEpoch,
                scheduledHeight: 3_000_000 + index,
                status: broadcastStatuses[index],
              ),
          ],
    parts: parts,
  );
}

rust_sync.MigrationStatus _visualMigrationStatus() {
  final scheduledAt = DateTime(2026, 7, 18, 12).millisecondsSinceEpoch;
  const values = [
    412_000_000,
    412_000_000,
    412_000_000,
    412_000_000,
    412_000_000,
    412_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    1_876_000_000,
  ];
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'visual-run',
    targetValuesZatoshi: frb.Uint64List.fromList(values),
    preparedNoteCount: 12,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 9,
    broadcastedTxCount: 3,
    confirmedTxCount: 3,
    totalCount: 12,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 12,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 12,
    scheduledBroadcasts: [
      for (var i = 0; i < values.length; i++)
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'visual-$i',
          valueZatoshi: BigInt.from(values[i]),
          scheduledAtMs: scheduledAt,
          scheduledHeight: 3_000_000 + (i + 1) * 144,
          status: switch (i) {
            0 => 'confirmed',
            1 => 'needs_input',
            2 => 'broadcasted',
            _ => 'scheduled',
          },
        ),
    ],
    parts: const [],
  );
}

AppBootstrapState _bootstrap({bool hardware = false}) => AppBootstrapState(
  initialLocation: '/migration/private/review',
  initialAccountState: AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Wallet 1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
        isHardware: hardware,
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

Widget _app({
  required MobileIronwoodMigrationStep step,
  AppThemeData theme = AppThemeData.light,
  rust_sync.MigrationStatus? previewStatus,
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
  MobileIronwoodMigrationReviewPreviewStage previewReviewStage =
      MobileIronwoodMigrationReviewPreviewStage.review,
  bool disableAnimations = true,
}) {
  late final GoRouter router;
  MobileIronwoodMigrationFlowScreen screen(MobileIronwoodMigrationStep value) {
    return MobileIronwoodMigrationFlowScreen(
      step: value,
      previewData: _data,
      previewPrivatePlan: previewPlan ?? _plan,
      previewStatus: previewStatus,
      previewReviewStage: previewReviewStage,
    );
  }

  router = GoRouter(
    initialLocation: switch (step) {
      MobileIronwoodMigrationStep.intro => '/migration/intro',
      MobileIronwoodMigrationStep.howItWorks => '/migration/how-it-works',
      MobileIronwoodMigrationStep.options => '/migration/options',
      MobileIronwoodMigrationStep.privateReview => '/migration/private/review',
      MobileIronwoodMigrationStep.fastReview => '/migration/fast/review',
      MobileIronwoodMigrationStep.preparing => '/migration/private/preparing',
      MobileIronwoodMigrationStep.migrating => '/migration/private/status',
    },
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.intro),
      ),
      GoRoute(
        path: '/migration/how-it-works',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.howItWorks),
      ),
      GoRoute(
        path: '/migration/options',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.options),
      ),
      GoRoute(
        path: '/migration/private/review',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.privateReview),
      ),
      GoRoute(
        path: '/migration/fast/review',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.fastReview),
      ),
      GoRoute(
        path: '/migration/private/preparing',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.preparing),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.migrating),
      ),
    ],
  );

  return ProviderScope(
    child: AppTheme(
      data: theme,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
    ),
  );
}

Widget _productionApp({
  required String initialLocation,
  required IronwoodMigrationService migrationService,
  rust_sync.MigrationStatus? status,
  rust_sync.MigrationStatus? startedStatus,
  IronwoodHomeMigrationCtaState Function()? ctaBuilder,
  bool hardware = false,
  rust_sync.OrchardMigrationPrivatePlan? privatePlan,
  Future<rust_sync.OrchardMigrationPrivatePlan?>? privatePlanFuture,
  Future<rust_sync.OrchardMigrationPrivatePlan?> Function()? privatePlanLoader,
  SyncState? syncState,
  bool disableAnimations = true,
}) {
  final cta = status == null
      ? const IronwoodHomeMigrationCtaState.start(
          network: 'main',
          accountUuid: 'account-1',
        )
      : IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: status,
        );
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => const Text('intro route'),
      ),
      GoRoute(
        path: '/migration/private/review',
        builder: (_, _) => const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.privateReview,
        ),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => const MobileIronwoodMigrationPrivateStatusScreen(),
      ),
      GoRoute(
        path: '/migration/private/keystone/denominations/sign',
        builder: (_, _) => const Text('keystone denomination sign route'),
      ),
      GoRoute(
        path: '/migration/private/keystone/batch/sign',
        builder: (_, _) => const Text('keystone batch sign route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(hardware: hardware)),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          syncState ??
              SyncState(
                accountUuid: 'account-1',
                hasAccountScopedData: true,
                isSyncComplete: true,
              ),
        ),
      ),
      ironwoodMigrationFlowDataProvider.overrideWith((ref) => _data),
      ironwoodMigrationPrivatePlanProvider.overrideWith(
        (ref) =>
            privatePlanLoader?.call() ??
            privatePlanFuture ??
            Future.value(privatePlan ?? _plan),
      ),
      ironwoodMigrationRouteCtaProvider.overrideWith(
        (ref) async => ctaBuilder?.call() ?? cta,
      ),
      ironwoodMigrationStatusProvider.overrideWith(
        (ref, request) async =>
            startedStatus ??
            status ??
            _status(phase: kIronwoodMigrationWaitingDenomConfirmationsPhase),
      ),
      ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
    ],
    child: AppTheme(
      data: AppThemeData.light,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
    ),
  );
}

IronwoodMigrationService _migrationService({
  Future<rust_sync.IronwoodMigrationResult> Function(
    String accountUuid,
    List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  )?
  onStart,
  Future<rust_sync.IronwoodMigrationResult> Function(String accountUuid)?
  onContinue,
  Future<rust_sync.IronwoodMigrationResult> Function(String accountUuid)?
  onSendOne,
  Future<bool> Function()? onRetryInBackground,
  bool supportsBackgroundMigration = true,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            _status(phase: kIronwoodMigrationWaitingDenomConfirmationsPhase),
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            _plan,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => defaultRpcEndpointConfig('main'),
    getSessionPassword: () => 'test-password',
    getMnemonicBytesForAccount: (_) async => [1, 2, 3],
    isMacOS: () => false,
    isMobile: () => true,
    supportsBackgroundMigration: () => supportsBackgroundMigration,
    startSoftwareMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required mnemonicBytes,
          required password,
          required saltBase64,
          required approvedSchedule,
        }) =>
            onStart?.call(accountUuid, approvedSchedule) ??
            Future.value(_migrationResult()),
    broadcastDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) => onContinue?.call(accountUuid) ?? Future.value(_migrationResult()),
    broadcastOneDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) => onSendOne?.call(accountUuid) ?? Future.value(_migrationResult()),
    scheduleBackgroundMigration: onRetryInBackground ?? () async => true,
  );
}

rust_sync.IronwoodMigrationResult _migrationResult() {
  return rust_sync.IronwoodMigrationResult(
    txids: 'txid',
    status: 'broadcasted',
    broadcastedCount: 1,
    totalCount: 3,
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(4_120_000_000),
  );
}

void _useMobileViewport(
  WidgetTester tester, {
  Size size = const Size(393, 852),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('connects the About and migration-steps screens', (tester) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.intro));
    await tester.pumpAndSettle();

    expect(find.text('Zcash Network Update'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_wordmark')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_ironwood_legacy_connection_dot')),
      ),
      const Size.square(16),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_ironwood_target_connection_dot')),
      ),
      const Size.square(16),
    );
    final profilePictures = find.byType(AppProfilePicture);
    expect(profilePictures, findsNWidgets(2));
    expect(
      tester
              .getCenter(
                find.byKey(
                  const ValueKey('mobile_ironwood_legacy_connection_dot'),
                ),
              )
              .dy -
          tester.getCenter(profilePictures.first).dy,
      5,
    );
    expect(
      tester
              .getCenter(
                find.byKey(
                  const ValueKey('mobile_ironwood_target_connection_dot'),
                ),
              )
              .dy -
          tester.getCenter(profilePictures.last).dy,
      5,
    );
    expect(find.text('A new shielded pool for Zcash.'), findsOneWidget);
    expect(find.text('Official release note'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('How Migration Works'), findsOneWidget);
    expect(find.textContaining('Choose how you migrate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_step_1')),
      findsOneWidget,
    );
    expect(find.textContaining('Prepare your balance'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_step_2')),
      findsOneWidget,
    );
    expect(find.textContaining('Move to Ironwood'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_step_3')),
      findsOneWidget,
    );
    expect(find.text('Spend as funds arrive'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('Choose how you migrate'))
          .style
          ?.fontWeight,
      FontWeight.w500,
    );
    expect(tester.widget<Text>(find.text('1')).style?.fontSize, 16);
    expect(
      tester.widget<Text>(find.text('1')).style?.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('shows the migration type choice and preview selection', (
    tester,
  ) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.options));
    await tester.pumpAndSettle();

    expect(find.text('Choose How to Migrate'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_recommended_badge')),
      findsOneWidget,
    );
    expect(find.text('Sends independent parts over time'), findsOneWidget);
    expect(find.text('Immediate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_immediate_unavailable')),
      findsOneWidget,
    );
    expect(find.text('Sends now in one step.'), findsOneWidget);
    expect(find.text('Customise'), findsNothing);
    expect(find.text('Advanced'), findsNothing);

    final subtitle = tester.widget<Text>(
      find.text(
        'Choose between more privacy over time or a faster migration. '
        'You can review the details before anything moves.',
      ),
    );
    expect(subtitle.textAlign, TextAlign.center);
    expect(
      tester.widget<Text>(find.text('Immediate')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester
          .widget<Text>(find.text('Sends now in one step.'))
          .style
          ?.fontWeight,
      FontWeight.w500,
    );
    final immediateIconOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('mobile_ironwood_immediate_icon')),
        matching: find.byType(Opacity),
      ),
    );
    expect(immediateIconOpacity.opacity, 0.5);
    expect(
      (tester
                  .widget<DecoratedBox>(
                    find.byKey(
                      const ValueKey('mobile_ironwood_recommended_badge'),
                    ),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      const Color(0xFF00A460),
    );

    final unselectedRadio = tester.widget<Container>(
      find.byKey(const ValueKey('mobile_ironwood_unselected_radio')),
    );
    expect(
      (unselectedRadio.decoration! as BoxDecoration).color,
      const Color(0x33B8B8B8),
    );

    final privateOption = find.byKey(
      const ValueKey('mobile_ironwood_private_option'),
    );
    final immediateOption = find.byKey(
      const ValueKey('mobile_ironwood_immediate_unavailable'),
    );
    await tester.tap(immediateOption);
    await tester.pump();
    expect(
      find.descendant(
        of: immediateOption,
        matching: find.byKey(const ValueKey('mobile_ironwood_selected_radio')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: privateOption,
        matching: find.byKey(
          const ValueKey('mobile_ironwood_unselected_radio'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(privateOption);
    await tester.pump();
    expect(
      find.descendant(
        of: privateOption,
        matching: find.byKey(const ValueKey('mobile_ironwood_selected_radio')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review Migration Plan'), findsOneWidget);
  });

  testWidgets('renders the private migration review plan', (tester) async {
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.privateReview),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Migration 12 notes'), findsOneWidget);
    expect(find.text('142.20 ZEC'), findsOneWidget);
    expect(find.text('Est. completion'), findsOneWidget);
    final completionText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_review_value_Est. completion'),
        ),
        matching: find.byType(Text),
      ),
    );
    expect(
      completionText.data,
      matches(RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{2}:\d{2}$')),
    );
    expect(completionText.data, isNot(contains('blocks')));
    expect(find.text('Fees (estimate)'), findsOneWidget);
    expect(find.text('0.1442 ZEC'), findsOneWidget);
    expect(find.text('Start migration'), findsOneWidget);
  });

  testWidgets('scrolls migration parts only when the review overflows', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewPlan: _planWith(plannedBatchCount: 6),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('Review Migration Plan')).dx,
      closeTo(393 / 2, 0.5),
    );
    final labelCell = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_part_label_cell_0')),
    );
    final valueCell = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_part_value_cell_0')),
    );
    final statusCell = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_part_status_cell_0')),
    );
    expect(labelCell.left, 16);
    expect(labelCell.width, 70);
    expect(labelCell.height, 24);
    expect(valueCell.left, closeTo(101.5, 0.5));
    expect(valueCell.width, 130);
    expect(statusCell.right, 377);
    expect(statusCell.width, 130);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('mobile_ironwood_part_bar_5')))
          .right,
      closeTo(377, 0.5),
    );
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey('mobile_ironwood_review_value_Est. completion'),
            ),
          )
          .right,
      373,
    );

    var partListPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(partListPosition.maxScrollExtent, 0);
    var railPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_bar_scroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(railPosition.maxScrollExtent, 0);

    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewPlan: _planWith(plannedBatchCount: 50, signingBatchLimit: 50),
      ),
    );
    await tester.pumpAndSettle();

    partListPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(partListPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('mobile_ironwood_part_list')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(partListPosition.pixels, greaterThan(0));
    railPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_bar_scroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(railPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('mobile_ironwood_part_bar_scroll')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(railPosition.pixels, greaterThan(0));
  });

  testWidgets('splits the analysis bar before staggering the part rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final firstBar = find.byKey(const ValueKey('mobile_ironwood_part_bar_0'));
    final lastBar = find.byKey(const ValueKey('mobile_ironwood_part_bar_11'));
    final firstRow = find.byKey(
      const ValueKey('mobile_ironwood_part_row_reveal_0'),
    );
    final lastVisibleRow = find.byKey(
      const ValueKey('mobile_ironwood_part_row_reveal_1'),
    );
    final singleTrack = find.byKey(
      const ValueKey('mobile_ironwood_part_bar_single_track'),
    );

    final initialBarSpan =
        tester.getRect(lastBar).right - tester.getRect(firstBar).left;
    expect(initialBarSpan, closeTo(196, 0.5));
    expect(tester.widget<Opacity>(singleTrack).opacity, 1);
    expect(tester.widget<FadeTransition>(firstRow).opacity.value, 0);

    await tester.pump(const Duration(milliseconds: 1200));

    final splitBarSpan =
        tester.getRect(lastBar).right - tester.getRect(firstBar).left;
    expect(splitBarSpan, greaterThan(initialBarSpan));
    expect(tester.widget<Opacity>(singleTrack).opacity, 0);
    expect(tester.widget<FadeTransition>(firstRow).opacity.value, 0);

    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<FadeTransition>(firstRow).opacity.value,
      greaterThan(tester.widget<FadeTransition>(lastVisibleRow).opacity.value),
    );

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.widget<FadeTransition>(lastVisibleRow).opacity.value, 1);
  });

  testWidgets('holds the analyzing preview at the Figma progress value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewReviewStage: MobileIronwoodMigrationReviewPreviewStage.analyzing,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsOneWidget,
    );
    final progress = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress'),
        ),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(progress.widthFactor, closeTo(72 / 196, 0.001));
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress_fill'),
        ),
      ),
      const Size(72, 12),
    );
    expect(find.text('Analyzing your balance...'), findsOneWidget);
  });

  testWidgets('advances the animated analyzing preview over time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewReviewStage:
            MobileIronwoodMigrationReviewPreviewStage.animatedAnalyzing,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final progressFinder = find.descendant(
      of: find.byKey(
        const ValueKey('mobile_ironwood_migration_analysis_progress'),
      ),
      matching: find.byType(FractionallySizedBox),
    );
    final initialProgress = tester
        .widget<FractionallySizedBox>(progressFinder)
        .widthFactor!;

    await tester.pump(const Duration(milliseconds: 500));

    final advancedProgress = tester
        .widget<FractionallySizedBox>(progressFinder)
        .widthFactor!;
    expect(advancedProgress, greaterThan(initialProgress));
    expect(advancedProgress, lessThan(0.97));
  });

  testWidgets('waits for the plan before completing analysis', (tester) async {
    _useMobileViewport(tester);
    final planCompleter = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanFuture: planCompleter.future,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 2746));
    var progress = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress'),
        ),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(progress.widthFactor, closeTo(0.97, 0.001));
    expect(find.text('Review Migration Plan'), findsNothing);

    planCompleter.complete(_plan);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 256));

    progress = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress'),
        ),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(progress.widthFactor, closeTo(1, 0.001));
    expect(find.text('Your migration plan is ready'), findsOneWidget);
    expect(find.text('Review Migration Plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );
  });

  testWidgets('keeps the review visible while its plan refreshes', (
    tester,
  ) async {
    final refreshCompleter =
        Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    var loadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () {
          loadCount++;
          return loadCount == 1 ? Future.value(_plan) : refreshCompleter.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    container.invalidate(ironwoodMigrationPrivatePlanProvider);
    await tester.pump();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );

    refreshCompleter.complete(_plan);
    await tester.pumpAndSettle();
  });

  testWidgets('does not announce a ready plan when analysis fails', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanFuture: Future.value(),
        disableAnimations: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2746));
    await tester.pump(const Duration(milliseconds: 256));

    expect(find.text('Your migration plan is ready'), findsNothing);
    expect(find.text("Couldn't prepare your migration plan"), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    expect(
      find.textContaining('Vizor needs an up-to-date balance'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('retries plan analysis when foreground sync finishes', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () async {
          planLoadCount++;
          return planLoadCount == 1 ? null : _plan;
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
          isSyncComplete: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsOneWidget,
    );
    final container = ProviderScope.containerOf(
      tester.element(
        find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      ),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(planLoadCount, 2);
    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.textContaining('Vizor needs an up-to-date balance'),
      findsNothing,
    );
  });

  testWidgets('does not reactivate a stale plan while sync refreshes it', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final refreshedPlan = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () {
          planLoadCount++;
          return planLoadCount == 1
              ? Future.value(_plan)
              : refreshedPlan.future;
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start migration').hitTestable(), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
      ),
    );
    await tester.pump();
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await tester.pump();

    expect(planLoadCount, greaterThanOrEqualTo(2));
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsOneWidget,
    );
    expect(find.text('Start migration').hitTestable(), findsNothing);

    refreshedPlan.complete(_plan);
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
  });

  testWidgets('does not reactivate a stale plan after refresh fails', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () {
          planLoadCount++;
          return planLoadCount == 1
              ? Future.value(_plan)
              : Future.error(StateError('plan refresh failed'));
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start migration').hitTestable(), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
      ),
    );
    await tester.pump();
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2746));
    await tester.pump(const Duration(milliseconds: 256));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(planLoadCount, greaterThanOrEqualTo(2));
    final startButton = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(startButton.onPressed, isNull);
    expect(
      find.textContaining('Vizor needs an up-to-date balance'),
      findsOneWidget,
    );
  });

  testWidgets('does not reactivate a stale plan after sync fails', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () async {
          planLoadCount++;
          return _plan;
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start migration').hitTestable(), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
      ),
    );
    await tester.pump();
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: false,
        error: 'sync failed',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2746));
    await tester.pump(const Duration(milliseconds: 256));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(planLoadCount, greaterThanOrEqualTo(2));
    final startButton = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(startButton.onPressed, isNull);
    expect(
      find.textContaining('Vizor needs an up-to-date balance'),
      findsOneWidget,
    );
  });

  testWidgets('keeps the migration review usable at 320 by 568', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.privateReview),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps review summary clear at the Widgetbook viewport', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(393, 720));
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.privateReview),
    );
    await tester.pumpAndSettle();

    final feeRow = tester.getRect(find.text('Fees (estimate)'));
    final startButton = tester.getRect(find.text('Start migration'));
    expect(
      startButton.top - feeRow.bottom,
      greaterThanOrEqualTo(AppSpacing.sm),
    );
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps the fast review warning readable in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.fastReview,
        theme: AppThemeData.dark,
      ),
    );
    await tester.pumpAndSettle();

    final warning = tester.widget<Text>(find.text('Privacy trade-off'));
    expect(warning.style?.color, AppThemeData.dark.colors.text.homeCard);
    final privacyIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('mobile_ironwood_fast_privacy_icon')),
    );
    expect(privacyIcon.name, AppIcons.transparentBalance);
    expect(privacyIcon.size, 20);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_ironwood_fast_privacy_card')),
          )
          .height,
      189,
    );
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('142.23 ZEC'), findsOneWidget);
    expect(find.text('Migration complete in'), findsOneWidget);
    expect(find.text('~5 mins'), findsOneWidget);
    expect(find.text('Orchard remains'), findsNothing);
    expect(
      find.text(
        'I understand that this migration’s amount and timing will be visible '
        'on the Zcash network.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_ironwood_fast_acknowledgement')),
      findsOneWidget,
    );
    expect(find.text('Continue anyway'), findsOneWidget);
    expect(find.text('Authorise anyway'), findsNothing);
  });

  testWidgets('renders the preparing migration state', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(
      find.text(
        'Preparing your balance for migration. This step usually takes '
        '10-20 mins.',
      ),
      findsOneWidget,
    );
    expect(find.text('142.20 ZEC'), findsOneWidget);
    expect(find.text('Migration 12 notes'), findsOneWidget);
    expect(find.text('Note Split'), findsOneWidget);
    expect(find.text('Split Notes into 12 Migration Parts'), findsOneWidget);
    expect(find.text('Wait for confirmation'), findsOneWidget);
    final loader = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.loader,
      ),
    );
    expect(loader.animated, isFalse);
    expect(
      find.text(
        'Migration will start automatically once note split is complete.',
      ),
      findsOneWidget,
    );
    expect(find.text('Go home'), findsOneWidget);
  });

  testWidgets('animates the preparing confirmation loader', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.preparing,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final loader = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.loader,
      ),
    );
    expect(loader.animated, isTrue);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders migrating parts inline', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        previewStatus: _visualMigrationStatus(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Migration 12 notes'), findsOneWidget);
    expect(find.text('142.20 ZEC'), findsOneWidget);
    expect(find.text('Part 1'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Action needed'), findsOneWidget);
    expect(find.text('Sending'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_0')),
        matching: find.text('Done'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_1')),
        matching: find.text('Action needed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_2')),
        matching: find.text('Sending'),
      ),
      findsOneWidget,
    );
    final rail = find.byKey(
      const ValueKey('mobile_ironwood_status_rail_scroll'),
    );
    final railScrollable = find.descendant(
      of: rail,
      matching: find.byType(Scrollable),
    );
    final railPosition = tester.state<ScrollableState>(railScrollable).position;
    expect(railPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(rail, const Offset(-120, 0));
    await tester.pump();
    expect(railPosition.pixels, greaterThan(0));

    final partList = find.byKey(
      const ValueKey('mobile_ironwood_active_part_list'),
    );
    final listScrollable = find.descendant(
      of: partList,
      matching: find.byType(Scrollable),
    );
    final listPosition = tester.state<ScrollableState>(listScrollable).position;
    expect(listPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(partList, const Offset(0, -120));
    await tester.pump();
    expect(listPosition.pixels, greaterThan(0));
    expect(find.text('Currently spendable balance'), findsOneWidget);
    expect(find.text('4.12 ZEC'), findsWidgets);
    expect(
      find.text('You can leave this screen.').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.text('But keep Vizor open & running.').hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Go home'));
    await tester.pumpAndSettle();
    expect(find.text('Go home').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps migration status actions reachable on compact screens', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Go home'));
    await tester.pumpAndSettle();
    expect(find.text('Go home').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts a software migration and opens the status route', (
    tester,
  ) async {
    _useMobileViewport(tester);
    String? startedAccountUuid;
    List<rust_sync.MigrationScheduledTransfer>? startedSchedule;
    var started = false;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (accountUuid, approvedSchedule) async {
            startedAccountUuid = accountUuid;
            startedSchedule = approvedSchedule;
            started = true;
            return _migrationResult();
          },
        ),
        ctaBuilder: () => started
            ? IronwoodHomeMigrationCtaState.resume(
                network: 'main',
                accountUuid: 'account-1',
                status: _status(
                  phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
                ),
              )
            : const IronwoodHomeMigrationCtaState.start(
                network: 'main',
                accountUuid: 'account-1',
              ),
      ),
    );
    await tester.pumpAndSettle();

    final startButton = find.text('Start migration');
    expect(startButton, findsOneWidget);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(startedAccountUuid, 'account-1');
    expect(startedSchedule, _plan.scheduledTransfers);
    expect(find.text('Migration in Progress'), findsOneWidget);
  });

  testWidgets('routes a Keystone account to split signing from review', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var softwareStartCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (_, _) async {
            softwareStartCount += 1;
            return _migrationResult();
          },
        ),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Keystone'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_authorize_start_button')),
    );
    await tester.pumpAndSettle();

    expect(softwareStartCount, 0);
    expect(find.text('keystone denomination sign route'), findsOneWidget);
  });

  testWidgets('renders the mobile Keystone split signing QR', (tester) async {
    _useMobileViewport(tester, size: const Size(320, 568));
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
      signingBatchLimit: 50,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
        child: AppTheme(
          data: AppThemeData.light,
          child: MaterialApp(
            home: MobileIronwoodMigrationKeystoneDenominationSignScreen(
              previewRequest: request,
              previewUrParts: const ['UR:ZCASH-SIGN-BATCH/PREVIEW'],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Scan with Keystone'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_qr')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final nextButton = find.byKey(
      const ValueKey('mobile_ironwood_keystone_signing_next'),
    );
    await tester.ensureVisible(nextButton);
    await tester.pumpAndSettle();
    await tester.tap(nextButton);
    await tester.pump();

    expect(find.text('Step 2/2'), findsOneWidget);
    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(find.textContaining('Scan the QR code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocks an oversized Keystone signing plan before QR', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        hardware: true,
        privatePlan: _planWith(
          denominationSplitStageCount: 13,
          signingBatchLimit: 12,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This migration needs more transactions than one Keystone signing '
        'request supports.',
      ),
      findsOneWidget,
    );
    final button = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('accepts exactly 50 transactions in each Keystone round', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        hardware: true,
        privatePlan: _planWith(
          denominationSplitStageCount: 50,
          plannedBatchCount: 50,
          signingBatchLimit: 50,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('blocks 51 transactions in either Keystone round', (
    tester,
  ) async {
    _useMobileViewport(tester);
    for (final plan in [
      _planWith(
        denominationSplitStageCount: 51,
        plannedBatchCount: 50,
        signingBatchLimit: 50,
      ),
      _planWith(
        denominationSplitStageCount: 50,
        plannedBatchCount: 51,
        signingBatchLimit: 50,
      ),
    ]) {
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/review',
          migrationService: _migrationService(),
          hardware: true,
          privatePlan: plan,
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<AppButton>(
        find.descendant(
          of: find.byKey(
            const ValueKey('mobile_ironwood_authorize_start_button'),
          ),
          matching: find.byType(AppButton),
        ),
      );
      expect(button.onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets(
    'leaving Keystone signing discards the request and reopening prepares a fresh one',
    (tester) async {
      _useMobileViewport(tester, size: const Size(320, 568));
      var prepareCount = 0;
      final discardedRequestIds = <String>[];
      final discardStarted = Completer<void>();
      final finishDiscard = Completer<void>();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _status(phase: kIronwoodMigrationReadyPhase),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                _plan,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => defaultRpcEndpointConfig('main'),
        prepareKeystoneDenominationMigration:
            ({required dbPath, required network, required accountUuid}) async {
              prepareCount += 1;
              return rust_sync.KeystoneMigrationSigningRequest(
                requestId: 'request-$prepareCount',
                messages: [
                  rust_sync.KeystoneMigrationMessage(
                    id: 'message-$prepareCount',
                    redactedPczt: Uint8List.fromList([prepareCount]),
                  ),
                ],
                signingBatchLimit: 50,
              );
            },
        getKeystoneProofStatus: ({required requestId}) async =>
            const rust_sync.KeystoneMigrationProofStatus(
              readyCount: 1,
              totalCount: 1,
              isReady: true,
              isFailed: false,
            ),
        discardKeystoneMigrationRequest: ({required requestId}) async {
          discardedRequestIds.add(requestId);
          if (!discardStarted.isCompleted) {
            discardStarted.complete();
          }
          await finishDiscard.future;
        },
      );

      Widget signingApp() => ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(hardware: true)),
          ironwoodMigrationServiceProvider.overrideWithValue(service),
        ],
        child: AppTheme(
          data: AppThemeData.light,
          child: const MaterialApp(
            home: MobileIronwoodMigrationKeystoneDenominationSignScreen(),
          ),
        ),
      );

      await tester.pumpWidget(signingApp());
      final qr = find.byKey(const ValueKey('mobile_ironwood_keystone_qr'));
      for (var attempt = 0; attempt < 20 && !tester.any(qr); attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(prepareCount, 1);
      expect(qr, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await discardStarted.future;
      expect(discardedRequestIds, ['request-1']);

      await tester.pumpWidget(signingApp());
      await tester.pump(const Duration(milliseconds: 100));
      expect(prepareCount, 1);

      finishDiscard.complete();
      for (var attempt = 0; attempt < 20 && !tester.any(qr); attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(prepareCount, 2);
      expect(qr, findsOneWidget);
    },
  );

  testWidgets('routes a Keystone ready state to migration batch signing', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(phase: kIronwoodMigrationReadyToMigratePhase),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ready for Keystone'), findsOneWidget);
    expect(find.text('3 migration transactions ready to sign'), findsOneWidget);
    final signButton = find.byKey(
      const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
    );
    await tester.ensureVisible(signButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(signButton);
    await tester.pumpAndSettle();

    expect(find.text('keystone batch sign route'), findsOneWidget);
  });

  testWidgets('keeps review visible when start has no durable run', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (_, _) async => _migrationResult(),
        ),
        startedStatus: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          activeRunId: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start migration'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    expect(find.text('Preparing...'), findsNothing);
  });

  testWidgets('maps a live denomination status to Preparing', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          parts: [
            rust_sync.MigrationPartStatus(
              partIndex: 0,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.confirming,
              confirmationCount: 2,
              confirmationTarget: 3,
            ),
            rust_sync.MigrationPartStatus(
              partIndex: 1,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.preparing,
              confirmationCount: 0,
              confirmationTarget: 3,
            ),
            rust_sync.MigrationPartStatus(
              partIndex: 2,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.preparing,
              confirmationCount: 0,
              confirmationTarget: 3,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Wait for confirmation'), findsOneWidget);
    expect(find.text('2/3 blocks'), findsOneWidget);
    expect(find.text('Split Notes into 3 Migration Parts'), findsOneWidget);
    expect(find.bySemanticsLabel('Part 1 progress 20%'), findsNothing);
    expect(find.bySemanticsLabel('Part 1 progress 76%'), findsNothing);
  });

  testWidgets('explains the additional Keystone approval while waiting', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        ),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Another Keystone approval will be needed after these confirmations.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('start automatically'), findsNothing);
  });

  testWidgets('maps live migration progress into the Migrating screen', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(phase: kIronwoodMigrationWaitingConfirmationsPhase),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Migration 3 notes'), findsOneWidget);
    expect(find.text('12.36 ZEC'), findsOneWidget);
    expect(find.textContaining('4.12 ZEC'), findsNWidgets(3));
    expect(find.text('Part 1'), findsOneWidget);
    expect(find.text('Part 3'), findsOneWidget);
  });

  testWidgets('uses per-part state and confirmation progress from Rust', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationWaitingConfirmationsPhase,
      parts: [
        rust_sync.MigrationPartStatus(
          partIndex: 0,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.completed,
          confirmationCount: 3,
          confirmationTarget: 3,
        ),
        rust_sync.MigrationPartStatus(
          partIndex: 1,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.confirming,
          confirmationCount: 2,
          confirmationTarget: 3,
        ),
        rust_sync.MigrationPartStatus(
          partIndex: 2,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.scheduled,
          scheduleStartHeight: 3_499_900,
          scheduledHeight: 3_500_100,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
      ],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          ironwoodBalance: BigInt.from(100_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Confirming · 2/3'), findsOneWidget);
    expect(find.bySemanticsLabel('Part 2 progress 90%'), findsOneWidget);
    expect(find.text('Currently spendable balance'), findsOneWidget);
    expect(find.text('1.00 ZEC'), findsOneWidget);
  });

  testWidgets('does not render synthetic migration values before run data', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      targetValues: const [],
      parts: const [],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Migration 1 notes'), findsNothing);
    expect(find.text('Schedule pending'), findsNothing);
  });

  testWidgets('maps out-of-order broadcasts by their explicit status', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          broadcastStatuses: const ['scheduled', 'confirmed', 'broadcasted'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_0')),
        matching: find.text('Done'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_1')),
        matching: find.text('Done'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_2')),
        matching: find.text('Sending'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows compact queued and waiting states with timing help', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          nextActionHeight: 3_000_020,
          estimatedCompletionHeight: 3_000_040,
          nextActionPartIndex: 1,
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.textContaining('Waiting · ~'), findsOneWidget);
    expect(find.bySemanticsLabel('About estimated completion'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('About estimated completion'));
    await tester.pumpAndSettle();

    expect(find.text('About migration timing'), findsOneWidget);
    expect(find.textContaining('privacy checkpoints'), findsOneWidget);
  });

  testWidgets('keeps an all-confirmed waiting run in progress', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          broadcastStatuses: const ['confirmed', 'confirmed', 'confirmed'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Migration complete'), findsNothing);
    expect(find.text('Done'), findsNWidgets(3));
  });

  testWidgets('offers explicit recovery when a scheduled transfer is due', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var sentAccountUuid = '';
    final dueStatus = _status(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      broadcastStatuses: const ['scheduled', 'scheduled', 'scheduled'],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onSendOne: (accountUuid) async {
            sentAccountUuid = accountUuid;
            return _migrationResult();
          },
        ),
        status: dueStatus,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_100,
          chainTipHeight: 3_000_100,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transfer ready'), findsOneWidget);
    expect(find.text('Send one now'), findsOneWidget);
    expect(find.text('Retry in background'), findsOneWidget);
    expect(find.textContaining('current app activity'), findsOneWidget);

    await tester.tap(find.text('Send one now'));
    await tester.pumpAndSettle();

    expect(sentAccountUuid, 'account-1');
  });

  testWidgets('hides background recovery when the platform cannot run it', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(supportsBackgroundMigration: false),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          broadcastStatuses: const ['scheduled', 'scheduled', 'scheduled'],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_100,
          chainTipHeight: 3_000_100,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transfer ready'), findsOneWidget);
    expect(find.text('Send one now'), findsOneWidget);
    expect(find.text('Retry in background'), findsNothing);
  });

  testWidgets('keeps overdue recovery usable at 320 by 568', (tester) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          broadcastStatuses: const ['scheduled', 'scheduled', 'scheduled'],
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_100,
          chainTipHeight: 3_000_100,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Transfer ready'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry in background'));
    await tester.pumpAndSettle();
    expect(find.text('Retry in background'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
