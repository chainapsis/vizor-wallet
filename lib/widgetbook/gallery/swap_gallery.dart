// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/core/theme/app_theme.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';
import '../swap_mobile_use_cases.dart';
import '../swap_use_cases.dart';

/// The Swap gallery: one use case per surface, each knob dispatching to the
/// fixtures in `swap_use_cases.dart` so figma_compare and the tests keep every
/// `build*UseCase` they bind to.
///
/// A surface both form factors have is a single 'Playground' whose `Layout`
/// knob swaps the widget class; where the lanes' state axes are disjoint (the
/// swap page, review, status and Keystone signing), each lane registers only
/// its own knobs.
final List<WidgetbookNode> swapGalleryNodes = [
  WidgetbookComponent(
    name: 'Swap page',
    useCases: [
      WidgetbookUseCase(name: 'Screen', builder: buildSwapScreenGalleryCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Swap review',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildSwapReviewGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Mobile content',
        builder: buildMobileSwapReviewContentGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Mobile actions',
        builder: buildMobileSwapReviewActionsGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Mobile header row',
        builder: buildMobileSwapReviewHeaderGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Swap deposit',
    useCases: [
      WidgetbookUseCase(
        name: 'Deposit tokens',
        builder: buildSwapDepositTokensGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Hardware ZEC deposit',
        builder: buildSwapHardwareZecDepositGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Deposit timeout',
        builder: buildSwapDepositTimeoutGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Swap status',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildSwapStatusGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Swap activity detail',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildSwapActivityDetailGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Page panel',
        builder: buildSwapActivityPagePanelGalleryCase,
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Progress route',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSwapProgressRouteGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Review info row',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSwapReviewInfoGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Asset icon',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSwapAssetIconGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'NEAR Intents attribution',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSwapAttributionGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Modal controls',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSwapModalControlsGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Mobile swap composer',
        useCases: [
          WidgetbookUseCase(
            name: 'Ticket',
            builder: buildMobileSwapTicketGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Modals',
    children: [
      WidgetbookComponent(
        name: 'Swap modals',
        useCases: [
          WidgetbookUseCase(
            name: 'Address editor',
            builder: buildSwapAddressEditorGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Slippage',
            builder: buildSwapSlippageGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Asset selector',
            builder: buildSwapAssetSelectorGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        // One surface: the desktop overlay and the mobile sign screen are separate
        // widget classes over the same Keystone handoff.
        name: 'Keystone signing',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSwapKeystoneSigningGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Swap page -------------------------------------------------------------

/// Pane height of the real swap screen: the Figma design height keeps the
/// title and footer pinned, anything shorter packs the column and scrolls.
enum SwapScreenPane { designHeight, packed }

Widget buildSwapPageGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  // Disjoint axes: the mobile screen is a CTA ladder with a number pad, the
  // desktop one a composer frame with hosted modals and pane heights.
  if (layout == WbLayout.mobile) {
    final cta = wbStateKnob<SwapMobileCta>(
      context,
      label: 'CTA',
      options: SwapMobileCta.values,
      labelBuilder: swapMobileCtaLabel,
    );
    final quoteError = wbStateKnob<SwapMobileQuoteError>(
      context,
      label: 'Quote error',
      options: SwapMobileQuoteError.values,
      labelBuilder: swapMobileQuoteErrorLabel,
    );
    final keyboardOpen = wbBoolKnob(context, label: 'Number pad open');
    return WbFrame(
      layout: layout,
      child: swapMobileScreenFixture(
        cta: cta,
        quoteError: quoteError,
        keyboardOpen: keyboardOpen,
      ),
    );
  }
  final frame = wbStateKnob<SwapComposerFrame>(
    context,
    label: 'Frame',
    options: SwapComposerFrame.values,
    labelBuilder: swapComposerFrameLabel,
  );
  final fixture = wbStateKnob<SwapComposerFixture>(
    context,
    label: 'State',
    options: SwapComposerFixture.values,
    labelBuilder: swapComposerFixtureLabel,
  );
  if (frame == SwapComposerFrame.screen) {
    // These axes belong to the real screen: the mock frames host no modal
    // surface, pane constraints or privacy mask.
    final overlay = wbStateKnob<SwapScreenOverlay>(
      context,
      label: 'Modal',
      options: SwapScreenOverlay.values,
      labelBuilder: swapScreenOverlayLabel,
    );
    final pane = wbStateKnob<SwapScreenPane>(
      context,
      label: 'Pane',
      options: SwapScreenPane.values,
      labelBuilder: swapScreenPaneLabel,
    );
    final hideAmounts = wbBoolKnob(context, label: 'Hide amounts');
    return _SwapStaticScreenPreview(
      child: swapScreenFixture(
        fixture: fixture,
        overlay: overlay,
        packedPane: pane == SwapScreenPane.packed,
        hideAmounts: hideAmounts,
      ),
    );
  }
  return swapComposerFixture(frame: frame, fixture: fixture);
}

/// The primary Swap screen uses the same isolated flow implementation as the
/// feature journey.  The legacy snapshot dispatcher remains available to
/// fixture tests, but is no longer exposed as a parallel gallery entry.
Widget buildSwapScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final scenario = wbStateKnob<SwapScreenSimulationScenario>(
    context,
    label: 'Scenario',
    options: SwapScreenSimulationScenario.values,
    labelBuilder: swapScreenSimulationScenarioLabel,
  );
  final fixture = wbStateKnob<SwapComposerFixture>(
    context,
    label: 'State',
    options: SwapComposerFixture.values,
    labelBuilder: swapComposerFixtureLabel,
  );
  final hideAmounts = wbBoolKnob(context, label: 'Hide amounts');
  return swapInteractiveScreenFixture(
    mobile: layout == WbLayout.mobile,
    fixture: fixture,
    hideAmounts: hideAmounts,
    scenario: scenario,
  );
}

class _SwapStaticScreenPreview extends StatelessWidget {
  const _SwapStaticScreenPreview({required this.child});

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
                  'Static preview · modals are driven by knobs',
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

String swapComposerFrameLabel(SwapComposerFrame frame) {
  return switch (frame) {
    SwapComposerFrame.page => 'Swap page',
    SwapComposerFrame.widget => 'Swap widget',
    SwapComposerFrame.screen => 'Swap screen',
  };
}

String swapScreenOverlayLabel(SwapScreenOverlay overlay) {
  return switch (overlay) {
    SwapScreenOverlay.none => 'None',
    SwapScreenOverlay.assetSelector => 'Asset selector',
    SwapScreenOverlay.addressEditor => 'Address editor',
    SwapScreenOverlay.contactPicker => 'Contact picker',
    SwapScreenOverlay.slippage => 'Slippage',
  };
}

String swapScreenPaneLabel(SwapScreenPane pane) {
  return switch (pane) {
    SwapScreenPane.designHeight => 'Design height',
    SwapScreenPane.packed => 'Packed',
  };
}

String swapComposerFixtureLabel(SwapComposerFixture fixture) {
  return switch (fixture) {
    SwapComposerFixture.payAmountActive => 'Pay amount active',
    SwapComposerFixture.receiveAmountActive => 'Receive amount active',
    SwapComposerFixture.amountEntered => 'Amount entered',
    SwapComposerFixture.directionSwitched => 'Direction switched',
    SwapComposerFixture.fiatValueInput => 'Fiat value input',
    SwapComposerFixture.unsupportedFiatPrice => 'Unsupported fiat price',
    SwapComposerFixture.torBlocked => 'Tor connection blocked',
    SwapComposerFixture.savedContactAddress => 'Saved contact address',
    SwapComposerFixture.overAvailableBalance => 'Over available balance',
    SwapComposerFixture.maxAmountFailed => "Couldn't read max",
    SwapComposerFixture.quoteLoading => 'Getting quote',
    SwapComposerFixture.rateUnavailable => 'Rate unavailable',
    SwapComposerFixture.assetPillOpen => 'Asset pill open',
    SwapComposerFixture.slippagePillOpen => 'Slippage pill open',
    SwapComposerFixture.wrongDestinationFormat => 'Wrong address format',
  };
}

// --- Swap modals -----------------------------------------------------------

Widget buildSwapAddressEditorGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final direction = wbStateKnob<SwapAddressModalDirection>(
    context,
    label: 'Direction',
    options: SwapAddressModalDirection.values,
    labelBuilder: swapAddressModalDirectionLabel,
  );
  final format = wbStateKnob<SwapAddressModalFormat>(
    context,
    label: 'Address',
    options: SwapAddressModalFormat.values,
    labelBuilder: swapAddressModalFormatLabel,
  );
  final contact = wbStateKnob<SwapAddressModalContact>(
    context,
    label: 'Contact match',
    options: SwapAddressModalContact.values,
    labelBuilder: swapAddressModalContactLabel,
  );
  // Desktop keeps the toggle in state with no prop, so this reaches the
  // mobile modal only.
  final remember = wbBoolKnob(context, label: 'Remember address');
  return swapAddressEditFixture(
    mobile: layout == WbLayout.mobile,
    direction: direction,
    format: format,
    contact: contact,
    rememberAddress: remember,
  );
}

String swapAddressModalDirectionLabel(SwapAddressModalDirection direction) {
  return switch (direction) {
    SwapAddressModalDirection.refund => 'Refund',
    SwapAddressModalDirection.recipient => 'Recipient',
  };
}

String swapAddressModalFormatLabel(SwapAddressModalFormat format) {
  return switch (format) {
    SwapAddressModalFormat.empty => 'Empty',
    SwapAddressModalFormat.valid => 'Valid',
    SwapAddressModalFormat.unusual => 'Unusual, still submittable',
    SwapAddressModalFormat.invalid => 'Wrong format',
  };
}

String swapAddressModalContactLabel(SwapAddressModalContact contact) {
  return switch (contact) {
    SwapAddressModalContact.none => 'None',
    SwapAddressModalContact.matched => 'Saved contact',
  };
}

/// Which flow the slippage editor was opened from; Payment adds the
/// quote-movement explainer above the control.
enum SwapSlippageMode { swap, payment }

Widget buildSwapSlippageGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final mode = wbStateKnob<SwapSlippageMode>(
    context,
    label: 'Mode',
    options: SwapSlippageMode.values,
    labelBuilder: swapSlippageModeLabel,
  );
  final value = wbStateKnob<SwapSlippageValue>(
    context,
    label: 'Value',
    options: SwapSlippageValue.values,
    labelBuilder: swapSlippageValueLabel,
  );
  return swapSlippageFixture(
    mobile: layout == WbLayout.mobile,
    paymentMode: mode == SwapSlippageMode.payment,
    value: value,
  );
}

String swapSlippageModeLabel(SwapSlippageMode mode) {
  return switch (mode) {
    SwapSlippageMode.swap => 'Swap',
    SwapSlippageMode.payment => 'Payment',
  };
}

String swapSlippageValueLabel(SwapSlippageValue value) {
  return switch (value) {
    SwapSlippageValue.minimum => 'Minimum 0.1%',
    SwapSlippageValue.presetHalf => 'Preset 0.5%',
    SwapSlippageValue.presetOne => 'Preset 1%',
    SwapSlippageValue.presetTwo => 'Preset 2%',
    SwapSlippageValue.custom => 'Custom 1.25%',
    SwapSlippageValue.maximum => 'Maximum 5%',
    SwapSlippageValue.outOfRange => 'Out of range 15%',
  };
}

Widget buildSwapAssetSelectorGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final query = wbStateKnob<SwapAssetModalQuery>(
    context,
    label: 'Query',
    options: SwapAssetModalQuery.values,
    labelBuilder: swapAssetModalQueryLabel,
  );
  final selection = wbStateKnob<SwapAssetModalSelection>(
    context,
    label: 'Selection',
    options: SwapAssetModalSelection.values,
    labelBuilder: swapAssetModalSelectionLabel,
  );
  final length = wbStateKnob<SwapAssetModalLength>(
    context,
    label: 'List length',
    options: SwapAssetModalLength.values,
    labelBuilder: swapAssetModalLengthLabel,
  );
  return swapAssetSelectorFixture(
    mobile: layout == WbLayout.mobile,
    query: query,
    selection: selection,
    length: length,
  );
}

String swapAssetModalQueryLabel(SwapAssetModalQuery query) {
  return switch (query) {
    SwapAssetModalQuery.none => 'No query',
    SwapAssetModalQuery.matching => "Matching 'us'",
    SwapAssetModalQuery.noMatch => 'No matches',
  };
}

String swapAssetModalSelectionLabel(SwapAssetModalSelection selection) {
  return switch (selection) {
    SwapAssetModalSelection.none => 'None',
    SwapAssetModalSelection.usdc => 'USDC',
  };
}

String swapAssetModalLengthLabel(SwapAssetModalLength length) {
  return switch (length) {
    SwapAssetModalLength.short => 'Short, 3 assets',
    SwapAssetModalLength.long => 'Long, 9 assets',
  };
}

// --- Swap review -----------------------------------------------------------

enum SwapReviewQuote {
  usdcToZec,
  zecToUsdc,
  longPayAmount,
  longReceiveAmount,
  longBothAmounts,
}

Widget buildSwapReviewGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  // Disjoint axes: the mobile screen carries the swap/payment mode and its own
  // blocked line, the desktop page the pinned long-amount quotes.
  if (layout == WbLayout.mobile) {
    final mode = wbStateKnob<SwapMobileReviewMode>(
      context,
      label: 'Mode',
      options: SwapMobileReviewMode.values,
      labelBuilder: swapMobileReviewModeLabel,
    );
    final mobileQuote = wbStateKnob<SwapMobileReviewQuoteCase>(
      context,
      label: 'Quote',
      options: SwapMobileReviewQuoteCase.values,
      labelBuilder: swapMobileReviewQuoteCaseLabel,
    );
    final blocked = wbStateKnob<SwapMobileReviewBlocked>(
      context,
      label: 'Blocked',
      options: SwapMobileReviewBlocked.values,
      labelBuilder: swapMobileReviewBlockedLabel,
    );
    return WbFrame(
      layout: layout,
      child: swapMobileReviewScreenFixture(
        mode: mode,
        quote: mobileQuote,
        blocked: blocked,
      ),
    );
  }
  final quote = wbStateKnob<SwapReviewQuote>(
    context,
    label: 'Quote',
    options: SwapReviewQuote.values,
    labelBuilder: swapReviewQuoteLabel,
  );
  final state = wbStateKnob<SwapReviewScreenCase>(
    context,
    label: 'State',
    options: SwapReviewScreenCase.values,
    labelBuilder: swapReviewScreenCaseLabel,
  );
  // Anything but the plain review is a state only the real screen carries
  // (its own toolbar, notices and action labels), so it outranks `Quote`,
  // whose long-amount fixtures exist for the pinned Figma quote alone.
  if (state != SwapReviewScreenCase.review) {
    return swapReviewScreenFixture(state: state);
  }
  return switch (quote) {
    SwapReviewQuote.usdcToZec => buildSwapReviewDefaultUseCase(context),
    SwapReviewQuote.zecToUsdc => buildSwapReviewZecToExternalUseCase(context),
    SwapReviewQuote.longPayAmount => buildSwapReviewLargeLeftAmountUseCase(
      context,
    ),
    SwapReviewQuote.longReceiveAmount => buildSwapReviewLargeRightAmountUseCase(
      context,
    ),
    SwapReviewQuote.longBothAmounts => buildSwapReviewLargeAmountsUseCase(
      context,
    ),
  };
}

String swapReviewScreenCaseLabel(SwapReviewScreenCase state) {
  return switch (state) {
    SwapReviewScreenCase.review => 'Review swap',
    SwapReviewScreenCase.payment => 'Confirm payment',
    SwapReviewScreenCase.expired => 'Quote expired',
    SwapReviewScreenCase.amountDrift => 'Amount moved',
    SwapReviewScreenCase.startError => "Couldn't start",
    SwapReviewScreenCase.notEnoughZec => 'Not enough ZEC',
    SwapReviewScreenCase.submitting => 'Submitting',
  };
}

String swapReviewQuoteLabel(SwapReviewQuote quote) {
  return switch (quote) {
    SwapReviewQuote.usdcToZec => 'USDC to ZEC',
    SwapReviewQuote.zecToUsdc => 'ZEC to USDC',
    SwapReviewQuote.longPayAmount => 'Long pay amount',
    SwapReviewQuote.longReceiveAmount => 'Long receive amount',
    SwapReviewQuote.longBothAmounts => 'Long amounts both sides',
  };
}

// --- Swap deposit ----------------------------------------------------------

enum SwapDepositTokensCase {
  staticExpiry,
  countdown,
  memoAndQr,
  checking,
  checkFailed,
  elapsed,
}

Widget buildSwapDepositTokensGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final deposit = wbStateKnob<SwapDepositTokensCase>(
    context,
    label: 'Deposit',
    options: SwapDepositTokensCase.values,
    labelBuilder: swapDepositTokensCaseLabel,
  );
  final wait = switch (deposit) {
    SwapDepositTokensCase.checking => SwapDepositWaitCase.checking,
    SwapDepositTokensCase.checkFailed => SwapDepositWaitCase.checkFailed,
    SwapDepositTokensCase.elapsed => SwapDepositWaitCase.elapsed,
    _ => null,
  };
  // The mobile frame is a prop on the same content widget, so the three
  // pinned Figma fixtures route through the parameterized one there — with
  // their own expiry and memo, not collapsed onto the checking state.
  if (wait != null || layout == WbLayout.mobile) {
    return swapDepositTokensFixture(
      state: wait,
      expiry:
          deposit == SwapDepositTokensCase.staticExpiry
              ? SwapDepositExpiryCase.staticLabel
              : SwapDepositExpiryCase.countdown,
      memo:
          deposit == SwapDepositTokensCase.memoAndQr
              ? 'memo with & routing=value?'
              : null,
      mobile: layout == WbLayout.mobile,
    );
  }
  return switch (deposit) {
    SwapDepositTokensCase.staticExpiry => buildSwapDepositDurationUseCase(
      context,
    ),
    SwapDepositTokensCase.countdown => buildSwapDepositCountdownUseCase(
      context,
    ),
    SwapDepositTokensCase.memoAndQr => buildSwapDepositMemoQrUseCase(context),
    _ => const SizedBox.shrink(),
  };
}

Widget buildSwapHardwareZecDepositGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final memo = wbBoolKnob(context, label: 'Memo');
  // The clock is its own axis: the pinned Figma frame prints a static
  // duration, so Layout and Memo must not swap it for a countdown.
  final countdown = wbBoolKnob(context, label: 'Countdown');
  if (layout == WbLayout.desktop && !memo && !countdown) {
    return buildSwapDepositHardwareZecUseCase(context);
  }
  return swapHardwareZecDepositFixture(
    mobile: layout == WbLayout.mobile,
    memo: memo,
    expiry:
        countdown
            ? SwapDepositExpiryCase.countdown
            : SwapDepositExpiryCase.staticLabel,
  );
}

Widget buildSwapDepositTimeoutGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  if (layout == WbLayout.desktop) {
    return buildSwapDepositTimeoutUseCase(context);
  }
  return WbFrame(layout: layout, child: swapMobileTimeoutFixture());
}

String swapDepositTokensCaseLabel(SwapDepositTokensCase deposit) {
  return switch (deposit) {
    SwapDepositTokensCase.staticExpiry => 'Static expiry',
    SwapDepositTokensCase.countdown => 'Countdown',
    SwapDepositTokensCase.memoAndQr => 'Memo and QR',
    SwapDepositTokensCase.checking => 'Checking deposit',
    SwapDepositTokensCase.checkFailed => "Couldn't check",
    SwapDepositTokensCase.elapsed => 'Countdown elapsed',
  };
}

// --- Swap status -----------------------------------------------------------

enum SwapStatusCase {
  inProgress,
  nextStep,
  detailsTab,
  completed,
  capturedFiat,
  failed,
  refunded,
  incompleteDeposit,
  paymentInProgress,
  paymentCompleted,
}

Widget buildSwapStatusGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  // The lanes were built from different Figma frames: the desktop page carries
  // the amount-length fixtures, the mobile route its tabs and recipient rows.
  if (layout == WbLayout.mobile) {
    final mode = wbStateKnob<SwapMobileStatusMode>(
      context,
      label: 'Mode',
      options: SwapMobileStatusMode.values,
      labelBuilder: swapMobileStatusModeLabel,
    );
    final mobileStatus = wbStateKnob<SwapMobileStatusCase>(
      context,
      label: 'Status',
      options: SwapMobileStatusCase.values,
      labelBuilder: swapMobileStatusCaseLabel,
    );
    final tab = wbStateKnob<SwapMobileStatusTab>(
      context,
      label: 'Tab',
      options: SwapMobileStatusTab.values,
      labelBuilder: swapMobileStatusTabLabel,
    );
    final recipient = wbStateKnob<SwapMobileStatusRecipient>(
      context,
      label: 'Recipient',
      options: SwapMobileStatusRecipient.values,
      labelBuilder: swapMobileStatusRecipientLabel,
    );
    final depositTx = wbStateKnob<SwapMobileStatusDepositTx>(
      context,
      label: 'Deposit tx',
      options: SwapMobileStatusDepositTx.values,
      labelBuilder: swapMobileStatusDepositTxLabel,
    );
    return WbFrame(
      layout: layout,
      child: swapMobileStatusFixture(
        mode: mode,
        status: mobileStatus,
        tab: tab,
        recipient: recipient,
        depositTx: depositTx,
      ),
    );
  }
  final status = wbStateKnob<SwapStatusCase>(
    context,
    label: 'Status',
    options: SwapStatusCase.values,
    labelBuilder: swapStatusCaseLabel,
  );
  final amounts = wbStateKnob<SwapStatusAmounts>(
    context,
    label: 'Amount size',
    options: SwapStatusAmounts.values,
    labelBuilder: swapStatusAmountsLabel,
  );
  // The long-amount fixtures only exist for the in-progress status, so a
  // non-standard size picks the fixture and `Status` has nothing left to say.
  if (amounts != SwapStatusAmounts.standard) {
    return switch (amounts) {
      SwapStatusAmounts.standard => buildSwapStatusProgressUseCase(context),
      SwapStatusAmounts.longPay => buildSwapStatusLargeLeftAmountUseCase(
        context,
      ),
      SwapStatusAmounts.longReceive => buildSwapStatusLargeRightAmountUseCase(
        context,
      ),
      SwapStatusAmounts.longBoth => buildSwapStatusLargeAmountsUseCase(context),
    };
  }
  return switch (status) {
    SwapStatusCase.inProgress => buildSwapStatusProgressUseCase(context),
    SwapStatusCase.nextStep => buildSwapStatusProgressNextStepUseCase(context),
    // `buildSwapStatusDetailsExpandedUseCase` renders the same preview today;
    // give it its own option once the expanded state actually differs.
    SwapStatusCase.detailsTab => buildSwapStatusDetailsCollapsedUseCase(
      context,
    ),
    SwapStatusCase.completed => buildSwapStatusCompletedUseCase(context),
    SwapStatusCase.capturedFiat => buildSwapStatusCapturedFiatUseCase(context),
    SwapStatusCase.failed => buildSwapStatusFailedUseCase(context),
    SwapStatusCase.refunded => buildSwapStatusRefundedUseCase(context),
    SwapStatusCase.incompleteDeposit => buildSwapStatusIncompleteDepositUseCase(
      context,
    ),
    SwapStatusCase.paymentInProgress => buildSwapStatusPaymentProgressUseCase(
      context,
    ),
    SwapStatusCase.paymentCompleted => buildSwapStatusPaymentCompletedUseCase(
      context,
    ),
  };
}

String swapStatusCaseLabel(SwapStatusCase status) {
  return switch (status) {
    SwapStatusCase.inProgress => 'In progress',
    SwapStatusCase.nextStep => 'In progress, next step',
    SwapStatusCase.detailsTab => 'Details tab',
    SwapStatusCase.completed => 'Completed',
    SwapStatusCase.capturedFiat => 'Completed with captured fiat',
    SwapStatusCase.failed => 'Failed',
    SwapStatusCase.refunded => 'Refunded',
    SwapStatusCase.incompleteDeposit => 'Incomplete deposit',
    SwapStatusCase.paymentInProgress => 'Payment in progress',
    SwapStatusCase.paymentCompleted => 'Payment complete',
  };
}

/// Amount-length axis of the status page; 'Standard' defers to `Status`.
enum SwapStatusAmounts { standard, longPay, longReceive, longBoth }

String swapStatusAmountsLabel(SwapStatusAmounts amounts) {
  return switch (amounts) {
    SwapStatusAmounts.standard => 'Standard',
    SwapStatusAmounts.longPay => 'Long pay',
    SwapStatusAmounts.longReceive => 'Long receive',
    SwapStatusAmounts.longBoth => 'Long both',
  };
}

// --- Swap page, mobile labels ----------------------------------------------

String swapMobileCtaLabel(SwapMobileCta cta) {
  return switch (cta) {
    SwapMobileCta.addRecipientAddress => 'Add recipient address',
    SwapMobileCta.addRefundAddress => 'Add refund address',
    SwapMobileCta.addressFormatError => 'Address format error',
    SwapMobileCta.notEnoughZec => 'Not enough ZEC',
    SwapMobileCta.gettingQuote => 'Getting quote',
    SwapMobileCta.continueToReview => 'Continue to review',
  };
}

String swapMobileQuoteErrorLabel(SwapMobileQuoteError error) {
  return switch (error) {
    SwapMobileQuoteError.none => 'None',
    SwapMobileQuoteError.amountPrecision => 'Amount precision',
    SwapMobileQuoteError.unsupportedAsset => 'Unsupported asset',
    SwapMobileQuoteError.noQuoteAvailable => 'No quote available',
  };
}

// --- Mobile swap composer --------------------------------------------------

Widget buildMobileSwapTicketGalleryCase(BuildContext context) {
  final direction = wbStateKnob<SwapMobileTicketDirection>(
    context,
    label: 'Direction',
    options: SwapMobileTicketDirection.values,
    labelBuilder: swapMobileTicketDirectionLabel,
  );
  final side = wbStateKnob<SwapMobileTicketSide>(
    context,
    label: 'Active side',
    options: SwapMobileTicketSide.values,
    labelBuilder: swapMobileTicketSideLabel,
  );
  final amountMode = wbStateKnob<SwapMobileTicketAmountMode>(
    context,
    label: 'Amount mode',
    options: SwapMobileTicketAmountMode.values,
    labelBuilder: swapMobileTicketAmountModeLabel,
  );
  final max = wbStateKnob<SwapMobileTicketMax>(
    context,
    label: 'Max trigger',
    options: SwapMobileTicketMax.values,
    labelBuilder: swapMobileTicketMaxLabel,
  );
  final destination = wbStateKnob<SwapMobileTicketDestination>(
    context,
    label: 'Destination',
    options: SwapMobileTicketDestination.values,
    labelBuilder: swapMobileTicketDestinationLabel,
  );
  return WbFrame(
    layout: WbLayout.mobile,
    child: swapMobileComposerTicketFixture(
      direction: direction,
      side: side,
      amountMode: amountMode,
      max: max,
      destination: destination,
    ),
  );
}

String swapMobileTicketDirectionLabel(SwapMobileTicketDirection direction) {
  return switch (direction) {
    SwapMobileTicketDirection.zecToUsdc => 'ZEC to USDC',
    SwapMobileTicketDirection.usdcToZec => 'USDC to ZEC',
  };
}

String swapMobileTicketSideLabel(SwapMobileTicketSide side) {
  return switch (side) {
    SwapMobileTicketSide.pay => 'Pay',
    SwapMobileTicketSide.receive => 'Receive',
  };
}

String swapMobileTicketAmountModeLabel(SwapMobileTicketAmountMode mode) {
  return switch (mode) {
    SwapMobileTicketAmountMode.token => 'Token',
    SwapMobileTicketAmountMode.fiat => 'Fiat',
  };
}

String swapMobileTicketMaxLabel(SwapMobileTicketMax max) {
  return switch (max) {
    SwapMobileTicketMax.balance => 'Balance',
    SwapMobileTicketMax.error => 'Error',
  };
}

String swapMobileTicketDestinationLabel(
  SwapMobileTicketDestination destination,
) {
  return switch (destination) {
    SwapMobileTicketDestination.empty => 'Empty',
    SwapMobileTicketDestination.address => 'Address',
    SwapMobileTicketDestination.contact => 'Contact',
  };
}

// --- Swap status, mobile labels --------------------------------------------

String swapMobileStatusModeLabel(SwapMobileStatusMode mode) {
  return switch (mode) {
    SwapMobileStatusMode.swap => 'Swap',
    SwapMobileStatusMode.payment => 'Payment',
  };
}

String swapMobileStatusCaseLabel(SwapMobileStatusCase status) {
  return switch (status) {
    SwapMobileStatusCase.inProgress => 'In progress',
    SwapMobileStatusCase.incompleteDeposit => 'Incomplete deposit',
    SwapMobileStatusCase.completed => 'Completed',
    SwapMobileStatusCase.failed => 'Failed',
  };
}

String swapMobileStatusTabLabel(SwapMobileStatusTab tab) {
  return switch (tab) {
    SwapMobileStatusTab.progress => 'Progress',
    SwapMobileStatusTab.details => 'Transaction details',
  };
}

String swapMobileStatusRecipientLabel(SwapMobileStatusRecipient recipient) {
  return switch (recipient) {
    SwapMobileStatusRecipient.contact => 'Saved contact',
    SwapMobileStatusRecipient.address => 'Unknown address',
  };
}

String swapMobileStatusDepositTxLabel(SwapMobileStatusDepositTx depositTx) {
  return switch (depositTx) {
    SwapMobileStatusDepositTx.pending => 'Not sent yet',
    SwapMobileStatusDepositTx.recorded => 'Recorded',
  };
}

// --- Keystone signing, mobile labels ---------------------------------------

String swapMobileKeystonePhaseLabel(SwapMobileKeystonePhase phase) {
  return switch (phase) {
    SwapMobileKeystonePhase.preparing => 'Preparing',
    SwapMobileKeystonePhase.qrCode => 'QR code',
  };
}

String swapMobileKeystoneErrorLabel(SwapMobileKeystoneError error) {
  return switch (error) {
    SwapMobileKeystoneError.none => 'None',
    SwapMobileKeystoneError.texUnsupported => 'TEX not supported',
    SwapMobileKeystoneError.saplingParams => 'Proving parameters',
    SwapMobileKeystoneError.proposalExpired => 'Transaction expired',
    SwapMobileKeystoneError.signatureNotApplied => 'Signature not applied',
    SwapMobileKeystoneError.broadcastFailed => 'Broadcast failed',
    SwapMobileKeystoneError.generic => 'Unknown fault',
  };
}

// --- Mobile swap review ----------------------------------------------------

String swapMobileReviewModeLabel(SwapMobileReviewMode mode) {
  return switch (mode) {
    SwapMobileReviewMode.swap => 'Swap',
    SwapMobileReviewMode.payment => 'Payment',
  };
}

String swapMobileReviewQuoteCaseLabel(SwapMobileReviewQuoteCase quote) {
  return switch (quote) {
    SwapMobileReviewQuoteCase.live => 'Live',
    SwapMobileReviewQuoteCase.expired => 'Expired',
  };
}

String swapMobileReviewBlockedLabel(SwapMobileReviewBlocked blocked) {
  return switch (blocked) {
    SwapMobileReviewBlocked.none => 'None',
    SwapMobileReviewBlocked.notEnoughZec => 'Not enough ZEC',
  };
}

Widget buildMobileSwapReviewContentGalleryCase(BuildContext context) {
  final direction = wbStateKnob<SwapMobileReviewDirection>(
    context,
    label: 'Direction',
    options: SwapMobileReviewDirection.values,
    labelBuilder: swapMobileReviewDirectionLabel,
  );
  final notice = wbStateKnob<SwapMobileReviewNotice>(
    context,
    label: 'Notice',
    options: SwapMobileReviewNotice.values,
    labelBuilder: swapMobileReviewNoticeLabel,
  );
  final addressLabel = wbStateKnob<SwapMobileReviewAddressLabel>(
    context,
    label: 'Address label',
    options: SwapMobileReviewAddressLabel.values,
    labelBuilder: swapMobileReviewAddressLabelLabel,
  );
  return WbFrame(
    layout: WbLayout.mobile,
    child: swapMobileReviewContentFixture(
      direction: direction,
      notice: notice,
      addressLabel: addressLabel,
    ),
  );
}

String swapMobileReviewDirectionLabel(SwapMobileReviewDirection direction) {
  return switch (direction) {
    SwapMobileReviewDirection.zecToUsdc => 'ZEC to USDC',
    SwapMobileReviewDirection.usdcToZec => 'USDC to ZEC',
  };
}

String swapMobileReviewNoticeLabel(SwapMobileReviewNotice notice) {
  return switch (notice) {
    SwapMobileReviewNotice.none => 'None',
    SwapMobileReviewNotice.amountDrift => 'Amount drift',
    SwapMobileReviewNotice.expired => 'Expired',
    SwapMobileReviewNotice.startError => 'Start error',
    SwapMobileReviewNotice.notEnoughZec => 'Not enough ZEC',
    SwapMobileReviewNotice.noLongerActive => 'No longer active',
  };
}

String swapMobileReviewAddressLabelLabel(
  SwapMobileReviewAddressLabel addressLabel,
) {
  return switch (addressLabel) {
    SwapMobileReviewAddressLabel.plain => 'Plain',
    SwapMobileReviewAddressLabel.contact => 'Contact',
  };
}

Widget buildMobileSwapReviewActionsGalleryCase(BuildContext context) {
  final action = wbStateKnob<SwapMobileReviewAction>(
    context,
    label: 'Action',
    options: SwapMobileReviewAction.values,
    labelBuilder: swapMobileReviewActionLabel,
  );
  final direction = wbStateKnob<SwapMobileActionsDirection>(
    context,
    label: 'Direction',
    options: SwapMobileActionsDirection.values,
    labelBuilder: swapMobileActionsDirectionLabel,
  );
  return WbFrame(
    layout: WbLayout.mobile,
    child: swapMobileReviewActionsFixture(action: action, direction: direction),
  );
}

String swapMobileReviewActionLabel(SwapMobileReviewAction action) {
  return switch (action) {
    SwapMobileReviewAction.confirm => 'Confirm & swap',
    SwapMobileReviewAction.reviewAgain => 'Review again',
    SwapMobileReviewAction.notEnoughZec => 'Not enough ZEC',
    SwapMobileReviewAction.starting => 'Starting',
    SwapMobileReviewAction.noLongerActive => 'Return to swap',
  };
}

String swapMobileActionsDirectionLabel(SwapMobileActionsDirection direction) {
  return switch (direction) {
    SwapMobileActionsDirection.sendsZec => 'Sends ZEC',
    SwapMobileActionsDirection.receivesZec => 'Receives ZEC',
  };
}

Widget buildMobileSwapReviewHeaderGalleryCase(BuildContext context) {
  final bottomLine = wbStateKnob<SwapMobileHeaderBottomLine>(
    context,
    label: 'Bottom line',
    options: SwapMobileHeaderBottomLine.values,
    labelBuilder: swapMobileHeaderBottomLineLabel,
  );
  final asset = wbStateKnob<SwapMobileHeaderAsset>(
    context,
    label: 'Asset',
    options: SwapMobileHeaderAsset.values,
    labelBuilder: swapMobileHeaderAssetLabel,
  );
  final fullAddress = wbBoolKnob(context, label: 'Full address action');
  return WbFrame(
    layout: WbLayout.mobile,
    child: swapMobileReviewHeaderFixture(
      bottomLine: bottomLine,
      fullAddressAction: fullAddress,
      asset: asset,
    ),
  );
}

String swapMobileHeaderBottomLineLabel(SwapMobileHeaderBottomLine bottomLine) {
  return switch (bottomLine) {
    SwapMobileHeaderBottomLine.fiat => 'Fiat',
    SwapMobileHeaderBottomLine.toAddress => 'To address',
    SwapMobileHeaderBottomLine.none => 'None',
  };
}

String swapMobileHeaderAssetLabel(SwapMobileHeaderAsset asset) {
  return switch (asset) {
    SwapMobileHeaderAsset.zec => 'ZEC',
    SwapMobileHeaderAsset.usdc => 'USDC on Ethereum',
  };
}

// --- Keystone signing ------------------------------------------------------

Widget buildSwapKeystoneSigningGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  // The two lanes name their phases differently ('Ready to sign' against the
  // mobile 'QR code'), so each registers its own axes instead of sharing them.
  if (layout == WbLayout.mobile) {
    final phase = wbStateKnob<SwapMobileKeystonePhase>(
      context,
      label: 'Phase',
      options: SwapMobileKeystonePhase.values,
      labelBuilder: swapMobileKeystonePhaseLabel,
    );
    final error = wbStateKnob<SwapMobileKeystoneError>(
      context,
      label: 'Error',
      options: SwapMobileKeystoneError.values,
      labelBuilder: swapMobileKeystoneErrorLabel,
    );
    return WbFrame(
      layout: layout,
      // A failure lands on the same panel from either phase, so the error axis
      // takes over once it leaves 'None'.
      child: swapMobileKeystoneSignFixture(phase: phase, error: error),
    );
  }
  final phase = wbStateKnob<SwapKeystoneOverlayPhase>(
    context,
    label: 'Phase',
    options: SwapKeystoneOverlayPhase.values,
    labelBuilder: swapKeystoneOverlayPhaseLabel,
  );
  final error = wbStateKnob<SwapKeystoneOverlayError>(
    context,
    label: 'Error',
    options: SwapKeystoneOverlayError.values,
    labelBuilder: swapKeystoneOverlayErrorLabel,
  );
  return WbFrame(
    layout: layout,
    // A failure lands on the same panel from either phase, so the error axis
    // takes over once it leaves 'None'.
    child: swapKeystoneOverlayFixture(phase: phase, error: error),
  );
}

String swapKeystoneOverlayPhaseLabel(SwapKeystoneOverlayPhase phase) {
  return switch (phase) {
    SwapKeystoneOverlayPhase.preparing => 'Preparing',
    SwapKeystoneOverlayPhase.ready => 'Ready to sign',
  };
}

String swapKeystoneOverlayErrorLabel(SwapKeystoneOverlayError error) {
  return switch (error) {
    SwapKeystoneOverlayError.none => 'None',
    SwapKeystoneOverlayError.texUnsupported => 'TEX not supported',
    SwapKeystoneOverlayError.provingParameters => 'Proving parameters',
    SwapKeystoneOverlayError.proposalExpired => 'Transaction expired',
    SwapKeystoneOverlayError.signatureNotApplied => 'Signature not applied',
    SwapKeystoneOverlayError.broadcastFailed => 'Broadcast failed',
    SwapKeystoneOverlayError.generic => 'Unknown fault',
  };
}

// --- Swap activity detail --------------------------------------------------

Widget buildSwapActivityDetailGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final status = wbStateKnob<SwapActivityStatusCase>(
    context,
    label: 'Status',
    options: SwapActivityStatusCase.values,
    labelBuilder: swapActivityStatusCaseLabel,
  );
  final mode = wbStateKnob<SwapActivityMode>(
    context,
    label: 'Mode',
    options: SwapActivityMode.values,
    labelBuilder: swapActivityModeLabel,
  );
  final intentCase = wbStateKnob<SwapActivityIntentCase>(
    context,
    label: 'Intent',
    options: SwapActivityIntentCase.values,
    labelBuilder: swapActivityIntentCaseLabel,
  );
  final notice = wbStateKnob<SwapActivityNotice>(
    context,
    label: 'Notice',
    options: SwapActivityNotice.values,
    labelBuilder: swapActivityNoticeLabel,
  );
  // The hardware ZEC deposit page is chosen by the account the intent belongs
  // to, not by a prop, so the axis is an account rather than a page.
  final hardware = wbBoolKnob(context, label: 'Hardware account');
  return WbFrame(
    layout: layout,
    child: swapActivityDetailSurfaceFixture(
      mobile: layout == WbLayout.mobile,
      status: status,
      mode: mode,
      intentCase: intentCase,
      notice: notice,
      hardwareAccount: hardware,
    ),
  );
}

String swapActivityStatusCaseLabel(SwapActivityStatusCase status) {
  return switch (status) {
    SwapActivityStatusCase.awaitingDeposit => 'Awaiting deposit',
    SwapActivityStatusCase.awaitingExternalDeposit =>
      'Awaiting external deposit',
    SwapActivityStatusCase.depositObserved => 'Deposit observed',
    SwapActivityStatusCase.processing => 'Processing',
    SwapActivityStatusCase.statusUnknown => 'Status unknown',
    SwapActivityStatusCase.incompleteDeposit => 'Incomplete deposit',
    SwapActivityStatusCase.complete => 'Complete',
    SwapActivityStatusCase.refunded => 'Refunded',
    SwapActivityStatusCase.expired => 'Expired',
    SwapActivityStatusCase.failed => 'Failed',
  };
}

String swapActivityModeLabel(SwapActivityMode mode) {
  return switch (mode) {
    SwapActivityMode.swap => 'Swap',
    SwapActivityMode.payment => 'Payment',
  };
}

String swapActivityIntentCaseLabel(SwapActivityIntentCase intentCase) {
  return switch (intentCase) {
    SwapActivityIntentCase.found => 'Found',
    SwapActivityIntentCase.missing => 'Missing',
  };
}

String swapActivityNoticeLabel(SwapActivityNotice notice) {
  return switch (notice) {
    SwapActivityNotice.none => 'None',
    SwapActivityNotice.statusRefreshError => 'Status refresh error',
  };
}

Widget buildSwapActivityPagePanelGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final content = wbStateKnob<SwapActivityPagePanelContent>(
    context,
    label: 'Content',
    options: SwapActivityPagePanelContent.values,
    labelBuilder: swapActivityPagePanelContentLabel,
  );
  return WbFrame(
    layout: layout,
    child: swapActivityDetailPagePanelFixture(
      content: content,
      mobile: layout == WbLayout.mobile,
    ),
  );
}

