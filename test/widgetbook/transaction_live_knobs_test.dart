import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';
import 'package:zcash_wallet/src/features/address_book/widgets/address_book_contact_picker_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_address_edit_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_selector_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_slippage_modal.dart';
import 'package:zcash_wallet/widgetbook/gallery/home_activity_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/receive_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/swap_gallery.dart';
import 'package:zcash_wallet/widgetbook/receive_screen_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_compare_layouts.dart';
import 'package:zcash_wallet/widgetbook/support/wb_design_status.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/swap_use_cases.dart';

// Desktop-lane host tests, including mobile widget previews under desktop
// tokens. Unlike pumpUseCase, each test mounts Widgetbook exactly once and
// changes its real query state without manually replacing the fixture tree.
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

  testWidgets('live Pool changes reapply the receive address', (tester) async {
    final host = await _LiveHost.mount(tester, buildReceiveScreenGalleryCase);
    for (final pool in [
      ReceivePoolCase.shielded,
      ReceivePoolCase.transparent,
      ReceivePoolCase.shielded,
    ]) {
      await host.set('Pool', receivePoolCaseLabel(pool));
      expect(
        tester
            .widget<ReceiveAddressLine>(find.byType(ReceiveAddressLine))
            .address,
        pool == ReceivePoolCase.shielded
            ? kReceiveScreenShieldedAddress
            : kReceiveScreenTransparentAddress,
      );
    }
    await host.dispose();
  });

  testWidgets('live mobile receipt knobs replace detail and message state', (
    tester,
  ) async {
    final host = await _LiveHost.mount(
      tester,
      buildActivityTransactionStatusGalleryCase,
      layout: WbLayout.mobile,
    );
    expect(_text('Sent successfully'), findsOneWidget);
    await host.set('Kind', 'Received');
    expect(_text('Received'), findsWidgets);
    expect(_text('Sent successfully'), findsNothing);
    await host.set('Phase', 'Pending');
    expect(_text('Receiving...'), findsOneWidget);
    await host.set('Phase', 'Succeeded');
    await host.set('Counterparty', 'Unknown');
    expect(_text('Unknown sender'), findsOneWidget);
    await host.set('Counterparty', 'Contact');
    expect(_text('Mike'), findsOneWidget);
    expect(_text('Unknown sender'), findsNothing);
    await host.set('Message', 'Expanded');
    expect(_text('Thanks for lunch, see you next week!'), findsOneWidget);
    expect(_text('Thanks for lunch,...'), findsNothing);
    await host.set('Message', 'Collapsed');
    expect(_text('Thanks for lunch,...'), findsOneWidget);
    expect(_text('Thanks for lunch, see you next week!'), findsNothing);
    await host.set('Message', 'None');
    expect(_text('Thanks for lunch, see you next week!'), findsNothing);
    expect(_text('Thanks for lunch,...'), findsNothing);
    expect(_text('Message'), findsNothing);
    await host.dispose();
  });

  testWidgets('live composer State changes replace init-only state', (
    tester,
  ) async {
    final host = await _LiveHost.mount(tester, buildSwapPageGalleryCase);
    await host.set(
      'State',
      swapComposerFixtureLabel(SwapComposerFixture.payAmountActive),
    );
    expect(_text('Add refund address'), findsWidgets);
    await host.set(
      'State',
      swapComposerFixtureLabel(SwapComposerFixture.overAvailableBalance),
    );
    expect(_text('Not enough ZEC'), findsWidgets);
    expect(_text('Add refund address'), findsNothing);
    await host.set(
      'State',
      swapComposerFixtureLabel(SwapComposerFixture.payAmountActive),
    );
    expect(_text('Add refund address'), findsWidgets);
    expect(_text('Not enough ZEC'), findsNothing);
    await host.dispose();
  });

  testWidgets('live Modal changes rerun swap mount triggers', (tester) async {
    final host = await _LiveHost.mount(
      tester,
      buildSwapPageGalleryCase,
      knobs: {'Frame': swapComposerFrameLabel(SwapComposerFrame.screen)},
    );
    final modals = <SwapScreenOverlay, Type>{
      SwapScreenOverlay.assetSelector: SwapAssetSelectorModal,
      SwapScreenOverlay.addressEditor: SwapAddressEditModal,
      SwapScreenOverlay.contactPicker: AddressBookContactPickerModal,
      SwapScreenOverlay.slippage: SwapSlippageModal,
    };
    for (final entry in modals.entries) {
      await host.set('Modal', swapScreenOverlayLabel(entry.key));
      expect(find.byType(entry.value), findsOneWidget);
      await host.set('Modal', swapScreenOverlayLabel(SwapScreenOverlay.none));
      for (final type in modals.values) {
        expect(find.byType(type), findsNothing);
      }
    }
    await host.dispose();
  });

  testWidgets('live review State changes recreate the initial route', (
    tester,
  ) async {
    final host = await _LiveHost.mount(tester, buildSwapReviewGalleryCase);
    for (final state in [
      SwapReviewScreenCase.payment,
      SwapReviewScreenCase.expired,
      SwapReviewScreenCase.payment,
    ]) {
      await host.set('State', swapReviewScreenCaseLabel(state));
      expect(
        _text('Confirm payment'),
        state == SwapReviewScreenCase.payment ? findsWidgets : findsNothing,
      );
      if (state == SwapReviewScreenCase.expired) {
        expect(_text('Review again'), findsWidgets);
      }
    }
    await host.dispose();
  });
}

class _LiveHost {
  _LiveHost(this.tester);
  final WidgetTester tester;
  late WidgetbookState state;

  static Future<_LiveHost> mount(
    WidgetTester tester,
    WidgetBuilder builder, {
    WbLayout layout = WbLayout.desktop,
    Map<String, String> knobs = const {},
  }) async {
    final host = _LiveHost(tester);
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final route = Uri(
      path: '/',
      queryParameters: {
        'path': 'probe/surface',
        'knobs': FieldCodec.encodeQueryGroup({
          'Layout': wbLayoutLabel(layout),
          ...knobs,
        }),
      },
    );
    await tester.pumpWidget(
      Widgetbook.material(
        initialRoute: route.toString(),
        addons: [
          ThemeAddon<AppThemeData>(
            themes: [WidgetbookTheme(name: 'Dark', data: AppThemeData.dark)],
            themeBuilder: (_, theme, child) =>
                AppTheme(data: theme, child: child),
          ),
          WbDesignStatusAddon(),
          AlignmentAddon(),
          WbCompareLayoutsAddon(),
        ],
        directories: [
          WidgetbookComponent(
            name: 'Probe',
            useCases: [
              WidgetbookUseCase(
                name: 'Surface',
                builder: (context) {
                  host.state = WidgetbookState.of(context);
                  return KeyedSubtree(
                    key: const ValueKey('live-fixture'),
                    child: builder(context),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
    await host.pump();
    return host;
  }

  Future<void> set(String field, String value) async {
    state.updateQueryField(group: 'knobs', field: field, value: value);
    await pump();
  }

  Future<void> pump() async {
    // Some fixtures animate indefinitely; bounded frames also allow chained
    // mount callbacks (address editor -> contact picker) to finish.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> dispose() => tester.pumpWidget(const SizedBox.shrink());
}

// Exclude knob labels in the Widgetbook chrome from visible-output assertions.
Finder _text(String value) => find.descendant(
  of: find.byKey(const ValueKey('live-fixture')),
  matching: find.text(value),
);
