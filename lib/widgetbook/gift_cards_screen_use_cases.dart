// ignore_for_file: depend_on_referenced_packages
// Widgetbook is dev-only. Every value here is a deterministic literal: these
// fixtures never reach payment-link services, storage, network, or Rust state.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/comma_to_dot_input_formatter.dart';
import '../src/core/widgets/decimal_amount_input_formatter.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/payment_links/screens/payment_links_local_page.dart';
import '../src/features/payment_links/screens/payment_links_mobile_body.dart';
import '../src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import '../src/features/payment_links/services/payment_link_service.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_claim_account_sheet.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_share_sheet.dart';
import '../src/features/payment_links/widgets/payment_link_keystone_signing_overlay.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import '../src/features/payment_links/widgets/payment_link_archive_header.dart';
import '../src/features/payment_links/widgets/payment_link_card_flip.dart';
import '../src/features/payment_links/widgets/payment_link_card_selector.dart';
import '../src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import '../src/features/payment_links/widgets/payment_link_claim_outcome_view.dart';
import '../src/features/payment_links/widgets/payment_link_confetti.dart';
import '../src/features/payment_links/widgets/payment_link_copy.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../src/features/payment_links/widgets/payment_link_long_sync_warning.dart';
import '../src/features/payment_links/widgets/payment_link_qr_share_card.dart';
import '../src/features/payment_links/widgets/payment_link_wizard_chrome.dart';
import '../src/features/payment_links/services/payment_link_received_store.dart';
import 'support/wb_layout.dart';

// --- Shared fixture data ---------------------------------------------------

const _message = 'Hey there! Welcome to the Shielded World ;)';
const _messageCharacterCount = 42;
const _amount = '4.45';
const _fiat = r'$1,210.20';
const _maxAmount = '142.23';
const _amountFormatters = [
  CommaToDotInputFormatter(),
  DecimalAmountInputFormatter(maxFractionDigits: 8),
];
const _desktopArtwork = PaymentLinkCardArtwork.ruby;
const _wizardArtwork = PaymentLinkCardArtwork.chestLava;
const _mobileCardArtwork = PaymentLinkCardArtwork.knightMagic;

/// Reference stage of the mobile views; the phone frame is taller by the
/// status bar the fixtures keep empty.
const _phoneStageHeight = 773.0;

/// Height the software keyboard takes from the stage on a 393pt phone.
const _phoneKeyboardInset = 336.0;

// Supporting-text copy of the amount step, quoted from
// `payment_links_screen.dart`.
const _syncingSupportingText =
    'Card fee will be estimated when wallet sync completes.';
const _aboveMaximumSupportingText = 'Above your maximum ZEC';
const _feeEstimateFailedSupportingText =
    'Card fee could not be estimated. Try again.';
const _feeStaleSupportingText =
    'Card fee could not be updated. Return to the amount step and try again.';

// --- Create amount ---------------------------------------------------------

/// Amount-step states that do not need a live editor.
enum GiftCardsAmountStage {
  empty,
  focused,
  amountEntered,
  fiatLoading,
  fiatResolved,
}

/// The five supporting-text slots the amount step can show under the rail.
enum GiftCardsAmountSupportingText {
  none,
  syncing,
  aboveMaximum,
  feeEstimateFailed,
  feeStale,
}

Widget giftCardsAmountFixture({
  required WbLayout layout,
  required GiftCardsAmountStage stage,
  GiftCardsAmountSupportingText supporting = GiftCardsAmountSupportingText.none,
  bool continueEnabled = true,
  bool keyboardOpen = false,
  bool stepperInteractive = true,
}) {
  final isError =
      supporting == GiftCardsAmountSupportingText.aboveMaximum ||
      supporting == GiftCardsAmountSupportingText.feeEstimateFailed ||
      supporting == GiftCardsAmountSupportingText.feeStale;
  final supportingText = switch (supporting) {
    GiftCardsAmountSupportingText.none => null,
    GiftCardsAmountSupportingText.syncing => _syncingSupportingText,
    GiftCardsAmountSupportingText.aboveMaximum => _aboveMaximumSupportingText,
    GiftCardsAmountSupportingText.feeEstimateFailed =>
      _feeEstimateFailedSupportingText,
    GiftCardsAmountSupportingText.feeStale => _feeStaleSupportingText,
  };
  final card = _amountCard(layout: layout, stage: stage);
  if (layout == WbLayout.mobile) {
    return _frame(
      layout: layout,
      keyboardOpen: keyboardOpen,
      child: PaymentLinkAmountMobileView(
        card: card,
        cardSelector: _selectorRail(layout),
        onBack: _noop,
        onContinue: continueEnabled ? _noop : null,
        supportingText: supportingText,
        supportingTextIsError: isError,
      ),
    );
  }
  return _frame(
    layout: layout,
    child: PaymentLinkAmountDesktopView(
      state: switch (stage) {
        GiftCardsAmountStage.empty => PaymentLinkAmountVisualState.empty,
        GiftCardsAmountStage.focused => PaymentLinkAmountVisualState.focused,
        GiftCardsAmountStage.amountEntered =>
          PaymentLinkAmountVisualState.amount,
        GiftCardsAmountStage.fiatLoading =>
          PaymentLinkAmountVisualState.fiatLoading,
        GiftCardsAmountStage.fiatResolved =>
          PaymentLinkAmountVisualState.fiatLoaded,
      },
      card: card,
      cardSelector: _selectorRail(layout),
      onBack: _noop,
      onCreate: continueEnabled ? _noop : null,
      onStepSelected: stepperInteractive ? _ignoreStep : null,
      supportingText: supportingText,
      supportingTextIsError: isError,
      emptyActionLabel: isError ? 'Enter amount' : 'Continue',
    ),
  );
}

Widget _amountCard({
  required WbLayout layout,
  required GiftCardsAmountStage stage,
}) {
  final mobile = layout == WbLayout.mobile;
  final artwork = mobile ? _wizardArtwork : _desktopArtwork;
  final width = _cardWidth(layout);
  final height = _cardHeight(layout);
  // Mobile has no focused visual state: the caret comes from a real editor.
  if (mobile && stage == GiftCardsAmountStage.focused) {
    return _GiftCardsFocusedAmountCard(artwork: artwork);
  }
  return switch (stage) {
    GiftCardsAmountStage.empty => PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      emptyAmountLabel: 'Enter Amount',
      maxAmountText: _maxAmount,
      onUseMax: _noop,
    ),
    GiftCardsAmountStage.focused => PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      amountText: '1',
      maxAmountText: _maxAmount,
      onUseMax: _noop,
      showMaxButton: true,
    ),
    GiftCardsAmountStage.amountEntered => PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      amountText: _amount,
      maxAmountText: _maxAmount,
      onUseMax: _noop,
      showMaxButton: true,
    ),
    GiftCardsAmountStage.fiatLoading => PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      amountText: _amount,
      maxAmountText: _maxAmount,
      onUseMax: _noop,
      showMaxButton: true,
      supportingLoading: true,
      showCaret: false,
    ),
    GiftCardsAmountStage.fiatResolved => PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      amountText: _amount,
      maxAmountText: _maxAmount,
      onUseMax: _noop,
      showMaxButton: true,
      supportingText: _fiat,
      showCaret: false,
    ),
  };
}

/// Amount card whose editor takes focus on the first frame, so the caret and
/// the focused card treatment render without a tap.
class _GiftCardsFocusedAmountCard extends StatefulWidget {
  const _GiftCardsFocusedAmountCard({required this.artwork});

  final PaymentLinkCardArtwork artwork;

  @override
  State<_GiftCardsFocusedAmountCard> createState() =>
      _GiftCardsFocusedAmountCardState();
}

class _GiftCardsFocusedAmountCardState
    extends State<_GiftCardsFocusedAmountCard> {
  final _controller = TextEditingController(text: _amount);
  final _focusNode = FocusNode(debugLabel: 'GiftCardsAmountFixture');
  var _focusUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      } else {
        setState(() => _focusUnavailable = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_focusUnavailable) {
      return PaymentLinkGiftCard(
        artwork: widget.artwork,
        cardWidth: kPaymentLinkMobileCardWidth,
        cardHeight: kPaymentLinkMobileCardHeight,
        amountText: _amount,
        maxAmountText: _maxAmount,
        onUseMax: _noop,
        showMaxButton: true,
        supportingLoading: true,
      );
    }
    return PaymentLinkGiftCard(
      artwork: widget.artwork,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
      amountController: _controller,
      amountFocusNode: _focusNode,
      amountEditorKey: const ValueKey('gift_cards_focused_amount_editor'),
      amountInputFormatters: _amountFormatters,
      supportingLoading: true,
      semanticLabel: 'Gift card amount input',
    );
  }
}

