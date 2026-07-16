@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

final _data = IronwoodMigrationFlowData(
  amountZatoshi: BigInt.from(14_224_000_000),
  accountName: 'Wallet 1',
  profilePictureId: 'default',
);

rust_sync.OrchardMigrationPrivatePlan get _plan =>
    rust_sync.OrchardMigrationPrivatePlan(
      targetValuesZatoshi: frb.Uint64List.fromList([]),
      totalInputZatoshi: BigInt.from(14_224_000_000),
      totalMigratableZatoshi: BigInt.from(14_223_900_000),
      orchardChangeZatoshi: BigInt.from(90_000),
      denominationSplitFeeZatoshi: BigInt.from(20_000),
      migrationFeeZatoshi: BigInt.from(14_400_000),
      estimatedTotalFeeZatoshi: BigInt.from(14_420_000),
      plannedBatchCount: 12,
      denominationSplitStageCount: 1,
      signingBatchLimit: 12,
      broadcastWindowSeconds: BigInt.from(172_800),
      maxPreparedNotesPerRun: 12,
    );

Widget _app({
  required MobileIronwoodMigrationStep step,
  AppThemeData theme = AppThemeData.light,
}) {
  late final GoRouter router;
  MobileIronwoodMigrationFlowScreen screen(MobileIronwoodMigrationStep value) {
    return MobileIronwoodMigrationFlowScreen(
      step: value,
      previewData: _data,
      previewPrivatePlan: _plan,
      previewArrivalLabel: 'July 18, 12:00 (~2days)',
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
      MobileIronwoodMigrationStep.passcodeWhileSyncing =>
        '/migration/private/unlock',
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
      GoRoute(
        path: '/migration/private/unlock',
        builder: (_, _) =>
            screen(MobileIronwoodMigrationStep.passcodeWhileSyncing),
      ),
    ],
  );

  return ProviderScope(
    child: AppTheme(
      data: theme,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void _useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('connects the About and migration-steps screens', (tester) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.intro));
    await tester.pumpAndSettle();

    expect(find.text('Zcash Network Update'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_wordmark')),
      findsOneWidget,
    );
    expect(find.text('How the migration works'), findsOneWidget);

    await tester.tap(find.text('How the migration works'));
    await tester.pumpAndSettle();

    expect(find.text('How Migration Works'), findsOneWidget);
    expect(find.text('Split funds'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Sign once'), findsOneWidget);
  });

  testWidgets('shows the production migration type choice and private route', (
    tester,
  ) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.options));
    await tester.pumpAndSettle();

    expect(find.text('Choose How to Migrate\nyour 142.24 ZEC'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Immediate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_immediate_unavailable')),
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
    expect(find.text('142.24 ZEC'), findsOneWidget);
    expect(find.text('12 planned batches'), findsOneWidget);
    expect(find.text('July 18, 12:00 (~2days)'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
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
    expect(find.text('Authorise anyway'), findsOneWidget);
  });

  testWidgets('renders the preparing migration state', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('142.24 ZEC'), findsOneWidget);
    expect(find.text('Transaction splits submitted'), findsOneWidget);
    expect(find.text('Waiting for confirmation ...'), findsOneWidget);
    expect(find.text('Migration schedule'), findsOneWidget);
    expect(find.text('Back home'), findsOneWidget);
  });

  testWidgets('opens and closes the migrating batch plan', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.migrating));
    await tester.pumpAndSettle();

    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.text('142.24 ZEC'), findsOneWidget);
    expect(find.text('12 planned batches'), findsOneWidget);
    expect(find.text('Current batch'), findsOneWidget);
    expect(find.text('Confirming...'), findsOneWidget);
    expect(find.text('July 18, 12:00'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.text('12 batches'), findsOneWidget);
    expect(find.text('ETA: Jul 18, 12:00'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('migration_batch_scrollbar')),
      findsOneWidget,
    );
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('12 batches'), findsNothing);
  });

  testWidgets('renders passcode while migration keeps running', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.passcodeWhileSyncing),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });
}
