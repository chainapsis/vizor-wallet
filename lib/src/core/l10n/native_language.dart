import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_language.dart';

const _channel = MethodChannel('com.zcash.wallet/native_strings');

/// Tells iOS, Android and macOS the app language, so the copy they draw
/// themselves (notifications, background-task captions, system prompts, the
/// macOS update alerts) matches the UI. Native code stores it for background
/// work and uses English until it arrives. Windows and Linux have no native
/// copy.
Future<void> sendNativeAppLanguage(String tag) async {
  if (kIsWeb || !(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
    return;
  }
  try {
    await _channel.invokeMethod<void>('setLanguage', {'tag': tag});
  } catch (error) {
    // Native keeps its last language, English when it never got one.
    log('native strings: could not send the app language: $error');
  }
}

/// Sends the language the app shows to native code at startup and whenever it
/// changes.
///
/// It reads the locale `MaterialApp` resolved rather than the saved
/// preference, so a build that offers English only sends what the user
/// actually sees.
class NativeLanguageSync extends StatefulWidget {
  const NativeLanguageSync({
    super.key,
    required this.child,
    this.send = sendNativeAppLanguage,
  });

  final Widget child;

  @visibleForTesting
  final Future<void> Function(String tag) send;

  @override
  State<NativeLanguageSync> createState() => _NativeLanguageSyncState();
}

class _NativeLanguageSyncState extends State<NativeLanguageSync> {
  String? _sent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    final tag =
        (AppLanguage.fromTag(locale.languageCode) ?? AppLanguage.en).tag;
    if (tag == _sent) return;
    _sent = tag;
    widget.send(tag);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
