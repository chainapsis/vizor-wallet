import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart'
    show TextInputAction, TextInputFormatter, TextInputType;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The shared single-line mobile text field (Figma `_Modal Type` field
/// 4755:84371 / 4755:85337): a flat `surface.input` box sized by
/// [AppInputSizing] (60px tall, radius 16 on mobile), label-m Medium text, NO
/// visible border by default and a bright `background.inverse` outline only
/// while focused, over the layered surface shadow — the same shell the
/// canonical desktop [AppTextField] draws.
///
/// Optional [leading] / [trailing] slots host inline affordances (a search
/// glyph, a clear button, contacts/scan icons), laid out inside the box around
/// the text. This is the general mobile input: the swap modals use it, and it
/// is reusable anywhere on mobile that needs the compact field.
class MobileTextField extends StatefulWidget {
  const MobileTextField({
    required this.controller,
    required this.focusNode,
    this.fieldKey,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.restingBorderColor,
    this.focusedBorderColor,
    this.textStyle,
    this.hintStyle,
    this.height,
    this.radius,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Key applied to the inner [TextField] — tests target the field by key.
  final Key? fieldKey;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// Rendered before the text (e.g. a search glyph). Owns its own sizing.
  final Widget? leading;

  /// Rendered after the text (e.g. a clear button or contacts/scan icons).
  /// Owns its own padding/sizing.
  final Widget? trailing;

  /// Optional per-surface fill override for one-off Figma variants.
  final Color? backgroundColor;

  /// Optional border shown when the field is not focused. Defaults to
  /// transparent for the canonical mobile input.
  final Color? restingBorderColor;

  /// Optional border shown when focused. Defaults to the inverse focus ring.
  final Color? focusedBorderColor;

  /// Optional text style override. Color is not injected automatically.
  final TextStyle? textStyle;

  /// Optional placeholder style override.
  final TextStyle? hintStyle;

  /// Optional height override for one-off embedded field variants.
  final double? height;

  /// Optional radius override for one-off embedded field variants.
  final double? radius;

  @override
  State<MobileTextField> createState() => _MobileTextFieldState();
}

class _MobileTextFieldState extends State<MobileTextField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant MobileTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  // Repaint the border when focus toggles.
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final focused = widget.focusNode.hasFocus;
    final textStyle =
        widget.textStyle ??
        AppTypography.labelMedium.copyWith(
          fontWeight: FontWeight.w500,
          color: colors.text.accent,
        );
    final hintStyle =
        widget.hintStyle ??
        AppTypography.labelMedium.copyWith(color: colors.text.muted);
    return Container(
      // Mobile input metrics (AppInputSizing → 60px tall, radius 16); desktop
      // resolves these to 46 / 12. The surface fill, the focus-only inverse
      // outline and the layered surface shadow mirror the canonical
      // AppTextField shell.
      height: widget.height ?? AppInputSizing.height,
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? colors.surface.input,
        borderRadius: BorderRadius.circular(
          widget.radius ?? AppInputSizing.radius,
        ),
        border: Border.all(
          color: focused
              ? widget.focusedBorderColor ?? colors.background.inverse
              : widget.restingBorderColor ?? const Color(0x00000000),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: Row(
        children: [
          if (widget.leading != null) widget.leading!,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                key: widget.fieldKey,
                controller: widget.controller,
                focusNode: widget.focusNode,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                textInputAction: widget.textInputAction,
                keyboardType: widget.keyboardType,
                inputFormatters: widget.inputFormatters,
                style: textStyle,
                cursorColor: colors.text.accent,
                decoration: InputDecoration.collapsed(
                  hintText: widget.hintText,
                  hintStyle: hintStyle,
                ),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}
