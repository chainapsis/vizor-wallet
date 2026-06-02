import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'app_tooltip.dart';

enum AppTextFieldTone { neutral, destructive, success, brandCrimson }

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.rightLabel,
    this.rightSlot,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.hintText,
    this.showLabel = true,
    this.leadingSlotWidth,
    this.trailingSlotWidth,
    this.inputHorizontalPadding,
    this.inputBottomPadding,
    this.leading,
    this.trailing,
    this.messageText,
    this.messageIcon,
    this.messageStyle,
    this.tone = AppTextFieldTone.neutral,
    this.showClearButton = false,
    this.clearButtonRequiresText = true,
    this.clearButtonSemanticLabel = 'Clear text',
    this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.scrollController,
    this.textStyle,
    this.hintStyle,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
  }) : assert(
         controller == null || initialValue == null,
         'Provide either controller or initialValue, not both.',
       ),
       assert(
         rightLabel == null || rightSlot == null,
         'Provide either rightLabel or rightSlot, not both.',
       );

  final String label;
  final String? rightLabel;
  final Widget? rightSlot;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String? hintText;
  final bool showLabel;
  final double? leadingSlotWidth;
  final double? trailingSlotWidth;
  final double? inputHorizontalPadding;
  final double? inputBottomPadding;
  final Widget? leading;
  final Widget? trailing;
  final String? messageText;
  final Widget? messageIcon;
  final TextStyle? messageStyle;
  final AppTextFieldTone tone;
  final bool showClearButton;
  final bool clearButtonRequiresText;
  final String clearButtonSemanticLabel;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ScrollController? scrollController;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  static const _multilineClearButtonKey = ValueKey(
    'app-text-field-multiline-clear-button',
  );
  static const _multilineClearSlotKey = ValueKey(
    'app-text-field-multiline-clear-slot',
  );
  static const _multilineScrollbarKey = ValueKey(
    'app-text-field-multiline-scrollbar',
  );

  late final TextEditingController _internalController;
  late final FocusNode _internalFocusNode;
  final GlobalKey _textFieldRegionKey = GlobalKey();
  TextEditingController? _attachedController;
  FocusNode? _attachedFocusNode;
  bool _hovered = false;
  Offset? _pendingShellTapGlobalPosition;

  TextEditingController get _controller =>
      widget.controller ?? _internalController;
  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;
  bool get _multiline => widget.maxLines > 1 || widget.minLines > 1;
  bool get _hasText => _controller.text.isNotEmpty;
  bool get _isFocused => _focusNode.hasFocus;
  bool get _showMessage =>
      widget.messageText != null && widget.messageText!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _internalController = TextEditingController(text: widget.initialValue);
    _internalFocusNode = FocusNode();
    _attachListeners();
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attachListeners();
  }

  @override
  void dispose() {
    _attachedController?.removeListener(_handleTextChanged);
    _attachedFocusNode?.removeListener(_handleFocusChanged);
    _internalController.dispose();
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _attachListeners() {
    final nextController = _controller;
    if (!identical(_attachedController, nextController)) {
      _attachedController?.removeListener(_handleTextChanged);
      nextController.addListener(_handleTextChanged);
      _attachedController = nextController;
    }

    final nextFocusNode = _focusNode;
    if (!identical(_attachedFocusNode, nextFocusNode)) {
      _attachedFocusNode?.removeListener(_handleFocusChanged);
      nextFocusNode.addListener(_handleFocusChanged);
      _attachedFocusNode = nextFocusNode;
    }
  }

  void _handleTextChanged() => setState(() {});

  void _handleFocusChanged() => setState(() {});

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
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

  TextSelection _selectionForShellPointer(
    Offset globalPosition,
    TextStyle valueStyle,
    StrutStyle textStrutStyle,
  ) {
    if (_controller.text.isEmpty) {
      return const TextSelection.collapsed(offset: 0);
    }

    final regionContext = _textFieldRegionKey.currentContext;
    final renderObject = regionContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return TextSelection.collapsed(offset: _controller.text.length);
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    final clampedPosition = Offset(
      localPosition.dx.clamp(0.0, renderObject.size.width),
      localPosition.dy.clamp(0.0, renderObject.size.height),
    );

    final textPainter = TextPainter(
      text: TextSpan(text: _controller.text, style: valueStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      strutStyle: textStrutStyle,
      maxLines: _multiline ? null : 1,
    )..layout(maxWidth: renderObject.size.width);

    final position = textPainter.getPositionForOffset(clampedPosition);
    return TextSelection.collapsed(offset: position.offset);
  }

  void _handleShellTapDown(TapDownDetails details) {
    _pendingShellTapGlobalPosition = details.globalPosition;
  }

  void _requestFocusFromShell(TextStyle valueStyle, StrutStyle textStrutStyle) {
    final globalPosition = _pendingShellTapGlobalPosition;
    _pendingShellTapGlobalPosition = null;
    if (!widget.enabled || widget.readOnly || globalPosition == null) return;
    if (_positionIsInsideTextFieldRegion(globalPosition)) return;
    final selection = _selectionForShellPointer(
      globalPosition,
      valueStyle,
      textStrutStyle,
    );
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      _controller.selection = selection;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleStyle = AppTypography.labelMedium.copyWith(
      color: colors.text.secondary,
    );
    final hintStyle =
        widget.hintStyle ??
        AppTypography.labelLarge.copyWith(color: colors.text.muted);
    final valueStyle =
        widget.textStyle ??
        AppTypography.labelLarge.copyWith(color: colors.text.accent);
    final defaultHintStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.muted,
    );
    final resolvedHintStyle = hintStyle.copyWith(
      color: hintStyle.color ?? defaultHintStyle.color,
    );
    final neutralIconColor = _hasText || _isFocused
        ? colors.icon.accent
        : colors.icon.regular;
    final leadingIconColor = switch (widget.tone) {
      AppTextFieldTone.neutral => neutralIconColor,
      AppTextFieldTone.destructive => colors.icon.destructive,
      AppTextFieldTone.success => colors.icon.success,
      AppTextFieldTone.brandCrimson => colors.icon.brandCrimson,
    };
    final gap = _multiline ? AppSpacing.xs : AppSpacing.xxs;
    final shellHeight = _multiline ? 148.0 : 46.0;
    const shellRadius = AppRadii.small;
    const focusRingWidth = 3.0;
    const focusRingStrokeWidth = 2.0;
    final useFixedSlotLayout =
        !_multiline &&
        (widget.leadingSlotWidth != null ||
            widget.trailingSlotWidth != null ||
            widget.inputHorizontalPadding != null ||
            widget.inputBottomPadding != null);
    final titleHeight = widget.showLabel ? 16.0 : 0.0;
    final titleGap = widget.showLabel ? gap : 0.0;
    final messageTop = titleHeight + titleGap + shellHeight + gap;
    final textStrutStyle = StrutStyle.fromTextStyle(
      valueStyle,
      forceStrutHeight: true,
    );

    final isNeutralTone = widget.tone == AppTextFieldTone.neutral;
    final borderColor = switch (widget.tone) {
      AppTextFieldTone.neutral when _isFocused || _hasText =>
        colors.border.medium,
      AppTextFieldTone.neutral when _hovered => colors.border.regular,
      AppTextFieldTone.neutral => colors.border.subtle,
      AppTextFieldTone.destructive => colors.border.utilityDestructive,
      AppTextFieldTone.success => colors.border.utilitySuccess,
      AppTextFieldTone.brandCrimson => colors.border.brandCrimsonStrong,
    };
    final focusRingColor = switch (widget.tone) {
      AppTextFieldTone.neutral => colors.state.focusRing,
      AppTextFieldTone.destructive => colors.border.utilityDestructive,
      AppTextFieldTone.success => colors.border.utilitySuccess,
      AppTextFieldTone.brandCrimson => colors.border.brandCrimsonStrong,
    };
    final messageColor = switch (widget.tone) {
      AppTextFieldTone.neutral => colors.text.secondary,
      AppTextFieldTone.destructive => colors.text.destructive,
      AppTextFieldTone.success => colors.text.success,
      AppTextFieldTone.brandCrimson => colors.text.brandCrimson,
    };
    final defaultMessageIcon = switch (widget.tone) {
      AppTextFieldTone.neutral => null,
      AppTextFieldTone.destructive => AppIcon(
        AppIcons.warning,
        size: AppIconSize.medium,
        color: messageColor,
      ),
      AppTextFieldTone.success => AppIcon(
        AppIcons.checkCircle,
        size: AppIconSize.medium,
        color: messageColor,
      ),
      AppTextFieldTone.brandCrimson => AppIcon(
        AppIcons.shieldKeyhole,
        size: AppIconSize.medium,
        color: messageColor,
      ),
    };
    final shouldShowClearButton =
        widget.showClearButton &&
        (_isFocused || _hovered) &&
        (!widget.clearButtonRequiresText || _hasText) &&
        widget.enabled &&
        !widget.readOnly;
    final trailingWidget = shouldShowClearButton ? null : widget.trailing;
    final clearButton = shouldShowClearButton
        ? _AppTextFieldClearButton(
            onTap: _clear,
            iconColor: neutralIconColor,
            semanticLabel: widget.clearButtonSemanticLabel,
          )
        : null;

    final textField = TextField(
      key: _textFieldRegionKey,
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      enableSuggestions: widget.enableSuggestions,
      autocorrect: widget.autocorrect,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      maxLines: _multiline ? null : 1,
      minLines: _multiline ? null : 1,
      expands: _multiline,
      scrollController: widget.scrollController,
      textAlignVertical: _multiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      style: valueStyle,
      strutStyle: textStrutStyle,
      cursorColor: colors.text.accent,
      selectAllOnFocus: false,
      decoration: InputDecoration.collapsed(
        hintText: widget.hintText,
        hintStyle: resolvedHintStyle,
      ),
    );
    final fieldInput = _multiline
        ? ScrollConfiguration(
            behavior: _AppTextFieldNoScrollbarBehavior(
              ScrollConfiguration.of(context),
            ),
            child: textField,
          )
        : textField;

    final shell = SizedBox(
      height: shellHeight,
      child: MouseRegion(
        cursor: widget.enabled && !widget.readOnly
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: _handleShellTapDown,
          onTap: () => _requestFocusFromShell(valueStyle, textStrutStyle),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_isFocused)
                      Positioned(
                        left: -focusRingWidth,
                        top: -focusRingWidth,
                        right: -focusRingWidth,
                        bottom: -focusRingWidth,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                shellRadius + focusRingWidth,
                              ),
                              border: Border.all(
                                color: focusRingColor,
                                width: focusRingStrokeWidth,
                                strokeAlign: BorderSide.strokeAlignInside,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface.input,
                          borderRadius: BorderRadius.circular(shellRadius),
                          border: Border.all(
                            color: borderColor,
                            width: 1.5,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Keep this hover layer in the tree at all times and only vary opacity.
              // Inserting/removing a same-typed Stack sibling around the desktop
              // TextField caused the EditableText subtree to be replaced during
              // hover/focus transitions, which made focus visuals appear while text
              // input/caret handling broke. Apply the same rule to any future
              // conditional overlay siblings in this Stack.
              Positioned.fill(
                child: Opacity(
                  opacity: _hovered && !_isFocused && isNeutralTone ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.state.hover,
                      borderRadius: BorderRadius.circular(shellRadius),
                    ),
                  ),
                ),
              ),
              if (_multiline && widget.scrollController != null)
                Positioned(
                  right: 1.5,
                  top: -1.5,
                  width: 12,
                  height: shellHeight,
                  child: IgnorePointer(
                    child: _AppTextFieldScrollbar(
                      key: _multilineScrollbarKey,
                      controller: widget.scrollController!,
                      thumbColor: colors.background.neutralStrongOpacity,
                    ),
                  ),
                ),
              Positioned.fill(
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: neutralIconColor,
                    size: AppIconSize.large,
                  ),
                  child: _multiline
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.leading != null)
                              SizedBox(
                                width: 28,
                                height: 48,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: AppSpacing.xs,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: IconTheme.merge(
                                      data: IconThemeData(
                                        color: leadingIconColor,
                                        size: 20,
                                      ),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: widget.leading,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.s,
                                  AppSpacing.s,
                                  0,
                                  AppSpacing.s,
                                ),
                                child: fieldInput,
                              ),
                            ),
                            if (widget.showClearButton &&
                                trailingWidget == null)
                              SizedBox(
                                key: _multilineClearSlotKey,
                                width: 40,
                                height: 48,
                                child: clearButton == null
                                    ? const SizedBox.shrink()
                                    : SizedBox(
                                        key: _multilineClearButtonKey,
                                        child: clearButton,
                                      ),
                              )
                            else if (trailingWidget != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.xs,
                                  AppSpacing.s,
                                  AppSpacing.sm,
                                  0,
                                ),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: trailingWidget,
                                ),
                              ),
                          ],
                        )
                      : useFixedSlotLayout
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (widget.leading != null)
                              SizedBox(
                                width: widget.leadingSlotWidth ?? 32,
                                height: shellHeight,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: IconTheme.merge(
                                    data: IconThemeData(
                                      color: leadingIconColor,
                                      size: 20,
                                    ),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: widget.leading,
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left:
                                      widget.inputHorizontalPadding ??
                                      AppSpacing.s,
                                  right:
                                      widget.inputHorizontalPadding ??
                                      AppSpacing.s,
                                  bottom: widget.inputBottomPadding ?? 6,
                                ),
                                child: fieldInput,
                              ),
                            ),
                            if (widget.trailingSlotWidth != null ||
                                trailingWidget != null ||
                                clearButton != null)
                              SizedBox(
                                width: widget.trailingSlotWidth ?? 40,
                                height: shellHeight,
                                child:
                                    clearButton ??
                                    Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: trailingWidget,
                                      ),
                                    ),
                              ),
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (widget.leading != null)
                                IconTheme.merge(
                                  data: IconThemeData(
                                    color: leadingIconColor,
                                    size: AppIconSize.large,
                                  ),
                                  child: SizedBox(
                                    width: AppIconSize.large,
                                    height: AppIconSize.large,
                                    child: widget.leading,
                                  ),
                                ),
                              if (widget.leading != null)
                                const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: fieldInput,
                                ),
                              ),
                              if (clearButton != null) ...[
                                const SizedBox(width: AppSpacing.xs),
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: clearButton,
                                ),
                              ] else if (trailingWidget != null) ...[
                                const SizedBox(width: AppSpacing.xs),
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: trailingWidget,
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showLabel) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text(widget.label, style: titleStyle)),
                  if (widget.rightSlot != null) widget.rightSlot!,
                  if (widget.rightSlot == null && widget.rightLabel != null)
                    Text(widget.rightLabel!, style: titleStyle),
                ],
              ),
              SizedBox(height: gap),
            ],
            shell,
          ],
        ),
        if (_showMessage)
          Positioned(
            top: messageTop,
            left: 0,
            right: 0,
            child: Row(
              children: [
                IgnorePointer(
                  child:
                      widget.messageIcon ??
                      defaultMessageIcon ??
                      const SizedBox(),
                ),
                if (widget.messageIcon != null || defaultMessageIcon != null)
                  const IgnorePointer(child: SizedBox(width: AppSpacing.xxs)),
                Expanded(
                  child: _AppTextFieldMessageText(
                    text: widget.messageText!,
                    style:
                        widget.messageStyle ??
                        AppTypography.labelMedium.copyWith(color: messageColor),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AppTextFieldMessageText extends StatelessWidget {
  const _AppTextFieldMessageText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 0) {
          return IgnorePointer(child: child);
        }

        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          ellipsis: '...',
          maxLines: 1,
        )..layout(maxWidth: constraints.maxWidth);

        if (!textPainter.didExceedMaxLines) {
          return IgnorePointer(child: child);
        }

        return AppTooltip(message: text, preferBelow: true, child: child);
      },
    );
  }
}

