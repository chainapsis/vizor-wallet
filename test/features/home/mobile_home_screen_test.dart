@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/privacy/privacy_mask.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/features/home/services/pay_introduction_badge_store.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/widgets/mobile/mobile_ironwood_migration_announcement_sheet.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

/// Skips the secure-storage write so toggling works without a platform
/// channel in widget tests.
class _FakePrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _FakeMarketDataSource implements ZecMarketDataSource {
  const _FakeMarketDataSource(this.data);

  final ZecMarketData? data;

  @override
  Future<ZecMarketData?> fetchMarketData() async => data;
}

/// In-memory clicked-state store for the shared desktop/mobile Pay intro.
class _FakePayIntroductionBadgeStore implements PayIntroductionBadgeStore {
  _FakePayIntroductionBadgeStore({this.clicked = false});

  bool clicked;
  int markCount = 0;

  @override
  Future<bool> hasClickedPay() async => clicked;

  @override
  Future<void> markPayClicked() async {
    markCount += 1;
    clicked = true;
  }
}

class _FakePaySelectedAssetStore implements PaySelectedAssetStore {
  const _FakePaySelectedAssetStore();

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    return null;
  }

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {}
}

class _FakeIronwoodAnnouncementStore
    implements IronwoodMigrationAnnouncementStore {
  bool seen = false;

  @override
  Future<bool> isSeen({required String network, required String accountUuid}) {
    return Future.value(seen);
  }

  @override
  Future<void> markSeen({
    required String network,
    required String accountUuid,
  }) async {
    seen = true;
  }
}

class _FakeIronwoodCompletionStore implements IronwoodMigrationCompletionStore {
  bool seen = false;
  int markCount = 0;

  @override
  Future<bool> isSeen({
    required String network,
    required String accountUuid,
    required String completionId,
  }) async => seen;

  @override
  Future<void> markSeen({
    required String network,
    required String accountUuid,
    required String completionId,
  }) async {
    markCount += 1;
    seen = true;
  }
}

class _FakeSyncKeepAwakeNotifier extends SyncKeepAwakeNotifier {
  @override
  SyncKeepAwakeSettings build() =>
      const SyncKeepAwakeSettings(enabled: false, promptSeen: false);

  @override
  Future<void> markPromptSeen() async {
    state = state.copyWith(promptSeen: true);
  }
}

TextStyle _effectiveTextStyle(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  final defaultStyle = DefaultTextStyle.of(tester.element(finder)).style;
  return defaultStyle.merge(text.style);
}

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1homeaddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app(
  SyncState syncState, {
  ZecMarketData? marketData = const ZecMarketData(
    usdPrice: 70,
    change24hPct: 13.12,
  ),
  FakeSyncNotifier? syncNotifier,
  SyncKeepAwakeNotifier? syncKeepAwakeNotifier,
  bool? swapEnabled,
  PayIntroductionBadgeStore? badgeStore,
  IronwoodHomeMigrationCtaState migrationCta =
      const IronwoodHomeMigrationCtaState.hidden(),
  IronwoodHomeMigrationCtaState? migrationPresentationCta,
  IronwoodMigrationAnnouncementState announcement =
      const IronwoodMigrationAnnouncementState.hidden(),
  IronwoodMigrationCompletionState completion =
      const IronwoodMigrationCompletionState.hidden(),
  _FakeIronwoodCompletionStore? completionStore,
}) {
  final effectiveSyncNotifier = syncNotifier ?? FakeSyncNotifier(syncState);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const MobileHomeScreen()),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/pay',
        builder: (_, _) => Consumer(
          builder: (_, ref, _) {
            final state = ref.watch(swapStateProvider);
            return Text(
              'pay route ${state.direction.name} ${state.quoteMode.name}',
            );
          },
        ),
      ),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => const Text('migration intro route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(() => effectiveSyncNotifier),
      if (syncKeepAwakeNotifier != null)
        syncKeepAwakeProvider.overrideWith(() => syncKeepAwakeNotifier),
      privacyModeProvider.overrideWith(_FakePrivacyModeNotifier.new),
      zecMarketDataSourceProvider.overrideWithValue(
        _FakeMarketDataSource(marketData),
      ),
      payIntroductionBadgeStoreProvider.overrideWithValue(
        badgeStore ?? _FakePayIntroductionBadgeStore(),
      ),
      paySelectedAssetStoreProvider.overrideWithValue(
        const _FakePaySelectedAssetStore(),
      ),
      // The coin float loops forever; keep it off so pumpAndSettle-based
      // tests can settle (mirrors the desktop suites' motion seam).
      payIntroductionBadgeMotionEnabledProvider.overrideWithValue(false),
      if (swapEnabled != null)
        swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
      ironwoodHomeMigrationCtaProvider.overrideWith(
        (ref) async => migrationCta,
      ),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        migrationPresentationCta ?? migrationCta,
      ),
      ironwoodMigrationAnnouncementProvider.overrideWith(
        (ref) async => announcement,
      ),
      ironwoodMigrationAnnouncementStoreProvider.overrideWithValue(
        _FakeIronwoodAnnouncementStore(),
      ),
      ironwoodMigrationCompletionProvider.overrideWith(
        (ref) async => completion,
      ),
      ironwoodMigrationCompletionStoreProvider.overrideWithValue(
        completionStore ?? _FakeIronwoodCompletionStore(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    ),
  );
}

