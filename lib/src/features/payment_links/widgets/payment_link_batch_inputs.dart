import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../models/vizor_payment_link.dart';
import '../services/payment_link_batch_limits.dart';
import 'payment_link_wizard_chrome.dart';

/// The count field between hold-to-repeat decrement and increment buttons,
/// drawn on the same shell as [AppTextField].
class PaymentLinkBatchCountStepper extends StatefulWidget {
  const PaymentLinkBatchCountStepper({
    super.key,
    required this.count,
    required this.maxCount,
    required this.onChanged,
  });

  final int count;
  final int maxCount;
  final ValueChanged<int> onChanged;

  @override
  State<PaymentLinkBatchCountStepper> createState() =>
      _PaymentLinkBatchCountStepperState();
}

class _PaymentLinkBatchCountStepperState
    extends State<PaymentLinkBatchCountStepper> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.count}',
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChanged);

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _step(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _step(-1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void didUpdateWidget(covariant PaymentLinkBatchCountStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count ||
        oldWidget.maxCount != widget.maxCount) {
      _controller.text = '${widget.count}';
    }
  }

  void _step(int delta) => widget.onChanged(
    (widget.count + delta).clamp(kPaymentLinkBatchMinCount, widget.maxCount),
  );

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
    setState(() {});
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text);
    final next = (parsed ?? widget.count).clamp(
      kPaymentLinkBatchMinCount,
      widget.maxCount,
    );
    _controller.text = '$next';
    if (next != widget.count) widget.onChanged(next);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _InputShell(
      focused: _focusNode.hasFocus,
      constraints: const BoxConstraints.tightFor(height: AppInputSizing.height),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RepeatStepButton(
            buttonKey: const ValueKey('payment_link_bulk_decrease'),
            icon: AppIcons.minus,
            semanticLabel: 'Remove a card',
            onStep: widget.count > kPaymentLinkBatchMinCount
                ? () => _step(-1)
                : null,
          ),
          SizedBox(
            width: 52,
            child: Semantics(
              label: 'Number of cards, 2 to ${widget.maxCount}',
              child: TextField(
                key: const ValueKey('payment_link_bulk_count'),
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onSubmitted: (_) => _focusNode.unfocus(),
                cursorColor: colors.text.accent,
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration.collapsed(hintText: null),
              ),
            ),
          ),
          _RepeatStepButton(
            buttonKey: const ValueKey('payment_link_bulk_increase'),
            icon: AppIcons.plus,
            semanticLabel: 'Add a card',
            onStep: widget.count < widget.maxCount ? () => _step(1) : null,
          ),
        ],
      ),
    );
  }
}

/// A ghost icon action that repeats while held.
class _RepeatStepButton extends StatefulWidget {
  const _RepeatStepButton({
    required this.buttonKey,
    required this.icon,
    required this.semanticLabel,
    required this.onStep,
  });

  final Key buttonKey;
  final String icon;
  final String semanticLabel;
  final VoidCallback? onStep;

  @override
  State<_RepeatStepButton> createState() => _RepeatStepButtonState();
}

class _RepeatStepButtonState extends State<_RepeatStepButton> {
  static const _size = 36.0;

  Timer? _holdTimer;
  Timer? _repeatTimer;
  bool _repeated = false;
  int _repeatCount = 0;

