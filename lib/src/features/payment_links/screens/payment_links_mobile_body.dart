/// The mobile Gift Card render tree.
///
/// It is the whole mobile side of `payment_links_screen.dart`, which
/// owns the state machine for both form factors. Every value and callback it
/// needs arrives as a constructor argument, so the widget reads as the explicit
/// contract between the state machine and the mobile surface, and the screen
/// file is left with the state machine plus one render tree instead of two.
library;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
    this.claimOutcome,
    required this.operationInProgress,
    required this.redeemActionLabel,
    required this.redeemFromQrCode,
    required this.keystoneOverlay,
    required this.onCancelKeystone,
    required this.navigationLocked,
    required this.hasCards,
    required this.cardsSections,
    required this.activeCardsTab,
    required this.selectedArtwork,
    required this.amountController,
    required this.amountFocusNode,
    required this.amountInputFormatters,
    required this.amountFiatText,
    required this.amountFiatLoading,
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
    required this.readyFiatText,
    required this.readyCopyInProgress,
    required this.fundingProgressByAddress,
    required this.readyShowsBack,
    required this.receivedLink,
    required this.receivedFiatText,
    required this.receivedShowsBack,
    required this.receivedClaimSession,
    required this.linkWaitLabel,
    required this.claimWaitLabel,
    required this.availableSoonRemainingConfirmations,
    required this.onShowPage,
    required this.onStartCreate,
    required this.onRunRedeemAction,
    required this.onScanCard,
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
    required this.onAbandonReceivedPreview,
    required this.onReceivedHome,
    required this.onClaimReceivedLink,
    super.key,
  });

  final PaymentLinksLocalPage page;
  final PaymentLinkRedeemVisualState redeemState;
  final Widget? claimOutcome;
  final bool operationInProgress;
  final String redeemActionLabel;
  final bool redeemFromQrCode;

  /// The hardware funding round trip, already built by the screen. A hardware
  /// account funds its Card through the same Keystone handoff the desktop pane
  /// runs; without this overlay the mobile review CTA would sit on
  /// "Creating..." forever.
  final Widget? keystoneOverlay;
  final VoidCallback onCancelKeystone;
  final bool navigationLocked;

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
  final String? amountFiatText;
  final bool amountFiatLoading;
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
  final String? readyFiatText;
  final bool readyCopyInProgress;
  final Map<String, PaymentLinkFundingProgress> fundingProgressByAddress;
  final bool readyShowsBack;

  final VizorPaymentLink? receivedLink;
  final String? receivedFiatText;
  final bool receivedShowsBack;
  final PaymentLinkClaimSession? receivedClaimSession;

  final String Function(PaymentLinkFundingProgress progress) linkWaitLabel;
  final String Function(PaymentLinkClaimSession session) claimWaitLabel;
  final int availableSoonRemainingConfirmations;

  final ValueChanged<PaymentLinksLocalPage> onShowPage;
  final VoidCallback onStartCreate;
  final VoidCallback onRunRedeemAction;
  final VoidCallback onScanCard;
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
  final VoidCallback onAbandonReceivedPreview;
  final VoidCallback onReceivedHome;
  final VoidCallback onClaimReceivedLink;

  @override
  Widget build(BuildContext context) =>
      _PaymentLinksMobileNavigator(body: this);

  Widget _buildPage(BuildContext context, PaymentLinksLocalPage page) =>
      switch (page) {
        PaymentLinksLocalPage.home => _buildHome(context),
        PaymentLinksLocalPage.amount => _buildAmount(),
        PaymentLinksLocalPage.message => _buildMessage(),
        PaymentLinksLocalPage.review => _buildReview(),
        PaymentLinksLocalPage.ready => _buildReady(context),
        PaymentLinksLocalPage.shareQr => _buildHome(context),
        PaymentLinksLocalPage.redeem =>
          claimOutcome ??
              PaymentLinkRedeemMobileView(
                state: PaymentLinkRedeemMobileState.values.byName(
                  redeemState.name,
                ),
                onBack: () => onShowPage(PaymentLinksLocalPage.home),
                onPaste: operationInProgress ? null : onRunRedeemAction,
                onScan: operationInProgress ? null : onScanCard,
                fromQrCode: redeemFromQrCode,
                onClearClipboard: operationInProgress ? null : onClearClipboard,
                pasteLabel: redeemActionLabel,
              ),
        PaymentLinksLocalPage.received => _buildReceived(context),
      };

  void _leavePaymentLinks(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

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
        supportingText: amountFiatText,
        supportingLoading: amountFiatLoading,
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
      supportingText: amountFiatText,
      supportingLoading: amountFiatLoading,
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
      onContinue:
          operationInProgress ||
              (!hasPendingFundingMetadata && !canContinueAmount)
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
      supportingText: readyFiatText,
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
      onCopy: ready && !operationInProgress && !readyCopyInProgress
          ? () => onCopyLink(link)
          : null,
      onCardTap: ready && message.isNotEmpty ? onToggleReadyBack : null,
      waitingStatusLabel: linkWaitLabel(progress),
      copyLabel: readyCopyInProgress ? 'Copying...' : 'Copy link',
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
        onScan: operationInProgress ? null : onScanCard,
        fromQrCode: redeemFromQrCode,
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
      supportingText: receivedFiatText,
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
        onHome: onReceivedHome,
        waitingHeading: 'Your Gift Card\nis almost ready!',
        waitingDescription:
            '$kPaymentLinkClaimWaitingDescription\n$kPaymentLinkWaitingDescription',
        waitingIcon: AppIcons.time,
        waitingStatusLabel: claimWaitLabel(session),
        homeLabel: 'Go home',
      );
    }
    return PaymentLinkReceivedMobileView(
      card: card,
      hasMessage: hasCardMessage,
      onClose: onAbandonReceivedPreview,
      decoration: const PaymentLinkConfetti(),
      onRevealMessage: hasCardMessage ? onToggleReceivedBack : null,
      onClaim: operationInProgress ? null : onClaimReceivedLink,
      claimLabel: operationInProgress
          ? 'Claiming...'
          : receivedClaimSession == null
          ? 'Try again'
          : 'Claim the gift',
    );
  }
}

