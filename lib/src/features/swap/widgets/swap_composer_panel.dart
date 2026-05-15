import 'package:flutter/material.dart' show InputDecoration, TextField, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../models/swap_prototype_models.dart';
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
    super.key,
  });

  final SwapPrototypeState state;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<SwapDirection> onDirectionChanged;
  final VoidCallback onToggleDirection;
  final ValueChanged<SwapAsset> onExternalAssetChanged;
  final ValueChanged<int> onSlippageChanged;

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
    final quoteStatus = _ComposerQuoteStatus.fromState(state);
    final sendsZec = state.direction.sendsZec;
    final targetDirection = state.direction.toggled;

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
            quoteStatus: quoteStatus,
            slippageBps: state.slippageBps,
            settingsOpen: _settingsOpen,
            onSettingsTap: _toggleSettings,
          ),
          const SizedBox(height: AppSpacing.xs),
          _SwapAmountTile(
            label: 'You pay',
            helper: sendsZec ? 'Available 12.48 ZEC' : 'External source',
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
                ? null
                : _InlineAddressField(
                    label: '${state.externalAsset.symbol} refund',
                    hint: 'Refund address on ${state.externalAsset.chainLabel}',
                    badge: 'Refund only',
                    controller: _destinationController,
                    onChanged: widget.onDestinationChanged,
                  ),
          ),
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
                : 'Minimum ${quote.minimumReceiveText}',
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
            footer: sendsZec
                ? _InlineAddressField(
                    label: 'Recipient',
                    hint: 'Add ${state.externalAsset.chainLabel} recipient',
                    badge: state.externalAsset.chainLabel,
                    controller: _destinationController,
                    onChanged: widget.onDestinationChanged,
                  )
                : null,
          ),
          if (!state.quoteLoading && quote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _QuoteDetailsStrip(quote: quote, quoteStatus: quoteStatus),
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

enum _ComposerQuoteTone { idle, estimate, loading, success, warning, error }

class _ComposerQuoteStatus {
  const _ComposerQuoteStatus({
    required this.badgeLabel,
    required this.title,
    required this.detail,
    required this.iconName,
    required this.tone,
  });

  factory _ComposerQuoteStatus.fromState(SwapPrototypeState state) {
    if (state.quoteLoading) {
      return const _ComposerQuoteStatus(
        badgeLabel: 'Checking',
        title: 'Getting live quote',
        detail:
            'Fetching a one-time deposit address and minimum receive from NEAR Intents.',
        iconName: AppIcons.loader,
        tone: _ComposerQuoteTone.loading,
      );
    }

    if (state.quoteError != null) {
      return const _ComposerQuoteStatus(
        badgeLabel: 'Issue',
        title: 'Route issue',
        detail:
            'The swap service did not return a live route. The local draft remains editable.',
        iconName: AppIcons.warning,
        tone: _ComposerQuoteTone.error,
      );
    }

    final reviewQuote = state.reviewQuote;
    if (reviewQuote != null && state.quoteExpired) {
      return const _ComposerQuoteStatus(
        badgeLabel: 'Expired',
        title: 'Review again required',
        detail:
            'The locked quote expired; start is disabled until a fresh route is loaded.',
        iconName: AppIcons.time,
        tone: _ComposerQuoteTone.warning,
      );
    }

    if (reviewQuote != null) {
      return _ComposerQuoteStatus(
        badgeLabel: 'Locked',
        title: 'Live quote locked',
        detail: 'Minimum ${reviewQuote.minimumReceiveText}.',
        iconName: AppIcons.checkCircle,
        tone: _ComposerQuoteTone.success,
      );
    }

    if (state.sellAmount != null && state.draftAddressPlan != null) {
      return const _ComposerQuoteStatus(
        badgeLabel: 'Estimate',
        title: 'Estimated rate',
        detail:
            'Review fetches the live deposit address and minimum receive before anything moves.',
        iconName: AppIcons.crystalBall,
        tone: _ComposerQuoteTone.estimate,
      );
    }

    final missingDestination = state.sellAmount != null;
    return _ComposerQuoteStatus(
      badgeLabel: 'Draft',
      title: missingDestination ? 'Add destination details' : 'Enter a trade',
      detail: state.direction.sendsZec
          ? 'Choose an amount and external destination, then review the live quote.'
          : 'Choose an external amount and refund address; ZEC is received by this wallet.',
      iconName: AppIcons.link,
      tone: _ComposerQuoteTone.idle,
    );
  }

  final String badgeLabel;
  final String title;
  final String detail;
  final String iconName;
  final _ComposerQuoteTone tone;
}

class _SwapTicketHeader extends StatelessWidget {
  const _SwapTicketHeader({
    required this.quoteStatus,
    required this.slippageBps,
    required this.settingsOpen,
    required this.onSettingsTap,
  });

  final _ComposerQuoteStatus quoteStatus;
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
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'Powered by NEAR Intents',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.codeSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _QuoteReadinessBadge(status: quoteStatus),
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
      constraints: const BoxConstraints(minHeight: 96),
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
          const SizedBox(height: 2),
          Text(
            helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.xs),
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
        : _stripTrailingSymbol(quote!.receiveEstimateText, receiveSymbol);
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

class _InlineAddressField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_address_summary'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: _quietBoxDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              key: const ValueKey('swap_destination_field'),
              controller: controller,
              onChanged: onChanged,
              style: AppTypography.codeSmall.copyWith(
                color: colors.text.primary,
              ),
              cursorColor: colors.text.accent,
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: AppTypography.codeSmall.copyWith(
                  color: colors.text.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: Text(
              badge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
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
      width: 280,
      padding: const EdgeInsets.all(AppSpacing.xs),
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
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final preset in swapSlippagePresetBps)
                _SlippagePresetButton(
                  bps: preset,
                  selected: preset == widget.slippageBps,
                  onTap: () => widget.onSelected(preset),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  decoration: _quietBoxDecoration(context),
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('swap_slippage_custom_field'),
                          controller: _customController,
                          keyboardType: const TextInputType.numberWithOptions(
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
              const SizedBox(width: AppSpacing.xxs),
              AppButton(
                key: const ValueKey('swap_slippage_custom_apply'),
                onPressed: _applyCustomSlippage,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
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
      size: AppButtonSize.small,
      child: Text(_formatSlippage(bps)),
    );
  }
}

class _QuoteDetailsStrip extends StatelessWidget {
  const _QuoteDetailsStrip({required this.quoteStatus, required this.quote});

  final _ComposerQuoteStatus quoteStatus;
  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('swap_quote_details_strip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: _quietBoxDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuoteStatusPanel(status: quoteStatus),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: _QuoteDetailPill(label: 'Rate', value: quote.rateText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuoteDetailPill extends StatelessWidget {
  const _QuoteDetailPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.codeSmall.copyWith(
              color: value == '--' ? colors.text.disabled : colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteStatusPanel extends StatelessWidget {
  const _QuoteStatusPanel({required this.status});

  final _ComposerQuoteStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, status.tone);
    final iconColor = _toneIconColor(context, status.tone);
    return Row(
      key: const ValueKey('swap_quote_status_panel'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppIcon(status.iconName, size: 16, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            status.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(color: color),
          ),
        ),
      ],
    );
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
      padding: const EdgeInsets.all(AppSpacing.xs),
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
          AppIcon(AppIcons.warning, size: 18, color: colors.icon.destructive),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quote unavailable',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Check the connection and retry the quote.',
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
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
      constraints: const BoxConstraints(maxWidth: 168),
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
                    itemCount: assets.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xxs),
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      return _AssetMenuRow(
                        asset: asset,
                        selected: selected == asset,
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
        key: ValueKey('swap_asset_row_${asset.name}'),
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
                      asset.railLabel,
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

class _QuoteReadinessBadge extends StatelessWidget {
  const _QuoteReadinessBadge({required this.status});

  final _ComposerQuoteStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, status.tone);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        status.badgeLabel,
        style: AppTypography.labelSmall.copyWith(color: color),
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

Color _toneColor(BuildContext context, _ComposerQuoteTone tone) {
  final colors = context.colors;
  return switch (tone) {
    _ComposerQuoteTone.success => colors.text.success,
    _ComposerQuoteTone.warning ||
    _ComposerQuoteTone.loading ||
    _ComposerQuoteTone.estimate => colors.text.warning,
    _ComposerQuoteTone.error => colors.text.destructive,
    _ComposerQuoteTone.idle => colors.text.secondary,
  };
}

Color _toneIconColor(BuildContext context, _ComposerQuoteTone tone) {
  final colors = context.colors;
  return switch (tone) {
    _ComposerQuoteTone.success => colors.icon.success,
    _ComposerQuoteTone.warning ||
    _ComposerQuoteTone.loading ||
    _ComposerQuoteTone.estimate => colors.icon.warning,
    _ComposerQuoteTone.error => colors.icon.destructive,
    _ComposerQuoteTone.idle => colors.icon.muted,
  };
}

BoxDecoration _quietBoxDecoration(BuildContext context) {
  final colors = context.colors;
  return BoxDecoration(
    color: colors.background.raised,
    border: Border.all(color: colors.border.subtle),
    borderRadius: BorderRadius.circular(AppRadii.small),
  );
}
