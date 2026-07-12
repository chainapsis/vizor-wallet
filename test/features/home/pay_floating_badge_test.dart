import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/services/pay_introduction_badge_store.dart';
import 'package:zcash_wallet/src/features/home/widgets/pay_floating_badge.dart';

void main() {
  test('SharedPreferences store remembers a Pay button click', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesPayIntroductionBadgeStore();

    expect(await store.hasClickedPay(), isFalse);
    await store.markPayClicked();
    expect(await store.hasClickedPay(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(payIntroductionButtonClickedStorageKey), isTrue);
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

  testWidgets('coin bobs continuously and stays still under reduce motion', (
    tester,
  ) async {
    await _pumpBadge(
      tester,
      theme: AppThemeData.light,
      disableAnimations: false,
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(_coinTranslationY(tester), lessThan(0));
    // A full up-down cycle later the loop passes through rest...
    await tester.pump(const Duration(milliseconds: 2700));
    expect(_coinTranslationY(tester), moreOrLessEquals(0));
    // ...and keeps bobbing instead of stopping after one cycle.
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

  testWidgets('target keeps the full treatment until Pay is clicked', (
    tester,
  ) async {
    final store = _FakePayIntroductionBadgeStore();
    await _pumpTarget(tester, store, persistenceEnabled: true);

    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_floating_badge_glow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pay_floating_badge_coin')),
      findsOneWidget,
    );
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(store.markCount, 0);
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PayIntroductionBadgeTarget)),
      listen: false,
    );
    container.read(payIntroductionBadgeClickedProvider.notifier).markClicked();
    await tester.pumpAndSettle();

    expect(find.byType(PayFloatingBadge), findsNothing);
    expect(find.byKey(const ValueKey('pay_floating_badge_glow')), findsNothing);
    expect(find.byKey(const ValueKey('pay_floating_badge_coin')), findsNothing);
    expect(find.text('Pay in USDC'), findsNothing);
    expect(find.text('NEW'), findsNothing);
    expect(store.markCount, 1);
  });

  testWidgets('clicked target shows the full treatment only while hovered', (
    tester,
  ) async {
    final store = _FakePayIntroductionBadgeStore()..clicked = true;
    await _pumpTarget(tester, store, persistenceEnabled: true);

    expect(find.byType(PayFloatingBadge), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('pay_introduction_badge_target')),
      ),
    );
    await tester.pump();

    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_floating_badge_glow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pay_floating_badge_coin')),
      findsOneWidget,
    );
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();

    expect(find.byType(PayFloatingBadge), findsNothing);
    expect(find.byKey(const ValueKey('pay_floating_badge_glow')), findsNothing);
    expect(find.byKey(const ValueKey('pay_floating_badge_coin')), findsNothing);
    expect(find.text('Pay in USDC'), findsNothing);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('clicked target fades the treatment on hover transitions', (
    tester,
  ) async {
    final store = _FakePayIntroductionBadgeStore()..clicked = true;
    await _pumpTarget(
      tester,
      store,
      persistenceEnabled: true,
      disableAnimations: false,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('pay_introduction_badge_target')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    expect(_badgeFadeOpacity(tester), inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 90));
    expect(_badgeFadeOpacity(tester), 1);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(_badgeFadeOpacity(tester), inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 61));
    await tester.pump();
    expect(find.byType(PayFloatingBadge), findsNothing);
  });

  testWidgets('target excludes decorative callout semantics', (tester) async {
    final store = _FakePayIntroductionBadgeStore();
    await _pumpTarget(tester, store, persistenceEnabled: true);

    expect(find.bySemanticsLabel('Pay in USDC'), findsNothing);
  });

  testWidgets(
    'QA mode bypasses the clicked store so the badge can be reviewed',
    (tester) async {
      final store = _FakePayIntroductionBadgeStore()..clicked = true;
      await _pumpTarget(tester, store);

      expect(find.byType(PayFloatingBadge), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(store.markCount, 0);
    },
  );

  testWidgets('navigation without a Pay click keeps the full treatment', (
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
    expect(find.text('NEW'), findsOneWidget);
    expect(store.markCount, 0);
  });
}

double _coinTranslationY(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.byKey(const ValueKey('pay_floating_badge_coin_motion')),
  );
  return transform.transform.getTranslation().y;
}

double _badgeFadeOpacity(WidgetTester tester) {
  final fade = tester.widget<FadeTransition>(
    find.descendant(
      of: find.byKey(const ValueKey('pay_introduction_badge_fade')),
      matching: find.byKey(const ValueKey('pay_introduction_visible_fade')),
    ),
  );
  return fade.opacity.value;
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
  bool disableAnimations = true,
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
          data: const MediaQueryData().copyWith(
            disableAnimations: disableAnimations,
          ),
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
  await tester.pump();
  await tester.pump();
  if (disableAnimations) await tester.pumpAndSettle();
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
  bool clicked = false;
  int markCount = 0;

  @override
  Future<bool> hasClickedPay() async => clicked;

  @override
  Future<void> markPayClicked() async {
    markCount += 1;
    clicked = true;
  }
}
