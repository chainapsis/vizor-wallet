/// The mobile Gift Card render tree.
///
/// It is the whole mobile side of `payment_links_screen.dart`, which
/// owns the state machine for both form factors. Every value and callback it
/// needs arrives as a constructor argument, so the widget reads as the explicit
/// contract between the state machine and the mobile surface, and the screen
/// file is left with the state machine plus one render tree instead of two.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../models/vizor_payment_link.dart';
import '../services/payment_link_service.dart';
import '../widgets/mobile/payment_link_mobile_views.dart';
import '../widgets/payment_link_card_flip.dart';
import '../widgets/payment_link_card_selector_rail.dart';
import '../widgets/payment_link_confetti.dart';
import '../widgets/payment_link_copy.dart';
import '../widgets/payment_link_desktop_views.dart';
import '../widgets/payment_link_gift_card.dart';
import 'payment_links_local_page.dart';

class PaymentLinksMobileBody extends StatelessWidget {
  const PaymentLinksMobileBody({
    required this.page,
    required this.redeemState,
    required this.operationInProgress,
    required this.redeemActionLabel,
    required this.keystoneOverlay,
    required this.hasCards,
    required this.cardsSections,
    required this.activeCardsTab,
    required this.selectedArtwork,
    required this.amountController,
    required this.amountFocusNode,
    required this.amountInputFormatters,
    required this.maxAmountText,
    required this.canContinueAmount,
    required this.amountSupportingText,
    required this.amountSupportingTextIsError,
    required this.messageController,
    required this.messageFocusNode,
    required this.hasMessage,
    required this.messageExceedsByteLimit,
    required this.fundingQuote,
    required this.reviewShowsBack,
    required this.hasPendingFundingMetadata,
    required this.readyLink,
    required this.fundingProgressByAddress,
    required this.readyShowsBack,
    required this.receivedLink,
    required this.receivedShowsBack,
    required this.receivedClaimSession,
    required this.linkWaitLabel,
    required this.claimWaitLabel,
    required this.availableSoonRemainingConfirmations,
    required this.onShowPage,
    required this.onStartCreate,
    required this.onRunRedeemAction,
    required this.onClearClipboard,
    required this.onTabSelected,
    required this.onArtworkSelected,
    required this.onAmountChanged,
    required this.onUseMax,
    required this.onMessageChanged,
    required this.onClearMessage,
    required this.onSkipMessage,
    required this.onReviewShowsBackChanged,
    required this.onCreateFundedLink,
    required this.onRetryFundingMetadata,
    required this.onCopyLink,
    required this.onToggleReadyBack,
    required this.onToggleReceivedBack,
    required this.onLeavePendingClaim,
    required this.onClaimReceivedLink,
    super.key,
  });

  final PaymentLinksLocalPage page;
  final PaymentLinkRedeemVisualState redeemState;
  final bool operationInProgress;
  final String redeemActionLabel;

  /// The hardware funding round trip, already built by the screen. A hardware
  /// account funds its Card through the same Keystone handoff the desktop pane
  /// runs; without this overlay the mobile review CTA would sit on
  /// "Creating..." forever.
  final Widget? keystoneOverlay;

  /// Whether any created or received Card exists, which is what decides the
  /// home page between the empty landing surface and the cards list.
  final bool hasCards;

  /// Built lazily so the rows are only constructed on the pages that show
  /// them, exactly as the screen's own home page does.
  final ValueGetter<List<PaymentLinkCardsSection>> cardsSections;
  final PaymentLinkCardsTab activeCardsTab;

  final PaymentLinkCardArtwork selectedArtwork;
  final TextEditingController amountController;
  final FocusNode amountFocusNode;
  final List<TextInputFormatter> amountInputFormatters;
  final String? maxAmountText;
  final bool canContinueAmount;
  final String? amountSupportingText;
  final bool amountSupportingTextIsError;

  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final bool hasMessage;
  final bool messageExceedsByteLimit;

  final PaymentLinkFundingQuote? fundingQuote;
  final bool reviewShowsBack;
  final bool hasPendingFundingMetadata;

  final VizorPaymentLink? readyLink;
  final Map<String, PaymentLinkFundingProgress> fundingProgressByAddress;
  final bool readyShowsBack;