String swapActivityPagePanelContentLabel(SwapActivityPagePanelContent content) {
  return switch (content) {
    SwapActivityPagePanelContent.depositPage => 'Deposit page',
    SwapActivityPagePanelContent.statusPage => 'Status page',
  };
}

// --- Swap progress route ---------------------------------------------------

/// Which step carries the loader; clamped to the shorter list.
enum SwapProgressRouteStep { first, second, third, fourth }

Widget buildSwapProgressRouteGalleryCase(BuildContext context) {
  final variant = wbStateKnob<SwapProgressRouteVariant>(
    context,
    label: 'Variant',
    options: SwapProgressRouteVariant.values,
    labelBuilder: swapProgressRouteVariantLabel,
  );
  final length = wbStateKnob<SwapProgressRouteLength>(
    context,
    label: 'Steps',
    options: SwapProgressRouteLength.values,
    labelBuilder: swapProgressRouteLengthLabel,
  );
  final step = wbStateKnob<SwapProgressRouteStep>(
    context,
    label: 'Active step',
    options: SwapProgressRouteStep.values,
    labelBuilder: swapProgressRouteStepLabel,
  );
  final copy = wbStateKnob<SwapProgressRouteCopy>(
    context,
    label: 'Supporting copy',
    options: SwapProgressRouteCopy.values,
    labelBuilder: swapProgressRouteCopyLabel,
  );
  return swapProgressRouteFixture(
    variant: variant,
    length: length,
    activeStep: SwapProgressRouteStep.values.indexOf(step),
    copy: copy,
  );
}

