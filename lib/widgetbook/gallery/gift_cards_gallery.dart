// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/features/payment_links/services/payment_link_received_store.dart';
import '../../src/features/payment_links/widgets/payment_link_cards_layout.dart';
import '../../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../gift_cards_screen_use_cases.dart';
import '../payment_link_mobile_use_cases.dart';
import '../payment_link_use_cases.dart';
import '../screen_use_cases.dart';
import '../support/wb_design_status.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';

/// The Gift cards gallery: one use case per surface, every knob dispatching to
/// an existing `build*UseCase` in the payment-link fixture files so
/// figma_compare and the fixture tests keep the builders they bind to.
///
/// Desktop and mobile are separate widget classes here (`*DesktopView` vs
/// `*MobileView`), so a `Layout` knob swaps them; where only one lane has a
/// fixture the knob's option list is filtered instead of offering a dead
/// option. Surfaces whose widget branches on `kAppFormFactor` internally (the
/// claim outcome, the Keystone signing overlay) either carry no `Layout` knob
/// or gate it behind `WbLaneOnly`, because the knob cannot change what renders.
final List<WidgetbookNode> giftCardsGalleryNodes = [
  WidgetbookComponent(
    name: 'Gift cards home',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildGiftCardsHomeGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Cards list',
        builder: buildGiftCardsCardsListGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'How it works',
        builder: buildGiftCardsHowItWorksGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Create amount',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildGiftCardsAmountGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Create message',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildGiftCardsMessageGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Review',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildGiftCardsReviewGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Ready',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildGiftCardsReadyGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Share QR',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildGiftCardsShareQrGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Redeem',
    useCases: [
      WidgetbookUseCase(
        name: 'Entry',
        builder: buildGiftCardsRedeemGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Claim result',
        builder: buildGiftCardsClaimOutcomeGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Scan sheet',
        builder: buildGiftCardsScanGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Received',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildGiftCardsReceivedGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Claim account picker',
        builder: buildGiftCardsClaimAccountGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Activity and detail',
    useCases: [
      WidgetbookUseCase(
        name: 'Activity row',
        builder: buildGiftCardsActivityGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Card detail',
        builder: buildGiftCardsDetailGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Mobile',
    useCases: [
      WidgetbookUseCase(
        name: 'Body navigator',
        builder: buildGiftCardsMobileBodyGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Keystone',
    useCases: [
      WidgetbookUseCase(
        name: 'Signing overlay',
        builder: buildGiftCardsKeystoneSigningGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Components',
    useCases: [
      WidgetbookUseCase(
        name: 'Card row',
        builder: buildGiftCardsCardRowGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Gift card',
        builder: buildGiftCardsGiftCardGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Card selector',
        builder: buildGiftCardsCardSelectorGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Selector rail',
        builder: buildGiftCardsSelectorRailGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'QR share card',
        builder: buildGiftCardsQrShareCardGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Action shell',
        builder: buildGiftCardsActionShellGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Archive header',
        builder: buildGiftCardsArchiveHeaderGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Wizard stepper',
        builder: buildGiftCardsWizardStepperGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Motion',
    useCases: [
      WidgetbookUseCase(
        name: 'Interactive handoff',
        builder: buildPaymentLinkMotionHandoffUseCase,
        designLink: wbNoFigma(
          note:
              'Code-only: a motion handoff harness with its own headings, '
              'not a product screen.',
        ),
      ),
    ],
  ),
];

// --- Gift cards home -------------------------------------------------------

/// What the home pane shows. The mobile fixtures cover only the two values in
/// [giftCardsHomeContentOptions]; the rest are desktop-only today. 'How it
/// works' is its own use case, so the surface has exactly one entry.
enum GiftCardsHomeContent { empty, createdCards, receiving, received }

List<GiftCardsHomeContent> giftCardsHomeContentOptions(WbLayout layout) {
  return layout == WbLayout.desktop
      ? GiftCardsHomeContent.values
      : const [GiftCardsHomeContent.empty, GiftCardsHomeContent.createdCards];
}

String giftCardsHomeContentLabel(GiftCardsHomeContent content) {
  return switch (content) {
    GiftCardsHomeContent.empty => 'Empty',
    GiftCardsHomeContent.createdCards => 'Created cards',
    GiftCardsHomeContent.receiving => 'Receiving',
    GiftCardsHomeContent.received => 'Received',
  };
}

Widget buildGiftCardsHomeGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final content = wbStateKnob<GiftCardsHomeContent>(
    context,
    label: 'Content',
    options: giftCardsHomeContentOptions(layout),
    labelBuilder: giftCardsHomeContentLabel,
  );
  if (layout == WbLayout.mobile) {
    return switch (content) {
      GiftCardsHomeContent.createdCards =>
        buildMobilePaymentLinkHomeCardsUseCase(context),
      _ => buildMobilePaymentLinkHomeEmptyUseCase(context),
    };
  }
  return switch (content) {
    GiftCardsHomeContent.empty => buildPaymentLinkEmptyUseCase(context),
    GiftCardsHomeContent.createdCards => buildPaymentLinkCardsListUseCase(
      context,
    ),
    GiftCardsHomeContent.receiving => buildPaymentLinkCardsReceivingUseCase(
      context,
    ),
    GiftCardsHomeContent.received => buildPaymentLinkCardsReceivedUseCase(
      context,
    ),
  };
}

/// Where the help modal sits: on its own, or over the home pane it opens from.
enum GiftCardsHelpPresentation { standalone, overHome }

String giftCardsHelpPresentationLabel(GiftCardsHelpPresentation value) {
  return value == GiftCardsHelpPresentation.standalone
      ? 'Standalone'
      : 'Over home';
}

Widget buildGiftCardsHowItWorksGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final presentation = wbStateKnob<GiftCardsHelpPresentation>(
    context,
    label: 'Presentation',
    options: GiftCardsHelpPresentation.values,
    labelBuilder: giftCardsHelpPresentationLabel,
  );
  return giftCardsHowItWorksFixture(
    layout: layout,
    overHome: presentation == GiftCardsHelpPresentation.overHome,
  );
}

/// The created and received card lists, including the claim-outcome rows and
/// the archive section the received tab folds them into.
String giftCardsListContentLabel(GiftCardsListContent content) {
  return switch (content) {
    GiftCardsListContent.empty => 'Empty',
    GiftCardsListContent.creating => 'Creating',
    GiftCardsListContent.pending => 'Pending',
    GiftCardsListContent.claimOutcomes => 'Claim outcomes',
    GiftCardsListContent.archiveCollapsed => 'Archive collapsed',
    GiftCardsListContent.archiveExpanded => 'Archive expanded',
  };
}

String giftCardsTabLabel(PaymentLinkCardsTab tab) {
  return tab == PaymentLinkCardsTab.created ? 'Created' : 'Received';
}

Widget buildGiftCardsCardsListGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final tab = wbStateKnob<PaymentLinkCardsTab>(
    context,
    label: 'Tab',
    options: PaymentLinkCardsTab.values,
    labelBuilder: giftCardsTabLabel,
  );
  final content = wbStateKnob<GiftCardsListContent>(
    context,
    label: 'Content',
    options: GiftCardsListContent.values,
    labelBuilder: giftCardsListContentLabel,
    initial: GiftCardsListContent.pending,
  );
  final tabsEnabled = wbBoolKnob(context, label: 'Tabs enabled', initial: true);
  // A list long enough to overflow the pane, which is what raises the bottom
  // scroll fade on desktop.
  final longList = wbBoolKnob(context, label: 'Long list');
  return giftCardsCardsListFixture(
    layout: layout,
    tab: tab,
    content: content,
    tabsEnabled: tabsEnabled,
    longList: longList,
  );
}

// --- Create amount ---------------------------------------------------------

/// Amount-step states. The two interactive options keep dispatching to the
/// live simulators; the rest go through the parameterized fixture so the
/// supporting-text and continue axes stay orthogonal.
enum GiftCardsAmountState {
  empty,
  focused,
  amount,
  fiatLoading,
  fiatResolved,
  live,
  livePrefilled,
}

List<GiftCardsAmountState> giftCardsAmountStateOptions(WbLayout layout) {
  return layout == WbLayout.desktop
      ? GiftCardsAmountState.values
      : const [
          GiftCardsAmountState.empty,
          GiftCardsAmountState.focused,
          GiftCardsAmountState.amount,
          GiftCardsAmountState.fiatLoading,
          GiftCardsAmountState.fiatResolved,
          GiftCardsAmountState.live,
        ];
}

String giftCardsAmountStateLabel(GiftCardsAmountState state) {
  return switch (state) {
    GiftCardsAmountState.empty => 'Empty',
    GiftCardsAmountState.focused => 'Focused',
    GiftCardsAmountState.amount => 'Amount entered',
    GiftCardsAmountState.fiatLoading => 'Fiat loading',
    GiftCardsAmountState.fiatResolved => 'Fiat resolved',
    GiftCardsAmountState.live => 'Interactive',
    GiftCardsAmountState.livePrefilled => 'Interactive, prefilled',
  };
}

String giftCardsAmountSupportingLabel(GiftCardsAmountSupportingText text) {
  return switch (text) {
    GiftCardsAmountSupportingText.none => 'None',
    GiftCardsAmountSupportingText.syncing => 'Waiting for sync',
    GiftCardsAmountSupportingText.aboveMaximum => 'Above maximum',
    GiftCardsAmountSupportingText.feeEstimateFailed =>
      'Card fee could not be estimated',
    GiftCardsAmountSupportingText.feeStale => 'Card fee could not be updated',
  };
}

Widget buildGiftCardsAmountGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final state = wbStateKnob<GiftCardsAmountState>(
    context,
    label: 'State',
    options: giftCardsAmountStateOptions(layout),
    labelBuilder: giftCardsAmountStateLabel,
    initial: GiftCardsAmountState.amount,
  );
  final supporting = wbStateKnob<GiftCardsAmountSupportingText>(
    context,
    label: 'Supporting text',
    options: GiftCardsAmountSupportingText.values,
    labelBuilder: giftCardsAmountSupportingLabel,
  );
  final continueEnabled = wbBoolKnob(
    context,
    label: 'Continue enabled',
    initial: true,
  );
  var keyboardOpen = false;
  if (layout == WbLayout.mobile) {
    keyboardOpen = wbBoolKnob(context, label: 'Keyboard open');
  }
  var stepperInteractive = true;
  if (layout == WbLayout.desktop) {
    stepperInteractive = wbBoolKnob(
      context,
      label: 'Stepper enabled',
      initial: true,
    );
  }
  switch (state) {
    // The mobile simulator walks amount to message to review from here.
    case GiftCardsAmountState.live:
      return layout == WbLayout.mobile
          ? buildMobilePaymentLinkInteractiveUseCase(context)
          : buildPaymentLinkInteractiveUseCase(context);
    case GiftCardsAmountState.livePrefilled:
      return buildPaymentLinkInteractiveFocusedUseCase(context);
    default:
      return giftCardsAmountFixture(
        layout: layout,
        stage: switch (state) {
          GiftCardsAmountState.empty => GiftCardsAmountStage.empty,
          GiftCardsAmountState.focused => GiftCardsAmountStage.focused,
          GiftCardsAmountState.fiatLoading => GiftCardsAmountStage.fiatLoading,
          GiftCardsAmountState.fiatResolved =>
            GiftCardsAmountStage.fiatResolved,
          _ => GiftCardsAmountStage.amountEntered,
        },
        supporting: supporting,
        continueEnabled: continueEnabled,
        keyboardOpen: keyboardOpen,
        stepperInteractive: stepperInteractive,
      );
  }
}

// --- Create message --------------------------------------------------------

/// Message-step states. 'Interactive' keeps the live desktop editor; the
/// static states carry the error and continue axes as their own knobs.
enum GiftCardsMessageState { empty, filled, editorFocused, live }

List<GiftCardsMessageState> giftCardsMessageStateOptions(WbLayout layout) {
  return layout == WbLayout.desktop
      ? GiftCardsMessageState.values
      : const [
          GiftCardsMessageState.empty,
          GiftCardsMessageState.filled,
          GiftCardsMessageState.editorFocused,
        ];
}

String giftCardsMessageStateLabel(GiftCardsMessageState state) {
  return switch (state) {
    GiftCardsMessageState.empty => 'Empty',
    GiftCardsMessageState.filled => 'Filled',
    GiftCardsMessageState.editorFocused => 'Editor focused',
    GiftCardsMessageState.live => 'Interactive',
  };
}

Widget buildGiftCardsMessageGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final state = wbStateKnob<GiftCardsMessageState>(
    context,
    label: 'State',
    options: giftCardsMessageStateOptions(layout),
    labelBuilder: giftCardsMessageStateLabel,
    initial: GiftCardsMessageState.filled,
  );
  final tooLarge = wbBoolKnob(context, label: 'Message too large');
  final continueEnabled = wbBoolKnob(
    context,
    label: 'Continue enabled',
    initial: true,
  );
  var stepperInteractive = true;
  if (layout == WbLayout.desktop) {
    stepperInteractive = wbBoolKnob(
      context,
      label: 'Stepper enabled',
      initial: true,
    );
  }
  if (state == GiftCardsMessageState.live) {
    return buildPaymentLinkMessageInteractiveUseCase(context);
  }
  return giftCardsMessageFixture(
    layout: layout,
    stage: switch (state) {
      GiftCardsMessageState.empty => GiftCardsMessageStage.empty,
      GiftCardsMessageState.editorFocused =>
        GiftCardsMessageStage.editorFocused,
      _ => GiftCardsMessageStage.filled,
    },
    tooLarge: tooLarge,
    continueEnabled: continueEnabled,
    stepperInteractive: stepperInteractive,
  );
}

// --- Review ----------------------------------------------------------------

/// Which side of the card the review step shows.
enum GiftCardsReviewFace { front, message }

String giftCardsReviewFaceLabel(GiftCardsReviewFace face) {
  return face == GiftCardsReviewFace.front ? 'Front' : 'Message';
}

String giftCardsReviewConfirmLabel(GiftCardsReviewConfirm confirm) {
  return switch (confirm) {
    GiftCardsReviewConfirm.create => 'Create card',
    GiftCardsReviewConfirm.creating => 'Creating...',
    GiftCardsReviewConfirm.retry => 'Try saving again',
    GiftCardsReviewConfirm.saving => 'Saving...',
    GiftCardsReviewConfirm.disabled => 'Disabled',
  };
}

Widget buildGiftCardsReviewGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final face = wbStateKnob<GiftCardsReviewFace>(
    context,
    label: 'Card face',
    options: GiftCardsReviewFace.values,
    labelBuilder: giftCardsReviewFaceLabel,
  );
  final confirm = wbStateKnob<GiftCardsReviewConfirm>(
    context,
    label: 'Confirm',
    options: GiftCardsReviewConfirm.values,
    labelBuilder: giftCardsReviewConfirmLabel,
  );
  // Small amounts are what make the fee label wrap.
  final smallAmounts = wbBoolKnob(context, label: 'Small amounts');
  var feeHelp = true;
  var largeText = false;
  var stepperInteractive = true;
  if (layout == WbLayout.mobile) {
    // The desktop total row always carries the help icon; only mobile gates
    // it on a handler, and only mobile has a text-scale fixture.
    feeHelp = wbBoolKnob(context, label: 'Fee help', initial: true);
    largeText = wbBoolKnob(context, label: 'Text scale 2x');
  } else {
    stepperInteractive = wbBoolKnob(
      context,
      label: 'Stepper enabled',
      initial: true,
    );
  }
  return giftCardsReviewFixture(
    layout: layout,
    showMessageSide: face == GiftCardsReviewFace.message,
    confirm: confirm,
    feeHelp: feeHelp,
    smallAmounts: smallAmounts,
    largeText: largeText,
    stepperInteractive: stepperInteractive,
  );
}

// --- Ready -----------------------------------------------------------------

List<GiftCardsReadyStage> giftCardsReadyStageOptions(WbLayout layout) {
  return layout == WbLayout.desktop
      ? const [GiftCardsReadyStage.waiting, GiftCardsReadyStage.ready]
      : GiftCardsReadyStage.values;
}

String giftCardsReadyStageLabel(GiftCardsReadyStage stage) {
  return switch (stage) {
    GiftCardsReadyStage.waiting => 'Waiting',
    GiftCardsReadyStage.availableSoon => 'Available soon',
    GiftCardsReadyStage.ready => 'Ready',
  };
}

String giftCardsReadyCopyLabel(GiftCardsReadyCopy copy) {
  return switch (copy) {
    GiftCardsReadyCopy.copyLink => 'Copy link',
    GiftCardsReadyCopy.copying => 'Copying...',
    GiftCardsReadyCopy.disabled => 'Disabled',
  };
}

String giftCardsWaitingIconLabel(GiftCardsWaitingIcon icon) {
  return switch (icon) {
    GiftCardsWaitingIcon.giftCard => 'Gift card',
    GiftCardsWaitingIcon.link => 'Link',
    GiftCardsWaitingIcon.time => 'Time',
  };
}

Widget buildGiftCardsReadyGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final stage = wbStateKnob<GiftCardsReadyStage>(
    context,
    label: 'State',
    options: giftCardsReadyStageOptions(layout),
    labelBuilder: giftCardsReadyStageLabel,
    initial: GiftCardsReadyStage.ready,
  );
  final copy = wbStateKnob<GiftCardsReadyCopy>(
    context,
    label: 'Copy',
    options: GiftCardsReadyCopy.values,
    labelBuilder: giftCardsReadyCopyLabel,
  );
  final confetti = wbBoolKnob(context, label: 'Confetti', initial: true);
  var waitingIcon = GiftCardsWaitingIcon.giftCard;
  if (layout == WbLayout.mobile) {
    // Only the mobile waiting pill carries an icon.
    waitingIcon = wbStateKnob<GiftCardsWaitingIcon>(
      context,
      label: 'Waiting icon',
      options: GiftCardsWaitingIcon.values,
      labelBuilder: giftCardsWaitingIconLabel,
    );
  }
  final reducedMotion = wbBoolKnob(context, label: 'Reduced motion');
  return giftCardsReadyFixture(
    layout: layout,
    stage: stage,
    copy: copy,
    confetti: confetti,
    waitingIcon: waitingIcon,
    reducedMotion: reducedMotion,
  );
}

// --- Share QR --------------------------------------------------------------

/// The five artworks the share composite is previewed on; the rail offers all
/// eleven, and the composite treats them identically.
const List<PaymentLinkCardArtwork> giftCardsShareArtworkOptions = [
  PaymentLinkCardArtwork.gift,
  PaymentLinkCardArtwork.ruby,
  PaymentLinkCardArtwork.diamond,
  PaymentLinkCardArtwork.chestLava,
  PaymentLinkCardArtwork.dragon,
];

String giftCardsShareArtworkLabel(PaymentLinkCardArtwork artwork) =>
    artwork.semanticLabel;

String giftCardsShareSaveLabel(GiftCardsShareAction action) {
  return switch (action) {
    GiftCardsShareAction.ready => 'Save QR code',
    GiftCardsShareAction.running => 'Saving...',
    GiftCardsShareAction.disabled => 'Disabled',
  };
}

String giftCardsShareCopyLabel(GiftCardsShareAction action) {
  return switch (action) {
    GiftCardsShareAction.ready => 'Copy link',
    GiftCardsShareAction.running => 'Copying...',
    GiftCardsShareAction.disabled => 'Disabled',
  };
}

/// Whether the QR payload fits a symbol at all.
enum GiftCardsShareQrSymbol { rendered, failed }

String giftCardsShareQrSymbolLabel(GiftCardsShareQrSymbol symbol) {
  return symbol == GiftCardsShareQrSymbol.rendered
      ? 'Rendered'
      : 'Could not be generated';
}

Widget buildGiftCardsShareQrGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final artwork = wbStateKnob<PaymentLinkCardArtwork>(
    context,
    label: 'Artwork',
    options: giftCardsShareArtworkOptions,
    labelBuilder: giftCardsShareArtworkLabel,
  );
  final symbol = wbStateKnob<GiftCardsShareQrSymbol>(
    context,
    label: 'QR',
    options: GiftCardsShareQrSymbol.values,
    labelBuilder: giftCardsShareQrSymbolLabel,
  );
  var save = GiftCardsShareAction.ready;
  var copy = GiftCardsShareAction.ready;
  if (layout == WbLayout.desktop) {
    // The mobile sheet owns its own 'Sharing...' / 'Copying...' state, so it
    // takes no label props to drive.
    save = wbStateKnob<GiftCardsShareAction>(
      context,
      label: 'Save QR',
      options: GiftCardsShareAction.values,
      labelBuilder: giftCardsShareSaveLabel,
    );
    copy = wbStateKnob<GiftCardsShareAction>(
      context,
      label: 'Copy link',
      options: GiftCardsShareAction.values,
      labelBuilder: giftCardsShareCopyLabel,
    );
  }
  return giftCardsShareQrFixture(
    layout: layout,
    save: save,
    copy: copy,
    qrFailed: symbol == GiftCardsShareQrSymbol.failed,
    artwork: artwork,
  );
}

// --- Redeem ----------------------------------------------------------------

String giftCardsRedeemStageLabel(GiftCardsRedeemStage stage) {
  return switch (stage) {
    GiftCardsRedeemStage.paste => 'Paste link',
    GiftCardsRedeemStage.checking => 'Checking',
    GiftCardsRedeemStage.invalid => 'Invalid link',
  };
}

Widget buildGiftCardsRedeemGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final stage = wbStateKnob<GiftCardsRedeemStage>(
    context,
    label: 'State',
    options: GiftCardsRedeemStage.values,
    labelBuilder: giftCardsRedeemStageLabel,
  );
  final retryLabel = wbBoolKnob(context, label: 'Try again label');
  final busy = wbBoolKnob(context, label: 'Working');
  final longSyncWarning = wbBoolKnob(context, label: 'Long sync warning');
  var fromQrCode = false;
  if (layout == WbLayout.mobile) {
    // Only the mobile invalid state distinguishes a scanned code from a link.
    fromQrCode = wbBoolKnob(context, label: 'Scanned QR code');
  }
  return giftCardsRedeemFixture(
    layout: layout,
    stage: stage,
    retryLabel: retryLabel,
    busy: busy,
    fromQrCode: fromQrCode,
    longSyncWarning: longSyncWarning,
  );
}

/// What the claim result reports back. `unchecked` is absent because it
/// renders exactly the 'Claim' copy [PaymentLinkAvailability.available] does.
const List<PaymentLinkAvailability> giftCardsClaimOutcomeOptions = [
  PaymentLinkAvailability.available,
  PaymentLinkAvailability.noBalance,
  PaymentLinkAvailability.claimedElsewhere,
  PaymentLinkAvailability.checking,
  PaymentLinkAvailability.rejected,
  PaymentLinkAvailability.failed,
];

String giftCardsClaimOutcomeLabel(PaymentLinkAvailability availability) {
  return switch (availability) {
    PaymentLinkAvailability.unchecked ||
    PaymentLinkAvailability.available => 'Ready to claim',
    PaymentLinkAvailability.noBalance => 'No balance',
    PaymentLinkAvailability.claimedElsewhere => 'Already claimed',
    PaymentLinkAvailability.checking => 'Checking result',
    PaymentLinkAvailability.rejected => 'Rejected',
    PaymentLinkAvailability.failed => 'Claim failed',
  };
}

String giftCardsClaimArchiveActionLabel(GiftCardsClaimArchiveAction action) {
  return switch (action) {
    GiftCardsClaimArchiveAction.none => 'None',
    GiftCardsClaimArchiveAction.hide => 'Hide card',
    GiftCardsClaimArchiveAction.restore => 'Restore card',
  };
}

Widget buildGiftCardsClaimOutcomeGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final availability = wbStateKnob<PaymentLinkAvailability>(
    context,
    label: 'Outcome',
    options: giftCardsClaimOutcomeOptions,
    labelBuilder: giftCardsClaimOutcomeLabel,
    initial: PaymentLinkAvailability.noBalance,
  );
  final busy = wbBoolKnob(context, label: 'Checking');
  final archiveAction = wbStateKnob<GiftCardsClaimArchiveAction>(
    context,
    label: 'Archive action',
    options: GiftCardsClaimArchiveAction.values,
    labelBuilder: giftCardsClaimArchiveActionLabel,
    initial: GiftCardsClaimArchiveAction.hide,
  );
  return giftCardsClaimOutcomeFixture(
    layout: layout,
    availability: availability,
    busy: busy,
    archiveAction: archiveAction,
  );
}

