import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_fiat_amount.dart';
import '../models/swap_models.dart';
import 'swap_asset_icon.dart';

class SwapComposerPanel extends StatefulWidget {
  const SwapComposerPanel({
    required this.state,
    required this.onAmountChanged,
    required this.onAmountFiatChanged,
    required this.onReceiveAmountChanged,
    required this.onReceiveAmountFiatChanged,
    required this.onToggleFiatInputMode,
    required this.onDirectionChanged,
    required this.onToggleDirection,
    required this.onOpenExternalAssetPicker,
    required this.onOpenDestinationAddress,
    required this.onOpenSlippageSettings,
    required this.onUseMaxZecAmount,
    required this.assetSelectorOpen,
    required this.slippageSettingsOpen,
    required this.zecAvailableText,
    required this.zecAvailableZatoshi,
    super.key,
  });

  final SwapState state;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onAmountFiatChanged;
  final ValueChanged<String> onReceiveAmountChanged;
  final ValueChanged<String> onReceiveAmountFiatChanged;
  final ValueChanged<SwapAmountInputSide> onToggleFiatInputMode;
  final ValueChanged<SwapDirection> onDirectionChanged;
  final VoidCallback onToggleDirection;
  final VoidCallback onOpenExternalAssetPicker;
  final VoidCallback onOpenDestinationAddress;
  final VoidCallback onOpenSlippageSettings;
  final VoidCallback onUseMaxZecAmount;
  final bool assetSelectorOpen;
  final bool slippageSettingsOpen;
  final String zecAvailableText;
  final BigInt zecAvailableZatoshi;

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
          hintText: payInputIsFiat ? '0.00' : (sendsZec ? '0.0000' : '0.00'),
          prefixText: payInputIsFiat ? r'$' : null,
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
                  ),
                  showModeIcon: payActive,
                  active: payInputIsFiat,
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
                  ),
                  showModeIcon: payActive,
                  active: payInputIsFiat,
                  onTap: () =>
                      widget.onToggleFiatInputMode(SwapAmountInputSide.pay),
                ),
                trailing: _AddressTrigger(
                  value: state.destinationText,
                  emptyText: 'Add Refund address...',
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
          hintText: receiveInputIsFiat
              ? '0.00'
              : (state.direction.toSymbol(state.externalAsset) == 'ZEC'
                    ? '0.0000'
                    : '0.00'),
          prefixText: receiveInputIsFiat ? r'$' : null,
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
                  ),
                  showModeIcon: receiveActive,
                  active: receiveInputIsFiat,
                  onTap: () =>
                      widget.onToggleFiatInputMode(SwapAmountInputSide.receive),
                ),
                trailing: _AddressTrigger(
                  value: state.destinationText,
                  emptyText: 'Add Recipient address...',
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
        width: 400,
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
              onSettingsTap: widget.onOpenSlippageSettings,
            ),
            if (quoteError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _QuoteErrorBanner(message: quoteError),
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
    required this.onSettingsTap,
  });

  final String rateText;
  final int slippageBps;
  final bool settingsOpen;
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
            label: _formatSlippage(slippageBps),
            selected: settingsOpen,
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
        color: colors.background.base,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(children: [payCard, const SizedBox(height: 16), receiveCard]),
          Positioned(
            top: 148,
            left: 176,
            child: _SwapDirectionButton(
              key: ValueKey('swap_direction_${targetDirection.name}'),
              onTap: onToggleDirection,
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
        color: active ? colors.background.ground : null,
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
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
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
    final valueStyle = AppTypography.displaySmall.copyWith(
      color: colors.text.accent,
      fontWeight: FontWeight.w400,
    );
    return Row(
      children: [
        if (prefixText != null)
          Text(
            prefixText!,
            style: valueStyle.copyWith(color: colors.text.accent),
          ),
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
    this.onTap,
  });

  final String text;
  final bool showModeIcon;
  final bool active;
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
              style: AppTypography.labelMedium.copyWith(
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
  });

  final String value;
  final String emptyText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trimmed = value.trim();
    final hasValue = trimmed.isNotEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_address_summary'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 190),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.wallet, size: 20, color: colors.icon.regular),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  hasValue ? _compactAddress(trimmed) : emptyText,
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
                    color: hasError
                        ? colors.text.destructive
                        : colors.text.secondary,
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

typedef SwapAddressSubmitCallback = void Function(String value, bool remember);

class SwapAddressEditModal extends StatefulWidget {
  const SwapAddressEditModal({
    required this.state,
    required this.onSubmitted,
    required this.onScan,
    required this.onOpenContacts,
    required this.onCancel,
    super.key,
  });

  final SwapState state;
  final SwapAddressSubmitCallback onSubmitted;
  final VoidCallback onScan;
  final VoidCallback onOpenContacts;
  final VoidCallback onCancel;

  @override
  State<SwapAddressEditModal> createState() => _SwapAddressEditModalState();
}

class _SwapAddressEditModalState extends State<SwapAddressEditModal> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _rememberAddress = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.destinationText);
    _focusNode = FocusNode(debugLabel: 'SwapAddressModalField');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant SwapAddressEditModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.destinationText == widget.state.destinationText) {
      return;
    }
    _controller.value = TextEditingValue(
      text: widget.state.destinationText,
      selection: TextSelection.collapsed(
        offset: widget.state.destinationText.length,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSubmitted(_controller.text.trim(), _rememberAddress);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sendsZec = widget.state.direction.sendsZec;
    final asset = widget.state.externalAsset;
    final title = sendsZec
        ? '${asset.symbol} Recipient Address'
        : '${asset.symbol} Refund Address';
    final fieldLabel = sendsZec ? 'Recipient' : 'Refund to';
    final hint = widget.state.destinationFieldHint;
    final description = sendsZec
        ? 'The external asset will be delivered to this address.'
        : 'If swap fails, or market conditions change, your transaction may be refunded minus the fee. The refund currency is ${asset.symbol} on Near.';
    final rememberLabel = sendsZec
        ? 'Remember this address for recipients'
        : 'Remember this address for refunds';

    return Container(
      key: const ValueKey('swap_address_modal'),
      width: 312,
      height: 440,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SwapModalIconBadge(
                iconName: AppIcons.wallet,
                iconColor: colors.icon.regular,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      fieldLabel,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.background.base,
                        border: Border.all(
                          color: colors.border.subtle,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.small),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: TextField(
                                key: const ValueKey('swap_destination_field'),
                                controller: _controller,
                                focusNode: _focusNode,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.text.accent,
                                ),
                                cursorColor: colors.text.accent,
                                decoration: InputDecoration.collapsed(
                                  hintText: hint,
                                  hintStyle: AppTypography.labelLarge.copyWith(
                                    color: colors.text.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _SwapInlineIconButton(
                                  key: const ValueKey(
                                    'swap_address_scan_button',
                                  ),
                                  iconName: AppIcons.qr,
                                  onTap: widget.onScan,
                                ),
                                const SizedBox(width: 4),
                                _SwapInlineIconButton(
                                  key: const ValueKey(
                                    'swap_address_contacts_button',
                                  ),
                                  iconName: AppIcons.users,
                                  onTap: widget.onOpenContacts,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AddressRememberToggle(
                      selected: _rememberAddress,
                      label: rememberLabel,
                      onTap: () {
                        setState(() => _rememberAddress = !_rememberAddress);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          _SwapModalButtons(
            primaryKey: const ValueKey('swap_address_update_button'),
            cancelKey: const ValueKey('swap_address_cancel_button'),
            onPrimary: _submit,
            onCancel: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

class SwapSlippageModal extends StatefulWidget {
  const SwapSlippageModal({
    required this.slippageBps,
    required this.onSubmitted,
    required this.onCancel,
    this.initialCustomText,
    super.key,
  });

  final int slippageBps;
  final ValueChanged<int> onSubmitted;
  final VoidCallback onCancel;
  final String? initialCustomText;

  @override
  State<SwapSlippageModal> createState() => _SwapSlippageModalState();
}

class _SwapSlippageModalState extends State<SwapSlippageModal> {
  static const int _minCustomBps = 10;
  static const int _maxCustomBps = 500;

  late int? _selectedPresetBps;
  late TextEditingController _customController;
  late final FocusNode _customFocusNode;

  @override
  void initState() {
    super.initState();
    _initializeSelection(widget.slippageBps);
    _customFocusNode = FocusNode(debugLabel: 'SwapSlippageCustom');
  }

  @override
  void didUpdateWidget(covariant SwapSlippageModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slippageBps == widget.slippageBps &&
        oldWidget.initialCustomText == widget.initialCustomText) {
      return;
    }
    _customController.dispose();
    _initializeSelection(widget.slippageBps);
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  void _initializeSelection(int slippageBps) {
    final initialCustomText = widget.initialCustomText;
    if (initialCustomText != null) {
      _selectedPresetBps = null;
      _customController = TextEditingController(text: initialCustomText);
      return;
    }
    final normalized = slippageBps.clamp(_minCustomBps, _maxCustomBps).toInt();
    if (swapSlippagePresetBps.contains(normalized)) {
      _selectedPresetBps = normalized;
      _customController = TextEditingController();
      return;
    }
    _selectedPresetBps = null;
    _customController = TextEditingController(
      text: _formatSlippageValue(normalized),
    );
  }

  void _selectPreset(int bps) {
    setState(() {
      _selectedPresetBps = bps;
      _customFocusNode.unfocus();
    });
  }

  void _selectCustom() {
    setState(() => _selectedPresetBps = null);
    _customFocusNode.requestFocus();
  }

  void _handleCustomChanged(String _) {
    if (_selectedPresetBps == null) {
      setState(() {});
      return;
    }
    setState(() => _selectedPresetBps = null);
  }

  int? get _customBps {
    final text = _customController.text.trim();
    if (text.isEmpty || text == '.') return null;
    final percent = double.tryParse(text);
    if (percent == null) return null;
    return (percent * 100).round();
  }

  bool get _customSelected => _selectedPresetBps == null;

  bool get _customValueInvalid {
    if (!_customSelected || _customController.text.trim().isEmpty) return false;
    final bps = _customBps;
    return bps == null || bps < _minCustomBps || bps > _maxCustomBps;
  }

  int? get _selectedBps {
    if (_selectedPresetBps != null) return _selectedPresetBps;
    final bps = _customBps;
    if (bps == null || bps < _minCustomBps || bps > _maxCustomBps) {
      return null;
    }
    return bps;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedBps = _selectedBps;
    final canSubmit = selectedBps != null;

    return Container(
      key: const ValueKey('swap_slippage_modal'),
      width: 312,
      height: 398,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SwapModalIconBadge(
                iconName: AppIcons.cog,
                iconColor: colors.icon.regular,
              ),
              const SizedBox(width: 8),
              Text(
                'Slippage',
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (final bps in swapSlippagePresetBps) ...[
            _SlippageRadioCard(
              bps: bps,
              height: bps == swapSlippagePresetBps.first ? 34 : 40,
              selected: _selectedPresetBps == bps,
              onTap: () => _selectPreset(bps),
            ),
            if (bps != swapSlippagePresetBps.last) const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          _SlippageCustomRadioCard(
            controller: _customController,
            focusNode: _customFocusNode,
            selected: _customSelected,
            invalid: _customValueInvalid,
            onTap: _selectCustom,
            onChanged: _handleCustomChanged,
          ),
          const Spacer(),
          _SwapModalButtons(
            primaryKey: const ValueKey('swap_slippage_update_button'),
            cancelKey: const ValueKey('swap_slippage_cancel_button'),
            primaryLabel: _customValueInvalid
                ? 'Slippage must be 0.1 - 5%'
                : 'Update',
            primaryEnabled: canSubmit,
            onPrimary: () {
              final value = _selectedBps;
              if (value == null) return;
              widget.onSubmitted(value);
            },
            onCancel: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

class _SwapModalIconBadge extends StatelessWidget {
  const _SwapModalIconBadge({required this.iconName, required this.iconColor});

  final String iconName;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: AppIcon(iconName, size: 16, color: iconColor),
    );
  }
}

class _SwapInlineIconButton extends StatelessWidget {
  const _SwapInlineIconButton({
    required this.iconName,
    required this.onTap,
    super.key,
  });

  final String iconName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 20,
          height: 20,
          child: AppIcon(iconName, size: 20, color: colors.icon.accent),
        ),
      ),
    );
  }
}

class _AddressRememberToggle extends StatelessWidget {
  const _AddressRememberToggle({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_address_remember_toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              key: const ValueKey('swap_address_remember_checkbox'),
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.background.inverse : null,
                border: Border.all(
                  color: selected
                      ? colors.border.strong
                      : colors.border.regular,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: selected
                  ? AppIcon(
                      AppIcons.check,
                      size: 12,
                      color: colors.icon.inverse,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapModalButtons extends StatelessWidget {
  const _SwapModalButtons({
    required this.primaryKey,
    required this.cancelKey,
    required this.onPrimary,
    required this.onCancel,
    this.primaryLabel = 'Update',
    this.primaryEnabled = true,
  });

  final Key primaryKey;
  final Key cancelKey;
  final VoidCallback onPrimary;
  final VoidCallback onCancel;
  final String primaryLabel;
  final bool primaryEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: primaryKey,
          onPressed: primaryEnabled ? onPrimary : null,
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: 280,
          child: SizedBox(
            width: 220,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(primaryLabel)),
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          key: cancelKey,
          onPressed: onCancel,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.large,
          minWidth: 280,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _SlippageRadioCard extends StatelessWidget {
  const _SlippageRadioCard({
    required this.bps,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final int bps;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      key: ValueKey('swap_slippage_${bps}bps'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.regular,
              width: selected ? 2 : 1.5,
            ),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    _formatSlippage(bps),
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ),
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.background.inverse
                      : colors.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: selected
                    ? AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.icon.inverse,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlippageCustomRadioCard extends StatelessWidget {
  const _SlippageCustomRadioCard({
    required this.controller,
    required this.focusNode,
    required this.selected,
    required this.invalid,
    required this.onTap,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool selected;
  final bool invalid;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = invalid
        ? colors.border.utilityDestructive
        : selected
        ? colors.border.strong
        : colors.border.regular;
    final valueColor = invalid ? colors.text.destructive : colors.text.accent;
    final valueStyle = AppTypography.labelLarge.copyWith(color: valueColor);
    final hintStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.accent.withValues(alpha: 0.4),
    );
    final inputWidth = _slippageInputWidth(
      context,
      text: controller.text,
      valueStyle: valueStyle,
      hintStyle: hintStyle,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_slippage_custom_card'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: selected ? 2 : 1.5),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Custom',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: inputWidth,
                        height: 18,
                        child: TextField(
                          key: const ValueKey('swap_slippage_custom_input'),
                          controller: controller,
                          focusNode: focusNode,
                          onTap: onTap,
                          onChanged: onChanged,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [
                            _SlippageCustomInputFormatter(),
                          ],
                          style: valueStyle,
                          textAlign: TextAlign.right,
                          cursorColor: valueColor,
                          decoration: InputDecoration.collapsed(
                            hintText: '0.1-5',
                            hintStyle: hintStyle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        key: const ValueKey('swap_slippage_custom_percent'),
                        '%',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.background.inverse
                      : colors.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: selected
                    ? AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.icon.inverse,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _slippageInputWidth(
  BuildContext context, {
  required String text,
  required TextStyle valueStyle,
  required TextStyle hintStyle,
}) {
  final hintWidth = _measureSlippageInputWidth(
    context,
    text: '0.1-5',
    style: hintStyle,
  );
  final valueWidth = text.isEmpty
      ? 0.0
      : _measureSlippageInputWidth(context, text: text, style: valueStyle);
  final measuredWidth = hintWidth > valueWidth ? hintWidth : valueWidth;
  final paddedWidth = measuredWidth.ceilToDouble() + 6;
  if (paddedWidth < 38) return 38;
  if (paddedWidth > 72) return 72;
  return paddedWidth;
}

double _measureSlippageInputWidth(
  BuildContext context, {
  required String text,
  required TextStyle style,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

class _SlippageCustomInputFormatter extends TextInputFormatter {
  const _SlippageCustomInputFormatter();

  static final RegExp _allowed = RegExp(r'^\d{0,3}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty || _allowed.hasMatch(text)) return newValue;
    return oldValue;
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

class _QuoteErrorBanner extends StatelessWidget {
  const _QuoteErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_quote_error_banner'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.text.destructive.withValues(alpha: 0.08),
        border: Border.all(
          color: colors.text.destructive.withValues(alpha: 0.28),
        ),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.warning, size: 16, color: colors.icon.destructive),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quote unavailable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      constraints: BoxConstraints(maxWidth: showChevron ? 136 : 112),
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
          const SizedBox(width: 8),
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
                    color: colors.text.accent,
                  ),
                ),
                if (label != null)
                  Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
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
}) {
  if (inputMode == SwapAmountInputMode.fiat) {
    return swapTokenAmountDisplayText(
      asset: asset,
      tokenAmountText: tokenAmountText,
    );
  }
  return swapFiatDisplayText(
    state,
    asset: asset,
    tokenAmountText: tokenAmountText,
  );
}

class SwapAssetSelectorModal extends StatefulWidget {
  const SwapAssetSelectorModal({
    required this.assets,
    required this.selected,
    required this.onSelected,
    this.initialQuery = '',
    super.key,
  });

  final List<SwapAsset> assets;
  final SwapAsset selected;
  final ValueChanged<SwapAsset> onSelected;
  final String initialQuery;

  @override
  State<SwapAssetSelectorModal> createState() => _SwapAssetSelectorModalState();
}

class _SwapAssetSelectorModalState extends State<SwapAssetSelectorModal> {
  late final TextEditingController _queryController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode(debugLabel: 'SwapAssetSelectorSearch');
    _scrollController = ScrollController();
    _focusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  void _clearQuery() {
    if (_queryController.text.isEmpty) return;
    setState(() => _queryController.clear());
    _focusNode.requestFocus();
  }

  List<SwapAsset> get _filteredAssets {
    final query = _queryController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.assets;
    return [
      for (final asset in widget.assets)
        if (asset.symbol.toLowerCase().contains(query) ||
            asset.displayName.toLowerCase().contains(query) ||
            asset.chainLabel.toLowerCase().contains(query) ||
            asset.railLabel.toLowerCase().contains(query))
          asset,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final assets = _filteredAssets;
    final hasQuery = _queryController.text.isNotEmpty;
    final searchBorderColor = _focusNode.hasFocus || hasQuery
        ? colors.border.medium
        : colors.border.regular;

    return Container(
      key: const ValueKey('swap_external_asset_menu'),
      width: 312,
      height: 440,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SwapModalIconBadge(
                iconName: AppIcons.coins,
                iconColor: colors.icon.regular,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select asset',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: colors.background.base,
              border: Border.all(color: searchBorderColor, width: 1.5),
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AppIcon(
                      AppIcons.search,
                      size: 20,
                      color: colors.icon.accent,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      key: const ValueKey('swap_asset_search_field'),
                      controller: _queryController,
                      focusNode: _focusNode,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                      cursorColor: colors.text.accent,
                      decoration: InputDecoration.collapsed(
                        hintText: 'Search token or chain',
                        hintStyle: AppTypography.labelLarge.copyWith(
                          color: colors.text.muted,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasQuery)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _SwapInlineIconButton(
                      key: const ValueKey('swap_asset_search_clear_button'),
                      iconName: AppIcons.cross,
                      onTap: _clearQuery,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: assets.isEmpty
                ? Center(
                    child: SizedBox(
                      width: 112,
                      child: Text(
                        'No tokens or chains found',
                        textAlign: TextAlign.center,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ),
                  )
                : RawScrollbar(
                    key: const ValueKey('swap_asset_selector_scrollbar'),
                    controller: _scrollController,
                    thumbVisibility: assets.length > 5,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: 6,
                    mainAxisMargin: 3,
                    crossAxisMargin: 3,
                    thumbColor: colors.background.overlay,
                    child: Padding(
                      key: const ValueKey('swap_asset_selector_list_gutter'),
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          itemCount: assets.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.xxs),
                          itemBuilder: (context, index) {
                            final asset = assets[index];
                            return _AssetMenuRow(
                              asset: asset,
                              selected: widget.selected == asset,
                              onTap: () => widget.onSelected(asset),
                            );
                          },
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

class _AssetMenuRow extends StatelessWidget {
  const _AssetMenuRow({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final SwapAsset asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_asset_row_${asset.identityKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? colors.background.neutralSubtleOpacity : null,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            children: [
              SwapAssetIcon(
                asset: asset,
                selected: selected,
                size: 32,
                showChainBadge: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    Text(
                      asset.chainLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlippageControl extends StatelessWidget {
  const _SlippageControl({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_settings_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 28,
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
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(width: 2),
              AppIcon(AppIcons.cog, size: 16, color: colors.icon.muted),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactAddress(String value) {
  if (value.length <= 18) return value;
  return '${value.substring(0, 8)}...${value.substring(value.length - 6)}';
}

String _formatSlippage(int bps) {
  return '${_formatSlippageValue(bps)}%';
}

String _formatSlippageValue(int bps) {
  final value = bps / 100;
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  if (bps % 10 == 0) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}
