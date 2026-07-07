import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/config/fiat_currencies.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../address_book/widgets/contact_name_inline.dart';
import '../models/swap_address_formatting.dart';
import '../models/swap_fiat_amount.dart';
import '../models/swap_models.dart';
import 'swap_asset_icon.dart';

class SwapComposerPanel extends StatefulWidget {
  const SwapComposerPanel({
    required this.state,
    this.width = 396,
    required this.onAmountChanged,
    required this.onAmountFiatChanged,
    required this.onReceiveAmountChanged,
    required this.onReceiveAmountFiatChanged,
    required this.onToggleFiatInputMode,
    required this.onToggleDirection,
    required this.onOpenExternalAssetPicker,
    required this.onOpenDestinationAddress,
    required this.onOpenSlippageSettings,
    required this.onUseMaxZecAmount,
    required this.assetSelectorOpen,
    required this.slippageSettingsOpen,
    required this.zecAvailableText,
    required this.zecAvailableZatoshi,
    this.destinationContactName,
    this.fiatDisplay = kUsdFiatDisplay,
    super.key,
  });

  final SwapState state;

  /// Address-book label for the current destination address, shown in the
  /// address chip instead of the truncated address when set.
  final String? destinationContactName;

  /// Panel width — 396 on the desktop pane; mobile callers can pass their
  /// content width.
  final double width;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onAmountFiatChanged;
  final ValueChanged<String> onReceiveAmountChanged;
  final ValueChanged<String> onReceiveAmountFiatChanged;
  final ValueChanged<SwapAmountInputSide> onToggleFiatInputMode;
  final VoidCallback onToggleDirection;
  final VoidCallback onOpenExternalAssetPicker;
  final VoidCallback onOpenDestinationAddress;
  final VoidCallback onOpenSlippageSettings;
  final VoidCallback onUseMaxZecAmount;
  final bool assetSelectorOpen;
  final bool slippageSettingsOpen;
  final String zecAvailableText;
  final BigInt zecAvailableZatoshi;

  /// Selected display currency + USD conversion for quote fiat values.
  final FiatDisplay fiatDisplay;

  @override
  State<SwapComposerPanel> createState() => _SwapComposerPanelState();
}

