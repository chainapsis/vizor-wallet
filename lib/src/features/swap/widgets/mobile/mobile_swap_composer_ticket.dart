import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../models/swap_address_formatting.dart';
import '../../models/swap_fiat_amount.dart';
import '../../models/swap_models.dart';
import '../swap_asset_icon.dart';

/// Mobile swap composer ticket — Figma `Swap` (4686:101421): the white
/// rounded wrapper holding the pay card (base fill), the inverse switch
/// button on the card boundary, and the transparent receive card. The
/// serif amount, the ⇅ fiat line, and the in-card address chip follow
/// the redesigned card anatomy; the "You pay/You receive" labels render
/// only while that side is empty, per the filled frames (4697:106414).
///
/// Input semantics mirror [SwapComposerPanel] one-to-one — controllers
/// synced from state, fiat/token mode per side, exact-input vs
/// exact-output via which field is edited.
class MobileSwapComposerTicket extends StatefulWidget {
  const MobileSwapComposerTicket({
    required this.state,
    required this.onAmountChanged,
    required this.onAmountFiatChanged,
    required this.onReceiveAmountChanged,
    required this.onReceiveAmountFiatChanged,
    required this.onToggleFiatInputMode,
    required this.onToggleDirection,
    required this.onOpenExternalAssetPicker,
    required this.onOpenDestinationAddress,
    required this.onUseMaxZecAmount,
    required this.zecAvailableText,
    super.key,
  });

  final SwapState state;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onAmountFiatChanged;
  final ValueChanged<String> onReceiveAmountChanged;
  final ValueChanged<String> onReceiveAmountFiatChanged;
  final ValueChanged<SwapAmountInputSide> onToggleFiatInputMode;
  final VoidCallback onToggleDirection;
  final VoidCallback onOpenExternalAssetPicker;
  final VoidCallback onOpenDestinationAddress;
  final VoidCallback onUseMaxZecAmount;
  final String zecAvailableText;

  @override
  State<MobileSwapComposerTicket> createState() =>
      _MobileSwapComposerTicketState();
}

class _MobileSwapComposerTicketState extends State<MobileSwapComposerTicket> {
  late final TextEditingController _amountController;
  late final TextEditingController _receiveAmountController;
  late final FocusNode _amountFocusNode;
  late final FocusNode _receiveAmountFocusNode;

