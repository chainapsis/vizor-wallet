// ignore_for_file: depend_on_referenced_packages
// Widgetbook is dev-only; every value in this file is deterministic fixture
// data and is intentionally isolated from payment-link services and storage.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/payment_links/widgets/payment_link_card_flip.dart';
import '../src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import '../src/features/payment_links/widgets/payment_link_confetti.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../src/features/payment_links/widgets/payment_link_long_sync_warning.dart';

const _previewWindowSize = Size(1080, 720);
const _message = 'Hey there! Welcome to the Shielded\nWorld ;)';
const kPaymentLinkPreviewFiatDelay = Duration(milliseconds: 1200);

enum PaymentLinkPreviewState {
  empty,
  help,
  createEmpty,
  createFocused,
  createAmount,
  createSyncing,
  createInsufficient,
  createFiatLoading,
  createFiat,
  messageEmpty,
  messageFilled,
  review,
  reviewMessage,
  readyWaiting,
  ready,
  cardsList,
  cardsReceiving,
  cardsReceived,
  redeemPaste,
  redeemLongSyncWarning,
  redeemLoading,
  redeemInvalid,
  redeemUnavailable,
  receivedWaiting,
  received,
  receivedMessage,
}

Widget buildPaymentLinkEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.empty);

Widget buildPaymentLinkHelpUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.help);

Widget buildPaymentLinkCreateEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.createEmpty);

Widget buildPaymentLinkCreateFocusedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createFocused,
    );

Widget buildPaymentLinkCreateAmountUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createAmount,
    );

Widget buildPaymentLinkCreateInsufficientUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createInsufficient,
    );

Widget buildPaymentLinkCreateSyncingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createSyncing,
    );

Widget buildPaymentLinkCreateFiatLoadingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createFiatLoading,
    );

Widget buildPaymentLinkCreateFiatUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.createFiat);

Widget buildPaymentLinkInteractiveUseCase(BuildContext context) =>
    const PaymentLinkInteractiveDesktopPreview();

Widget buildPaymentLinkInteractiveFocusedUseCase(BuildContext context) =>
    const PaymentLinkInteractiveDesktopPreview(
      initialAmount: '4.45',
      focusAmount: true,
    );

Widget buildPaymentLinkMessageEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.messageEmpty,
    );

Widget buildPaymentLinkMessageFilledUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.messageFilled,
    );

Widget buildPaymentLinkMessageInteractiveUseCase(BuildContext context) =>
    const PaymentLinkInteractiveMessageDesktopPreview();

Widget buildPaymentLinkMessageEditingUseCase(BuildContext context) =>
    const PaymentLinkInteractiveMessageDesktopPreview(
      initialEditorRevealed: true,
    );

Widget buildPaymentLinkMessageTooLargeUseCase(BuildContext context) =>
    PaymentLinkInteractiveMessageDesktopPreview(
      initialEditorRevealed: true,
      initialMessage: List.filled(25, '👨‍👩‍👧‍👦').join(),
    );

Widget buildPaymentLinkReviewUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.review);

Widget buildPaymentLinkReviewMessageUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.reviewMessage,
    );

Widget buildPaymentLinkReadyWaitingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.readyWaiting,
    );

Widget buildPaymentLinkReadyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.ready);

Widget buildPaymentLinkCardsListUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.cardsList);

Widget buildPaymentLinkCardsReceivingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.cardsReceiving,
    );

Widget buildPaymentLinkCardsReceivedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.cardsReceived,
    );

Widget buildPaymentLinkRedeemPasteUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.redeemPaste);

Widget buildPaymentLinkRedeemLongSyncWarningUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemLongSyncWarning,
    );

Widget buildPaymentLinkRedeemLoadingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemLoading,
    );

Widget buildPaymentLinkRedeemInvalidUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemInvalid,
    );

Widget buildPaymentLinkRedeemUnavailableUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemUnavailable,
    );

Widget buildPaymentLinkReceivedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.received);

Widget buildPaymentLinkReceivedWaitingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.receivedWaiting,
    );

Widget buildPaymentLinkReceivedMessageUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.receivedMessage,
    );

