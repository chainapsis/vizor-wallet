// ignore_for_file: depend_on_referenced_packages
// Widgetbook is dev-only. Every fixture in this file is isolated from wallet
// storage, payment-link operations, network access, and Rust state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import '../src/features/payment_links/widgets/payment_link_card_flip.dart';
import '../src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import '../src/features/payment_links/widgets/payment_link_confetti.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';

const _mobilePreviewSize = Size(393, 773);
const _cardWidth = 361.0;
const _cardHeight = 225.625;
const _fixtureAmount = '4.45';
const _fixtureFee = '0.04 ZEC';
const _fixtureTotal = '4.49 ZEC';
const _fixtureMessage = 'Hey there! Welcome to the Shielded World ;)';
const _fixtureArtwork = PaymentLinkCardArtwork.chestLava;
const kMobilePaymentLinkPreviewFiatDelay = Duration(milliseconds: 1200);

Widget buildMobilePaymentLinkHomeEmptyUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(child: _PaymentLinkHomeFixture());
}

Widget buildMobilePaymentLinkAmountEmptyUseCase(BuildContext context) {
  return _MobilePaymentLinkFrame(
    child: PaymentLinkAmountMobileView(
      card: const PaymentLinkGiftCard(
        artwork: _fixtureArtwork,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
        emptyAmountLabel: 'Enter Amount',
      ),
      cardSelector: _artworkSelector(_fixtureArtwork),
      onBack: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkAmountFilledUseCase(BuildContext context) {
  return _MobilePaymentLinkFrame(
    child: PaymentLinkAmountMobileView(
      card: const PaymentLinkGiftCard(
        artwork: _fixtureArtwork,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
        amountText: _fixtureAmount,
        showCaret: false,
        supportingLoading: true,
      ),
      cardSelector: _artworkSelector(_fixtureArtwork),
      onBack: _noop,
      onContinue: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkAmountFocusedUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(child: _FocusedAmountFixture());
}

Widget buildMobilePaymentLinkMessageEmptyUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkMessageMobileView(
      card: PaymentLinkGiftCard(
        artwork: _fixtureArtwork,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
        showBack: true,
      ),
      onBack: _noop,
      onSkip: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkMessageFilledUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkMessageMobileView(
      card: PaymentLinkGiftCard(
        artwork: _fixtureArtwork,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
        showBack: true,
        message: _fixtureMessage,
        onDeleteMessage: _noop,
      ),
      onBack: _noop,
      onContinue: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkMessageFocusedUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(child: _FocusedMessageFixture());
}

Widget buildMobilePaymentLinkReviewUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkReviewMobileView(
      card: PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.knightMagic,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
        amountText: _fixtureAmount,
        supportingText: r'$142.23',
        showCaret: false,
      ),
      onBack: _noop,
      cardAmountText: '$_fixtureAmount ZEC',
      cardFeeText: _fixtureFee,
      totalAmountText: _fixtureTotal,
      onContinue: _noop,
      onFeeHelp: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkReadyCelebratingUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkReadyMobileView(
      state: PaymentLinkReadyMobileState.waiting,
      card: PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.knightMagic,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
        amountText: _fixtureAmount,
        supportingText: r'$142.23',
        showCaret: false,
      ),
      onHome: _noop,
      decoration: PaymentLinkConfetti(),
    ),
  );
}

Widget buildMobilePaymentLinkReadyWaitingUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkReadyMobileView(
      state: PaymentLinkReadyMobileState.soon,
      card: PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.knightMagic,
        cardWidth: _cardWidth,
        cardHeight: _cardHeight,
        amountText: _fixtureAmount,
        supportingText: r'$142.23',
        showCaret: false,
      ),
      onHome: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkReadyUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(child: _MobileReadyFixture());
}

Widget buildMobilePaymentLinkRedeemPasteUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkRedeemMobileView(
      state: PaymentLinkRedeemMobileState.paste,
      onBack: _noop,
      onPaste: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkRedeemLoadingUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkRedeemMobileView(
      state: PaymentLinkRedeemMobileState.loading,
      onBack: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkRedeemInvalidUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: PaymentLinkRedeemMobileView(
      state: PaymentLinkRedeemMobileState.invalid,
      onBack: _noop,
      onPaste: _noop,
      onClearClipboard: _noop,
    ),
  );
}

Widget buildMobilePaymentLinkReceivedUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(child: _MobileReceivedFixture());
}

Widget buildMobilePaymentLinkInteractiveUseCase(BuildContext context) {
  return const _MobilePaymentLinkFrame(
    child: _MobilePaymentLinkInteractivePreview(),
  );
}

Widget _artworkSelector(PaymentLinkCardArtwork selected) {
  return PaymentLinkCardSelectorRail(
    artworks: PaymentLinkCardArtwork.values,
    selected: selected,
    width: _mobilePreviewSize.width,
    itemWidth: 80,
    itemHeight: 60,
    artworkWidth: 76,
    artworkHeight: 56,
    itemGap: AppSpacing.xs,
    selectionInset: EdgeInsets.zero,
    selectionBorderWidth: 2.5,
    selectionBorderRadius: 15,
    selectedCheckSize: 24,
    edgeMaskInset: AppSpacing.sm,
    edgeFadeFraction: 0.3,
    inactiveOpacity: 1,
    onSelected: _ignoreArtwork,
  );
}

class _PaymentLinkHomeFixture extends StatelessWidget {
  const _PaymentLinkHomeFixture();

  @override
  Widget build(BuildContext context) {
    return PaymentLinksHomeMobileView(
      illustration: Image.asset(
        'assets/illustrations/payment_links/payment_link_empty_card.png',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
      onBack: _noop,
      onShowHelp: () => showAppMobileSheet<void>(
        context: context,
        builder: (sheetContext) => PaymentLinkHowItWorksMobileSheet(
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      ),
      onCreate: _noop,
      onRedeem: _noop,
    );
  }
}

class _MobileReadyFixture extends StatefulWidget {
  const _MobileReadyFixture();

  @override
  State<_MobileReadyFixture> createState() => _MobileReadyFixtureState();
}

class _MobileReadyFixtureState extends State<_MobileReadyFixture> {
  var _showBack = false;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkReadyMobileView(
      state: PaymentLinkReadyMobileState.ready,
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.knightMagic,
          cardWidth: _cardWidth,
          cardHeight: _cardHeight,
          amountText: _fixtureAmount,
          supportingText: r'$142.23',
          showCaret: false,
        ),
        back: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.knightMagic,
          cardWidth: _cardWidth,
          cardHeight: _cardHeight,
          showBack: true,
          message: _fixtureMessage,
        ),
      ),
      onHome: _noop,
      onCopy: _noop,
      onCardTap: () => setState(() => _showBack = !_showBack),
      decoration: const PaymentLinkConfetti(),
    );
  }
}