/// Camera and result states of the gift-card scan sheet.
enum GiftCardsScanState { scanning, wrongCode, cameraDenied }

String giftCardsScanStateLabel(GiftCardsScanState state) {
  return switch (state) {
    GiftCardsScanState.scanning => 'Scanning',
    GiftCardsScanState.wrongCode => 'Not a gift card',
    GiftCardsScanState.cameraDenied => 'Camera denied',
  };
}

// No `Layout` knob: scanning a card is a mobile-only surface.
Widget buildGiftCardsScanGalleryCase(BuildContext context) {
  final state = wbStateKnob<GiftCardsScanState>(
    context,
    label: 'State',
    options: GiftCardsScanState.values,
    labelBuilder: giftCardsScanStateLabel,
  );
  return switch (state) {
    GiftCardsScanState.scanning => buildMobilePaymentLinkScanUseCase(context),
    GiftCardsScanState.wrongCode => buildMobilePaymentLinkScanInvalidUseCase(
      context,
    ),
    GiftCardsScanState.cameraDenied => buildMobilePaymentLinkScanDeniedUseCase(
      context,
    ),
  };
}

// --- Received --------------------------------------------------------------

String giftCardsReceivedStageLabel(GiftCardsReceivedStage stage) {
  return switch (stage) {
    GiftCardsReceivedStage.waiting => 'Waiting for confirmations',
    GiftCardsReceivedStage.gift => 'Gift received',
  };
}

