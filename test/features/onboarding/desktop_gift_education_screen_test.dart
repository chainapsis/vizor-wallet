import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/create/desktop_gift_education_screen.dart';
import 'package:zcash_wallet/src/features/home/widgets/desktop_home_setup_carousel.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/widgets/app_carousel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

import '../../support/payment_link_navigation_support.dart';
import '../../support/payment_links_screen_support.dart'
    show loadPaymentLinksTestFonts;

class _EducationAccounts extends AccountNotifier {
  final finished = <String>[];
  bool failSave = false;
  Completer<void>? saving;
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'a',
        name: 'First',
        order: 0,
        setupPending: true,
        giftEducationPending: true,
      ),
      AccountInfo(
        uuid: 'b',
        name: 'Second',
        order: 1,
        setupPending: true,
        giftEducationPending: true,
      ),
    ],
    activeAccountUuid: 'a',
  );

  @override
  Future<void> markGiftEducationComplete(String uuid) async {
    if (failSave) throw StateError('storage unavailable');
    await saving?.future;
    finished.add(uuid);
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        accounts: [
          for (final account in current.accounts)
            if (account.uuid == uuid)
              account.copyWith(giftEducationPending: false)
            else
              account,
        ],
      ),
    );
  }

  void switchToSecondAccount() =>
      state = AsyncData(state.requireValue.copyWith(activeAccountUuid: 'b'));
}

Widget _app(_EducationAccounts accounts, GoRouter router) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(readyPaymentLinkBootstrap),
    accountProvider.overrideWith(() => accounts),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(
      data: AppThemeData.dark,
      child: AppToastHost(child: child!),
    ),
  ),
);

GoRouter _router({
  String initialLocation = '/setup/education/intro',
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/home',
      builder: (_, _) => const Center(child: DesktopHomeSetupCarousel()),
    ),
    GoRoute(
      path: '/setup/backup',
      builder: (_, state) => Text('Backup ${state.extra}'),
    ),
    GoRoute(path: '/other', builder: (_, _) => const Text('Other destination')),
    for (final entry in {
      '/setup/education/intro': DesktopGiftEducationPage.intro,
      '/setup/education/address-types': DesktopGiftEducationPage.addressTypes,
      '/setup/education/things-to-know': DesktopGiftEducationPage.thingsToKnow,
    }.entries)
      GoRoute(
        path: entry.key,
        builder: (_, state) => DesktopGiftEducationScreen(
          page: entry.value,
          accountUuid: state.extra as String?,
        ),
      ),
  ],
);

void main() {
  setUpAll(loadPaymentLinksTestFonts);

  testWidgets(
    'Home setup carousel is manual and pins backup and education to its account',
    (tester) async {
      final accounts = _EducationAccounts();
      final router = _router(initialLocation: '/home');
      addTearDown(router.dispose);
      await _pumpApp(tester, accounts, router);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppCarousel>(find.byType(AppCarousel)).autoplay,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('app_carousel_card_0')));
      await tester.pumpAndSettle();
      expect(find.text('Backup a'), findsOneWidget);
      router.go('/home');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('app_carousel_page_view')),
        const Offset(-420, 0),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/setup/education/intro');
      accounts.switchToSecondAccount();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('desktop_education_skip')));
      await tester.pumpAndSettle();
      expect(accounts.finished, ['a']);
      expect(accounts.state.requireValue.accounts.first.setupPending, isTrue);
    },
  );

  for (final skip in [false, true]) {
    testWidgets(
      skip
          ? 'Skip completes only education and returns Home'
          : 'existing three education pages finish directly Home without setup progress',
      (tester) async {
        final accounts = _EducationAccounts();
        final router = _router();
        addTearDown(router.dispose);
        await _pumpApp(tester, accounts, router);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Your wallet is ready. Learn how Zcash protects your privacy and which address to use.',
          ),
          findsOneWidget,
        );
        expect(find.text('Secret Passphrase'), findsNothing);
        if (!skip) {
          for (final key in [
            'desktop_education_continue',
            'desktop_education_continue',
          ]) {
            await tester.tap(find.byKey(ValueKey(key)));
            await tester.pumpAndSettle();
            expect(find.text('Secret Passphrase'), findsNothing);
          }
        }
        await tester.tap(
          find.byKey(
            ValueKey(
              skip ? 'desktop_education_skip' : 'desktop_education_continue',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(router.state.matchedLocation, '/home');
        expect(accounts.finished, ['a']);
        expect(accounts.state.requireValue.accounts.first.setupPending, isTrue);
        expect(
          accounts.state.requireValue.accounts.last.giftEducationPending,
          isTrue,
        );
      },
    );
  }

  testWidgets('leaving education keeps its Home prompt pending', (
    tester,
  ) async {
    final accounts = _EducationAccounts();
    final router = _router();
    addTearDown(router.dispose);
    await _pumpApp(tester, accounts, router);
    await tester.pumpAndSettle();
    router.go('/home');
    await tester.pumpAndSettle();
    expect(accounts.finished, isEmpty);
    expect(
      accounts.state.requireValue.accounts.first.giftEducationPending,
      isTrue,
    );
  });

  testWidgets('saving failure leaves education open for a retry', (
    tester,
  ) async {
    final accounts = _EducationAccounts()..failSave = true;
    final router = _router();
    addTearDown(router.dispose);
    await _pumpApp(tester, accounts, router);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop_education_skip')));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/setup/education/intro');
    expect(
      find.text('Unable to save your progress. Try again.'),
      findsOneWidget,
    );
    expect(accounts.finished, isEmpty);
    accounts.failSave = false;
    await tester.tap(find.byKey(const ValueKey('desktop_education_skip')));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/home');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'completion targets the original account after an account switch',
    (tester) async {
      final accounts = _EducationAccounts();
      final router = _router();
      addTearDown(router.dispose);
      await _pumpApp(tester, accounts, router);
      await tester.pumpAndSettle();
      accounts.switchToSecondAccount();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('desktop_education_skip')));
      await tester.pumpAndSettle();
      expect(accounts.finished, ['a']);
      expect(
        accounts.state.requireValue.accounts.last.giftEducationPending,
        isTrue,
      );
    },
  );

  testWidgets(
    'completion that finishes after leaving does not replace the new route',
    (tester) async {
      final accounts = _EducationAccounts()..saving = Completer<void>();
      final router = _router();
      addTearDown(router.dispose);
      await _pumpApp(tester, accounts, router);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('desktop_education_skip')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('desktop_education_continue')),
      );
      await tester.pump();
      expect(router.state.matchedLocation, '/setup/education/intro');
      router.go('/other');
      await tester.pumpAndSettle();
      accounts.saving!.complete();
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/other');
      expect(accounts.finished, ['a']);
    },
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  _EducationAccounts accounts,
  GoRouter router,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_app(accounts, router));
}