  final VizorPaymentLink? receivedLink;
  final bool receivedShowsBack;
  final PaymentLinkClaimSession? receivedClaimSession;

  final String Function(PaymentLinkFundingProgress progress) linkWaitLabel;
  final String Function(PaymentLinkClaimSession session) claimWaitLabel;
  final int availableSoonRemainingConfirmations;

  final ValueChanged<PaymentLinksLocalPage> onShowPage;
  final VoidCallback onStartCreate;
  final VoidCallback onRunRedeemAction;
  final VoidCallback onClearClipboard;
  final ValueChanged<PaymentLinkCardsTab> onTabSelected;
  final ValueChanged<PaymentLinkCardArtwork> onArtworkSelected;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onUseMax;
  final ValueChanged<String> onMessageChanged;
  final VoidCallback onClearMessage;
  final VoidCallback onSkipMessage;
  final ValueChanged<bool> onReviewShowsBackChanged;
  final VoidCallback onCreateFundedLink;
  final VoidCallback onRetryFundingMetadata;
  final ValueChanged<VizorPaymentLink> onCopyLink;
  final VoidCallback onToggleReadyBack;
  final VoidCallback onToggleReceivedBack;
  final VoidCallback onLeavePendingClaim;
  final VoidCallback onClaimReceivedLink;

  @override
  Widget build(BuildContext context) {
    final currentPage = switch (page) {
      PaymentLinksLocalPage.home => _buildHome(context),
      PaymentLinksLocalPage.amount => _buildAmount(),
      PaymentLinksLocalPage.message => _buildMessage(),
      PaymentLinksLocalPage.review => _buildReview(),
      PaymentLinksLocalPage.ready => _buildReady(context),
      PaymentLinksLocalPage.shareQr => _buildHome(context),
      PaymentLinksLocalPage.redeem => PaymentLinkRedeemMobileView(
        state: PaymentLinkRedeemMobileState.values.byName(redeemState.name),
        onBack: () => onShowPage(PaymentLinksLocalPage.home),
        onPaste: operationInProgress ? null : onRunRedeemAction,
        onClearClipboard: operationInProgress ? null : onClearClipboard,
        pasteLabel: redeemActionLabel,
      ),
      PaymentLinksLocalPage.received => _buildReceived(context),
    };

    final overlay = keystoneOverlay;
    final body = overlay == null
        ? currentPage
        : Stack(
            fit: StackFit.expand,
            children: [
              currentPage,
              Positioned.fill(child: overlay),
            ],
          );

    return Scaffold(
      key: const ValueKey('payment_links_mobile_screen'),
      backgroundColor: context.colors.background.window,
      body: AppToastHost(child: SafeArea(child: body)),
    );
  }