/// Keep the wallet state above the navigator, but give each mobile step a real
/// Cupertino route. The outer /payment-links route remains the intake owner.
class _PaymentLinksMobileNavigator extends StatefulWidget {
  const _PaymentLinksMobileNavigator({required this.body});
  final PaymentLinksMobileBody body;

  @override
  State<_PaymentLinksMobileNavigator> createState() =>
      _PaymentLinksMobileNavigatorState();
}

class _PaymentLinksMobileNavigatorState
    extends State<_PaymentLinksMobileNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _stepKeys = <PaymentLinksLocalPage, LocalKey>{};
  ValueKey<Key?> get _signingKey => ValueKey(widget.body.keystoneOverlay?.key);

  List<PaymentLinksLocalPage> get _steps => switch (widget.body.page) {
    PaymentLinksLocalPage.home ||
    PaymentLinksLocalPage.shareQr => [PaymentLinksLocalPage.home],
    PaymentLinksLocalPage.amount => [
      PaymentLinksLocalPage.home,
      PaymentLinksLocalPage.amount,
    ],
    PaymentLinksLocalPage.message => [
      PaymentLinksLocalPage.home,
      PaymentLinksLocalPage.amount,
      PaymentLinksLocalPage.message,
    ],
    PaymentLinksLocalPage.review => [
      PaymentLinksLocalPage.home,
      PaymentLinksLocalPage.amount,
      PaymentLinksLocalPage.message,
      PaymentLinksLocalPage.review,
    ],
    PaymentLinksLocalPage.ready => [
      PaymentLinksLocalPage.home,
      PaymentLinksLocalPage.ready,
    ],
    PaymentLinksLocalPage.redeem => [
      PaymentLinksLocalPage.home,
      PaymentLinksLocalPage.redeem,
    ],
    PaymentLinksLocalPage.received => [
      PaymentLinksLocalPage.home,
      PaymentLinksLocalPage.received,
    ],
  };

  void _didRemovePage(Page<Object?> removed) {
    final body = widget.body;
    if (removed.key == _signingKey) {
      if (body.keystoneOverlay != null) body.onCancelKeystone();
      return;
    }
    // Declarative resets also remove routes. Only a user pop of the current
    // step may update the owner; removed predecessors must not resurrect it.
    if (body.keystoneOverlay != null || removed.key != _stepKeys[body.page]) {
      return;
    }
    if (body.page == PaymentLinksLocalPage.received) {
      body.onAbandonReceivedPreview();
    } else {
      final steps = _steps;
      if (steps.length > 1) body.onShowPage(steps[steps.length - 2]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    final signing = body.keystoneOverlay;
    final steps = _steps;
    // A newly entered step must not reuse the identity of its outgoing route.
    // In particular, late removal callbacks must never dismiss a new draft.
    _stepKeys.removeWhere((step, _) => !steps.contains(step));
    for (final step in steps) {
      _stepKeys.putIfAbsent(step, UniqueKey.new);
    }
    final hasInnerBack = steps.length > 1 || signing != null;
    final outerRoute = ModalRoute.of(context);
    return PopScope<Object?>(
      canPop:
          !hasInnerBack &&
          !body.navigationLocked &&
          outerRoute?.isFirst != true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (hasInnerBack) {
          _navigatorKey.currentState?.maybePop();
        } else if (!body.navigationLocked) {
          body._leavePaymentLinks(context);
        }
      },
      child: Scaffold(
        key: const ValueKey('payment_links_mobile_screen'),
        backgroundColor: context.colors.background.window,
        body: Navigator(
          key: _navigatorKey,
          onDidRemovePage: _didRemovePage,
          pages: [
            for (final step in steps)
              CupertinoPage<Object?>(
                key: _stepKeys[step],
                child: PopScope<Object?>(
                  canPop: !body.navigationLocked,
                  child: Scaffold(
                    backgroundColor: context.colors.background.window,
                    body: AppToastHost(
                      child: SafeArea(child: body._buildPage(context, step)),
                    ),
                  ),
                ),
              ),
            if (signing != null)
              CupertinoPage<Object?>(
                key: _signingKey,
                // The shared signing flow owns its decode/finalization guard.
                child: Scaffold(
                  backgroundColor: context.colors.background.window,
                  body: AppToastHost(child: SafeArea(child: signing)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
