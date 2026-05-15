import 'package:flutter/material.dart' show InputDecoration, TextField, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../models/swap_prototype_models.dart';
import 'swap_amount_text.dart';
import 'swap_asset_icon.dart';

class SwapComposerPanel extends StatefulWidget {
  const SwapComposerPanel({
    required this.state,
    required this.onAmountChanged,
    required this.onDestinationChanged,
    required this.onDirectionChanged,
    required this.onToggleDirection,
    required this.onExternalAssetChanged,
    required this.onSlippageChanged,
    required this.onUseMaxZecAmount,
    required this.zecAvailableText,
    required this.zecAvailableZatoshi,
    super.key,
  });

  final SwapPrototypeState state;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<SwapDirection> onDirectionChanged;
  final VoidCallback onToggleDirection;
  final ValueChanged<SwapAsset> onExternalAssetChanged;
  final ValueChanged<int> onSlippageChanged;
  final VoidCallback onUseMaxZecAmount;
  final String zecAvailableText;
  final BigInt zecAvailableZatoshi;

  @override
  State<SwapComposerPanel> createState() => _SwapComposerPanelState();
}

class _SwapComposerPanelState extends State<SwapComposerPanel> {
  late final TextEditingController _amountController;
  late final TextEditingController _destinationController;
  late final TextEditingController _assetQueryController;
  late final Object _overlayTapRegionGroup;
  var _assetPickerOpen = false;
  var _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.state.amountText);
    _destinationController = TextEditingController(
      text: widget.state.destinationText,
    );
    _assetQueryController = TextEditingController();
    _overlayTapRegionGroup = Object();
  }

  @override
  void didUpdateWidget(covariant SwapComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_amountController, widget.state.amountText);
    _syncController(_destinationController, widget.state.destinationText);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _destinationController.dispose();
    _assetQueryController.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _toggleAssetPicker() {
    setState(() {
      _assetPickerOpen = !_assetPickerOpen;
      if (_assetPickerOpen) _settingsOpen = false;
    });
  }

  void _closeAssetPicker() {
    if (!_assetPickerOpen) return;
    setState(() {
      _assetPickerOpen = false;
      _assetQueryController.clear();
    });
  }

  void _toggleSettings() {
    setState(() {
      _settingsOpen = !_settingsOpen;
      if (_settingsOpen) {
        _assetPickerOpen = false;
        _assetQueryController.clear();
      }
    });
  }

  void _closeSettings() {
    if (!_settingsOpen) return;
    setState(() => _settingsOpen = false);
  }

  void _selectExternalAsset(SwapAsset asset) {
    widget.onExternalAssetChanged(asset);
    _closeAssetPicker();
  }

  void _selectSlippage(int slippageBps) {
    widget.onSlippageChanged(slippageBps);
    _closeSettings();
  }

  List<SwapAsset> get _filteredAssets {
    final query = _assetQueryController.text.trim().toLowerCase();
    final assets = widget.state.supportedExternalAssets;
    if (query.isEmpty) return assets;
    return [
      for (final asset in assets)
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
    final state = widget.state;
    final quote = state.quote;
    final sendsZec = state.direction.sendsZec;
    final targetDirection = state.direction.toggled;
    final rateText = _rateTextForState(state);
    final zecAmountOverAvailable = _zecAmountOverAvailable(
      state,
      widget.zecAvailableZatoshi,
    );

    final ticket = Container(
      key: const ValueKey('swap_compact_ticket'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwapTicketHeader(
            rateText: rateText,
            quoteLoading: state.quoteLoading,
            slippageBps: state.slippageBps,
            settingsOpen: _settingsOpen,
            onSettingsTap: _toggleSettings,
          ),
          const SizedBox(height: AppSpacing.xxs),
          _SwapAmountTile(
            label: 'You pay',
            helper: sendsZec ? 'Shielded ZEC' : 'External source',
            tone: _SwapAmountTileTone.input,
            amount: _SwapAmountInput(
              controller: _amountController,
              onChanged: widget.onAmountChanged,
            ),
            asset: sendsZec
                ? const _TokenPill(asset: SwapAsset.zec, label: 'Zcash wallet')
                : _ExternalAssetButton(
                    selected: state.externalAsset,
                    open: _assetPickerOpen,
                    onTap: _toggleAssetPicker,
                  ),
            footer: sendsZec
                ? _SwapMaxAmountFooter(
                    availableText: widget.zecAvailableText,
                    loading: state.maxAmountLoading,
                    errorText: state.maxAmountError,
                    balanceExceeded: zecAmountOverAvailable,
                    onTap: widget.onUseMaxZecAmount,
                  )
                : null,
          ),
          if (!sendsZec) ...[
            const SizedBox(height: 3),
            _InlineAddressField(
              label: '${state.externalAsset.symbol} refund',
              hint: 'Refund address on ${state.externalAsset.chainLabel}',
              badge: 'Refund only',
              controller: _destinationController,
              onChanged: widget.onDestinationChanged,
            ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          _SwapDirectionDivider(
            key: ValueKey('swap_direction_${targetDirection.name}'),
            onTap: widget.onToggleDirection,
          ),
          const SizedBox(height: AppSpacing.xxs),
          _SwapAmountTile(
            label: 'You receive',
            helper: quote == null
                ? 'Estimated receive'
                : 'Minimum ${compactSwapAmountText(quote.minimumReceiveText)}',
            tone: _SwapAmountTileTone.output,
            amount: _ReceiveAmountText(
              quote: quote,
              receiveSymbol: state.direction.toSymbol(state.externalAsset),
            ),
            asset: sendsZec
                ? _ExternalAssetButton(
                    selected: state.externalAsset,
                    open: _assetPickerOpen,
                    onTap: _toggleAssetPicker,
                  )
                : const _TokenPill(asset: SwapAsset.zec),
          ),
          if (sendsZec) ...[
            const SizedBox(height: 3),
            _InlineAddressField(
              label: 'Recipient',
              hint:
                  'Add ${state.externalAsset.chainLabel} ${state.externalAsset.symbol} recipient',
              badge: state.externalAsset.chainLabel,
              controller: _destinationController,
              onChanged: widget.onDestinationChanged,
            ),
          ],
          if (state.quoteError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _QuoteErrorBanner(message: state.quoteError!),
          ],
        ],
      ),
    );

    return TapRegion(
      groupId: _overlayTapRegionGroup,
      onTapOutside: (_) {
        _closeAssetPicker();
        _closeSettings();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ticket,
          if (_assetPickerOpen)
            Positioned(
              top: 72,
              right: AppSpacing.sm,
              child: _AssetPickerPopover(
                queryController: _assetQueryController,
                assets: _filteredAssets,
                selected: state.externalAsset,
                onQueryChanged: (_) => setState(() {}),
                onSelected: _selectExternalAsset,
              ),
            ),
          if (_settingsOpen)
            Positioned(
              top: 44,
              right: AppSpacing.sm,
              child: _SwapSettingsPopover(
                slippageBps: state.slippageBps,
                onSelected: _selectSlippage,
              ),
            ),
        ],
      ),
    );
  }
}

