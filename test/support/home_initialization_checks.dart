import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/home/widgets/home_activity_skeleton.dart';
import 'package:zcash_wallet/src/providers/account_initialization_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../fakes/fake_sync_notifier.dart';

void registerHomeInitializationChecks({
  required bool mobile,
  required Widget Function(
    SyncState,
    FakeSyncNotifier,
    Future<GiftCardActivityIndex>,
  )
  app,
  required Finder Function() home,
  required Finder Function() importing,
}) {
  Future<void> pumpFrames(
    WidgetTester tester, {
    bool noSkeleton = false,
  }) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (noSkeleton) {
        expect(find.byType(HomeActivitySkeletonRow), findsNothing);
      }
    }
  }

  Future<void> viewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(
      mobile ? const Size(393, 852) : const Size(1080, 720),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('initial Home for a created account never swaps into importing', (
    tester,
  ) async {
    await viewport(tester);
    final cards = Completer<GiftCardActivityIndex>();
    final initial = SyncState(accountUuid: 'account-1', isSyncing: true);
    final sync = FakeSyncNotifier(initial);
    await tester.pumpWidget(app(initial, sync, cards.future));
    await pumpFrames(tester);
    final c = ProviderScope.containerOf(tester.element(home()));
    c
        .read(accountInitializationProvider.notifier)
        .register('account-1', AccountInitializationKind.created);
    for (final remaining in [1, 0]) {
      sync.emit(initial.copyWith(remainingScanBlocks: remaining));
      await pumpFrames(tester);
      expect(importing(), findsNothing);
      expect(find.byType(HomeActivitySkeletonRow), findsNWidgets(5));
      expect(find.text('No activity, yet...'), findsNothing);
    }
    sync.emit(
      initial.copyWith(
        isSyncing: false,
        isSyncComplete: true,
        hasAccountScopedData: true,
        percentage: 1,
        remainingScanBlocks: 0,
      ),
    );
    await pumpFrames(tester);
    expect(find.byType(HomeActivitySkeletonRow), findsNWidgets(5));
    cards.complete(GiftCardActivityIndex.empty);
    await pumpFrames(tester);
    expect(importing(), findsNothing);
    expect(find.byType(HomeActivitySkeletonRow), findsNothing);
    expect(find.text('No activity, yet...'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'initial Home restore waits through scan zero and delayed local indexes',
    (tester) async {
      await viewport(tester);
      final cards = Completer<GiftCardActivityIndex>();
      final initial = SyncState(accountUuid: 'account-1', isSyncing: true);
      final sync = FakeSyncNotifier(initial);
      await tester.pumpWidget(app(initial, sync, cards.future));
      await pumpFrames(tester);
      final c = ProviderScope.containerOf(tester.element(home()));
      final registry = c.read(accountInitializationProvider.notifier);
      registry.register('account-1', AccountInitializationKind.restored);
      final tokens = registry.pendingTokens();
      await pumpFrames(tester);
      expect(importing(), findsWidgets);
      for (final remaining in [1000, 0]) {
        sync.emit(
          initial.copyWith(
            remainingScanBlocks: remaining,
            hasAccountScopedData: true,
          ),
        );
        registry.observeScan(tokens, completed: false);
        registry.reportReads('account-1', tokens['account-1'], available: true);
        await pumpFrames(tester, noSkeleton: true);
        expect(importing(), findsWidgets);
        expect(find.text('No activity, yet...'), findsNothing);
      }
      sync.emit(
        initial.copyWith(
          isSyncing: false,
          isSyncComplete: true,
          hasAccountScopedData: true,
          remainingScanBlocks: 0,
          percentage: 1,
        ),
      );
      registry.observeScan(tokens, completed: true);
      registry.reportReads('account-1', tokens['account-1'], available: true);
      await pumpFrames(tester, noSkeleton: true);
      expect(importing(), findsWidgets);
      cards.complete(GiftCardActivityIndex.empty);
      // Every frame after releasing the index goes directly to usable Home.
      await pumpFrames(tester, noSkeleton: true);
      expect(importing(), findsNothing);
      expect(find.text('No activity, yet...'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial Home read failure is unavailable rather than stuck importing',
    (tester) async {
      await viewport(tester);
      final initial = SyncState(accountUuid: 'account-1');
      final sync = FakeSyncNotifier(initial);
      await tester.pumpWidget(
        app(initial, sync, Future.value(GiftCardActivityIndex.empty)),
      );
      await pumpFrames(tester);
      final c = ProviderScope.containerOf(tester.element(home()));
      final registry = c.read(accountInitializationProvider.notifier);
      registry.register('account-1', AccountInitializationKind.restored);
      final tokens = registry.pendingTokens();
      registry.observeScan(tokens, completed: true);
      registry.reportReads('account-1', tokens['account-1'], available: false);
      await pumpFrames(tester, noSkeleton: true);
      expect(importing(), findsNothing);
      expect(find.text('Unable to load activity.'), findsOneWidget);
      expect(find.text('No activity, yet...'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
