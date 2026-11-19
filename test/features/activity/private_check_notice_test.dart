import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/features/activity/widgets/private_check_notice.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../support/localized_test_scope.dart';
import '../../support/test_l10n.dart';

const _checking = PrivateCheckNoticeState.checking();
const _stalled = PrivateCheckNoticeState.stopped(
  rust_sync.TransparentStopReason.stalled,
);
const _quarantined = PrivateCheckNoticeState.stopped(
  rust_sync.TransparentStopReason.quarantined,
);

Widget _slot(PrivateCheckNoticeState? notice, {bool reduceMotion = false}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: AppTheme(
        data: AppThemeData.light,
        child: LocalizedTestScope(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              child: PrivateCheckNoticeSlot(
                notice: notice,
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
              ),
            ),
          ),
        ),
      ),
    );

double _height(WidgetTester tester) =>
    tester.getSize(find.byType(PrivateCheckNoticeSlot)).height;

void main() {
  testWidgets('a notice shown from the start has no entrance', (tester) async {
    await tester.pumpWidget(_slot(_checking));

    expect(find.text(testL10n.activityPrivateCheckNotice), findsOneWidget);
    final shown = _height(tester);
    expect(shown, greaterThan(AppSpacing.md));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_height(tester), shown);
  });

  testWidgets('a notice eases out with its spacing, then eases back in', (
    tester,
  ) async {
    await tester.pumpWidget(_slot(_checking));
    final shown = _height(tester);

    await tester.pumpWidget(_slot(null));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_height(tester), inExclusiveRange(0, shown));
    await tester.pump(PrivateCheckNoticeSlot.exitDuration);
    expect(_height(tester), 0);
    expect(find.text(testL10n.activityPrivateCheckNotice), findsNothing);

    await tester.pumpWidget(_slot(_checking));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_height(tester), inExclusiveRange(0, shown));
    await tester.pump(PrivateCheckNoticeSlot.enterDuration);
    expect(_height(tester), shown);
  });

  testWidgets('a stop replaces the notice in place, so it never folds', (
    tester,
  ) async {
    await tester.pumpWidget(_slot(_checking));
    final checking = _height(tester);

    await tester.pumpWidget(_slot(_stalled));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(_height(tester), greaterThanOrEqualTo(checking));
    }
    await tester.pump(PrivateCheckNoticeSlot.swapDuration);
    expect(find.text(testL10n.activityPrivateCheckNotice), findsNothing);
    expect(find.text(testL10n.homeTransparentStopStalled), findsOneWidget);
    // Vizor retries this one itself.
    expect(
      find.byKey(const ValueKey('private_check_notice_settings')),
      findsNothing,
    );

    // A retry checks again.
    await tester.pumpWidget(_slot(_checking));
    await tester.pump(PrivateCheckNoticeSlot.swapDuration * 2);
    expect(find.text(testL10n.activityPrivateCheckNotice), findsOneWidget);
    expect(_height(tester), checking);
  });

  testWidgets('reduced motion switches the notice at once', (tester) async {
    await tester.pumpWidget(_slot(_checking, reduceMotion: true));

    await tester.pumpWidget(_slot(_stalled, reduceMotion: true));
    await tester.pump();
    expect(find.text(testL10n.activityPrivateCheckNotice), findsNothing);
    expect(find.text(testL10n.homeTransparentStopStalled), findsOneWidget);

    await tester.pumpWidget(_slot(null, reduceMotion: true));
    await tester.pump();
    expect(_height(tester), 0);

    await tester.pumpWidget(_slot(_checking, reduceMotion: true));
    await tester.pump();
    expect(find.text(testL10n.activityPrivateCheckNotice), findsOneWidget);
  });

  testWidgets('a stop only the user clears opens Settings', (tester) async {
    final router = GoRouter(
      initialLocation: '/activity',
      routes: [
        GoRoute(
          path: '/activity',
          builder: (_, _) => const Scaffold(
            body: PrivateCheckNoticeSlot(notice: _quarantined),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('settings page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: MaterialApp.router(
          localizationsDelegates: appLocalizationsDelegates,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    // One sentence; the setting's turn-off prompt says what turning it off
    // does.
    expect(
      find.text(testL10n.activityPrivateCheckStopQuarantined),
      findsOneWidget,
    );
    expect(find.text(testL10n.settingsPrivateQueriesLabel), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('private_check_notice_settings')),
    );
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);
  });
}
