import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/home/screens/home_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/widgetbook/support/wb_sidebar.dart';
import 'package:zcash_wallet/widgetbook/gallery/receive_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/home_activity_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/send_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/swap_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/pay_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/send_screen_use_cases.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  test(
    'preview post-migration state follows the CTA without chain services',
    () async {
      for (final cta in [
        const IronwoodHomeMigrationCtaState.hidden(),
        const IronwoodHomeMigrationCtaState.start(
          network: 'main',
          accountUuid: 'preview',
        ),
      ]) {
        final container = ProviderContainer(
          overrides: [
            ironwoodHomeMigrationPresentationProvider.overrideWithValue(cta),
            wbPostMigrationState,
          ],
        );
        addTearDown(container.dispose);
        final state = await container.read(
          ironwoodPostMigrationStateProvider.future,
        );
        expect(
          state.locksNavigation,
          cta.mode == IronwoodHomeMigrationCtaMode.start,
        );
        expect(state.accountUuid, cta.accountUuid);
        expect(container.exists(chainUpgradeStatusProvider), isFalse);
        expect(container.exists(ironwoodActivationStoreProvider), isFalse);
      }
    },
  );
  setUpAll(() async {
    for (final entry in {
      'Geist': ['Regular', 'Medium', 'SemiBold', 'Bold'],
      'Geist Mono': ['Regular', 'Medium'],
      'Young Serif': ['Regular'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final weight in entry.value) {
        loader.addFont(
          rootBundle.load(
            'assets/fonts/${entry.key.replaceAll(' ', '')}-$weight.ttf',
          ),
        );
      }
      await loader.load();
    }
  });

  test('normal sidebar keeps its service-backed actions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appSidebarActionOverrideProvider), isNull);
  });

  final surfaces = <String, WidgetBuilder>{
    'Receive': buildReceiveScreenGalleryCase,
    'Home': buildHomeScreenGalleryCase,
    'Send': buildSendScreenGalleryCase,
    'Swap': buildSwapScreenGalleryCase,
    'Pay': buildPayScreenGalleryCase,
    'Activity': buildActivityScreenGalleryCase,
    'Transaction detail': buildActivityTransactionStatusGalleryCase,
    'Swap detail': buildActivitySwapDetailScreenGalleryCase,
  };
  testWidgets('Send resume does not expose an active migration sidebar route', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'Balance': sendScreenBalanceLabel(SendScreenBalance.ironwoodResume),
      },
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final sidebar = find.byType(AppMainSidebar);
    final context = tester.element(sidebar);
    final router = GoRouter.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final accountBefore = container.read(accountProvider);
    expect(
      container.read(ironwoodHomeMigrationPresentationProvider).mode,
      IronwoodHomeMigrationCtaMode.resume,
    );
    expect(find.text('Migrating...'), findsNothing);
    expect(
      find.byKey(const ValueKey('sidebar_migration_progress_button')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('sidebar_home_button')));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.error, isNull);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.textContaining('/home'), findsWidgets);
    await tester.tap(find.text('Back to send preview'));
    await tester.pumpAndSettle();
    expect(find.byType(AppMainSidebar), findsOneWidget);
    expect(find.text('Migrating...'), findsNothing);
    expect(container.read(accountProvider), same(accountBefore));
    expect(container.exists(chainUpgradeStatusProvider), isFalse);
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });
  for (final layout in WbLayout.values) {
    testWidgets('${layout.name} Home switch updates address and scoped sync', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
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
      await pumpUseCase(
        tester,
        buildHomeScreenGalleryCase,
        knobs: {'Layout': wbLayoutLabel(layout)},
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final container = ProviderScope.containerOf(
        tester.element(
          find.byType(
            layout == WbLayout.mobile ? MobileHomeScreen : HomeScreen,
          ),
        ),
        listen: false,
      );
      final original = container.read(accountProvider).requireValue;
      final first = original.activeAccountUuid!;
      final second = original.accounts.firstWhere((a) => a.uuid != first).uuid;
      Future<void> openMenu() async {
        await tester.tap(
          layout == WbLayout.mobile
              ? find.text('Account Name').first
              : find.byKey(const ValueKey('sidebar_accounts_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      Finder row(String uuid) => find.byKey(
        ValueKey(
          layout == WbLayout.mobile
              ? 'account_row_$uuid'
              : 'sidebar_account_popover_row_$uuid',
        ),
      );
      final copyButton = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Copy shielded address',
      );
      await openMenu();
      await tester.tap(row(second));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        container.read(accountProvider).requireValue.activeAddress,
        'u1widgetbookhomeaddress2',
      );
      expect(container.read(syncProvider).requireValue.accountUuid, second);
      if (layout == WbLayout.desktop) {
        await tester.tap(copyButton);
        await tester.pump(const Duration(milliseconds: 300));
        expect(copied.last, 'u1widgetbookhomeaddress2');
      }
      await openMenu();
      await tester.tap(find.descendant(of: row(first), matching: copyButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied.last, original.activeAddress);
      await tester.tap(row(first));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        container.read(accountProvider).requireValue.activeAddress,
        original.activeAddress,
      );
      expect(container.read(syncProvider).requireValue.accountUuid, first);
      expect(tester.takeException(), isNull);
      await disposeTree(tester);
    });
  }
  for (final surface in surfaces.entries) {
    if (const [
      'Home',
      'Activity',
      'Transaction detail',
      'Swap detail',
      'Send',
    ].contains(surface.key)) {
      testWidgets(
        '${surface.key} copies inactive and active fixture addresses',
        (tester) async {
          final copied = <String>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied.add((call.arguments as Map)['text'] as String);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await pumpUseCase(
            tester,
            surface.value,
            knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
          );
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final sidebar = find.byType(AppMainSidebar);
          final container = ProviderScope.containerOf(
            tester.element(sidebar),
            listen: false,
          );
          final before = container.read(accountProvider);
          expect(before.value!.accounts.length, greaterThan(1));
          final copyButton = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Copy shielded address',
          );
          await tester.tap(
            find.byKey(const ValueKey('sidebar_accounts_button')),
          );
          await tester.pump(const Duration(milliseconds: 300));
          for (final account in before.value!.accounts.where(
            (account) => account.uuid != before.value!.activeAccountUuid,
          )) {
            await tester.tap(
              find.descendant(
                of: find.byKey(
                  ValueKey('sidebar_account_popover_row_${account.uuid}'),
                ),
                matching: copyButton,
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              copied.last,
              surface.key == 'Send'
                  ? (account.name == 'Savings'
                        ? kSendScreenFixtureOwnAccountAddress
                        : kSendScreenFixtureAddress)
                  : 'u1widgetbookhomeaddress2',
            );
          }
          expect(find.text('Shielded address copied'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('sidebar_accounts_button')),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.descendant(of: sidebar, matching: copyButton));
          await tester.pump(const Duration(milliseconds: 300));
          expect(copied.last, before.value!.activeAddress);
          expect(copied.length, before.value!.accounts.length);
          expect(container.read(accountProvider), same(before));
          if (surface.key == 'Send') {
            final savings = before.value!.accounts.firstWhere(
              (a) => a.name == 'Savings',
            );
            await tester.tap(
              find.byKey(const ValueKey('sidebar_accounts_button')),
            );
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(
              find.byKey(
                ValueKey('sidebar_account_popover_row_${savings.uuid}'),
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              container.read(accountProvider).requireValue.activeAddress,
              kSendScreenFixtureOwnAccountAddress,
            );
            expect(
              container.read(syncProvider).requireValue.accountUuid,
              savings.uuid,
            );
          }
          expect(tester.takeException(), isNull);
          await disposeTree(tester);
        },
      );
    }
    for (final action in {
      'Pay': '/pay',
      'Vote': '/voting',
      'Sign out': '/unlock',
      'Manage accounts': '/accounts',
      'Add account': '/add-account',
    }.entries) {
      // Pay is current on Pay and intentionally disabled in Send's fixture.
      if ((surface.key == 'Pay' || surface.key == 'Send') &&
          action.key == 'Pay') {
        continue;
      }
      testWidgets(
        '${surface.key} sidebar ${action.key} exits without host services',
        (tester) async {
          await pumpUseCase(
            tester,
            surface.value,
            knobs: {
              'Layout': wbLayoutLabel(WbLayout.desktop),
              'Pay in USDC': 'true',
            },
          );
          // Receive's QR renderer can keep scheduling frames; only the
          // sidebar needs to be ready for this navigation check.
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final sidebar = find.byType(AppMainSidebar);
          final context = tester.element(sidebar);
          final router = GoRouter.of(context);
          final container = ProviderScope.containerOf(context, listen: false);
          final accountBefore = container.read(accountProvider);
          expect(container.exists(chainUpgradeStatusProvider), isFalse);
          expect(container.exists(ironwoodActivationStoreProvider), isFalse);
          if (surface.key == 'Receive' || surface.key == 'Home') {
            expect(container.exists(swapStateProvider), isFalse);
          }
          if (action.value == '/accounts' || action.value == '/add-account') {
            await tester.tap(
              find.byKey(const ValueKey('sidebar_accounts_button')),
            );
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(
              find.byKey(
                ValueKey(
                  action.value == '/accounts'
                      ? 'sidebar_accounts_manage'
                      : 'sidebar_accounts_add',
                ),
              ),
            );
          } else {
            await tester.tap(
              find.descendant(of: sidebar, matching: find.text(action.key)),
            );
          }
          await tester.pumpAndSettle();
          expect(
            router.routerDelegate.currentConfiguration.uri.path,
            action.value,
          );
          expect(find.byType(AppMainSidebar), findsNothing);
          expect(find.textContaining(action.value), findsWidgets);
          expect(router.routerDelegate.currentConfiguration.error, isNull);
          if (surface.key == 'Activity' ||
              surface.key == 'Transaction detail' ||
              surface.key == 'Swap detail') {
            expect(find.text('Navigated to ${action.value}'), findsOneWidget);
          }
          expect(container.read(accountProvider), same(accountBefore));
          if (surface.key == 'Receive' || surface.key == 'Home') {
            expect(container.exists(swapStateProvider), isFalse);
          }
          expect(tester.takeException(), isNull);
          if (surface.key == 'Send') {
            await tester.tap(find.text('Back to send preview'));
            await tester.pumpAndSettle();
            expect(find.byType(AppMainSidebar), findsOneWidget);
            expect(
              router.routerDelegate.currentConfiguration.uri.path,
              '/send',
            );
          }
          await disposeTree(tester);
        },
      );
    }
  }
}