String giftCardsClaimActionLabel(GiftCardsClaimAction claim) {
  return switch (claim) {
    GiftCardsClaimAction.claim => 'Claim the gift',
    GiftCardsClaimAction.claiming => 'Claiming...',
    GiftCardsClaimAction.retry => 'Try again',
    GiftCardsClaimAction.disabled => 'Disabled',
  };
}

Widget buildGiftCardsReceivedGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final stage = wbStateKnob<GiftCardsReceivedStage>(
    context,
    label: 'State',
    options: GiftCardsReceivedStage.values,
    labelBuilder: giftCardsReceivedStageLabel,
    initial: GiftCardsReceivedStage.gift,
  );
  final hasMessage = wbBoolKnob(
    context,
    label: 'Message attached',
    initial: true,
  );
  final claim = wbStateKnob<GiftCardsClaimAction>(
    context,
    label: 'Claim',
    options: GiftCardsClaimAction.values,
    labelBuilder: giftCardsClaimActionLabel,
  );
  final reducedMotion = wbBoolKnob(context, label: 'Reduced motion');
  return giftCardsReceivedFixture(
    layout: layout,
    stage: stage,
    hasMessage: hasMessage,
    claim: claim,
    reducedMotion: reducedMotion,
  );
}

/// How many accounts the claim sheet has to list. Four rows fit before the
/// list scrolls, which is what separates 'few' from 'many'.
enum GiftCardsClaimAccounts { single, few, many }

