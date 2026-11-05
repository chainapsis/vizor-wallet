import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../layout/app_form_factor.dart';

/// Adds a native dismiss action to every focused iOS system keyboard, including
/// fields inside routes and sheets. Custom passcode keypads do not open an
/// EditableText connection and are unaffected.
class MobileKeyboardToolbar extends StatefulWidget {
  const MobileKeyboardToolbar({required this.child, super.key});

  final Widget child;

  @override
  State<MobileKeyboardToolbar> createState() => _MobileKeyboardToolbarState();
}

class _MobileKeyboardToolbarState extends State<MobileKeyboardToolbar>
    with WidgetsBindingObserver {
  bool _updateScheduled = false;
  static const _channel = MethodChannel('com.zcash.wallet/keyboard_toolbar');
  bool? _nativeVisible;
  bool? _nativeDark;
  bool get _usesNative => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (kAppFormFactor == AppFormFactor.mobile && _usesNative) {
      WidgetsBinding.instance.addObserver(this);
      FocusManager.instance.addListener(_focusChanged);
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'dismiss') {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      });
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
    if (kAppFormFactor != AppFormFactor.mobile || !_usesNative) {
      return widget.child;
    }
    final media = MediaQuery.of(context);
    final focus = FocusManager.instance.primaryFocus;
    final editable = focus?.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.widget;
    final hasKeyboard =
        editable != null &&
        !editable.readOnly &&
        editable.keyboardType != TextInputType.none;
    final visible = hasKeyboard && media.viewInsets.bottom > 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_nativeVisible != visible || _nativeDark != dark) {
      _nativeVisible = visible;
      _nativeDark = dark;
      _channel.invokeMethod<void>('update', {'visible': visible, 'dark': dark});
    }
    return widget.child;
  }
}