  void _leavePaymentLinks(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _returnHomeFromReceivedGift(BuildContext context) => context.go('/home');

  Widget _buildHome(BuildContext context) {
    if (hasCards) {
      return _buildCardsList(context);
    }
    return PaymentLinksHomeMobileView(
      illustration: Image.asset(
        'assets/illustrations/payment_links/payment_link_empty_card.png',
        fit: BoxFit.contain,
        semanticLabel: 'Gift box',
      ),
      onBack: () => _leavePaymentLinks(context),
      onShowHelp: () => _showHelpSheet(context),
      onCreate: onStartCreate,
      onRedeem: () => onShowPage(PaymentLinksLocalPage.redeem),
    );
  }

  Widget _buildCardsList(BuildContext context) {
    return PaymentLinkCardsMobileView(
      sections: cardsSections(),
      emptyLabel: activeCardsTab == PaymentLinkCardsTab.created
          ? kPaymentLinkNoCreatedCardsText
          : kPaymentLinkNoReceivedCardsText,
      onBack: () => _leavePaymentLinks(context),
      onCreate: onStartCreate,
      onRedeem: () => onShowPage(PaymentLinksLocalPage.redeem),
      activeTab: activeCardsTab,
      onTabSelected: onTabSelected,
    );
  }

  void _showHelpSheet(BuildContext context) {
    showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) => PaymentLinkHowItWorksMobileSheet(
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  Widget _buildAmount() {
    final maxAmount = maxAmountText;
    return PaymentLinkAmountMobileView(
      card: PaymentLinkGiftCard(
        artwork: selectedArtwork,
        cardWidth: kPaymentLinkMobileCardWidth,
        cardHeight: kPaymentLinkMobileCardHeight,
        amountController: amountController,
        amountFocusNode: amountFocusNode,
        amountEditorKey: const ValueKey('payment_link_amount_editor'),
        amountInputFormatters: amountInputFormatters,
        onAmountChanged: onAmountChanged,
        maxAmountText: maxAmount,
        onUseMax: maxAmount == null ? null : onUseMax,
        showMaxButton: true,
        semanticLabel: 'Gift card amount input',
      ),
      cardSelector: PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: selectedArtwork,
        width: 393,
        itemWidth: 80,
        itemHeight: 60,
        artworkWidth: 76,
        artworkHeight: 56,
        edgeMaskInset: AppSpacing.sm,
        edgeFadeFraction: 0.3,
        inactiveOpacity: 1,
        onSelected: onArtworkSelected,
      ),
      onBack: () => onShowPage(PaymentLinksLocalPage.home),
      onContinue: canContinueAmount
          ? () => onShowPage(PaymentLinksLocalPage.message)
          : null,
      supportingText: amountSupportingText,
      supportingTextIsError: amountSupportingTextIsError,
    );
  }

  Widget _buildMessage() {
    return PaymentLinkMessageMobileView(
      card: PaymentLinkGiftCard(
        artwork: selectedArtwork,
        cardWidth: kPaymentLinkMobileCardWidth,
        cardHeight: kPaymentLinkMobileCardHeight,
        showBack: true,
        messageController: messageController,
        messageFocusNode: messageFocusNode,
        messageEditorKey: const ValueKey('payment_link_message_editor'),
        messageInputFormatters: [
          LengthLimitingTextInputFormatter(
            PaymentLinkPresentation.maxMessageCharacters,
          ),
        ],
        onMessageChanged: onMessageChanged,
        onDeleteMessage: hasMessage ? onClearMessage : null,
        semanticLabel: 'Gift card message input',
      ),
      onBack: () => onShowPage(PaymentLinksLocalPage.amount),
      onSkip: onSkipMessage,
      onContinue: hasMessage && !messageExceedsByteLimit
          ? () => onShowPage(PaymentLinksLocalPage.review)
          : null,
      errorText: messageExceedsByteLimit
          ? kPaymentLinkMessageTooLargeText
          : null,
    );
  }

  Widget _buildReview() {
    final quote = fundingQuote!;
    final message = messageController.text.trim();
    final front = PaymentLinkGiftCard(
      artwork: selectedArtwork,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
      amountText: amountController.text,
      showCaret: false,
      onTap: message.isEmpty ? null : () => onReviewShowsBackChanged(true),
      semanticLabel: message.isEmpty ? null : 'Reveal gift card message',
    );
    final card = message.isEmpty
        ? front
        : PaymentLinkCardFlip(
            showBack: reviewShowsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: selectedArtwork,
              cardWidth: kPaymentLinkMobileCardWidth,
              cardHeight: kPaymentLinkMobileCardHeight,
              showBack: true,
              message: message,
              onTap: () => onReviewShowsBackChanged(false),
              semanticLabel: 'Show gift card front',
            ),
          );
    return PaymentLinkReviewMobileView(
      card: card,
      onBack: () => onShowPage(PaymentLinksLocalPage.message),
      cardAmountText: '${formatZecAmount(quote.recipientAmountZatoshi)} ZEC',
      cardFeeText: '${formatZecAmount(quote.cardFeeZatoshi)} ZEC',
      totalAmountText: '${formatZecAmount(quote.totalDeductedZatoshi)} ZEC',
      onContinue: operationInProgress
          ? null
          : !hasPendingFundingMetadata
          ? onCreateFundedLink
          : onRetryFundingMetadata,
      onFeeHelp: () {},
      continueLabel: operationInProgress
          ? !hasPendingFundingMetadata
                ? 'Creating...'
                : 'Saving...'
          : !hasPendingFundingMetadata
          ? 'Approve & create'
          : 'Try saving again',
    );
  }

