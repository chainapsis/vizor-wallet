import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../core/widgets/decimal_amount_input_formatter.dart';
import 'payment_link_action.dart';
import 'payment_link_gift_card.dart';

enum PaymentLinkAmountCurrency {
  zec,
  usd;

  String get label => name.toUpperCase();
}

/// The editable gift card and its input unit. Funding amounts remain in ZEC.
class PaymentLinkAmountCard extends StatefulWidget {
  const PaymentLinkAmountCard({
    required this.artwork,
    required this.amountController,
    required this.amountFocusNode,
    required this.currency,
    required this.onCurrencyChanged,
    required this.usdEnabled,
    required this.onAmountChanged,
    this.usdDisabledReason,
    this.supportingText,
    this.supportingLoading = false,
    this.maxAmountText,
    this.onUseMax,
    this.cardWidth = PaymentLinkGiftCard.width,
    this.cardHeight = PaymentLinkGiftCard.height,
    super.key,
  });

  final PaymentLinkCardArtwork artwork;
  final TextEditingController amountController;
  final FocusNode amountFocusNode;
  final PaymentLinkAmountCurrency currency;
  final ValueChanged<PaymentLinkAmountCurrency> onCurrencyChanged;
  final bool usdEnabled;
  final String? usdDisabledReason;
  final ValueChanged<String> onAmountChanged;
  final String? supportingText;
  final bool supportingLoading;
  final String? maxAmountText;
  final VoidCallback? onUseMax;
  final double cardWidth;
  final double cardHeight;

  static const selectionDuration = Duration(milliseconds: 180);
  static const conversionDuration = Duration(milliseconds: 120);

  @override
  State<PaymentLinkAmountCard> createState() => _PaymentLinkAmountCardState();
}

