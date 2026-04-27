// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_text_field.dart';

Widget _fieldFrame(
  BuildContext context,
  Widget child, {
  bool reserveMessageSpace = false,
}) {
  return ColoredBox(
    color: context.colors.background.ground,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + (reserveMessageSpace ? 28 : 0),
      ),
      child: child,
    ),
  );
}

Widget buildTextFieldGalleryUseCase(BuildContext context) {
  return _fieldFrame(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TEXT FIELD',
          style: TextStyle(
            color: context.colors.text.secondary,
            fontSize: 11,
            letterSpacing: 0.88,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          runSpacing: AppSpacing.xl,
          spacing: AppSpacing.lg,
          children: [
            SizedBox(
              width: 320,
              child: AppTextField(
                label: 'Send to',
                rightLabel: 'Max: 150 ZEC',
                hintText: 'Placeholder',
                leading: const AppIcon(AppIcons.users, size: 20),
              ),
            ),
            SizedBox(
              width: 320,
              child: AppTextField(
                label: 'Label Only',
                hintText: 'Placeholder',
                leading: const AppIcon(AppIcons.users, size: 20),
              ),
            ),
            SizedBox(
              width: 320,
              child: AppTextField(
                label: 'Send to',
                rightLabel: 'Max: 150 ZEC',
                initialValue: 'Value',
                leading: const AppIcon(AppIcons.users, size: 20),
              ),
            ),
            SizedBox(
              width: 320,
              child: AppTextField(
                label: 'Send to',
                rightLabel: 'Max: 150 ZEC',
                initialValue: 'Value',
                leading: const AppIcon(AppIcons.users, size: 20),
                messageText: 'Shielded Address',
                tone: AppTextFieldTone.brandCrimson,
              ),
            ),
            SizedBox(
              width: 320,
              child: AppTextField(
                label: 'Send to',
                rightLabel: 'Max: 150 ZEC',
                initialValue: 'Value',
                leading: const AppIcon(AppIcons.users, size: 20),
                messageText: 'Insufficient Funds',
                tone: AppTextFieldTone.destructive,
              ),
            ),
            SizedBox(
              width: 320,
              child: AppTextField(
                label: 'Message',
                rightLabel: '512/512',
                hintText: 'Placeholder',
                leading: const AppIcon(AppIcons.users, size: 20),
                minLines: 4,
                maxLines: 4,
              ),
            ),
          ],
        ),
      ],
    ),
    reserveMessageSpace: true,
  );
}

class _InteractiveTextFieldDemo extends StatefulWidget {
  const _InteractiveTextFieldDemo({
    required this.multiline,
    required this.tone,
    required this.showLeading,
    required this.showClearButton,
    required this.messageText,
  });

  final bool multiline;
  final AppTextFieldTone tone;
  final bool showLeading;
  final bool showClearButton;
  final String messageText;

  @override
  State<_InteractiveTextFieldDemo> createState() =>
      _InteractiveTextFieldDemoState();
}

class _InteractiveTextFieldDemoState extends State<_InteractiveTextFieldDemo> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: AppTextField(
        label: widget.multiline ? 'Message' : 'Send to',
        rightLabel: widget.multiline ? '512/512' : 'Max: 150 ZEC',
        controller: _controller,
        focusNode: _focusNode,
        hintText: 'Placeholder',
        leading: widget.showLeading
            ? const AppIcon(AppIcons.users, size: 20)
            : null,
        minLines: widget.multiline ? 4 : 1,
        maxLines: widget.multiline ? 4 : 1,
        tone: widget.tone,
        showClearButton: widget.showClearButton,
        messageText: widget.messageText.isEmpty ? null : widget.messageText,
      ),
    );
  }
}

Widget buildTextFieldInteractiveUseCase(BuildContext context) {
  final multiline = context.knobs.boolean(
    label: 'Text area',
    initialValue: false,
  );
  final showLeading = context.knobs.boolean(
    label: 'Leading icon',
    initialValue: true,
  );
  final showClearButton = context.knobs.boolean(
    label: 'Clear button',
    initialValue: true,
  );
  final tone = context.knobs.object.dropdown<AppTextFieldTone>(
    label: 'Tone',
    options: const [
      AppTextFieldTone.neutral,
      AppTextFieldTone.brandCrimson,
      AppTextFieldTone.destructive,
    ],
    initialOption: AppTextFieldTone.neutral,
    labelBuilder: (value) => value.name,
  );
  final messageText = context.knobs.string(
    label: 'Message text',
    initialValue: '',
  );

  return _fieldFrame(
    context,
    Center(
      child: _InteractiveTextFieldDemo(
        multiline: multiline,
        tone: tone,
        showLeading: showLeading,
        showClearButton: showClearButton,
        messageText: messageText,
      ),
    ),
    reserveMessageSpace: true,
  );
}