class _AppTextFieldClearButton extends StatelessWidget {
  const _AppTextFieldClearButton({
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

class _AppTextFieldNoScrollbarBehavior extends ScrollBehavior {
  const _AppTextFieldNoScrollbarBehavior(this.delegate);

  final ScrollBehavior delegate;

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      delegate.getPlatform(context);

  @override
  Set<PointerDeviceKind> get dragDevices => delegate.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      delegate.pointerAxisModifiers;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      delegate.getMultitouchDragStrategy(context);

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      delegate.velocityTrackerBuilder(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      delegate.getScrollPhysics(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => delegate.getKeyboardDismissBehavior(context);

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => delegate.buildOverscrollIndicator(context, child, details);

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollBehavior copyWith({
    bool? scrollbars,
    bool? overscroll,
    Set<PointerDeviceKind>? dragDevices,
    MultitouchDragStrategy? multitouchDragStrategy,
    Set<LogicalKeyboardKey>? pointerAxisModifiers,
    ScrollPhysics? physics,
    TargetPlatform? platform,
    ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior,
  }) {
    return _AppTextFieldNoScrollbarBehavior(
      delegate.copyWith(
        scrollbars: false,
        overscroll: overscroll,
        dragDevices: dragDevices,
        multitouchDragStrategy: multitouchDragStrategy,
        pointerAxisModifiers: pointerAxisModifiers,
        physics: physics,
        platform: platform,
        keyboardDismissBehavior: keyboardDismissBehavior,
      ),
    );
  }

  @override
  bool shouldNotify(covariant _AppTextFieldNoScrollbarBehavior oldDelegate) =>
      delegate.shouldNotify(oldDelegate.delegate);
}

class _AppTextFieldScrollbar extends StatefulWidget {
  const _AppTextFieldScrollbar({
    super.key,
    required this.controller,
    required this.thumbColor,
  });

  final ScrollController controller;
  final Color thumbColor;

  @override
  State<_AppTextFieldScrollbar> createState() => _AppTextFieldScrollbarState();
}

class _AppTextFieldScrollbarState extends State<_AppTextFieldScrollbar> {
  static const _horizontalInset = 3.0;
  static const _topInset = 8.0;
  static const _bottomInset = 8.0;
  static const _minThumbHeight = 24.0;
  static const _maxThumbHeight = 62.0;
  static const _thumbWidth = 6.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _AppTextFieldScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleScrollChanged);
      widget.controller.addListener(_handleScrollChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScrollChanged);
    super.dispose();
  }

  void _handleScrollChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!widget.controller.hasClients) return const SizedBox.shrink();
        final position = widget.controller.position;
        if (!position.hasContentDimensions) return const SizedBox.shrink();
        final maxScrollExtent = position.maxScrollExtent;
        if (maxScrollExtent <= 0) return const SizedBox.shrink();

        final height = constraints.maxHeight;
        final viewportExtent = position.viewportDimension;
        final contentExtent = viewportExtent + maxScrollExtent;
        if (height <= 0 || viewportExtent <= 0 || contentExtent <= 0) {
          return const SizedBox.shrink();
        }

        final rawThumbHeight = height * viewportExtent / contentExtent;
        final trackHeight = height - _topInset - _bottomInset;
        final maxThumbHeight = trackHeight < _maxThumbHeight
            ? trackHeight
            : _maxThumbHeight;
        if (maxThumbHeight <= 0) return const SizedBox.shrink();
        final thumbHeight = rawThumbHeight
            .clamp(_minThumbHeight, maxThumbHeight)
            .toDouble();
        final scrollableTrackHeight =
            height - _topInset - _bottomInset - thumbHeight;
        final scrollFraction = (position.pixels / maxScrollExtent)
            .clamp(0.0, 1.0)
            .toDouble();
        final top = _topInset + scrollFraction * scrollableTrackHeight;

        return Stack(
          children: [
            Positioned(
              key: const ValueKey('app-text-field-multiline-scrollbar-thumb'),
              left: _horizontalInset,
              top: top,
              width: _thumbWidth,
              height: thumbHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.thumbColor,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
