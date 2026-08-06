import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_action.dart';
import 'payment_link_skeleton.dart';

/// Artwork choices exported from the Figma `_CARD BG IMAGE` component set.
enum PaymentLinkCardArtwork {
  knight('payment_link_card_knight.png', 'Knight'),
  chestLava('payment_link_card_chest_lava.png', 'Chest in lava cave'),
  chestCave('payment_link_card_chest_cave.png', 'Chest in crystal cave'),
  dragon('payment_link_card_dragon.png', 'Dragon'),
  knightMagic('payment_link_card_knight_magic.png', 'Magic knight'),
  gandalf('payment_link_card_gandalf.png', 'Wizard'),
  crystal('payment_link_card_crystal.png', 'Crystal'),
  diamond('payment_link_card_diamond.png', 'Diamond'),
  ruby('payment_link_card_ruby.png', 'Ruby'),
  coin('payment_link_card_coin.png', 'Zcash coin'),
  gift('payment_link_card_gift.png', 'Gift box');

  const PaymentLinkCardArtwork(this.fileName, this.semanticLabel);

  final String fileName;
  final String semanticLabel;

  String get assetPath => 'assets/illustrations/payment_links/$fileName';

  String get protocolId => name;

  static PaymentLinkCardArtwork fromProtocolId(String? id) {
    for (final artwork in values) {
      if (artwork.protocolId == id) return artwork;
    }
    return gift;
  }
}

/// Figma `_CARD` presentation component.
///
/// [amountText] selects a static front state: null renders the default prompt,
/// an empty string renders the active caret state, and a non-empty string
/// renders the value state. Supplying [amountController] and [amountFocusNode]
/// switches that row to a real desktop text field with native selection and a
/// blinking caret. [showBack] switches to the message side; supplying
/// [messageController] and [messageFocusNode] makes that side editable.
class PaymentLinkGiftCard extends StatefulWidget {
  const PaymentLinkGiftCard({
    required this.artwork,
    this.amountText,
    this.amountController,
    this.amountFocusNode,
    this.amountEditorKey,
    this.amountInputFormatters = const [],
    this.onAmountChanged,
    this.maxAmountText,
    this.onUseMax,
    this.supportingText,
    this.supportingLoading = false,
    this.currencySymbol = 'ZEC',
    this.emptyAmountLabel = 'Enter amount',
    this.showCaret = true,
    this.showBack = false,
    this.message = '',
    this.messageController,
    this.messageFocusNode,
    this.messageEditorKey,
    this.messageInputFormatters = const [],
    this.onMessageChanged,
    this.emptyMessageLabel = 'Start typing',
    this.maxMessageLength = 128,
    this.messageCharacterCount,
    this.onTap,
    this.onDeleteMessage,
    this.semanticLabel,
    super.key,
  }) : assert(maxMessageLength > 0),
       assert(
         (amountController == null) == (amountFocusNode == null),
         'amountController and amountFocusNode must be supplied together.',
       ),
       assert(
         amountController == null || !showBack,
         'The amount editor is only available on the front of the card.',
       ),
       assert(
         (messageController == null) == (messageFocusNode == null),
         'messageController and messageFocusNode must be supplied together.',
       ),
       assert(
         messageController == null || showBack,
         'The message editor is only available on the back of the card.',
       ),
       assert(
         messageCharacterCount == null ||
             (messageCharacterCount >= 0 &&
                 messageCharacterCount <= maxMessageLength),
       );

  static const double width = 372;
  static const double height = 253;

  final PaymentLinkCardArtwork artwork;

  /// Null is the default state; empty is active; non-empty is the value state.
  final String? amountText;
  final TextEditingController? amountController;
  final FocusNode? amountFocusNode;
  final Key? amountEditorKey;
  final List<TextInputFormatter> amountInputFormatters;
  final ValueChanged<String>? onAmountChanged;
  final String? maxAmountText;
  final VoidCallback? onUseMax;
  final String? supportingText;
  final bool supportingLoading;
  final String currencySymbol;
  final String emptyAmountLabel;
  final bool showCaret;

  final bool showBack;
  final String message;
  final TextEditingController? messageController;
  final FocusNode? messageFocusNode;
  final Key? messageEditorKey;
  final List<TextInputFormatter> messageInputFormatters;
  final ValueChanged<String>? onMessageChanged;
  final String emptyMessageLabel;
  final int maxMessageLength;
  final int? messageCharacterCount;