SyncState _syncedState({
  BigInt? orchardBalance,
  BigInt? ironwoodBalance,
  BigInt? transparentBalance,
  bool canShieldTransparentBalance = false,
}) => SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  percentage: 1.0,
  displayPercentage: 1.0,
  orchardBalance: orchardBalance ?? BigInt.zero,
  ironwoodBalance: ironwoodBalance ?? BigInt.zero,
  transparentBalance: transparentBalance ?? BigInt.zero,
  canShieldTransparentBalance: canShieldTransparentBalance,
);

rust_sync.TransactionInfo _tx(int index) {
  final seconds = BigInt.from(1800000000 + index);
  return rust_sync.TransactionInfo(
    txidHex: 'tx-$index',
    minedHeight: BigInt.from(index),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: seconds,
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.from(index) * BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: seconds,
  );
}

void main() {
  testWidgets('shows the Figma sync keep-awake prompt copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _app(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
          percentage: 0.25,
          displayPercentage: 0.25,
          scannedHeight: 50,
          chainTipHeight: 200,
          lastSyncStartedAt: DateTime.now().subtract(
            const Duration(minutes: 2),
          ),
        ),
        syncKeepAwakeNotifier: _FakeSyncKeepAwakeNotifier(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    const lockCopy =
        'The app locks after 1 minute of inactivity. Syncing continues behind '
        'the lock.';
    const settingsCopy = 'You can change this anytime in the Settings.';
    expect(find.text('Stay awake to sync?'), findsOneWidget);
    expect(
      find.text(
        'Your phone pauses syncing when screen is off. This allows sync to '
        'finish faster.',
      ),
      findsOneWidget,
    );
    expect(find.text(lockCopy), findsOneWidget);
    expect(find.text(settingsCopy), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(lockCopy)).dy,
      lessThan(tester.getTopLeft(find.text(settingsCopy)).dy),
    );
    expect(find.text('Keep screen awake'), findsOneWidget);
    expect(find.text('Maybe later'), findsOneWidget);

    await tester.tap(find.text('Maybe later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('shows the importing state before account data exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _app(
        SyncState(
          accountUuid: 'account-1',
          isSyncing: true,
          displayPercentage: 0.32,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('32%'), findsOneWidget);
    expect(find.textContaining("importing"), findsOneWidget);
    expect(find.text('Send'), findsNothing);

    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_canvas')),
    );
    final imageRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_image')),
    );

    expect(canvasRect.size, const Size(340, 220));
    expect(imageRect.size, const Size(246, 192));
    expect(canvasRect.bottom, moreOrLessEquals(744));
  });

  testWidgets('shows balance, actions, and empty activity when funded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('143.12', findRichText: true), findsOneWidget);
    expect(find.text(r'$10,018.40'), findsOneWidget);
    expect(find.text('+ 13.12% (24h)'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('No activity, yet...'), findsOneWidget);
  });

  testWidgets('includes Ironwood funds in the mobile shielded balance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.from(100000000),
          ironwoodBalance: BigInt.from(200000000),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('3 ZEC', findRichText: true), findsOneWidget);
  });

  testWidgets('shows the Ironwood home card state without hiding actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(211200000)),
        marketData: const ZecMarketData(
          usdPrice: 568.2386363,
          change24hPct: 13.12,
        ),
        migrationCta: IronwoodHomeMigrationCtaState.start(
          network: 'main',
          accountUuid: 'account-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Migration required'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('mobile_home_ironwood_migration_required_pill'),
            ),
          )
          .height,
      40,
    );
    expect(find.text(r'$1,200.12'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_home_ironwood_migration_banner_background'),
      ),
      findsOneWidget,
    );
    final migrationPill = find.byKey(
      const ValueKey('mobile_home_ironwood_migration_required_pill'),
    );
    final migrationPillIcon = find.descendant(
      of: migrationPill,
      matching: find.byType(AppIcon),
    );
    final migrationPillLabel = find.descendant(
      of: migrationPill,
      matching: find.text('Migration required'),
    );
    expect(
      tester.getTopLeft(migrationPillLabel).dx -
          tester.getTopRight(migrationPillIcon).dx,
      8,
    );
    expect(
      tester
          .widget<Image>(
            find.byKey(
              const ValueKey(
                'mobile_home_ironwood_migration_banner_background',
              ),
            ),
          )
          .fit,
      BoxFit.fill,
    );
    final imageMask = tester.widget<ShaderMask>(
      find.byKey(
        const ValueKey('mobile_home_ironwood_migration_banner_image_mask'),
      ),
    );
    expect(imageMask.blendMode, BlendMode.dstIn);
    final maskShader = imageMask.shaderCallback(
      const Rect.fromLTWH(0, 0, 361, 52),
    );
    expect(maskShader, isA<Shader>());
    final blinkRipple = find.byKey(
      const ValueKey('mobile_home_ironwood_migration_blink_ripple'),
    );
    expect(tester.widget<Opacity>(blinkRipple).opacity, 1);
    expect(tester.getSize(blinkRipple), const Size.square(8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<Opacity>(blinkRipple).opacity, closeTo(0.5, 0.001));
    expect(tester.getSize(blinkRipple), const Size.square(32));
    final rippleDecoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: blinkRipple,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect((rippleDecoration.border! as Border).top.width, 2);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Opacity>(blinkRipple).opacity, 0);
    expect(tester.getSize(blinkRipple), const Size.square(56));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Opacity>(blinkRipple).opacity, 1);
    expect(tester.getSize(blinkRipple), const Size.square(8));
    expect(find.text('Send'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('mobile_home_send')))
          .onPressed,
      isNull,
    );
    expect(find.text('Receive'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_home_ironwood_migration_banner')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_home_ironwood_migration_banner')),
          )
          .height,
      52,
    );

    await tester.tap(find.text('Migration required'));
    await tester.pumpAndSettle();
    expect(find.text('migration intro route'), findsOneWidget);
  });

  testWidgets('keeps the required migration lock while the raw CTA is hidden', (
    tester,
  ) async {
    const requiredCta = IronwoodHomeMigrationCtaState.start(
      network: 'main',
      accountUuid: 'account-1',
    );
    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(100000000)),
        migrationPresentationCta: requiredCta,
      ),
    );
    await tester.pump();

    expect(find.text('Migration required'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('mobile_home_send')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('shows migrated balance and remaining amount while migrating', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now().millisecondsSinceEpoch;
    final status = rust_sync.MigrationStatus(
      phase: kIronwoodMigrationWaitingConfirmationsPhase,
      activeRunId: 'run-1',
      targetValuesZatoshi: frb.Uint64List.fromList([100000000, 200000000]),
      preparedNoteCount: 2,
      denominationConfirmationCount: 3,
      denominationConfirmationTarget: 3,
      denominationSplitCompletedCount: 1,
      denominationSplitTotalCount: 1,
      pendingTxCount: 1,
      broadcastedTxCount: 2,
      confirmedTxCount: 1,
      totalCount: 2,
      signedChildPcztCount: 0,
      pendingSplitStageCount: 0,
      canAbandon: false,
      signingBatchLimit: 50,
      scheduleMeanDelayBlocks: 144,
      scheduleMaxDelayBlocks: 576,
      maxPreparedNotesPerRun: 64,
      scheduledBroadcasts: [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'confirmed',
          valueZatoshi: BigInt.from(100000000),
          scheduledAtMs: now,
          scheduledHeight: 3000000,
          status: 'confirmed',
        ),
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'scheduled',
          valueZatoshi: BigInt.from(200000000),
          scheduledAtMs: now,
          scheduledHeight: 3000144,
          status: 'scheduled',
        ),
      ],
      parts: const [],
    );

    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.from(200000000),
          ironwoodBalance: BigInt.from(150000000),
        ),
        migrationCta: IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: status,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('1.50 ZEC', findRichText: true), findsOneWidget);
    expect(find.text('2 ZEC still migrating'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_home_ironwood_migration_loader')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('mobile_home_send')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('does not infer an exact remaining amount without broadcasts', (
    tester,
  ) async {
    final status = rust_sync.MigrationStatus(
      phase: kIronwoodMigrationWaitingConfirmationsPhase,
      activeRunId: 'run-1',
      targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
      preparedNoteCount: 1,
      denominationConfirmationCount: 3,
      denominationConfirmationTarget: 3,
      denominationSplitCompletedCount: 1,
      denominationSplitTotalCount: 1,
      pendingTxCount: 1,
      broadcastedTxCount: 0,
      confirmedTxCount: 0,
      totalCount: 1,
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

    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.from(100000000),
          ironwoodBalance: BigInt.from(50000000),
        ),
        migrationCta: IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: status,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Migration in progress'), findsOneWidget);
    expect(find.text('1 ZEC still migrating'), findsNothing);
  });

  testWidgets('marks a migration that is more than two hours late', (
    tester,
  ) async {
    final status = rust_sync.MigrationStatus(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      activeRunId: 'run-1',
      targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
      preparedNoteCount: 1,
      denominationConfirmationCount: 3,
      denominationConfirmationTarget: 3,
      denominationSplitCompletedCount: 1,
      denominationSplitTotalCount: 1,
      pendingTxCount: 1,
      broadcastedTxCount: 0,
      confirmedTxCount: 0,
      totalCount: 1,
      signedChildPcztCount: 0,
      pendingSplitStageCount: 0,
      canAbandon: false,
      signingBatchLimit: 50,
      scheduleMeanDelayBlocks: 144,
      scheduleMaxDelayBlocks: 576,
      maxPreparedNotesPerRun: 64,
      scheduledBroadcasts: [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'overdue',
          valueZatoshi: BigInt.from(100000000),
          scheduledAtMs: DateTime.now()
              .subtract(const Duration(hours: 3))
              .millisecondsSinceEpoch,
          scheduledHeight: 3000000,
          status: 'scheduled',
        ),
      ],
      parts: const [],
    );

    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(100000000)),
        migrationCta: IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: status,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Migration needs attention'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_home_ironwood_migration_attention')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_home_ironwood_migration_loader')),
      findsNothing,
    );
  });

  testWidgets('shows the mobile Ironwood announcement sheet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(14312000000)),
        announcement: IronwoodMigrationAnnouncementState.visible(
          network: 'main',
          accountUuid: 'account-1',
          status: rust_sync.MigrationStatus(
            phase: kIronwoodMigrationReadyPhase,
            activeRunId: null,
            preparedNoteCount: 0,
            targetValuesZatoshi: frb.Uint64List.fromList([]),
            denominationConfirmationCount: 0,
            denominationConfirmationTarget: 0,
            denominationSplitCompletedCount: 0,
            denominationSplitTotalCount: 0,
            pendingTxCount: 0,
            broadcastedTxCount: 0,
            confirmedTxCount: 0,
            totalCount: 0,
            signedChildPcztCount: 0,
            pendingSplitStageCount: 0,
            message: null,
            canAbandon: false,
            signingBatchLimit: 0,
            scheduleMeanDelayBlocks: 144,
            scheduleMaxDelayBlocks: 576,
            maxPreparedNotesPerRun: 0,
            scheduledBroadcasts: const [],
            parts: const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(const ValueKey('mobile_ironwood_announcement_sheet')),
      findsOneWidget,
    );
    expect(find.text('Upgrade to Ironwood'), findsOneWidget);
    expect(find.text('Official announcement'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_announcement_close_button')),
      findsOneWidget,
    );

    final bodyRect = tester.getRect(
      find.textContaining('Zcash’s latest shielded pool'),
    );
    final startRect = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_start_migration_button')),
    );
    final announcementRect = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_release_notes_button')),
    );
    expect(startRect.top, greaterThanOrEqualTo(bodyRect.bottom));
    expect(announcementRect.top, greaterThanOrEqualTo(startRect.bottom));
  });

  testWidgets('shows and acknowledges the completed migration receipt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completionStore = _FakeIronwoodCompletionStore();

    await tester.pumpWidget(
      _app(
        _syncedState(ironwoodBalance: BigInt.from(14_212_300_000)),
        completion: IronwoodMigrationCompletionState.visible(
          network: 'main',
          accountUuid: 'account-1',
          completionId: '14000000000_212300000',
          transferredZatoshi: BigInt.from(14_212_300_000),
        ),
        completionStore: completionStore,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_complete_sheet')),
      findsOneWidget,
    );
    expect(find.text('Transferred: 142.123 ZEC'), findsOneWidget);
    expect(find.text('Your funds now\nin Ironwood'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(completionStore.markCount, 0);

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_migration_complete_done')),
    );
    await tester.pumpAndSettle();

    expect(completionStore.markCount, 1);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_complete_sheet')),
      findsNothing,
    );
  });

  testWidgets('Ironwood home surfaces do not overflow at 320 by 568', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(14312000000)),
        migrationCta: IronwoodHomeMigrationCtaState.start(
          network: 'main',
          accountUuid: 'account-1',
        ),
        announcement: IronwoodMigrationAnnouncementState.visible(
          network: 'main',
          accountUuid: 'account-1',
          status: rust_sync.MigrationStatus(
            phase: kIronwoodMigrationReadyPhase,
            activeRunId: null,
            preparedNoteCount: 0,
            targetValuesZatoshi: frb.Uint64List.fromList([]),
            denominationConfirmationCount: 0,
            denominationConfirmationTarget: 0,
            denominationSplitCompletedCount: 0,
            denominationSplitTotalCount: 0,
            pendingTxCount: 0,
            broadcastedTxCount: 0,
            confirmedTxCount: 0,
            totalCount: 0,
            signedChildPcztCount: 0,
            pendingSplitStageCount: 0,
            message: null,
            canAbandon: false,
            signingBatchLimit: 0,
            scheduleMeanDelayBlocks: 144,
            scheduleMaxDelayBlocks: 576,
            maxPreparedNotesPerRun: 0,
            scheduledBroadcasts: const [],
            parts: const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Upgrade to Ironwood'), findsOneWidget);
    await tester.ensureVisible(find.text('Official announcement'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('announcement scrolls at 320 width with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
        home: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 288,
            height: 536,
            child: MobileIronwoodMigrationAnnouncementSheet(
              onStartMigration: () {},
              onOpenReleaseNotes: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Official announcement'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses compact balance precision for long decimals', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.parse('1234512345678'),
          transparentBalance: BigInt.from(12345678),
          canShieldTransparentBalance: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('12345.12', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('12345.12345678', findRichText: true),
      findsNothing,
    );
    expect(find.text('Transparent: 0.123456 ZEC'), findsOneWidget);
  });

  testWidgets('shows transparent balance tray with shield action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.from(14312000000),
          transparentBalance: BigInt.from(242000000),
          canShieldTransparentBalance: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_home_transparent_balance_strip')),
      findsOneWidget,
    );
    expect(find.text('Transparent: 2.42 ZEC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_home_shield_balance_button')),
      findsOneWidget,
    );
    expect(find.text('Shield'), findsOneWidget);
  });

  testWidgets('animates transparent balance tray away before removal', (
    tester,
  ) async {
    final syncNotifier = FakeSyncNotifier(
      _syncedState(
        orchardBalance: BigInt.from(14312000000),
        transparentBalance: BigInt.from(242000000),
        canShieldTransparentBalance: true,
      ),
    );
    await tester.pumpWidget(
      _app(syncNotifier.initialState!, syncNotifier: syncNotifier),
    );
    await tester.pump();
    await tester.pump();

    final stripFinder = find.byKey(
      const ValueKey('mobile_home_transparent_balance_strip'),
    );
    expect(stripFinder, findsOneWidget);
    final expandedHeight = tester.getSize(stripFinder).height;
    expect(expandedHeight, moreOrLessEquals(57));

    syncNotifier.setSyncState(
      _syncedState(orchardBalance: BigInt.from(14312000000)),
    );
    await tester.pump();
    expect(stripFinder, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getSize(stripFinder).height, lessThan(expandedHeight));

    await tester.pumpAndSettle();
    expect(stripFinder, findsNothing);
  });

  testWidgets('matches the Figma balance card controls and action labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();
    await tester.pump();

    final privacyButtonRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_privacy_button')),
    );
    final privacyIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_home_privacy_button')),
        matching: find.byType(AppIcon),
      ),
    );
    final sendRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_send')),
    );
    final receiveRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_receive')),
    );
    final payRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_pay')),
    );
    final payIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_home_pay')),
        matching: find.byType(AppIcon),
      ),
    );
    final sendLabelStyle = _effectiveTextStyle(tester, find.text('Send'));
    final receiveLabelStyle = _effectiveTextStyle(tester, find.text('Receive'));
    final shieldedLabel = tester.widget<Text>(find.text('Shielded balance'));
    final fiatLabel = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_home_balance_fiat_text')),
    );
    final balanceText = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_home_shielded_balance')),
    );
    final balanceSpan = balanceText.textSpan! as TextSpan;
    final amountSpan = balanceSpan.children![0] as TextSpan;
    final tickerSpan = balanceSpan.children![1] as TextSpan;

    expect(privacyButtonRect.size, const Size(32, 32));
    expect(privacyIcon.size, 16);
    expect(payIcon.name, AppIcons.paid);
    expect(payIcon.size, 20);
    expect(find.bySemanticsLabel('Pay'), findsOneWidget);
    expect(payRect.top, moreOrLessEquals(sendRect.top, epsilon: 0.1));
    expect(payRect.bottom, moreOrLessEquals(sendRect.bottom, epsilon: 0.1));
    expect(payRect.size, const Size(50, 50));
    expect(receiveRect.left, greaterThan(sendRect.right));
    expect(payRect.left, greaterThan(receiveRect.right));
    expect(
      find.byKey(const ValueKey('mobile_home_pay_badges')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile_home_pay_coin')), findsOneWidget);
    expect(sendRect.height, AppButtonSizing.largeHeight);
    expect(sendLabelStyle.fontSize, AppTypography.labelLarge.fontSize);
    expect(sendLabelStyle.height, AppTypography.labelLarge.height);
    expect(sendLabelStyle.fontWeight, AppTypography.labelLarge.fontWeight);
    expect(
      sendLabelStyle.letterSpacing,
      AppTypography.labelLarge.letterSpacing,
    );
    expect(receiveLabelStyle.fontSize, AppTypography.labelLarge.fontSize);
    expect(receiveLabelStyle.height, AppTypography.labelLarge.height);
    expect(receiveLabelStyle.fontWeight, AppTypography.labelLarge.fontWeight);
    expect(
      receiveLabelStyle.letterSpacing,
      AppTypography.labelLarge.letterSpacing,
    );
    expect(shieldedLabel.style?.fontSize, 14);
    expect(shieldedLabel.style?.height, 16 / 14);
    expect(fiatLabel.style?.fontSize, 14);
    expect(amountSpan.style?.fontSize, 45);
    expect(amountSpan.style?.height, 48 / 45);
    expect(tickerSpan.style?.fontSize, 32);
    expect(tickerSpan.style?.height, 33 / 32);
  });

  testWidgets('zero balance offers the first-receive action', (tester) async {
    await tester.pumpWidget(_app(_syncedState()));
    await tester.pump();

    expect(find.text('Receive your first ZEC'), findsOneWidget);
    expect(find.text('Send'), findsNothing);

    await tester.tap(find.text('Receive your first ZEC'));
    await tester.pumpAndSettle();
    expect(find.text('receive route'), findsOneWidget);
  });

  testWidgets('pay action opens exact-output pay route', (tester) async {
    final badgeStore = _FakePayIntroductionBadgeStore();
    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(14312000000)),
        badgeStore: badgeStore,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_home_pay')));
    await tester.pumpAndSettle();

    expect(find.text('pay route zecToExternal exactOutput'), findsOneWidget);
    expect(badgeStore.clicked, isTrue);
    expect(badgeStore.markCount, 1);
  });

  testWidgets('hides the mobile Pay introduction after Pay was activated', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(14312000000)),
        badgeStore: _FakePayIntroductionBadgeStore(clicked: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_home_pay')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_home_pay_badges')), findsNothing);
    expect(find.byKey(const ValueKey('mobile_home_pay_coin')), findsNothing);
    final glow = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mobile_home_pay_glow')),
    );
    expect((glow.decoration as BoxDecoration).boxShadow, isNull);
  });

  testWidgets('hides the pay entry and callout when swap is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(14312000000)),
        swapEnabled: false,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_home_pay')), findsNothing);
    expect(find.byKey(const ValueKey('mobile_home_pay_badges')), findsNothing);
    expect(find.byKey(const ValueKey('mobile_home_pay_coin')), findsNothing);
    // Send/Receive remain.
    expect(find.byKey(const ValueKey('mobile_home_send')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_home_receive')), findsOneWidget);
  });

  testWidgets('uses the mobile Rest illustration canvas for empty activity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_app(_syncedState()));
    await tester.pump();

    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_canvas')),
    );
    final imageRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_image')),
    );

    expect(canvasRect.size, const Size(340, 220));
    expect(imageRect.size, const Size(246, 192));
    expect(imageRect.left - canvasRect.left, 47);
    expect(imageRect.top - canvasRect.top, 28);
  });

  testWidgets('privacy eye masks the balance', (tester) async {
    final impactTypes = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          impactTypes.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.eye,
      ),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Hide balance'));
    await tester.pump();

    expect(
      find.textContaining(fixedPrivacyMask(), findRichText: true),
      findsAtLeastNWidgets(2),
    );
    expect(impactTypes, ['HapticFeedbackType.mediumImpact']);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.eyeClosed,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('143.12', findRichText: true), findsNothing);
    expect(find.text(r'$10.02K'), findsNothing);
  });

  testWidgets('shows up to ten recent activity rows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(100000000)).copyWith(
          recentTransactions: [for (var i = 0; i < 11; i++) _tx(i + 1)],
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 10; i++) {
      expect(
        find.byKey(ValueKey('mobile_home_activity_row_$i')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('mobile_home_activity_row_10')),
      findsNothing,
    );
  });

  testWidgets('recent activity section uses the Figma inner inset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.from(100000000),
        ).copyWith(recentTransactions: [_tx(1)]),
      ),
    );
    await tester.pump();

    final sendRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_send')),
    );
    final payRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_pay')),
    );
    final rowRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_activity_row_0')),
    );
    final headerFinder = find.text('Recent activity');
    final seeAllFinder = find.text('See all');
    final headerRect = tester.getRect(headerFinder);
    final seeAllRect = tester.getRect(
      find.ancestor(
        of: seeAllFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 24,
        ),
      ),
    );
    final headerText = tester.widget<Text>(headerFinder);
    final seeAllText = tester.widget<Text>(seeAllFinder);

    expect(
      rowRect.left,
      moreOrLessEquals(sendRect.left + AppSpacing.xs, epsilon: 0.1),
    );
    expect(
      rowRect.right,
      moreOrLessEquals(payRect.right - AppSpacing.xs, epsilon: 0.1),
    );
    expect(headerRect.left, rowRect.left);
    expect(seeAllRect.height, 24);
    expect(headerText.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(headerText.style?.fontWeight, FontWeight.w600);
    expect(seeAllText.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(
      seeAllText.style?.color,
      AppThemeData.dark.colors.button.ghost.label,
    );
  });
}
