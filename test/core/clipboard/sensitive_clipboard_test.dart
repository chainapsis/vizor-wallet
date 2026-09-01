import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/clipboard/sensitive_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeChannel = MethodChannel('com.zcash.wallet/sensitive_clipboard');

  tearDown(() {
    SensitiveClipboard.debugIsIosOverride = null;
    SensitiveClipboard.debugExpirationDelay = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'iOS copy sends text with the default expiration to native channel',
    () async {
      final calls = <MethodCall>[];
      SensitiveClipboard.debugIsIosOverride = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
            calls.add(call);
            return null;
          });

      await SensitiveClipboard.copyText('alpha bravo');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'copyText');
      expect(calls.single.arguments, {
        'text': 'alpha bravo',
        'expirationSeconds': 60,
      });
    },
  );

  test(
    'non-iOS copy clears the unchanged clipboard after expiration',
    () async {
      final expiration = Completer<void>();
      String? clipboardText;
      SensitiveClipboard.debugIsIosOverride = false;
      SensitiveClipboard.debugExpirationDelay = (_) => expiration.future;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardText = (call.arguments as Map)['text'] as String;
            } else if (call.method == 'Clipboard.getData') {
              return {'text': clipboardText};
            }
            return null;
          });

      await SensitiveClipboard.copyText('charlie delta');
      expect(clipboardText, 'charlie delta');

      expiration.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(clipboardText, isEmpty);
    },
  );

  test('non-iOS expiry preserves newer clipboard content', () async {
    final expiration = Completer<void>();
    String? clipboardText;
    SensitiveClipboard.debugIsIosOverride = false;
    SensitiveClipboard.debugExpirationDelay = (_) => expiration.future;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });

    await SensitiveClipboard.copyText('gift card secret');
    clipboardText = 'newer user copy';
    expiration.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(clipboardText, 'newer user copy');
  });

  test('a repeated copy supersedes the earlier expiry', () async {
    final expirations = <Completer<void>>[];
    String? clipboardText;
    SensitiveClipboard.debugIsIosOverride = false;
    SensitiveClipboard.debugExpirationDelay = (_) {
      final completer = Completer<void>();
      expirations.add(completer);
      return completer.future;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });

    await SensitiveClipboard.copyText('same gift card secret');
    await SensitiveClipboard.copyText('same gift card secret');

    expirations.first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(clipboardText, 'same gift card secret');

    expirations.last.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(clipboardText, isEmpty);
  });

  test('an expired copy retries after background clipboard denial', () async {
    final expiration = Completer<void>();
    String? clipboardText;
    var denyRead = true;
    SensitiveClipboard.debugIsIosOverride = false;
    SensitiveClipboard.debugExpirationDelay = (_) => expiration.future;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            if (denyRead) throw StateError('clipboard unavailable');
            return {'text': clipboardText};
          }
          return null;
        });

    await SensitiveClipboard.copyText('gift card secret');
    expiration.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(clipboardText, 'gift card secret');

    denyRead = false;
    await SensitiveClipboard.debugRetryExpiredFallbackClear();

    expect(clipboardText, isEmpty);
  });
}
