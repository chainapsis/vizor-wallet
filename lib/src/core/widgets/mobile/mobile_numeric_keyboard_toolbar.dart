import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoColors;
import 'package:flutter/material.dart';

import '../../layout/app_form_factor.dart';
import '../../theme/app_theme.dart';
import '../app_icon.dart';

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
  static const _buttonSize = 48.0;
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
        widget.child,
        if (visible)
          Positioned(
            right: media.padding.right + AppSpacing.sm,
            bottom: media.viewInsets.bottom + AppSpacing.sm,
            width: _buttonSize,
            height: _buttonSize,
            child: TextFieldTapRegion(
              child: Semantics(
                label: 'Done',
                button: true,
                child: DecoratedBox(
                  key: const ValueKey('mobile_numeric_keyboard_toolbar'),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Material(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xBB303033)
                            : const Color(0xCCFFFFFF),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => focus?.unfocus(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Center(
                              child: ExcludeSemantics(
                                child: AppIcon(
                                  AppIcons.check,
                                  size: 28,
                                  color: CupertinoColors.activeBlue.resolveFrom(
                                    context,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