/// A deterministic desktop-only surface for Widgetbook and Figma capture.
///
/// This deliberately contains no provider, persistence, network, or Rust
/// dependency. Unsupported values such as messages, fees, and Redeemed status
/// exist only in this fixture layer.
class PaymentLinkDesktopPreview extends StatelessWidget {
  const PaymentLinkDesktopPreview({required this.state, super.key});

  final PaymentLinkPreviewState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        size: _previewWindowSize,
        child: AppDesktopShell(
          sidebar: const _PaymentLinkPreviewSidebar(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: _PaymentLinkPreviewPane(state: state),
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkPreviewPane extends StatelessWidget {
  const _PaymentLinkPreviewPane({required this.state});

  final PaymentLinkPreviewState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PaymentLinkPreviewState.empty => _home(),
      PaymentLinkPreviewState.help => PaymentLinkHowItWorksDesktopView(
        background: _home(),
        onClose: _noop,
      ),
      PaymentLinkPreviewState.createEmpty => _amount(
        visualState: PaymentLinkAmountVisualState.empty,
        artwork: PaymentLinkCardArtwork.gift,
        cardBuilder: (artwork) => PaymentLinkGiftCard(
          artwork: artwork,
          emptyAmountLabel: 'Enter Amount',
        ),
      ),
      PaymentLinkPreviewState.createFocused => _amount(
        visualState: PaymentLinkAmountVisualState.focused,
        artwork: PaymentLinkCardArtwork.gift,
        cardBuilder: (artwork) => PaymentLinkGiftCard(
          artwork: artwork,
          amountText: '1',
          maxAmountText: '142.23',
        ),
      ),
      PaymentLinkPreviewState.createAmount => _amount(
        visualState: PaymentLinkAmountVisualState.amount,
        artwork: PaymentLinkCardArtwork.chestLava,
        cardBuilder: (artwork) => PaymentLinkGiftCard(
          artwork: artwork,
          amountText: '4.45',
          maxAmountText: '142.23',
        ),
      ),
      PaymentLinkPreviewState.createSyncing => _amount(
        visualState: PaymentLinkAmountVisualState.amount,
        artwork: PaymentLinkCardArtwork.diamond,
        supportingText:
            'Card fee will be estimated when wallet sync completes.',
        enableContinue: false,
        cardBuilder: (artwork) => PaymentLinkGiftCard(
          artwork: artwork,
          amountText: '4.45',
          showCaret: false,
        ),
      ),
      PaymentLinkPreviewState.createInsufficient => _amount(
        visualState: PaymentLinkAmountVisualState.amount,
        artwork: PaymentLinkCardArtwork.diamond,
        supportingText:
            'Insufficient balance to cover the Card amount and fees.',
        supportingTextIsError: true,
        enableContinue: false,
        cardBuilder: (artwork) => PaymentLinkGiftCard(
          artwork: artwork,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
      ),
      PaymentLinkPreviewState.createFiatLoading => _amount(
        visualState: PaymentLinkAmountVisualState.fiatLoading,
        artwork: PaymentLinkCardArtwork.ruby,
        cardBuilder: (artwork) => PaymentLinkGiftCard(
          artwork: artwork,
          amountText: '4.45',
          supportingLoading: true,
          showCaret: false,
        ),
      ),
      PaymentLinkPreviewState.createFiat => _amount(
        visualState: PaymentLinkAmountVisualState.fiatLoaded,
        artwork: PaymentLinkCardArtwork.ruby,
        cardBuilder: (artwork) => PaymentLinkGiftCard(
          artwork: artwork,
          amountText: '4.45',
          supportingText: r'$1,201.21',
          showCaret: false,
        ),
      ),
      PaymentLinkPreviewState.messageEmpty => PaymentLinkMessageDesktopView(
        state: PaymentLinkMessageVisualState.empty,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
        ),
        onBack: _noop,
        onSkip: _noop,
      ),
      PaymentLinkPreviewState.messageFilled => PaymentLinkMessageDesktopView(
        state: PaymentLinkMessageVisualState.filled,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          messageCharacterCount: 72,
          onDeleteMessage: _noop,
        ),
        onBack: _noop,
        onSkip: _noop,
        onContinue: _noop,
      ),
      PaymentLinkPreviewState.review => const _PaymentLinkReviewPreview(),
      PaymentLinkPreviewState.reviewMessage => const _PaymentLinkReviewPreview(
        initialShowBack: true,
      ),
      PaymentLinkPreviewState.readyWaiting => PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.waiting,
        card: _readyCard(),
        decoration: const PaymentLinkConfetti(),
        onBack: _noop,
        onCopy: null,
      ),
      PaymentLinkPreviewState.receivedWaiting => PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.waiting,
        card: _readyCard(),
        onBack: _noop,
        onCopy: null,
        waitingHeading: 'Your Gift Card\nis almost ready!',
        waitingPrimaryText: 'Waiting for 6 confirmations.',
        waitingSecondaryText:
            'Vizor will keep checking. You can claim the card as soon as\n'
            'the funds are ready.',
        waitingStatusLabel: 'Wait 5:00 to claim',
      ),
      PaymentLinkPreviewState.ready => const _PaymentLinkReadyPreview(),
      PaymentLinkPreviewState.cardsList => PaymentLinkCardsDesktopView(
        sections: const [
          PaymentLinkCardsSection(
            label: 'Creating',
            cards: [
              PaymentLinkCardListRow(
                thumbnail: _PaymentLinkThumbnail(PaymentLinkCardArtwork.dragon),
                amountText: '1.10 ZEC',
                dateText: 'May 20',
                statusText: 'Preparing...',
                showLoader: true,
              ),
            ],
          ),
          PaymentLinkCardsSection(
            label: 'Pending',
            cards: [
              PaymentLinkCardListRow(
                thumbnail: _PaymentLinkThumbnail(PaymentLinkCardArtwork.ruby),
                amountText: '0.25 ZEC',
                dateText: 'July 2',
                statusText: 'New Wallet',
                onAction: _noop,
                showCopyIcon: true,
              ),
              PaymentLinkCardListRow(
                thumbnail: _PaymentLinkThumbnail(PaymentLinkCardArtwork.dragon),
                amountText: '1.10 ZEC',
                dateText: 'May 20',
                statusText: 'New Wallet',
                onAction: _noop,
                showCopyIcon: true,
              ),
            ],
          ),
          PaymentLinkCardsSection(
            label: 'July 2026',
            cards: [
              PaymentLinkCardListRow(
                thumbnail: _PaymentLinkThumbnail(
                  PaymentLinkCardArtwork.chestLava,
                ),
                amountText: '2.5 ZEC',
                dateText: 'July 20',
                statusText: 'Redeemed',
              ),
              PaymentLinkCardListRow(
                thumbnail: _PaymentLinkThumbnail(
                  PaymentLinkCardArtwork.chestLava,
                ),
                amountText: '2.5 ZEC',
                dateText: 'July 20',
                statusText: 'Redeemed',
              ),
              PaymentLinkCardListRow(
                thumbnail: _PaymentLinkThumbnail(
                  PaymentLinkCardArtwork.chestLava,
                ),
                amountText: '2.5 ZEC',
                dateText: 'July 20',
                statusText: 'Redeemed',
              ),
              PaymentLinkCardListRow(
                thumbnail: _PaymentLinkThumbnail(
                  PaymentLinkCardArtwork.chestLava,
                ),
                amountText: '2.5 ZEC',
                dateText: 'July 20',
                statusText: 'Redeemed',
              ),
            ],
          ),
        ],
        onBack: _noop,
        onCreate: _noop,
        onRedeem: _noop,
      ),
      PaymentLinkPreviewState.cardsReceiving => _receivedCardsList(
        statusText: 'Receiving...',
      ),
      PaymentLinkPreviewState.cardsReceived => _receivedCardsList(
        statusText: 'Received',
      ),
      PaymentLinkPreviewState.redeemPaste => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.paste,
        onBack: _noop,
        onPaste: _noop,
        subtitle: 'Copy the card link you’ve received, and paste it below.',
        pasteLabel: 'Paste card link',
      ),
      PaymentLinkPreviewState.redeemLongSyncWarning => Stack(
        fit: StackFit.expand,
        children: [
          PaymentLinkRedeemDesktopView(
            state: PaymentLinkRedeemVisualState.paste,
            onBack: _noop,
            onPaste: _noop,
            subtitle: 'Copy the card link you’ve received, and paste it below.',
            pasteLabel: 'Paste card link',
          ),
          const PaymentLinkLongSyncWarningModal(
            onConfirm: _noop,
            onCancel: _noop,
          ),
        ],
      ),
      PaymentLinkPreviewState.redeemLoading =>
        const PaymentLinkRedeemDesktopView(
          state: PaymentLinkRedeemVisualState.loading,
          onBack: _noop,
          subtitle: 'Copy the card link you’ve received, and paste it below.',
        ),
      PaymentLinkPreviewState.redeemInvalid => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.invalid,
        onBack: _noop,
        onPaste: _noop,
        onClearClipboard: _noop,
        subtitle: 'Copy the card link you’ve received, and paste it below.',
        pasteLabel: 'Paste card link',
        clearLabel: 'Clear clipboard',
      ),
      PaymentLinkPreviewState.redeemUnavailable => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.unavailable,
        onBack: _noop,
        onPaste: _noop,
        onClearClipboard: _noop,
      ),
      PaymentLinkPreviewState.received => const _PaymentLinkReceivedPreview(
        hasMessage: false,
      ),
      PaymentLinkPreviewState.receivedMessage =>
        const _PaymentLinkReceivedPreview(hasMessage: true),
    };
  }

  PaymentLinksHomeDesktopView _home() {
    return PaymentLinksHomeDesktopView(
      illustration: Image.asset(
        'assets/illustrations/payment_links/payment_link_empty_card.png',
        width: 243,
        height: 162,
        fit: BoxFit.contain,
        semanticLabel: 'Gift box',
      ),
      onBack: _noop,
      onShowHelp: _noop,
      onCreate: _noop,
      onRedeem: _noop,
    );
  }

  PaymentLinkCardsDesktopView _receivedCardsList({required String statusText}) {
    return PaymentLinkCardsDesktopView(
      sections: [
        PaymentLinkCardsSection(
          label: 'Received',
          cards: [
            PaymentLinkCardListRow(
              thumbnail: const _PaymentLinkThumbnail(
                PaymentLinkCardArtwork.ruby,
              ),
              amountText: '4.45 ZEC',
              dateText: 'August 7',
              statusText: statusText,
              showLoader: statusText == 'Receiving...',
            ),
          ],
        ),
      ],
      onBack: _noop,
      onCreate: _noop,
      onRedeem: _noop,
      activeTab: PaymentLinkCardsTab.received,
    );
  }

  Widget _amount({
    required PaymentLinkAmountVisualState visualState,
    required PaymentLinkCardArtwork artwork,
    required _PaymentLinkGiftCardBuilder cardBuilder,
    String? supportingText,
    bool supportingTextIsError = false,
    bool enableContinue = true,
  }) {
    return _PaymentLinkStaticAmountPreview(
      visualState: visualState,
      initialArtwork: artwork,
      cardBuilder: cardBuilder,
      supportingText: supportingText,
      supportingTextIsError: supportingTextIsError,
      enableContinue: enableContinue,
    );
  }

  static Widget _readyCard() {
    return const PaymentLinkGiftCard(
      artwork: PaymentLinkCardArtwork.ruby,
      amountText: '4.45',
      supportingText: r'$1,210.20',
      showCaret: false,
    );
  }
}

