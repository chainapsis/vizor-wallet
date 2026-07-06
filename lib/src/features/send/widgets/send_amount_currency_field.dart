import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../models/send_amount_currency.dart';

class SendAmountCurrencyField extends StatefulWidget {
  const SendAmountCurrencyField({
    required this.mode,
    required this.conversionText,
    required this.rightSlot,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.label = 'Amount',
    this.hintText,
    this.tone = AppTextFieldTone.neutral,
    this.messageText,
    this.messageIcon,
    this.autofocus = false,
    this.inputFormatters,
    this.onChanged,
    this.onClear,
    this.onToggleMode,
    this.canToggleMode = true,
    this.isPriceLoading = false,
    this.showClearButton = true,
    this.clearButtonSemanticLabel = 'Clear amount',
    super.key,
  }) : assert(
         controller == null || initialValue == null,
         'Provide either controller or initialValue, not both.',
       );

  final SendAmountInputMode mode;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String label;
  final String? hintText;
  final AppTextFieldTone tone;
  final String? messageText;
  final Widget? messageIcon;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final VoidCallback? onToggleMode;
  final bool canToggleMode;
  final bool isPriceLoading;
  final String? conversionText;
  final Widget rightSlot;
  final bool showClearButton;
  final String clearButtonSemanticLabel;

  @override
  State<SendAmountCurrencyField> createState() =>
      _SendAmountCurrencyFieldState();
}

class _SendAmountCurrencyFieldState extends State<SendAmountCurrencyField> {
  static const _fieldShellHeight = AppInputSizing.height;
  static const _fieldShellRadius = AppInputSizing.radius;
  static const _inputIconSize = AppInputSizing.iconSize;
  static const _inputTextGap = 2.0;
  static const _metaHeight = 16.0;

  late final TextEditingController _internalController;
  late final FocusNode _internalFocusNode;
  final GlobalKey _textFieldRegionKey = GlobalKey();
  TextEditingController? _attachedController;
  FocusNode? _attachedFocusNode;
  bool _hovered = false;