class _MobileReceivedFixture extends StatefulWidget {
  const _MobileReceivedFixture();

  @override
  State<_MobileReceivedFixture> createState() => _MobileReceivedFixtureState();
}

class _MobileReceivedFixtureState extends State<_MobileReceivedFixture> {
  var _showBack = false;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkReceivedMobileView(
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.knightMagic,
          cardWidth: _cardWidth,
          cardHeight: _cardHeight,
          amountText: _fixtureAmount,
          supportingText: r'$142.23',
          showCaret: false,
        ),
        back: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.knightMagic,
          cardWidth: _cardWidth,
          cardHeight: _cardHeight,
          showBack: true,
          message: _fixtureMessage,
        ),
      ),
      hasMessage: true,
      onClose: _noop,
      onClaim: _noop,
      decoration: const PaymentLinkConfetti(),
      onRevealMessage: () => setState(() => _showBack = !_showBack),
    );
  }
}

class _FocusedAmountFixture extends StatefulWidget {
  const _FocusedAmountFixture();

  @override
  State<_FocusedAmountFixture> createState() => _FocusedAmountFixtureState();
}

class _FocusedAmountFixtureState extends State<_FocusedAmountFixture> {
  final _controller = TextEditingController(text: _fixtureAmount);
  final _focusNode = FocusNode(debugLabel: 'MobilePaymentLinkAmountFixture');
  var _renderVisualFocusFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      } else {
        setState(() => _renderVisualFocusFallback = true);
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
    return PaymentLinkAmountMobileView(
      card: _renderVisualFocusFallback
          ? const PaymentLinkGiftCard(
              key: ValueKey('mobile_payment_link_amount_focus_fallback'),
              artwork: _fixtureArtwork,
              cardWidth: _cardWidth,
              cardHeight: _cardHeight,
              amountText: _fixtureAmount,
              supportingLoading: true,
            )
          : PaymentLinkGiftCard(
              artwork: _fixtureArtwork,
              cardWidth: _cardWidth,
              cardHeight: _cardHeight,
              amountController: _controller,
              amountFocusNode: _focusNode,
              amountEditorKey: const ValueKey(
                'mobile_payment_link_focused_amount_editor',
              ),
              supportingLoading: true,
              semanticLabel: 'Gift card amount input',
            ),
      cardSelector: _artworkSelector(_fixtureArtwork),
      onBack: _noop,
    );
  }
}

