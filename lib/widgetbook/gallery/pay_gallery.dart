// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/core/theme/app_theme.dart';
import '../donation_use_cases.dart';
import '../mobile_pay_use_cases.dart';
import '../pay_screen_use_cases.dart';
import '../pay_use_cases.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';

/// The Pay gallery: one use case per surface, every knob dispatching into a
/// parameterized fixture or an existing `build*UseCase`, so figma_compare and
/// the fixture tests keep the builders they bind to.
///
/// The wizard steps share both the `Layout` knob and their state axes across
/// lanes; only the options a lane has no counterpart for are filtered out
/// (`Not enough ZEC` is mobile-only, `Couldn't start` desktop-only). The
/// status and modal surfaces still carry per-lane axes, because their two
/// lanes were built from different Figma frames.
final List<WidgetbookNode> payGalleryNodes = [
  WidgetbookComponent(
    name: 'Pay screen',
    useCases: [
      WidgetbookUseCase(name: 'Screen', builder: buildPayScreenGalleryCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Pay amount step',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildPayAmountStepGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Pay recipient step',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildPayRecipientStepGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Pay review',
    useCases: [
      WidgetbookUseCase(name: 'Playground', builder: buildPayReviewGalleryCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Pay status',
    useCases: [
      WidgetbookUseCase(name: 'Playground', builder: buildPayStatusGalleryCase),
    ],
  ),
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Pay wizard stepper',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildPayWizardStepperGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Modals',
    children: [
      WidgetbookComponent(
        name: 'Pay modals',
        useCases: [
          WidgetbookUseCase(
            name: 'Asset selector',
            builder: buildPayAssetSelectorUseCase,
          ),
          WidgetbookUseCase(
            name: 'Add contact',
            builder: buildPayAddContactGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Pay screen ------------------------------------------------------------

/// Whether the pay composer still has pricing in flight; the amount step
/// renders skeleton bars for the counterpart and estimated-spend rows.
enum PayScreenPricingCase { loaded, loading }

Widget buildPayWizardShellGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final pricing = wbStateKnob<PayScreenPricingCase>(
    context,
    label: 'Pricing',
    options: PayScreenPricingCase.values,
    labelBuilder: payScreenPricingCaseLabel,
  );
  final loading = pricing == PayScreenPricingCase.loading;
  if (layout == WbLayout.mobile) {
    return _PayStaticPreview(
      child:
          loading
              ? buildMobilePayWizardShellPricingLoadingUseCase(context)
              : buildMobilePayWizardShellUseCase(context),
    );
  }
  // The real `AppMainSidebar` overflows the 1080x720 desktop window by 2px
  // under mobile typography, so this half of the knob is desktop-lane only.
  return _PayStaticPreview(
    child: WbLaneOnly(
      layout: WbLayout.desktop,
      child:
          loading
              ? buildPayWizardShellPricingLoadingUseCase(context)
              : buildPayWizardShellUseCase(context),
    ),
  );
}

/// The primary Pay screen is the bounded, in-memory interactive flow.  Keep
/// the old wizard-shell fixture above available for Figma scenarios and
/// focused snapshot tests, but do not register it as a second screen entry.
Widget buildPayScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final scenario = wbStateKnob<PayScreenSimulationScenario>(
    context,
    label: 'Scenario',
    options: PayScreenSimulationScenario.values,
    labelBuilder: payScreenSimulationScenarioLabel,
  );
  final pricing = wbStateKnob<PayScreenPricingCase>(
    context,
    label: 'Pricing',
    options: PayScreenPricingCase.values,
    labelBuilder: payScreenPricingCaseLabel,
  );
  return payInteractiveScreenFixture(
    mobile: layout == WbLayout.mobile,
    pricingLoading: pricing == PayScreenPricingCase.loading,
    scenario: scenario,
  );
}

class _PayStaticPreview extends StatelessWidget {
  const _PayStaticPreview({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          top: 12,
          right: 12,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.background.neutralScrim,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  'Static preview · use knobs to change state',
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: context.colors.text.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String payScreenPricingCaseLabel(PayScreenPricingCase pricing) {
  return switch (pricing) {
    PayScreenPricingCase.loaded => 'Loaded',
    PayScreenPricingCase.loading => 'Loading',
  };
}

// --- Pay wizard stepper ----------------------------------------------------

/// Which step the wizard is on; the chips before it are completed and the
/// ones after it upcoming.
enum PayWizardStepperStep { amount, recipient, review }

Widget buildPayWizardStepperGalleryCase(BuildContext context) {
  final step = wbStateKnob<PayWizardStepperStep>(
    context,
    label: 'Step',
    options: PayWizardStepperStep.values,
    labelBuilder: payWizardStepperStepLabel,
  );
  final selectable = wbBoolKnob(context, label: 'Selectable', initial: true);
  return payWizardStepperFixture(
    currentIndex: step.index,
    selectable: selectable,
  );
}

String payWizardStepperStepLabel(PayWizardStepperStep step) {
  return switch (step) {
    PayWizardStepperStep.amount => 'Amount',
    PayWizardStepperStep.recipient => 'Recipient',
    PayWizardStepperStep.review => 'Review',
  };
}

// --- Pay amount step -------------------------------------------------------

/// Which side of the pair the amount field edits.
enum PayAmountMode { token, fiat }

/// Whether the field carries an amount at all. Every other axis below only
/// reads as itself once something is typed.
enum PayAmountEntry { empty, typed }

/// State of the indicative price snapshot behind the counterpart and the
/// estimated ZEC spend.
enum PayAmountPricing { loaded, loading, noPrice }

/// The single error line the step can show, derived from the composer state.
/// 'Not enough ZEC' is the mobile step's own balance guard and has no desktop
/// counterpart.
enum PayAmountError {
  none,
  tooManyDecimals,
  assetUnavailable,
  quoteFailed,
  notEnoughZec,
}

List<PayAmountError> payAmountErrorOptions(WbLayout layout) {
  return layout == WbLayout.mobile
      ? PayAmountError.values
      : const [
        PayAmountError.none,
        PayAmountError.tooManyDecimals,
        PayAmountError.assetUnavailable,
        PayAmountError.quoteFailed,
      ];
}

Widget buildPayAmountStepGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final mode = wbStateKnob<PayAmountMode>(
    context,
    label: 'Mode',
    options: PayAmountMode.values,
    labelBuilder: payAmountModeLabel,
  );
  final entry = wbStateKnob<PayAmountEntry>(
    context,
    label: 'Amount',
    options: PayAmountEntry.values,
    labelBuilder: payAmountEntryLabel,
  );
  final fiatMode = mode == PayAmountMode.fiat;
  final emptyAmount = entry == PayAmountEntry.empty;
  final pricing =
      emptyAmount
          ? PayAmountPricing.loaded
          : wbStateKnob<PayAmountPricing>(
            context,
            label: 'Pricing',
            options: PayAmountPricing.values,
            labelBuilder: payAmountPricingLabel,
          );
  final error =
      emptyAmount
          ? PayAmountError.none
          : wbStateKnob<PayAmountError>(
            context,
            label: 'Error',
            options: payAmountErrorOptions(layout),
            labelBuilder: payAmountErrorLabel,
          );
  final pricingLoading = pricing == PayAmountPricing.loading;
  final priceUnavailable = pricing == PayAmountPricing.noPrice;
  if (layout == WbLayout.mobile) {
    return mobilePayAmountStepFixture(
      fiatMode: fiatMode,
      emptyAmount: emptyAmount,
      pricingLoading: pricingLoading,
      priceUnavailable: priceUnavailable,
      tooManyDecimals: error == PayAmountError.tooManyDecimals,
      assetUnavailable: error == PayAmountError.assetUnavailable,
      quoteFailed: error == PayAmountError.quoteFailed,
      notEnoughZec: error == PayAmountError.notEnoughZec,
    );
  }
  return payAmountStepFixture(
    fiatMode: fiatMode,
    emptyAmount: emptyAmount,
    pricingLoading: pricingLoading,
    priceUnavailable: priceUnavailable,
    tooManyDecimals: error == PayAmountError.tooManyDecimals,
    assetUnavailable: error == PayAmountError.assetUnavailable,
    quoteFailed: error == PayAmountError.quoteFailed,
  );
}

String payAmountModeLabel(PayAmountMode mode) {
  return switch (mode) {
    PayAmountMode.token => 'Token',
    PayAmountMode.fiat => 'Fiat',
  };
}

String payAmountEntryLabel(PayAmountEntry entry) {
  return switch (entry) {
    PayAmountEntry.empty => 'Empty',
    PayAmountEntry.typed => 'Typed',
  };
}

String payAmountPricingLabel(PayAmountPricing pricing) {
  return switch (pricing) {
    PayAmountPricing.loaded => 'Loaded',
    PayAmountPricing.loading => 'Loading',
    PayAmountPricing.noPrice => 'No price',
  };
}

String payAmountErrorLabel(PayAmountError error) {
  return switch (error) {
    PayAmountError.none => 'None',
    PayAmountError.tooManyDecimals => 'Too many decimals',
    PayAmountError.assetUnavailable => 'Asset unavailable',
    PayAmountError.quoteFailed => 'Quote failed',
    PayAmountError.notEnoughZec => 'Not enough ZEC',
  };
}

// --- Pay recipient step ----------------------------------------------------

/// What the address field holds; the list filtering, the new-address notice,
/// and the format error all follow from it.
enum PayRecipientAddress {
  empty,
  matchingContact,
  unknownAddress,
  invalidAddress,
}

/// Which saved lists the wallet has to offer.
enum PayRecipientLists {
  contactsAndRecents,
  contactsOnly,
  recentsOnly,
  neither,
}

/// Whether the step can act: quote in flight, or contacts still loading.
enum PayRecipientAvailability { ready, fetchingQuote, contactsLoading }

/// Provider verdict on the address the user picked.
enum PayRecipientQuoteError { none, routeRejected }

Widget buildPayRecipientStepGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final address = wbStateKnob<PayRecipientAddress>(
    context,
    label: 'Address',
    options: PayRecipientAddress.values,
    labelBuilder: payRecipientAddressLabel,
  );
  final lists = wbStateKnob<PayRecipientLists>(
    context,
    label: 'Lists',
    options: PayRecipientLists.values,
    labelBuilder: payRecipientListsLabel,
  );
  final hasValidAddress =
      address == PayRecipientAddress.matchingContact ||
      address == PayRecipientAddress.unknownAddress;
  final availability =
      hasValidAddress
          ? wbStateKnob<PayRecipientAvailability>(
            context,
            label: 'Availability',
            options: PayRecipientAvailability.values,
            labelBuilder: payRecipientAvailabilityLabel,
          )
          : PayRecipientAvailability.ready;
  final quoteError =
      hasValidAddress
          ? wbStateKnob<PayRecipientQuoteError>(
            context,
            label: 'Quote error',
            options: PayRecipientQuoteError.values,
            labelBuilder: payRecipientQuoteErrorLabel,
          )
          : PayRecipientQuoteError.none;
  final showContacts =
      lists == PayRecipientLists.contactsAndRecents ||
      lists == PayRecipientLists.contactsOnly;
  final showRecents =
      lists == PayRecipientLists.contactsAndRecents ||
      lists == PayRecipientLists.recentsOnly;
  final busy = availability == PayRecipientAvailability.fetchingQuote;
  final enabled = availability != PayRecipientAvailability.contactsLoading;
  final routeRejected = quoteError == PayRecipientQuoteError.routeRejected;
  if (layout == WbLayout.mobile) {
    return mobilePayRecipientStepFixture(
      address: payMobileRecipientAddressValue(address),
      showContacts: showContacts,
      showRecents: showRecents,
      busy: busy,
      enabled: enabled,
      routeRejected: routeRejected,
    );
  }
  return payRecipientStepFixture(
    address: payRecipientAddressValue(address),
    showContacts: showContacts,
    showRecents: showRecents,
    busy: busy,
    enabled: enabled,
    routeRejected: routeRejected,
  );
}

String payRecipientAddressValue(PayRecipientAddress address) {
  return switch (address) {
    PayRecipientAddress.empty => '',
    PayRecipientAddress.matchingContact => payFixtureKnownAddress,
    PayRecipientAddress.unknownAddress => payFixtureUnknownAddress,
    PayRecipientAddress.invalidAddress => payFixtureInvalidAddress,
  };
}

String payMobileRecipientAddressValue(PayRecipientAddress address) {
  return switch (address) {
    PayRecipientAddress.empty => '',
    PayRecipientAddress.matchingContact => mobilePayFixtureKnownAddress,
    PayRecipientAddress.unknownAddress => mobilePayFixtureUnknownAddress,
    PayRecipientAddress.invalidAddress => mobilePayFixtureInvalidAddress,
  };
}

String payRecipientAddressLabel(PayRecipientAddress address) {
  return switch (address) {
    PayRecipientAddress.empty => 'Empty',
    PayRecipientAddress.matchingContact => 'Matching contact',
    PayRecipientAddress.unknownAddress => 'Unknown address',
    PayRecipientAddress.invalidAddress => 'Invalid address',
  };
}

String payRecipientListsLabel(PayRecipientLists lists) {
  return switch (lists) {
    PayRecipientLists.contactsAndRecents => 'Contacts and recents',
    PayRecipientLists.contactsOnly => 'Contacts only',
    PayRecipientLists.recentsOnly => 'Recents only',
    PayRecipientLists.neither => 'Neither',
  };
}

String payRecipientAvailabilityLabel(PayRecipientAvailability availability) {
  return switch (availability) {
    PayRecipientAvailability.ready => 'Ready',
    PayRecipientAvailability.fetchingQuote => 'Fetching quote',
    PayRecipientAvailability.contactsLoading => 'Contacts loading',
  };
}

String payRecipientQuoteErrorLabel(PayRecipientQuoteError quoteError) {
  return switch (quoteError) {
    PayRecipientQuoteError.none => 'None',
    PayRecipientQuoteError.routeRejected => 'Route rejected',
  };
}

// --- Pay review ------------------------------------------------------------

/// Quote countdown state. 'Live (static label)' is the fallback the screens
/// render before the first tick, when the step has no remainder of its own.
enum PayReviewQuote { live, staticLabel, expired }

/// Whether the recipient resolves to a saved contact.
enum PayReviewRecipient { knownContact, unknownAddress }

/// Whether fiat equivalents accompany the token amounts.
enum PayReviewFiat { shown, absent }

/// The bottom action's state. 'Couldn't start' is desktop-only (the mobile
/// actions carry no error line) and 'Return to pay' is mobile-only.
enum PayReviewSubmit {
  confirm,
  paying,
  notEnoughZec,
  couldNotStart,
  returnToPay,
}

List<PayReviewSubmit> payReviewSubmitOptions(WbLayout layout) {
  return layout == WbLayout.mobile
      ? const [
        PayReviewSubmit.confirm,
        PayReviewSubmit.paying,
        PayReviewSubmit.notEnoughZec,
        PayReviewSubmit.returnToPay,
      ]
      : const [
        PayReviewSubmit.confirm,
        PayReviewSubmit.paying,
        PayReviewSubmit.notEnoughZec,
        PayReviewSubmit.couldNotStart,
      ];
}

Widget buildPayReviewGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final quote = wbStateKnob<PayReviewQuote>(
    context,
    label: 'Quote',
    options: PayReviewQuote.values,
    labelBuilder: payReviewQuoteLabel,
  );
  final recipient = wbStateKnob<PayReviewRecipient>(
    context,
    label: 'Recipient',
    options: PayReviewRecipient.values,
    labelBuilder: payReviewRecipientLabel,
  );
  final fiat = wbStateKnob<PayReviewFiat>(
    context,
    label: 'Fiat',
    options: PayReviewFiat.values,
    labelBuilder: payReviewFiatLabel,
  );
  final submit =
      quote == PayReviewQuote.expired
          ? PayReviewSubmit.confirm
          : wbStateKnob<PayReviewSubmit>(
            context,
            label: 'Submit',
            options: payReviewSubmitOptions(layout),
            labelBuilder: payReviewSubmitLabel,
          );
  final knownRecipient = recipient == PayReviewRecipient.knownContact;
  final showFiat = fiat == PayReviewFiat.shown;
  final expiresInText =
      quote == PayReviewQuote.staticLabel ? null : payReviewTickingExpiryText;
  if (layout == WbLayout.mobile) {
    return mobilePayReviewFixture(
      expired: quote == PayReviewQuote.expired,
      expiresInText: expiresInText,
      knownRecipient: knownRecipient,
      showFiat: showFiat,
      starting: submit == PayReviewSubmit.paying,
      notEnoughZec: submit == PayReviewSubmit.notEnoughZec,
      inactive: submit == PayReviewSubmit.returnToPay,
    );
  }
  return payReviewStepFixture(
    expired: quote == PayReviewQuote.expired,
    expiresInText: expiresInText,
    knownRecipient: knownRecipient,
    showFiat: showFiat,
    starting: submit == PayReviewSubmit.paying,
    notEnoughZec: submit == PayReviewSubmit.notEnoughZec,
    startFailed: submit == PayReviewSubmit.couldNotStart,
  );
}

String payReviewQuoteLabel(PayReviewQuote quote) {
  return switch (quote) {
    PayReviewQuote.live => 'Live',
    PayReviewQuote.staticLabel => 'Live (static label)',
    PayReviewQuote.expired => 'Expired',
  };
}

String payReviewRecipientLabel(PayReviewRecipient recipient) {
  return switch (recipient) {
    PayReviewRecipient.knownContact => 'Known contact',
    PayReviewRecipient.unknownAddress => 'Unknown address',
  };
}

String payReviewFiatLabel(PayReviewFiat fiat) {
  return switch (fiat) {
    PayReviewFiat.shown => 'Shown',
    PayReviewFiat.absent => 'Absent',
  };
}

String payReviewSubmitLabel(PayReviewSubmit submit) {
  return switch (submit) {
    PayReviewSubmit.confirm => 'Confirm and pay',
    PayReviewSubmit.paying => 'Paying',
    PayReviewSubmit.notEnoughZec => 'Not enough ZEC',
    PayReviewSubmit.couldNotStart => "Couldn't start",
    PayReviewSubmit.returnToPay => 'Return to pay',
  };
}

// --- Pay modals ------------------------------------------------------------

Widget buildPayAddContactGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  // Two separate widget classes, so the knob really does swap the surface;
  // only the token metrics stay the compiled lane's, which is the documented
  // approximation every mobile preview carries.
  return layout == WbLayout.mobile
      ? buildMobilePayAddContactUseCase(context)
      : buildPayAddContactUseCase(context);
}

// --- Pay status ------------------------------------------------------------

/// Desktop pay activity phases.
enum PayStatusPhase { inProgress, completed }

/// Mobile deposit-handoff phases. One axis, not two: the recovery
/// presentations ('Payment unavailable', 'Submission interrupted') are only
/// defined on top of the in-progress base, so they are options of it.
enum PayMobileStatusCase {
  submitting,
  submitted,
  statusUncertain,
  failed,
  paymentUnavailable,
  submissionInterrupted,
}

Widget buildPayStatusGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  if (layout == WbLayout.mobile) {
    final status = wbStateKnob<PayMobileStatusCase>(
      context,
      label: 'Status',
      options: PayMobileStatusCase.values,
      labelBuilder: payMobileStatusCaseLabel,
    );
    return switch (status) {
      PayMobileStatusCase.submitting => buildMobilePaySubmittingUseCase(
        context,
      ),
      PayMobileStatusCase.submitted => buildMobilePaySubmittedUseCase(context),
      PayMobileStatusCase.statusUncertain =>
        buildMobilePayStatusUncertainUseCase(context),
      PayMobileStatusCase.failed => buildMobilePayFailedUseCase(context),
      PayMobileStatusCase.paymentUnavailable =>
        buildMobilePayUnavailableUseCase(context),
      PayMobileStatusCase.submissionInterrupted =>
        buildMobilePaySubmissionInterruptedUseCase(context),
    };
  }
  final phase = wbStateKnob<PayStatusPhase>(
    context,
    label: 'Phase',
    options: PayStatusPhase.values,
    labelBuilder: payStatusPhaseLabel,
  );
  return switch (phase) {
    PayStatusPhase.inProgress => buildPayInProgressUseCase(context),
    PayStatusPhase.completed => buildPayCompletedUseCase(context),
  };
}

String payMobileStatusCaseLabel(PayMobileStatusCase status) {
  return switch (status) {
    PayMobileStatusCase.submitting => 'Submitting',
    PayMobileStatusCase.submitted => 'Submitted',
    PayMobileStatusCase.statusUncertain => 'Status uncertain',
    PayMobileStatusCase.failed => 'Failed',
    PayMobileStatusCase.paymentUnavailable => 'Payment unavailable',
    PayMobileStatusCase.submissionInterrupted => 'Submission interrupted',
  };
}

String payStatusPhaseLabel(PayStatusPhase phase) {
  return switch (phase) {
    PayStatusPhase.inProgress => 'In progress',
    PayStatusPhase.completed => 'Completed',
  };
}

// --- Donation --------------------------------------------------------------

/// Which currency the amount field is denominated in; it also swaps the
/// preset row between ZEC and USD amounts.
enum DonationComposeMode { zec, usd }

/// What the amount field holds: nothing, a tapped preset, or a typed amount
/// with the caret parked mid-string.
enum DonationComposeAmount { empty, preset, midCursor }

/// The validation line the composer shows under the amount, with the amount
/// and its unit restyled destructively.
enum DonationComposeError { none, invalidAmount, insufficientBalance }

Widget buildDonationComposeGalleryCase(BuildContext context) {
  final mode = wbStateKnob<DonationComposeMode>(
    context,
    label: 'Currency',
    options: DonationComposeMode.values,
    labelBuilder: donationComposeModeLabel,
  );
  final amount = wbStateKnob<DonationComposeAmount>(
    context,
    label: 'Amount',
    options: DonationComposeAmount.values,
    labelBuilder: donationComposeAmountLabel,
  );
  final error = wbStateKnob<DonationComposeError>(
    context,
    label: 'Error',
    options: DonationComposeError.values,
    labelBuilder: donationComposeErrorLabel,
  );
  final submitting = wbBoolKnob(context, label: 'Submitting');
  final price = wbStateKnob<DonationScreenPriceCase>(
    context,
    label: 'Price',
    options: DonationScreenPriceCase.values,
    labelBuilder: donationScreenPriceCaseLabel,
  );
  return donationComposeFixture(
    donationComposeAmountProps(mode, amount),
    errorText: donationComposeErrorText(error),
    isSubmitting: submitting,
    livePrice: price == DonationScreenPriceCase.available,
  );
}

DonationComposeAmountProps donationComposeAmountProps(
  DonationComposeMode mode,
  DonationComposeAmount amount,
) {
  return switch ((mode, amount)) {
    (DonationComposeMode.zec, DonationComposeAmount.empty) =>
      donationComposeZecEmptyAmount,
    (DonationComposeMode.zec, DonationComposeAmount.preset) =>
      donationComposeZecPresetAmount,
    (DonationComposeMode.zec, DonationComposeAmount.midCursor) =>
      donationComposeZecMidCursorAmount,
    (DonationComposeMode.usd, DonationComposeAmount.empty) =>
      donationComposeUsdEmptyAmount,
    (DonationComposeMode.usd, DonationComposeAmount.preset) =>
      donationComposeUsdPresetAmount,
    (DonationComposeMode.usd, DonationComposeAmount.midCursor) =>
      donationComposeUsdMidCursorAmount,
  };
}

/// The screen's own validation copy, not gallery text.
String? donationComposeErrorText(DonationComposeError error) {
  return switch (error) {
    DonationComposeError.none => null,
    DonationComposeError.invalidAmount => 'Invalid amount',
    DonationComposeError.insufficientBalance => 'Insufficient shielded balance',
  };
}

String donationComposeErrorLabel(DonationComposeError error) {
  return switch (error) {
    DonationComposeError.none => 'None',
    DonationComposeError.invalidAmount => 'Invalid amount',
    DonationComposeError.insufficientBalance => 'Not enough shielded ZEC',
  };
}

String donationComposeModeLabel(DonationComposeMode mode) {
  return switch (mode) {
    DonationComposeMode.zec => 'ZEC',
    DonationComposeMode.usd => 'USD',
  };
}

String donationComposeAmountLabel(DonationComposeAmount amount) {
  return switch (amount) {
    DonationComposeAmount.empty => 'Empty',
    DonationComposeAmount.preset => 'Preset',
    DonationComposeAmount.midCursor => 'Mid-cursor',
  };
}

/// Whether a live ZEC/USD price is available; without one the screen's
/// currency toggle is inert.
enum DonationScreenPriceCase { available, missing }

Widget buildDonationScreenGalleryCase(BuildContext context) {
  final price = wbStateKnob<DonationScreenPriceCase>(
    context,
    label: 'Price',
    options: DonationScreenPriceCase.values,
    labelBuilder: donationScreenPriceCaseLabel,
  );
  // Desktop-only screen, and its real sidebar overflows by 2px under mobile
  // typography.
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child:
        price == DonationScreenPriceCase.missing
            ? buildDonationScreenNoPriceUseCase(context)
            : buildDonationScreenUseCase(context),
  );
}

String donationScreenPriceCaseLabel(DonationScreenPriceCase price) {
  return switch (price) {
    DonationScreenPriceCase.available => 'Available',
    DonationScreenPriceCase.missing => 'Missing',
  };
}

/// Whether the review can be submitted; without a callback the confirm
/// button renders disabled.
enum DonationReviewConfirm { enabled, disabled }

/// Whether the amount carries its fiat sub-line.
enum DonationReviewFiat { shown, absent }

Widget buildDonationReviewGalleryCase(BuildContext context) {
  final confirm = wbStateKnob<DonationReviewConfirm>(
    context,
    label: 'Confirm',
    options: DonationReviewConfirm.values,
    labelBuilder: donationReviewConfirmLabel,
  );
  final fiat = wbStateKnob<DonationReviewFiat>(
    context,
    label: 'Fiat',
    options: DonationReviewFiat.values,
    labelBuilder: donationReviewFiatLabel,
  );
  return donationReviewFixture(
    confirmEnabled: confirm == DonationReviewConfirm.enabled,
    showFiat: fiat == DonationReviewFiat.shown,
  );
}

String donationReviewConfirmLabel(DonationReviewConfirm confirm) {
  return switch (confirm) {
    DonationReviewConfirm.enabled => 'Enabled',
    DonationReviewConfirm.disabled => 'Disabled',
  };
}

String donationReviewFiatLabel(DonationReviewFiat fiat) {
  return switch (fiat) {
    DonationReviewFiat.shown => 'Shown',
    DonationReviewFiat.absent => 'Absent',
  };
}

/// How the recipient row reads: struck through is the failed or cancelled
/// donation.
enum DonationRecipientRowState { active, struckThrough }

Widget buildDonationRecipientRowGalleryCase(BuildContext context) {
  final state = wbStateKnob<DonationRecipientRowState>(
    context,
    label: 'State',
    options: DonationRecipientRowState.values,
    labelBuilder: donationRecipientRowStateLabel,
  );
  return donationRecipientRowFixture(
    struckThrough: state == DonationRecipientRowState.struckThrough,
  );
}

String donationRecipientRowStateLabel(DonationRecipientRowState state) {
  return switch (state) {
    DonationRecipientRowState.active => 'Active',
    DonationRecipientRowState.struckThrough => 'Struck through',
  };
}

enum DonationStatusCase { inProgress, success }

Widget buildDonationStatusGalleryCase(BuildContext context) {
  final status = wbStateKnob<DonationStatusCase>(
    context,
    label: 'Status',
    options: DonationStatusCase.values,
    labelBuilder: donationStatusCaseLabel,
  );
  return switch (status) {
    DonationStatusCase.inProgress => buildDonationStatusInProgressUseCase(
      context,
    ),
    DonationStatusCase.success => buildDonationSuccessUseCase(context),
  };
}

String donationStatusCaseLabel(DonationStatusCase status) {
  return switch (status) {
    DonationStatusCase.inProgress => 'In progress',
    DonationStatusCase.success => 'Success',
  };
}