class _PaymentLinkAmountCardState extends State<PaymentLinkAmountCard>
    with TickerProviderStateMixin {
  static const _visualHeight = 32.0;
  static const _targetHeight = kAppFormFactor == AppFormFactor.mobile
      ? 44.0
      : _visualHeight;
  static const _hitSlop = (_targetHeight - _visualHeight) / 2;
  late final _selectionPosition = AnimationController(
    vsync: this,
    value: _isUsd ? 1 : 0,
    duration: PaymentLinkAmountCard.selectionDuration,
  );
  late final _conversionOpacity = AnimationController(
    vsync: this,
    value: 1,
    duration: PaymentLinkAmountCard.conversionDuration,
  );

  bool get _isUsd => widget.currency == PaymentLinkAmountCurrency.usd;
  bool get _motionDisabled =>
      MediaQuery.disableAnimationsOf(context) ||
      !TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionDisabled) _settleMotion();
  }

  @override
  void didUpdateWidget(covariant PaymentLinkAmountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currency == widget.currency) return;
    if (_motionDisabled) {
      _settleMotion();
      return;
    }
    _selectionPosition.animateTo(
      _isUsd ? 1 : 0,
      duration: PaymentLinkAmountCard.selectionDuration,
      curve: Curves.easeOutCubic,
    );
    // Repeated switches retarget from the current position and opacity.
    // Typing and price refreshes do not restart the supporting-value fade.
    if (!_conversionOpacity.isAnimating) _conversionOpacity.value = 0.55;
    _conversionOpacity.animateTo(
      1,
      duration: PaymentLinkAmountCard.conversionDuration,
      curve: Curves.easeOut,
    );
  }

  void _settleMotion() {
    _selectionPosition
      ..stop()
      ..value = _isUsd ? 1 : 0;
    _conversionOpacity
      ..stop()
      ..value = 1;
  }

  @override
  void dispose() {
    _selectionPosition.dispose();
    _conversionOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      PaymentLinkGiftCard(
        artwork: widget.artwork,
        cardWidth: widget.cardWidth,
        cardHeight: widget.cardHeight,
        amountController: widget.amountController,
        amountFocusNode: widget.amountFocusNode,
        amountEditorKey: const ValueKey('payment_link_amount_editor'),
        amountInputFormatters: [
          const CommaToDotInputFormatter(),
          DecimalAmountInputFormatter(maxFractionDigits: _isUsd ? 2 : 8),
        ],
        onAmountChanged: widget.onAmountChanged,
        currencySymbol: widget.currency.label,
        emptyAmountLabel: _isUsd ? 'Enter dollars' : 'Enter amount',
        supportingText: widget.supportingText,
        supportingLoading: widget.supportingLoading,
        supportingTextBuilder: (context, text) => FadeTransition(
          key: const ValueKey('payment_link_amount_conversion_fade'),
          opacity: _conversionOpacity,
          alwaysIncludeSemantics: true,
          child: text,
        ),
        maxAmountText: widget.maxAmountText,
        onUseMax: widget.onUseMax,
        showMaxButton: true,
        semanticLabel: 'Gift card amount input',
      ),
      Positioned(
        top: AppSpacing.sm - _hitSlop,
        left: AppSpacing.sm,
        child: AnimatedBuilder(
          animation: _selectionPosition,
          builder: (context, _) => _buildSelector(context),
        ),
      ),
    ],
  );

  Widget _buildSelector(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        top: _hitSlop,
        bottom: _hitSlop,
        child: DecoratedBox(
          key: const ValueKey('payment_link_amount_currency_visual'),
          decoration: BoxDecoration(
            color: context.colors.button.secondary.bg,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      ),
      Positioned(
        top: (_targetHeight - 28) / 2,
        left: 2,
        child: IgnorePointer(
          child: Transform.translate(
            offset: Offset(60 * _selectionPosition.value, 0),
            child: DecoratedBox(
              key: const ValueKey('payment_link_amount_currency_indicator'),
              decoration: BoxDecoration(
                color: context.colors.button.primary.bg,
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: const SizedBox(width: 56, height: 28),
            ),
          ),
        ),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final currency in PaymentLinkAmountCurrency.values)
            _buildOption(context, currency),
        ],
      ),
    ],
  );

  Widget _buildOption(
    BuildContext context,
    PaymentLinkAmountCurrency currency,
  ) {
    final colors = context.colors;
    final selected = widget.currency == currency;
    final enabled =
        currency == PaymentLinkAmountCurrency.zec || widget.usdEnabled;
    final progress = currency == PaymentLinkAmountCurrency.usd
        ? _selectionPosition.value
        : 1 - _selectionPosition.value;
    final labelColor = enabled || selected
        ? Color.lerp(
            colors.button.secondary.label,
            colors.button.primary.label,
            progress,
          )!
        : colors.button.secondary.label.withValues(alpha: 0.45);
    final label = Text(
      currency.label,
      style: AppTypography.labelMedium.copyWith(
        color: labelColor,
        fontWeight: FontWeight.w600,
      ),
    );
    final action = PaymentLinkAction(
      key: ValueKey('payment_link_amount_currency_${currency.name}'),
      semanticLabel: !enabled && widget.usdDisabledReason != null
          ? 'Enter amount in ${currency.label}. ${widget.usdDisabledReason}'
          : 'Enter amount in ${currency.label}',
      selected: selected,
      onPressed: enabled ? () => widget.onCurrencyChanged(currency) : null,
      builder: (context, hovered, focused) => SizedBox(
        width: 60,
        height: _targetHeight,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: !selected && hovered
                  ? colors.button.secondary.bgHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.full),
              border: focused
                  ? Border.all(color: colors.state.focusRing, width: 1.5)
                  : null,
            ),
            child: SizedBox(width: 56, height: 28, child: Center(child: label)),
          ),
        ),
      ),
    );
    return !enabled && widget.usdDisabledReason != null
        ? AppTooltip(
            message: widget.usdDisabledReason!,
            tapToShow: true,
            excludeFromSemantics: true,
            child: Builder(
              builder: (context) => GestureDetector(
                // The tooltip's tap trigger handles touch, but not mouse clicks.
                supportedDevices: const {PointerDeviceKind.mouse},
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => context
                    .findAncestorStateOfType<TooltipState>()
                    ?.ensureTooltipVisible(),
                child: action,
              ),
            ),
          )
        : action;
  }
}
