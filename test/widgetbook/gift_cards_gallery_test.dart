import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart'
    show PaymentLinkCardListRow;
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart'
    show PaymentLinkCardListMobileRow;
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_archive_header.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_cards_layout.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_qr_share_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_wizard_chrome.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/widgetbook/gallery/gift_cards_gallery.dart';
import 'package:zcash_wallet/widgetbook/gift_cards_screen_use_cases.dart';
import 'package:zcash_wallet/widgetbook/payment_link_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Lane-agnostic: every layout-dependent sweep drives the Layout knob
// explicitly, so both test lanes exercise the same combinations.
void main() {
  testWidgets('every gift cards gallery case builds at its knob defaults', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    final useCases = widgetbookUseCases(giftCardsGalleryNodes).toList();
    expect(useCases.length, 26);

    // The registry mixes desktop-only and mobile-only surfaces, so a default
    // pump is not necessarily on-lane; the per-case suites below sweep each
    // one with its lane declared.
    _previewingBothLanes();
    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      await _settleFixture(tester);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('home covers both lanes and every registered pane', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      if (layout == WbLayout.mobile) _previewingLabelBoundSurface();
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsHomeGalleryCase,
        label: 'Content',
        optionLabels: giftCardsHomeContentOptions(
          layout,
        ).map(giftCardsHomeContentLabel).toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }

    _previewingBothLanes();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsHomeGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('cards list covers both tabs, the archive and the long list', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      _previewingLabelBoundSurface();
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardsListGalleryCase,
        label: 'Content',
        optionLabels: GiftCardsListContent.values
            .map(giftCardsListContentLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardsListGalleryCase,
        label: 'Tab',
        optionLabels: PaymentLinkCardsTab.values
            .map(giftCardsTabLabel)
            .toList(),
        otherKnobs: lane,
      );
      // The long list is what pushes the desktop pane past its scroll extent,
      // which is what raises the bottom fade.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardsListGalleryCase,
        label: 'Long list',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
      // A disabled tab keeps its paint and drops its handler.
      for (final enabled in const ['true', 'false']) {
        await pumpUseCase(
          tester,
          buildGiftCardsCardsListGalleryCase,
          knobs: {...lane, 'Tabs enabled': enabled},
        );
        final tabs = tester
            .widgetList<PaymentLinkTabAction>(find.byType(PaymentLinkTabAction))
            .toList();
        expect(tabs, isNotEmpty, reason: '$layout / $enabled');
        expect(
          tabs.every((tab) => tab.onTap != null),
          enabled == 'true',
          reason: '$layout / $enabled',
        );
      }
    }
    await disposeTree(tester);
  });

  testWidgets('amount step covers both lanes and every supporting text', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsAmountGalleryCase,
        label: 'State',
        optionLabels: giftCardsAmountStateOptions(
          layout,
        ).map(giftCardsAmountStateLabel).toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsAmountGalleryCase,
        label: 'Supporting text',
        optionLabels: GiftCardsAmountSupportingText.values
            .map(giftCardsAmountSupportingLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsAmountGalleryCase,
        label: 'Continue enabled',
        optionLabels: const ['true', 'false'],
        otherKnobs: lane,
      );
    }

    // Mobile-only: the keyboard shrinks the stage, so it scrolls.
    _previewing(WbLayout.mobile);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsAmountGalleryCase,
      label: 'Keyboard open',
      optionLabels: const ['false', 'true'],
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    _previewing(WbLayout.desktop);
    await _expectStepperEnabled(
      tester,
      buildGiftCardsAmountGalleryCase,
      layout: WbLayout.desktop,
    );
  });

  testWidgets('message step covers both lanes, the error and the live editor', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsMessageGalleryCase,
        label: 'State',
        optionLabels: giftCardsMessageStateOptions(layout)
            // The live editor opens on the empty message; it is asserted by
            // widget type below instead.
            .where((state) => state != GiftCardsMessageState.live)
            .map(giftCardsMessageStateLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsMessageGalleryCase,
        label: 'Message too large',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsMessageGalleryCase,
        label: 'Continue enabled',
        optionLabels: const ['true', 'false'],
        otherKnobs: lane,
      );
    }
    _previewing(WbLayout.desktop);
    await _expectStepperEnabled(
      tester,
      buildGiftCardsMessageGalleryCase,
      layout: WbLayout.desktop,
    );

    await _expectPreviewType<PaymentLinkInteractiveMessageDesktopPreview>(
      tester,
      buildGiftCardsMessageGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'State': giftCardsMessageStateLabel(GiftCardsMessageState.live),
      },
      present: true,
    );
    await _expectPreviewType<PaymentLinkInteractiveMessageDesktopPreview>(
      tester,
      buildGiftCardsMessageGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'State': giftCardsMessageStateLabel(GiftCardsMessageState.empty),
      },
      present: false,
    );
  });

  testWidgets('review covers both lanes, both faces and every confirm label', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      final lane = {'Layout': wbLayoutLabel(layout)};
      // The confirm options differ only in the button label and whether the
      // button is live; the test font paints same-length labels identically.
      for (final confirm in GiftCardsReviewConfirm.values) {
        await pumpUseCase(
          tester,
          buildGiftCardsReviewGalleryCase,
          knobs: {...lane, 'Confirm': giftCardsReviewConfirmLabel(confirm)},
        );
        expect(tester.takeException(), isNull, reason: '$layout / $confirm');
        final expectedLabel = switch (confirm) {
          GiftCardsReviewConfirm.creating => 'Creating...',
          GiftCardsReviewConfirm.retry => 'Try saving again',
          GiftCardsReviewConfirm.saving => 'Saving...',
          _ => layout == WbLayout.mobile ? 'Approve & create' : 'Create card',
        };
        expect(
          find.text(expectedLabel),
          findsOneWidget,
          reason: '$layout / $confirm',
        );
        final button = tester.widget<AppButton>(
          find.ancestor(
            of: find.text(expectedLabel),
            matching: find.byType(AppButton),
          ),
        );
        expect(
          button.onPressed != null,
          confirm == GiftCardsReviewConfirm.create ||
              confirm == GiftCardsReviewConfirm.retry,
          reason: '$layout / $confirm',
        );
      }
      await disposeTree(tester);
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsReviewGalleryCase,
        label: 'Card face',
        optionLabels: GiftCardsReviewFace.values
            .map(giftCardsReviewFaceLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsReviewGalleryCase,
        label: 'Small amounts',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
    }

    _previewing(WbLayout.mobile);
    final mobile = {'Layout': wbLayoutLabel(WbLayout.mobile)};
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsReviewGalleryCase,
      label: 'Fee help',
      optionLabels: const ['true', 'false'],
      otherKnobs: mobile,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsReviewGalleryCase,
      label: 'Text scale 2x',
      optionLabels: const ['false', 'true'],
      otherKnobs: mobile,
    );
    _previewing(WbLayout.desktop);
    await _expectStepperEnabled(
      tester,
      buildGiftCardsReviewGalleryCase,
      layout: WbLayout.desktop,
    );
  });

  testWidgets('ready covers both lanes, the copy states and reduced motion', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      if (layout == WbLayout.mobile) _previewingLabelBoundSurface();
      final lane = {'Layout': wbLayoutLabel(layout)};
      // Waiting and 'available soon' differ only in the wait label and the
      // pill icon, and the test font paints same-length labels identically.
      for (final stage in giftCardsReadyStageOptions(layout)) {
        await pumpUseCase(
          tester,
          buildGiftCardsReadyGalleryCase,
          knobs: {...lane, 'State': giftCardsReadyStageLabel(stage)},
        );
        expect(tester.takeException(), isNull, reason: '$layout / $stage');
        expect(
          find.text(switch (stage) {
            GiftCardsReadyStage.waiting => 'Wait 1:15 to get the link',
            GiftCardsReadyStage.availableSoon => 'Wait 0:15 to get the link',
            GiftCardsReadyStage.ready => 'Copy link',
          }),
          findsOneWidget,
          reason: '$layout / $stage',
        );
      }
      await disposeTree(tester);
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsReadyGalleryCase,
        label: 'Copy',
        optionLabels: GiftCardsReadyCopy.values
            .map(giftCardsReadyCopyLabel)
            .toList(),
        otherKnobs: lane,
      );
      // The confetti only paints once its animation has advanced.
      await _expectSettledOptionsRenderDistinctly(
        tester,
        buildGiftCardsReadyGalleryCase,
        label: 'Confetti',
        optionLabels: const ['true', 'false'],
        otherKnobs: lane,
      );
      // Motion only diverges once the confetti has had frames to travel.
      await _expectSettledOptionsRenderDistinctly(
        tester,
        buildGiftCardsReadyGalleryCase,
        label: 'Reduced motion',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
    }

    // SVG glyphs load asynchronously in a widget test, so the pill icon is
    // asserted on the widget that names it.
    _previewing(WbLayout.mobile);
    _previewingLabelBoundSurface();
    for (final icon in GiftCardsWaitingIcon.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsReadyGalleryCase,
        knobs: {
          'Layout': wbLayoutLabel(WbLayout.mobile),
          'State': giftCardsReadyStageLabel(GiftCardsReadyStage.waiting),
          'Waiting icon': giftCardsWaitingIconLabel(icon),
        },
      );
      expect(tester.takeException(), isNull, reason: '$icon');
      expect(
        tester
            .widgetList<AppIcon>(find.byType(AppIcon))
            .map((widget) => widget.name),
        contains(switch (icon) {
          GiftCardsWaitingIcon.giftCard => AppIcons.giftCard,
          GiftCardsWaitingIcon.link => AppIcons.link,
          GiftCardsWaitingIcon.time => AppIcons.time,
        }),
        reason: '$icon',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('redeem covers both lanes, the outcomes and the scan sheet', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      if (layout == WbLayout.mobile) _previewingLabelBoundSurface();
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsRedeemGalleryCase,
        label: 'State',
        optionLabels: GiftCardsRedeemStage.values
            .map(giftCardsRedeemStageLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsRedeemGalleryCase,
        label: 'Try again label',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsRedeemGalleryCase,
        label: 'Working',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsRedeemGalleryCase,
        label: 'Long sync warning',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
    }

    // The scanned-code copy replaces the invalid title and the scan action.
    _previewing(WbLayout.mobile);
    _previewingLabelBoundSurface();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsRedeemGalleryCase,
      label: 'Scanned QR code',
      optionLabels: const ['false', 'true'],
      otherKnobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'State': giftCardsRedeemStageLabel(GiftCardsRedeemStage.invalid),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsScanGalleryCase,
      label: 'State',
      optionLabels: GiftCardsScanState.values
          .map(giftCardsScanStateLabel)
          .toList(),
    );
  });

  testWidgets('received covers both lanes and the claim account sheet', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      if (layout == WbLayout.mobile) _previewingLabelBoundSurface();
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsReceivedGalleryCase,
        label: 'State',
        optionLabels: GiftCardsReceivedStage.values
            .map(giftCardsReceivedStageLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsReceivedGalleryCase,
        label: 'Claim',
        optionLabels: GiftCardsClaimAction.values
            .map(giftCardsClaimActionLabel)
            .toList(),
        otherKnobs: lane,
      );
      for (final claim in GiftCardsClaimAction.values) {
        await pumpUseCase(
          tester,
          buildGiftCardsReceivedGalleryCase,
          knobs: {...lane, 'Claim': giftCardsClaimActionLabel(claim)},
        );
        final label = switch (claim) {
          GiftCardsClaimAction.claiming => 'Claiming...',
          GiftCardsClaimAction.retry => 'Try again',
          _ =>
            layout == WbLayout.mobile
                ? 'Claim the gift'
                : 'Claim the gift card',
        };
        final button = tester.widget<AppButton>(
          find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
        );
        expect(
          button.onPressed != null,
          claim == GiftCardsClaimAction.claim ||
              claim == GiftCardsClaimAction.retry,
          reason: '$layout / $claim',
        );
        expect(tester.takeException(), isNull);
      }
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsReceivedGalleryCase,
        label: 'Message attached',
        optionLabels: const ['true', 'false'],
        otherKnobs: lane,
      );
      await _expectSettledOptionsRenderDistinctly(
        tester,
        buildGiftCardsReceivedGalleryCase,
        label: 'Reduced motion',
        optionLabels: const ['false', 'true'],
        otherKnobs: lane,
      );
    }
  });

  // The activity and receipt previews mount real screens behind async
  // loaders, so they need frames to settle before their pixels mean anything.
  testWidgets('activity and detail stages each render their own frame', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    _previewing(WbLayout.mobile);
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsActivityGalleryCase,
      label: 'Stage',
      optionLabels: GiftCardsActivityStage.values
          .map(giftCardsActivityStageLabel)
          .toList(),
      canvasSize: const Size(393, 1000),
    );
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsDetailGalleryCase,
      label: 'Stage',
      optionLabels: GiftCardsDetailStage.values
          .map(giftCardsDetailStageLabel)
          .toList(),
      canvasSize: const Size(393, 1000),
    );
  });

  testWidgets('activity and detail interactions stay inside Widgetbook', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final platformCalls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      platformCalls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await pumpUseCase(
      tester,
      buildGiftCardsActivityGalleryCase,
      knobs: {
        'Stage': giftCardsActivityStageLabel(GiftCardsActivityStage.created),
      },
      canvasSize: const Size(393, 1000),
    );
    await _settleFixture(tester);
    await tester.tap(find.byType(ActivityFeedRow).first);
    await tester.pump();
    await tester.pump();
    expect(find.byType(MobileTransactionStatusScreen), findsOneWidget);

    await pumpUseCase(
      tester,
      buildGiftCardsDetailGalleryCase,
      knobs: {'Stage': giftCardsDetailStageLabel(GiftCardsDetailStage.created)},
      canvasSize: const Size(393, 1000),
    );
    await _settleFixture(tester);
    await tester.tap(find.text('Tx ID'));
    await tester.pump();
    expect(platformCalls, isEmpty);
    await disposeTree(tester);
  });

  testWidgets('how it works covers both lanes and both presentations', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    _previewingBothLanes();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsHowItWorksGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    for (final layout in WbLayout.values) {
      _previewing(layout);
      if (layout == WbLayout.desktop) _previewingLabelBoundSurface();
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsHowItWorksGalleryCase,
        label: 'Presentation',
        optionLabels: GiftCardsHelpPresentation.values
            .map(giftCardsHelpPresentationLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }
  });

  testWidgets('share QR covers both lanes, the busy labels and the QR error', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    _previewingBothLanes();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsShareQrGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // Only the desktop pane takes the labels as props; the mobile sheet owns
    // its own busy state, so the two action knobs are desktop-only.
    _previewing(WbLayout.desktop);
    final desktop = {'Layout': wbLayoutLabel(WbLayout.desktop)};
    for (final save in GiftCardsShareAction.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsShareQrGalleryCase,
        knobs: {...desktop, 'Save QR': giftCardsShareSaveLabel(save)},
      );
      expect(tester.takeException(), isNull, reason: '$save');
      expect(
        find.text(
          save == GiftCardsShareAction.running ? 'Saving...' : 'Save QR code',
        ),
        findsOneWidget,
        reason: '$save',
      );
      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('payment_link_save_qr_button')),
      );
      expect(
        button.onPressed != null,
        save == GiftCardsShareAction.ready,
        reason: '$save',
      );
    }
    for (final copy in GiftCardsShareAction.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsShareQrGalleryCase,
        knobs: {...desktop, 'Copy link': giftCardsShareCopyLabel(copy)},
      );
      expect(tester.takeException(), isNull, reason: '$copy');
      expect(
        find.text(
          copy == GiftCardsShareAction.running ? 'Copying...' : 'Copy link',
        ),
        findsOneWidget,
        reason: '$copy',
      );
      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('payment_link_share_copy_button')),
      );
      expect(
        button.onPressed != null,
        copy == GiftCardsShareAction.ready,
        reason: '$copy',
      );
    }

    // Assets do not decode in a widget test, so the artwork is asserted on the
    // composite that carries it rather than on pixels.
    for (final artwork in giftCardsShareArtworkOptions) {
      await pumpUseCase(
        tester,
        buildGiftCardsShareQrGalleryCase,
        knobs: {...desktop, 'Artwork': giftCardsShareArtworkLabel(artwork)},
      );
      expect(tester.takeException(), isNull, reason: '$artwork');
      expect(
        tester
            .widget<PaymentLinkQrShareCard>(find.byType(PaymentLinkQrShareCard))
            .artwork,
        artwork,
        reason: '$artwork',
      );
    }

    for (final layout in WbLayout.values) {
      _previewing(layout);
      if (layout == WbLayout.mobile) _previewingLabelBoundSurface();
      for (final symbol in GiftCardsShareQrSymbol.values) {
        await pumpUseCase(
          tester,
          buildGiftCardsShareQrGalleryCase,
          knobs: {
            'Layout': wbLayoutLabel(layout),
            'QR': giftCardsShareQrSymbolLabel(symbol),
          },
        );
        expect(tester.takeException(), isNull, reason: '$layout / $symbol');
        expect(
          _qrErrorIcon,
          symbol == GiftCardsShareQrSymbol.failed
              ? findsOneWidget
              : findsNothing,
          reason: '$layout / $symbol',
        );
      }
    }
    await disposeTree(tester);
  });

  testWidgets('claim result covers every outcome, the check and archiving', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    // The view picks its redeem pane from `kAppFormFactor`, so the off-lane
    // option is the run-command notice and the states sweep in the lane.
    _previewingBothLanes();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsClaimOutcomeGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    _previewing(wbCompiledLaneLayout);
    final lane = {'Layout': wbLayoutLabel(wbCompiledLaneLayout)};
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsClaimOutcomeGalleryCase,
      label: 'Outcome',
      optionLabels: giftCardsClaimOutcomeOptions
          .map(giftCardsClaimOutcomeLabel)
          .toList(),
      otherKnobs: lane,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsClaimOutcomeGalleryCase,
      label: 'Checking',
      optionLabels: const ['false', 'true'],
      otherKnobs: lane,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsClaimOutcomeGalleryCase,
      label: 'Archive action',
      optionLabels: GiftCardsClaimArchiveAction.values
          .map(giftCardsClaimArchiveActionLabel)
          .toList(),
      otherKnobs: lane,
    );
  });

  testWidgets('claim account picker covers counts, hardware and selection', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    _previewing(WbLayout.mobile);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsClaimAccountGalleryCase,
      label: 'Accounts',
      optionLabels: GiftCardsClaimAccounts.values
          .map(giftCardsClaimAccountsLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsClaimAccountGalleryCase,
      label: 'Hardware account',
      optionLabels: const ['false', 'true'],
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsClaimAccountGalleryCase,
      label: 'Selection',
      optionLabels: GiftCardsClaimSelection.values
          .map(giftCardsClaimSelectionLabel)
          .toList(),
    );
  });

  // The body mounts a nested navigator, so each option needs the step
  // transition to land before its pixels mean anything.
  testWidgets('mobile body navigator covers every page and its overlays', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    _previewingLabelBoundSurface();
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsMobileBodyGalleryCase,
      label: 'Page',
      optionLabels: GiftCardsMobilePage.values
          .map(giftCardsMobilePageLabel)
          .toList(),
    );
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsMobileBodyGalleryCase,
      label: 'Created cards',
      optionLabels: const ['false', 'true'],
    );
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsMobileBodyGalleryCase,
      label: 'Keystone overlay',
      optionLabels: const ['false', 'true'],
    );
    // The claim stages differ only in their wait or claim label, and the test
    // font paints same-length labels identically.
    for (final session in GiftCardsClaimSession.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsMobileBodyGalleryCase,
        knobs: {
          'Page': giftCardsMobilePageLabel(GiftCardsMobilePage.received),
          'Claim session': giftCardsClaimSessionLabel(session),
        },
      );
      await _settleFixture(tester);
      expect(tester.takeException(), isNull, reason: '$session');
      expect(
        find.text(switch (session) {
          GiftCardsClaimSession.none => 'Try again',
          GiftCardsClaimSession.waiting => 'Wait 6:00 to claim',
          GiftCardsClaimSession.availableSoon => 'Wait 2:00 to claim',
          GiftCardsClaimSession.ready => 'Claim the gift',
        }),
        findsOneWidget,
        reason: '$session',
      );
    }
    // Same reason: the review CTA labels are the same length.
    for (final metadata in GiftCardsFundingMetadata.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsMobileBodyGalleryCase,
        knobs: {
          'Page': giftCardsMobilePageLabel(GiftCardsMobilePage.review),
          'Funding metadata': giftCardsFundingMetadataLabel(metadata),
        },
      );
      await _settleFixture(tester);
      expect(tester.takeException(), isNull, reason: '$metadata');
      expect(
        find.text(
          metadata == GiftCardsFundingMetadata.saved
              ? 'Approve & create'
              : 'Try saving again',
        ),
        findsOneWidget,
        reason: '$metadata',
      );
    }

    // The lock only drops the step route's pop handler; it paints the same.
    for (final locked in const ['false', 'true']) {
      await pumpUseCase(
        tester,
        buildGiftCardsMobileBodyGalleryCase,
        knobs: {'Navigation locked': locked},
      );
      await _settleFixture(tester);
      final scopes = tester
          .widgetList<PopScope<Object?>>(find.byType(PopScope<Object?>))
          .toList();
      expect(scopes, isNotEmpty, reason: locked);
      expect(
        scopes.any((scope) => scope.canPop),
        locked == 'false',
        reason: locked,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('keystone signing overlay covers its phases and error copy', (
    tester,
  ) async {
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsKeystoneSigningGalleryCase,
      label: 'Phase',
      optionLabels: GiftCardsKeystonePhase.values
          .map(giftCardsKeystonePhaseLabel)
          .toList(),
    );

    // The overlay derives this copy from the thrown message, so each option
    // has to land on its own `_friendlyError` branch.
    const expectedCopy = {
      GiftCardsKeystoneError.provingParameters:
          'Required proving parameters could not be prepared.',
      GiftCardsKeystoneError.expired:
          'Transaction expired before it could be signed.',
      GiftCardsKeystoneError.broadcast:
          'Gift card funding could not be broadcast.',
      GiftCardsKeystoneError.signature:
          'Keystone signature could not be applied.',
      GiftCardsKeystoneError.generic:
          'Gift card signing could not be completed.',
    };
    for (final entry in expectedCopy.entries) {
      await pumpUseCase(
        tester,
        buildGiftCardsKeystoneSigningGalleryCase,
        knobs: {
          'Phase': giftCardsKeystonePhaseLabel(GiftCardsKeystonePhase.failed),
          'Error': giftCardsKeystoneErrorLabel(entry.key),
        },
      );
      await _settleFixture(tester);
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }
    await disposeTree(tester);
  });

  testWidgets('card row covers both lanes, its trailings and its statuses', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardRowGalleryCase,
        label: 'Trailing',
        optionLabels: giftCardsRowTrailingOptions(
          layout,
        ).map(giftCardsRowTrailingLabel).toList(),
        otherKnobs: lane,
      );
      // The link actions replace the status slot, so the status and action
      // vocabularies are swept on the row that shows them.
      final statusRow = {
        ...lane,
        'Trailing': giftCardsRowTrailingLabel(GiftCardsRowTrailing.none),
      };
      for (final trailing in giftCardsRowTrailingOptions(layout)) {
        for (final action in GiftCardsRowAction.values) {
          for (final enabled in [true, false]) {
            await pumpUseCase(
              tester,
              buildGiftCardsCardRowGalleryCase,
              knobs: {
                ...lane,
                'Trailing': giftCardsRowTrailingLabel(trailing),
                'Action': giftCardsRowActionOptionLabel(action),
                'Enabled': '$enabled',
              },
            );
            final callback = layout == WbLayout.mobile
                ? tester
                      .widget<PaymentLinkCardListMobileRow>(
                        find.byType(PaymentLinkCardListMobileRow),
                      )
                      .onAction
                : tester
                      .widget<PaymentLinkCardListRow>(
                        find.byType(PaymentLinkCardListRow),
                      )
                      .onAction;
            expect(
              callback != null,
              enabled && action != GiftCardsRowAction.none,
              reason: '$layout / $trailing / $action / $enabled',
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardRowGalleryCase,
        label: 'Status',
        optionLabels: GiftCardsRowStatus.values
            .map(giftCardsRowStatusLabel)
            .toList(),
        otherKnobs: statusRow,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardRowGalleryCase,
        label: 'Action',
        optionLabels: GiftCardsRowAction.values
            .map(giftCardsRowActionOptionLabel)
            .toList(),
        otherKnobs: statusRow,
      );
      // Disabled drops the link handlers and mutes the icons.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardRowGalleryCase,
        label: 'Enabled',
        optionLabels: const ['true', 'false'],
        otherKnobs: lane,
      );
    }

    // Only the desktop row has a secondary text action.
    _previewing(WbLayout.desktop);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsCardRowGalleryCase,
      label: 'Secondary action',
      optionLabels: const ['false', 'true'],
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
  });

  testWidgets('gift card covers both faces, its amounts and its artworks', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      final lane = {'Layout': wbLayoutLabel(layout)};
      final front = {
        ...lane,
        'Face': giftCardsCardFaceLabel(GiftCardsCardFace.front),
      };
      final back = {
        ...lane,
        'Face': giftCardsCardFaceLabel(GiftCardsCardFace.message),
      };
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        label: 'Face',
        optionLabels: GiftCardsCardFace.values
            .map(giftCardsCardFaceLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        label: 'Amount',
        optionLabels: GiftCardsCardAmount.values
            .map(giftCardsCardAmountLabel)
            .toList(),
        otherKnobs: front,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        label: 'Supporting',
        optionLabels: GiftCardsCardSupporting.values
            .map(giftCardsCardSupportingLabel)
            .toList(),
        otherKnobs: front,
      );
      // The Max button needs an entered amount, which is the default.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        label: 'Max button',
        optionLabels: GiftCardsCardMax.values
            .map(giftCardsCardMaxLabel)
            .toList(),
        otherKnobs: front,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        label: 'Message',
        optionLabels: GiftCardsCardMessage.values
            .map(giftCardsCardMessageLabel)
            .toList(),
        otherKnobs: back,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        label: 'Delete message',
        optionLabels: const ['true', 'false'],
        otherKnobs: back,
      );
      // Reduced motion swaps the face without the flip transform.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        label: 'Reduced motion',
        optionLabels: const ['false', 'true'],
        otherKnobs: back,
      );
    }

    _previewingBothLanes();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsGiftCardGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // Assets do not decode in a widget test, so the artwork is asserted on the
    // card that carries it rather than on pixels.
    _previewing(wbCompiledLaneLayout);
    for (final artwork in giftCardsComponentArtworkOptions) {
      await pumpUseCase(
        tester,
        buildGiftCardsGiftCardGalleryCase,
        knobs: {'Artwork': giftCardsShareArtworkLabel(artwork)},
      );
      expect(tester.takeException(), isNull, reason: '$artwork');
      final cards = tester.widgetList<PaymentLinkGiftCard>(
        find.byType(PaymentLinkGiftCard),
      );
      expect(cards, isNotEmpty, reason: '$artwork');
      expect(
        cards.every((card) => card.artwork == artwork),
        isTrue,
        reason: '$artwork',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('card selector covers both lanes, its states and artworks', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      // The focus ring lands a frame after the fixture takes focus.
      await _expectSettledOptionsRenderDistinctly(
        tester,
        buildGiftCardsCardSelectorGalleryCase,
        label: 'State',
        optionLabels: GiftCardsSelectorState.values
            .map(giftCardsSelectorStateLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }

    // An unselected tile paints nothing but its (undecoded) artwork, so the
    // lanes are compared on the selected tile.
    _previewingBothLanes();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsCardSelectorGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      otherKnobs: {
        'State': giftCardsSelectorStateLabel(GiftCardsSelectorState.selected),
      },
    );

    _previewing(wbCompiledLaneLayout);
    for (final artwork in giftCardsComponentArtworkOptions) {
      await pumpUseCase(
        tester,
        buildGiftCardsCardSelectorGalleryCase,
        knobs: {'Artwork': giftCardsShareArtworkLabel(artwork)},
      );
      expect(tester.takeException(), isNull, reason: '$artwork');
      expect(
        tester
            .widget<PaymentLinkCardSelector>(
              find.byType(PaymentLinkCardSelector),
            )
            .artwork,
        artwork,
        reason: '$artwork',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('selector rail covers both lanes and its selection edges', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    for (final layout in WbLayout.values) {
      _previewing(layout);
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildGiftCardsSelectorRailGalleryCase,
        label: 'Selection',
        optionLabels: GiftCardsRailSelection.values
            .map(giftCardsRailSelectionLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }
    _previewingBothLanes();
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsSelectorRailGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // The rail only animates on a selection change, so at rest the knob is
    // asserted on the media query it feeds rather than on pixels.
    _previewing(wbCompiledLaneLayout);
    for (final reduced in const ['false', 'true']) {
      await pumpUseCase(
        tester,
        buildGiftCardsSelectorRailGalleryCase,
        knobs: {'Reduced motion': reduced},
      );
      expect(tester.takeException(), isNull, reason: reduced);
      final railContext = tester.element(
        find.byType(PaymentLinkCardSelectorRail),
      );
      expect(
        MediaQuery.of(railContext).disableAnimations,
        reduced == 'true',
        reason: reduced,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('QR share card covers every artwork and the QR error', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsQrShareCardGalleryCase,
      label: 'QR',
      optionLabels: GiftCardsShareQrSymbol.values
          .map(giftCardsShareQrSymbolLabel)
          .toList(),
    );

    for (final artwork in giftCardsComponentArtworkOptions) {
      await pumpUseCase(
        tester,
        buildGiftCardsQrShareCardGalleryCase,
        knobs: {'Artwork': giftCardsShareArtworkLabel(artwork)},
      );
      expect(tester.takeException(), isNull, reason: '$artwork');
      expect(
        tester
            .widget<PaymentLinkQrShareCard>(find.byType(PaymentLinkQrShareCard))
            .artwork,
        artwork,
        reason: '$artwork',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('action shell covers its states and its icon slots', (
    tester,
  ) async {
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsActionShellGalleryCase,
      label: 'State',
      optionLabels: GiftCardsActionState.values
          .map(giftCardsActionStateLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsActionShellGalleryCase,
      label: 'Slots',
      optionLabels: GiftCardsActionSlots.values
          .map(giftCardsActionSlotsLabel)
          .toList(),
    );

    // Disabled drops the handler the shell forwards to its action.
    for (final state in GiftCardsActionState.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsActionShellGalleryCase,
        knobs: {'State': giftCardsActionStateLabel(state)},
      );
      expect(tester.takeException(), isNull, reason: '$state');
      expect(
        tester
            .widget<PaymentLinkTextAction>(find.byType(PaymentLinkTextAction))
            .enabled,
        state != GiftCardsActionState.disabled,
        reason: '$state',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('archive header covers expansion, counts and focus', (
    tester,
  ) async {
    // The chevron is an SVG glyph that does not decode in a widget test, so
    // expansion is asserted on the header rather than on pixels.
    for (final expanded in const ['false', 'true']) {
      await pumpUseCase(
        tester,
        buildGiftCardsArchiveHeaderGalleryCase,
        knobs: {'Expanded': expanded},
      );
      expect(tester.takeException(), isNull, reason: expanded);
      expect(
        tester
            .widget<PaymentLinkArchiveHeader>(
              find.byType(PaymentLinkArchiveHeader),
            )
            .expanded,
        expanded == 'true',
        reason: expanded,
      );
    }

    for (final count in GiftCardsArchiveCount.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsArchiveHeaderGalleryCase,
        knobs: {'Count': giftCardsArchiveCountLabel(count)},
      );
      expect(tester.takeException(), isNull, reason: '$count');
      expect(
        find.text('Archived (${giftCardsArchiveCountValue(count)})'),
        findsOneWidget,
        reason: '$count',
      );
    }
    await disposeTree(tester);

    // The focus border is a paint-only difference.
    await _expectSettledOptionsRenderDistinctly(
      tester,
      buildGiftCardsArchiveHeaderGalleryCase,
      label: 'Focused',
      optionLabels: const ['false', 'true'],
    );
  });

  testWidgets('wizard stepper covers its steps and its interaction states', (
    tester,
  ) async {
    _ignoreExpectedOverflow();
    _previewing(WbLayout.desktop);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildGiftCardsWizardStepperGalleryCase,
      label: 'Step',
      optionLabels: GiftCardsWizardStep.values
          .map(giftCardsWizardStepLabel)
          .toList(),
    );

    // Interactive and busy paint the same and differ only in the handler; the
    // focused option is the one that adds a ring.
    final fingerprints = <GiftCardsStepperInteraction, String>{};
    for (final interaction in GiftCardsStepperInteraction.values) {
      await pumpUseCase(
        tester,
        buildGiftCardsWizardStepperGalleryCase,
        knobs: {'Interaction': giftCardsStepperInteractionLabel(interaction)},
      );
      await _settleFixture(tester);
      expect(tester.takeException(), isNull, reason: '$interaction');
      expect(
        tester
                .widget<PaymentLinkWizardStepper>(
                  find.byType(PaymentLinkWizardStepper),
                )
                .onStepSelected !=
            null,
        interaction != GiftCardsStepperInteraction.busy,
        reason: '$interaction',
      );
      fingerprints[interaction] = await useCaseFingerprint(tester);
    }
    expect(
      fingerprints[GiftCardsStepperInteraction.focused],
      isNot(fingerprints[GiftCardsStepperInteraction.interactive]),
    );
    await disposeTree(tester);
  });
}

/// The `PrettyQrView` errorBuilder the share composite falls back to when the
/// payload does not fit a symbol.
final Finder _qrErrorIcon = find.byWidgetPredicate(
  (widget) =>
      widget is AppIcon &&
      widget.semanticLabel == 'QR code could not be generated',
);

/// Whether the pumps in flight are known to overflow.
bool _overflowExpected = false;

/// Ignores overflow raised while [_overflowExpected] is set.
///
/// Previewing a mobile widget under desktop tokens (and the reverse) overflows
/// a few pixels — the approximation the Layout knob is documented to make —
/// and [_previewingLabelBoundSurface] marks the rest. On every other pump the
/// real handler stays in place, so an overflow in the compiled lane fails the
/// test.
void _ignoreExpectedOverflow() {
  final inner = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_overflowExpected &&
        details.exception.toString().contains('overflowed')) {
      return;
    }
    inner?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = inner;
    _overflowExpected = false;
  });
}

/// Declares which lane the pumps that follow render.
void _previewing(WbLayout layout) =>
    _overflowExpected = layout != wbCompiledLaneLayout;

/// Declares that the pumps that follow sweep both lanes in one call.
void _previewingBothLanes() => _overflowExpected = true;

/// Declares that the pumps that follow render a label-bound surface: a status
/// row, a dashed status pill, or one of the two desktop panes that fill the
/// 1080x720 minimum window. Their text is laid out in the test font, whose
/// glyphs are wider than the product font, so the label pushes its row past
/// the edge here and not in the app.
void _previewingLabelBoundSurface() => _overflowExpected = true;

Future<void> _settleFixture(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Asserts a knob option is distinguished by the preview widget it mounts,
/// for pairs whose first painted frame is identical.
Future<void> _expectPreviewType<T extends Widget>(
  WidgetTester tester,
  WidgetBuilder builder, {
  required Map<String, String> knobs,
  required bool present,
}) async {
  await pumpUseCase(tester, builder, knobs: knobs);
  expect(tester.takeException(), isNull, reason: '$knobs');
  expect(
    find.byType(T),
    present ? findsWidgets : findsNothing,
    reason: '$knobs',
  );
  await disposeTree(tester);
}

/// The stepper reads the same in both states and only drops its handler, so
/// the knob is asserted on the widget rather than on pixels.
Future<void> _expectStepperEnabled(
  WidgetTester tester,
  WidgetBuilder builder, {
  required WbLayout layout,
}) async {
  for (final enabled in const ['true', 'false']) {
    await pumpUseCase(
      tester,
      builder,
      knobs: {'Layout': wbLayoutLabel(layout), 'Stepper enabled': enabled},
    );
    final steppers = tester
        .widgetList<PaymentLinkWizardStepper>(
          find.byType(PaymentLinkWizardStepper),
        )
        .toList();
    expect(steppers, isNotEmpty, reason: 'Stepper enabled / $enabled');
    expect(
      steppers.every((stepper) => stepper.onStepSelected != null),
      enabled == 'true',
      reason: 'Stepper enabled / $enabled',
    );
  }
  await disposeTree(tester);
}

/// Like [expectKnobOptionsRenderDistinctly], but lets running animations and
/// async fixture loads advance before the pixels are hashed.
Future<void> _expectSettledOptionsRenderDistinctly(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
  Size canvasSize = const Size(1600, 1200),
}) async {
  final seen = <String, String>{};
  for (final option in optionLabels) {
    await pumpUseCase(
      tester,
      builder,
      knobs: {...otherKnobs, label: option},
      canvasSize: canvasSize,
    );
    await _settleFixture(tester);
    expect(tester.takeException(), isNull, reason: '$label / $option');

    final fingerprint = await useCaseFingerprint(tester);
    expect(
      seen[fingerprint],
      isNull,
      reason:
          "'$label' options '${seen[fingerprint]}' and '$option' render "
          'identically.',
    );
    seen[fingerprint] = option;
  }
  await disposeTree(tester);
}