class _FocusedMessageFixture extends StatefulWidget {
  const _FocusedMessageFixture();

  @override
  State<_FocusedMessageFixture> createState() => _FocusedMessageFixtureState();
}

class _FocusedMessageFixtureState extends State<_FocusedMessageFixture> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'MobilePaymentLinkMessageFixture');
  var _renderVisualFocusFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      } else {
        setState(() => _renderVisualFocusFallback = true);
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
    return PaymentLinkMessageMobileView(
      card: _renderVisualFocusFallback
          ? const PaymentLinkGiftCard(
              key: ValueKey('mobile_payment_link_message_focus_fallback'),
              artwork: _fixtureArtwork,
              cardWidth: _cardWidth,
              cardHeight: _cardHeight,
              showBack: true,
              emptyMessageLabel: '',
            )
          : PaymentLinkGiftCard(
              artwork: _fixtureArtwork,
              cardWidth: _cardWidth,
              cardHeight: _cardHeight,
              showBack: true,
              messageController: _controller,
              messageFocusNode: _focusNode,
              messageEditorKey: const ValueKey(
                'mobile_payment_link_focused_message_editor',
              ),
              semanticLabel: 'Gift card message input',
            ),
      onBack: _noop,
      onSkip: _noop,
    );
  }
}

class _MobilePaymentLinkFrame extends StatelessWidget {
  const _MobilePaymentLinkFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        key: const ValueKey('mobile_payment_link_preview_frame'),
        size: _mobilePreviewSize,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(size: _mobilePreviewSize),
          child: ColoredBox(
            color: context.colors.background.window,
            child: child,
          ),
        ),
      ),
    );
  }
}

enum _MobilePaymentLinkStep { amount, message, review }

class _MobilePaymentLinkInteractivePreview extends StatefulWidget {
  const _MobilePaymentLinkInteractivePreview();

  @override
  State<_MobilePaymentLinkInteractivePreview> createState() =>
      _MobilePaymentLinkInteractivePreviewState();
}