class _SwapComposerPanelState extends State<SwapComposerPanel> {
  late final TextEditingController _amountController;
  late final TextEditingController _receiveAmountController;
  late final FocusNode _amountFocusNode;
  late final FocusNode _receiveAmountFocusNode;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _payInputText(widget.state),
    );
    _receiveAmountController = TextEditingController(
      text: _receiveInputText(widget.state),
    );
    _amountFocusNode = FocusNode(debugLabel: 'SwapPayAmount');
    _receiveAmountFocusNode = FocusNode(debugLabel: 'SwapReceiveAmount');
    _amountFocusNode.addListener(_handleAmountFocusChanged);
    _receiveAmountFocusNode.addListener(_handleAmountFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SwapComposerPanel oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final sendsZec = state.direction.sendsZec;
    final payInputIsFiat = state.amountInputMode == SwapAmountInputMode.fiat;
    final receiveInputIsFiat =
        state.receiveAmountInputMode == SwapAmountInputMode.fiat;
    final targetDirection = state.direction.toggled;
    final rateText = _rateTextForState(state);
    final quoteError = state.quoteAmountPrecisionError ?? state.quoteError;
    final zecAmountOverAvailable = _zecAmountOverAvailable(
      state,
      widget.zecAvailableZatoshi,
    );

    final payActive =
        _amountFocusNode.hasFocus ||
        (!_receiveAmountFocusNode.hasFocus &&
            state.quoteMode == SwapQuoteMode.exactInput);
    final receiveActive =
        _receiveAmountFocusNode.hasFocus ||
        (!_amountFocusNode.hasFocus &&
            state.quoteMode == SwapQuoteMode.exactOutput);
    final ticket = _SwapTicketShell(
      key: const ValueKey('swap_compact_ticket'),
      payCard: _SwapAmountCard(
        label: 'You pay',
        active: payActive,
        amount: _SwapAmountInput(
          key: const ValueKey('swap_amount_field'),
          controller: _amountController,
          focusNode: _amountFocusNode,
          onChanged: payInputIsFiat
              ? widget.onAmountFiatChanged
              : widget.onAmountChanged,
          hintText: payInputIsFiat ? '0.00' : '0',
          prefixText: payInputIsFiat
              ? widget.fiatDisplay.displayCurrency.symbol
              : null,
          maxFractionDigits: payInputIsFiat
              ? null
              : state.direction.fromAsset(state.externalAsset).decimals,
        ),
        asset: sendsZec
            ? const _TokenPill(asset: SwapAsset.zec, label: 'Zcash')
            : _ExternalAssetButton(
                selected: state.externalAsset,
                open: widget.assetSelectorOpen,
                onTap: widget.onOpenExternalAssetPicker,
              ),
        titleTrailing: sendsZec
            ? _MaxAmountTrigger(
                availableText: widget.zecAvailableText,
                loading: state.maxAmountLoading,
                errorText: state.maxAmountError,
                balanceExceeded: zecAmountOverAvailable,
                onTap: widget.onUseMaxZecAmount,
              )
            : null,
        footer: sendsZec
            ? _SwapCardFooter(
                leading: _SwapFiatValueText(
                  text: _amountMetaText(
                    state,
                    asset: SwapAsset.zec,
                    tokenAmountText: state.amountText,
                    inputMode: state.amountInputMode,
                    fiatDisplay: widget.fiatDisplay,
                  ),
                  showModeIcon: payActive,
                  active: payInputIsFiat,
                  emphasized: true,
                  onTap: () =>
                      widget.onToggleFiatInputMode(SwapAmountInputSide.pay),
                ),
              )
            : _SwapCardFooter(
                leading: _SwapFiatValueText(
                  text: _amountMetaText(
                    state,
                    asset: state.externalAsset,
                    tokenAmountText: state.amountText,
                    inputMode: state.amountInputMode,
                    fiatDisplay: widget.fiatDisplay,
                  ),
                  showModeIcon: payActive,
                  active: payInputIsFiat,
                  emphasized: true,
                  onTap: () =>
                      widget.onToggleFiatInputMode(SwapAmountInputSide.pay),
                ),
                trailing: _AddressTrigger(
                  value: state.destinationText,
                  contactName: widget.destinationContactName,
                  emptyText: 'Add refund address...',
                  onTap: widget.onOpenDestinationAddress,
                ),
              ),
      ),
      receiveCard: _SwapAmountCard(
        label: 'You receive',
        active: receiveActive,
        amount: _SwapAmountInput(
          key: const ValueKey('swap_receive_amount_field'),
          controller: _receiveAmountController,
          focusNode: _receiveAmountFocusNode,
          onChanged: receiveInputIsFiat
              ? widget.onReceiveAmountFiatChanged
              : widget.onReceiveAmountChanged,
          hintText: receiveInputIsFiat ? '0.00' : '0',
          prefixText: receiveInputIsFiat
              ? widget.fiatDisplay.displayCurrency.symbol
              : null,
          maxFractionDigits: receiveInputIsFiat
              ? null
              : state.direction.toAsset(state.externalAsset).decimals,
        ),
        asset: sendsZec
            ? _ExternalAssetButton(
                selected: state.externalAsset,
                open: widget.assetSelectorOpen,
                onTap: widget.onOpenExternalAssetPicker,
              )
            : const _TokenPill(asset: SwapAsset.zec, label: 'Zcash'),
        footer: sendsZec
            ? _SwapCardFooter(
                leading: _SwapFiatValueText(
                  text: _amountMetaText(
                    state,
                    asset: state.externalAsset,
                    tokenAmountText: state.receiveAmountText,
                    inputMode: state.receiveAmountInputMode,
                    fiatDisplay: widget.fiatDisplay,
                  ),
                  showModeIcon: receiveActive,
                  active: receiveInputIsFiat,
                  onTap: () =>
                      widget.onToggleFiatInputMode(SwapAmountInputSide.receive),
                ),
                trailing: _AddressTrigger(
                  value: state.destinationText,
                  contactName: widget.destinationContactName,
                  emptyText: 'Add recipient address...',
                  onTap: widget.onOpenDestinationAddress,
                ),
              )
            : _SwapCardFooter(
                leading: _SwapFiatValueText(
                  text: _amountMetaText(
                    state,
                    asset: SwapAsset.zec,
                    tokenAmountText: state.receiveAmountText,
                    inputMode: state.receiveAmountInputMode,
                    fiatDisplay: widget.fiatDisplay,
                  ),
                  showModeIcon: receiveActive,
                  active: receiveInputIsFiat,
                  onTap: () =>
                      widget.onToggleFiatInputMode(SwapAmountInputSide.receive),
                ),
              ),
      ),
      targetDirection: targetDirection,
      onToggleDirection: widget.onToggleDirection,
    );

    return Center(
      child: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ticket,
            const SizedBox(height: AppSpacing.sm),
            _SwapTicketFooter(
              rateText: rateText,
              slippageBps: state.slippageBps,
              settingsOpen: widget.slippageSettingsOpen,
              settingsEnabled: !state.quoteLoading,
              onSettingsTap: widget.onOpenSlippageSettings,
            ),
            if (quoteError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _QuoteErrorMessage(message: quoteError),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwapTicketFooter extends StatelessWidget {
  const _SwapTicketFooter({
    required this.rateText,
    required this.slippageBps,
    required this.settingsOpen,
    required this.settingsEnabled,
    required this.onSettingsTap,
  });

  final String rateText;
  final int slippageBps;
  final bool settingsOpen;
  final bool settingsEnabled;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('swap_settings_row'),
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _SwapRateInline(rateText: rateText)),
          const SizedBox(width: 8),
          _SlippageControl(
            label: formatSwapSlippage(slippageBps),
            selected: settingsOpen,
            enabled: settingsEnabled,
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _SwapRateInline extends StatelessWidget {
  const _SwapRateInline({required this.rateText});

  final String rateText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('swap_rate_line'),
      children: [
        AppIcon(
          AppIcons.swapArrows,
          size: 20,
          color: colors.icon.muted.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            rateText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SwapTicketShell extends StatelessWidget {
  const _SwapTicketShell({
    required this.payCard,
    required this.receiveCard,
    required this.targetDirection,
    required this.onToggleDirection,
    super.key,
  });

  final Widget payCard;
  final Widget receiveCard;
  final SwapDirection targetDirection;
  final VoidCallback onToggleDirection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 336,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(28),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(children: [payCard, const SizedBox(height: 16), receiveCard]),
          Positioned(
            top: 147,
            left: 0,
            right: 0,
            child: Center(
              child: _SwapDirectionButton(
                key: ValueKey('swap_direction_${targetDirection.name}'),
                onTap: onToggleDirection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapAmountCard extends StatelessWidget {
  const _SwapAmountCard({
    required this.label,
    required this.active,
    required this.amount,
    required this.asset,
    required this.footer,
    this.titleTrailing,
  });

  final String label;
  final bool active;
  final Widget amount;
  final Widget asset;
  final Widget footer;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      height: 156,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      decoration: BoxDecoration(
        color: active ? colors.background.base : null,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.muted,
                    ),
                  ),
                ),
                if (titleTrailing != null) ...[
                  const SizedBox(width: 8),
                  titleTrailing!,
                ],
              ],
            ),
          ),
          SizedBox(
            height: 60,
            child: Row(
              children: [
                Expanded(child: amount),
                const SizedBox(width: 8),
                asset,
              ],
            ),
          ),
          footer,
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
    required this.hintText,
    this.prefixText,
    this.maxFractionDigits,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hintText;
  final String? prefixText;
  final int? maxFractionDigits;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle = appSerifDisplayStyle(color: colors.text.accent);
    return Row(
      children: [
        if (prefixText != null) ...[
          // The fiat '$' prefix renders one step larger than the 32px amount
          // (YoungSerif-Regular 36/44, letter-spacing -0.72) in the secondary
          // text color, while the digits stay accent.
          Text(
            prefixText!,
            style: valueStyle.copyWith(
              fontSize: 36,
              height: 44 / 36,
              letterSpacing: -0.72,
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              // The decimal-pad key follows the device locale, so map a
              // comma to the period the validator below expects.
              const CommaToDotInputFormatter(),
              _DecimalAmountInputFormatter(
                maxFractionDigits: maxFractionDigits,
              ),
            ],
            style: valueStyle,
            cursorColor: colors.text.accent,
            decoration: InputDecoration.collapsed(
              hintText: hintText,
              hintStyle: valueStyle.copyWith(color: colors.text.disabled),
            ),
          ),
        ),
      ],
    );
  }
}

class _SwapCardFooter extends StatelessWidget {
  const _SwapCardFooter({required this.leading, this.trailing});

  final Widget leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(child: leading),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _SwapFiatValueText extends StatelessWidget {
  const _SwapFiatValueText({
    required this.text,
    this.showModeIcon = false,
    this.active = false,
    this.emphasized = false,
    this.onTap,
  });

  final String text;
  final bool showModeIcon;
  final bool active;
  final bool emphasized;
  final VoidCallback? onTap;

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
              size: 16,
              color: active ? colors.icon.brandCrimson : colors.icon.muted,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null || !showModeIcon) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _AddressTrigger extends StatelessWidget {
  const _AddressTrigger({
    required this.value,
    required this.emptyText,
    required this.onTap,
    this.contactName,
  });

  final String value;
  final String emptyText;
  final VoidCallback onTap;

  /// Saved-contact label for [value]; when set, the chip shows the name
  /// (with the matched-contact user icon) instead of the truncated address.
  final String? contactName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trimmed = value.trim();
    final hasValue = trimmed.isNotEmpty;
    final name = contactName?.trim();
    final hasContact = hasValue && name != null && name.isNotEmpty;
    final textStyle = AppTypography.labelLarge.copyWith(
      fontWeight: FontWeight.w600,
      color: colors.text.accent,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_address_summary'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // Wide enough for the full 'Add recipient address...' empty label;
          // the footer's Expanded leading absorbs the difference.
          constraints: const BoxConstraints(maxWidth: 240),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: hasContact
              ? ContactNameInline(
                  name: name,
                  textStyle: textStyle,
                  key: const ValueKey('swap_destination_value'),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.wallet,
                      size: 20,
                      color: colors.icon.regular,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        hasValue
                            ? compactSwapAddress(
                                trimmed,
                                prefixLength: 8,
                                suffixLength: 6,
                                separator: '...',
                              )
                            : emptyText,
                        key: const ValueKey('swap_destination_value'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                  ],
                ),
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
    required this.balanceExceeded,
    required this.onTap,
  });

  final String availableText;
  final bool loading;
  final String? errorText;
  final bool balanceExceeded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = errorText != null || balanceExceeded;
    final label =
        errorText ?? (hasError ? 'Max: $availableText' : 'Max: $availableText');
    return MouseRegion(
      cursor: loading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_max_amount_button'),
        behavior: HitTestBehavior.opaque,
        onTap: loading ? null : onTap,
        child: Container(
          key: const ValueKey('swap_available_balance'),
          constraints: const BoxConstraints(maxWidth: 160),
          height: 32,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: hasError
                        ? colors.text.destructive
                        : colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _rateTextForState(SwapState state) {
  final quote = state.quote;
  if (quote != null) return quote.rateText;

  final externalPerZec =
      state.indicativeExternalPerZec[state.externalAsset] ??
      state.externalAsset.fallbackExternalPerZec;
  if (externalPerZec <= 0) return '--';
  if (state.direction.sendsZec) {
    return '1 ZEC = ${externalPerZec.toStringAsFixed(2)} ${state.externalAsset.symbol}';
  }
  return '1 ${state.externalAsset.symbol} = ${(1 / externalPerZec).toStringAsFixed(4)} ZEC';
}

bool _zecAmountOverAvailable(SwapState state, BigInt availableZatoshi) {
  if (!state.direction.sendsZec) return false;
  final amount = parseZecAmount(state.amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}

class _SwapDirectionButton extends StatelessWidget {
  const _SwapDirectionButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.background.inverse,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AppIcon(
            AppIcons.swapArrows,
            size: 20,
            color: colors.icon.inverse,
          ),
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

class _QuoteErrorMessage extends StatelessWidget {
  const _QuoteErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      message,
      key: const ValueKey('swap_quote_error_message'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(color: colors.text.destructive),
    );
  }
}

class _ExternalAssetButton extends StatelessWidget {
  const _ExternalAssetButton({
    required this.selected,
    required this.open,
    required this.onTap,
  });

  final SwapAsset selected;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_external_asset_selector'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _TokenPill(
          asset: selected,
          label: selected.chainLabel,
          open: open,
          showChainBadge: true,
          showChevron: true,
        ),
      ),
    );
  }
}

class _TokenPill extends StatelessWidget {
  const _TokenPill({
    required this.asset,
    this.label,
    this.open = false,
    this.showChainBadge = false,
    this.showChevron = false,
  });

  final SwapAsset asset;
  final String? label;
  final bool open;
  final bool showChainBadge;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: BoxConstraints(maxWidth: showChevron ? 140 : 116),
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwapAssetIcon(
            asset: asset,
            selected: true,
            size: 32,
            showChainBadge: showChainBadge,
          ),
          const SizedBox(width: 12),
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
                if (label != null)
                  Text(
                    label!,
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
          if (showChevron) ...[
            const SizedBox(width: 8),
            AppIcon(
              open ? AppIcons.arrowUpward : AppIcons.expand,
              size: 16,
              color: colors.icon.regular,
            ),
          ],
        ],
      ),
    );
  }
}

String _amountMetaText(
  SwapState state, {
  required SwapAsset asset,
  required String tokenAmountText,
  required SwapAmountInputMode inputMode,
  required FiatDisplay fiatDisplay,
}) {
  if (inputMode == SwapAmountInputMode.fiat) {
    return swapTokenAmountDisplayText(tokenAmountText: tokenAmountText);
  }
  return swapFiatDisplayText(
    state,
    asset: asset,
    tokenAmountText: tokenAmountText,
    fiatDisplay: fiatDisplay,
  );
}

class _SlippageControl extends StatelessWidget {
  const _SlippageControl({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        key: const ValueKey('swap_settings_button'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          height: 24,
          alignment: Alignment.center,
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          decoration: BoxDecoration(
            color: selected
                ? colors.state.selectedOpacity
                : colors.background.ground.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.text.secondary.withValues(
                    alpha: enabled ? 1 : 0.45,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              AppIcon(
                AppIcons.cog,
                size: 16,
                color: colors.icon.muted.withValues(alpha: enabled ? 1 : 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