  final VoidCallback? onTap;
  final VoidCallback? onDeleteMessage;
  final String? semanticLabel;

  bool get hasAmountEditor =>
      amountController != null && amountFocusNode != null;
  bool get hasMessageEditor =>
      messageController != null && messageFocusNode != null;

  @override
  State<PaymentLinkGiftCard> createState() => _PaymentLinkGiftCardState();
}

class _PaymentLinkGiftCardState extends State<PaymentLinkGiftCard> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    widget.amountFocusNode?.addListener(_handleAmountFocusChanged);
    widget.amountController?.addListener(_handleAmountControllerChanged);
    widget.messageFocusNode?.addListener(_handleMessageFocusChanged);
    widget.messageController?.addListener(_handleMessageControllerChanged);
  }

  @override
  void didUpdateWidget(covariant PaymentLinkGiftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amountFocusNode != widget.amountFocusNode) {
      oldWidget.amountFocusNode?.removeListener(_handleAmountFocusChanged);
      widget.amountFocusNode?.addListener(_handleAmountFocusChanged);
    }
    if (oldWidget.amountController != widget.amountController) {
      oldWidget.amountController?.removeListener(
        _handleAmountControllerChanged,
      );
      widget.amountController?.addListener(_handleAmountControllerChanged);
    }
    if (oldWidget.messageFocusNode != widget.messageFocusNode) {
      oldWidget.messageFocusNode?.removeListener(_handleMessageFocusChanged);
      widget.messageFocusNode?.addListener(_handleMessageFocusChanged);
    }
    if (oldWidget.messageController != widget.messageController) {
      oldWidget.messageController?.removeListener(
        _handleMessageControllerChanged,
      );
      widget.messageController?.addListener(_handleMessageControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.amountFocusNode?.removeListener(_handleAmountFocusChanged);
    widget.amountController?.removeListener(_handleAmountControllerChanged);
    widget.messageFocusNode?.removeListener(_handleMessageFocusChanged);
    widget.messageController?.removeListener(_handleMessageControllerChanged);
    super.dispose();
  }

  void _handleAmountFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleAmountControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleMessageFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleMessageControllerChanged() {
    if (mounted) setState(() {});
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _activateEditor() {
    final focusNode = widget.hasAmountEditor
        ? widget.amountFocusNode!
        : widget.messageFocusNode!;
    if (!focusNode.hasFocus) {
      final controller = widget.hasAmountEditor
          ? widget.amountController!
          : widget.messageController!;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      focusNode.requestFocus();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.semanticLabel ??
        (widget.showBack
            ? 'Gift card message'
            : 'Gift card, ${widget.artwork.semanticLabel} design');
    final card = SizedBox(
      width: PaymentLinkGiftCard.width,
      height: PaymentLinkGiftCard.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.showBack)
              const _PaymentLinkGiftCardBackBackground()
            else
              _PaymentLinkGiftCardFrontBackground(artwork: widget.artwork),
            if (widget.showBack)
              _PaymentLinkGiftCardBackContent(
                message: widget.message,
                messageController: widget.messageController,
                messageFocusNode: widget.messageFocusNode,
                messageEditorKey: widget.messageEditorKey,
                messageInputFormatters: widget.messageInputFormatters,
                onMessageChanged: widget.onMessageChanged,
                emptyMessageLabel: widget.emptyMessageLabel,
                maxMessageLength: widget.maxMessageLength,
                messageCharacterCount: widget.messageCharacterCount,
                onDeleteMessage: widget.onDeleteMessage,
                semanticLabel: label,
              )
            else
              _PaymentLinkGiftCardFrontContent(
                amountText: widget.amountText,
                amountController: widget.amountController,
                amountFocusNode: widget.amountFocusNode,
                amountEditorKey: widget.amountEditorKey,
                amountInputFormatters: widget.amountInputFormatters,
                onAmountChanged: widget.onAmountChanged,
                maxAmountText: widget.maxAmountText,
                onUseMax: widget.onUseMax,
                supportingText: widget.supportingText,
                supportingLoading: widget.supportingLoading,
                currencySymbol: widget.currencySymbol,
                emptyAmountLabel: widget.emptyAmountLabel,
                semanticLabel: label,
                showCaret: widget.showCaret,
              ),
            const _PaymentLinkGiftCardBorder(),
          ],
        ),
      ),
    );

    if (widget.hasAmountEditor || widget.hasMessageEditor) {
      final editorName = widget.hasAmountEditor ? 'amount' : 'message';
      final focusNode = widget.hasAmountEditor
          ? widget.amountFocusNode!
          : widget.messageFocusNode!;
      final focused = focusNode.hasFocus;
      return MouseRegion(
        key: ValueKey('payment_link_${editorName}_input_mouse_region'),
        cursor: SystemMouseCursors.text,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: _activateEditor,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              card,
              if (_hovered || focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: ValueKey(
                        focused
                            ? 'payment_link_${editorName}_focus_ring'
                            : 'payment_link_${editorName}_hover_ring',
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.xLarge),
                        border: Border.all(
                          color: focused
                              ? context.colors.state.focusRing
                              : context.colors.border.strong,
                          width: focused ? 2 : 1.5,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (widget.onTap == null) {
      return Semantics(image: true, label: label, child: card);
    }
    return PaymentLinkAction(
      onPressed: widget.onTap,
      semanticLabel: label,
      excludeChildSemantics:
          widget.onDeleteMessage == null && widget.onUseMax == null,
      builder: (context, hovered, focused) => Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (hovered || focused)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.xLarge),
                    border: Border.all(
                      color: focused
                          ? context.colors.state.focusRing
                          : context.colors.border.strong,
                      width: focused ? 2 : 1.5,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentLinkGiftCardFrontBackground extends StatelessWidget {
  const _PaymentLinkGiftCardFrontBackground({required this.artwork});

  final PaymentLinkCardArtwork artwork;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          artwork.assetPath,
          fit: BoxFit.cover,
          semanticLabel: artwork.semanticLabel,
        ),
        const DecoratedBox(
          key: ValueKey('payment_link_card_artwork_fade'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xB3000000)],
              stops: [0.48024, 0.73518],
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentLinkGiftCardFrontContent extends StatelessWidget {
  const _PaymentLinkGiftCardFrontContent({
    required this.amountText,
    required this.amountController,
    required this.amountFocusNode,
    required this.amountEditorKey,
    required this.amountInputFormatters,
    required this.onAmountChanged,
    required this.maxAmountText,
    required this.onUseMax,
    required this.supportingText,
    required this.supportingLoading,
    required this.currencySymbol,
    required this.emptyAmountLabel,
    required this.semanticLabel,
    required this.showCaret,
  });

  final String? amountText;
  final TextEditingController? amountController;
  final FocusNode? amountFocusNode;
  final Key? amountEditorKey;
  final List<TextInputFormatter> amountInputFormatters;
  final ValueChanged<String>? onAmountChanged;
  final String? maxAmountText;
  final VoidCallback? onUseMax;
  final String? supportingText;
  final bool supportingLoading;
  final String currencySymbol;
  final String emptyAmountLabel;
  final String semanticLabel;
  final bool showCaret;

  @override
  Widget build(BuildContext context) {
    final cardTextColor = context.colors.text.homeCard;
    final editing = amountController != null && amountFocusNode != null;
    final amount = editing ? amountController!.text : amountText;
    if (!editing && amount == null) {
      return Positioned(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: AppSpacing.md,
        child: Text(
          emptyAmountLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.displayLarge.copyWith(
            color: cardTextColor.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      bottom: AppSpacing.md,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing && amount!.isEmpty && !amountFocusNode!.hasFocus) ...[
            _PaymentLinkAmountTextField(
              key: const ValueKey('payment_link_amount_text_field'),
              editorKey: amountEditorKey,
              controller: amountController!,
              focusNode: amountFocusNode!,
              inputFormatters: amountInputFormatters,
              onChanged: onAmountChanged,
              currencySymbol: currencySymbol,
              emptyAmountLabel: emptyAmountLabel,
              semanticLabel: semanticLabel,
              cardTextColor: cardTextColor,
            ),
          ] else ...[
            if (supportingLoading) ...[
              Semantics(
                label: 'Fiat value loading',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r'$',
                        style: AppTypography.labelLarge.copyWith(
                          color: cardTextColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      PaymentLinkSkeletonBar(
                        key: const ValueKey(
                          'payment_link_fiat_loading_placeholder',
                        ),
                        width: 48,
                        height: 12,
                        colors: [
                          cardTextColor,
                          cardTextColor.withValues(alpha: 0.15),
                        ],
                        shimmerKey: const ValueKey(
                          'payment_link_fiat_loading_shimmer',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s),
            ] else if (supportingText case final supporting?) ...[
              Text(
                supporting,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(color: cardTextColor),
              ),
              const SizedBox(height: AppSpacing.s),
            ] else if (maxAmountText case final maxAmount?) ...[
              if (onUseMax == null)
                Text(
                  'Use max: $maxAmount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: cardTextColor,
                  ),
                )
              else
                PaymentLinkAction(
                  onPressed: onUseMax,
                  semanticLabel: 'Use max: $maxAmount $currencySymbol',
                  builder: (context, hovered, focused) => Text(
                    'Use max: $maxAmount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: cardTextColor,
                      decoration: hovered || focused
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: cardTextColor,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.s),
            ],
            if (editing)
              _PaymentLinkAmountTextField(
                key: const ValueKey('payment_link_amount_text_field'),
                editorKey: amountEditorKey,
                controller: amountController!,
                focusNode: amountFocusNode!,
                inputFormatters: amountInputFormatters,
                onChanged: onAmountChanged,
                currencySymbol: currencySymbol,
                emptyAmountLabel: emptyAmountLabel,
                semanticLabel: semanticLabel,
                cardTextColor: cardTextColor,
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (amount!.isNotEmpty) ...[
                    Flexible(
                      child: Text(
                        amount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.displayLarge.copyWith(
                          color: cardTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (showCaret) ...[
                    Container(
                      width: 3,
                      height: 48,
                      decoration: BoxDecoration(
                        color: cardTextColor,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                    ),
                    if (currencySymbol.isNotEmpty) const SizedBox(width: 10),
                  ],
                  if (currencySymbol.isNotEmpty)
                    _PaymentLinkCurrencyLabel(
                      currencySymbol: currencySymbol,
                      cardTextColor: cardTextColor,
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _PaymentLinkAmountTextField extends StatelessWidget {
  const _PaymentLinkAmountTextField({
    required this.editorKey,
    required this.controller,
    required this.focusNode,
    required this.inputFormatters,
    required this.onChanged,
    required this.currencySymbol,
    required this.emptyAmountLabel,
    required this.semanticLabel,
    required this.cardTextColor,
    super.key,
  });

  final Key? editorKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> inputFormatters;
  final ValueChanged<String>? onChanged;
  final String currencySymbol;
  final String emptyAmountLabel;
  final String semanticLabel;
  final Color cardTextColor;

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    final value = controller.text;
    final style = AppTypography.displayLarge.copyWith(color: cardTextColor);
    final strutStyle = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final showCurrency = focused || value.isNotEmpty;
    final measuredText = value.isEmpty && !focused ? emptyAmountLabel : value;
    final painter = TextPainter(
      text: TextSpan(text: measuredText, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      strutStyle: strutStyle,
    )..layout();
    final maxInputWidth = showCurrency ? 239.0 : 324.0;
    final inputWidth = (painter.width + (focused ? 5 : 0)).clamp(
      3.0,
      maxInputWidth,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: inputWidth,
          height: 48,
          child: MergeSemantics(
            child: Semantics(
              label: semanticLabel,
              child: TextField(
                key: editorKey,
                controller: controller,
                focusNode: focusNode,
                style: style,
                strutStyle: strutStyle,
                cursorColor: cardTextColor,
                cursorWidth: 3,
                cursorHeight: 48,
                cursorRadius: const Radius.circular(AppRadii.full),
                cursorOpacityAnimates: true,
                mouseCursor: SystemMouseCursors.text,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: inputFormatters,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 1,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration.collapsed(
                  hintText: focused ? null : emptyAmountLabel,
                  hintStyle: style.copyWith(
                    color: cardTextColor.withValues(alpha: 0.55),
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        if (showCurrency && currencySymbol.isNotEmpty) ...[
          const SizedBox(width: 10),
          _PaymentLinkCurrencyLabel(
            currencySymbol: currencySymbol,
            cardTextColor: cardTextColor,
          ),
        ],
      ],
    );
  }
}

class _PaymentLinkCurrencyLabel extends StatelessWidget {
  const _PaymentLinkCurrencyLabel({
    required this.currencySymbol,
    required this.cardTextColor,
  });

  final String currencySymbol;
  final Color cardTextColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('payment_link_amount_currency_box'),
      width: 75,
      height: 46,
      child: Transform.translate(
        offset: const Offset(0, 3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            currencySymbol,
            maxLines: 1,
            style: AppTypography.displayLarge.copyWith(
              color: cardTextColor.withValues(alpha: 0.65),
              fontSize: 40,
              height: 48 / 40,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkGiftCardBackBackground extends StatelessWidget {
  const _PaymentLinkGiftCardBackBackground();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.colors.background.brandCrimsonStrong);
  }
}

class _PaymentLinkGiftCardBackContent extends StatelessWidget {
  const _PaymentLinkGiftCardBackContent({
    required this.message,
    required this.messageController,
    required this.messageFocusNode,
    required this.messageEditorKey,
    required this.messageInputFormatters,
    required this.onMessageChanged,
    required this.emptyMessageLabel,
    required this.maxMessageLength,
    required this.messageCharacterCount,
    required this.onDeleteMessage,
    required this.semanticLabel,
  });

  final String message;
  final TextEditingController? messageController;
  final FocusNode? messageFocusNode;
  final Key? messageEditorKey;
  final List<TextInputFormatter> messageInputFormatters;
  final ValueChanged<String>? onMessageChanged;
  final String emptyMessageLabel;
  final int maxMessageLength;
  final int? messageCharacterCount;
  final VoidCallback? onDeleteMessage;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;
    final editing = messageController != null && messageFocusNode != null;
    final displayedMessage = editing ? messageController!.text : message;
    final usedCharacterCount = displayedMessage.characters.length.clamp(
      0,
      maxMessageLength,
    );
    final characterCount =
        messageCharacterCount ?? maxMessageLength - usedCharacterCount;

    return Stack(
      children: [
        Positioned(
          left: 56,
          right: 56,
          top: 46.5,
          height: 160,
          child: editing
              ? _PaymentLinkMessageTextField(
                  editorKey: messageEditorKey,
                  controller: messageController!,
                  focusNode: messageFocusNode!,
                  inputFormatters: messageInputFormatters,
                  onChanged: onMessageChanged,
                  emptyMessageLabel: emptyMessageLabel,
                  maxMessageLength: maxMessageLength,
                  semanticLabel: semanticLabel,
                  cardTextColor: cardTextColor,
                )
              : Center(
                  child: Text(
                    message.isEmpty ? emptyMessageLabel : message,
                    textAlign: TextAlign.center,
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: cardTextColor,
                    ),
                  ),
                ),
        ),
        Positioned(
          left: 20,
          bottom: 20,
          child: Text(
            '$characterCount/$maxMessageLength',
            style: AppTypography.labelLarge.copyWith(
              color: cardTextColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (onDeleteMessage != null)
          Positioned(
            right: AppSpacing.s,
            bottom: AppSpacing.s,
            child: PaymentLinkAction(
              onPressed: onDeleteMessage,
              semanticLabel: 'Delete gift card message',
              builder: (context, _, focused) => SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.background.homeCard,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.trash,
                            size: AppIconSize.medium,
                            color: cardTextColor,
                          ),
                        ),
                      ),
                    ),
                    if (focused)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.state.focusRing,
                                width: 2,
                                strokeAlign: BorderSide.strokeAlignOutside,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PaymentLinkMessageTextField extends StatelessWidget {
  const _PaymentLinkMessageTextField({
    required this.editorKey,
    required this.controller,
    required this.focusNode,
    required this.inputFormatters,
    required this.onChanged,
    required this.emptyMessageLabel,
    required this.maxMessageLength,
    required this.semanticLabel,
    required this.cardTextColor,
  });

  final Key? editorKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> inputFormatters;
  final ValueChanged<String>? onChanged;
  final String emptyMessageLabel;
  final int maxMessageLength;
  final String semanticLabel;
  final Color cardTextColor;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodyMedium.copyWith(color: cardTextColor);
    return Center(
      child: MergeSemantics(
        child: Semantics(
          label: semanticLabel,
          child: TextField(
            key: editorKey,
            controller: controller,
            focusNode: focusNode,
            style: style,
            cursorColor: cardTextColor,
            cursorWidth: 2,
            cursorRadius: const Radius.circular(AppRadii.full),
            cursorOpacityAnimates: true,
            mouseCursor: SystemMouseCursors.text,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            inputFormatters: [
              ...inputFormatters,
              LengthLimitingTextInputFormatter(maxMessageLength),
            ],
            minLines: 1,
            maxLines: 7,
            textAlign: TextAlign.center,
            decoration: InputDecoration.collapsed(
              hintText: emptyMessageLabel,
              hintStyle: style,
            ),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkGiftCardBorder extends StatelessWidget {
  const _PaymentLinkGiftCardBorder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xLarge),
          border: Border.all(
            color: context.colors.text.homeCard.withValues(alpha: 0.55),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}