String giftCardsClaimAccountsLabel(GiftCardsClaimAccounts accounts) {
  return switch (accounts) {
    GiftCardsClaimAccounts.single => '1 account',
    GiftCardsClaimAccounts.few => '3 accounts',
    GiftCardsClaimAccounts.many => '12 accounts',
  };
}

int giftCardsClaimAccountCount(GiftCardsClaimAccounts accounts) {
  return switch (accounts) {
    GiftCardsClaimAccounts.single => 1,
    GiftCardsClaimAccounts.few => 3,
    GiftCardsClaimAccounts.many => 12,
  };
}

/// Which row the sheet opens on.
enum GiftCardsClaimSelection { first, last }

String giftCardsClaimSelectionLabel(GiftCardsClaimSelection selection) {
  return selection == GiftCardsClaimSelection.first
      ? 'First account'
      : 'Last account';
}

// No `Layout` knob: the claim account sheet is a mobile-only surface.
Widget buildGiftCardsClaimAccountGalleryCase(BuildContext context) {
  final accounts = wbStateKnob<GiftCardsClaimAccounts>(
    context,
    label: 'Accounts',
    options: GiftCardsClaimAccounts.values,
    labelBuilder: giftCardsClaimAccountsLabel,
    initial: GiftCardsClaimAccounts.few,
  );
  final hardware = wbBoolKnob(context, label: 'Hardware account');
  final selection = wbStateKnob<GiftCardsClaimSelection>(
    context,
    label: 'Selection',
    options: GiftCardsClaimSelection.values,
    labelBuilder: giftCardsClaimSelectionLabel,
  );
  return giftCardsClaimAccountFixture(
    accountCount: giftCardsClaimAccountCount(accounts),
    hardwareAccount: hardware,
    selectLast: selection == GiftCardsClaimSelection.last,
  );
}