// --- Create message --------------------------------------------------------

enum GiftCardsMessageStage { empty, filled, editorFocused }

Widget giftCardsMessageFixture({
  required WbLayout layout,
  required GiftCardsMessageStage stage,
  bool tooLarge = false,
  bool continueEnabled = true,
  bool stepperInteractive = true,
}) {
  final card = _messageCard(layout: layout, stage: stage);
  final errorText = tooLarge ? kPaymentLinkMessageTooLargeText : null;
  if (layout == WbLayout.mobile) {
    return _frame(
      layout: layout,
      child: PaymentLinkMessageMobileView(
        card: card,
        onBack: _noop,
        onContinue: continueEnabled ? _noop : null,
        onSkip: continueEnabled ? _noop : null,
        errorText: errorText,
      ),
    );
  }
  return _frame(
    layout: layout,
    child: PaymentLinkMessageDesktopView(
      state: stage == GiftCardsMessageStage.empty
          ? PaymentLinkMessageVisualState.empty
          : PaymentLinkMessageVisualState.filled,
      card: card,
      onBack: _noop,
      onSkip: _noop,
      onContinue: continueEnabled ? _noop : null,
      onStepSelected: stepperInteractive ? _ignoreStep : null,
      errorText: errorText,
    ),
  );
}

Widget _messageCard({
  required WbLayout layout,
  required GiftCardsMessageStage stage,
}) {
  final artwork = layout == WbLayout.mobile ? _wizardArtwork : _desktopArtwork;
  final width = _cardWidth(layout);
  final height = _cardHeight(layout);
  return switch (stage) {
    GiftCardsMessageStage.empty => PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      showBack: true,
    ),
    GiftCardsMessageStage.filled => PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      showBack: true,
      message: _message,
      messageCharacterCount: _messageCharacterCount,
      onDeleteMessage: _noop,
    ),
    GiftCardsMessageStage.editorFocused => _GiftCardsFocusedMessageCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
    ),
  };
}

/// Message card whose editor takes focus on the first frame.
class _GiftCardsFocusedMessageCard extends StatefulWidget {
  const _GiftCardsFocusedMessageCard({
    required this.artwork,
    required this.cardWidth,
    required this.cardHeight,
  });

  final PaymentLinkCardArtwork artwork;
  final double cardWidth;
  final double cardHeight;

  @override
  State<_GiftCardsFocusedMessageCard> createState() =>
      _GiftCardsFocusedMessageCardState();
}

class _GiftCardsFocusedMessageCardState
    extends State<_GiftCardsFocusedMessageCard> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'GiftCardsMessageFixture');
  var _focusUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      } else {
        setState(() => _focusUnavailable = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_focusUnavailable) {
      return PaymentLinkGiftCard(
        artwork: widget.artwork,
        cardWidth: widget.cardWidth,
        cardHeight: widget.cardHeight,
        showBack: true,
        emptyMessageLabel: '',
      );
    }
    return PaymentLinkGiftCard(
      artwork: widget.artwork,
      cardWidth: widget.cardWidth,
      cardHeight: widget.cardHeight,
      showBack: true,
      messageController: _controller,
      messageFocusNode: _focusNode,
      messageEditorKey: const ValueKey('gift_cards_focused_message_editor'),
      semanticLabel: 'Gift card message input',
    );
  }
}

// --- Review ----------------------------------------------------------------

/// Every confirm label the review step can show, plus the disabled slot.
enum GiftCardsReviewConfirm { create, creating, retry, saving, disabled }

Widget giftCardsReviewFixture({
  required WbLayout layout,
  bool showMessageSide = false,
  GiftCardsReviewConfirm confirm = GiftCardsReviewConfirm.create,
  bool feeHelp = true,
  bool smallAmounts = false,
  bool largeText = false,
  bool stepperInteractive = true,
}) {
  final mobile = layout == WbLayout.mobile;
  final amountText = smallAmounts ? '0.001' : _amount;
  final cardAmountText = '$amountText ZEC';
  final cardFeeText = smallAmounts ? '0.0002 ZEC' : '0.04 ZEC';
  final totalAmountText = smallAmounts ? '0.0012 ZEC' : '4.49 ZEC';
  final onConfirm = switch (confirm) {
    GiftCardsReviewConfirm.creating ||
    GiftCardsReviewConfirm.saving ||
    GiftCardsReviewConfirm.disabled => null,
    GiftCardsReviewConfirm.create || GiftCardsReviewConfirm.retry => _noop,
  };
  final label = switch (confirm) {
    GiftCardsReviewConfirm.creating => 'Creating...',
    GiftCardsReviewConfirm.retry => 'Try saving again',
    GiftCardsReviewConfirm.saving => 'Saving...',
    _ => mobile ? 'Approve & create' : 'Create card',
  };
  final card = _reviewCard(
    layout: layout,
    amountText: amountText,
    showBack: showMessageSide,
  );
  final view = mobile
      ? PaymentLinkReviewMobileView(
          card: card,
          onBack: _noop,
          cardAmountText: cardAmountText,
          cardFeeText: cardFeeText,
          totalAmountText: totalAmountText,
          onContinue: onConfirm,
          onFeeHelp: feeHelp ? _noop : null,
          continueLabel: label,
        )
      : PaymentLinkReviewDesktopView(
          card: card,
          onBack: _noop,
          cardAmountText: cardAmountText,
          cardFeeText: cardFeeText,
          totalAmountText: totalAmountText,
          onConfirm: onConfirm,
          onStepSelected: stepperInteractive ? _ignoreStep : null,
          confirmLabel: label,
        );
  return _textScale(largeText, _frame(layout: layout, child: view));
}

Widget _reviewCard({
  required WbLayout layout,
  required String amountText,
  required bool showBack,
}) {
  final artwork = layout == WbLayout.mobile
      ? _mobileCardArtwork
      : _desktopArtwork;
  final width = _cardWidth(layout);
  final height = _cardHeight(layout);
  return PaymentLinkCardFlip(
    showBack: showBack,
    front: PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      amountText: amountText,
      supportingText: _fiat,
      showCaret: false,
      semanticLabel: kPaymentLinkRevealMessageSemanticLabel,
    ),
    back: PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      showBack: true,
      message: _message,
      messageCharacterCount: _messageCharacterCount,
      semanticLabel: 'Show gift card front',
    ),
  );
}

// --- Ready / share ---------------------------------------------------------

enum GiftCardsReadyStage { waiting, availableSoon, ready }

enum GiftCardsReadyCopy { copyLink, copying, disabled }

/// Icon of the mobile waiting pill; the desktop pill carries no icon.
enum GiftCardsWaitingIcon { giftCard, link, time }

Widget giftCardsReadyFixture({
  required WbLayout layout,
  required GiftCardsReadyStage stage,
  GiftCardsReadyCopy copy = GiftCardsReadyCopy.copyLink,
  bool confetti = true,
  GiftCardsWaitingIcon waitingIcon = GiftCardsWaitingIcon.giftCard,
  bool reducedMotion = false,
}) {
  final ready = stage == GiftCardsReadyStage.ready;
  final copyLabel = copy == GiftCardsReadyCopy.copying
      ? 'Copying...'
      : 'Copy link';
  final onCopy = copy == GiftCardsReadyCopy.copyLink ? _noop : null;
  final decoration = confetti ? const PaymentLinkConfetti() : null;
  final card = _shareCard(layout);
  final view = layout == WbLayout.mobile
      ? PaymentLinkReadyMobileView(
          state: switch (stage) {
            GiftCardsReadyStage.ready => PaymentLinkReadyMobileState.ready,
            GiftCardsReadyStage.availableSoon =>
              PaymentLinkReadyMobileState.soon,
            GiftCardsReadyStage.waiting => PaymentLinkReadyMobileState.waiting,
          },
          card: card,
          onHome: _noop,
          onCopy: onCopy,
          copyLabel: copyLabel,
          decoration: decoration,
          waitingIcon: switch (waitingIcon) {
            GiftCardsWaitingIcon.giftCard => AppIcons.giftCard,
            GiftCardsWaitingIcon.link => AppIcons.link,
            GiftCardsWaitingIcon.time => AppIcons.time,
          },
          waitingStatusLabel: stage == GiftCardsReadyStage.availableSoon
              ? 'Wait 0:15 to get the link'
              : kPaymentLinkWaitingStatusLabel,
        )
      : PaymentLinkReadyDesktopView(
          state: ready
              ? PaymentLinkReadyVisualState.ready
              : PaymentLinkReadyVisualState.waiting,
          card: card,
          decoration: decoration,
          onBack: _noop,
          onCopy: onCopy,
          copyLabel: copyLabel,
          waitingStatusLabel: stage == GiftCardsReadyStage.availableSoon
              ? 'Wait 0:15 to get the link'
              : kPaymentLinkWaitingStatusLabel,
        );
  return _reduceMotion(reducedMotion, _frame(layout: layout, child: view));
}

