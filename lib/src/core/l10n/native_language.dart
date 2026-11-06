import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_language.dart';

const _channel = MethodChannel('com.zcash.wallet/native_strings');

/// Tells iOS and Android the app language, so the copy they draw themselves
/// (notifications, background-task captions, system prompts) matches the UI.
/// Native code stores it for background work and uses English until it
/// arrives. Desktop has no native copy and ignores it.
Future<void> sendNativeAppLanguage(String tag) async {
  if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;
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
/// preference, so "follow the device", a device language change and builds
/// that offer English only all send what the user actually sees.
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