class _PaymentLinkReviewPreview extends StatefulWidget {
  const _PaymentLinkReviewPreview({this.initialShowBack = false});

  final bool initialShowBack;

  @override
  State<_PaymentLinkReviewPreview> createState() =>
      _PaymentLinkReviewPreviewState();
}

class _PaymentLinkReviewPreviewState extends State<_PaymentLinkReviewPreview> {
  late bool _showBack = widget.initialShowBack;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkReviewDesktopView(
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
          onTap: () => setState(() => _showBack = true),
          semanticLabel: 'Reveal gift card message',
        ),
        back: PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          onTap: () => setState(() => _showBack = false),
          semanticLabel: 'Show gift card front',
        ),
      ),
      onBack: _noop,
      onConfirm: _noop,
      cardAmountText: '4.45 ZEC',
      cardFeeText: '0.04 ZEC',
      totalAmountText: '4.49 ZEC',
    );
  }
}

typedef _PaymentLinkGiftCardBuilder =
    Widget Function(PaymentLinkCardArtwork artwork);

class _PaymentLinkStaticAmountPreview extends StatefulWidget {
  const _PaymentLinkStaticAmountPreview({
    required this.visualState,
    required this.initialArtwork,
    required this.cardBuilder,
    this.supportingText,
    this.supportingTextIsError = false,
    this.enableContinue = true,
  });