// --- Received card ---------------------------------------------------------

enum GiftCardsReceivedStage { waiting, gift }

enum GiftCardsClaimAction { claim, claiming, retry, disabled }

Widget giftCardsReceivedFixture({
  required WbLayout layout,
  required GiftCardsReceivedStage stage,
  bool hasMessage = true,
  GiftCardsClaimAction claim = GiftCardsClaimAction.claim,
  bool reducedMotion = false,
}) {
  final mobile = layout == WbLayout.mobile;
  final card = hasMessage
      ? _shareCard(layout, flippable: true)
      : _shareCard(layout);
  final Widget view;
  if (stage == GiftCardsReceivedStage.waiting) {
    // The claim wait reuses the ready view with the claim waiting copy, the
    // way `payment_links_screen.dart` and the mobile body do.
    view = mobile
        ? PaymentLinkReadyMobileView(
            state: PaymentLinkReadyMobileState.soon,
            card: card,
            cardTop: kPaymentLinkMobileReceivedCardTop,
            onHome: _noop,
            waitingHeading: 'Your Gift Card\nis almost ready!',
            waitingDescription:
                '$kPaymentLinkClaimWaitingDescription\n$kPaymentLinkWaitingDescription',
            waitingIcon: AppIcons.time,
            waitingStatusLabel: 'Wait 5:00 to claim',
          )
        : PaymentLinkReadyDesktopView(
            state: PaymentLinkReadyVisualState.waiting,
            card: card,
            onBack: _noop,
            onCopy: null,
            waitingHeading: 'Your Gift Card\nis almost ready!',
            waitingPrimaryText: kPaymentLinkClaimWaitingDescription,
            waitingSecondaryText: kPaymentLinkWaitingDescription,
            waitingStatusLabel: 'Wait 5:00 to claim',
          );
  } else {
    final onClaim = switch (claim) {
      GiftCardsClaimAction.claiming || GiftCardsClaimAction.disabled => null,
      GiftCardsClaimAction.claim || GiftCardsClaimAction.retry => _noop,
    };
    final claimLabel = switch (claim) {
      GiftCardsClaimAction.claiming => 'Claiming...',
      GiftCardsClaimAction.retry => 'Try again',
      _ => mobile ? 'Claim the gift' : 'Claim the gift card',
    };
    view = mobile
        ? PaymentLinkReceivedMobileView(
            card: card,
            hasMessage: hasMessage,
            onClose: _noop,
            onClaim: onClaim,
            claimLabel: claimLabel,
            onRevealMessage: hasMessage ? _noop : null,
            decoration: const PaymentLinkConfetti(),
          )
        : PaymentLinkReceivedDesktopView(
            card: card,
            onBack: _noop,
            onClaim: onClaim,
            claimLabel: claimLabel,
            onRevealMessage: hasMessage ? _noop : null,
            decoration: const PaymentLinkConfetti(),
          );
  }
  return _reduceMotion(reducedMotion, _frame(layout: layout, child: view));
}

Widget _shareCard(WbLayout layout, {bool flippable = false}) {
  final artwork = layout == WbLayout.mobile
      ? _mobileCardArtwork
      : _desktopArtwork;
  final width = _cardWidth(layout);
  final height = _cardHeight(layout);
  final front = PaymentLinkGiftCard(
    artwork: artwork,
    cardWidth: width,
    cardHeight: height,
    amountText: _amount,
    supportingText: _fiat,
    showCaret: false,
  );
  if (!flippable) return front;
  return PaymentLinkCardFlip(
    showBack: false,
    front: front,
    back: PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: width,
      cardHeight: height,
      showBack: true,
      message: _message,
      messageCharacterCount: _messageCharacterCount,
    ),
  );
}

// --- Cards list ------------------------------------------------------------

/// What the selected tab lists.
enum GiftCardsListContent {
  empty,
  creating,
  pending,
  claimOutcomes,
  archiveCollapsed,
  archiveExpanded,
}

Widget giftCardsCardsListFixture({
  required WbLayout layout,
  PaymentLinkCardsTab tab = PaymentLinkCardsTab.created,
  GiftCardsListContent content = GiftCardsListContent.pending,
  bool tabsEnabled = true,
  bool longList = false,
}) {
  final sections = _cardsSections(
    layout: layout,
    content: content,
    longList: longList,
  );
  final onTabSelected = tabsEnabled ? _ignoreTab : null;
  if (layout == WbLayout.mobile) {
    return _frame(
      layout: layout,
      child: PaymentLinkCardsMobileView(
        sections: sections,
        activeTab: tab,
        onTabSelected: onTabSelected,
        emptyLabel: tab == PaymentLinkCardsTab.created
            ? kPaymentLinkNoCreatedCardsText
            : kPaymentLinkNoReceivedCardsText,
        onBack: _noop,
        onCreate: _noop,
        onRedeem: _noop,
      ),
    );
  }
  return _frame(
    layout: layout,
    child: PaymentLinkCardsDesktopView(
      sections: sections,
      activeTab: tab,
      onTabSelected: onTabSelected,
      onBack: _noop,
      onCreate: _noop,
      onRedeem: _noop,
    ),
  );
}

List<PaymentLinkCardsSection> _cardsSections({
  required WbLayout layout,
  required GiftCardsListContent content,
  required bool longList,
}) {
  final filler = longList
      ? [
          for (var i = 0; i < 6; i++)
            _cardRow(
              layout: layout,
              artwork: PaymentLinkCardArtwork.chestLava,
              amountText: '2.50 ZEC',
              dateText: 'July 20',
              showLinkActions: true,
            ),
        ]
      : const <Widget>[];
  final creatingSection = PaymentLinkCardsSection(
    label: kPaymentLinkCreatingSectionLabel,
    cards: [
      _cardRow(
        layout: layout,
        artwork: PaymentLinkCardArtwork.chestLava,
        amountText: '0.25 ZEC',
        dateText: 'July 2',
        statusText: kPaymentLinkFundingIncompleteStatus,
      ),
      _cardRow(
        layout: layout,
        artwork: PaymentLinkCardArtwork.dragon,
        amountText: '1.10 ZEC',
        dateText: 'July 18',
        statusText: kPaymentLinkPreparingStatus,
        showLoader: true,
      ),
    ],
  );
  final pendingSection = PaymentLinkCardsSection(
    label: kPaymentLinkPendingSectionLabel,
    cards: [
      _cardRow(
        layout: layout,
        artwork: PaymentLinkCardArtwork.ruby,
        amountText: '4.45 ZEC',
        dateText: 'August 7',
        showLinkActions: true,
      ),
      _cardRow(
        layout: layout,
        artwork: PaymentLinkCardArtwork.diamond,
        amountText: '2.50 ZEC',
        dateText: 'August 2',
        showLinkActions: true,
      ),
      ...filler,
    ],
  );
  final outcomeRows = [
    _cardRow(
      layout: layout,
      artwork: PaymentLinkCardArtwork.ruby,
      amountText: '0.10 ZEC',
      dateText: 'September 9',
      statusText: 'Checking result',
      actionLabel: 'Check status',
      showLoader: true,
    ),
    _cardRow(
      layout: layout,
      artwork: PaymentLinkCardArtwork.gift,
      amountText: '0.50 ZEC',
      dateText: 'September 7',
      statusText: 'Claim failed',
      actionLabel: 'Check status',
    ),
    _cardRow(
      layout: layout,
      artwork: PaymentLinkCardArtwork.diamond,
      amountText: '1.00 ZEC',
      dateText: 'September 4',
      statusText: 'No balance',
      actionLabel: 'Check status',
    ),
  ];
  return switch (content) {
    GiftCardsListContent.empty => const [],
    GiftCardsListContent.creating => [creatingSection],
    GiftCardsListContent.pending => [creatingSection, pendingSection],
    GiftCardsListContent.claimOutcomes => [
      PaymentLinkCardsSection(
        label: kPaymentLinkReceivedTabLabel,
        cards: [...outcomeRows, ...filler],
      ),
    ],
    GiftCardsListContent.archiveCollapsed ||
    GiftCardsListContent.archiveExpanded => [
      PaymentLinkCardsSection(
        label: kPaymentLinkReceivedTabLabel,
        cards: [outcomeRows.first, ...filler],
      ),
      PaymentLinkCardsSection(
        label: 'Archived',
        header: PaymentLinkArchiveHeader(
          count: 2,
          expanded: content == GiftCardsListContent.archiveExpanded,
          onToggle: _noop,
        ),
        cards: content == GiftCardsListContent.archiveExpanded
            ? outcomeRows.sublist(1)
            : const [],
      ),
    ],
  };
}