String swapProgressRouteVariantLabel(SwapProgressRouteVariant variant) {
  return switch (variant) {
    SwapProgressRouteVariant.plain => 'Static',
    SwapProgressRouteVariant.animated => 'Animated, live quote',
  };
}

String swapProgressRouteLengthLabel(SwapProgressRouteLength length) {
  return switch (length) {
    SwapProgressRouteLength.three => 'Three steps',
    SwapProgressRouteLength.four => 'Four steps',
  };
}

String swapProgressRouteStepLabel(SwapProgressRouteStep step) {
  return switch (step) {
    SwapProgressRouteStep.first => 'First',
    SwapProgressRouteStep.second => 'Second',
    SwapProgressRouteStep.third => 'Third',
    SwapProgressRouteStep.fourth => 'Fourth',
  };
}

String swapProgressRouteCopyLabel(SwapProgressRouteCopy copy) {
  return switch (copy) {
    SwapProgressRouteCopy.none => 'None',
    SwapProgressRouteCopy.lastChecked => 'Last checked',
    SwapProgressRouteCopy.description => 'Description',
  };
}

// --- Swap review info ------------------------------------------------------

Widget buildSwapReviewInfoGalleryCase(BuildContext context) {
  final detail = wbStateKnob<SwapReviewInfoDetail>(
    context,
    label: 'Side detail',
    options: SwapReviewInfoDetail.values,
    labelBuilder: swapReviewInfoDetailLabel,
  );
  final asset = wbStateKnob<SwapReviewInfoAsset>(
    context,
    label: 'Asset',
    options: SwapReviewInfoAsset.values,
    labelBuilder: swapReviewInfoAssetLabel,
  );
  return swapReviewInfoFixture(detail: detail, asset: asset);
}

