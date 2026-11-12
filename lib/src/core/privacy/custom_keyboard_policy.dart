import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks iOS to use only the system keyboard while a seed-entry screen is
/// showing, so an installed keyboard extension does not receive the words.
///
/// Callers hold before the field can take focus and release once the screen
/// is covered or disposed. Other platforms have no app-level equivalent and
/// ignore the request.
abstract final class CustomKeyboardPolicy {
  static const _channel = MethodChannel('com.zcash.wallet/keyboard_policy');

  static int _holds = 0;

  static void hold() {
    if (++_holds == 1) _send(rejected: true);
  }

  static void release() {
    if (_holds == 0) return;
    if (--_holds == 0) _send(rejected: false);
  }

  @visibleForTesting
  static void resetForTesting() => _holds = 0;

  static void _send({required bool rejected}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    unawaited(
      _channel
          .invokeMethod<void>('setCustomKeyboardsRejected', {
            'rejected': rejected,
          })
          .catchError((Object error) {
            debugPrint('Keyboard policy request failed: ${error.runtimeType}');
          }),
    );
  }
}