Widget _cardRow({
  required WbLayout layout,
  required PaymentLinkCardArtwork artwork,
  required String amountText,
  required String dateText,
  String? statusText,
  String? actionLabel,
  bool showLoader = false,
  bool showLinkActions = false,
}) {
  final thumbnail = Image.asset(
    artwork.assetPath,
    fit: BoxFit.cover,
    excludeFromSemantics: true,
  );
  if (layout == WbLayout.mobile) {
    return PaymentLinkCardListMobileRow(
      thumbnail: thumbnail,
      amountText: amountText,
      dateText: dateText,
      statusText: statusText,
      actionLabel: actionLabel,
      onAction: actionLabel == null ? null : _noop,
      showLoader: showLoader,
      showLinkActions: showLinkActions,
      onCopyLink: showLinkActions ? _noop : null,
      onShowQr: showLinkActions ? _noop : null,
    );
  }
  return PaymentLinkCardListRow(
    thumbnail: thumbnail,
    amountText: amountText,
    dateText: dateText,
    statusText: statusText,
    actionLabel: actionLabel,
    onAction: actionLabel == null ? null : _noop,
    showLoader: showLoader,
    showLinkActions: showLinkActions,
    onCopyLink: showLinkActions ? _noop : null,
    onShowQr: showLinkActions ? _noop : null,
  );
}

// --- Redeem entry ----------------------------------------------------------

enum GiftCardsRedeemStage { paste, checking, invalid }

Widget giftCardsRedeemFixture({
  required WbLayout layout,
  required GiftCardsRedeemStage stage,
  bool retryLabel = false,
  bool busy = false,
  bool fromQrCode = false,
  bool longSyncWarning = false,
}) {
  final pasteLabel = retryLabel ? 'Try again' : kPaymentLinkPasteLabel;
  final onPaste = busy ? null : _noop;
  final onClear = busy ? null : _noop;
  final view = layout == WbLayout.mobile
      ? PaymentLinkRedeemMobileView(
          state: switch (stage) {
            GiftCardsRedeemStage.paste => PaymentLinkRedeemMobileState.paste,
            GiftCardsRedeemStage.checking =>
              PaymentLinkRedeemMobileState.loading,
            GiftCardsRedeemStage.invalid =>
              PaymentLinkRedeemMobileState.invalid,
          },
          onBack: _noop,
          onPaste: onPaste,
          onScan: busy ? null : _noop,
          onClearClipboard: onClear,
          pasteLabel: pasteLabel,
          fromQrCode: fromQrCode,
        )
      : PaymentLinkRedeemDesktopView(
          state: switch (stage) {
            GiftCardsRedeemStage.paste => PaymentLinkRedeemVisualState.paste,
            GiftCardsRedeemStage.checking =>
              PaymentLinkRedeemVisualState.loading,
            GiftCardsRedeemStage.invalid =>
              PaymentLinkRedeemVisualState.invalid,
          },
          onBack: _noop,
          onPaste: onPaste,
          onClearClipboard: onClear,
          pasteLabel: pasteLabel,
        );
  if (!longSyncWarning) return _frame(layout: layout, child: view);
  return _frame(
    layout: layout,
    child: layout == WbLayout.mobile
        ? MobileModalOverlay(
            background: view,
            child: const PaymentLinkLongSyncWarningSheet(
              onConfirm: _noop,
              onCancel: _noop,
            ),
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              view,
              const PaymentLinkLongSyncWarningModal(
                onConfirm: _noop,
                onCancel: _noop,
              ),
            ],
          ),
  );
}

// --- Shared plumbing -------------------------------------------------------

double _cardWidth(WbLayout layout) => layout == WbLayout.mobile
    ? kPaymentLinkMobileCardWidth
    : PaymentLinkGiftCard.width;

double _cardHeight(WbLayout layout) => layout == WbLayout.mobile
    ? kPaymentLinkMobileCardHeight
    : PaymentLinkGiftCard.height;

Widget _selectorRail(WbLayout layout) {
  if (layout == WbLayout.desktop) {
    return PaymentLinkCardSelectorRail(
      artworks: PaymentLinkCardArtwork.values,
      selected: _desktopArtwork,
      onSelected: _ignoreArtwork,
    );
  }
  return PaymentLinkCardSelectorRail(
    artworks: PaymentLinkCardArtwork.values,
    selected: _wizardArtwork,
    width: kWbPhoneSize.width,
    itemWidth: 80,
    itemHeight: 60,
    artworkWidth: 76,
    artworkHeight: 56,
    edgeMaskInset: AppSpacing.sm,
    edgeFadeFraction: 0.3,
    inactiveOpacity: 1,
    onSelected: _ignoreArtwork,
  );
}

/// Desktop uses the shared pane frame; mobile keeps the fixtures' 773pt stage
/// under the status bar so these cases line up with the registered ones.
Widget _frame({
  required WbLayout layout,
  required Widget child,
  bool keyboardOpen = false,
}) {
  if (layout == WbLayout.desktop) return WbFrame(layout: layout, child: child);
  return WbFrame(
    layout: layout,
    child: _PhoneStage(keyboardOpen: keyboardOpen, child: child),
  );
}

class _PhoneStage extends StatelessWidget {
  const _PhoneStage({required this.child, this.keyboardOpen = false});

  final Widget child;
  final bool keyboardOpen;

  @override
  Widget build(BuildContext context) {
    // The keyboard takes height from the body, which is what the mobile views
    // react to (they scroll below their minimum stage height).
    final height = keyboardOpen
        ? _phoneStageHeight - _phoneKeyboardInset
        : _phoneStageHeight;
    final size = Size(kWbPhoneSize.width, height);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: kWbPhoneStatusBarInset),
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: size),
            child: child,
          ),
        ),
      ),
    );
  }
}

Widget _reduceMotion(bool reduced, Widget child) {
  if (!reduced) return child;
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child,
    ),
  );
}

Widget _textScale(bool large, Widget child) {
  if (!large) return child;
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: child,
    ),
  );
}

void _noop() {}
void _ignoreArtwork(PaymentLinkCardArtwork _) {}
void _ignoreStep(int _) {}
void _ignoreTab(PaymentLinkCardsTab _) {}

// --- Gift cards home > How it works ----------------------------------------

Widget giftCardsHowItWorksFixture({
  required WbLayout layout,
  bool overHome = false,
}) {
  if (layout == WbLayout.mobile) {
    return WbFrame(
      layout: layout,
      child: Builder(
        builder: (context) => MobileModalOverlay(
          background: overHome ? _mobileHomeView() : const SizedBox.expand(),
          child: PaymentLinkHowItWorksMobileSheet(
            onClose: () => Navigator.maybePop(context),
          ),
        ),
      ),
    );
  }
  return WbFrame(
    layout: layout,
    child: Builder(
      builder: (context) => PaymentLinkHowItWorksDesktopView(
        background: overHome ? _desktopHomeView() : const SizedBox.expand(),
        onClose: () => Navigator.maybePop(context),
      ),
    ),
  );
}

