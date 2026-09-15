import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/donation/widgets/donation_views.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import 'package:zcash_wallet/widgetbook/donation_use_cases.dart';
import 'package:zcash_wallet/widgetbook/gallery/pay_gallery.dart';
import 'package:zcash_wallet/widgetbook/pay_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Lane-agnostic: every layout-dependent assertion drives the `Layout` knob
// explicitly, so both test lanes exercise the same combinations. Untagged on
// purpose, so the mobile lane runs this file without `--tags mobile`:
// `fvm flutter test --dart-define=VIZOR_FORM_FACTOR=mobile <this file>`.
void main() {
  // Real fonts: the fallback test font is wider, which overflows the
  // fixed-size desktop fixtures that fit fine in the app.
  setUpAll(_loadAppFonts);

  testWidgets('every pay gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(payGalleryNodes).toList();
    expect(useCases.length, 8);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('wizard shell renders the real screen in both lanes', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildPayWizardShellGalleryCase,
      label: 'Pricing',
      optionLabels: PayScreenPricingCase.values
          .map(payScreenPricingCaseLabel)
          .toList(),
      otherKnobs: const {'Layout': 'Mobile'},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildPayWizardShellGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // The desktop half is gated to its own lane: the real sidebar overflows
    // the 720px window by 2px under mobile typography.
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayWizardShellGalleryCase,
        label: 'Pricing',
        optionLabels: PayScreenPricingCase.values
            .map(payScreenPricingCaseLabel)
            .toList(),
        otherKnobs: const {'Layout': 'Desktop'},
      );

      // The production slippage control, not the widgetbook stub the flat
      // amount-step fixtures pass as `headingTrailing`.
      await pumpUseCase(
        tester,
        buildPayWizardShellGalleryCase,
        knobs: {'Layout': 'Desktop'},
      );
      expect(
        find.text('Static preview · use knobs to change state'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay_slippage_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('pay_amount_step')), findsOneWidget);
    }
    await disposeTree(tester);
  });

  testWidgets('wizard stepper shows each step and gates its back taps', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildPayWizardStepperGalleryCase,
      label: 'Step',
      optionLabels: PayWizardStepperStep.values
          .map(payWizardStepperStepLabel)
          .toList(),
    );

    // Selectable is a handler, not a paint: on the last step the two earlier
    // chips gain (or lose) their tap targets.
    for (final selectable in const ['true', 'false']) {
      await pumpUseCase(
        tester,
        buildPayWizardStepperGalleryCase,
        knobs: {
          'Step': payWizardStepperStepLabel(PayWizardStepperStep.review),
          'Selectable': selectable,
        },
      );
      expect(
        find.byKey(const ValueKey('pay_wizard_step_back_0')),
        selectable == 'true' ? findsOneWidget : findsNothing,
        reason: selectable,
      );
      expect(
        find.byKey(const ValueKey('pay_wizard_step_back_1')),
        selectable == 'true' ? findsOneWidget : findsNothing,
        reason: selectable,
      );
    }

    // The first step has nothing completed behind it, so nothing is tappable
    // even with a handler.
    await pumpUseCase(
      tester,
      buildPayWizardStepperGalleryCase,
      knobs: {'Step': payWizardStepperStepLabel(PayWizardStepperStep.amount)},
    );
    expect(find.byKey(const ValueKey('pay_wizard_step_back_0')), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('amount step sweeps every axis in both lanes', (tester) async {
    for (final layout in WbLayout.values) {
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayAmountStepGalleryCase,
        label: 'Mode',
        optionLabels: PayAmountMode.values.map(payAmountModeLabel).toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayAmountStepGalleryCase,
        label: 'Amount',
        optionLabels: PayAmountEntry.values.map(payAmountEntryLabel).toList(),
        otherKnobs: lane,
      );
      // Pricing and Error only read as themselves with an amount typed: the
      // skeletons and every error line are gated on a non-empty field.
      final typed = {
        ...lane,
        'Amount': payAmountEntryLabel(PayAmountEntry.typed),
      };
      final emptyState = await pumpUseCase(
        tester,
        buildPayAmountStepGalleryCase,
        knobs: lane,
      );
      expect(emptyState.knobs.keys, isNot(contains('Pricing')));
      expect(emptyState.knobs.keys, isNot(contains('Error')));
      final typedState = await pumpUseCase(
        tester,
        buildPayAmountStepGalleryCase,
        knobs: typed,
      );
      expect(typedState.knobs.keys, containsAll(['Pricing', 'Error']));
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayAmountStepGalleryCase,
        label: 'Pricing',
        optionLabels: PayAmountPricing.values
            .map(payAmountPricingLabel)
            .toList(),
        otherKnobs: typed,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayAmountStepGalleryCase,
        label: 'Error',
        optionLabels: payAmountErrorOptions(
          layout,
        ).map(payAmountErrorLabel).toList(),
        otherKnobs: typed,
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildPayAmountStepGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // Guards the reason the unfocused fixtures are not options: Material
    // TextField overwrites the node's canRequestFocus, so `focused: false`
    // still autofocuses and would be a dead knob value.
    await pumpUseCase(tester, buildPayAmountEmptyUnfocusedUseCase);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'WidgetbookPayAmount',
    );
    await disposeTree(tester);
  });

  testWidgets('amount step derives its errors from the composer state', (
    tester,
  ) async {
    const typed = 'Typed';
    for (final layout in WbLayout.values) {
      final lane = wbLayoutLabel(layout);

      await pumpUseCase(
        tester,
        buildPayAmountStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Amount': typed,
          'Error': payAmountErrorLabel(PayAmountError.tooManyDecimals),
        },
      );
      expect(
        find.text('USDC supports up to 6 decimal places.'),
        findsOneWidget,
      );

      // In fiat mode the field holds the USD amount, so the over-precise
      // token amount the error names is the counterpart line under it.
      await pumpUseCase(
        tester,
        buildPayAmountStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Mode': payAmountModeLabel(PayAmountMode.fiat),
          'Amount': typed,
          'Error': payAmountErrorLabel(PayAmountError.tooManyDecimals),
        },
      );
      expect(
        find.text('USDC supports up to 6 decimal places.'),
        findsOneWidget,
      );
      expect(find.textContaining('25.1234567 USDC'), findsOneWidget);

      await pumpUseCase(
        tester,
        buildPayAmountStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Amount': typed,
          'Error': payAmountErrorLabel(PayAmountError.assetUnavailable),
        },
      );
      expect(find.textContaining('not currently supported'), findsOneWidget);

      await pumpUseCase(
        tester,
        buildPayAmountStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Amount': typed,
          'Error': payAmountErrorLabel(PayAmountError.quoteFailed),
        },
      );
      expect(find.textContaining('No quote is available'), findsOneWidget);

      // Estimated spend has no value to show without a price.
      await pumpUseCase(
        tester,
        buildPayAmountStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Amount': typed,
          'Pricing': payAmountPricingLabel(PayAmountPricing.noPrice),
        },
      );
      expect(find.text('--'), findsOneWidget);
    }

    // Mobile-only balance guard, and it disables Continue.
    await pumpUseCase(
      tester,
      buildPayAmountStepGalleryCase,
      knobs: {
        'Layout': 'Mobile',
        'Amount': typed,
        'Error': payAmountErrorLabel(PayAmountError.notEnoughZec),
      },
    );
    expect(find.text('Not enough ZEC'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
          )
          .onPressed,
      isNull,
    );
    await disposeTree(tester);
  });

  testWidgets('recipient step sweeps every axis in both lanes', (tester) async {
    for (final layout in WbLayout.values) {
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayRecipientStepGalleryCase,
        label: 'Address',
        optionLabels: PayRecipientAddress.values
            .map(payRecipientAddressLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayRecipientStepGalleryCase,
        label: 'Lists',
        optionLabels: PayRecipientLists.values
            .map(payRecipientListsLabel)
            .toList(),
        otherKnobs: lane,
      );
      // Availability and the quote error only surface through the bottom
      // actions, which need a valid address to render at all.
      final valid = {
        ...lane,
        'Address': payRecipientAddressLabel(PayRecipientAddress.unknownAddress),
      };
      final emptyState = await pumpUseCase(
        tester,
        buildPayRecipientStepGalleryCase,
        knobs: lane,
      );
      expect(emptyState.knobs.keys, isNot(contains('Availability')));
      expect(emptyState.knobs.keys, isNot(contains('Quote error')));
      final validState = await pumpUseCase(
        tester,
        buildPayRecipientStepGalleryCase,
        knobs: valid,
      );
      expect(
        validState.knobs.keys,
        containsAll(['Availability', 'Quote error']),
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayRecipientStepGalleryCase,
        label: 'Availability',
        optionLabels: PayRecipientAvailability.values
            .map(payRecipientAvailabilityLabel)
            .toList(),
        otherKnobs: valid,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayRecipientStepGalleryCase,
        label: 'Quote error',
        optionLabels: PayRecipientQuoteError.values
            .map(payRecipientQuoteErrorLabel)
            .toList(),
        otherKnobs: valid,
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildPayRecipientStepGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('recipient step shows the state each option names', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      final lane = wbLayoutLabel(layout);

      await pumpUseCase(
        tester,
        buildPayRecipientStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Address': payRecipientAddressLabel(
            PayRecipientAddress.invalidAddress,
          ),
        },
      );
      expect(find.text('Invalid EVM address'), findsOneWidget);

      // Both preview contacts hold the same address, so the matched list keeps
      // the duplicate-selection indicator and marks the selected one.
      await pumpUseCase(
        tester,
        buildPayRecipientStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Address': payRecipientAddressLabel(
            PayRecipientAddress.matchingContact,
          ),
        },
      );
      expect(find.bySemanticsLabel('Selected contact'), findsOneWidget);

      await pumpUseCase(
        tester,
        buildPayRecipientStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Address': payRecipientAddressLabel(
            PayRecipientAddress.unknownAddress,
          ),
          'Availability': payRecipientAvailabilityLabel(
            PayRecipientAvailability.fetchingQuote,
          ),
        },
      );
      expect(find.text('Fetching quote'), findsWidgets);

      await pumpUseCase(
        tester,
        buildPayRecipientStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Address': payRecipientAddressLabel(
            PayRecipientAddress.unknownAddress,
          ),
          'Availability': payRecipientAvailabilityLabel(
            PayRecipientAvailability.contactsLoading,
          ),
          'Quote error': payRecipientQuoteErrorLabel(
            PayRecipientQuoteError.routeRejected,
          ),
        },
      );
      expect(find.textContaining('was rejected'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(
                ValueKey(
                  layout == WbLayout.mobile
                      ? 'mobile_pay_recipient_continue_button'
                      : 'pay_select_recipient_button',
                ),
              ),
            )
            .onPressed,
        isNull,
      );

      await pumpUseCase(
        tester,
        buildPayRecipientStepGalleryCase,
        knobs: {
          'Layout': lane,
          'Lists': payRecipientListsLabel(PayRecipientLists.neither),
        },
      );
      expect(find.text('Recently sent'), findsNothing);
    }
    await disposeTree(tester);
  });

  testWidgets('review sweeps every axis in both lanes', (tester) async {
    for (final layout in WbLayout.values) {
      final lane = {'Layout': wbLayoutLabel(layout)};
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayReviewGalleryCase,
        label: 'Quote',
        optionLabels: PayReviewQuote.values.map(payReviewQuoteLabel).toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayReviewGalleryCase,
        label: 'Recipient',
        optionLabels: PayReviewRecipient.values
            .map(payReviewRecipientLabel)
            .toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayReviewGalleryCase,
        label: 'Fiat',
        optionLabels: PayReviewFiat.values.map(payReviewFiatLabel).toList(),
        otherKnobs: lane,
      );
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayReviewGalleryCase,
        label: 'Submit',
        optionLabels: payReviewSubmitOptions(
          layout,
        ).map(payReviewSubmitLabel).toList(),
        otherKnobs: lane,
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildPayReviewGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('review shows the state each option names', (tester) async {
    for (final layout in WbLayout.values) {
      final lane = wbLayoutLabel(layout);

      await pumpUseCase(
        tester,
        buildPayReviewGalleryCase,
        knobs: {'Layout': lane},
      );
      expect(find.textContaining(payReviewTickingExpiryText), findsOneWidget);

      // No ticking remainder yet: the quote's own label fills the divider.
      await pumpUseCase(
        tester,
        buildPayReviewGalleryCase,
        knobs: {
          'Layout': lane,
          'Quote': payReviewQuoteLabel(PayReviewQuote.staticLabel),
        },
      );
      expect(find.textContaining('1:30'), findsOneWidget);

      final expiredState = await pumpUseCase(
        tester,
        buildPayReviewGalleryCase,
        knobs: {
          'Layout': lane,
          'Quote': payReviewQuoteLabel(PayReviewQuote.expired),
        },
      );
      expect(expiredState.knobs.keys, isNot(contains('Submit')));

      await pumpUseCase(
        tester,
        buildPayReviewGalleryCase,
        knobs: {
          'Layout': lane,
          'Recipient': payReviewRecipientLabel(
            PayReviewRecipient.unknownAddress,
          ),
        },
      );
      expect(find.text('Unknown address'), findsOneWidget);

      await pumpUseCase(
        tester,
        buildPayReviewGalleryCase,
        knobs: {
          'Layout': lane,
          'Submit': payReviewSubmitLabel(PayReviewSubmit.paying),
        },
      );
      expect(find.text('Paying'), findsWidgets);

      await pumpUseCase(
        tester,
        buildPayReviewGalleryCase,
        knobs: {
          'Layout': lane,
          'Submit': payReviewSubmitLabel(PayReviewSubmit.notEnoughZec),
        },
      );
      expect(find.text('Not enough ZEC'), findsWidgets);
    }

    // The desktop review is the only lane with a start-error line...
    await pumpUseCase(
      tester,
      buildPayReviewGalleryCase,
      knobs: {
        'Layout': 'Desktop',
        'Submit': payReviewSubmitLabel(PayReviewSubmit.couldNotStart),
      },
    );
    expect(
      find.byKey(const ValueKey('pay_review_start_error')),
      findsOneWidget,
    );

    // ...and the mobile one the only lane that can lose its quote entirely.
    await pumpUseCase(
      tester,
      buildPayReviewGalleryCase,
      knobs: {
        'Layout': 'Mobile',
        'Submit': payReviewSubmitLabel(PayReviewSubmit.returnToPay),
      },
    );
    expect(find.text('Return to pay'), findsWidgets);
    expect(find.text('Cancel'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('add contact swaps the card per lane', (tester) async {
    // Two separate widget classes, so both lanes preview rather than showing
    // the lane notice.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildPayAddContactGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    await pumpUseCase(
      tester,
      buildPayAddContactGalleryCase,
      knobs: {'Layout': wbLayoutLabel(wbCompiledLaneLayout)},
    );
    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsNothing);
    expect(find.text('Chain & address'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('status covers the desktop phases and the mobile screen', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildPayStatusGalleryCase,
      knobs: {'Layout': 'Mobile'},
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('pay_submitted_title')), findsOneWidget);

    // Desktop-only fixture: with mobile typography its pane overflows by 2px,
    // which is the lane approximation the layout knob warns about rather than
    // a gallery defect, so the pixel sweep runs where the tokens match.
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildPayStatusGalleryCase,
        label: 'Phase',
        optionLabels: PayStatusPhase.values.map(payStatusPhaseLabel).toList(),
        otherKnobs: {'Layout': 'Desktop'},
      );
    }
    await disposeTree(tester);
  });

  testWidgets('mobile pay status covers every deposit phase', (tester) async {
    const bodies = <PayMobileStatusCase, String>{
      PayMobileStatusCase.submitting:
          'Submitting your payment to the network...',
      PayMobileStatusCase.submitted:
          'It will confirm on-chain shortly.\nTrack it in Activity.',
      PayMobileStatusCase.statusUncertain:
          'The network did not acknowledge this payment yet. '
          'Check Activity before trying again.',
      PayMobileStatusCase.failed:
          'The payment could not be submitted. '
          'Try again.',
      PayMobileStatusCase.paymentUnavailable:
          "We couldn't load this payment. Check Activity for its latest "
          'status.',
      PayMobileStatusCase.submissionInterrupted:
          'The payment status is uncertain. Check Activity before trying '
          'again.',
    };
    for (final entry in bodies.entries) {
      await pumpUseCase(
        tester,
        buildPayStatusGalleryCase,
        knobs: {
          'Layout': 'Mobile',
          'Status': payMobileStatusCaseLabel(entry.key),
        },
      );
      // The two recovery presentations only replace the in-progress base once
      // the intent-restore grace timer fires.
      await tester.pump(
        kMobilePayIntentRestoreGrace + const Duration(milliseconds: 100),
      );
      expect(tester.takeException(), isNull, reason: entry.key.name);
      expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);
    }
    await disposeTree(tester);
  });

  testWidgets('donation screen gates its currency toggle on a live price', (
    tester,
  ) async {
    // Desktop-only screen; the mobile lane shows the lane notice instead.
    if (wbCompiledLaneLayout != WbLayout.desktop) return;
    for (final price in DonationScreenPriceCase.values) {
      await pumpUseCase(
        tester,
        buildDonationScreenGalleryCase,
        knobs: {'Price': donationScreenPriceCaseLabel(price)},
      );
      expect(tester.takeException(), isNull, reason: price.name);
      // The two options are pixel-identical at rest — the screen only drops
      // the toggle callback — so the knob is asserted on that callback.
      final view = tester.widget<DonationComposeView>(
        find.byType(DonationComposeView),
      );
      expect(
        view.onToggleMode,
        price == DonationScreenPriceCase.available ? isNotNull : isNull,
        reason: price.name,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('donation compose and status sweep every fixture', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildDonationComposeGalleryCase,
      label: 'Currency',
      optionLabels: DonationComposeMode.values
          .map(donationComposeModeLabel)
          .toList(),
    );
    for (final mode in DonationComposeMode.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildDonationComposeGalleryCase,
        label: 'Amount',
        optionLabels: DonationComposeAmount.values
            .map(donationComposeAmountLabel)
            .toList(),
        otherKnobs: {'Currency': donationComposeModeLabel(mode)},
      );
    }
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildDonationComposeGalleryCase,
      label: 'Error',
      optionLabels: DonationComposeError.values
          .map(donationComposeErrorLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildDonationComposeGalleryCase,
      label: 'Submitting',
      optionLabels: const ['false', 'true'],
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildDonationStatusGalleryCase,
      label: 'Status',
      optionLabels: DonationStatusCase.values
          .map(donationStatusCaseLabel)
          .toList(),
    );
  });

  test('the currency and amount pair still reaches the pinned corners', () {
    expect(
      donationComposeAmountProps(
        DonationComposeMode.zec,
        DonationComposeAmount.empty,
      ),
      same(donationComposeZecEmptyAmount),
    );
    expect(
      donationComposeAmountProps(
        DonationComposeMode.zec,
        DonationComposeAmount.preset,
      ),
      same(donationComposeZecPresetAmount),
    );
    expect(
      donationComposeAmountProps(
        DonationComposeMode.zec,
        DonationComposeAmount.midCursor,
      ),
      same(donationComposeZecMidCursorAmount),
    );
    expect(
      donationComposeAmountProps(
        DonationComposeMode.usd,
        DonationComposeAmount.preset,
      ),
      same(donationComposeUsdPresetAmount),
    );
  });

  testWidgets('donation compose shows the state each option names', (
    tester,
  ) async {
    for (final error in DonationComposeError.values) {
      await pumpUseCase(
        tester,
        buildDonationComposeGalleryCase,
        knobs: {'Error': donationComposeErrorLabel(error)},
      );
      final text = donationComposeErrorText(error);
      if (text == null) {
        expect(find.text('Invalid amount'), findsNothing);
      } else {
        expect(find.text(text), findsOneWidget, reason: error.name);
      }
    }

    // The CTA swaps its label for a spinner while the donation is submitting.
    await pumpUseCase(
      tester,
      buildDonationComposeGalleryCase,
      knobs: {'Submitting': 'true'},
    );
    expect(find.text('Continue'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Price is a callback, not a paint: without a live price the currency
    // switch under the amount is inert.
    for (final price in DonationScreenPriceCase.values) {
      await pumpUseCase(
        tester,
        buildDonationComposeGalleryCase,
        knobs: {'Price': donationScreenPriceCaseLabel(price)},
      );
      expect(
        tester
            .widget<DonationComposeView>(find.byType(DonationComposeView))
            .onToggleMode,
        price == DonationScreenPriceCase.available ? isNotNull : isNull,
        reason: price.name,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('donation review gates its confirm button and fiat line', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildDonationReviewGalleryCase,
      label: 'Fiat',
      optionLabels: DonationReviewFiat.values
          .map(donationReviewFiatLabel)
          .toList(),
    );

    for (final confirm in DonationReviewConfirm.values) {
      await pumpUseCase(
        tester,
        buildDonationReviewGalleryCase,
        knobs: {'Confirm': donationReviewConfirmLabel(confirm)},
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('donation_confirm_button')),
            )
            .onPressed,
        confirm == DonationReviewConfirm.enabled ? isNotNull : isNull,
        reason: confirm.name,
      );
    }

    await pumpUseCase(
      tester,
      buildDonationReviewGalleryCase,
      knobs: {'Fiat': donationReviewFiatLabel(DonationReviewFiat.absent)},
    );
    expect(find.text(r'$250.12'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('donation recipient row strikes through on demand', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildDonationRecipientRowGalleryCase,
      label: 'State',
      optionLabels: DonationRecipientRowState.values
          .map(donationRecipientRowStateLabel)
          .toList(),
    );

    await pumpUseCase(tester, buildDonationRecipientRowGalleryCase);
    expect(
      tester
          .widget<DonationRecipientInfoRow>(
            find.byType(DonationRecipientInfoRow),
          )
          .struckThrough,
      isFalse,
    );

    // The badge case is the row's leading slot on its own.
    await pumpUseCase(tester, buildDonationVizorBadgeUseCase);
    expect(find.byType(DonationVizorBadge), findsOneWidget);
    expect(find.byType(DonationRecipientInfoRow), findsNothing);
    await disposeTree(tester);
  });
}

Future<void> _loadAppFonts() async {
  final fonts = <String, List<String>>{
    'Geist': [
      'assets/fonts/Geist-Regular.ttf',
      'assets/fonts/Geist-Medium.ttf',
      'assets/fonts/Geist-SemiBold.ttf',
    ],
    'Geist Mono': [
      'assets/fonts/GeistMono-Regular.ttf',
      'assets/fonts/GeistMono-Medium.ttf',
    ],
    'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}
