import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/decimal_amount_input_formatter.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../address_book/widgets/contact_name_inline.dart';
import '../../../../core/formatting/address_display.dart';
import '../../models/swap_fiat_amount.dart';
import '../../models/swap_models.dart';
import '../one_time_address_label.dart';
import '../swap_asset_icon.dart';
import '../swap_confidential_ui.dart';

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
/// A Figma row height grown with the text size, so the row's text never
/// clips. The card height and the direction button's position use the same
/// values, so the layout stays aligned.
double _scaledSwapRowHeight(BuildContext context, double height) =>
    math.max(height, MediaQuery.textScalerOf(context).scale(height));

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
    this.destinationContactName,
    this.oneTimeZecAddress = false,
    this.preparingOneTimeAddress = false,
    this.confidentialReveal = 0,
    this.amountFocusNode,
    this.receiveAmountPlaceholder,
    this.receiveAmountMetaText,
    super.key,
  });

  final SwapState state;

  /// See [SwapComposerPanel.oneTimeZecAddress].
  final bool oneTimeZecAddress;

  /// See [SwapComposerPanel.preparingOneTimeAddress].
  final bool preparingOneTimeAddress;

  /// Address-book label for the current destination address, shown in the
  /// address chip instead of the truncated address when set.
  final String? destinationContactName;

  /// From the screen's [SwapConfidentialRevealCounter]: each rise plays the
  /// seam flip once.
  final int confidentialReveal;
  final FocusNode? amountFocusNode;

  final String? receiveAmountPlaceholder;
  final String? receiveAmountMetaText;
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

  // Card anatomy: 24px vertical padding (Figma's 20 plus a little breathing
  // room around the amounts), 17px title line (only while the side is
  // empty), 60px amount row, 32px bottom row.
  static const _cardVerticalPadding = AppSpacing.md;
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
    _amountFocusNode =
        widget.amountFocusNode ?? FocusNode(debugLabel: 'MobileSwapPayAmount');
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
    if (widget.amountFocusNode == null) _amountFocusNode.dispose();
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

  double _cardHeight(BuildContext context, {required bool showTitle}) {
    return _cardVerticalPadding * 2 +
        (showTitle ? _scaledSwapRowHeight(context, _titleRowHeight) : 0) +
        _scaledSwapRowHeight(context, _amountRowHeight) +
        _scaledSwapRowHeight(context, _bottomRowHeight);
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
        (!_receiveAmountFocusNode.hasFocus && state.quoteMode.usesInputAmount);
    final receiveActive = !payActive;

    final payCard = _SwapCard(
      // The active input's card carries the base tint; the other falls back
      // to the wrapper — mirrors the desktop composer's active-card
      // highlight that follows which side drives the quote.
      filled: payActive,
      // Always show the "You pay" / "You receive" labels (and MAX) instead of
      // collapsing them on the first keystroke: it reads better, holds the
      // card height steady (no switch-button hop), and removes the title-row
      // relayout entirely. A deliberate product step away from the Figma
      // filled frames, which hide the labels once a value is entered.
      showTitle: true,
      title: context.l10n.commonYouPay,
      titleTrailing: sendsZec
          ? _MaxAmountTrigger(
              availableText: widget.zecAvailableText,
              loading: state.maxAmountLoading,
              errorText: state.maxAmountError?.text(context.l10n),
              onTap: widget.onUseMaxZecAmount,
            )
          : null,
      amount: _SwapAmountInput(
        semanticsLabel: context.l10n.commonYouPay,
        key: const ValueKey('swap_amount_field'),
        controller: _amountController,
        focusNode: _amountFocusNode,
        onChanged: payInputIsFiat
            ? widget.onAmountFiatChanged
            : widget.onAmountChanged,
        prefixText: payInputIsFiat ? r'$' : null,
        maxFractionDigits: payInputIsFiat
            ? 2
            : state.direction.fromAsset(state.externalAsset).decimals,
      ),
      asset: sendsZec
          ? const _CurrencyPicker(
              asset: SwapAsset.zec,
              label: 'Zcash', // l10n-ignore: product name
            )
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
          ? (widget.oneTimeZecAddress
                ? const OneTimeAddressSlot(
                    role: OneTimeAddressRole.refund,
                    height: _MobileSwapComposerTicketState._bottomRowHeight,
                  )
                : null)
          : _AddressChip(
              value: state.destinationText,
              contactName: widget.destinationContactName,
              emptyText: context.l10n.swapComposerAddRefundAddressEllipsis,
              onTap: widget.onOpenDestinationAddress,
            ),
    );

    final receiveCard = _SwapCard(
      filled: receiveActive,
      showTitle: true,
      title: context.l10n.swapComposerYouReceive,
      amount: _SwapAmountInput(
        semanticsLabel: context.l10n.swapComposerYouReceive,
        key: const ValueKey('swap_receive_amount_field'),
        controller: _receiveAmountController,
        focusNode: _receiveAmountFocusNode,
        hintText: widget.receiveAmountPlaceholder ?? '0',
        onChanged: receiveInputIsFiat
            ? widget.onReceiveAmountFiatChanged
            : widget.onReceiveAmountChanged,
        prefixText: receiveInputIsFiat ? r'$' : null,
        maxFractionDigits: receiveInputIsFiat
            ? 2
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
          : const _CurrencyPicker(
              asset: SwapAsset.zec,
              label: 'Zcash', // l10n-ignore: product name
            ),
      fiat: _FiatModeToggle(
        text:
            widget.receiveAmountMetaText ??
            _amountMetaText(
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
              contactName: widget.destinationContactName,
              emptyText: context.l10n.swapComposerAddRecipientAddressEllipsis,
              onTap: widget.onOpenDestinationAddress,
            )
          : widget.oneTimeZecAddress
          ? OneTimeAddressSlot(
              role: OneTimeAddressRole.payout,
              height: _MobileSwapComposerTicketState._bottomRowHeight,
              preparing: widget.preparingOneTimeAddress,
            )
          : null,
    );

    final payCardHeight = _cardHeight(context, showTitle: true);
    final switchButtonTop =
        payCardHeight + _cardGap / 2 - _switchButtonSize / 2;

    return Container(
      key: const ValueKey('swap_compact_ticket'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(28),
        boxShadow: mobileSurfaceShadows(colors),
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
              child: SwapConfidentialSeamReveal(
                reveal: widget.confidentialReveal,
                on: widget.state.confidential,
                size: _switchButtonSize,
                radius: 18,
                faceBorder: Border.all(
                  color: context.colors.background.ground,
                  width: 6,
                ),
                child: _SwapDirectionButton(
                  tapKey: ValueKey('swap_direction_${targetDirection.name}'),
                  flipped: sendsZec,
                  onTap: widget.onToggleDirection,
                ),
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

  /// When true — the active input's side — the card carries the base tint;
  /// otherwise it falls back to the wrapper surface. The switch animates.
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
    return AnimatedContainer(
      // Mirrors the desktop composer's 140ms active-card highlight.
      duration: const Duration(milliseconds: 140),
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
              // Keyed so adding/removing the title row across an empty↔filled
              // transition does not positionally re-slot the amount/bottom
              // rows below — without keys the Column matches the unkeyed
              // SizedBoxes by index, rebuilding (recreating) the amount
              // field's EditableText into the old title's element. The
              // logical FocusNode (owned by this State) survives that, but on
              // a real device recreating the EditableText tears down and
              // reopens the platform text-input connection, which dismisses
              // the keyboard mid-entry.
              key: const ValueKey('swap_card_title'),
              height: _scaledSwapRowHeight(
                context,
                _MobileSwapComposerTicketState._titleRowHeight,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Readable label tone; muted falls under 4.5:1.
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
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
            // Keyed (with the title + bottom rows) so the focused amount
            // TextField keeps its element across the empty↔filled title-row
            // toggle — preserving the live platform keyboard connection.
            key: const ValueKey('swap_card_amount'),
            height: _scaledSwapRowHeight(
              context,
              _MobileSwapComposerTicketState._amountRowHeight,
            ),
            child: Row(
              children: [
                Expanded(child: amount),
                const SizedBox(width: AppSpacing.xs),
                asset,
              ],
            ),
          ),
          SizedBox(
            key: const ValueKey('swap_card_bottom'),
            height: _scaledSwapRowHeight(
              context,
              _MobileSwapComposerTicketState._bottomRowHeight,
            ),
            child: Row(
              children: [
                // Fiat meta takes only its (short) content width so the
                // address chip gets the rest of the row — otherwise the
                // greedy fiat squeezes "Add refund address..." down to
                // "Add refund a...". Figma 4700:121914 keeps the fiat
                // left and the address chip right-aligned.
                IntrinsicWidth(child: fiat),
                if (addressChip != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: addressChip!,
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

class _SwapAmountInput extends StatelessWidget {
  const _SwapAmountInput({
    required this.semanticsLabel,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.maxFractionDigits,
    this.prefixText,
    this.hintText = '0',
    super.key,
  });

  /// The card title ("You pay" / "You receive"), so a screen reader names
  /// the field instead of reading its "0" placeholder.
  final String semanticsLabel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String? prefixText;
  final String hintText;
  final int maxFractionDigits;

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
          child: Semantics(
            label: semanticsLabel,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                // The decimal-pad key follows the device locale, so map a
                // comma to the period the validator below expects.
                const CommaToDotInputFormatter(),
                DecimalAmountInputFormatter(
                  maxFractionDigits: maxFractionDigits,
                ),
              ],
              style: valueStyle,
              cursorColor: colors.text.accent,
              cursorWidth: 2,
              cursorRadius: const Radius.circular(AppRadii.full),
              decoration: InputDecoration.collapsed(
                // Muted "0" so an empty field reads as a placeholder rather
                // than an entered zero — matches the desktop composer, which
                // recolours the hint to text.disabled over the same serif.
                hintText: hintText,
                hintStyle: valueStyle.copyWith(color: colors.text.disabled),
              ),
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
          // Mobile composer uses a 40px asset (Figma) with a 0.5/0.1 badge
          // so the chain circle stays the same 20px as desktop's 32px asset.
          size: 40,
          badgeScale: 0.5,
          overhangScale: 0.1,
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
        // A pickable asset shows the list-row chevron; the fixed ZEC side
        // does not.
        if (onTap != null) ...[
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(
            AppIcons.chevronForward,
            key: const ValueKey('swap_currency_picker_chevron'),
            size: AppIconSize.medium,
            color: colors.icon.muted,
          ),
        ],
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
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
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(AppHaptics.selection());
          onTap();
        },
        child: content,
      ),
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({
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
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('swap_address_summary'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: _scaledSwapRowHeight(
            context,
            _MobileSwapComposerTicketState._bottomRowHeight,
          ),
          // No end inset, so the chip ends on the card's right edge like
          // "Max" and the asset name above it.
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xs,
            AppSpacing.xxs,
            0,
            AppSpacing.xxs,
          ),
          child: hasContact
              ? ContactNameInline(
                  name: name,
                  textStyle: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                  key: const ValueKey('swap_destination_value'),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.wallet,
                      size: 20,
                      color: colors.icon.accent,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        hasValue ? truncatedAddress(trimmed) : emptyText,
                        key: const ValueKey('swap_destination_value'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: hasValue
                              ? colors.text.accent
                              : colors.text.primary,
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
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('swap_max_amount_button'),
        behavior: HitTestBehavior.opaque,
        onTap: loading ? null : onTap,
        child: Text(
          errorText ?? context.l10n.swapComposerMaxAmount(availableText),
          key: const ValueKey('swap_available_balance'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge.copyWith(
            color: hasError ? colors.text.destructive : colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _SwapDirectionButton extends StatefulWidget {
  const _SwapDirectionButton({
    required this.tapKey,
    required this.flipped,
    required this.onTap,
  });

  /// Keys the tap target. It changes with the direction, so it sits inside
  /// the button: keying the button itself would remount it on every flip and
  /// drop the turn.
  final Key tapKey;

  /// Follows the swap direction; each change turns the arrows.
  final bool flipped;
  final VoidCallback onTap;

  @override
  State<_SwapDirectionButton> createState() => _SwapDirectionButtonState();
}

class _SwapDirectionButtonState extends State<_SwapDirectionButton>
    with SingleTickerProviderStateMixin {
  /// Strong ease-in-out, as the tab bar's swap arrows use.
  static const _turnCurve = Cubic(0.77, 0, 0.175, 1);
  static const _turnDuration = Duration(milliseconds: 300);

  // The rotation lives in this state, not in an implicit animation under
  // the keyed tap target: the key changes with every flip, which remounts
  // that subtree and would snap an implicit animation to its end.
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: _turnDuration,
  );

  /// Half a turn per flip, always the same way round. The arrows are
  /// symmetric under a half turn, so they rest looking unchanged.
  double _turns = 0;
  Animation<double> _rotation = const AlwaysStoppedAnimation(0);

  @override
  void didUpdateWidget(covariant _SwapDirectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flipped == widget.flipped) return;
    // A flip mid-turn continues from where the arrows are.
    final from = _rotation.value;
    _turns += 0.5;
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation = AlwaysStoppedAnimation(_turns);
      return;
    }
    _rotation = Tween<double>(
      begin: from,
      end: _turns,
    ).chain(CurveTween(curve: _turnCurve)).animate(_turn);
    _turn.forward(from: 0);
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.swapSwitchDirection,
      excludeSemantics: true,
      child: GestureDetector(
        key: widget.tapKey,
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: _MobileSwapComposerTicketState._switchButtonSize,
          height: _MobileSwapComposerTicketState._switchButtonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.background.inverse,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.background.ground, width: 6),
          ),
          child: RotationTransition(
            turns: _rotation,
            child: AppIcon(
              AppIcons.swapArrows,
              size: 20,
              color: colors.icon.inverse,
            ),
          ),
        ),
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
    return swapTokenAmountDisplayText(tokenAmountText: tokenAmountText);
  }
  return swapFiatDisplayText(
    state,
    asset: asset,
    tokenAmountText: tokenAmountText,
  );
}