// --- Activity and detail ---------------------------------------------------

/// Stage of the gift-card row in the activity feed. Create and claim have
/// different stage sets, so this stays one fixture-selection axis.
///
/// The feed row is deliberately confirmation-count agnostic once the claim is
/// mined, so the 5-confirmation and complete fixtures render exactly what
/// [GiftCardsActivityStage.claimConfirmed] renders and are not offered here.
enum GiftCardsActivityStage {
  creating,
  created,
  claimTransitions,
  claimBroadcast,
  claimConfirmed,
}

String giftCardsActivityStageLabel(GiftCardsActivityStage stage) {
  return switch (stage) {
    GiftCardsActivityStage.creating => 'Creating',
    GiftCardsActivityStage.created => 'Created',
    GiftCardsActivityStage.claimTransitions => 'Claim transitions',
    GiftCardsActivityStage.claimBroadcast => 'Claim broadcast',
    GiftCardsActivityStage.claimConfirmed => 'Claim confirmed',
  };
}

// No `Layout` knob: the activity and receipt previews mount the mobile screens.
Widget buildGiftCardsActivityGalleryCase(BuildContext context) {
  final stage = wbStateKnob<GiftCardsActivityStage>(
    context,
    label: 'Stage',
    options: GiftCardsActivityStage.values,
    labelBuilder: giftCardsActivityStageLabel,
  );
  return switch (stage) {
    GiftCardsActivityStage.creating => buildGiftCardCreatingActivityPreview(
      context,
    ),
    GiftCardsActivityStage.created => buildGiftCardCreatedActivityPreview(
      context,
    ),
    GiftCardsActivityStage.claimTransitions =>
      buildGiftCardClaimTransitionPreview(context),
    GiftCardsActivityStage.claimBroadcast => buildGiftCardClaimBroadcastPreview(
      context,
    ),
    GiftCardsActivityStage.claimConfirmed =>
      buildGiftCardClaimOneConfirmationPreview(context),
  };
}