class _SwapTicketHeader extends StatelessWidget {
  const _SwapTicketHeader({
    required this.rateText,
    required this.quoteLoading,
    required this.slippageBps,
    required this.settingsOpen,
    required this.onSettingsTap,
  });

  final String rateText;
  final bool quoteLoading;
  final int slippageBps;
  final bool settingsOpen;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Powered by NEAR Intents',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.codeSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: 2),
              _SwapRateInline(rateText: rateText, quoteLoading: quoteLoading),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _ProviderBadge(label: _formatSlippage(slippageBps)),
        const SizedBox(width: AppSpacing.xxs),
        _IconControl(
          iconName: AppIcons.cog,
          tooltip: 'Swap settings',
          selected: settingsOpen,
          onTap: onSettingsTap,
        ),
      ],
    );
  }
}

class _SwapRateInline extends StatelessWidget {
  const _SwapRateInline({required this.rateText, required this.quoteLoading});

  final String rateText;
  final bool quoteLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('swap_rate_line'),
      children: [
        Text(
          'Rate',
          style: AppTypography.labelSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            rateText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.codeSmall.copyWith(color: colors.text.primary),
          ),
        ),
        if (quoteLoading) ...[
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(AppIcons.loader, size: 12, color: colors.icon.muted),
        ],
      ],
    );
  }
}

enum _SwapAmountTileTone { input, output }

class _SwapAmountTile extends StatelessWidget {
  const _SwapAmountTile({
    required this.label,
    required this.helper,
    required this.amount,
    required this.asset,
    required this.tone,
    this.footer,
  });

