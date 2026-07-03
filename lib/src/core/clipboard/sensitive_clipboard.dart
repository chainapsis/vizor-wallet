import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const sensitiveClipboardDefaultExpiration = Duration(minutes: 1);

abstract final class SensitiveClipboard {
  static const _channel = MethodChannel('com.zcash.wallet/sensitive_clipboard');

  @visibleForTesting
  static bool? debugIsIosOverride;

  static Future<void> copyText(
    String text, {
    Duration expiration = sensitiveClipboardDefaultExpiration,
  }) async {
    if (_supportsNativeExpiration) {
      await _channel.invokeMethod<void>('copyText', {
        'text': text,
        'expirationSeconds': expiration.inSeconds,
      });
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
  }

  static bool get _supportsNativeExpiration {
    final override = debugIsIosOverride;
    if (override != null) return override;
    return !kIsWeb && Platform.isIOS;
  }
}