  // Figma card anatomy: 20px vertical padding, 17px title line (only
  // while the side is empty), 60px amount row, 32px bottom row.
  static const _cardVerticalPadding = 20.0;
  static const _titleRowHeight = 17.0;
  static const _amountRowHeight = 60.0;
  static const _bottomRowHeight = 32.0;
  static const _cardGap = 16.0;
  static const _switchButtonSize = 52.0; // 40 + 6px ground ring.

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _payInputText(widget.state),
    );
    _receiveAmountController = TextEditingController(
      text: _receiveInputText(widget.state),
    );
    _amountFocusNode = FocusNode(debugLabel: 'MobileSwapPayAmount');
    _receiveAmountFocusNode = FocusNode(debugLabel: 'MobileSwapReceiveAmount');
    _amountFocusNode.addListener(_handleAmountFocusChanged);
    _receiveAmountFocusNode.addListener(_handleAmountFocusChanged);
  }

  @override
  void didUpdateWidget(covariant MobileSwapComposerTicket oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_amountController, _payInputText(widget.state));
    _syncController(_receiveAmountController, _receiveInputText(widget.state));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _receiveAmountController.dispose();
    _amountFocusNode.removeListener(_handleAmountFocusChanged);
    _receiveAmountFocusNode.removeListener(_handleAmountFocusChanged);
    _amountFocusNode.dispose();
    _receiveAmountFocusNode.dispose();
    super.dispose();
  }

  void _handleAmountFocusChanged() => setState(() {});

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String _payInputText(SwapState state) {
    return state.amountInputMode == SwapAmountInputMode.fiat
        ? state.amountFiatText
        : state.amountText;
  }

  String _receiveInputText(SwapState state) {
    return state.receiveAmountInputMode == SwapAmountInputMode.fiat
        ? state.receiveFiatText
        : state.receiveAmountText;
  }

  double _cardHeight({required bool showTitle}) {
    return _cardVerticalPadding * 2 +
        (showTitle ? _titleRowHeight : 0) +
        _amountRowHeight +
        _bottomRowHeight;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = widget.state;
    final sendsZec = state.direction.sendsZec;
    final payInputIsFiat = state.amountInputMode == SwapAmountInputMode.fiat;
    final receiveInputIsFiat =
        state.receiveAmountInputMode == SwapAmountInputMode.fiat;
    final targetDirection = state.direction.toggled;

    final payActive =
        _amountFocusNode.hasFocus ||
        (!_receiveAmountFocusNode.hasFocus &&
            state.quoteMode == SwapQuoteMode.exactInput);
    final receiveActive = !payActive;

    final payEmpty = _payInputText(state).trim().isEmpty;
    final receiveEmpty = _receiveInputText(state).trim().isEmpty;

    final payCard = _SwapCard(
      filled: true,
      showTitle: payEmpty,
      title: 'You pay',
      titleTrailing: sendsZec && payEmpty
          ? _MaxAmountTrigger(
              availableText: widget.zecAvailableText,
              loading: state.maxAmountLoading,
              errorText: state.maxAmountError,
              onTap: widget.onUseMaxZecAmount,
            )
          : null,
      amount: _SwapAmountInput(
        key: const ValueKey('swap_amount_field'),
        controller: _amountController,
        focusNode: _amountFocusNode,
        onChanged: payInputIsFiat
            ? widget.onAmountFiatChanged
            : widget.onAmountChanged,
        prefixText: payInputIsFiat ? r'$' : null,
        maxFractionDigits: payInputIsFiat
            ? null
            : state.direction.fromAsset(state.externalAsset).decimals,
      ),
      asset: sendsZec
          ? const _CurrencyPicker(asset: SwapAsset.zec, label: 'Zcash')
          : _CurrencyPicker(
              key: const ValueKey('swap_external_asset_selector'),
              asset: state.externalAsset,
              label: state.externalAsset.chainLabel,
              showChainBadge: true,
              onTap: widget.onOpenExternalAssetPicker,
            ),
      fiat: _FiatModeToggle(
        text: _amountMetaText(
          state,
          asset: state.direction.fromAsset(state.externalAsset),
          tokenAmountText: state.amountText,
          inputMode: state.amountInputMode,
        ),
        showModeIcon: payActive,
        active: payInputIsFiat,
        strong: payActive,
        onTap: () => widget.onToggleFiatInputMode(SwapAmountInputSide.pay),
      ),
      addressChip: sendsZec
          ? null
          : _AddressChip(
              value: state.destinationText,
              emptyText: 'Add refund address...',
              onTap: widget.onOpenDestinationAddress,
            ),
    );

    final receiveCard = _SwapCard(
      filled: false,
      showTitle: receiveEmpty,
      title: 'You receive',
      amount: _SwapAmountInput(
        key: const ValueKey('swap_receive_amount_field'),
        controller: _receiveAmountController,
        focusNode: _receiveAmountFocusNode,
        onChanged: receiveInputIsFiat
            ? widget.onReceiveAmountFiatChanged
            : widget.onReceiveAmountChanged,
        prefixText: receiveInputIsFiat ? r'$' : null,
        maxFractionDigits: receiveInputIsFiat
            ? null
            : state.direction.toAsset(state.externalAsset).decimals,
      ),
      asset: sendsZec
          ? _CurrencyPicker(
              key: const ValueKey('swap_external_asset_selector'),
              asset: state.externalAsset,
              label: state.externalAsset.chainLabel,
              showChainBadge: true,
              onTap: widget.onOpenExternalAssetPicker,
            )
          : const _CurrencyPicker(asset: SwapAsset.zec, label: 'Zcash'),
      fiat: _FiatModeToggle(
        text: _amountMetaText(
          state,
          asset: state.direction.toAsset(state.externalAsset),
          tokenAmountText: state.receiveAmountText,
          inputMode: state.receiveAmountInputMode,
        ),
        showModeIcon: receiveActive,
        active: receiveInputIsFiat,
        strong: receiveActive,
        onTap: () => widget.onToggleFiatInputMode(SwapAmountInputSide.receive),
      ),
      addressChip: sendsZec
          ? _AddressChip(
              value: state.destinationText,
              emptyText: 'Add recipient address...',
              onTap: widget.onOpenDestinationAddress,
            )
          : null,
    );

    final payCardHeight = _cardHeight(showTitle: payEmpty);
    final switchButtonTop =
        payCardHeight + _cardGap / 2 - _switchButtonSize / 2;

    return Container(
      key: const ValueKey('swap_compact_ticket'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              payCard,
              const SizedBox(height: _cardGap),
              receiveCard,
            ],
          ),
          Positioned(
            top: switchButtonTop,
            left: 0,
            right: 0,
            child: Center(
              child: _SwapDirectionButton(
                key: ValueKey('swap_direction_${targetDirection.name}'),
                onTap: widget.onToggleDirection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapCard extends StatelessWidget {
  const _SwapCard({
    required this.filled,
    required this.showTitle,
    required this.title,
    required this.amount,
    required this.asset,
    required this.fiat,
    this.titleTrailing,
    this.addressChip,
  });

  /// Pay card carries the base fill; the receive card stays on the
  /// wrapper's white.
  final bool filled;
  final bool showTitle;
  final String title;
  final Widget amount;
  final Widget asset;
  final Widget fiat;
  final Widget? titleTrailing;
  final Widget? addressChip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: _MobileSwapComposerTicketState._cardVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: filled ? colors.background.base : null,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            SizedBox(
              height: _MobileSwapComposerTicketState._titleRowHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                  ),
                  if (titleTrailing != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    titleTrailing!,
                  ],
                ],
              ),
            ),
          SizedBox(
            height: _MobileSwapComposerTicketState._amountRowHeight,
            child: Row(
              children: [
                Expanded(child: amount),
                const SizedBox(width: AppSpacing.xs),
                asset,
              ],
            ),
          ),
          SizedBox(
            height: _MobileSwapComposerTicketState._bottomRowHeight,
            child: Row(
              children: [
                Expanded(child: fiat),
                if (addressChip != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  addressChip!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapAmountInput extends StatelessWidget {
  const _SwapAmountInput({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.prefixText,
    this.maxFractionDigits,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String? prefixText;
  final int? maxFractionDigits;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle = AppTypography.displayLarge.copyWith(
      color: colors.text.accent,
    );
    return Row(
      children: [
        if (prefixText != null) Text(prefixText!, style: valueStyle),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              _DecimalAmountInputFormatter(
                maxFractionDigits: maxFractionDigits,
              ),
            ],
            style: valueStyle,
            cursorColor: colors.text.accent,
            cursorWidth: 2,
            cursorRadius: const Radius.circular(AppRadii.full),
            decoration: InputDecoration.collapsed(
              // The empty card renders a solid "0", not a greyed
              // placeholder — Figma 4686:101443.
              hintText: '0',
              hintStyle: valueStyle,
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({
    required this.asset,
    required this.label,
    this.showChainBadge = false,
    this.onTap,
    super.key,
  });

  final SwapAsset asset;
  final String label;
  final bool showChainBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwapAssetIcon(
          asset: asset,
          selected: true,
          size: 32,
          showChainBadge: showChainBadge,
        ),
        const SizedBox(width: AppSpacing.s),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 72),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                asset.symbol,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

class _FiatModeToggle extends StatelessWidget {
  const _FiatModeToggle({
    required this.text,
    required this.showModeIcon,
    required this.active,
    required this.strong,
    required this.onTap,
  });

  final String text;
  final bool showModeIcon;

  /// Fiat input mode engaged (crimson mode icon).
  final bool active;

  /// The side currently driving the quote renders its value semibold —
  /// Figma pay "$0" Label M Semibold vs receive Label M Regular.
  final bool strong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showModeIcon) ...[
            AppIcon(
              AppIcons.doubleArrowVertical,
              key: const ValueKey('swap_fiat_value_mode_icon'),
              size: AppIconSize.medium,
              color: active ? colors.icon.brandCrimson : colors.icon.muted,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
    if (!showModeIcon) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({
    required this.value,
    required this.emptyText,
    required this.onTap,
  });

  final String value;
  final String emptyText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trimmed = value.trim();
    final hasValue = trimmed.isNotEmpty;
    return GestureDetector(
      key: const ValueKey('swap_address_summary'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: _MobileSwapComposerTicketState._bottomRowHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.wallet, size: 20, color: colors.icon.accent),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                hasValue
                    ? compactSwapAddress(
                        trimmed,
                        prefixLength: 6,
                        suffixLength: 4,
                        separator: ' … ',
                      )
                    : emptyText,
                key: const ValueKey('swap_destination_value'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: hasValue ? colors.text.accent : colors.text.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaxAmountTrigger extends StatelessWidget {
  const _MaxAmountTrigger({
    required this.availableText,
    required this.loading,
    required this.errorText,
    required this.onTap,
  });

  final String availableText;
  final bool loading;
  final String? errorText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = errorText != null;
    return GestureDetector(
      key: const ValueKey('swap_max_amount_button'),
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : onTap,
      child: Text(
        errorText ?? 'Max: $availableText',
        key: const ValueKey('swap_available_balance'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelMedium.copyWith(
          color: hasError ? colors.text.destructive : colors.text.secondary,
        ),
      ),
    );
  }
}

class _SwapDirectionButton extends StatelessWidget {
  const _SwapDirectionButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: _MobileSwapComposerTicketState._switchButtonSize,
        height: _MobileSwapComposerTicketState._switchButtonSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.background.inverse,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.background.ground, width: 6),
        ),
        child: AppIcon(
          AppIcons.swapArrows,
          size: 20,
          color: colors.icon.inverse,
        ),
      ),
    );
  }
}

class _DecimalAmountInputFormatter extends TextInputFormatter {
  const _DecimalAmountInputFormatter({this.maxFractionDigits});

  final int? maxFractionDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final max = maxFractionDigits;
    final pattern = max == null
        ? RegExp(r'^\d*(\.\d*)?$')
        : RegExp('^\\d*(\\.\\d{0,$max})?\$');
    if (pattern.hasMatch(text)) return newValue;
    return oldValue;
  }
}

String _amountMetaText(
  SwapState state, {
  required SwapAsset asset,
  required String tokenAmountText,
  required SwapAmountInputMode inputMode,
}) {
  if (inputMode == SwapAmountInputMode.fiat) {
    return swapTokenAmountDisplayText(
      asset: asset,
      tokenAmountText: tokenAmountText,
    );
  }
  return swapFiatDisplayText(state, asset: asset, tokenAmountText: tokenAmountText);
}
