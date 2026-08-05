import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef PaymentLinkActionBuilder =
    Widget Function(BuildContext context, bool hovered, bool focused);

/// Shared desktop interaction shell for payment-link presentation widgets.
///
/// It keeps custom Figma-shaped targets keyboard-operable without changing
/// their layout: pointer clicks, Enter, numpad Enter, and Space all invoke the
/// same callback. Callers own the focused/hovered visuals through [builder].
class PaymentLinkAction extends StatefulWidget {
  const PaymentLinkAction({
    required this.builder,
    required this.onPressed,
    this.semanticLabel,
    this.excludeChildSemantics = true,
    this.selected,
    this.button = true,
    this.role,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final PaymentLinkActionBuilder builder;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool excludeChildSemantics;
  final bool? selected;
  final bool button;
  final SemanticsRole? role;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<PaymentLinkAction> createState() => _PaymentLinkActionState();
}

class _PaymentLinkActionState extends State<PaymentLinkAction> {
  static const _activationShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _activate() => widget.onPressed?.call();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics:
          widget.semanticLabel != null && widget.excludeChildSemantics,
      button: widget.button,
      selected: widget.selected,
      enabled: _enabled,
      label: widget.semanticLabel,
      role: widget.role,
      onTap: _enabled ? _activate : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: _setFocused,
        shortcuts: _activationShortcuts,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: _enabled ? (_) => _setHovered(true) : null,
          onExit: _enabled ? (_) => _setHovered(false) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? _activate : null,
            child: widget.builder(context, _hovered, _focused),
          ),
        ),
      ),
    );
  }
}