  final PaymentLinkAmountVisualState visualState;
  final PaymentLinkCardArtwork initialArtwork;
  final _PaymentLinkGiftCardBuilder cardBuilder;
  final String? supportingText;
  final bool supportingTextIsError;
  final bool enableContinue;

  @override
  State<_PaymentLinkStaticAmountPreview> createState() =>
      _PaymentLinkStaticAmountPreviewState();
}

class _PaymentLinkStaticAmountPreviewState
    extends State<_PaymentLinkStaticAmountPreview> {
  late PaymentLinkCardArtwork _selectedArtwork;

  @override
  void initState() {
    super.initState();
    _selectedArtwork = widget.initialArtwork;
  }

  @override
  void didUpdateWidget(covariant _PaymentLinkStaticAmountPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialArtwork != widget.initialArtwork) {
      _selectedArtwork = widget.initialArtwork;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaymentLinkAmountDesktopView(
      state: widget.visualState,
      card: widget.cardBuilder(_selectedArtwork),
      cardSelector: PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: _selectedArtwork,
        onSelected: (artwork) {
          if (artwork == _selectedArtwork) return;
          setState(() => _selectedArtwork = artwork);
        },
      ),
      onBack: _noop,
      onCreate: widget.enableContinue ? _noop : null,
      supportingText: widget.supportingText,
      supportingTextIsError: widget.supportingTextIsError,
    );
  }
}