Widget _emptyCardIllustration({double? width, double? height}) {
  return Image.asset(
    'assets/illustrations/payment_links/payment_link_empty_card.png',
    width: width,
    height: height,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

Widget _desktopHomeView() {
  return PaymentLinksHomeDesktopView(
    illustration: _emptyCardIllustration(width: 243, height: 162),
    onBack: _noop,
    onShowHelp: _noop,
    onCreate: _noop,
    onRedeem: _noop,
  );
}

Widget _mobileHomeView() {
  return PaymentLinksHomeMobileView(
    illustration: _emptyCardIllustration(),
    onBack: _noop,
    onShowHelp: _noop,
    onCreate: _noop,
    onRedeem: _noop,
  );
}

// --- Share QR --------------------------------------------------------------

/// Whether a share action is live, mid-run, or blocked by another operation.
enum GiftCardsShareAction { ready, running, disabled }

/// A payload past the level-L QR capacity, so `PrettyQrView`'s errorBuilder is
/// what renders instead of a symbol.
final _oversizedQrData = 'z' * 4000;

Widget giftCardsShareQrFixture({
  required WbLayout layout,
  GiftCardsShareAction save = GiftCardsShareAction.ready,
  GiftCardsShareAction copy = GiftCardsShareAction.ready,
  bool qrFailed = false,
  PaymentLinkCardArtwork artwork = PaymentLinkCardArtwork.gift,
}) {
  final qrData = qrFailed ? _oversizedQrData : _shareLink(artwork);
  if (layout == WbLayout.mobile) {
    return WbFrame(
      layout: layout,
      child: Builder(
        builder: (context) => MobileModalOverlay(
          background: _mobileCardsListView(),
          child: PaymentLinkShareSheet(
            artwork: artwork,
            link: qrData,
            onShare: (_, _) async {},
            onShareError: _noop,
            onCopyLink: () async {},
            onClose: () => Navigator.maybePop(context),
          ),
        ),
      ),
    );
  }
  return _frame(
    layout: layout,
    child: PaymentLinkShareQrDesktopView(
      artwork: artwork,
      qrData: qrData,
      onBack: _noop,
      onSaveQr: save == GiftCardsShareAction.ready ? _noop : null,
      onCopyLink: copy == GiftCardsShareAction.ready ? _noop : null,
      saveLabel: save == GiftCardsShareAction.running
          ? 'Saving...'
          : 'Save QR code',
      copyLabel: copy == GiftCardsShareAction.running
          ? 'Copying...'
          : 'Copy link',
    ),
  );
}

String _shareLink(PaymentLinkCardArtwork artwork) {
  return VizorPaymentLink(
    network: 'main',
    address: 'u1previewgiftcardaddress',
    amountZatoshi: BigInt.from(445000000),
    mnemonic: List.filled(24, 'abandon').join(' '),
    birthdayHeight: 3000000,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 6),
    presentation: PaymentLinkPresentation(
      artworkId: artwork.protocolId,
      message: 'A Gift Card for you!',
    ),
  ).toUri().toString();
}

Widget _mobileCardsListView() {
  return PaymentLinkCardsMobileView(
    sections: _cardsSections(
      layout: WbLayout.mobile,
      content: GiftCardsListContent.pending,
      longList: false,
    ),
    activeTab: PaymentLinkCardsTab.created,
    onTabSelected: _ignoreTab,
    emptyLabel: kPaymentLinkNoCreatedCardsText,
    onBack: _noop,
    onCreate: _noop,
    onRedeem: _noop,
  );
}

// --- Claim outcome ---------------------------------------------------------

/// Whether the outcome offers the archive toggle, and in which direction.
enum GiftCardsClaimArchiveAction { none, hide, restore }

/// `PaymentLinkClaimOutcomeView` picks its redeem pane from `kAppFormFactor`,
/// so the Layout knob cannot switch it — the off-lane shows the run command.
Widget giftCardsClaimOutcomeFixture({
  required WbLayout layout,
  required PaymentLinkAvailability availability,
  bool busy = false,
  GiftCardsClaimArchiveAction archiveAction = GiftCardsClaimArchiveAction.none,
}) {
  return WbLaneOnly(
    layout: layout,
    child: _frame(
      layout: wbCompiledLaneLayout,
      child: PaymentLinkClaimOutcomeView(
        availability: availability,
        busy: busy,
        archived: archiveAction == GiftCardsClaimArchiveAction.restore,
        onBack: _noop,
        onCheck: _noop,
        onArchive: archiveAction == GiftCardsClaimArchiveAction.none
            ? null
            : _noop,
      ),
    ),
  );
}

// --- Claim account picker --------------------------------------------------

Widget giftCardsClaimAccountFixture({
  int accountCount = 3,
  bool hardwareAccount = false,
  bool selectLast = false,
}) {
  final accounts = [
    for (var i = 0; i < accountCount; i++)
      AccountInfo(
        uuid: 'gift-cards-claim-$i',
        name: hardwareAccount && i == accountCount - 1
            ? 'Keystone'
            : switch (i) {
                0 => 'Primary Vault',
                1 => 'Savings',
                2 => 'Daily',
                _ => 'Account ${i + 1}',
              },
        order: i,
        isHardware: hardwareAccount && i == accountCount - 1,
      ),
  ];
  return WbFrame(
    layout: WbLayout.mobile,
    child: Builder(
      builder: (context) => MobileModalOverlay(
        background: _mobileReceivedView(),
        child: PaymentLinkClaimAccountSheet(
          amountZatoshi: BigInt.from(445000000),
          accounts: accounts,
          activeAccountUuid: selectLast
              ? accounts.last.uuid
              : accounts.first.uuid,
          onConfirm: (_) async {},
          onConfirmed: _noop,
          onClose: () => Navigator.maybePop(context),
        ),
      ),
    ),
  );
}

Widget _mobileReceivedView() {
  return PaymentLinkReceivedMobileView(
    card: _shareCard(WbLayout.mobile),
    hasMessage: false,
    onClose: _noop,
    onClaim: _noop,
    claimLabel: 'Claim the gift',
  );
}

// --- Mobile body navigator -------------------------------------------------

/// The local pages the mobile body's nested navigator can land on. `shareQr`
/// is absent because the body renders the home page for it.
enum GiftCardsMobilePage {
  home,
  amount,
  message,
  review,
  ready,
  redeem,
  received,
}

/// How far the received card's claim wait has progressed.
enum GiftCardsClaimSession { none, waiting, availableSoon, ready }

Widget giftCardsMobileBodyFixture({
  required GiftCardsMobilePage page,
  bool hasCards = false,
  bool keystoneOverlay = false,
  bool navigationLocked = false,
  GiftCardsClaimSession claimSession = GiftCardsClaimSession.ready,
  bool pendingFundingMetadata = false,
}) {
  return WbFrame(
    layout: WbLayout.mobile,
    child: _GiftCardsPreviewRouter(
      key: ValueKey((
        page,
        hasCards,
        keystoneOverlay,
        navigationLocked,
        claimSession,
        pendingFundingMetadata,
      )),
      child: _GiftCardsMobileBody(
        page: page,
        hasCards: hasCards,
        keystoneOverlay: keystoneOverlay,
        navigationLocked: navigationLocked,
        claimSession: claimSession,
        pendingFundingMetadata: pendingFundingMetadata,
      ),
    ),
  );
}

/// Owns the controllers, focus nodes and callbacks the prop-driven body needs.
class _GiftCardsMobileBody extends StatefulWidget {
  const _GiftCardsMobileBody({
    required this.page,
    required this.hasCards,
    required this.keystoneOverlay,
    required this.navigationLocked,
    required this.claimSession,
    required this.pendingFundingMetadata,
  });

  final GiftCardsMobilePage page;
  final bool hasCards;
  final bool keystoneOverlay;
  final bool navigationLocked;
  final GiftCardsClaimSession claimSession;
  final bool pendingFundingMetadata;

  @override
  State<_GiftCardsMobileBody> createState() => _GiftCardsMobileBodyState();
}

class _GiftCardsMobileBodyState extends State<_GiftCardsMobileBody> {
  final _amountController = TextEditingController(text: _amount);
  final _messageController = TextEditingController(text: _message);
  final _amountFocusNode = FocusNode(debugLabel: 'GiftCardsMobileBodyAmount');
  final _messageFocusNode = FocusNode(debugLabel: 'GiftCardsMobileBodyMessage');

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    _amountFocusNode.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PaymentLinksMobileBody(
      page: switch (widget.page) {
        GiftCardsMobilePage.home => PaymentLinksLocalPage.home,
        GiftCardsMobilePage.amount => PaymentLinksLocalPage.amount,
        GiftCardsMobilePage.message => PaymentLinksLocalPage.message,
        GiftCardsMobilePage.review => PaymentLinksLocalPage.review,
        GiftCardsMobilePage.ready => PaymentLinksLocalPage.ready,
        GiftCardsMobilePage.redeem => PaymentLinksLocalPage.redeem,
        GiftCardsMobilePage.received => PaymentLinksLocalPage.received,
      },
      redeemState: PaymentLinkRedeemVisualState.paste,
      operationInProgress: false,
      redeemActionLabel: kPaymentLinkPasteLabel,
      redeemFromQrCode: false,
      keystoneOverlay: widget.keystoneOverlay
          ? const _GiftCardsKeystonePlaceholder(
              key: ValueKey('gift_cards_keystone_overlay_placeholder'),
            )
          : null,
      onCancelKeystone: _noop,
      navigationLocked: widget.navigationLocked,
      hasCards: widget.hasCards,
      cardsSections: () => _cardsSections(
        layout: WbLayout.mobile,
        content: GiftCardsListContent.pending,
        longList: false,
      ),
      activeCardsTab: PaymentLinkCardsTab.created,
      selectedArtwork: _wizardArtwork,
      amountController: _amountController,
      amountFocusNode: _amountFocusNode,
      amountInputFormatters: _amountFormatters,
      amountFiatText: _fiat,
      amountFiatLoading: false,
      maxAmountText: _maxAmount,
      canContinueAmount: true,
      amountSupportingText: null,
      amountSupportingTextIsError: false,
      messageController: _messageController,
      messageFocusNode: _messageFocusNode,
      hasMessage: true,
      messageExceedsByteLimit: false,
      fundingQuote: _giftCardsFundingQuote,
      reviewShowsBack: false,
      hasPendingFundingMetadata: widget.pendingFundingMetadata,
      readyLink: _giftCardsPreviewLink,
      readyFiatText: _fiat,
      readyCopyInProgress: false,
      fundingProgressByAddress: const {
        _giftCardsPreviewAddress: PaymentLinkFundingProgress(
          confirmationCount: 1,
        ),
      },
      readyShowsBack: false,
      receivedLink: _giftCardsPreviewLink,
      receivedFiatText: _fiat,
      receivedShowsBack: false,
      receivedClaimSession: _giftCardsClaimSession(widget.claimSession),
      linkWaitLabel: (_) => kPaymentLinkWaitingStatusLabel,
      // Derived from the session the way the screen's own estimate is, so the
      // claim wait shortens as confirmations land.
      claimWaitLabel: (session) =>
          'Wait ${kPaymentLinkClaimConfirmationTarget - session.fundingConfirmationCount}:00 to claim',
      availableSoonRemainingConfirmations: 3,
      onShowPage: _ignorePage,
      onStartCreate: _noop,
      onRunRedeemAction: _noop,
      onScanCard: _noop,
      onClearClipboard: _noop,
      onTabSelected: _ignoreTab,
      onArtworkSelected: _ignoreArtwork,
      onAmountChanged: _ignoreText,
      onUseMax: _noop,
      onMessageChanged: _ignoreText,
      onClearMessage: _noop,
      onSkipMessage: _noop,
      onReviewShowsBackChanged: _ignoreFlag,
      onCreateFundedLink: _noop,
      onRetryFundingMetadata: _noop,
      onCopyLink: _ignoreLink,
      onToggleReadyBack: _noop,
      onToggleReceivedBack: _noop,
      onAbandonReceivedPreview: _noop,
      onReceivedHome: _noop,
      onClaimReceivedLink: _noop,
    );
  }
}