String swapReviewInfoDetailLabel(SwapReviewInfoDetail detail) {
  return switch (detail) {
    SwapReviewInfoDetail.fiat => 'Fiat line',
    SwapReviewInfoDetail.copyableAddress => 'Copyable address',
  };
}

String swapReviewInfoAssetLabel(SwapReviewInfoAsset asset) {
  return switch (asset) {
    SwapReviewInfoAsset.zec => 'ZEC',
    SwapReviewInfoAsset.external => 'USDC on Ethereum',
    SwapReviewInfoAsset.letterFallback => 'Unknown token',
  };
}

// --- Swap asset icon -------------------------------------------------------

Widget buildSwapAssetIconGalleryCase(BuildContext context) {
  final asset = wbStateKnob<SwapAssetIconAsset>(
    context,
    label: 'Asset',
    options: SwapAssetIconAsset.values,
    labelBuilder: swapAssetIconAssetLabel,
  );
  final size = wbStateKnob<SwapAssetIconSize>(
    context,
    label: 'Size',
    options: SwapAssetIconSize.values,
    labelBuilder: swapAssetIconSizeLabel,
  );
  final chainBadge = wbBoolKnob(context, label: 'Chain badge', initial: true);
  final selected = wbBoolKnob(context, label: 'Selected');
  return swapAssetIconFixture(
    asset: asset,
    chainBadge: chainBadge,
    selected: selected,
    size: size,
  );
}

