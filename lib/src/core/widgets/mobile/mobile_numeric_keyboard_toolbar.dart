import 'package:flutter/material.dart';

import '../../layout/app_form_factor.dart';
import '../../theme/app_theme.dart';

/// Adds a dismiss action to every focused OS numeric keyboard, including
/// fields inside routes and sheets. Custom passcode keypads do not open an
/// EditableText connection and are unaffected.
class MobileNumericKeyboardToolbar extends StatefulWidget {
  const MobileNumericKeyboardToolbar({required this.child, super.key});

  final Widget child;

  @override
  State<MobileNumericKeyboardToolbar> createState() =>
      _MobileNumericKeyboardToolbarState();
}

class _MobileNumericKeyboardToolbarState
    extends State<MobileNumericKeyboardToolbar> {
  static const _height = 44.0;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor == AppFormFactor.mobile) {
      FocusManager.instance.addListener(_focusChanged);
    }
  }

  void _focusChanged() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor != AppFormFactor.mobile) return widget.child;
    final media = MediaQuery.of(context);
    final focus = FocusManager.instance.primaryFocus;
    final editable = focus?.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.widget;
    final numeric =
        editable != null &&
        !editable.readOnly &&
        (editable.keyboardType.index == TextInputType.number.index ||
            editable.keyboardType == TextInputType.phone);
    final visible = numeric && media.viewInsets.bottom > 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaQuery(
          // Reserve toolbar space for the same keyboard avoidance already
          // used by each route or sheet. Keep the router subtree mounted.
          data: visible
              ? media.copyWith(
                  viewInsets: media.viewInsets.copyWith(
                    bottom: media.viewInsets.bottom + _height,
                  ),
                )
              : media,
          child: widget.child,
        ),
        if (visible)
          Positioned(
            left: 0,
            right: 0,
            bottom: media.viewInsets.bottom,
            height: _height,
            child: TextFieldTapRegion(
              child: Material(
                key: const ValueKey('mobile_numeric_keyboard_toolbar'),
                color: context.colors.background.raised,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: context.colors.border.regular),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: media.padding.left + AppSpacing.sm,
                      right: media.padding.right + AppSpacing.sm,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => focus?.unfocus(),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.text.primary,
                          textStyle: AppTypography.labelLarge,
                          minimumSize: const Size(64, _height),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