class _PaymentLinkReadyPreview extends StatefulWidget {
  const _PaymentLinkReadyPreview();

  @override
  State<_PaymentLinkReadyPreview> createState() =>
      _PaymentLinkReadyPreviewState();
}

class _PaymentLinkReadyPreviewState extends State<_PaymentLinkReadyPreview> {
  bool _showBack = false;

  void _toggleCardSide() => setState(() => _showBack = !_showBack);

  @override
  Widget build(BuildContext context) {
    return PaymentLinkReadyDesktopView(
      state: PaymentLinkReadyVisualState.ready,
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        back: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          messageCharacterCount: 72,
        ),
      ),
      decoration: const PaymentLinkConfetti(),
      onBack: _noop,
      onCopy: _noop,
      onCardTap: _toggleCardSide,
    );
  }
}

/// Interactive message-entry surface kept separate from the deterministic
/// empty and filled Figma fixtures.
class PaymentLinkInteractiveMessageDesktopPreview extends StatefulWidget {
  const PaymentLinkInteractiveMessageDesktopPreview({
    this.initialEditorRevealed = false,
    this.initialMessage = '',
    super.key,
  });

  final bool initialEditorRevealed;
  final String initialMessage;

  @override
  State<PaymentLinkInteractiveMessageDesktopPreview> createState() =>
      _PaymentLinkInteractiveMessageDesktopPreviewState();
}

