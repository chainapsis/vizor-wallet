import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const _channel = EventChannel('com.zcash.wallet/screenshots');

/// Emits whenever the OS reports a user screenshot (iOS only — Android
/// uses FLAG_SECURE and never emits here). iOS now also blanks the window
/// via the secure-field privacy shield (see `SecureScreenshotShield`), but
/// keeps this stream as a secondary UX: the OS only reports the capture
/// after it happens, so the warning sheet explains why the shot is blank.
/// Errors from a missing host handler (tests, other platforms) are
/// swallowed so listeners only ever see real events.
Stream<void> screenshotEvents() {
  if (kIsWeb || !Platform.isIOS) return const Stream.empty();
  return _channel
      .receiveBroadcastStream()
      .map((_) {})
      .handleError((Object _) {});
}