  void _startHold(PointerDownEvent event) {
    if (widget.onStep == null ||
        event.kind == PointerDeviceKind.mouse && event.buttons != 1) {
      return;
    }
    _cancelTimers();
    _repeated = false;
    _repeatCount = 0;
    _holdTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || widget.onStep == null) return;
      _repeated = true;
      _repeatOnce();
      _scheduleRepeat();
    });
  }

  void _repeatOnce() {
    if (!mounted || widget.onStep == null) {
      _cancelTimers();
      return;
    }
    widget.onStep!();
    _repeatCount++;
  }

  void _scheduleRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = Timer(
      Duration(milliseconds: _repeatCount < 12 ? 100 : 60),
      () {
        _repeatOnce();
        if (_repeatTimer != null) _scheduleRepeat();
      },
    );
  }

  void _cancelTimers() {
    _holdTimer?.cancel();
    _repeatTimer?.cancel();
    _holdTimer = null;
    _repeatTimer = null;
  }

  void _onPressed() {
    if (_repeated) {
      _repeated = false;
      return;
    }
    widget.onStep?.call();
  }

  @override
  void didUpdateWidget(covariant _RepeatStepButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onStep == null) _cancelTimers();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _startHold,
    onPointerUp: (_) => _cancelTimers(),
    onPointerCancel: (_) => _cancelTimers(),
    onPointerMove: (event) {
      if (event.localPosition.dx < 0 ||
          event.localPosition.dx > _size ||
          event.localPosition.dy < 0 ||
          event.localPosition.dy > _size) {
        _cancelTimers();
      }
    },
    child: PaymentLinkIconAction(
      key: widget.buttonKey,
      icon: widget.icon,
      semanticLabel: widget.semanticLabel,
      size: _size,
      onPressed: widget.onStep == null ? null : _onPressed,
    ),
  );
}

/// The shared message: one line until it needs a second, never more than
/// two. The counter appears once the field is in use.
class PaymentLinkBatchMessageField extends StatefulWidget {
  const PaymentLinkBatchMessageField({
    super.key,
    required this.controller,
    required this.labelStyle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final TextStyle labelStyle;
  final ValueChanged<String> onChanged;

  @override
  State<PaymentLinkBatchMessageField> createState() =>
      _PaymentLinkBatchMessageFieldState();
}

class _PaymentLinkBatchMessageFieldState
    extends State<PaymentLinkBatchMessageField> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Group message');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final focused = _focusNode.hasFocus;
    final length = widget.controller.text.characters.length;
    final inUse = focused || length > 0;
    // AppTextField's multi-line mode is a 148px text area, so this draws the
    // same shell around a field that grows from one line to two.
    final max = PaymentLinkPresentation.maxMessageCharacters;
    return Semantics(
      label: 'Message (optional), appears on every card',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Titled like the amount field; screen readers get the name above.
          ExcludeSemantics(
            child: Text('Message (optional)', style: widget.labelStyle),
          ),
          const SizedBox(height: AppSpacing.xxs),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focusNode.requestFocus,
            child: _InputShell(
              key: const ValueKey('payment_link_bulk_message'),
              focused: focused,
              cursor: SystemMouseCursors.text,
              constraints: const BoxConstraints(
                minHeight: AppInputSizing.height,
              ),
              padding: const EdgeInsets.all(AppSpacing.s),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.scroll,
                    size: 20,
                    color: inUse ? colors.icon.accent : colors.icon.regular,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 2,
                      keyboardType: TextInputType.multiline,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                      cursorColor: colors.text.accent,
                      decoration: InputDecoration.collapsed(
                        hintText: 'Add a message',
                        hintStyle: AppTypography.labelLarge.copyWith(
                          color: colors.text.muted,
                        ),
                      ),
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          PaymentLinkPresentation.maxMessageCharacters,
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {});
                        widget.onChanged(value);
                      },
                    ),
                  ),
                  if (inUse) ...[
                    const SizedBox(width: AppSpacing.xs),
                    // Characters left, counting down from the limit.
                    Text(
                      '${max - length}/$max',
                      style: widget.labelStyle.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The [AppTextField] surface for a field it cannot host: the input fill,
/// with a border on hover and on focus.
class _InputShell extends StatefulWidget {
  const _InputShell({
    super.key,
    required this.focused,
    required this.constraints,
    required this.padding,
    required this.child,
    this.cursor = MouseCursor.defer,
  });

  final bool focused;
  final BoxConstraints constraints;
  final EdgeInsetsGeometry padding;
  final MouseCursor cursor;
  final Widget child;

  @override
  State<_InputShell> createState() => _InputShellState();
}

class _InputShellState extends State<_InputShell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        constraints: widget.constraints,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: colors.surface.input.primary,
          borderRadius: BorderRadius.circular(AppInputSizing.radius),
          border: Border.all(
            color: widget.focused
                ? colors.background.inverse
                : _hovered
                ? colors.border.subtleOpacity
                : Colors.transparent,
          ),
          boxShadow: appSurfaceShadow(colors),
        ),
        child: widget.child,
      ),
    );
  }
}