String swapAssetIconAssetLabel(SwapAssetIconAsset asset) {
  return switch (asset) {
    SwapAssetIconAsset.zec => 'ZEC',
    SwapAssetIconAsset.usdc => 'USDC',
    SwapAssetIconAsset.unknown => 'Unknown token',
  };
}

String swapAssetIconSizeLabel(SwapAssetIconSize size) {
  return switch (size) {
    SwapAssetIconSize.desktop => 'Desktop 32',
    SwapAssetIconSize.mobile => 'Mobile 40',
  };
}

// --- NEAR Intents attribution ----------------------------------------------

Widget buildSwapAttributionGalleryCase(BuildContext context) {
  final alignment = wbStateKnob<SwapAttributionAlignment>(
    context,
    label: 'Alignment',
    options: SwapAttributionAlignment.values,
    labelBuilder: swapAttributionAlignmentLabel,
  );
  return swapAttributionFixture(alignment: alignment);
}

String swapAttributionAlignmentLabel(SwapAttributionAlignment alignment) {
  return switch (alignment) {
    SwapAttributionAlignment.left => 'Left',
    SwapAttributionAlignment.centered => 'Centered',
    SwapAttributionAlignment.end => 'End',
  };
}

// --- Swap modal controls ---------------------------------------------------

Widget buildSwapModalControlsGalleryCase(BuildContext context) {
  final control = wbStateKnob<SwapModalControl>(
    context,
    label: 'Control',
    options: SwapModalControl.values,
    labelBuilder: swapModalControlLabel,
  );
  return swapModalControlsFixture(control: control);
}

String swapModalControlLabel(SwapModalControl control) {
  return switch (control) {
    SwapModalControl.iconBadge => 'Icon badge',
    SwapModalControl.inlineIconButtonDesktop =>
      'Inline icon button, desktop 20',
    SwapModalControl.inlineIconButtonMobile => 'Inline icon button, mobile 24',
    SwapModalControl.modalButtons => 'Modal buttons',
    SwapModalControl.modalButtonsPrimaryDisabled =>
      'Modal buttons, primary disabled',
  };
}