class _MobilePaymentLinkInteractivePreviewState
    extends State<_MobilePaymentLinkInteractivePreview> {
  static const _usdPerZec = 272.0;
  static final _amountFormatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    final valid = RegExp(
      r'^(?:\d+(?:\.\d{0,8})?|\.\d{0,8})?$',
    ).hasMatch(newValue.text);
    return valid ? newValue : oldValue;
  });

  final _amountController = TextEditingController();
  final _amountFocusNode = FocusNode();
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  Timer? _fiatTimer;
  String? _fiatText;
  var _fiatLoading = false;
  var _step = _MobilePaymentLinkStep.amount;
  var _artwork = _fixtureArtwork;

  bool get _hasPositiveAmount {
    final raw = _amountController.text;
    final value = double.tryParse(raw.startsWith('.') ? '0$raw' : raw);
    return value != null && value > 0;
  }

  bool get _messageFitsPayload =>
      PaymentLinkPresentation.isMessageWithinUtf8ByteLimit(
        _messageController.text,
      );

  @override
  void dispose() {
    _fiatTimer?.cancel();
    _amountController.dispose();
    _amountFocusNode.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _showStep(_MobilePaymentLinkStep step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = step);
  }

  void _clearMessage() {
    _messageController.clear();
    setState(() {});
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
    _fiatTimer = Timer(kMobilePaymentLinkPreviewFiatDelay, () {
      if (!mounted || _amountController.text != value) return;
      setState(() {
        _fiatLoading = false;
        _fiatText = _formatUsd(amount * _usdPerZec);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _MobilePaymentLinkStep.amount => PaymentLinkAmountMobileView(
        card: PaymentLinkGiftCard(
          artwork: _artwork,
          cardWidth: _cardWidth,
          cardHeight: _cardHeight,
          amountController: _amountController,
          amountFocusNode: _amountFocusNode,
          amountEditorKey: const ValueKey(
            'mobile_payment_link_interactive_amount_editor',
          ),
          amountInputFormatters: [_amountFormatter],
          onAmountChanged: _handleAmountChanged,
          supportingText: _fiatText,
          supportingLoading: _fiatLoading,
          maxAmountText: '142.23',
          onUseMax: () {
            _amountController.text = _fixtureAmount;
            _handleAmountChanged(_fixtureAmount);
          },
          emptyAmountLabel: 'Enter Amount',
          semanticLabel: 'Gift card amount input',
        ),
        cardSelector: PaymentLinkCardSelectorRail(
          artworks: PaymentLinkCardArtwork.values,
          selected: _artwork,
          width: _mobilePreviewSize.width,
          itemWidth: 80,
          itemHeight: 60,
          artworkWidth: 76,
          artworkHeight: 56,
          itemGap: AppSpacing.xs,
          selectionInset: EdgeInsets.zero,
          selectionBorderWidth: 2.5,
          selectionBorderRadius: 15,
          selectedCheckSize: 24,
          edgeMaskInset: AppSpacing.sm,
          edgeFadeFraction: 0.3,
          inactiveOpacity: 1,
          onSelected: (artwork) => setState(() => _artwork = artwork),
        ),
        onBack: _noop,
        onContinue: _hasPositiveAmount
            ? () => _showStep(_MobilePaymentLinkStep.message)
            : null,
      ),
      _MobilePaymentLinkStep.message => PaymentLinkMessageMobileView(
        card: PaymentLinkGiftCard(
          artwork: _artwork,
          cardWidth: _cardWidth,
          cardHeight: _cardHeight,
          showBack: true,
          messageController: _messageController,
          messageFocusNode: _messageFocusNode,
          messageEditorKey: const ValueKey(
            'mobile_payment_link_interactive_message_editor',
          ),
          messageInputFormatters: [
            LengthLimitingTextInputFormatter(
              PaymentLinkPresentation.maxMessageCharacters,
            ),
          ],
          onMessageChanged: (_) => setState(() {}),
          onDeleteMessage: _messageController.text.isEmpty
              ? null
              : _clearMessage,
          semanticLabel: 'Gift card message input',
        ),
        onBack: () => _showStep(_MobilePaymentLinkStep.amount),
        onSkip: () => _showStep(_MobilePaymentLinkStep.review),
        onContinue: _messageFitsPayload && _messageController.text.isNotEmpty
            ? () => _showStep(_MobilePaymentLinkStep.review)
            : null,
        errorText: _messageFitsPayload
            ? null
            : 'This message is too large. Try using fewer complex emoji.',
      ),
      _MobilePaymentLinkStep.review => PaymentLinkReviewMobileView(
        card: PaymentLinkGiftCard(
          artwork: _artwork,
          cardWidth: _cardWidth,
          cardHeight: _cardHeight,
          amountText: _amountController.text,
          showCaret: false,
        ),
        onBack: () => _showStep(_MobilePaymentLinkStep.message),
        cardAmountText: '${_amountController.text} ZEC',
        cardFeeText: _fixtureFee,
        totalAmountText: '${(_parsedAmount + 0.04).toStringAsFixed(2)} ZEC',
        onFeeHelp: _noop,
      ),
    };
  }

  double get _parsedAmount {
    final raw = _amountController.text;
    return double.tryParse(raw.startsWith('.') ? '0$raw' : raw) ?? 0;
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

void _noop() {}
void _ignoreArtwork(PaymentLinkCardArtwork _) {}