/// Stands in for the hardware funding round trip the screen injects, so the
/// pushed signing page renders without the real Keystone stack.
class _GiftCardsKeystonePlaceholder extends StatelessWidget {
  const _GiftCardsKeystonePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface.card,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: colors.border.subtle),
        ),
        child: Text(
          'Keystone signing',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.primary,
          ),
        ),
      ),
    );
  }
}

PaymentLinkClaimSession? _giftCardsClaimSession(GiftCardsClaimSession stage) {
  if (stage == GiftCardsClaimSession.none) return null;
  return PaymentLinkClaimSession(
    link: _giftCardsPreviewLink,
    destinationAddress: 'u1giftcardsdestination',
    destinationAccountUuid: 'gift-cards-destination',
    // Never read: the body only looks at the session's confirmation fields.
    directory: Directory('/widgetbook'),
    dbPath: '/widgetbook/gift-card-claim.db',
    accountUuid: 'gift-cards-claim',
    totalZatoshi: BigInt.from(445000000),
    claimableZatoshi: BigInt.from(445000000),
    feeZatoshi: BigInt.from(20000),
    fundingConfirmationCount: switch (stage) {
      GiftCardsClaimSession.waiting => 0,
      GiftCardsClaimSession.availableSoon => 4,
      _ => kPaymentLinkClaimConfirmationTarget,
    },
    waitingForFundingConfirmations: stage != GiftCardsClaimSession.ready,
  );
}

const _giftCardsPreviewAddress = 'u1previewgiftcardaddress';

final _giftCardsPreviewLink = VizorPaymentLink(
  network: 'main',
  address: _giftCardsPreviewAddress,
  amountZatoshi: BigInt.from(445000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
  presentation: PaymentLinkPresentation(
    artworkId: _mobileCardArtwork.protocolId,
    message: _message,
  ),
);

final _giftCardsFundingQuote = PaymentLinkFundingQuote(
  sourceAccountUuid: 'gift-cards-source',
  recipientAmountZatoshi: BigInt.from(445000000),
  fundingFeeZatoshi: BigInt.from(20000),
  claimFeeReserveZatoshi: BigInt.from(20000),
);

class _GiftCardsPreviewRouter extends StatefulWidget {
  const _GiftCardsPreviewRouter({required this.child, super.key});
  final Widget child;

  @override
  State<_GiftCardsPreviewRouter> createState() => _GiftCardsPreviewRouterState();
}

class _GiftCardsPreviewRouterState extends State<_GiftCardsPreviewRouter> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => widget.child),
      GoRoute(path: '/home', builder: (_, _) => const Center(child: Text('Preview: /home'))),
      GoRoute(
        path: '/send/keystone/scan',
        builder: (context, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Signature scanning is unavailable in this preview.'),
              AppButton(
                onPressed: () => context.pop(),
                child: const Text('Back to QR'),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

// --- Keystone signing overlay ----------------------------------------------

/// The three phases `_PaymentLinkKeystonePhase` can rest in; broadcasting is
/// transient and only reachable from a real device response.
enum GiftCardsKeystonePhase { preparing, ready, failed }

/// Which `_friendlyError` branch the thrown preparation error lands on.
enum GiftCardsKeystoneError {
  provingParameters,
  expired,
  broadcast,
  signature,
  generic,
}

/// No `Layout` knob: the overlay picks its surface from `kAppFormFactor`
/// (desktop `KeystoneSigningModal` vs mobile `MobileKeystonePcztSigningFlow`),
/// so each lane shows its own branch.
Widget giftCardsKeystoneSigningFixture({
  required GiftCardsKeystonePhase phase,
  GiftCardsKeystoneError error = GiftCardsKeystoneError.generic,
}) {
  return ProviderScope(
    key: ValueKey((phase, error)),
    overrides: [
      paymentLinkHardwareSigningServiceProvider.overrideWithValue(
        _GiftCardsKeystoneSigningService(phase: phase, error: error),
      ),
      syncProvider.overrideWith(_GiftCardsKeystoneSyncNotifier.new),
    ],
    child: _GiftCardsPreviewRouter(
      child: WbFrame(
        layout: wbCompiledLaneLayout,
        child: PaymentLinkKeystoneSigningOverlay(
          amountZatoshi: BigInt.from(445000000),
          sourceAccountUuid: 'gift-cards-source',
          onCancel: _noop,
          onFundingBroadcast: (_, _) async {},
        ),
      ),
    ),
  );
}

/// Sync is only read for `refreshAfterProposalRelease` when the overlay
/// releases its draft, so the fixture answers it without touching Rust.
class _GiftCardsKeystoneSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {}
}

class _GiftCardsKeystoneSigningService
    implements PaymentLinkHardwareSigningService {
  const _GiftCardsKeystoneSigningService({
    required this.phase,
    required this.error,
  });

  final GiftCardsKeystonePhase phase;
  final GiftCardsKeystoneError error;

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) {
    return switch (phase) {
      // Never completes, which is what leaves the overlay on its first phase.
      GiftCardsKeystonePhase.preparing =>
        Completer<PaymentLinkHardwarePcztDraft>().future,
      GiftCardsKeystonePhase.failed => Future.error(
        StateError(_giftCardsKeystoneErrorMessage(error)),
      ),
      GiftCardsKeystonePhase.ready => Future.value(
        PaymentLinkHardwarePcztDraft(
          link: _giftCardsPreviewLink,
          pcztBytes: const [1, 2, 3],
          needsSaplingParams: false,
          feeZatoshi: BigInt.from(20000),
          proposalId: BigInt.one,
          sendFlowId: 'gift-cards-widgetbook',
        ),
      ),
    };
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async => _giftCardsKeystoneUrParts;

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => const [1, 2, 3];

  @override
  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async => const [4, 5, 6];

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {}

  @override
  Future<PaymentLinkHardwareFundingResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
    FutureOr<void> Function()? onSubmissionStarted,
  }) async {
    await onSubmissionStarted?.call();
    return const PaymentLinkHardwareFundingResult(
      txids: 'widgetbook-txid',
      status: 'broadcasted',
      fundingMetadataSaved: true,
    );
  }
}

