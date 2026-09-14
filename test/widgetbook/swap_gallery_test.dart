import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/features/address_book/widgets/address_book_contact_picker_modal.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_address_edit_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_icon.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_asset_selector_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_slippage_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_modal_controls.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_status_page_content.dart';
import 'package:zcash_wallet/widgetbook/gallery/swap_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/swap_mobile_use_cases.dart';
import 'package:zcash_wallet/widgetbook/swap_use_cases.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// The layout knob is driven by explicit query params, never by the compiled
// lane, so both lanes exercise the same combinations — but this is a
// desktop-lane suite by design (AGENTS.md, 'Gallery tests'): several of these
// tests fail under `--dart-define=VIZOR_FORM_FACTOR=mobile` because the mobile
// typography and sizing tokens overflow the fixed frames these fixtures pin
// (2px in the modals, 64px on the mobile status route, 5.7px on the activity
// page panel). Those overflows live in production widgets, so they are a
// mobile-geometry finding for the lead, not something this file can assert
// around.
void main() {
  for (final layout in WbLayout.values) {
    testWidgets('${layout.name} payment detail isolates explorer launch', (
      tester,
    ) async {
      await pumpUseCase(
        tester,
        buildSwapActivityDetailGalleryCase,
        knobs: {
          'Layout': wbLayoutLabel(layout),
          'Mode': swapActivityModeLabel(SwapActivityMode.payment),
        },
      );
      // The processing illustration loops while the detail remains mounted.
      await tester.pump(const Duration(milliseconds: 300));
      final surface = tester.widget<SwapActivityDetailSurface>(
        find.byType(SwapActivityDetailSurface),
      );
      expect(surface.launchExternalUri, isNotNull);
      await tester.tap(find.text('Tx ID'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(SwapActivityDetailSurface), findsOneWidget);
      await disposeTree(tester);
    });
  }
  testWidgets('every swap gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(swapGalleryNodes).toList();
    expect(useCases.length, 21);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('swap page playground covers every frame and state', (
    tester,
  ) async {
    for (final frame in SwapComposerFrame.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSwapPageGalleryCase,
        label: 'State',
        // An open pill is a posed composer state on the mock frames and a
        // hosted modal on the real screen, so every option stays distinct in
        // both.
        optionLabels: SwapComposerFixture.values
            .map(swapComposerFixtureLabel)
            .toList(),
        otherKnobs: {..._desktop, 'Frame': swapComposerFrameLabel(frame)},
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapPageGalleryCase,
      label: 'Frame',
      optionLabels: SwapComposerFrame.values
          .map(swapComposerFrameLabel)
          .toList(),
      otherKnobs: _desktop,
    );
  });

  testWidgets('every folded surface registers one knob set per layout', (
    tester,
  ) async {
    // Disjoint state axes: each lane registers only the knobs it has, so the
    // knob set itself follows the Layout knob.
    for (final frame in [SwapComposerFrame.page, SwapComposerFrame.widget]) {
      expect(
        await _knobLabels(
          tester,
          buildSwapPageGalleryCase,
          WbLayout.desktop,
          otherKnobs: {'Frame': swapComposerFrameLabel(frame)},
        ),
        ['Layout', 'Frame', 'State'],
        reason: swapComposerFrameLabel(frame),
      );
    }
    expect(
      await _knobLabels(
        tester,
        buildSwapPageGalleryCase,
        WbLayout.desktop,
        otherKnobs: {'Frame': swapComposerFrameLabel(SwapComposerFrame.screen)},
      ),
      ['Layout', 'Frame', 'State', 'Modal', 'Pane', 'Hide amounts'],
    );
    expect(
      await _knobLabels(tester, buildSwapPageGalleryCase, WbLayout.mobile),
      ['Layout', 'CTA', 'Quote error', 'Number pad open'],
    );
    expect(
      await _knobLabels(tester, buildSwapReviewGalleryCase, WbLayout.desktop),
      ['Layout', 'Quote', 'State'],
    );
    expect(
      await _knobLabels(tester, buildSwapReviewGalleryCase, WbLayout.mobile),
      ['Layout', 'Mode', 'Quote', 'Blocked'],
    );
    expect(
      await _knobLabels(tester, buildSwapStatusGalleryCase, WbLayout.desktop),
      ['Layout', 'Status', 'Amount size'],
    );
    expect(
      await _knobLabels(tester, buildSwapStatusGalleryCase, WbLayout.mobile),
      ['Layout', 'Mode', 'Status', 'Tab', 'Recipient', 'Deposit tx'],
    );

    // Keystone signing is the one fold whose lanes share their axis names —
    // the options behind them are what differ.
    for (final layout in WbLayout.values) {
      expect(
        await _knobLabels(tester, buildSwapKeystoneSigningGalleryCase, layout),
        ['Layout', 'Phase', 'Error'],
        reason: wbLayoutLabel(layout),
      );
    }
    expect(
      await _knobOptionLabels(
        tester,
        buildSwapKeystoneSigningGalleryCase,
        WbLayout.desktop,
        'Phase',
      ),
      ['Preparing', 'Ready to sign'],
    );
    expect(
      await _knobOptionLabels(
        tester,
        buildSwapKeystoneSigningGalleryCase,
        WbLayout.mobile,
        'Phase',
      ),
      ['Preparing', 'QR code'],
    );
    await disposeTree(tester);
  });

  testWidgets('swap screen frame renders the real screen and its modals', (
    tester,
  ) async {
    final screenFrame = {
      ..._desktop,
      'Frame': swapComposerFrameLabel(SwapComposerFrame.screen),
    };
    await pumpUseCase(tester, buildSwapPageGalleryCase, knobs: screenFrame);
    expect(tester.takeException(), isNull);
    expect(find.byType(SwapScreen), findsOneWidget);
    expect(find.byType(AppMainSidebar), findsOneWidget);
    expect(
      find.text('Static preview · modals are driven by knobs'),
      findsOneWidget,
    );

    // The contact picker needs two driven frames (address editor, then its
    // contacts button), which is one more than the fingerprint sweep pumps —
    // so this axis asserts the hosted widget per option instead.
    expect(find.byType(AppPaneModalOverlay), findsNothing);

    // Each modal is the production widget the screen hosts, reached by the
    // trigger's own callback rather than a posed overlay.
    for (final entry in <SwapScreenOverlay, Type>{
      SwapScreenOverlay.assetSelector: SwapAssetSelectorModal,
      SwapScreenOverlay.addressEditor: SwapAddressEditModal,
      SwapScreenOverlay.contactPicker: AddressBookContactPickerModal,
      SwapScreenOverlay.slippage: SwapSlippageModal,
    }.entries) {
      await pumpUseCase(
        tester,
        buildSwapPageGalleryCase,
        knobs: {...screenFrame, 'Modal': swapScreenOverlayLabel(entry.key)},
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byType(entry.value),
        findsOneWidget,
        reason: swapScreenOverlayLabel(entry.key),
      );
    }
    await disposeTree(tester);
  });

  testWidgets('swap screen covers the pane heights and the privacy mask', (
    tester,
  ) async {
    final screenFrame = {
      ..._desktop,
      'Frame': swapComposerFrameLabel(SwapComposerFrame.screen),
      'State': swapComposerFixtureLabel(SwapComposerFixture.directionSwitched),
    };
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapPageGalleryCase,
      label: 'Pane',
      optionLabels: SwapScreenPane.values.map(swapScreenPaneLabel).toList(),
      otherKnobs: screenFrame,
    );

    // The max trigger reads the migration-aware spendable balance, so the
    // privacy mask is visible on the composer itself.
    await pumpUseCase(tester, buildSwapPageGalleryCase, knobs: screenFrame);
    expect(find.textContaining('12.3456'), findsWidgets);
    await pumpUseCase(
      tester,
      buildSwapPageGalleryCase,
      knobs: {...screenFrame, 'Hide amounts': 'true'},
    );
    expect(find.textContaining('12.3456'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('swap review screen covers its notices and action labels', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapReviewGalleryCase,
      label: 'State',
      optionLabels: SwapReviewScreenCase.values
          .map(swapReviewScreenCaseLabel)
          .toList(),
      otherKnobs: _desktop,
    );

    for (final entry in <SwapReviewScreenCase, String>{
      SwapReviewScreenCase.payment: 'Confirm payment',
      SwapReviewScreenCase.expired: 'Review again',
      SwapReviewScreenCase.notEnoughZec: 'Not enough ZEC',
      SwapReviewScreenCase.submitting: 'Locking quote',
    }.entries) {
      await pumpUseCase(
        tester,
        buildSwapReviewGalleryCase,
        knobs: {..._desktop, 'State': swapReviewScreenCaseLabel(entry.key)},
      );
      expect(tester.takeException(), isNull, reason: entry.value);
      expect(find.text(entry.value), findsWidgets, reason: entry.value);
    }

    await pumpUseCase(
      tester,
      buildSwapReviewGalleryCase,
      knobs: {
        ..._desktop,
        'State': swapReviewScreenCaseLabel(SwapReviewScreenCase.startError),
      },
    );
    expect(find.textContaining('could not lock this quote'), findsOneWidget);
    await pumpUseCase(
      tester,
      buildSwapReviewGalleryCase,
      knobs: {
        ..._desktop,
        'State': swapReviewScreenCaseLabel(SwapReviewScreenCase.amountDrift),
      },
    );
    expect(find.textContaining('Live quote'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('composer delegates keep the fixture parameters', (tester) async {
    // The Figma node 5 fixture is the only composer state with its own
    // balance / max overrides, so it is the one the extraction could drop.
    await pumpUseCase(tester, buildSwapPageFigmaNode5UseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Add recipient address'), findsOneWidget);
    expect(find.textContaining('128'), findsWidgets);
    await disposeTree(tester);
  });

  testWidgets('slippage covers layout, mode and every tolerance', (
    tester,
  ) async {
    const desktop = {'Layout': 'Desktop'};
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapSlippageGalleryCase,
      label: 'Value',
      optionLabels: SwapSlippageValue.values
          .map(swapSlippageValueLabel)
          .toList(),
      otherKnobs: desktop,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapSlippageGalleryCase,
      label: 'Mode',
      optionLabels: SwapSlippageMode.values.map(swapSlippageModeLabel).toList(),
      otherKnobs: desktop,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapSlippageGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // The mobile stepper clamps out-of-range input away, so it keeps the
    // presets while the destructive message stays a desktop-only state.
    await pumpUseCase(
      tester,
      buildSwapSlippageGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Value': swapSlippageValueLabel(SwapSlippageValue.presetTwo),
      },
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Slippage must be 0.1 - 5%'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('asset selector covers layout, query, selection and length', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      final otherKnobs = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSwapAssetSelectorGalleryCase,
        label: 'Query',
        optionLabels: SwapAssetModalQuery.values
            .map(swapAssetModalQueryLabel)
            .toList(),
        otherKnobs: otherKnobs,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSwapAssetSelectorGalleryCase,
        label: 'Selection',
        optionLabels: SwapAssetModalSelection.values
            .map(swapAssetModalSelectionLabel)
            .toList(),
        otherKnobs: otherKnobs,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSwapAssetSelectorGalleryCase,
        label: 'List length',
        optionLabels: SwapAssetModalLength.values
            .map(swapAssetModalLengthLabel)
            .toList(),
        otherKnobs: otherKnobs,
      );
    }

    await pumpUseCase(
      tester,
      buildSwapAssetSelectorGalleryCase,
      knobs: {'Query': swapAssetModalQueryLabel(SwapAssetModalQuery.noMatch)},
    );
    expect(find.text('No tokens or chains found'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('address editor covers direction, format and contact match', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapAddressEditorGalleryCase,
      label: 'Direction',
      optionLabels: SwapAddressModalDirection.values
          .map(swapAddressModalDirectionLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapAddressEditorGalleryCase,
      label: 'Address',
      optionLabels: SwapAddressModalFormat.values
          .map(swapAddressModalFormatLabel)
          .toList(),
    );
    // A contact only shows under an address that has no finding of its own.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapAddressEditorGalleryCase,
      label: 'Contact match',
      optionLabels: SwapAddressModalContact.values
          .map(swapAddressModalContactLabel)
          .toList(),
      otherKnobs: {
        'Address': swapAddressModalFormatLabel(SwapAddressModalFormat.valid),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapAddressEditorGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    // Only the mobile modal takes the remembered flag as a prop.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapAddressEditorGalleryCase,
      label: 'Remember address',
      optionLabels: const ['false', 'true'],
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
  });

  testWidgets('address editor routes every format finding', (tester) async {
    await pumpUseCase(
      tester,
      buildSwapAddressEditorGalleryCase,
      knobs: {
        'Address': swapAddressModalFormatLabel(SwapAddressModalFormat.invalid),
      },
    );
    expect(
      find.byKey(const ValueKey('swap_destination_format_error')),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildSwapAddressEditorGalleryCase,
      knobs: {
        'Address': swapAddressModalFormatLabel(SwapAddressModalFormat.unusual),
      },
    );
    expect(
      find.byKey(const ValueKey('swap_destination_format_warning')),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildSwapAddressEditorGalleryCase,
      knobs: {
        'Address': swapAddressModalFormatLabel(SwapAddressModalFormat.valid),
        'Contact match': swapAddressModalContactLabel(
          SwapAddressModalContact.matched,
        ),
      },
    );
    expect(
      find.byKey(const ValueKey('swap_destination_contact_match')),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('deposit pages cover their wait states and both layouts', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSwapDepositTokensGalleryCase,
        label: 'Deposit',
        optionLabels: _swapDepositFingerprintOptions
            .map(swapDepositTokensCaseLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }

    // The mobile frame is the reason the parameterized fixture carries the
    // expiry and memo axes at all, so it is asserted on the memo row.
    await pumpUseCase(
      tester,
      buildSwapDepositTokensGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Deposit': swapDepositTokensCaseLabel(SwapDepositTokensCase.memoAndQr),
      },
    );
    expect(find.text('memo with & routing=value?'), findsOneWidget);
    await pumpUseCase(
      tester,
      buildSwapDepositTokensGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Deposit': swapDepositTokensCaseLabel(
          SwapDepositTokensCase.staticExpiry,
        ),
      },
    );
    expect(find.text('2hrs'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSwapDepositTokensGalleryCase,
      knobs: {
        'Deposit': swapDepositTokensCaseLabel(
          SwapDepositTokensCase.checkFailed,
        ),
      },
    );
    expect(find.text("Couldn't check the deposit. Retrying."), findsOneWidget);

    // The elapsed countdown differs from the running one only in the five
    // characters of the deadline label, which the test font renders as five
    // identical boxes — so it is asserted on the label, not on pixels.
    await pumpUseCase(
      tester,
      buildSwapDepositTokensGalleryCase,
      knobs: {
        'Deposit': swapDepositTokensCaseLabel(SwapDepositTokensCase.elapsed),
      },
    );
    expect(find.text('00:00'), findsOneWidget);

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapHardwareZecDepositGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    await pumpUseCase(
      tester,
      buildSwapHardwareZecDepositGalleryCase,
      knobs: {'Memo': 'true'},
    );
    expect(find.text('swap-staging-memo'), findsOneWidget);

    // Layout and Memo keep the pinned static label; only Countdown swaps the
    // clock, so the two axes are not read through a deadline difference.
    for (final layout in WbLayout.values) {
      await pumpUseCase(
        tester,
        buildSwapHardwareZecDepositGalleryCase,
        knobs: {'Layout': wbLayoutLabel(layout)},
      );
      expect(find.text('2hrs'), findsOneWidget, reason: wbLayoutLabel(layout));
    }
    await pumpUseCase(
      tester,
      buildSwapHardwareZecDepositGalleryCase,
      knobs: {'Countdown': 'true'},
    );
    expect(find.text('2hrs'), findsNothing);
    expect(find.text('09:00'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('deposit timeout covers both form factors', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapDepositTimeoutGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    await pumpUseCase(
      tester,
      buildSwapDepositTimeoutGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(
      find.byKey(const ValueKey('mobile_swap_timeout_content')),
      findsOneWidget,
    );
    expect(find.text('Restart swap'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('single-axis knobs cover every option distinctly', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapReviewGalleryCase,
      label: 'Quote',
      optionLabels: SwapReviewQuote.values.map(swapReviewQuoteLabel).toList(),
      otherKnobs: _desktop,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapDepositTokensGalleryCase,
      label: 'Deposit',
      optionLabels: _swapDepositFingerprintOptions
          .map(swapDepositTokensCaseLabel)
          .toList(),
    );
  });

  testWidgets('swap status covers the status and amount-size axes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapStatusGalleryCase,
      label: 'Status',
      optionLabels: SwapStatusCase.values.map(swapStatusCaseLabel).toList(),
      otherKnobs: {
        ..._desktop,
        'Amount size': swapStatusAmountsLabel(SwapStatusAmounts.standard),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapStatusGalleryCase,
      label: 'Amount size',
      optionLabels: SwapStatusAmounts.values
          .map(swapStatusAmountsLabel)
          .toList(),
      otherKnobs: {
        ..._desktop,
        'Status': swapStatusCaseLabel(SwapStatusCase.inProgress),
      },
    );
  });

  _mobileSwapGalleryTests();
  _swapChunk3GalleryTests();
}

void _mobileSwapGalleryTests() {
  testWidgets('mobile swap composer covers the CTA ladder', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapPageGalleryCase,
      label: 'CTA',
      optionLabels: SwapMobileCta.values.map(swapMobileCtaLabel).toList(),
      otherKnobs: _mobile,
    );
  });

  testWidgets('mobile swap composer covers the error line and number pad', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapPageGalleryCase,
      label: 'Quote error',
      optionLabels: SwapMobileQuoteError.values
          .map(swapMobileQuoteErrorLabel)
          .toList(),
      otherKnobs: {
        ..._mobile,
        'CTA': swapMobileCtaLabel(SwapMobileCta.continueToReview),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapPageGalleryCase,
      label: 'Number pad open',
      optionLabels: const ['false', 'true'],
      otherKnobs: _mobile,
    );
  });

  testWidgets('mobile composer ticket covers every axis', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapTicketGalleryCase,
      label: 'Direction',
      optionLabels: SwapMobileTicketDirection.values
          .map(swapMobileTicketDirectionLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapTicketGalleryCase,
      label: 'Active side',
      optionLabels: SwapMobileTicketSide.values
          .map(swapMobileTicketSideLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapTicketGalleryCase,
      label: 'Amount mode',
      optionLabels: SwapMobileTicketAmountMode.values
          .map(swapMobileTicketAmountModeLabel)
          .toList(),
    );
    // The max trigger only renders on the ZEC-paying side.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapTicketGalleryCase,
      label: 'Max trigger',
      optionLabels: SwapMobileTicketMax.values
          .map(swapMobileTicketMaxLabel)
          .toList(),
      otherKnobs: {
        'Direction': swapMobileTicketDirectionLabel(
          SwapMobileTicketDirection.zecToUsdc,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapTicketGalleryCase,
      label: 'Destination',
      optionLabels: SwapMobileTicketDestination.values
          .map(swapMobileTicketDestinationLabel)
          .toList(),
    );
  });

  testWidgets('mobile swap review covers mode, quote and blocked', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapReviewGalleryCase,
      label: 'Mode',
      optionLabels: SwapMobileReviewMode.values
          .map(swapMobileReviewModeLabel)
          .toList(),
      otherKnobs: _mobile,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapReviewGalleryCase,
      label: 'Quote',
      optionLabels: SwapMobileReviewQuoteCase.values
          .map(swapMobileReviewQuoteCaseLabel)
          .toList(),
      otherKnobs: _mobile,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapReviewGalleryCase,
      label: 'Blocked',
      optionLabels: SwapMobileReviewBlocked.values
          .map(swapMobileReviewBlockedLabel)
          .toList(),
      otherKnobs: _mobile,
    );
  });

  testWidgets('mobile swap review titles follow the mode', (tester) async {
    await pumpUseCase(
      tester,
      buildSwapReviewGalleryCase,
      knobs: {
        ..._mobile,
        'Mode': swapMobileReviewModeLabel(SwapMobileReviewMode.swap),
      },
    );
    expect(find.text('Review quote'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSwapReviewGalleryCase,
      knobs: {
        ..._mobile,
        'Mode': swapMobileReviewModeLabel(SwapMobileReviewMode.payment),
      },
    );
    expect(find.text('Review Payment'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile review content covers direction, notices and labels', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapReviewContentGalleryCase,
      label: 'Direction',
      optionLabels: SwapMobileReviewDirection.values
          .map(swapMobileReviewDirectionLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapReviewContentGalleryCase,
      label: 'Notice',
      optionLabels: SwapMobileReviewNotice.values
          .map(swapMobileReviewNoticeLabel)
          .toList(),
    );
    // Both address lines overflow one row, so the test font paints them as the
    // same bar — assert the strings instead of the pixels.
    await pumpUseCase(
      tester,
      buildMobileSwapReviewContentGalleryCase,
      knobs: {
        'Address label': swapMobileReviewAddressLabelLabel(
          SwapMobileReviewAddressLabel.plain,
        ),
      },
    );
    expect(find.textContaining('To: 0x1111'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildMobileSwapReviewContentGalleryCase,
      knobs: {
        'Address label': swapMobileReviewAddressLabelLabel(
          SwapMobileReviewAddressLabel.contact,
        ),
      },
    );
    expect(find.textContaining('To: Mike'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile review actions label every primary state', (
    tester,
  ) async {
    const expectedLabels = {
      SwapMobileReviewAction.confirm: 'Confirm & swap',
      SwapMobileReviewAction.reviewAgain: 'Review again',
      SwapMobileReviewAction.notEnoughZec: 'Not enough ZEC',
      SwapMobileReviewAction.starting: 'Sending',
      SwapMobileReviewAction.noLongerActive: 'Return to swap',
    };
    for (final entry in expectedLabels.entries) {
      await pumpUseCase(
        tester,
        buildMobileSwapReviewActionsGalleryCase,
        knobs: {'Action': swapMobileReviewActionLabel(entry.key)},
      );
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }

    // Only the inactive state drops the Cancel affordance.
    expect(find.text('Cancel'), findsNothing);

    // The starting label is the one thing the direction axis changes.
    await pumpUseCase(
      tester,
      buildMobileSwapReviewActionsGalleryCase,
      knobs: {
        'Action': swapMobileReviewActionLabel(SwapMobileReviewAction.starting),
        'Direction': swapMobileActionsDirectionLabel(
          SwapMobileActionsDirection.receivesZec,
        ),
      },
    );
    expect(find.text('Locking quote'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile swap status covers every axis of the presentation', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapStatusGalleryCase,
      label: 'Mode',
      optionLabels: SwapMobileStatusMode.values
          .map(swapMobileStatusModeLabel)
          .toList(),
      otherKnobs: _mobile,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapStatusGalleryCase,
      label: 'Status',
      optionLabels: SwapMobileStatusCase.values
          .map(swapMobileStatusCaseLabel)
          .toList(),
      otherKnobs: _mobile,
    );
    // The tabs only exist while the swap is in flight.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapStatusGalleryCase,
      label: 'Tab',
      optionLabels: SwapMobileStatusTab.values
          .map(swapMobileStatusTabLabel)
          .toList(),
      otherKnobs: {
        ..._mobile,
        'Status': swapMobileStatusCaseLabel(SwapMobileStatusCase.inProgress),
      },
    );
    // Both recipient lines fill the same row, so the test font paints them as
    // one bar — assert the resolved text instead of the pixels.
    await pumpUseCase(
      tester,
      buildSwapStatusGalleryCase,
      knobs: {
        ..._mobile,
        'Recipient': swapMobileStatusRecipientLabel(
          SwapMobileStatusRecipient.contact,
        ),
      },
    );
    expect(find.textContaining('To: Mike'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSwapStatusGalleryCase,
      knobs: {
        ..._mobile,
        'Recipient': swapMobileStatusRecipientLabel(
          SwapMobileStatusRecipient.address,
        ),
      },
    );
    expect(find.textContaining('To: 0x1111'), findsOneWidget);

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapStatusGalleryCase,
      label: 'Deposit tx',
      optionLabels: SwapMobileStatusDepositTx.values
          .map(swapMobileStatusDepositTxLabel)
          .toList(),
      otherKnobs: _mobile,
    );
  });

  testWidgets('mobile swap status keeps the mapper routing', (tester) async {
    await pumpUseCase(tester, buildSwapStatusGalleryCase, knobs: _mobile);
    expect(find.text('Swap progress'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_status_header')),
      findsNothing,
    );

    // Payment mode swaps the header and relabels the progress tab.
    await pumpUseCase(
      tester,
      buildSwapStatusGalleryCase,
      knobs: {
        ..._mobile,
        'Mode': swapMobileStatusModeLabel(SwapMobileStatusMode.payment),
      },
    );
    expect(find.text('Payment progress'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_status_header')),
      findsOneWidget,
    );

    // A completed swap drops the tabs for the terminal status card.
    await pumpUseCase(
      tester,
      buildSwapStatusGalleryCase,
      knobs: {
        ..._mobile,
        'Status': swapMobileStatusCaseLabel(SwapMobileStatusCase.completed),
      },
    );
    expect(find.text('Swap progress'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_swap_status_card')),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('mobile Keystone sign covers both phases', (tester) async {
    await pumpUseCase(
      tester,
      buildSwapKeystoneSigningGalleryCase,
      knobs: {
        ..._mobile,
        'Phase': swapMobileKeystonePhaseLabel(
          SwapMobileKeystonePhase.preparing,
        ),
      },
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Loading QR code ...'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_swap_keystone_sign_qr_placeholder'),
        skipOffstage: false,
      ),
      findsWidgets,
    );

    await pumpUseCase(
      tester,
      buildSwapKeystoneSigningGalleryCase,
      knobs: {
        ..._mobile,
        'Phase': swapMobileKeystonePhaseLabel(SwapMobileKeystonePhase.qrCode),
      },
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Loading QR code ...'), findsNothing);
    expect(find.text('Next step'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile Keystone sign maps every failure to its copy', (
    tester,
  ) async {
    const expected = {
      SwapMobileKeystoneError.texUnsupported:
          'Keystone does not support TEX sends yet.',
      SwapMobileKeystoneError.saplingParams:
          'Required proving parameters could not be prepared.',
      SwapMobileKeystoneError.proposalExpired:
          'Transaction expired before it could be signed.',
      SwapMobileKeystoneError.signatureNotApplied:
          'Keystone signature could not be applied.',
      SwapMobileKeystoneError.broadcastFailed:
          'Transaction could not be broadcast.',
      SwapMobileKeystoneError.generic:
          'ZEC deposit signing could not be completed.',
    };
    for (final entry in expected.entries) {
      await pumpUseCase(
        tester,
        buildSwapKeystoneSigningGalleryCase,
        knobs: {..._mobile, 'Error': swapMobileKeystoneErrorLabel(entry.key)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(find.text('Keystone signing failed'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }
    await disposeTree(tester);
  });

  testWidgets('mobile review header covers its three axes', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapReviewHeaderGalleryCase,
      label: 'Bottom line',
      optionLabels: SwapMobileHeaderBottomLine.values
          .map(swapMobileHeaderBottomLineLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapReviewHeaderGalleryCase,
      label: 'Asset',
      optionLabels: SwapMobileHeaderAsset.values
          .map(swapMobileHeaderAssetLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileSwapReviewHeaderGalleryCase,
      label: 'Full address action',
      optionLabels: const ['false', 'true'],
    );
  });
}

void _swapChunk3GalleryTests() {
  const desktop = {'Layout': 'Desktop'};

  testWidgets('desktop Keystone overlay covers both phases', (tester) async {
    for (final phase in SwapKeystoneOverlayPhase.values) {
      await pumpUseCase(
        tester,
        buildSwapKeystoneSigningGalleryCase,
        knobs: {...desktop, 'Phase': swapKeystoneOverlayPhaseLabel(phase)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$phase');
      expect(
        tester
            .widget<KeystoneSigningModal>(find.byType(KeystoneSigningModal))
            .phase,
        phase == SwapKeystoneOverlayPhase.preparing
            ? KeystoneSigningModalPhase.preparing
            : KeystoneSigningModalPhase.ready,
        reason: '$phase',
      );
    }
    expect(find.text('Sign ZEC deposit on Keystone'), findsOneWidget);
    expect(find.text('Get signature'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('desktop Keystone overlay maps every failure to its copy', (
    tester,
  ) async {
    const expected = {
      SwapKeystoneOverlayError.texUnsupported:
          'Keystone does not support TEX sends yet.',
      SwapKeystoneOverlayError.provingParameters:
          'Required proving parameters could not be prepared.',
      SwapKeystoneOverlayError.proposalExpired:
          'Transaction expired before it could be signed.',
      SwapKeystoneOverlayError.signatureNotApplied:
          'Keystone signature could not be applied.',
      SwapKeystoneOverlayError.broadcastFailed:
          'Transaction could not be broadcast.',
      SwapKeystoneOverlayError.generic:
          'ZEC deposit signing could not be completed.',
    };
    for (final entry in expected.entries) {
      await pumpUseCase(
        tester,
        buildSwapKeystoneSigningGalleryCase,
        knobs: {...desktop, 'Error': swapKeystoneOverlayErrorLabel(entry.key)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(
        tester
            .widget<KeystoneSigningModal>(find.byType(KeystoneSigningModal))
            .phase,
        KeystoneSigningModalPhase.failed,
        reason: '${entry.key}',
      );
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }
    await disposeTree(tester);
  });

  testWidgets('swap activity detail routes every status', (tester) async {
    // In-flight statuses share the 'Swap in progress...' title and differ only
    // in which route step carries the loader. `Processing` and `Status
    // unknown` render identically here (see `SwapActivityStatusCase`), so they
    // are the one pair with a shared expectation.
    const activeStepIndexes = {
      SwapActivityStatusCase.awaitingDeposit: 0,
      SwapActivityStatusCase.depositObserved: 1,
      SwapActivityStatusCase.processing: 2,
      SwapActivityStatusCase.statusUnknown: 2,
      SwapActivityStatusCase.incompleteDeposit: 2,
    };
    for (final entry in activeStepIndexes.entries) {
      await pumpUseCase(
        tester,
        buildSwapActivityDetailGalleryCase,
        knobs: {...desktop, 'Status': swapActivityStatusCaseLabel(entry.key)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(
        find.byKey(ValueKey('swap_activity_route_step_${entry.value}_active')),
        findsOneWidget,
        reason: '${entry.key}',
      );
    }
    // `Incomplete deposit` keeps the tabs but takes its own title.
    expect(find.text('Incomplete deposit'), findsWidgets);

    // The terminal statuses drop the tabs for the final card, which is the one
    // place the status label itself is printed.
    const terminalLabels = {
      SwapActivityStatusCase.complete: 'Complete',
      SwapActivityStatusCase.refunded: 'Refunded',
      SwapActivityStatusCase.failed: 'Failed',
    };
    for (final entry in terminalLabels.entries) {
      await pumpUseCase(
        tester,
        buildSwapActivityDetailGalleryCase,
        knobs: {...desktop, 'Status': swapActivityStatusCaseLabel(entry.key)},
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(
        find.byKey(const ValueKey('swap_final_details')),
        findsOneWidget,
        reason: '${entry.key}',
      );
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }

    await pumpUseCase(
      tester,
      buildSwapActivityDetailGalleryCase,
      knobs: {
        ...desktop,
        'Status': swapActivityStatusCaseLabel(
          SwapActivityStatusCase.awaitingExternalDeposit,
        ),
      },
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('swap_deposit_tokens_panel')),
      findsOneWidget,
    );
    expect(find.text('Deposit ZEC'), findsNothing);

    await pumpUseCase(
      tester,
      buildSwapActivityDetailGalleryCase,
      knobs: {
        ...desktop,
        'Status': swapActivityStatusCaseLabel(SwapActivityStatusCase.expired),
      },
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('swap_deposit_timeout_panel')),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('swap activity detail covers intent, notice and hardware', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSwapActivityDetailGalleryCase,
      knobs: {
        ...desktop,
        'Intent': swapActivityIntentCaseLabel(SwapActivityIntentCase.missing),
      },
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('swap_activity_detail_missing')),
      findsOneWidget,
    );

    await pumpUseCase(
      tester,
      buildSwapActivityDetailGalleryCase,
      knobs: {
        ...desktop,
        'Intent': swapActivityIntentCaseLabel(SwapActivityIntentCase.found),
        'Notice': swapActivityNoticeLabel(
          SwapActivityNotice.statusRefreshError,
        ),
      },
    );
    await tester.pump();
    expect(
      find.textContaining('Could not refresh the swap status'),
      findsOneWidget,
    );

    // A hardware account turns the awaiting-deposit status into the ZEC
    // deposit page with its own signing action.
    await pumpUseCase(
      tester,
      buildSwapActivityDetailGalleryCase,
      knobs: {
        ...desktop,
        'Status': swapActivityStatusCaseLabel(
          SwapActivityStatusCase.awaitingDeposit,
        ),
        'Hardware account': 'true',
      },
    );
    await tester.pump();
    expect(find.text('Deposit ZEC'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('swap activity detail covers mode and layout', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapActivityDetailGalleryCase,
      label: 'Mode',
      optionLabels: SwapActivityMode.values.map(swapActivityModeLabel).toList(),
      otherKnobs: desktop,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapActivityDetailGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('swap activity page panel covers content and layout', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapActivityPagePanelGalleryCase,
      label: 'Content',
      optionLabels: SwapActivityPagePanelContent.values
          .map(swapActivityPagePanelContentLabel)
          .toList(),
      otherKnobs: desktop,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapActivityPagePanelGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    await pumpUseCase(
      tester,
      buildSwapActivityPagePanelGalleryCase,
      knobs: {
        ...desktop,
        'Content': swapActivityPagePanelContentLabel(
          SwapActivityPagePanelContent.depositPage,
        ),
      },
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('swap_deposit_tokens_panel')),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('progress route covers length, active step and copy', (
    tester,
  ) async {
    const fourSteps = {'Steps': 'Four steps'};
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapProgressRouteGalleryCase,
      label: 'Steps',
      optionLabels: SwapProgressRouteLength.values
          .map(swapProgressRouteLengthLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapProgressRouteGalleryCase,
      label: 'Active step',
      optionLabels: SwapProgressRouteStep.values
          .map(swapProgressRouteStepLabel)
          .toList(),
      otherKnobs: fourSteps,
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapProgressRouteGalleryCase,
      label: 'Supporting copy',
      optionLabels: SwapProgressRouteCopy.values
          .map(swapProgressRouteCopyLabel)
          .toList(),
      otherKnobs: fourSteps,
    );
  });

  testWidgets('progress route variant picks the live-quote wrapper', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSwapProgressRouteGalleryCase,
      knobs: {
        'Variant': swapProgressRouteVariantLabel(
          SwapProgressRouteVariant.plain,
        ),
      },
    );
    expect(find.byType(SwapAnimatedProgressRoute), findsNothing);
    expect(find.byType(SwapProgressRoute), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSwapProgressRouteGalleryCase,
      knobs: {
        'Variant': swapProgressRouteVariantLabel(
          SwapProgressRouteVariant.animated,
        ),
      },
    );
    expect(find.byType(SwapAnimatedProgressRoute), findsOneWidget);
    // The wrapper starts on its target step, so it schedules no advance timer
    // at the knob defaults (the active step's loader keeps spinning, which is
    // why this is not a `pumpAndSettle`).
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('swap_activity_route_step_0_active')),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('review info covers the detail line and the asset slot', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSwapReviewInfoGalleryCase,
      label: 'Side detail',
      optionLabels: SwapReviewInfoDetail.values
          .map(swapReviewInfoDetailLabel)
          .toList(),
    );

    // The copy affordance belongs to the address line only.
    await pumpUseCase(
      tester,
      buildSwapReviewInfoGalleryCase,
      knobs: {
        'Side detail': swapReviewInfoDetailLabel(
          SwapReviewInfoDetail.copyableAddress,
        ),
      },
    );
    expect(
      find.byKey(const ValueKey('swap_review_info_receive_copy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('swap_review_info_pay_copy')),
      findsNothing,
    );

    // The asset icons are bundle images, so assert the resolved symbol rather
    // than the pixels.
    const expectedAmounts = {
      SwapReviewInfoAsset.zec: '78.59 ZEC',
      SwapReviewInfoAsset.external: '78.59 USDC',
      SwapReviewInfoAsset.letterFallback: '78.59 QQQ',
    };
    for (final entry in expectedAmounts.entries) {
      await pumpUseCase(
        tester,
        buildSwapReviewInfoGalleryCase,
        knobs: {'Asset': swapReviewInfoAssetLabel(entry.key)},
      );
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
    }
    await disposeTree(tester);
  });

  testWidgets('asset icon covers asset, badge, selection and size', (
    tester,
  ) async {
    const expectedBadgeKeys = {
      SwapAssetIconAsset.zec: 'swap_asset_chain_badge_zec',
      SwapAssetIconAsset.usdc: 'swap_asset_chain_badge_usdc',
      SwapAssetIconAsset.unknown: 'swap_asset_chain_badge_widgetbook:unknown',
    };
    for (final entry in expectedBadgeKeys.entries) {
      await pumpUseCase(
        tester,
        buildSwapAssetIconGalleryCase,
        knobs: {'Asset': swapAssetIconAssetLabel(entry.key)},
      );
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(
        find.byKey(ValueKey(entry.value)),
        findsOneWidget,
        reason: '${entry.key}',
      );
    }

    await pumpUseCase(
      tester,
      buildSwapAssetIconGalleryCase,
      knobs: {'Chain badge': 'false'},
    );
    expect(
      find.byKey(const ValueKey('swap_asset_chain_badge_usdc')),
      findsNothing,
    );

    // The letter fallback only paints once the bundle lookup fails, so the
    // selected tint is asserted on the prop that carries it.
    await pumpUseCase(
      tester,
      buildSwapAssetIconGalleryCase,
      knobs: {'Selected': 'true'},
    );
    expect(
      tester.widget<SwapAssetIcon>(find.byType(SwapAssetIcon)).selected,
      isTrue,
    );

    for (final size in SwapAssetIconSize.values) {
      await pumpUseCase(
        tester,
        buildSwapAssetIconGalleryCase,
        knobs: {'Size': swapAssetIconSizeLabel(size)},
      );
      expect(
        tester.getSize(find.byType(SwapAssetIcon)).width,
        size == SwapAssetIconSize.mobile ? 40 : 32,
        reason: '$size',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('NEAR Intents attribution covers every alignment', (
    tester,
  ) async {
    const expectedAlignments = {
      SwapAttributionAlignment.left: CrossAxisAlignment.start,
      SwapAttributionAlignment.centered: CrossAxisAlignment.center,
      SwapAttributionAlignment.end: CrossAxisAlignment.end,
    };
    for (final entry in expectedAlignments.entries) {
      await pumpUseCase(
        tester,
        buildSwapAttributionGalleryCase,
        knobs: {'Alignment': swapAttributionAlignmentLabel(entry.key)},
      );
      expect(tester.takeException(), isNull, reason: '${entry.key}');
      expect(
        tester
            .widget<Column>(
              find.byKey(const ValueKey('swap_near_intents_attribution')),
            )
            .crossAxisAlignment,
        entry.value,
        reason: '${entry.key}',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('modal controls cover every control variant', (tester) async {
    await pumpUseCase(
      tester,
      buildSwapModalControlsGalleryCase,
      knobs: {'Control': swapModalControlLabel(SwapModalControl.iconBadge)},
    );
    expect(find.byType(SwapModalIconBadge), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSwapModalControlsGalleryCase,
      knobs: {'Control': swapModalControlLabel(SwapModalControl.modalButtons)},
    );
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSwapModalControlsGalleryCase,
      knobs: {
        'Control': swapModalControlLabel(
          SwapModalControl.modalButtonsPrimaryDisabled,
        ),
      },
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('swap_modal_buttons_primary')),
          )
          .onPressed,
      isNull,
    );

    const inlineWidths = {
      SwapModalControl.inlineIconButtonDesktop: 20.0,
      SwapModalControl.inlineIconButtonMobile: 24.0,
    };
    for (final entry in inlineWidths.entries) {
      await pumpUseCase(
        tester,
        buildSwapModalControlsGalleryCase,
        knobs: {'Control': swapModalControlLabel(entry.key)},
      );
      expect(
        tester.getSize(find.byType(SwapInlineIconButton)).width,
        entry.value,
        reason: '${entry.key}',
      );
    }
    await disposeTree(tester);
  });
}

/// Deposit options the pixel sweep can tell apart. `Countdown elapsed` differs
/// from `Countdown` only in the deadline text, which the test font collapses
/// to identical boxes; it is asserted on its label instead.
const _swapDepositFingerprintOptions = [
  SwapDepositTokensCase.staticExpiry,
  SwapDepositTokensCase.countdown,
  SwapDepositTokensCase.memoAndQr,
  SwapDepositTokensCase.checking,
  SwapDepositTokensCase.checkFailed,
];

/// Layout knob values, passed explicitly so both lanes sweep the same
/// combinations.
const _desktop = {'Layout': 'Desktop'};
const _mobile = {'Layout': 'Mobile'};

/// Knob labels the use case registers for [layout], in registration order.
Future<List<String>> _knobLabels(
  WidgetTester tester,
  WidgetBuilder builder,
  WbLayout layout, {
  Map<String, String> otherKnobs = const {},
}) async {
  final state = await pumpUseCase(
    tester,
    builder,
    knobs: {'Layout': wbLayoutLabel(layout), ...otherKnobs},
  );
  return state.knobs.keys.toList();
}

/// Option labels of one dropdown knob, as the shareable URL encodes them.
Future<List<String>> _knobOptionLabels(
  WidgetTester tester,
  WidgetBuilder builder,
  WbLayout layout,
  String label,
) async {
  final state = await pumpUseCase(
    tester,
    builder,
    knobs: {'Layout': wbLayoutLabel(layout)},
  );
  final values = state.knobs[label]!.fields.single.toJson()['values'] as List;
  return values.cast<String>();
}
