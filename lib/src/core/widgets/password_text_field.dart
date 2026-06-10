import 'package:flutter/widgets.dart';

import 'app_icon.dart';
import 'app_text_field.dart';

class PasswordTextField extends StatefulWidget {
  const PasswordTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.messageText,
    this.messageIcon,
    this.messageStyle,
    this.labelStyle,
    this.hintText,
    this.showLabel = true,
    this.leadingSlotWidth,
    this.trailingSlotWidth,
    this.inputHorizontalPadding,
    this.inputBottomPadding,
    this.tone = AppTextFieldTone.neutral,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.showVisibilityToggle = true,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? messageText;
  final Widget? messageIcon;
  final TextStyle? messageStyle;
  final TextStyle? labelStyle;
  final String? hintText;
  final bool showLabel;
  final double? leadingSlotWidth;
  final double? trailingSlotWidth;
  final double? inputHorizontalPadding;
  final double? inputBottomPadding;
  final AppTextFieldTone tone;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final bool showVisibilityToggle;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _obscureText = true;

  void _toggleVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      controller: widget.controller,
      focusNode: widget.focusNode,
      messageText: widget.messageText,
      messageIcon: widget.messageIcon,
      messageStyle: widget.messageStyle,
      labelStyle: widget.labelStyle,
      hintText: widget.hintText,
      showLabel: widget.showLabel,
      leadingSlotWidth: widget.leadingSlotWidth,
      trailingSlotWidth: widget.trailingSlotWidth,
      inputHorizontalPadding: widget.inputHorizontalPadding,
      inputBottomPadding: widget.inputBottomPadding,
      tone: widget.tone,
      leading: const AppIcon(AppIcons.lock, size: 20),
      trailing: widget.showVisibilityToggle
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleVisibility,
              child: AppIcon(
                _obscureText ? AppIcons.eyeClosed : AppIcons.eye,
                size: 20,
              ),
            )
          : null,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      keyboardType: TextInputType.visiblePassword,
      obscureText: _obscureText,
      enableSuggestions: false,
      autocorrect: false,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
    );
  }
}