/// The overlay derives its copy from the thrown message, so the fixture throws
/// a message rather than hard-coding the user-facing string.
String _giftCardsKeystoneErrorMessage(GiftCardsKeystoneError error) {
  return switch (error) {
    GiftCardsKeystoneError.provingParameters =>
      'Sapling parameters are unavailable.',
    GiftCardsKeystoneError.expired => 'Proposal not found.',
    GiftCardsKeystoneError.broadcast => 'Broadcast was refused by the node.',
    GiftCardsKeystoneError.signature =>
      'Keystone signature bytes were rejected.',
    GiftCardsKeystoneError.generic => 'The device returned nothing usable.',
  };
}

final _giftCardsKeystoneUrParts = [
  for (var i = 1; i <= 12; i++)
    'ur:zcash-pczt/$i-12/lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcx'
        'hdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcx'
        '${i.toString().padLeft(2, '0')}',
];

void _ignorePage(PaymentLinksLocalPage _) {}
void _ignoreText(String _) {}
void _ignoreFlag(bool _) {}
void _ignoreLink(VizorPaymentLink _) {}

// --- Components: card list row ---------------------------------------------

/// What the row shows on its trailing edge. `showLinkActions` wins over
/// `showLoader`, which wins over `showCopyIcon`, so this stays one axis.
enum GiftCardsRowTrailing { linkActions, copyIcon, loader, none }

/// Status vocabulary a created or received row carries.
enum GiftCardsRowStatus {
  preparing,
  noBalance,
  alreadyClaimed,
  checkingResult,
  claimFailed,
  receiving,
  received,
}

/// The action the received row offers next to its status.
enum GiftCardsRowAction { none, checkStatus, viewCard }

/// The mobile row has no copy-icon slot, so that trailing is desktop-only.
List<GiftCardsRowTrailing> giftCardsRowTrailingOptions(WbLayout layout) {
  return layout == WbLayout.desktop
      ? GiftCardsRowTrailing.values
      : const [
          GiftCardsRowTrailing.linkActions,
          GiftCardsRowTrailing.loader,
          GiftCardsRowTrailing.none,
        ];
}

String giftCardsRowStatusText(GiftCardsRowStatus status) {
  return switch (status) {
    GiftCardsRowStatus.preparing => kPaymentLinkPreparingStatus,
    GiftCardsRowStatus.noBalance => PaymentLinkAvailability.noBalance.label,
    GiftCardsRowStatus.alreadyClaimed =>
      PaymentLinkAvailability.claimedElsewhere.label,
    GiftCardsRowStatus.checkingResult => PaymentLinkAvailability.checking.label,
    GiftCardsRowStatus.claimFailed => PaymentLinkAvailability.failed.label,
    GiftCardsRowStatus.receiving => 'Receiving...',
    GiftCardsRowStatus.received => 'Received',
  };
}

String? giftCardsRowActionLabel(GiftCardsRowAction action) {
  return switch (action) {
    GiftCardsRowAction.none => null,
    GiftCardsRowAction.checkStatus => 'Check status',
    GiftCardsRowAction.viewCard => 'View card',
  };
}

Widget giftCardsCardRowFixture({
  required WbLayout layout,
  GiftCardsRowTrailing trailing = GiftCardsRowTrailing.linkActions,
  GiftCardsRowStatus status = GiftCardsRowStatus.preparing,
  GiftCardsRowAction action = GiftCardsRowAction.none,
  bool secondaryAction = false,
  bool enabled = true,
}) {
  final mobile = layout == WbLayout.mobile;
  final showLinkActions = trailing == GiftCardsRowTrailing.linkActions;
  final actionLabel = giftCardsRowActionLabel(action);
  final statusText = giftCardsRowStatusText(status);
  final onAction = enabled && actionLabel != null ? _noop : null;
  final thumbnail = Image.asset(
    _componentArtwork.assetPath,
    fit: BoxFit.cover,
    excludeFromSemantics: true,
  );
  final Widget row = mobile
      ? PaymentLinkCardListMobileRow(
          thumbnail: thumbnail,
          amountText: '4.45 ZEC',
          dateText: 'August 7',
          statusText: statusText,
          actionLabel: actionLabel,
          onAction: onAction,
          showLoader: trailing == GiftCardsRowTrailing.loader,
          showLinkActions: showLinkActions,
          onCopyLink: showLinkActions && enabled ? _noop : null,
          onShowQr: showLinkActions && enabled ? _noop : null,
        )
      : PaymentLinkCardListRow(
          thumbnail: thumbnail,
          amountText: '4.45 ZEC',
          dateText: 'August 7',
          statusText: statusText,
          actionLabel: actionLabel,
          onAction: onAction,
          showCopyIcon: trailing == GiftCardsRowTrailing.copyIcon,
          showLoader: trailing == GiftCardsRowTrailing.loader,
          showLinkActions: showLinkActions,
          onCopyLink: showLinkActions && enabled ? _noop : null,
          onShowQr: showLinkActions && enabled ? _noop : null,
          secondaryActionText: secondaryAction ? 'Hide card' : null,
          onSecondaryAction: secondaryAction && enabled ? _noop : null,
        );
  return WbFrame(
    layout: layout,
    child: Center(
      child: SizedBox(
        width: mobile ? kPaymentLinkMobileCardWidth : _componentRowWidth,
        child: row,
      ),
    ),
  );
}

// --- Components: gift card -------------------------------------------------

/// Which side of the flip is showing.
enum GiftCardsCardFace { front, message }

/// The three front amount states the card takes as a prop: null is the prompt,
/// an empty string is the caret, a value is the entered amount.
enum GiftCardsCardAmount { placeholder, caret, value }

enum GiftCardsCardSupporting { none, fiat, loading }

/// The Max button needs both a handler and an entered amount, so an unhandled
/// Max is not a state: the card falls back to the inline maximum.
enum GiftCardsCardMax { hidden, shown }

enum GiftCardsCardMessage { empty, written, atLimit }

Widget giftCardsGiftCardFixture({
  required WbLayout layout,
  PaymentLinkCardArtwork artwork = _componentArtwork,
  GiftCardsCardFace face = GiftCardsCardFace.front,
  GiftCardsCardAmount amount = GiftCardsCardAmount.value,
  GiftCardsCardSupporting supporting = GiftCardsCardSupporting.fiat,
  GiftCardsCardMax max = GiftCardsCardMax.shown,
  GiftCardsCardMessage message = GiftCardsCardMessage.written,
  bool deleteAction = true,
  bool reducedMotion = false,
}) {
  final width = _cardWidth(layout);
  final height = _cardHeight(layout);
  final front = PaymentLinkGiftCard(
    artwork: artwork,
    cardWidth: width,
    cardHeight: height,
    amountText: switch (amount) {
      GiftCardsCardAmount.placeholder => null,
      GiftCardsCardAmount.caret => '',
      GiftCardsCardAmount.value => _amount,
    },
    showCaret: amount == GiftCardsCardAmount.caret,
    maxAmountText: _maxAmount,
    onUseMax: _noop,
    showMaxButton: max == GiftCardsCardMax.shown,
    supportingText: supporting == GiftCardsCardSupporting.fiat ? _fiat : null,
    supportingLoading: supporting == GiftCardsCardSupporting.loading,
  );
  final back = PaymentLinkGiftCard(
    artwork: artwork,
    cardWidth: width,
    cardHeight: height,
    showBack: true,
    message: switch (message) {
      GiftCardsCardMessage.empty => '',
      GiftCardsCardMessage.written => _message,
      GiftCardsCardMessage.atLimit => _atLimitMessage,
    },
    messageCharacterCount: switch (message) {
      GiftCardsCardMessage.empty => null,
      GiftCardsCardMessage.written => _messageCharacterCount,
      GiftCardsCardMessage.atLimit => 0,
    },
    onDeleteMessage: deleteAction ? _noop : null,
  );
  return _reduceMotion(
    reducedMotion,
    WbFrame(
      layout: layout,
      child: Center(
        child: PaymentLinkCardFlip(
          showBack: face == GiftCardsCardFace.message,
          front: front,
          back: back,
        ),
      ),
    ),
  );
}