  Widget _buildReady(BuildContext context) {
    final link = readyLink;
    if (link == null) return _buildHome(context);
    final artwork = PaymentLinkCardArtwork.fromProtocolId(
      link.presentation?.artworkId,
    );
    final message = link.presentation?.message ?? '';
    final progress =
        fundingProgressByAddress[link.address] ??
        const PaymentLinkFundingProgress(confirmationCount: 0);
    final remaining = progress.confirmationTarget - progress.confirmationCount;
    final ready = progress.isReady;
    final soon =
        progress.confirmationCount > 0 &&
        remaining <= availableSoonRemainingConfirmations;
    final front = PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
      amountText: formatZecAmount(link.amountZatoshi),
      showCaret: false,
    );
    final card = message.isEmpty
        ? front
        : PaymentLinkCardFlip(
            showBack: readyShowsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: artwork,
              cardWidth: kPaymentLinkMobileCardWidth,
              cardHeight: kPaymentLinkMobileCardHeight,
              showBack: true,
              message: message,
            ),
          );
    return PaymentLinkReadyMobileView(
      state: ready
          ? PaymentLinkReadyMobileState.ready
          : soon
          ? PaymentLinkReadyMobileState.soon
          : PaymentLinkReadyMobileState.waiting,
      card: card,
      decoration: ready || progress.confirmationCount == 0
          ? const PaymentLinkConfetti()
          : null,
      onHome: () => onShowPage(PaymentLinksLocalPage.home),
      onCopy: ready && !operationInProgress ? () => onCopyLink(link) : null,
      onCardTap: ready && message.isNotEmpty ? onToggleReadyBack : null,
      waitingStatusLabel: linkWaitLabel(progress),
      copyLabel: operationInProgress ? 'Copying...' : 'Copy link',
    );
  }

  Widget _buildReceived(BuildContext context) {
    final link = receivedLink;
    if (link == null) {
      return PaymentLinkRedeemMobileView(
        state: PaymentLinkRedeemMobileState.paste,
        onBack: () => _leavePaymentLinks(context),
        onPaste: operationInProgress ? null : onRunRedeemAction,
        onClearClipboard: operationInProgress ? null : onClearClipboard,
        pasteLabel: redeemActionLabel,
      );
    }
    final artwork = PaymentLinkCardArtwork.fromProtocolId(
      link.presentation?.artworkId,
    );
    final message = link.presentation?.message ?? '';
    final hasCardMessage = message.isNotEmpty;
    final front = PaymentLinkGiftCard(
      artwork: artwork,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
      amountText: formatZecAmount(link.amountZatoshi),
      showCaret: false,
    );
    final card = hasCardMessage
        ? PaymentLinkCardFlip(
            showBack: receivedShowsBack,
            front: front,
            back: PaymentLinkGiftCard(
              artwork: artwork,
              cardWidth: kPaymentLinkMobileCardWidth,
              cardHeight: kPaymentLinkMobileCardHeight,
              showBack: true,
              message: message,
            ),
          )
        : front;
    final session = receivedClaimSession;
    if (session?.waitingForFundingConfirmations ?? false) {
      final remaining =
          kPaymentLinkClaimConfirmationTarget -
          session!.fundingConfirmationCount;
      return PaymentLinkReadyMobileView(
        state:
            session.fundingConfirmationCount > 0 &&
                remaining <= availableSoonRemainingConfirmations
            ? PaymentLinkReadyMobileState.soon
            : PaymentLinkReadyMobileState.waiting,
        card: card,
        cardTop: kPaymentLinkMobileReceivedCardTop,
        onHome: onLeavePendingClaim,
        waitingHeading: 'Your Gift Card\nis almost ready!',
        waitingDescription:
            'Waiting for 6 confirmations. Vizor will keep checking, and you '
            'can claim the card as soon as the funds are ready.',
        waitingIcon: AppIcons.time,
        waitingStatusLabel: claimWaitLabel(session),
        homeLabel: 'Go home',
      );
    }
    return PaymentLinkReceivedMobileView(
      card: card,
      hasMessage: hasCardMessage,
      onClose: () => _returnHomeFromReceivedGift(context),
      decoration: const PaymentLinkConfetti(),
      onRevealMessage: hasCardMessage ? onToggleReceivedBack : null,
      onClaim: operationInProgress ? null : onClaimReceivedLink,
      claimLabel: operationInProgress ? 'Claiming...' : 'Claim the gift',
    );
  }
}
