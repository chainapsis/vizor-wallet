import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoColors;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    extends State<MobileNumericKeyboardToolbar>
    with WidgetsBindingObserver {
  static const _buttonSize = 48.0;
  bool _updateScheduled = false;
  static const _channel = MethodChannel('com.zcash.wallet/numeric_keyboard');
  bool? _nativeVisible;
  bool? _nativeDark;
  bool get _usesNative => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor == AppFormFactor.mobile) {
      WidgetsBinding.instance.addObserver(this);
      FocusManager.instance.addListener(_focusChanged);
      if (_usesNative) {
        _channel.setMethodCallHandler((call) async {
          if (call.method == 'dismiss') {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _nativeVisible = null;
      _focusChanged();
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
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    if (kAppFormFactor == AppFormFactor.mobile && _usesNative) {
      _channel.invokeMethod<void>('update', {'visible': false, 'dark': false});
      _channel.setMethodCallHandler(null);
    }
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
    if (_usesNative) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      if (_nativeVisible != visible || _nativeDark != dark) {
        _nativeVisible = visible;
        _nativeDark = dark;
        _channel.invokeMethod<void>('update', {
          'visible': visible,
          'dark': dark,
        });
      }
      return widget.child;
    }
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
