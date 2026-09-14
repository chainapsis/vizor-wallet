import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart'
    show AssetImage, GestureDetector, Image, ValueKey, WidgetBuilder;
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/features/activity/widgets/received_receipt_view.dart';
import 'package:zcash_wallet/src/features/activity/widgets/shielded_receipt_view.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/features/activity/screens/swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/home_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/widgetbook/activity_use_cases.dart';
import 'package:zcash_wallet/widgetbook/gallery/home_activity_gallery.dart';
import 'package:zcash_wallet/widgetbook/home_activity_use_cases.dart';
import 'package:zcash_wallet/widgetbook/received_receipt_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_fake_scanner_platform.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

const _transparentStripKey = ValueKey('home_desktop_transparent_balance_strip');
const _mobileSendKey = ValueKey('mobile_home_send');

// The receipt's message fixture, truncated by the detail card at 18 chars.
const _fullMemo = 'Thanks for lunch, see you next week!';
const _collapsedMemo = 'Thanks for lunch,...';

// Desktop lane only: untagged, so `--tags mobile` never selects this file. The
// fixed-width home fixtures overflow when compiled with the mobile token set.
void main() {
  // Real fonts: the fallback test font is monospaced, which overflows the
  // fixed-width desktop home fixtures.
  setUpAll(_loadAppFonts);
  // The mobile shielding case installs the camera fake for its scanning
  // stage; nothing else in this file should inherit it.
  tearDown(WbFakeMobileScannerPlatform.reset);

  testWidgets('Home failure settings opens an isolated destination', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'Notice': homeNoticeLabel(HomeNoticeKind.syncFailureEndpointSettings),
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Navigated to /settings/endpoint'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  testWidgets('Home Tor Retry remains isolated and repeatable', (tester) async {
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
          'Network': homeNetworkRouteLabel(HomeNetworkRoute.torBlocked),
      },
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await disposeTree(tester);
  });

  testWidgets('Home sync Retry clears only the preview failure', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'Notice': homeNoticeLabel(HomeNoticeKind.syncFailure),
      },
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    final before = container.read(syncProvider).requireValue;
    expect(find.text('Network connection lost.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    final after = container.read(syncProvider).requireValue;
    expect(after.failure, isNull);
    expect(after.error, isNull);
    expect(after.isSyncing, before.isSyncing);
    expect(after.orchardBalance, before.orchardBalance);
    expect(find.text('Network connection lost.'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  for (final layout in WbLayout.values) {
    testWidgets('${layout.name} Home content Pay avoids host services', (
      tester,
    ) async {
      await pumpUseCase(
        tester,
        buildHomeScreenGalleryCase,
        knobs: {
          'Layout': wbLayoutLabel(layout),
          'Pay in USDC': 'true',
          'Balance': homeBalanceLabel(HomeBalanceAmount.funded),
        },
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final screen = layout == WbLayout.mobile
          ? find.byType(MobileHomeScreen)
          : find.byType(HomeScreen);
      final context = tester.element(screen);
      final router = GoRouter.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      expect(container.exists(swapStateProvider), isFalse);
      for (var visit = 0; visit < 2; visit++) {
        await tester.tap(
          layout == WbLayout.mobile
              ? find.byKey(const ValueKey('mobile_home_pay'))
              : find.byKey(const ValueKey('home_desktop_pay_button')),
        );
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.last.route.path,
          '/pay',
        );
        expect(router.routerDelegate.currentConfiguration.error, isNull);
        expect(find.text('Navigated to /pay'), findsOneWidget);
        expect(container.read(swapStateProvider).payMode, isTrue);
        expect(container.exists(paySelectedAssetStoreProvider), isFalse);
        expect(container.exists(swapComposerPreferencesStoreProvider), isFalse);
        expect(tester.takeException(), isNull);
        router.pop();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(screen, findsOneWidget);
      }
      await disposeTree(tester);
    });
  }

  testWidgets('both Home shield actions use the isolated preview runner', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await pumpUseCase(
        tester,
        buildHomeScreenGalleryCase,
        knobs: {
          'Layout': wbLayoutLabel(layout),
          'Balance': homeBalanceLabel(HomeBalanceAmount.fundedTransparent),
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(
        layout == WbLayout.mobile
            ? find.byKey(const ValueKey('mobile_home_shield_balance_button'))
            : find.byKey(const ValueKey('home_shield_balance_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text(shieldBalancePendingBroadcastMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeTree(tester);
    }
  });

  // Named rather than implied by the compiled lane, so a mobile-lane run of
  // this file would still sweep the layout the case name says.
  final desktopLayout = {'Layout': wbLayoutLabel(WbLayout.desktop)};
  final mobileLayout = {'Layout': wbLayoutLabel(WbLayout.mobile)};

  testWidgets('every home/activity gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(homeActivityGalleryNodes).toList();
    expect(useCases.length, 14);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }

    // The Layout knob opens on the compiled lane, so the folded cases' other
    // half needs its own default build.
    for (final builder in const <WidgetBuilder>[
      buildHomeScreenGalleryCase,
      buildActivityTransactionStatusGalleryCase,
      buildHomeKeystoneShieldGalleryCase,
    ]) {
      await pumpUseCase(tester, builder, knobs: mobileLayout);
      expect(tester.takeException(), isNull, reason: 'Mobile');
    }
    await disposeTree(tester);
  });

  testWidgets('home renders a different screen per layout', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildHomeScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('home activity rows inject a wallet-DB-free detail loader', (
    tester,
  ) async {
    await pumpUseCase(tester, buildHomeScreenGalleryCase, knobs: desktopLayout);
    expect(
      tester
          .widget<HomeScreen>(find.byType(HomeScreen))
          .transactionDetailLoader,
      isNotNull,
    );

    await pumpUseCase(tester, buildHomeScreenGalleryCase, knobs: mobileLayout);
    expect(
      tester
          .widget<MobileHomeScreen>(find.byType(MobileHomeScreen))
          .transactionDetailLoader,
      isNotNull,
    );
    await disposeTree(tester);
  });

  testWidgets('home registers a different knob set per layout', (tester) async {
    const shared = <String>[
      'Layout',
      'Balance',
      'Activity',
      'Sync',
      'Network',
      '24h change',
      'Privacy mode',
    ];
    const desktopOnly = <String>[
      'Wallet',
      'Notice',
      'Shield action',
      'Window height',
      'Pay in USDC',
    ];
    const mobileOnly = <String>[
      'Account',
      'Voting entry',
      'Send',
      'Accounts sheet',
      'Frame',
      'Keep awake prompt',
      'Pay entry',
    ];

    final desktop = await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: desktopLayout,
    );
    expect(desktop.knobs.keys, containsAll([...shared, ...desktopOnly]));
    for (final knob in mobileOnly) {
      expect(desktop.knobs.keys, isNot(contains(knob)), reason: knob);
    }

    final mobile = await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: mobileLayout,
    );
    expect(mobile.knobs.keys, containsAll([...shared, ...mobileOnly]));
    for (final knob in desktopOnly) {
      expect(mobile.knobs.keys, isNot(contains(knob)), reason: knob);
    }
    await disposeTree(tester);
  });

  testWidgets('desktop home sweeps every axis distinctly', (tester) async {
    Future<void> sweep(
      String label,
      List<String> options, {
      Map<String, String> otherKnobs = const {},
    }) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildHomeScreenGalleryCase,
        label: label,
        optionLabels: options,
        otherKnobs: {...desktopLayout, ...otherKnobs},
      );
    }

    await sweep(
      'Wallet',
      HomeWalletState.values.map(homeWalletStateLabel).toList(),
    );
    await sweep(
      'Balance',
      homeBalanceOptions(WbLayout.desktop).map(homeBalanceLabel).toList(),
    );
    await sweep(
      'Activity',
      homeActivityFeedOptions(
        WbLayout.desktop,
      ).map(homeActivityFeedLabel).toList(),
    );
    await sweep(
      'Sync',
      homeSyncProgressOptions(
        WbLayout.desktop,
      ).map(homeSyncProgressLabel).toList(),
    );
    await sweep(
      'Network',
      HomeNetworkRoute.values.map(homeNetworkRouteLabel).toList(),
    );
    await sweep('Notice', HomeNoticeKind.values.map(homeNoticeLabel).toList());
    await sweep(
      '24h change',
      HomePriceChange.values.map(homePriceChangeLabel).toList(),
    );
    await sweep('Pay in USDC', const ['true', 'false']);
    await sweep('Privacy mode', const ['true', 'false']);
    // The shield action only renders on the transparent strip, and the empty
    // illustration is the only content the window height changes.
    await sweep(
      'Shield action',
      HomeShieldAction.values.map(homeShieldActionLabel).toList(),
      otherKnobs: {
        'Balance': homeBalanceLabel(HomeBalanceAmount.fundedTransparent),
      },
    );
    await sweep(
      'Window height',
      HomeWindowHeight.values.map(homeWindowHeightLabel).toList(),
      otherKnobs: {'Activity': homeActivityFeedLabel(HomeActivityFeed.empty)},
    );
  });

  testWidgets('desktop home shows the states its knobs name', (tester) async {
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Balance': homeBalanceLabel(HomeBalanceAmount.zero),
      },
    );
    expect(find.text('Receive your first ZEC'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {...desktopLayout, 'Pay in USDC': 'true'},
    );
    // The pay entry is an icon-only pill; its label is semantics only.
    expect(
      find.byKey(const ValueKey('home_desktop_pay_button')),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Notice': homeNoticeLabel(HomeNoticeKind.passwordRotation),
      },
    );
    expect(
      find.text(
        "We couldn't verify the previous password change. "
        'Try again or restart Vizor.',
      ),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Notice': homeNoticeLabel(HomeNoticeKind.syncFailure),
      },
    );
    expect(find.text('Network connection lost.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Activity': homeActivityFeedLabel(HomeActivityFeed.empty),
      },
    );
    expect(find.text('No activity, yet...'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Sync': homeSyncProgressLabel(HomeSyncProgress.importingPartway),
      },
    );
    expect(find.text("We're importing\nyour wallet..."), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Wallet': homeWalletStateLabel(HomeWalletState.error),
      },
    );
    expect(find.textContaining('Something went wrong.'), findsOneWidget);

    // The transparent strip only exists with a transparent balance, and the
    // shield action only when the balance can be shielded.
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Balance': homeBalanceLabel(HomeBalanceAmount.fundedTransparent),
      },
    );
    expect(find.byKey(_transparentStripKey), findsOneWidget);
    expect(find.text('Shield now'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...desktopLayout,
        'Balance': homeBalanceLabel(HomeBalanceAmount.fundedTransparent),
        'Shield action': homeShieldActionLabel(HomeShieldAction.hidden),
      },
    );
    expect(find.byKey(_transparentStripKey), findsOneWidget);
    expect(find.text('Shield now'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('desktop window height crosses the empty-activity threshold', (
    tester,
  ) async {
    Future<double> restCharacterHeight(String height) async {
      await pumpUseCase(
        tester,
        buildHomeScreenGalleryCase,
        knobs: {
          ...desktopLayout,
          'Activity': homeActivityFeedLabel(HomeActivityFeed.empty),
          'Window height': height,
        },
      );
      return tester
          .widget<Image>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Image &&
                  widget.image is AssetImage &&
                  (widget.image as AssetImage).assetName ==
                      'assets/illustrations/home_rest_character.png',
            ),
          )
          .height!;
    }

    // 192 is the full illustration; the compact branch floors it at 64.
    expect(
      await restCharacterHeight(homeWindowHeightLabel(HomeWindowHeight.full)),
      192,
    );
    expect(
      await restCharacterHeight(
        homeWindowHeightLabel(HomeWindowHeight.compact),
      ),
      lessThan(192),
    );
    await disposeTree(tester);
  });

  testWidgets('mobile home shows the states its knobs name', (tester) async {
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Balance': homeBalanceLabel(HomeBalanceAmount.zero),
      },
    );
    expect(find.text('Receive your first ZEC'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Account': homeAccountKindLabel(HomeAccountKind.keystone),
      },
    );
    expect(find.text('Keystone Vault'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Voting entry': homeMobileVotingEntryLabel(
          HomeMobileVotingEntry.hidden,
        ),
      },
    );
    expect(find.text('Coinholder voting'), findsNothing);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Send': homeMobileSendGateLabel(HomeMobileSendGate.blockedByMigration),
      },
    );
    expect(
      tester.widget<AppButton>(find.byKey(_mobileSendKey)).onPressed,
      isNull,
    );

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Network': homeNetworkRouteLabel(HomeNetworkRoute.torBlocked),
      },
    );
    expect(find.text("Tor couldn't connect..."), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile home sweeps every axis distinctly', (tester) async {
    Future<void> sweep(String label, List<String> options) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildHomeScreenGalleryCase,
        label: label,
        optionLabels: options,
        otherKnobs: mobileLayout,
      );
    }

    // The shared axes, trimmed to the options the mobile layout offers.
    await sweep(
      'Balance',
      homeBalanceOptions(WbLayout.mobile).map(homeBalanceLabel).toList(),
    );
    await sweep(
      'Activity',
      homeActivityFeedOptions(
        WbLayout.mobile,
      ).map(homeActivityFeedLabel).toList(),
    );
    await sweep(
      'Sync',
      homeSyncProgressOptions(
        WbLayout.mobile,
      ).map(homeSyncProgressLabel).toList(),
    );
    await sweep(
      'Network',
      HomeNetworkRoute.values.map(homeNetworkRouteLabel).toList(),
    );
    await sweep(
      'Account',
      HomeAccountKind.values.map(homeAccountKindLabel).toList(),
    );
    await sweep(
      'Voting entry',
      HomeMobileVotingEntry.values.map(homeMobileVotingEntryLabel).toList(),
    );
    await sweep(
      'Send',
      HomeMobileSendGate.values.map(homeMobileSendGateLabel).toList(),
    );
    await sweep(
      'Frame',
      HomeMobileFrame.values.map(homeMobileFrameLabel).toList(),
    );
    await sweep(
      '24h change',
      HomePriceChange.values.map(homePriceChangeLabel).toList(),
    );
    await sweep('Pay entry', const ['true', 'false']);
    await sweep('Privacy mode', const ['true', 'false']);
  });

  testWidgets('mobile home accounts sheet option opens the switcher', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Accounts sheet': homeMobileAccountsSheetLabel(
          HomeMobileAccountsSheet.open,
        ),
      },
    );
    // Bounded pumps, not pumpAndSettle: the home Pay coin float loops forever.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Other accounts'), findsOneWidget);
    expect(find.text('Manage accounts'), findsOneWidget);

    // The closed option is the knob's other half: without this the sheet
    // could open unconditionally and the test would still pass.
    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Accounts sheet': homeMobileAccountsSheetLabel(
          HomeMobileAccountsSheet.closed,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Other accounts'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('mobile home opens the keep-awake prompt sheet', (tester) async {
    const sheetKey = ValueKey('mobile_sync_keep_awake_prompt_sheet');

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Keep awake prompt': homeMobileKeepAwakePromptLabel(
          HomeMobileKeepAwakePrompt.shown,
        ),
      },
    );
    // Bounded pumps, not pumpAndSettle: the home Pay coin float loops forever.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byKey(sheetKey), findsOneWidget);
    expect(find.text('Keep screen awake'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildHomeScreenGalleryCase,
      knobs: {
        ...mobileLayout,
        'Keep awake prompt': homeMobileKeepAwakePromptLabel(
          HomeMobileKeepAwakePrompt.hidden,
        ),
      },
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(sheetKey), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('shielding messages come from the production mappers', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildHomeShieldMessageGalleryCase,
      label: 'Message',
      optionLabels: HomeShieldMessage.values
          .map(homeShieldMessageLabel)
          .toList(),
    );

    // The mapper, not a restated literal: a reworded message must reach here.
    await pumpUseCase(
      tester,
      buildHomeShieldMessageGalleryCase,
      knobs: {
        'Message': homeShieldMessageLabel(HomeShieldMessage.balanceTooSmall),
      },
    );
    expect(
      find.text(friendlyShieldBalanceError(Exception('insufficient funds'))),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('activity screen renders a different screen per layout', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('gift card detail covers both kinds', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityGiftCardDetailGalleryCase,
      label: 'Kind',
      optionLabels: ActivityGiftCardKind.values
          .map(activityGiftCardKindLabel)
          .toList(),
    );
  });

  testWidgets('received receipt sweeps every axis distinctly', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityReceivedReceiptGalleryCase,
      label: 'Status',
      optionLabels: ReceivedReceiptStatus.values
          .map(activityReceiptStatusLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityReceivedReceiptGalleryCase,
      label: 'From',
      optionLabels: ReceivedReceiptFromSource.values
          .map(activityReceiptFromLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityReceivedReceiptGalleryCase,
      label: 'Received on',
      optionLabels: ReceivedReceiptReceivingPool.values
          .map(activityReceiptPoolLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityReceivedReceiptGalleryCase,
      label: 'Message',
      optionLabels: ActivityReceiptMessage.values
          .map(activityReceiptMessageLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityReceivedReceiptGalleryCase,
      label: 'Network fee',
      optionLabels: const ['true', 'false'],
    );
  });

  testWidgets('received receipt delegates keep their fixture parameters', (
    tester,
  ) async {
    // The in-progress fixture is the one the extraction could break: it is the
    // only builder with no memo, no fee row and a non-default status.
    await pumpUseCase(tester, buildReceivedReceiptInProgressUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Receive in progress...'), findsOneWidget);
    expect(find.text('Network fee'), findsNothing);
    expect(find.text('Message'), findsNothing);

    // The known-sender fixture is the only one with a contact recipient.
    await pumpUseCase(tester, buildReceivedReceiptKnownSenderUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('Received successfully'), findsOneWidget);

    // 'Default' is still an alias of the transparent-to-transparent fixture.
    await pumpUseCase(tester, buildReceivedReceiptUseCase);
    final aliasFingerprint = await useCaseFingerprint(tester);
    await pumpUseCase(
      tester,
      buildReceivedReceiptTransparentToTransparentUseCase,
    );
    expect(await useCaseFingerprint(tester), aliasFingerprint);
    await disposeTree(tester);
  });

  testWidgets('received receipt renders its failed and expanded states', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildActivityReceivedReceiptGalleryCase,
      knobs: {
        'Status': activityReceiptStatusLabel(ReceivedReceiptStatus.failed),
      },
    );
    expect(find.text('Receive failed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityReceivedReceiptGalleryCase,
      knobs: {
        'Message': activityReceiptMessageLabel(ActivityReceiptMessage.expanded),
      },
    );
    // The expanded memo replaces the truncated value with a Collapse action.
    expect(find.text('Collapse'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('activity screen sweeps every axis distinctly', (tester) async {
    Future<void> sweep(
      String label,
      List<String> options, {
      Map<String, String> otherKnobs = const {},
    }) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildActivityScreenGalleryCase,
        label: label,
        optionLabels: options,
        otherKnobs: otherKnobs,
      );
    }

    await sweep(
      'State',
      ActivityScreenState.values.map(activityScreenStateLabel).toList(),
    );
    await sweep(
      'Rows',
      ActivityRowSet.values.map(activityRowSetLabel).toList(),
    );
    await sweep('Privacy mode', const ['true', 'false']);
    // The desktop screen is the one that gates swap rows on the flag, and it
    // only has rows to hide when the feed carries a swap.
    await sweep(
      'Swap feature',
      const ['true', 'false'],
      otherKnobs: {'Rows': activityRowSetLabel(ActivityRowSet.withSwapRows)},
    );
    // The phone has no 'no account' branch: it renders that as an empty feed.
    await sweep(
      'State',
      const ['Rows', 'Loading', 'No activity', 'Failed to load'],
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
  });

  testWidgets('desktop activity screen shows the states its knobs name', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {'State': activityScreenStateLabel(ActivityScreenState.loading)},
    );
    expect(find.text('Loading activity...'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {'State': activityScreenStateLabel(ActivityScreenState.empty)},
    );
    expect(find.text('No activity yet'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {'State': activityScreenStateLabel(ActivityScreenState.error)},
    );
    expect(find.text('Activity could not be loaded.'), findsOneWidget);

    // Fixed past timestamps, so the month section title never moves.
    await pumpUseCase(tester, buildActivityScreenGalleryCase);
    expect(find.text('April 2025'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {'Rows': activityRowSetLabel(ActivityRowSet.giftCards)},
    );
    expect(find.text('Redeemed a gift card'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {'Rows': activityRowSetLabel(ActivityRowSet.withSwapRows)},
    );
    expect(find.text('Swapped'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {
        'Rows': activityRowSetLabel(ActivityRowSet.withSwapRows),
        'Swap feature': 'false',
      },
    );
    expect(find.text('Swapped'), findsNothing);

    // The payout row is absorbed: it renders only as the swap group's child.
    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {'Rows': activityRowSetLabel(ActivityRowSet.swapLegAbsorbed)},
    );
    expect(find.text('Swapped'), findsOneWidget);
    expect(find.text('Received ZEC'), findsOneWidget);
    expect(find.text('Received'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('mobile activity screen shows the states its knobs name', (
    tester,
  ) async {
    final mobile = {'Layout': wbLayoutLabel(WbLayout.mobile)};

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {
        ...mobile,
        'State': activityScreenStateLabel(ActivityScreenState.error),
      },
    );
    expect(
      find.text("Couldn't load activity. Try again in a moment."),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {
        ...mobile,
        'State': activityScreenStateLabel(ActivityScreenState.empty),
      },
    );
    expect(find.text('No activity yet'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityScreenGalleryCase,
      knobs: {...mobile, 'Rows': activityRowSetLabel(ActivityRowSet.giftCards)},
    );
    expect(find.text('Redeemed a gift card'), findsOneWidget);
    expect(find.text('April 2025'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('activity transaction rows navigate in both layouts', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await pumpUseCase(
        tester,
        buildActivityScreenGalleryCase,
        knobs: {'Layout': wbLayoutLabel(layout)},
      );
      await tester.tap(find.text('Sent').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Navigated to /activity/tx/'),
        findsOneWidget,
        reason: wbLayoutLabel(layout),
      );
    }
    await disposeTree(tester);
  });

  testWidgets('transaction status splits its load axis per layout', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityTransactionStatusGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    final desktop = await pumpUseCase(
      tester,
      buildActivityTransactionStatusGalleryCase,
      knobs: desktopLayout,
    );
    expect(desktop.knobs.keys, contains('Load'));
    expect(desktop.knobs.keys, isNot(contains('Refresh failed')));

    final mobile = await pumpUseCase(
      tester,
      buildActivityTransactionStatusGalleryCase,
      knobs: mobileLayout,
    );
    expect(mobile.knobs.keys, contains('Refresh failed'));
    expect(mobile.knobs.keys, isNot(contains('Load')));
    await disposeTree(tester);
  });

  testWidgets('transaction status previews keep explorer launches in memory', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildActivityTransactionStatusGalleryCase,
      knobs: desktopLayout,
    );
    expect(
      tester
          .widget<ActivityTransactionStatusScreen>(
            find.byType(ActivityTransactionStatusScreen),
          )
          .explorerLauncher,
      isNotNull,
    );
    await tester.tap(find.text('Tx ID'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await pumpUseCase(
      tester,
      buildActivityTransactionStatusGalleryCase,
      knobs: mobileLayout,
    );
    expect(
      tester
          .widget<MobileTransactionStatusScreen>(
            find.byType(MobileTransactionStatusScreen),
          )
          .explorerLauncher,
      isNotNull,
    );
    await tester.tap(find.text('Tx ID'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  testWidgets('swap detail previews keep explorer launches in memory', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildActivitySwapDetailScreenGalleryCase,
      knobs: {...desktopLayout, 'Status': 'Complete'},
    );
    expect(
      tester
          .widget<SwapActivityDetailScreen>(
            find.byType(SwapActivityDetailScreen),
          )
          .launchExternalUri,
      isNotNull,
    );

    await pumpUseCase(
      tester,
      buildActivitySwapDetailScreenGalleryCase,
      knobs: {...mobileLayout, 'Status': 'Complete'},
    );
    expect(
      tester
          .widget<MobileSwapActivityDetailScreen>(
            find.byType(MobileSwapActivityDetailScreen),
          )
          .launchExternalUri,
      isNotNull,
    );
    await disposeTree(tester);
  });

  testWidgets('mobile transaction status sweeps every axis distinctly', (
    tester,
  ) async {
    Future<void> sweep(
      String label,
      List<String> options, {
      Map<String, String> otherKnobs = const {},
    }) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildActivityTransactionStatusGalleryCase,
        label: label,
        optionLabels: options,
        otherKnobs: {...mobileLayout, ...otherKnobs},
      );
    }

    await sweep(
      'Kind',
      TxStatusKind.values.map(activityTxStatusKindLabel).toList(),
    );
    await sweep(
      'Phase',
      TxStatusPhase.values.map(activityTxStatusPhaseLabel).toList(),
    );
    // Only an incoming receipt names every counterparty: a sent receipt with
    // no resolved address drops the row instead of naming the sender.
    await sweep(
      'Counterparty',
      TxStatusCounterparty.values
          .map(activityTxStatusCounterpartyLabel)
          .toList(),
      otherKnobs: {'Kind': activityTxStatusKindLabel(TxStatusKind.received)},
    );
    await sweep('Refresh failed', const ['true', 'false']);
    await sweep('Privacy mode', const ['true', 'false']);
    // The Message axis is asserted per option in the state test below: the
    // expanded option lands a frame after the fingerprint sweep reads pixels.
  });

  testWidgets('mobile transaction status shows the states its knobs name', (
    tester,
  ) async {
    Future<void> pumpStatus(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildActivityTransactionStatusGalleryCase,
        knobs: {...mobileLayout, ...knobs},
      );
      // The expanded message is applied from a post-frame callback, so the
      // receipt needs one more frame than the default pump gives it.
      await tester.pump();
      await tester.pump();
    }

    String kind(TxStatusKind value) => activityTxStatusKindLabel(value);
    String phase(TxStatusPhase value) => activityTxStatusPhaseLabel(value);
    String party(TxStatusCounterparty value) =>
        activityTxStatusCounterpartyLabel(value);

    await pumpStatus({'Phase': phase(TxStatusPhase.pending)});
    expect(find.text('Sending...'), findsOneWidget);

    await pumpStatus({'Phase': phase(TxStatusPhase.failed)});
    expect(find.text('Send failed'), findsOneWidget);

    // 'Receiving' is not a kind of its own: it is a received tx still pending.
    await pumpStatus({
      'Kind': kind(TxStatusKind.received),
      'Phase': phase(TxStatusPhase.pending),
    });
    expect(find.text('Receiving...'), findsOneWidget);

    // 'Shielded' is both the receipt title and the destination pool tag.
    await pumpStatus({'Kind': kind(TxStatusKind.shielded)});
    expect(find.text('Shielded'), findsWidgets);
    expect(find.text('Shielded balance'), findsOneWidget);
    expect(find.text('From transparent balance'), findsOneWidget);

    await pumpStatus({'Kind': kind(TxStatusKind.migration)});
    expect(find.text('Migrated to Ironwood'), findsOneWidget);
    await pumpStatus({
      'Kind': kind(TxStatusKind.migration),
      'Phase': phase(TxStatusPhase.pending),
    });
    expect(find.text('Migrating to Ironwood...'), findsOneWidget);
    await pumpStatus({
      'Kind': kind(TxStatusKind.migration),
      'Phase': phase(TxStatusPhase.failed),
    });
    expect(find.text('Migration failed'), findsOneWidget);

    await pumpStatus({'Kind': kind(TxStatusKind.giftCard)});
    expect(find.text('Created a gift card'), findsOneWidget);

    await pumpStatus({'Counterparty': party(TxStatusCounterparty.contact)});
    expect(find.text('Mike'), findsOneWidget);

    await pumpStatus({'Counterparty': party(TxStatusCounterparty.ownAccount)});
    expect(find.text('Account Name'), findsOneWidget);

    // A sent tx with no resolved address keeps the amount row alone.
    await pumpStatus({'Counterparty': party(TxStatusCounterparty.unknown)});
    expect(find.text('To'), findsNothing);

    await pumpStatus({
      'Kind': kind(TxStatusKind.received),
      'Counterparty': party(TxStatusCounterparty.unknown),
    });
    expect(find.text('Unknown sender'), findsOneWidget);

    await pumpStatus({
      'Kind': kind(TxStatusKind.received),
      'Counterparty': party(TxStatusCounterparty.shieldedSender),
    });
    expect(find.text('Shielded sender'), findsOneWidget);

    await pumpStatus({
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.none),
    });
    expect(find.text('Message'), findsNothing);

    await pumpStatus({
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.collapsed),
    });
    expect(find.text('Message'), findsOneWidget);
    expect(find.text(_collapsedMemo), findsOneWidget);
    expect(find.text(_fullMemo), findsNothing);

    // The expanded option taps the receipt's own toggle, which swaps the
    // truncated value line for the full message below it.
    await pumpStatus({
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.expanded),
    });
    expect(find.text(_collapsedMemo), findsNothing);
    expect(find.text(_fullMemo), findsOneWidget);

    await pumpStatus({'Refresh failed': 'true'});
    expect(
      find.text('Latest transaction status could not be refreshed.'),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('desktop transaction status sweeps every axis distinctly', (
    tester,
  ) async {
    Future<void> sweep(
      String label,
      List<String> options, {
      Map<String, String> otherKnobs = const {},
    }) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildActivityTransactionStatusGalleryCase,
        label: label,
        optionLabels: options,
        otherKnobs: {...desktopLayout, ...otherKnobs},
      );
    }

    await sweep(
      'Kind',
      TxStatusKind.values.map(activityTxStatusKindLabel).toList(),
    );
    await sweep(
      'Phase',
      TxStatusPhase.values.map(activityTxStatusPhaseLabel).toList(),
    );
    // Only an incoming receipt names every counterparty: a sent receipt with
    // no resolved address drops the row instead of naming the sender.
    await sweep(
      'Counterparty',
      TxStatusCounterparty.values
          .map(activityTxStatusCounterpartyLabel)
          .toList(),
      otherKnobs: {'Kind': activityTxStatusKindLabel(TxStatusKind.received)},
    );
    await sweep(
      'Load',
      TxStatusLoad.values.map(activityTxStatusLoadLabel).toList(),
    );
    await sweep('Privacy mode', const ['true', 'false']);
    // The Message axis is asserted per option in the state test below: the
    // expanded option lands a frame after the fingerprint sweep reads pixels.
  });

  testWidgets('desktop transaction status shows the states its knobs name', (
    tester,
  ) async {
    Future<void> pumpStatus(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildActivityTransactionStatusGalleryCase,
        knobs: {...desktopLayout, ...knobs},
      );
      // The expanded message is applied from a post-frame callback, so the
      // receipt needs one more frame than the default pump gives it.
      await tester.pump();
      await tester.pump();
    }

    String kind(TxStatusKind value) => activityTxStatusKindLabel(value);
    String phase(TxStatusPhase value) => activityTxStatusPhaseLabel(value);
    String party(TxStatusCounterparty value) =>
        activityTxStatusCounterpartyLabel(value);
    String load(TxStatusLoad value) => activityTxStatusLoadLabel(value);

    await pumpStatus(const {});
    expect(find.text('Sent successfully'), findsOneWidget);

    await pumpStatus({'Phase': phase(TxStatusPhase.pending)});
    expect(find.text('Send in progress...'), findsOneWidget);

    await pumpStatus({'Phase': phase(TxStatusPhase.failed)});
    expect(find.text('Send failed'), findsOneWidget);

    await pumpStatus({'Kind': kind(TxStatusKind.received)});
    expect(find.text('Received successfully'), findsOneWidget);

    await pumpStatus({'Kind': kind(TxStatusKind.shielded)});
    expect(find.text('Shielded successfully'), findsOneWidget);
    expect(find.text('From transparent balance'), findsOneWidget);

    // The migration titles come from the fallback receipt, which is also the
    // shape a sent tx with no resolved recipient lands on.
    await pumpStatus({'Kind': kind(TxStatusKind.migration)});
    expect(find.text('Migrated to Ironwood'), findsOneWidget);
    await pumpStatus({
      'Kind': kind(TxStatusKind.migration),
      'Phase': phase(TxStatusPhase.pending),
    });
    expect(find.text('Migrating to Ironwood'), findsOneWidget);
    await pumpStatus({
      'Kind': kind(TxStatusKind.migration),
      'Phase': phase(TxStatusPhase.failed),
    });
    expect(find.text('Migration failed'), findsOneWidget);

    await pumpStatus({'Kind': kind(TxStatusKind.giftCard)});
    expect(find.text('Created a gift card'), findsOneWidget);

    await pumpStatus({'Counterparty': party(TxStatusCounterparty.contact)});
    expect(find.text('Mike'), findsOneWidget);

    // Two: the sidebar names the active account, the receipt names it again
    // as the recipient.
    await pumpStatus({'Counterparty': party(TxStatusCounterparty.ownAccount)});
    expect(find.text('Account Name'), findsNWidgets(2));

    // A sent tx with no resolved address falls back to the generic receipt.
    await pumpStatus({'Counterparty': party(TxStatusCounterparty.unknown)});
    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('To'), findsNothing);

    await pumpStatus({
      'Kind': kind(TxStatusKind.received),
      'Counterparty': party(TxStatusCounterparty.unknown),
    });
    expect(find.text('Unknown sender'), findsOneWidget);

    await pumpStatus({
      'Kind': kind(TxStatusKind.received),
      'Counterparty': party(TxStatusCounterparty.shieldedSender),
    });
    expect(find.text('Shielded sender'), findsOneWidget);

    await pumpStatus({
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.none),
    });
    expect(find.text('Message'), findsNothing);

    await pumpStatus({
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.collapsed),
    });
    expect(find.text('Message'), findsOneWidget);
    expect(find.text(_fullMemo), findsOneWidget);
    expect(find.text('Collapse'), findsNothing);

    // The expanded option presses the receipt's own Message row, which swaps
    // the value line for the collapse control and prints the memo below it.
    await pumpStatus({
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.expanded),
    });
    expect(find.text('Collapse'), findsOneWidget);
    expect(find.text(_fullMemo), findsOneWidget);

    // Every redesigned receipt carries the expandable row the driver presses.
    for (final expandable in const [
      TxStatusKind.received,
      TxStatusKind.shielded,
      TxStatusKind.giftCard,
    ]) {
      await pumpStatus({
        'Kind': kind(expandable),
        'Message': activityReceiptMessageLabel(ActivityReceiptMessage.expanded),
      });
      expect(find.text('Collapse'), findsOneWidget, reason: kind(expandable));
    }

    // The fallback receipt has no Message row, so the expanded option is inert
    // there rather than a driver that never finds its target.
    await pumpStatus({
      'Kind': kind(TxStatusKind.migration),
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.expanded),
    });
    expect(find.text('Migrated to Ironwood'), findsOneWidget);
    expect(find.text('Collapse'), findsNothing);

    await pumpStatus({
      'Counterparty': party(TxStatusCounterparty.unknown),
      'Message': activityReceiptMessageLabel(ActivityReceiptMessage.expanded),
    });
    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('Collapse'), findsNothing);

    await pumpStatus({'Load': load(TxStatusLoad.loading)});
    expect(find.text('Loading transaction…'), findsOneWidget);

    await pumpStatus({'Load': load(TxStatusLoad.failed)});
    expect(find.text('Transaction could not be loaded.'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('keystone shielding sweeps its stages distinctly', (
    tester,
  ) async {
    await _expectShieldStagesRenderDistinctly(
      tester,
      layout: WbLayout.desktop,
      optionLabels: HomeKeystoneShieldDesktopStage.values
          .map(homeKeystoneShieldDesktopStageLabel)
          .toList(),
    );
    await _expectShieldStagesRenderDistinctly(
      tester,
      layout: WbLayout.mobile,
      optionLabels: HomeKeystoneShieldMobileStage.values
          .map(homeKeystoneShieldMobileStageLabel)
          .toList(),
    );
  });

  testWidgets('keystone shielding shows the stages its knobs name', (
    tester,
  ) async {
    KeystonePcztQrStagePhase qrPhase() {
      return tester
          .widget<KeystonePcztQrStage>(find.byType(KeystonePcztQrStage))
          .phase;
    }

    String desktop(HomeKeystoneShieldDesktopStage stage) =>
        homeKeystoneShieldDesktopStageLabel(stage);
    String mobile(HomeKeystoneShieldMobileStage stage) =>
        homeKeystoneShieldMobileStageLabel(stage);

    await _pumpShield(tester, {
      ...desktopLayout,
      'Stage': desktop(HomeKeystoneShieldDesktopStage.preparing),
    });
    expect(qrPhase(), KeystonePcztQrStagePhase.preparing);
    expect(find.text('Sign tx on your Keystone'), findsOneWidget);

    await _pumpShield(tester, {
      ...desktopLayout,
      'Stage': desktop(HomeKeystoneShieldDesktopStage.qrReady),
    });
    expect(qrPhase(), KeystonePcztQrStagePhase.ready);
    expect(find.text('Get Signature'), findsOneWidget);

    // The copy is the overlay's own mapping of the thrown Rust error.
    await _pumpShield(tester, {
      ...desktopLayout,
      'Stage': desktop(HomeKeystoneShieldDesktopStage.failed),
    });
    expect(qrPhase(), KeystonePcztQrStagePhase.failed);
    expect(
      find.text('Transparent balance is too small to shield after fees.'),
      findsOneWidget,
    );
    expect(find.text('Back to Wallet'), findsOneWidget);

    await _pumpShield(tester, {
      ...mobileLayout,
      'Stage': mobile(HomeKeystoneShieldMobileStage.preparing),
    });
    expect(qrPhase(), KeystonePcztQrStagePhase.preparing);
    expect(find.text('Shield transparent balance'), findsOneWidget);

    await _pumpShield(tester, {
      ...mobileLayout,
      'Stage': mobile(HomeKeystoneShieldMobileStage.qrReady),
    });
    expect(qrPhase(), KeystonePcztQrStagePhase.ready);
    expect(find.text('Next step'), findsOneWidget);

    // The scanning stage replaces the QR with the camera, reached by the
    // fixture pressing the screen's own Next step button.
    await _pumpShield(tester, {
      ...mobileLayout,
      'Stage': mobile(HomeKeystoneShieldMobileStage.scanning),
    });
    expect(find.byType(KeystonePcztQrStage), findsNothing);
    expect(find.text('Show QR'), findsOneWidget);
    expect(find.text('Scan the signed QR on your Keystone'), findsOneWidget);

    await _pumpShield(tester, {
      ...mobileLayout,
      'Stage': mobile(HomeKeystoneShieldMobileStage.failed),
    });
    expect(qrPhase(), KeystonePcztQrStagePhase.failed);
    expect(find.text('Back to wallet'), findsOneWidget);

    // The stage lists are per layout: the phone-only scanning option is not
    // offered on desktop, where the knob falls back to its own default.
    await _pumpShield(tester, {
      ...desktopLayout,
      'Stage': mobile(HomeKeystoneShieldMobileStage.scanning),
    });
    expect(qrPhase(), KeystonePcztQrStagePhase.ready);
    expect(find.text('Get Signature'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('keystone shielding pins its own camera scenario', (
    tester,
  ) async {
    // The camera fake is a process-wide singleton the Scanner cases also
    // configure, so the shielding scanner must set its own scenario rather
    // than preview whatever was configured last.
    WbFakeMobileScannerPlatform.install(
      startResult: WbFakeScannerStart.permissionDenied,
    );
    await _pumpShield(tester, {
      ...mobileLayout,
      'Stage': homeKeystoneShieldMobileStageLabel(
        HomeKeystoneShieldMobileStage.scanning,
      ),
    });
    expect(
      WbFakeMobileScannerPlatform.current?.startResult,
      WbFakeScannerStart.running,
    );
    expect(find.text('Scan the signed QR on your Keystone'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('shielded receipt sweeps every axis distinctly', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityShieldedReceiptGalleryCase,
      label: 'Status',
      optionLabels: ShieldedReceiptStatus.values
          .map(activityShieldedReceiptStatusLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityShieldedReceiptGalleryCase,
      label: 'Network fee',
      optionLabels: const ['true', 'false'],
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityShieldedReceiptGalleryCase,
      label: 'Message',
      optionLabels: ActivityReceiptMessage.values
          .map(activityReceiptMessageLabel)
          .toList(),
    );
  });

  testWidgets('shielded receipt shows the states its knobs name', (
    tester,
  ) async {
    await pumpUseCase(tester, buildActivityShieldedReceiptGalleryCase);
    expect(find.text('Shielded successfully'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityShieldedReceiptGalleryCase,
      knobs: {
        'Status': activityShieldedReceiptStatusLabel(
          ShieldedReceiptStatus.inProgress,
        ),
      },
    );
    expect(find.text('Shielding in progress...'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityShieldedReceiptGalleryCase,
      knobs: {
        'Status': activityShieldedReceiptStatusLabel(
          ShieldedReceiptStatus.failed,
        ),
      },
    );
    expect(find.text('Shielding failed'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityShieldedReceiptGalleryCase,
      knobs: {'Network fee': 'false'},
    );
    expect(find.text('Tx fee'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('gift card detail sweeps every axis distinctly', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityGiftCardDetailGalleryCase,
      label: 'Status',
      optionLabels: GiftCardActivityDetailStatus.values
          .map(activityGiftCardStatusLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityGiftCardDetailGalleryCase,
      label: 'Message',
      optionLabels: ActivityReceiptMessage.values
          .map(activityReceiptMessageLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivityGiftCardDetailGalleryCase,
      label: 'Fiat value',
      optionLabels: const ['true', 'false'],
    );
  });

  testWidgets('gift card detail renders every artwork and status title', (
    tester,
  ) async {
    // Artwork is an asset image, which a widget test never decodes; the card's
    // own artwork field is what proves the knob reached the view.
    for (final artwork in PaymentLinkCardArtwork.values) {
      await pumpUseCase(
        tester,
        buildActivityGiftCardDetailGalleryCase,
        knobs: {'Artwork': activityGiftCardArtworkLabel(artwork)},
      );
      expect(tester.takeException(), isNull, reason: artwork.name);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is PaymentLinkGiftCard && widget.artwork == artwork,
        ),
        findsOneWidget,
        reason: artwork.name,
      );
    }

    await pumpUseCase(
      tester,
      buildActivityGiftCardDetailGalleryCase,
      knobs: {
        'Status': activityGiftCardStatusLabel(
          GiftCardActivityDetailStatus.inProgress,
        ),
      },
    );
    expect(find.text('Creating a card ...'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityGiftCardDetailGalleryCase,
      knobs: {
        'Status': activityGiftCardStatusLabel(
          GiftCardActivityDetailStatus.failed,
        ),
      },
    );
    expect(find.text('Gift card creation failed'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityGiftCardDetailGalleryCase,
      knobs: {
        'Message': activityReceiptMessageLabel(ActivityReceiptMessage.none),
      },
    );
    expect(find.text('Message'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('activity feed sweeps every axis distinctly', (tester) async {
    Future<void> sweep(
      String label,
      List<String> options, {
      Map<String, String> otherKnobs = const {},
    }) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildActivityFeedGalleryCase,
        label: label,
        optionLabels: options,
        otherKnobs: otherKnobs,
      );
    }

    // Host is asserted by widget type, not pixels: with one section the sliver
    // segments compose into the same card the Column draws.
    await sweep(
      'State',
      ActivityFeedBodyState.values.map(activityFeedBodyStateLabel).toList(),
    );
    await sweep(
      'Rows',
      ActivityFeedRowShape.values.map(activityFeedRowShapeLabel).toList(),
    );
    // Header and width are `ActivityFeed`-only props, so they are swept on the
    // Column host the desktop sliver does not share.
    await sweep(
      'Header',
      ActivityFeedHeader.values.map(activityFeedHeaderLabel).toList(),
    );
    await sweep(
      'Width',
      ActivityFeedWidth.values.map(activityFeedWidthLabel).toList(),
    );
  });

  testWidgets('activity feed shows the states its knobs name', (tester) async {
    for (final host in ActivityFeedHost.values) {
      final hostLabel = activityFeedHostLabel(host);
      final sliver = host == ActivityFeedHost.sliver;

      await pumpUseCase(
        tester,
        buildActivityFeedGalleryCase,
        knobs: {'Host': hostLabel},
      );
      expect(
        find.byType(ActivityFeedSliver),
        sliver ? findsOneWidget : findsNothing,
        reason: hostLabel,
      );
      expect(
        find.byType(ActivityFeed),
        sliver ? findsNothing : findsOneWidget,
        reason: hostLabel,
      );

      await pumpUseCase(
        tester,
        buildActivityFeedGalleryCase,
        knobs: {
          'Host': hostLabel,
          'State': activityFeedBodyStateLabel(ActivityFeedBodyState.loading),
        },
      );
      expect(
        find.text('Loading activity...'),
        findsOneWidget,
        reason: hostLabel,
      );

      await pumpUseCase(
        tester,
        buildActivityFeedGalleryCase,
        knobs: {
          'Host': hostLabel,
          'State': activityFeedBodyStateLabel(ActivityFeedBodyState.empty),
        },
      );
      expect(find.text('No activity yet'), findsOneWidget, reason: hostLabel);

      await pumpUseCase(
        tester,
        buildActivityFeedGalleryCase,
        knobs: {
          'Host': hostLabel,
          'State': activityFeedBodyStateLabel(ActivityFeedBodyState.error),
        },
      );
      expect(
        find.text('Activity could not be loaded.'),
        findsOneWidget,
        reason: hostLabel,
      );
    }

    await pumpUseCase(
      tester,
      buildActivityFeedGalleryCase,
      knobs: {'Rows': activityFeedRowShapeLabel(ActivityFeedRowShape.single)},
    );
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Received'), findsNothing);

    await pumpUseCase(
      tester,
      buildActivityFeedGalleryCase,
      knobs: {
        'Rows': activityFeedRowShapeLabel(ActivityFeedRowShape.withChildRow),
      },
    );
    expect(find.byKey(_childConnectorKey), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityFeedGalleryCase,
      knobs: {'Header': activityFeedHeaderLabel(ActivityFeedHeader.hidden)},
    );
    expect(find.byKey(_feedTitleRowKey), findsNothing);

    await pumpUseCase(
      tester,
      buildActivityFeedGalleryCase,
      knobs: {'Header': activityFeedHeaderLabel(ActivityFeedHeader.shown)},
    );
    expect(find.byKey(_feedTitleRowKey), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('activity row sweeps every axis distinctly', (tester) async {
    Future<void> sweep(String label, List<String> options) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildActivityRowGalleryCase,
        label: label,
        optionLabels: options,
      );
    }

    await sweep(
      'Density',
      ActivityRowDensity.values.map(activityRowDensityLabel).toList(),
    );
    await sweep(
      'Trailing',
      ActivityRowTrailing.values.map(activityRowTrailingLabel).toList(),
    );
    await sweep(
      'Status',
      ActivityRowStatus.values.map(activityRowStatusLabel).toList(),
    );
    await sweep(
      'Background',
      ActivityRowBackground.values.map(activityRowBackgroundLabel).toList(),
    );
    // The child row eases in from zero height, so on the first frame it is not
    // yet painted; it is asserted by its connector below instead.
    await sweep('Privacy mode', const ['true', 'false']);
  });

  testWidgets('activity row interaction knob drives the tap target', (
    tester,
  ) async {
    // Rest and 'Not tappable' differ only in the tap target: the row paints a
    // highlight on hover, which no prop reaches.
    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {
        'Interaction': activityRowInteractionLabel(ActivityRowInteraction.rest),
      },
    );
    expect(find.byType(GestureDetector), findsOneWidget);
    final rest = await useCaseFingerprint(tester);

    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {
        'Interaction': activityRowInteractionLabel(
          ActivityRowInteraction.selected,
        ),
      },
    );
    expect(find.byType(GestureDetector), findsOneWidget);
    expect(await useCaseFingerprint(tester), isNot(rest));

    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {
        'Interaction': activityRowInteractionLabel(
          ActivityRowInteraction.nonInteractive,
        ),
      },
    );
    expect(find.byType(GestureDetector), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('activity row shows the states its knobs name', (tester) async {
    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {'Trailing': activityRowTrailingLabel(ActivityRowTrailing.refund)},
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.uturnUp,
        description: 'AppIcon(uturn_up)',
      ),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {
        'Trailing': activityRowTrailingLabel(ActivityRowTrailing.timeout),
      },
    );
    expect(find.text('Timeout'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {'Status': activityRowStatusLabel(ActivityRowStatus.failed)},
    );
    expect(find.text('Failed'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {'Child row': 'true'},
    );
    expect(find.byKey(_childConnectorKey), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {'Child row': 'false'},
    );
    expect(find.byKey(_childConnectorKey), findsNothing);

    await pumpUseCase(
      tester,
      buildActivityRowGalleryCase,
      knobs: {'Privacy mode': 'true'},
    );
    expect(find.text('*** ZEC'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('transaction row sweeps every axis distinctly', (tester) async {
    Future<void> sweep(String label, List<String> options) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildActivityTransactionRowGalleryCase,
        label: label,
        optionLabels: options,
      );
    }

    await sweep(
      'Kind',
      ActivityTxRowKind.values.map(activityTxRowKindLabel).toList(),
    );
    await sweep(
      'Status',
      ActivityTxRowStatus.values.map(activityTxRowStatusLabel).toList(),
    );
    await sweep(
      'Pool',
      ActivityTxRowPool.values.map(activityTxRowPoolLabel).toList(),
    );
    await sweep(
      'Amount',
      ActivityTxRowAmount.values.map(activityTxRowAmountLabel).toList(),
    );
    await sweep('Privacy mode', const ['true', 'false']);
  });

  testWidgets('transaction row maps each kind to its own title', (
    tester,
  ) async {
    const titles = {
      ActivityTxRowKind.received: 'Received',
      ActivityTxRowKind.receiving: 'Receiving',
      ActivityTxRowKind.sent: 'Sent',
      ActivityTxRowKind.shielded: 'Shielded',
      ActivityTxRowKind.migration: 'Migrated to Ironwood',
      ActivityTxRowKind.giftCardCreated: 'Created a gift card',
      ActivityTxRowKind.giftCardRedeemed: 'Redeemed a gift card',
      ActivityTxRowKind.unknown: 'Transaction',
    };
    for (final entry in titles.entries) {
      await pumpUseCase(
        tester,
        buildActivityTransactionRowGalleryCase,
        knobs: {'Kind': activityTxRowKindLabel(entry.key)},
      );
      expect(find.text(entry.value), findsOneWidget, reason: entry.value);
    }
    await disposeTree(tester);
  });

  testWidgets('transaction row shows the states its knobs name', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildActivityTransactionRowGalleryCase,
      knobs: {'Status': activityTxRowStatusLabel(ActivityTxRowStatus.failed)},
    );
    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityTransactionRowGalleryCase,
      knobs: {
        'Kind': activityTxRowKindLabel(ActivityTxRowKind.giftCardCreated),
        'Status': activityTxRowStatusLabel(ActivityTxRowStatus.failed),
      },
    );
    expect(find.text('Gift card creation failed'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityTransactionRowGalleryCase,
      knobs: {'Pool': activityTxRowPoolLabel(ActivityTxRowPool.ironwood)},
    );
    expect(find.text('Ironwood'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityTransactionRowGalleryCase,
      knobs: {'Pool': activityTxRowPoolLabel(ActivityTxRowPool.none)},
    );
    expect(find.text('Shielded'), findsNothing);
    expect(find.text('Transparent'), findsNothing);

    await pumpUseCase(
      tester,
      buildActivityTransactionRowGalleryCase,
      knobs: {'Amount': activityTxRowAmountLabel(ActivityTxRowAmount.zero)},
    );
    expect(find.text('--'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivityTransactionRowGalleryCase,
      knobs: {'Privacy mode': 'true'},
    );
    expect(find.text('*** ZEC'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('swap row sweeps its non-alias axes distinctly', (tester) async {
    Future<void> sweep(
      String label,
      List<String> options, {
      Map<String, String> otherKnobs = const {},
    }) {
      return expectKnobOptionsRenderDistinctly(
        tester,
        buildActivitySwapRowGalleryCase,
        label: label,
        optionLabels: options,
        otherKnobs: otherKnobs,
      );
    }

    // 'Awaiting external deposit' and 'Checking status' are aliases of
    // 'Awaiting deposit' and 'Processing' in the mapper — same copy, same
    // progress step — so only the eight distinguishable options are swept.
    await sweep(
      'Status',
      const [
        SwapIntentStatus.awaitingDeposit,
        SwapIntentStatus.depositObserved,
        SwapIntentStatus.processing,
        SwapIntentStatus.incompleteDeposit,
        SwapIntentStatus.complete,
        SwapIntentStatus.refunded,
        SwapIntentStatus.expired,
        SwapIntentStatus.failed,
      ].map(activitySwapRowStatusLabel).toList(),
    );
    await sweep(
      'Mode',
      ActivitySwapRowMode.values.map(activitySwapRowModeLabel).toList(),
    );
    await sweep(
      'Direction',
      ActivitySwapRowDirection.values
          .map(activitySwapRowDirectionLabel)
          .toList(),
    );
    // The received leg only changes the child row, which eases in from zero
    // height; it is asserted by its amount text below instead.
    await sweep('Privacy mode', const ['true', 'false']);
  });

  testWidgets('swap row maps every status to its own copy', (tester) async {
    const titles = {
      SwapIntentStatus.awaitingDeposit: 'Swapping...',
      SwapIntentStatus.awaitingExternalDeposit: 'Swapping...',
      SwapIntentStatus.depositObserved: 'Swapping...',
      SwapIntentStatus.processing: 'Swapping...',
      SwapIntentStatus.providerStatusUnknown: 'Swapping...',
      SwapIntentStatus.incompleteDeposit: 'Swapping...',
      SwapIntentStatus.complete: 'Swapped',
      SwapIntentStatus.refunded: 'Swap failed',
      SwapIntentStatus.expired: 'Swap failed',
      SwapIntentStatus.failed: 'Swap failed',
    };
    for (final entry in titles.entries) {
      await pumpUseCase(
        tester,
        buildActivitySwapRowGalleryCase,
        knobs: {'Status': activitySwapRowStatusLabel(entry.key)},
      );
      expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);
    }

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {
        'Status': activitySwapRowStatusLabel(
          SwapIntentStatus.incompleteDeposit,
        ),
      },
    );
    expect(find.text('Incomplete deposit'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {'Status': activitySwapRowStatusLabel(SwapIntentStatus.refunded)},
    );
    expect(find.text('ZEC Refunded'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {'Status': activitySwapRowStatusLabel(SwapIntentStatus.expired)},
    );
    expect(find.text('Timeout'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('swap row shows the states its knobs name', (tester) async {
    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {'Mode': activitySwapRowModeLabel(ActivitySwapRowMode.pay)},
    );
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('from shielded ZEC · Ethereum'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {
        'Mode': activitySwapRowModeLabel(ActivitySwapRowMode.pay),
        'Status': activitySwapRowStatusLabel(SwapIntentStatus.failed),
      },
    );
    expect(find.text('Payment failed'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {
        'Direction': activitySwapRowDirectionLabel(
          ActivitySwapRowDirection.zecToAsset,
        ),
      },
    );
    expect(find.text('Deposited USDC'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {
        'Direction': activitySwapRowDirectionLabel(
          ActivitySwapRowDirection.assetToZec,
        ),
        'Received leg': activitySwapRowReceivedLegLabel(
          ActivitySwapRowReceivedLeg.present,
        ),
      },
    );
    expect(find.text('Received ZEC'), findsOneWidget);
    expect(find.text('+12.05 ZEC'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {
        'Direction': activitySwapRowDirectionLabel(
          ActivitySwapRowDirection.assetToZec,
        ),
        'Received leg': activitySwapRowReceivedLegLabel(
          ActivitySwapRowReceivedLeg.absent,
        ),
      },
    );
    // No absorbed payout: the child leg falls back to the quote estimate.
    expect(find.text('+12.13 ZEC'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildActivitySwapRowGalleryCase,
      knobs: {'Privacy mode': 'true'},
    );
    expect(find.text('*** ZEC'), findsWidgets);
    await disposeTree(tester);
  });

  testWidgets('swap detail screen sweeps its axes distinctly', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivitySwapDetailScreenGalleryCase,
      label: 'Status',
      optionLabels: [
        for (final status in SwapDetailStatus.values)
          activitySwapDetailStatusLabel(status),
      ],
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildActivitySwapDetailScreenGalleryCase,
      label: 'Intent',
      optionLabels: [
        for (final intentCase in SwapDetailIntentCase.values)
          activitySwapDetailIntentLabel(intentCase),
      ],
    );

    // The two hosts: only desktop puts the surface in the sidebar shell's pane.
    await pumpUseCase(
      tester,
      buildActivitySwapDetailScreenGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(
      find.byKey(const ValueKey('swap_activity_detail_pane')),
      findsOneWidget,
    );

    // Mobile's back-nav title is the mode/status mapping the host owns.
    await pumpUseCase(
      tester,
      buildActivitySwapDetailScreenGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Status': activitySwapDetailStatusLabel(SwapDetailStatus.complete),
      },
    );
    expect(find.text('Paid'), findsNothing);

    await pumpUseCase(
      tester,
      buildActivitySwapDetailScreenGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Status': activitySwapDetailStatusLabel(SwapDetailStatus.complete),
        'Mode': activitySwapDetailModeLabel(SwapDetailMode.payment),
      },
    );
    expect(find.text('Paid'), findsOneWidget);
    await disposeTree(tester);
  });
}

/// The shielding cases seed their stage from an async preparer and, for the
/// scanning stage, a post-frame button press, so they need more frames than
/// the default pump gives.
Future<void> _pumpShield(WidgetTester tester, Map<String, String> knobs) async {
  await pumpUseCase(tester, buildHomeKeystoneShieldGalleryCase, knobs: knobs);
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

/// The harness sweep with those extra frames, and a dispose per option so the
/// animated QR's timer never outlives its case.
Future<void> _expectShieldStagesRenderDistinctly(
  WidgetTester tester, {
  required WbLayout layout,
  required List<String> optionLabels,
}) async {
  final seen = <String, String>{};
  for (final option in optionLabels) {
    await _pumpShield(tester, {
      'Layout': wbLayoutLabel(layout),
      'Stage': option,
    });
    expect(tester.takeException(), isNull, reason: 'Stage / $option');

    final fingerprint = await useCaseFingerprint(tester);
    final duplicate = seen[fingerprint];
    expect(
      duplicate,
      isNull,
      reason:
          "'Stage' options '$duplicate' and '$option' render identically — "
          'the knob has a dead option or a duplicated dispatch.',
    );
    seen[fingerprint] = option;
    await disposeTree(tester);
  }
}

const _childConnectorKey = ValueKey('activity_feed_child_connector');
const _feedTitleRowKey = ValueKey('activity_screen_title_row');

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Bold.ttf'));
  final geistMono = FontLoader('Geist Mono')
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Medium.ttf'));
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));

  await Future.wait([geist.load(), geistMono.load(), youngSerif.load()]);
}