  TextEditingController get _controller =>
      widget.controller ?? _internalController;
  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  bool get _isFocused => _focusNode.hasFocus;
  bool get _hasText => _controller.text.trim().isNotEmpty;
  bool get _isUsd => widget.mode == SendAmountInputMode.usd;
  bool get _isDestructive => widget.tone == AppTextFieldTone.destructive;
  bool get _showMessage =>
      widget.messageText != null && widget.messageText!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _internalController = TextEditingController(text: widget.initialValue);
    _internalFocusNode = FocusNode(debugLabel: 'SendAmountCurrencyField');
    _attachController(_controller);
    _attachFocusNode(_focusNode);
  }

  @override
  void didUpdateWidget(covariant SendAmountCurrencyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(_attachedController);
      _attachController(_controller);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusNode(_attachedFocusNode);
      _attachFocusNode(_focusNode);
    }
    if (widget.controller == null &&
        oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != _internalController.text) {
      _internalController.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _detachController(_attachedController);
    _detachFocusNode(_attachedFocusNode);
    _internalController.dispose();
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _attachController(TextEditingController controller) {
    _attachedController = controller;
    controller.addListener(_handleControllerChanged);
  }

  void _detachController(TextEditingController? controller) {
    controller?.removeListener(_handleControllerChanged);
  }

  void _attachFocusNode(FocusNode focusNode) {
    _attachedFocusNode = focusNode;
    focusNode.addListener(_handleVisualStateChanged);
  }

  void _detachFocusNode(FocusNode? focusNode) {
    focusNode?.removeListener(_handleVisualStateChanged);
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleVisualStateChanged() {
    if (mounted) setState(() {});
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  bool _positionIsInsideTextFieldRegion(Offset globalPosition) {
    final context = _textFieldRegionKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final localPosition = renderObject.globalToLocal(globalPosition);
    return (Offset.zero & renderObject.size).contains(localPosition);
  }

  void _handleShellPointerDown(PointerDownEvent event) {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    if (_positionIsInsideTextFieldRegion(event.position)) return;
    final selection = TextSelection.collapsed(offset: _controller.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      final textLength = _controller.text.length;
      final offset = selection.baseOffset > textLength
          ? textLength
          : selection.baseOffset;
      _controller.selection = TextSelection.collapsed(offset: offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle = AppTypography.bodyMedium.copyWith(
      color: _isDestructive ? colors.text.destructive : colors.text.accent,
    );
    final hintStyle = valueStyle.copyWith(color: colors.text.disabled);
    final titleStyle = AppTypography.labelMedium.copyWith(
      color: colors.text.secondary,
    );
    final metaStyle = AppTypography.labelMedium.copyWith(
      color: colors.text.secondary,
    );
    final iconColor = _isDestructive
        ? colors.icon.destructive
        : _hasText
        ? colors.icon.accent
        : colors.icon.regular;
    final textStrutStyle = StrutStyle.fromTextStyle(
      valueStyle,
      forceStrutHeight: true,
    );
    final shellColor = widget.tone == AppTextFieldTone.destructive
        ? Color.alphaBlend(
            colors.background.utilityDestructiveAlphaSubtle,
            colors.surface.input.primary,
          )
        : colors.surface.input.primary;
    final borderColor = switch (widget.tone) {
      AppTextFieldTone.neutral when _isFocused => colors.background.inverse,
      AppTextFieldTone.neutral when _hovered => colors.border.subtleOpacity,
      AppTextFieldTone.neutral => Colors.transparent,
      AppTextFieldTone.destructive => colors.border.utilityDestructiveSubtle,
      AppTextFieldTone.success => colors.border.utilitySuccess,
      AppTextFieldTone.brandCrimson => colors.border.brandCrimsonStrong,
    };
    final messageColor = switch (widget.tone) {
      AppTextFieldTone.destructive => colors.text.destructive,
      AppTextFieldTone.success => colors.text.success,
      AppTextFieldTone.brandCrimson => colors.text.brandCrimson,
      AppTextFieldTone.neutral => colors.text.secondary,
    };
    final boxShadow = widget.tone == AppTextFieldTone.destructive
        ? const <BoxShadow>[]
        : appSurfaceShadow(colors);
    final shouldShowClearButton =
        widget.showClearButton && _hasText && (_isFocused || _hovered);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(widget.label, style: titleStyle)),
                widget.rightSlot,
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              height: _fieldShellHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                onEnter: (_) => _setHovered(true),
                onExit: (_) => _setHovered(false),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleShellPointerDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _focusNode.requestFocus,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: shellColor,
                        borderRadius: BorderRadius.circular(_fieldShellRadius),
                        border: Border.all(
                          color: borderColor,
                          width: 1.5,
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                        boxShadow: boxShadow,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            AppIcon(
                              _isUsd ? AppIcons.moneyBag : AppIcons.zcash,
                              size: _inputIconSize,
                              color: iconColor,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final textWidth = _measureInputTextWidth(
                                    context,
                                    text: _hasText
                                        ? _controller.text
                                        : widget.hintText ?? '',
                                    style: _hasText ? valueStyle : hintStyle,
                                  );
                                  final prefixWidth = _isUsd
                                      ? _measureInputTextWidth(
                                              context,
                                              text: r'$',
                                              style: valueStyle,
                                            ) +
                                            _inputTextGap
                                      : 0.0;
                                  final suffixWidth = !_isUsd
                                      ? _measureInputTextWidth(
                                              context,
                                              text: 'ZEC',
                                              style: valueStyle,
                                            ) +
                                            _inputTextGap
                                      : 0.0;
                                  final maxInputWidth =
                                      (constraints.maxWidth -
                                              prefixWidth -
                                              suffixWidth)
                                          .clamp(8.0, constraints.maxWidth)
                                          .toDouble();
                                  final inputWidth =
                                      (textWidth + (_hasText ? 2.0 : 0.0))
                                          .clamp(8.0, maxInputWidth)
                                          .toDouble();

                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_isUsd) ...[
                                        Text(
                                          r'$',
                                          key: const ValueKey(
                                            'send_amount_usd_prefix',
                                          ),
                                          style: valueStyle,
                                          strutStyle: textStrutStyle,
                                        ),
                                        const SizedBox(width: _inputTextGap),
                                      ],
                                      SizedBox(
                                        width: inputWidth,
                                        child: Stack(
                                          children: [
                                            if ((widget.hintText ?? '')
                                                    .isNotEmpty &&
                                                !_hasText)
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: Align(
                                                    alignment:
                                                        AlignmentDirectional
                                                            .centerStart,
                                                    child: Text(
                                                      widget.hintText!,
                                                      style: hintStyle,
                                                      strutStyle:
                                                          textStrutStyle,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            TextField(
                                              key: _textFieldRegionKey,
                                              controller: _controller,
                                              focusNode: _focusNode,
                                              autofocus: widget.autofocus,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              textInputAction:
                                                  TextInputAction.done,
                                              inputFormatters:
                                                  widget.inputFormatters,
                                              onChanged: widget.onChanged,
                                              maxLines: 1,
                                              textAlignVertical:
                                                  TextAlignVertical.center,
                                              style: valueStyle,
                                              strutStyle: textStrutStyle,
                                              cursorColor: _isDestructive
                                                  ? colors.text.destructive
                                                  : colors.text.accent,
                                              decoration: null,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!_isUsd) ...[
                                        const SizedBox(width: _inputTextGap),
                                        Text(
                                          'ZEC',
                                          key: const ValueKey(
                                            'send_amount_zec_suffix',
                                          ),
                                          style: valueStyle,
                                          strutStyle: textStrutStyle,
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                            if (shouldShowClearButton) ...[
                              const SizedBox(width: AppSpacing.xs),
                              _SendAmountClearButton(
                                onTap: _clear,
                                semanticLabel: widget.clearButtonSemanticLabel,
                                iconColor: colors.icon.regular,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              height: _metaHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _AmountConversionToggle(
                  isUsd: _isUsd,
                  enabled: widget.canToggleMode,
                  isLoading: widget.isPriceLoading,
                  conversionText: widget.conversionText,
                  textStyle: metaStyle,
                  onTap: widget.canToggleMode ? widget.onToggleMode : null,
                ),
              ),
            ),
          ],
        ),
        if (_showMessage)
          Positioned(
            top:
                16.0 +
                AppSpacing.xxs +
                _fieldShellHeight +
                AppSpacing.xxs +
                _metaHeight +
                AppSpacing.xxs,
            left: 0,
            right: 0,
            child: _AmountFieldMessage(
              text: widget.messageText!,
              icon:
                  widget.messageIcon ??
                  AppIcon(AppIcons.warning, size: 16, color: messageColor),
              style: AppTypography.labelMedium.copyWith(color: messageColor),
            ),
          ),
      ],
    );
  }

  double _measureInputTextWidth(
    BuildContext context, {
    required String text,
    required TextStyle style,
  }) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _SendAmountClearButton extends StatelessWidget {
  const _SendAmountClearButton({
    required this.onTap,
    required this.iconColor,
    required this.semanticLabel,
  });

  final VoidCallback onTap;
  final Color iconColor;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('send_amount_clear_button'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AppIcon(AppIcons.cross, size: 20, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _AmountConversionToggle extends StatelessWidget {
  const _AmountConversionToggle({
    required this.isUsd,
    required this.enabled,
    required this.isLoading,
    required this.conversionText,
    required this.textStyle,
    this.onTap,
  });

  final bool isUsd;
  final bool enabled;
  final bool isLoading;
  final String? conversionText;
  final TextStyle textStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: isUsd ? 'Enter amount in ZEC' : 'Enter amount in USD',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          key: const ValueKey('send_amount_currency_toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.doubleArrowVertical,
                size: 16,
                color: colors.text.secondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              if (isLoading) ...[
                Text(r'$', style: textStyle),
                const SizedBox(width: AppSpacing.xxs),
                const SendAmountPriceLoadingBar(),
              ] else
                Text(
                  conversionText ?? '',
                  key: const ValueKey('send_amount_conversion_text'),
                  style: textStyle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountFieldMessage extends StatelessWidget {
  const _AmountFieldMessage({
    required this.text,
    required this.icon,
    required this.style,
  });

  final String text;
  final Widget icon;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('send_amount_field_message'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 16, height: 16, child: icon),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class SendAmountPriceLoadingBar extends StatefulWidget {
  const SendAmountPriceLoadingBar({super.key});

  @override
  State<SendAmountPriceLoadingBar> createState() =>
      _SendAmountPriceLoadingBarState();
}

class _SendAmountPriceLoadingBarState extends State<SendAmountPriceLoadingBar>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 1200);
  static const _width = 74.0;
  static const _height = 8.0;
  AnimationController? _controller;

  AnimationController get _activeController {
    return _controller ??= AnimationController(vsync: this, duration: _period);
  }

  bool get _shouldAnimate {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return false;
    return TickerMode.valuesOf(context).enabled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SendAmountPriceLoadingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final controller = _controller;
    if (_shouldAnimate) {
      if (!_activeController.isAnimating) _activeController.repeat();
      return;
    }
    if (controller != null) {
      controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final baseColor = colors.background.overlay.withValues(alpha: 0.15);
    final highlightColor = colors.background.raised;
    final staticPainter = _SendAmountPriceLoadingPainter(
      progress: 0,
      baseColor: baseColor,
      highlightColor: highlightColor,
      animate: false,
    );

    return SizedBox(
      key: const ValueKey('send_amount_price_loading'),
      width: _width,
      height: _height,
      child: _shouldAnimate
          ? AnimatedBuilder(
              animation: _activeController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SendAmountPriceLoadingPainter(
                    progress: _activeController.value,
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                  ),
                );
              },
            )
          : CustomPaint(painter: staticPainter),
    );
  }
}

class _SendAmountPriceLoadingPainter extends CustomPainter {
  const _SendAmountPriceLoadingPainter({
    required this.progress,
    required this.baseColor,
    required this.highlightColor,
    this.animate = true,
  });

  final double progress;
  final Color baseColor;
  final Color highlightColor;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(AppRadii.full));
    if (!animate) {
      final shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [highlightColor, baseColor],
      ).createShader(rect);
      canvas.drawRRect(rrect, Paint()..shader = shader);
      return;
    }

    canvas.drawRRect(rrect, Paint()..color = baseColor);
    canvas.save();
    canvas.clipRRect(rrect);
    final sweepWidth = size.width * 1.6;
    final left = -sweepWidth + progress * (size.width + sweepWidth);
    final sweepRect = Rect.fromLTWH(left, 0, sweepWidth, size.height);
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        baseColor.withValues(alpha: 0),
        highlightColor,
        baseColor.withValues(alpha: 0),
      ],
      stops: const [0, 0.5, 1],
    ).createShader(sweepRect);
    canvas.drawRect(sweepRect, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SendAmountPriceLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.animate != animate;
  }
}

class SendAmountHeaderControls extends StatelessWidget {
  const SendAmountHeaderControls({
    required this.label,
    this.onLabelPressed,
    this.labelSemanticLabel = 'Use maximum spendable balance',
    this.onInfoPressed,
    this.infoSemanticLabel = 'Spendable balance info',
    super.key,
  });

  static const iconTargetKey = ValueKey('send_spendable_info_icon_target');

  final String label;
  final VoidCallback? onLabelPressed;
  final String labelSemanticLabel;
  final VoidCallback? onInfoPressed;
  final String infoSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelText = Text(
      label,
      style: AppTypography.labelMedium.copyWith(color: colors.text.secondary),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _wrapMaybeButton(
          enabled: onLabelPressed != null,
          semanticLabel: labelSemanticLabel,
          onTap: onLabelPressed,
          child: labelText,
        ),
        const SizedBox(width: AppSpacing.xxs),
        _wrapMaybeButton(
          enabled: onInfoPressed != null,
          semanticLabel: infoSemanticLabel,
          onTap: onInfoPressed,
          child: SizedBox(
            key: iconTargetKey,
            width: AppIconSize.medium,
            height: AppIconSize.medium,
            child: Center(
              child: AppIcon(
                AppIcons.help,
                size: AppIconSize.medium,
                color: colors.icon.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _wrapMaybeButton({
    required bool enabled,
    required String semanticLabel,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    if (!enabled) return child;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}