class _PaymentLinkInteractiveMessageDesktopPreviewState
    extends State<PaymentLinkInteractiveMessageDesktopPreview> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late bool _editorRevealed;
  bool get _hasMessage => _controller.text.isNotEmpty;
  bool get _messageExceedsByteLimit =>
      !PaymentLinkPresentation.isMessageWithinUtf8ByteLimit(_controller.text);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMessage);
    _editorRevealed = widget.initialEditorRevealed;
    if (_editorRevealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.context != null) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clearMessage() {
    _controller.clear();
    _focusNode.requestFocus();
    setState(() {});
  }

  void _revealEditor() {
    if (_editorRevealed) {
      _focusNode.requestFocus();
      return;
    }
    setState(() => _editorRevealed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editorRevealed || _focusNode.context == null) return;
      _focusNode.requestFocus();
    });
  }

  void _focusEditorAfterFlip() {
    if (!mounted || !_editorRevealed) return;
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        size: _previewWindowSize,
        child: AppDesktopShell(
          sidebar: const _PaymentLinkPreviewSidebar(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: PaymentLinkMessageDesktopView(
              state: _hasMessage
                  ? PaymentLinkMessageVisualState.filled
                  : PaymentLinkMessageVisualState.empty,
              card: PaymentLinkCardFlip(
                showBack: _editorRevealed,
                front: PaymentLinkGiftCard(
                  artwork: PaymentLinkCardArtwork.ruby,
                  showBack: true,
                  message: _controller.text,
                  onTap: _revealEditor,
                  semanticLabel: 'Start writing gift card message',
                ),
                back: PaymentLinkGiftCard(
                  artwork: PaymentLinkCardArtwork.ruby,
                  showBack: true,
                  messageController: _controller,
                  messageFocusNode: _focusNode,
                  messageEditorKey: const ValueKey(
                    'payment_link_interactive_message_editor',
                  ),
                  messageInputFormatters: [
                    LengthLimitingTextInputFormatter(128),
                  ],
                  onMessageChanged: (_) => setState(() {}),
                  onDeleteMessage: _hasMessage ? _clearMessage : null,
                  semanticLabel: 'Gift card message input',
                ),
                onAnimationEnd: _focusEditorAfterFlip,
              ),
              onBack: _noop,
              onSkip: _clearMessage,
              onContinue: _hasMessage && !_messageExceedsByteLimit
                  ? _noop
                  : null,
              errorText: _messageExceedsByteLimit
                  ? kPaymentLinkMessageTooLargeText
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkReceivedPreview extends StatefulWidget {
  const _PaymentLinkReceivedPreview({required this.hasMessage});

  final bool hasMessage;

  @override
  State<_PaymentLinkReceivedPreview> createState() =>
      _PaymentLinkReceivedPreviewState();
}

class _PaymentLinkReceivedPreviewState
    extends State<_PaymentLinkReceivedPreview> {
  late bool _showBack;

  @override
  void initState() {
    super.initState();
    _showBack = false;
  }

  void _toggleCardSide() => setState(() => _showBack = !_showBack);

  @override
  Widget build(BuildContext context) {
    if (!widget.hasMessage) {
      return PaymentLinkReceivedDesktopView(
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        decoration: const PaymentLinkConfetti(),
        onBack: _noop,
        onClaim: _noop,
      );
    }
    return PaymentLinkReceivedDesktopView(
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        back: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          messageCharacterCount: 72,
        ),
      ),
      decoration: const PaymentLinkConfetti(),
      onBack: _noop,
      onClaim: _noop,
      onRevealMessage: _toggleCardSide,
      cardActionLabel: _showBack
          ? 'Show gift card artwork'
          : 'Reveal gift card message',
    );
  }
}

/// An interactive, local-only amount and artwork simulator for Widgetbook.
///
/// It deliberately uses a fixed fake conversion rate and a local timer so it
/// never reaches payment-link providers, storage, network, or Rust code.
class PaymentLinkInteractiveDesktopPreview extends StatefulWidget {
  const PaymentLinkInteractiveDesktopPreview({
    this.initialAmount = '',
    this.focusAmount = false,
    super.key,
  });

  final String initialAmount;
  final bool focusAmount;

  @override
  State<PaymentLinkInteractiveDesktopPreview> createState() =>
      _PaymentLinkInteractiveDesktopPreviewState();
}

class _PaymentLinkInteractiveDesktopPreviewState
    extends State<PaymentLinkInteractiveDesktopPreview> {
  static const _usdPerZec = 272.0;
  static final _amountFormatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    final isNumericAmount = RegExp(
      r'^(?:\d+(?:\.\d{0,8})?|\.\d{0,8})?$',
    ).hasMatch(newValue.text);
    return isNumericAmount ? newValue : oldValue;
  });

  late final TextEditingController _amountController;
  final FocusNode _amountFocusNode = FocusNode();
  PaymentLinkCardArtwork _selectedArtwork = PaymentLinkCardArtwork.gift;
  Timer? _fiatTimer;
  String? _fiatText;
  bool _fiatLoading = false;
  bool _amountFocused = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.initialAmount);
    _amountFocused = widget.focusAmount;
    _amountFocusNode.addListener(_handleAmountFocus);
    if (widget.focusAmount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _amountFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _fiatTimer?.cancel();
    _amountFocusNode
      ..removeListener(_handleAmountFocus)
      ..dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _handleAmountFocus() {
    if (_amountFocused == _amountFocusNode.hasFocus) return;
    setState(() => _amountFocused = _amountFocusNode.hasFocus);
  }

  void _handleAmountChanged(String value) {
    _fiatTimer?.cancel();
    final amount = double.tryParse(value.startsWith('.') ? '0$value' : value);
    if (amount == null || amount <= 0) {
      setState(() {
        _fiatLoading = false;
        _fiatText = null;
      });
      return;
    }

    setState(() {
      _fiatLoading = true;
      _fiatText = null;
    });
    _fiatTimer = Timer(kPaymentLinkPreviewFiatDelay, () {
      if (!mounted || _amountController.text != value) return;
      setState(() {
        _fiatLoading = false;
        _fiatText = _formatUsd(amount * _usdPerZec);
      });
    });
  }

  PaymentLinkAmountVisualState get _visualState {
    if (_amountController.text.isEmpty) {
      return _amountFocused
          ? PaymentLinkAmountVisualState.focused
          : PaymentLinkAmountVisualState.empty;
    }
    if (!_hasPositiveAmount) return PaymentLinkAmountVisualState.focused;
    if (_fiatLoading) return PaymentLinkAmountVisualState.fiatLoading;
    if (_fiatText != null) return PaymentLinkAmountVisualState.fiatLoaded;
    return PaymentLinkAmountVisualState.amount;
  }

  bool get _hasPositiveAmount {
    final value = _amountController.text;
    final amount = double.tryParse(value.startsWith('.') ? '0$value' : value);
    return amount != null && amount > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        size: _previewWindowSize,
        child: AppDesktopShell(
          sidebar: const _PaymentLinkPreviewSidebar(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: PaymentLinkAmountDesktopView(
              state: _visualState,
              card: PaymentLinkGiftCard(
                artwork: _selectedArtwork,
                amountController: _amountController,
                amountFocusNode: _amountFocusNode,
                amountEditorKey: const ValueKey(
                  'payment_link_interactive_amount_editor',
                ),
                amountInputFormatters: [_amountFormatter],
                onAmountChanged: _handleAmountChanged,
                maxAmountText: '142.23',
                supportingText: _fiatText,
                supportingLoading: _fiatLoading,
                emptyAmountLabel: 'Enter Amount',
                semanticLabel: 'Gift card amount input',
              ),
              cardSelector: PaymentLinkCardSelectorRail(
                artworks: PaymentLinkCardArtwork.values,
                selected: _selectedArtwork,
                onSelected: (artwork) {
                  if (artwork == _selectedArtwork) return;
                  setState(() => _selectedArtwork = artwork);
                },
              ),
              onBack: _noop,
              onCreate: _noop,
            ),
          ),
        ),
      ),
    );
  }

  static String _formatUsd(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match[1]},',
    );
    return '\$$whole.${parts.last}';
  }
}