  final String label;
  final String helper;
  final Widget amount;
  final Widget asset;
  final _SwapAmountTileTone tone;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isInput = tone == _SwapAmountTileTone.input;
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: isInput
            ? colors.background.brandCrimsonAlpha
            : colors.background.raised,
        border: Border.all(
          color: isInput ? colors.border.regular : colors.border.subtle,
        ),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              asset,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          amount,
          const SizedBox(height: AppSpacing.xxs),
          Text(
            helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _SwapAmountInput extends StatelessWidget {
  const _SwapAmountInput({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle = AppTypography.headlineSmall.copyWith(
      color: colors.text.accent,
      fontSize: 28,
      height: 32 / 28,
      fontWeight: FontWeight.w500,
    );
    return TextField(
      key: const ValueKey('swap_amount_field'),
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: valueStyle,
      cursorColor: colors.text.accent,
      decoration: InputDecoration.collapsed(
        hintText: '0.00',
        hintStyle: valueStyle.copyWith(color: colors.text.disabled),
      ),
    );
  }
}

class _SwapMaxAmountFooter extends StatelessWidget {
  const _SwapMaxAmountFooter({
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
    return Row(
      children: [
        Expanded(
          child: Text(
            errorText ??
                (balanceExceeded
                    ? 'Exceeds available $availableText'
                    : 'Available $availableText'),
            key: const ValueKey('swap_available_balance'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: hasError ? colors.text.destructive : colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        MouseRegion(
          cursor: loading ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('swap_max_amount_button'),
            behavior: HitTestBehavior.opaque,
            onTap: loading ? null : onTap,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.background.brandCrimsonAlpha,
                border: Border.all(color: colors.border.subtle),
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    loading ? AppIcons.loader : AppIcons.zcash,
                    size: 13,
                    color: colors.icon.brandCrimson,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Max',
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.brandCrimson,
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

class _ReceiveAmountText extends StatelessWidget {
  const _ReceiveAmountText({required this.quote, required this.receiveSymbol});

  final SwapQuote? quote;
  final String receiveSymbol;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emptyAmount = receiveSymbol == 'ZEC' ? '0.0000' : '0.00';
    final value = quote == null
        ? emptyAmount
        : compactSwapAmountText(
            _stripTrailingSymbol(quote!.receiveEstimateText, receiveSymbol),
          );
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.headlineSmall.copyWith(
        color: quote == null ? colors.text.disabled : colors.text.accent,
        fontSize: 28,
        height: 32 / 28,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

String _stripTrailingSymbol(String value, String symbol) {
  return value.replaceFirst(RegExp(r'\s+' + RegExp.escape(symbol) + r'$'), '');
}

String _rateTextForState(SwapPrototypeState state) {
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

bool _zecAmountOverAvailable(
  SwapPrototypeState state,
  BigInt availableZatoshi,
) {
  if (!state.direction.sendsZec) return false;
  final amount = parseZecAmount(state.amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}

class _SwapDirectionDivider extends StatelessWidget {
  const _SwapDirectionDivider({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: colors.border.subtle)),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: colors.background.base,
                  border: Border.all(color: colors.border.regular),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.arrowDownward,
                  size: 16,
                  color: colors.icon.brandCrimson,
                ),
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: colors.border.subtle)),
        ],
      ),
    );
  }
}

class _InlineAddressField extends StatefulWidget {
  const _InlineAddressField({
    required this.label,
    required this.hint,
    required this.badge,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final String badge;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_InlineAddressField> createState() => _InlineAddressFieldState();
}

class _InlineAddressFieldState extends State<_InlineAddressField> {
  late final FocusNode _focusNode;
  late bool _hasText;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _hasText = widget.controller.text.trim().isNotEmpty;
    _focusNode.addListener(_handleFocusChanged);
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant _InlineAddressField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_focused == _focusNode.hasFocus) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _handleTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (_hasText == hasText) return;
    setState(() => _hasText = hasText);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emphasized = _focused || _hasText;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final showBadge = !maxWidth.isFinite || maxWidth >= 330;

        return AnimatedContainer(
          key: const ValueKey('swap_address_summary'),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: colors.background.base,
            border: Border.all(
              color: emphasized ? colors.border.regular : colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AppIcon(
                          AppIcons.link,
                          size: 12,
                          color: emphasized
                              ? colors.icon.accent
                              : colors.icon.muted,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSmall.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                        if (showBadge) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          _AddressRoleBadge(
                            label: widget.badge,
                            emphasized: emphasized,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    TextField(
                      key: const ValueKey('swap_destination_field'),
                      focusNode: _focusNode,
                      controller: widget.controller,
                      onChanged: widget.onChanged,
                      style: AppTypography.codeSmall.copyWith(
                        color: colors.text.primary,
                      ),
                      cursorColor: colors.text.accent,
                      decoration: InputDecoration.collapsed(
                        hintText: widget.hint,
                        hintStyle: AppTypography.codeSmall.copyWith(
                          color: colors.text.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddressRoleBadge extends StatelessWidget {
  const _AddressRoleBadge({required this.label, required this.emphasized});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 128),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(
          color: emphasized ? colors.border.regular : colors.border.subtle,
        ),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(
          color: emphasized ? colors.text.accent : colors.text.secondary,
        ),
      ),
    );
  }
}

class _SwapSettingsPopover extends StatefulWidget {
  const _SwapSettingsPopover({
    required this.slippageBps,
    required this.onSelected,
  });

  final int slippageBps;
  final ValueChanged<int> onSelected;

  @override
  State<_SwapSettingsPopover> createState() => _SwapSettingsPopoverState();
}

class _SwapSettingsPopoverState extends State<_SwapSettingsPopover> {
  late final TextEditingController _customController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: _formatSlippageValue(widget.slippageBps),
    );
  }

  @override
  void didUpdateWidget(covariant _SwapSettingsPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slippageBps == widget.slippageBps) return;
    _customController.value = TextEditingValue(
      text: _formatSlippageValue(widget.slippageBps),
      selection: TextSelection.collapsed(
        offset: _formatSlippageValue(widget.slippageBps).length,
      ),
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _applyCustomSlippage() {
    final value = double.tryParse(_customController.text.trim());
    if (value == null || value < 0.1 || value > 5) {
      setState(() => _errorText = 'Enter 0.1% to 5%');
      return;
    }
    widget.onSelected((value * 100).round());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_settings_popover'),
      width: 320,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.overlay,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Slippage tolerance',
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Used for the next live quote request.',
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var index = 0; index < swapSlippagePresetBps.length; index++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : AppSpacing.xxs,
                    ),
                    child: _SlippagePresetButton(
                      bps: swapSlippagePresetBps[index],
                      selected:
                          swapSlippagePresetBps[index] == widget.slippageBps,
                      onTap: () =>
                          widget.onSelected(swapSlippagePresetBps[index]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: colors.background.raised,
              border: Border.all(color: colors.border.subtle),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Custom tolerance',
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ),
                    Text(
                      '0.1% - 5%',
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: colors.background.base,
                          border: Border.all(color: colors.border.regular),
                          borderRadius: BorderRadius.circular(AppRadii.xSmall),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey(
                                  'swap_slippage_custom_field',
                                ),
                                controller: _customController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'),
                                  ),
                                ],
                                onChanged: (_) {
                                  if (_errorText == null) return;
                                  setState(() => _errorText = null);
                                },
                                onSubmitted: (_) => _applyCustomSlippage(),
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.text.accent,
                                ),
                                cursorColor: colors.text.accent,
                                decoration: InputDecoration.collapsed(
                                  hintText: 'Custom',
                                  hintStyle: AppTypography.labelLarge.copyWith(
                                    color: colors.text.disabled,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              '%',
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppButton(
                      key: const ValueKey('swap_slippage_custom_apply'),
                      onPressed: _applyCustomSlippage,
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.medium,
                      minWidth: 96,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _errorText!,
                    style: AppTypography.bodyExtraSmall.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlippagePresetButton extends StatelessWidget {
  const _SlippagePresetButton({
    required this.bps,
    required this.selected,
    required this.onTap,
  });

  final int bps;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: ValueKey('swap_slippage_${bps}bps'),
      onPressed: onTap,
      variant: selected ? AppButtonVariant.primary : AppButtonVariant.secondary,
      size: AppButtonSize.medium,
      child: Text(_formatSlippage(bps)),
    );
  }
}

class _QuoteErrorBanner extends StatelessWidget {
  const _QuoteErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: message,
      child: Container(
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
    this.showChevron = false,
  });

  final SwapAsset asset;
  final String? label;
  final bool open;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: BoxConstraints(maxWidth: showChevron ? 184 : 168),
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwapAssetIcon(asset: asset, selected: true, size: 24),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
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
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(
              open ? AppIcons.arrowUpward : AppIcons.arrowDown,
              size: 14,
              color: colors.icon.muted,
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetPickerPopover extends StatelessWidget {
  const _AssetPickerPopover({
    required this.queryController,
    required this.assets,
    required this.selected,
    required this.onQueryChanged,
    required this.onSelected,
  });

  final TextEditingController queryController;
  final List<SwapAsset> assets;
  final SwapAsset selected;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SwapAsset> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = _assetPickerEntries(assets);
    return Container(
      key: const ValueKey('swap_external_asset_menu'),
      width: 316,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.overlay,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: const ValueKey('swap_asset_search_field'),
            label: 'Search asset',
            showLabel: false,
            hintText: 'Search token or network',
            controller: queryController,
            leading: const AppIcon(AppIcons.link),
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: assets.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      'No supported asset found',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xxs),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final header = entry.header;
                      if (header != null) {
                        return _AssetMenuSectionHeader(header: header);
                      }
                      final asset = entry.asset!;
                      return _AssetMenuRow(
                        asset: asset,
                        selected: selected == asset,
                        showNetworkBadge: entry.showNetworkBadge,
                        onTap: () => onSelected(asset),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AssetPickerEntry {
  const _AssetPickerEntry.asset({
    required this.asset,
    required this.showNetworkBadge,
  }) : header = null;

  const _AssetPickerEntry.header(this.header)
    : asset = null,
      showNetworkBadge = false;

  final SwapAsset? asset;
  final _AssetPickerHeader? header;
  final bool showNetworkBadge;
}

class _AssetPickerHeader {
  const _AssetPickerHeader({required this.symbol, required this.count});

  final String symbol;
  final int count;
}

List<_AssetPickerEntry> _assetPickerEntries(List<SwapAsset> assets) {
  final symbolCounts = <String, int>{};
  for (final asset in assets) {
    final key = asset.symbol.toLowerCase();
    symbolCounts[key] = (symbolCounts[key] ?? 0) + 1;
  }

  final insertedHeaders = <String>{};
  final entries = <_AssetPickerEntry>[];
  for (final asset in assets) {
    final key = asset.symbol.toLowerCase();
    final count = symbolCounts[key] ?? 0;
    final duplicateSymbol = count > 1;
    if (duplicateSymbol && insertedHeaders.add(key)) {
      entries.add(
        _AssetPickerEntry.header(
          _AssetPickerHeader(symbol: asset.symbol, count: count),
        ),
      );
    }
    entries.add(
      _AssetPickerEntry.asset(asset: asset, showNetworkBadge: duplicateSymbol),
    );
  }
  return entries;
}

class _AssetMenuSectionHeader extends StatelessWidget {
  const _AssetMenuSectionHeader({required this.header});

  final _AssetPickerHeader header;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      key: ValueKey('swap_asset_group_${header.symbol.toLowerCase()}'),
      padding: const EdgeInsets.only(
        left: AppSpacing.xxs,
        top: AppSpacing.xxs,
        bottom: AppSpacing.xxs,
      ),
      child: Row(
        children: [
          Text(
            '${header.symbol} networks',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            '${header.count}',
            style: AppTypography.labelSmall.copyWith(
              color: colors.text.secondary,
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
    required this.showNetworkBadge,
    required this.onTap,
  });

  final SwapAsset asset;
  final bool selected;
  final bool showNetworkBadge;
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
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected ? colors.state.selectedOpacity : null,
            border: Border.all(
              color: selected ? colors.border.regular : colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            children: [
              SwapAssetIcon(asset: asset, selected: selected, size: 30),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          asset.symbol,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        if (showNetworkBadge) ...[
                          _AssetNetworkBadge(
                            key: ValueKey(
                              'swap_asset_network_badge_${asset.identityKey}',
                            ),
                            label: asset.chainLabel,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                        ],
                        if (!showNetworkBadge)
                          Flexible(
                            child: Text(
                              asset.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmall.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showNetworkBadge ? asset.displayName : asset.chainLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                AppIcon(
                  AppIcons.checkCircle,
                  size: 16,
                  color: colors.icon.success,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetNetworkBadge extends StatelessWidget {
  const _AssetNetworkBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(color: colors.text.secondary),
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.brandCrimsonAlpha,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.renew, size: 14, color: colors.icon.brandCrimson),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.brandCrimson,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconControl extends StatelessWidget {
  const _IconControl({
    required this.iconName,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final String iconName;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('swap_settings_button'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colors.background.brandCrimsonAlpha
                  : colors.background.raised,
              border: Border.all(
                color: selected ? colors.border.regular : colors.border.subtle,
              ),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: AppIcon(
              iconName,
              size: 15,
              color: selected ? colors.icon.brandCrimson : colors.icon.muted,
            ),
          ),
        ),
      ),
    );
  }
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