// --- Components: card selector ---------------------------------------------

enum GiftCardsSelectorState { unselected, selected, focused }

Widget giftCardsCardSelectorFixture({
  required WbLayout layout,
  PaymentLinkCardArtwork artwork = _componentArtwork,
  GiftCardsSelectorState state = GiftCardsSelectorState.unselected,
}) {
  final mobile = layout == WbLayout.mobile;
  final tile = PaymentLinkCardSelector(
    artwork: artwork,
    selected: state == GiftCardsSelectorState.selected,
    onSelected: _noop,
    itemWidth: mobile
        ? _mobileSelectorItemWidth
        : PaymentLinkCardSelector.width,
    itemHeight: mobile
        ? _mobileSelectorItemHeight
        : PaymentLinkCardSelector.height,
    artworkWidth: mobile ? _mobileSelectorArtworkWidth : 60,
    artworkHeight: mobile ? _mobileSelectorArtworkHeight : 44,
    // The mobile rail never dims its unselected designs.
    inactiveOpacity: mobile ? 1 : 0.5,
  );
  return WbFrame(
    layout: layout,
    child: Center(
      child: state == GiftCardsSelectorState.focused
          ? _GiftCardsFocusedAction(child: tile)
          : tile,
    ),
  );
}

// --- Components: card selector rail ----------------------------------------

/// Where the selection sits in the artwork list; the rail recenters it on
/// mount and clamps at both ends.
enum GiftCardsRailSelection { first, middle, last }

Widget giftCardsSelectorRailFixture({
  required WbLayout layout,
  GiftCardsRailSelection selection = GiftCardsRailSelection.middle,
  bool reducedMotion = false,
}) {
  const artworks = PaymentLinkCardArtwork.values;
  final selected = switch (selection) {
    GiftCardsRailSelection.first => artworks.first,
    GiftCardsRailSelection.middle => artworks[artworks.length ~/ 2],
    GiftCardsRailSelection.last => artworks.last,
  };
  final rail = layout == WbLayout.desktop
      ? PaymentLinkCardSelectorRail(
          artworks: artworks,
          selected: selected,
          onSelected: _ignoreArtwork,
        )
      : PaymentLinkCardSelectorRail(
          artworks: artworks,
          selected: selected,
          width: kWbPhoneSize.width,
          itemWidth: _mobileSelectorItemWidth,
          itemHeight: _mobileSelectorItemHeight,
          artworkWidth: _mobileSelectorArtworkWidth,
          artworkHeight: _mobileSelectorArtworkHeight,
          edgeMaskInset: AppSpacing.sm,
          edgeFadeFraction: 0.3,
          inactiveOpacity: 1,
          onSelected: _ignoreArtwork,
        );
  return _reduceMotion(
    reducedMotion,
    WbFrame(
      layout: layout,
      child: Center(child: rail),
    ),
  );
}

// --- Components: QR share card ---------------------------------------------

/// The composite is a fixed 396×270 export rather than a screen, so it is
/// framed on the desktop pane in both lanes instead of carrying a layout knob.
Widget giftCardsQrShareCardFixture({
  PaymentLinkCardArtwork artwork = PaymentLinkCardArtwork.gift,
  bool qrFailed = false,
}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: PaymentLinkQrShareCard(
        artwork: artwork,
        qrData: qrFailed ? _oversizedQrData : _shareLink(artwork),
      ),
    ),
  );
}

// --- Components: action shell ----------------------------------------------

enum GiftCardsActionState { idle, focused, disabled }

enum GiftCardsActionSlots { labelOnly, leadingIcon, trailingIcon }

/// No layout knob: the action shell is one widget in both form factors.
Widget giftCardsActionShellFixture({
  GiftCardsActionState state = GiftCardsActionState.idle,
  GiftCardsActionSlots slots = GiftCardsActionSlots.labelOnly,
}) {
  final action = PaymentLinkTextAction(
    label: 'Copy link',
    onTap: _noop,
    enabled: state != GiftCardsActionState.disabled,
    leading: slots == GiftCardsActionSlots.leadingIcon
        ? const AppIcon(AppIcons.copy, size: 16)
        : null,
    trailing: slots == GiftCardsActionSlots.trailingIcon
        ? const AppIcon(AppIcons.chevronForward, size: 16)
        : null,
  );
  return WbFrame(
    layout: wbCompiledLaneLayout,
    child: Center(
      child: state == GiftCardsActionState.focused
          ? _GiftCardsFocusedAction(child: action)
          : action,
    ),
  );
}

// --- Components: archive header --------------------------------------------

/// No layout knob: the archive header is one widget in both form factors.
Widget giftCardsArchiveHeaderFixture({
  int count = 3,
  bool expanded = false,
  bool focused = false,
}) {
  final header = PaymentLinkArchiveHeader(
    count: count,
    expanded: expanded,
    onToggle: _noop,
  );
  return WbFrame(
    layout: wbCompiledLaneLayout,
    child: Center(
      child: SizedBox(
        width: _componentRowWidth,
        child: focused ? _GiftCardsFocusedAction(child: header) : header,
      ),
    ),
  );
}

// --- Components: wizard stepper --------------------------------------------

/// Whether the stepper takes taps, is frozen by a running operation, or shows
/// its focus ring.
enum GiftCardsStepperInteraction { interactive, busy, focused }

/// No layout knob: the wizard stepper is desktop chrome.
Widget giftCardsWizardStepperFixture({
  int currentStep = 0,
  GiftCardsStepperInteraction interaction =
      GiftCardsStepperInteraction.interactive,
}) {
  final stepper = PaymentLinkWizardStepper(
    currentStep: currentStep,
    onStepSelected: interaction == GiftCardsStepperInteraction.busy
        ? null
        : _ignoreStep,
  );
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: interaction == GiftCardsStepperInteraction.focused
          ? _GiftCardsFocusedAction(child: stepper)
          : stepper,
    ),
  );
}

// --- Component plumbing ----------------------------------------------------

const _componentArtwork = PaymentLinkCardArtwork.ruby;
const _componentRowWidth = 480.0;
const _mobileSelectorItemWidth = 80.0;
const _mobileSelectorItemHeight = 60.0;
const _mobileSelectorArtworkWidth = 76.0;
const _mobileSelectorArtworkHeight = 56.0;

/// A 128-character message, so the back face shows its character-count limit.
const _atLimitMessage =
    'Happy birthday! Happy birthday! Happy birthday! Happy birthday! '
    'Happy birthday! Happy birthday! Happy birthday! Happy birthday! ';

/// Renders the focus ring of a `PaymentLinkAction` without a key press: the
/// first focusable descendant takes focus on the first frame, and the
/// traditional highlight is forced because the ring is otherwise suppressed on
/// a touch-highlight host.
class _GiftCardsFocusedAction extends StatefulWidget {
  const _GiftCardsFocusedAction({required this.child});

  final Widget child;

  @override
  State<_GiftCardsFocusedAction> createState() =>
      _GiftCardsFocusedActionState();
}

/// Refcount over the process-wide highlight strategy: a knob change mounts the
/// next focused fixture before the previous one is disposed, so a plain
/// save/restore pair would leak the forced value into the running widgetbook.
int _focusHighlightHolders = 0;
FocusHighlightStrategy? _focusHighlightRestore;

class _GiftCardsFocusedActionState extends State<_GiftCardsFocusedAction> {
  final _scope = FocusScopeNode(debugLabel: 'GiftCardsFocusedAction');

  @override
  void initState() {
    super.initState();
    if (_focusHighlightHolders++ == 0) {
      _focusHighlightRestore = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scope.requestFocus();
      _scope.nextFocus();
    });
  }

  @override
  void dispose() {
    if (--_focusHighlightHolders == 0) {
      FocusManager.instance.highlightStrategy =
          _focusHighlightRestore ?? FocusHighlightStrategy.automatic;
      _focusHighlightRestore = null;
    }
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _scope, child: widget.child);
}