class _PaymentLinkThumbnail extends StatelessWidget {
  const _PaymentLinkThumbnail(this.artwork);

  final PaymentLinkCardArtwork artwork;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      artwork.assetPath,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
  }
}

class _PaymentLinkPreviewSidebar extends StatelessWidget {
  const _PaymentLinkPreviewSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      glass: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PaymentLinkPreviewAccountHeader(),
            const SizedBox(height: AppSpacing.md),
            const AppSidebarItem(
              label: 'Home',
              iconName: AppIcons.home,
              active: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Swap',
              iconName: AppIcons.swapArrows,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Vote',
              iconName: AppIcons.scroll,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Activity',
              iconName: AppIcons.history,
              onTap: _noop,
            ),
            const Spacer(),
            AppSidebarItem(
              label: 'Settings',
              iconName: AppIcons.cog,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Sign out',
              iconName: AppIcons.logOut,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 20,
              child: Row(
                children: [
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: colors.sync.lightSuccess,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '34% Syncing...',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.sync.textSyncing,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentLinkPreviewAccountHeader extends StatelessWidget {
  const _PaymentLinkPreviewAccountHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const AppProfilePicture(
            profilePictureId: kDefaultProfilePictureId,
            size: AppProfilePictureSize.large,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Username',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '142.23 ZEC',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          AppIcon(AppIcons.copy, size: 16, color: colors.icon.muted),
        ],
      ),
    );
  }
}

void _noop() {}
