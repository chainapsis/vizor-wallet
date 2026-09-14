import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/widgetbook/gallery/receive_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/home_activity_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/send_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/swap_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/pay_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'support/wb_gallery_harness.dart';

void main() {
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
  };
  for (final surface in surfaces.entries) {
    for (final action in {
      'Pay': '/pay',
      'Vote': '/voting',
      'Sign out': '/unlock',
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
          if (surface.key == 'Receive' || surface.key == 'Home') {
            expect(container.exists(swapStateProvider), isFalse);
          }
          await tester.tap(
            find.descendant(of: sidebar, matching: find.text(action.key)),
          );
          await tester.pumpAndSettle();
          expect(
            router.routerDelegate.currentConfiguration.uri.path,
            action.value,
          );
          expect(find.byType(AppMainSidebar), findsNothing);
          expect(find.textContaining(action.value), findsWidgets);
          expect(container.read(accountProvider), same(accountBefore));
          if (surface.key == 'Receive' || surface.key == 'Home') {
            expect(container.exists(swapStateProvider), isFalse);
          }
          expect(tester.takeException(), isNull);
          if (surface.key == 'Send') {
            await tester.tap(find.text('Back to send preview'));
            await tester.pumpAndSettle();
            expect(find.byType(AppMainSidebar), findsOneWidget);
            expect(router.routerDelegate.currentConfiguration.uri.path, '/send');
          }
          await disposeTree(tester);
        },
      );
    }
  }
}
