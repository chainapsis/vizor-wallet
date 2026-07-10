import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/services/pay_introduction_badge_store.dart';
import 'package:zcash_wallet/src/features/home/widgets/pay_floating_badge.dart';

void main() {
  test('SharedPreferences store remembers the Pay introduction', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesPayIntroductionBadgeStore();

    expect(await store.hasSeen(), isFalse);
    await store.markSeen();
    expect(await store.hasSeen(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(payIntroductionBadgeSeenStorageKey), isTrue);
  });

  testWidgets('floating badge matches the Figma geometry and light colors', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      theme: AppThemeData.light,
      disableAnimations: true,
    );

    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('pay_floating_badge')),
    );
    expect(badgeRect.size, PayFloatingBadge.size);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pay_floating_badge_coin'))),
      badgeRect.topLeft + const Offset(39, 0),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('pay_floating_badge_glow'))),
      Rect.fromLTWH(badgeRect.left + 60, badgeRect.top + 65, 60, 44),
    );
    expect(
      tester.widget<Text>(find.text('Pay in USDC')).style?.color,
      AppThemeData.light.colors.text.inverse,
    );
    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('floating badge uses dark-mode inverse text', (tester) async {
    await _pumpBadge(tester, theme: AppThemeData.dark, disableAnimations: true);

    expect(
      tester.widget<Text>(find.text('Pay in USDC')).style?.color,
      AppThemeData.dark.colors.text.inverse,
    );
  });

  testWidgets('coin floats gently and stays still under reduce motion', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      theme: AppThemeData.light,
      disableAnimations: false,
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(_coinTranslationY(tester), lessThan(0));

    await _pumpBadge(
      tester,
      theme: AppThemeData.light,
      disableAnimations: true,
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(_coinTranslationY(tester), 0);
  });

  testWidgets('target persists NEW before showing and omits it on restart', (
    tester,
  ) async {
    final store = _FakePayIntroductionBadgeStore();
    await _pumpTarget(tester, store, persistenceEnabled: true);

    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(store.markCount, 1);
    final targetRect = tester.getRect(
      find.byKey(const ValueKey('pay_introduction_badge_target')),
    );
    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('pay_floating_badge')),
    );
    expect(badgeRect.left, targetRect.left);
    expect(badgeRect.top, targetRect.top - 65);
    expect(
      tester.getRect(find.byKey(const ValueKey('pay_floating_badge_glow'))),
      Rect.fromLTWH(targetRect.left, targetRect.top, 60, 44),
    );

    await tester.pumpWidget(const SizedBox());
    await _pumpTarget(tester, store, persistenceEnabled: true);

    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(find.text('NEW'), findsNothing);
    expect(store.markCount, 1);
  });

  testWidgets('QA mode bypasses the seen store so the badge can be reviewed', (
    tester,
  ) async {
    final store = _FakePayIntroductionBadgeStore()..seen = true;
    await _pumpTarget(tester, store);

    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(store.markCount, 0);
  });

  testWidgets('NEW stays dismissed after navigating away and back', (
    tester,
  ) async {
    final store = _FakePayIntroductionBadgeStore();
    await _pumpNavigableTarget(tester, store);
    expect(find.byType(PayFloatingBadge), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const SizedBox(key: ValueKey('next_page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('next_page')), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('pay_introduction_badge_target')),
      findsOneWidget,
    );
    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(find.text('NEW'), findsNothing);
    expect(store.markCount, 0);
  });
}

double _coinTranslationY(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.byKey(const ValueKey('pay_floating_badge_coin_motion')),
  );
  return transform.transform.getTranslation().y;
}

Future<void> _pumpBadge(
  WidgetTester tester, {
  required AppThemeData theme,
  required bool disableAnimations,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData().copyWith(
          disableAnimations: disableAnimations,
        ),
        child: AppTheme(
          data: theme,
          child: const Center(child: PayFloatingBadge()),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpTarget(
  WidgetTester tester,
  PayIntroductionBadgeStore store, {
  bool persistenceEnabled = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        payIntroductionBadgeStoreProvider.overrideWithValue(store),
        payIntroductionBadgePersistenceEnabledProvider.overrideWithValue(
          persistenceEnabled,
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData().copyWith(disableAnimations: true),
          child: const AppTheme(
            data: AppThemeData.light,
            child: Center(
              child: PayIntroductionBadgeTarget(
                child: SizedBox(width: 60, height: 44),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpNavigableTarget(
  WidgetTester tester,
  PayIntroductionBadgeStore store,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        payIntroductionBadgeStoreProvider.overrideWithValue(store),
        payIntroductionBadgePersistenceEnabledProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData().copyWith(disableAnimations: true),
          child: AppTheme(
            data: AppThemeData.light,
            child: const Center(
              child: PayIntroductionBadgeTarget(
                child: SizedBox(width: 60, height: 44),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakePayIntroductionBadgeStore implements PayIntroductionBadgeStore {
  bool seen = false;
  int markCount = 0;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async {
    markCount += 1;
    seen = true;
  }
}