/// Stage of the gift-card receipt screen.
enum GiftCardsDetailStage {
  creating,
  created,
  redeeming,
  redeemed,
  claimTransitions,
}

String giftCardsDetailStageLabel(GiftCardsDetailStage stage) {
  return switch (stage) {
    GiftCardsDetailStage.creating => 'Creating',
    GiftCardsDetailStage.created => 'Created',
    GiftCardsDetailStage.redeeming => 'Redeeming',
    GiftCardsDetailStage.redeemed => 'Redeemed',
    GiftCardsDetailStage.claimTransitions => 'Claim transitions',
  };
}

Widget buildGiftCardsDetailGalleryCase(BuildContext context) {
  final stage = wbStateKnob<GiftCardsDetailStage>(
    context,
    label: 'Stage',
    options: GiftCardsDetailStage.values,
    labelBuilder: giftCardsDetailStageLabel,
  );
  return switch (stage) {
    GiftCardsDetailStage.creating => buildGiftCardCreatingDetailPreview(
      context,
    ),
    GiftCardsDetailStage.created => buildGiftCardCreatedDetailPreview(context),
    GiftCardsDetailStage.redeeming => buildGiftCardRedeemingDetailPreview(
      context,
    ),
    GiftCardsDetailStage.redeemed => buildGiftCardRedeemedDetailPreview(
      context,
    ),
    GiftCardsDetailStage.claimTransitions =>
      buildGiftCardClaimDetailTransitionPreview(context),
  };
}

// --- Mobile > Body navigator -----------------------------------------------

String giftCardsMobilePageLabel(GiftCardsMobilePage page) {
  return switch (page) {
    GiftCardsMobilePage.home => 'Home',
    GiftCardsMobilePage.amount => 'Amount',
    GiftCardsMobilePage.message => 'Message',
    GiftCardsMobilePage.review => 'Review',
    GiftCardsMobilePage.ready => 'Ready',
    GiftCardsMobilePage.redeem => 'Redeem',
    GiftCardsMobilePage.received => 'Received',
  };
}

String giftCardsClaimSessionLabel(GiftCardsClaimSession session) {
  return switch (session) {
    GiftCardsClaimSession.none => 'None',
    GiftCardsClaimSession.waiting => 'Waiting',
    GiftCardsClaimSession.availableSoon => 'Available soon',
    GiftCardsClaimSession.ready => 'Ready',
  };
}

/// Whether the review step is still creating the card or retrying the
/// recovery row the funding already wrote.
enum GiftCardsFundingMetadata { saved, retrySaving }

String giftCardsFundingMetadataLabel(GiftCardsFundingMetadata metadata) {
  return metadata == GiftCardsFundingMetadata.saved ? 'Saved' : 'Retry saving';
}

// No `Layout` knob: the body is the mobile side of the Gift Card screen.
Widget buildGiftCardsMobileBodyGalleryCase(BuildContext context) {
  final page = wbStateKnob<GiftCardsMobilePage>(
    context,
    label: 'Page',
    options: GiftCardsMobilePage.values,
    labelBuilder: giftCardsMobilePageLabel,
  );
  final hasCards = wbBoolKnob(context, label: 'Created cards');
  final keystoneOverlay = wbBoolKnob(context, label: 'Keystone overlay');
  final navigationLocked = wbBoolKnob(context, label: 'Navigation locked');
  final claimSession = wbStateKnob<GiftCardsClaimSession>(
    context,
    label: 'Claim session',
    options: GiftCardsClaimSession.values,
    labelBuilder: giftCardsClaimSessionLabel,
    initial: GiftCardsClaimSession.ready,
  );
  final fundingMetadata = wbStateKnob<GiftCardsFundingMetadata>(
    context,
    label: 'Funding metadata',
    options: GiftCardsFundingMetadata.values,
    labelBuilder: giftCardsFundingMetadataLabel,
  );
  return giftCardsMobileBodyFixture(
    page: page,
    hasCards: hasCards,
    keystoneOverlay: keystoneOverlay,
    navigationLocked: navigationLocked,
    claimSession: claimSession,
    pendingFundingMetadata:
        fundingMetadata == GiftCardsFundingMetadata.retrySaving,
  );
}

// --- Keystone > Signing overlay --------------------------------------------

String giftCardsKeystonePhaseLabel(GiftCardsKeystonePhase phase) {
  return switch (phase) {
    GiftCardsKeystonePhase.preparing => 'Preparing',
    GiftCardsKeystonePhase.ready => 'Ready to scan',
    GiftCardsKeystonePhase.failed => 'Failed',
  };
}

String giftCardsKeystoneErrorLabel(GiftCardsKeystoneError error) {
  return switch (error) {
    GiftCardsKeystoneError.provingParameters => 'Proving parameters',
    GiftCardsKeystoneError.expired => 'Expired',
    GiftCardsKeystoneError.broadcast => 'Broadcast failed',
    GiftCardsKeystoneError.signature => 'Signature not applied',
    GiftCardsKeystoneError.generic => 'Could not be completed',
  };
}

// No `Layout` knob: the overlay picks its surface from `kAppFormFactor`, so
// each lane shows its own branch.
Widget buildGiftCardsKeystoneSigningGalleryCase(BuildContext context) {
  final phase = wbStateKnob<GiftCardsKeystonePhase>(
    context,
    label: 'Phase',
    options: GiftCardsKeystonePhase.values,
    labelBuilder: giftCardsKeystonePhaseLabel,
    initial: GiftCardsKeystonePhase.ready,
  );
  final error = wbStateKnob<GiftCardsKeystoneError>(
    context,
    label: 'Error',
    options: GiftCardsKeystoneError.values,
    labelBuilder: giftCardsKeystoneErrorLabel,
  );
  return giftCardsKeystoneSigningFixture(phase: phase, error: error);
}

