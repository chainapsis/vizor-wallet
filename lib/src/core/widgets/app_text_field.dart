import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

enum AppTextFieldTone { neutral, destructive, brandPurple }

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
    this.leading,
    this.trailing,
    this.messageText,
    this.messageIcon,
    this.messageStyle,
    this.tone = AppTextFieldTone.neutral,
    this.showClearButton = false,
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
  final Widget? leading;
  final Widget? trailing;
  final String? messageText;
  final Widget? messageIcon;
  final TextStyle? messageStyle;
  final AppTextFieldTone tone;
  final bool showClearButton;
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

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
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
    final iconColor = _hasText || _isFocused
        ? colors.icon.accent
        : colors.icon.regular;
    final gap = _multiline ? AppSpacing.xs : AppSpacing.xxs;
    final shellHeight = _multiline ? 148.0 : 46.0;
    const shellRadius = 12.0;
    const focusRingWidth = 3.0;
    const focusRingStrokeWidth = 2.0;
    final titleHeight = 16.0;
    final messageTop = titleHeight + gap + shellHeight + gap;
    final textStrutStyle = StrutStyle.fromTextStyle(
      valueStyle,
      forceStrutHeight: true,
    );

    final isNeutralTone = widget.tone == AppTextFieldTone.neutral;
    final borderColor = switch (widget.tone) {
      AppTextFieldTone.neutral when _isFocused => colors.border.strong,
      AppTextFieldTone.neutral => colors.border.subtle,
      AppTextFieldTone.destructive => colors.border.utilityDestructive,
      AppTextFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final focusRingColor = switch (widget.tone) {
      AppTextFieldTone.neutral => colors.state.focusRing,
      AppTextFieldTone.destructive => colors.border.utilityDestructive,
      AppTextFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final messageColor = switch (widget.tone) {
      AppTextFieldTone.neutral => colors.text.secondary,
      AppTextFieldTone.destructive => colors.text.warning,
      AppTextFieldTone.brandPurple => colors.text.brandPurple,
    };
    final defaultMessageIcon = switch (widget.tone) {
      AppTextFieldTone.neutral => null,
      AppTextFieldTone.destructive => AppIcon(
        AppIcons.warning,
        size: AppIconSize.medium,
        color: messageColor,
      ),
      AppTextFieldTone.brandPurple => AppIcon(
        AppIcons.shieldKeyhole,
        size: AppIconSize.medium,
        color: messageColor,
      ),
    };
    final trailingWidget =
        widget.showClearButton &&
            _isFocused &&
            _hasText &&
            widget.enabled &&
            !widget.readOnly
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _clear,
            child: AppIcon(AppIcons.cross, size: 20, color: iconColor),
          )
        : widget.trailing;

    final textField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
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
    final fieldInput = _multiline && widget.scrollController != null
        ? ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbColor: WidgetStatePropertyAll(
                colors.background.overlay.withValues(alpha: 0.5),
              ),
              radius: const Radius.circular(AppRadii.full),
              thickness: const WidgetStatePropertyAll(6),
              thumbVisibility: const WidgetStatePropertyAll(true),
              trackVisibility: const WidgetStatePropertyAll(false),
            ),
            child: Scrollbar(
              controller: widget.scrollController,
              child: textField,
            ),
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
              Positioned.fill(
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: iconColor,
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
                                        color: iconColor,
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
                                key: _textFieldRegionKey,
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.s,
                                  AppSpacing.s + 6,
                                  0,
                                  AppSpacing.s,
                                ),
                                child: fieldInput,
                              ),
                            ),
                            if (trailingWidget != null)
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
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (widget.leading != null)
                                SizedBox(
                                  width: AppIconSize.large,
                                  height: AppIconSize.large,
                                  child: widget.leading,
                                ),
                              if (widget.leading != null)
                                const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Padding(
                                  key: _textFieldRegionKey,
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: fieldInput,
                                ),
                              ),
                              if (trailingWidget != null) ...[
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
            shell,
          ],
        ),
        if (_showMessage)
          Positioned(
            top: messageTop,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Row(
                children: [
                  widget.messageIcon ?? defaultMessageIcon ?? const SizedBox(),
                  if (widget.messageIcon != null || defaultMessageIcon != null)
                    const SizedBox(width: AppSpacing.xxs),
                  Text(
                    widget.messageText!,
                    style:
                        widget.messageStyle ??
                        AppTypography.labelMedium.copyWith(color: messageColor),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