// --- Components ------------------------------------------------------------

/// Every exported design; the component cases treat them identically, so the
/// knob is an explicit matrix rather than the five the share composite shows.
const List<PaymentLinkCardArtwork> giftCardsComponentArtworkOptions =
    PaymentLinkCardArtwork.values;

String giftCardsRowTrailingLabel(GiftCardsRowTrailing trailing) {
  return switch (trailing) {
    GiftCardsRowTrailing.linkActions => 'Link actions',
    GiftCardsRowTrailing.copyIcon => 'Copy icon',
    GiftCardsRowTrailing.loader => 'Loader',
    GiftCardsRowTrailing.none => 'None',
  };
}

String giftCardsRowStatusLabel(GiftCardsRowStatus status) {
  return switch (status) {
    GiftCardsRowStatus.preparing => 'Preparing',
    GiftCardsRowStatus.noBalance => 'No balance',
    GiftCardsRowStatus.alreadyClaimed => 'Already claimed',
    GiftCardsRowStatus.checkingResult => 'Checking result',
    GiftCardsRowStatus.claimFailed => 'Claim failed',
    GiftCardsRowStatus.receiving => 'Receiving',
    GiftCardsRowStatus.received => 'Received',
  };
}

String giftCardsRowActionOptionLabel(GiftCardsRowAction action) {
  return switch (action) {
    GiftCardsRowAction.none => 'None',
    GiftCardsRowAction.checkStatus => 'Check status',
    GiftCardsRowAction.viewCard => 'View card',
  };
}

Widget buildGiftCardsCardRowGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final trailing = wbStateKnob<GiftCardsRowTrailing>(
    context,
    label: 'Trailing',
    options: giftCardsRowTrailingOptions(layout),
    labelBuilder: giftCardsRowTrailingLabel,
  );
  final status = wbStateKnob<GiftCardsRowStatus>(
    context,
    label: 'Status',
    options: GiftCardsRowStatus.values,
    labelBuilder: giftCardsRowStatusLabel,
  );
  final action = wbStateKnob<GiftCardsRowAction>(
    context,
    label: 'Action',
    options: GiftCardsRowAction.values,
    labelBuilder: giftCardsRowActionOptionLabel,
  );
  var secondaryAction = false;
  if (layout == WbLayout.desktop) {
    // Only the desktop row carries a secondary text action.
    secondaryAction = wbBoolKnob(context, label: 'Secondary action');
  }
  final enabled = wbBoolKnob(context, label: 'Enabled', initial: true);
  return giftCardsCardRowFixture(
    layout: layout,
    trailing: trailing,
    status: status,
    action: action,
    secondaryAction: secondaryAction,
    enabled: enabled,
  );
}

String giftCardsCardFaceLabel(GiftCardsCardFace face) {
  return face == GiftCardsCardFace.front ? 'Front' : 'Message';
}

String giftCardsCardAmountLabel(GiftCardsCardAmount amount) {
  return switch (amount) {
    GiftCardsCardAmount.placeholder => 'Placeholder',
    GiftCardsCardAmount.caret => 'Caret',
    GiftCardsCardAmount.value => 'Value',
  };
}

String giftCardsCardSupportingLabel(GiftCardsCardSupporting supporting) {
  return switch (supporting) {
    GiftCardsCardSupporting.none => 'None',
    GiftCardsCardSupporting.fiat => 'Fiat value',
    GiftCardsCardSupporting.loading => 'Fiat loading',
  };
}

String giftCardsCardMaxLabel(GiftCardsCardMax max) {
  return max == GiftCardsCardMax.hidden ? 'Hidden' : 'Shown';
}

String giftCardsCardMessageLabel(GiftCardsCardMessage message) {
  return switch (message) {
    GiftCardsCardMessage.empty => 'Empty',
    GiftCardsCardMessage.written => 'Written',
    GiftCardsCardMessage.atLimit => 'At limit',
  };
}

Widget buildGiftCardsGiftCardGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final artwork = wbStateKnob<PaymentLinkCardArtwork>(
    context,
    label: 'Artwork',
    options: giftCardsComponentArtworkOptions,
    labelBuilder: giftCardsShareArtworkLabel,
    initial: PaymentLinkCardArtwork.ruby,
  );
  final face = wbStateKnob<GiftCardsCardFace>(
    context,
    label: 'Face',
    options: GiftCardsCardFace.values,
    labelBuilder: giftCardsCardFaceLabel,
  );
  final amount = wbStateKnob<GiftCardsCardAmount>(
    context,
    label: 'Amount',
    options: GiftCardsCardAmount.values,
    labelBuilder: giftCardsCardAmountLabel,
    initial: GiftCardsCardAmount.value,
  );
  final supporting = wbStateKnob<GiftCardsCardSupporting>(
    context,
    label: 'Supporting',
    options: GiftCardsCardSupporting.values,
    labelBuilder: giftCardsCardSupportingLabel,
    initial: GiftCardsCardSupporting.fiat,
  );
  final max = wbStateKnob<GiftCardsCardMax>(
    context,
    label: 'Max button',
    options: GiftCardsCardMax.values,
    labelBuilder: giftCardsCardMaxLabel,
    initial: GiftCardsCardMax.shown,
  );
  final message = wbStateKnob<GiftCardsCardMessage>(
    context,
    label: 'Message',
    options: GiftCardsCardMessage.values,
    labelBuilder: giftCardsCardMessageLabel,
    initial: GiftCardsCardMessage.written,
  );
  final deleteAction = wbBoolKnob(
    context,
    label: 'Delete message',
    initial: true,
  );
  final reducedMotion = wbBoolKnob(context, label: 'Reduced motion');
  return giftCardsGiftCardFixture(
    layout: layout,
    artwork: artwork,
    face: face,
    amount: amount,
    supporting: supporting,
    max: max,
    message: message,
    deleteAction: deleteAction,
    reducedMotion: reducedMotion,
  );
}

String giftCardsSelectorStateLabel(GiftCardsSelectorState state) {
  return switch (state) {
    GiftCardsSelectorState.unselected => 'Default',
    GiftCardsSelectorState.selected => 'Selected',
    GiftCardsSelectorState.focused => 'Focused',
  };
}

Widget buildGiftCardsCardSelectorGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final artwork = wbStateKnob<PaymentLinkCardArtwork>(
    context,
    label: 'Artwork',
    options: giftCardsComponentArtworkOptions,
    labelBuilder: giftCardsShareArtworkLabel,
    initial: PaymentLinkCardArtwork.ruby,
  );
  final state = wbStateKnob<GiftCardsSelectorState>(
    context,
    label: 'State',
    options: GiftCardsSelectorState.values,
    labelBuilder: giftCardsSelectorStateLabel,
  );
  return giftCardsCardSelectorFixture(
    layout: layout,
    artwork: artwork,
    state: state,
  );
}

String giftCardsRailSelectionLabel(GiftCardsRailSelection selection) {
  return switch (selection) {
    GiftCardsRailSelection.first => 'First',
    GiftCardsRailSelection.middle => 'Middle',
    GiftCardsRailSelection.last => 'Last',
  };
}

Widget buildGiftCardsSelectorRailGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final selection = wbStateKnob<GiftCardsRailSelection>(
    context,
    label: 'Selection',
    options: GiftCardsRailSelection.values,
    labelBuilder: giftCardsRailSelectionLabel,
    initial: GiftCardsRailSelection.middle,
  );
  final reducedMotion = wbBoolKnob(context, label: 'Reduced motion');
  return giftCardsSelectorRailFixture(
    layout: layout,
    selection: selection,
    reducedMotion: reducedMotion,
  );
}

// No `Layout` knob: the composite is a fixed-size export, not a screen.
Widget buildGiftCardsQrShareCardGalleryCase(BuildContext context) {
  final artwork = wbStateKnob<PaymentLinkCardArtwork>(
    context,
    label: 'Artwork',
    options: giftCardsComponentArtworkOptions,
    labelBuilder: giftCardsShareArtworkLabel,
  );
  final symbol = wbStateKnob<GiftCardsShareQrSymbol>(
    context,
    label: 'QR',
    options: GiftCardsShareQrSymbol.values,
    labelBuilder: giftCardsShareQrSymbolLabel,
  );
  return giftCardsQrShareCardFixture(
    artwork: artwork,
    qrFailed: symbol == GiftCardsShareQrSymbol.failed,
  );
}

String giftCardsActionStateLabel(GiftCardsActionState state) {
  return switch (state) {
    GiftCardsActionState.idle => 'Idle',
    GiftCardsActionState.focused => 'Focused',
    GiftCardsActionState.disabled => 'Disabled',
  };
}

String giftCardsActionSlotsLabel(GiftCardsActionSlots slots) {
  return switch (slots) {
    GiftCardsActionSlots.labelOnly => 'Label only',
    GiftCardsActionSlots.leadingIcon => 'Leading icon',
    GiftCardsActionSlots.trailingIcon => 'Trailing icon',
  };
}

// No `Layout` knob: the action shell is one widget in both form factors.
Widget buildGiftCardsActionShellGalleryCase(BuildContext context) {
  final state = wbStateKnob<GiftCardsActionState>(
    context,
    label: 'State',
    options: GiftCardsActionState.values,
    labelBuilder: giftCardsActionStateLabel,
  );
  final slots = wbStateKnob<GiftCardsActionSlots>(
    context,
    label: 'Slots',
    options: GiftCardsActionSlots.values,
    labelBuilder: giftCardsActionSlotsLabel,
  );
  return giftCardsActionShellFixture(state: state, slots: slots);
}

/// How many cards the archive holds.
enum GiftCardsArchiveCount { one, few, many }

String giftCardsArchiveCountLabel(GiftCardsArchiveCount count) {
  return switch (count) {
    GiftCardsArchiveCount.one => '1 card',
    GiftCardsArchiveCount.few => '3 cards',
    GiftCardsArchiveCount.many => '12 cards',
  };
}

int giftCardsArchiveCountValue(GiftCardsArchiveCount count) {
  return switch (count) {
    GiftCardsArchiveCount.one => 1,
    GiftCardsArchiveCount.few => 3,
    GiftCardsArchiveCount.many => 12,
  };
}

// No `Layout` knob: the archive header is one widget in both form factors.
Widget buildGiftCardsArchiveHeaderGalleryCase(BuildContext context) {
  final expanded = wbBoolKnob(context, label: 'Expanded');
  final count = wbStateKnob<GiftCardsArchiveCount>(
    context,
    label: 'Count',
    options: GiftCardsArchiveCount.values,
    labelBuilder: giftCardsArchiveCountLabel,
    initial: GiftCardsArchiveCount.few,
  );
  final focused = wbBoolKnob(context, label: 'Focused');
  return giftCardsArchiveHeaderFixture(
    count: giftCardsArchiveCountValue(count),
    expanded: expanded,
    focused: focused,
  );
}

/// The three wizard steps, labelled the way the stepper labels them.
enum GiftCardsWizardStep { create, message, review }

String giftCardsWizardStepLabel(GiftCardsWizardStep step) {
  return switch (step) {
    GiftCardsWizardStep.create => 'Create',
    GiftCardsWizardStep.message => 'Add message',
    GiftCardsWizardStep.review => 'Review',
  };
}

String giftCardsStepperInteractionLabel(GiftCardsStepperInteraction value) {
  return switch (value) {
    GiftCardsStepperInteraction.interactive => 'Interactive',
    GiftCardsStepperInteraction.busy => 'Static while busy',
    GiftCardsStepperInteraction.focused => 'Focused step',
  };
}

// No `Layout` knob: the wizard stepper is desktop chrome.
Widget buildGiftCardsWizardStepperGalleryCase(BuildContext context) {
  final step = wbStateKnob<GiftCardsWizardStep>(
    context,
    label: 'Step',
    options: GiftCardsWizardStep.values,
    labelBuilder: giftCardsWizardStepLabel,
    initial: GiftCardsWizardStep.message,
  );
  final interaction = wbStateKnob<GiftCardsStepperInteraction>(
    context,
    label: 'Interaction',
    options: GiftCardsStepperInteraction.values,
    labelBuilder: giftCardsStepperInteractionLabel,
  );
  return giftCardsWizardStepperFixture(
    currentStep: step.index,
    interaction: interaction,
  );
}
