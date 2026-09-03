import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/clipboard/sensitive_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeChannel = MethodChannel('com.zcash.wallet/sensitive_clipboard');

  tearDown(() {
    SensitiveClipboard.debugCancelPendingExpiration();
    SensitiveClipboard.debugSupportsNativeClipboardOverride = null;
    SensitiveClipboard.debugExpirationDelay = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'native copy sends text with the default expiration to its channel',
    () async {
      final calls = <MethodCall>[];
      SensitiveClipboard.debugSupportsNativeClipboardOverride = true;
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
    'fallback copy clears the unchanged clipboard after expiration',
    () async {
      final expiration = Completer<void>();
      String? clipboardText;
      SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
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

  test('fallback expiry preserves newer clipboard content', () async {
    final expiration = Completer<void>();
    String? clipboardText;
    SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
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
    SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
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

  test('a failed second copy leaves the earlier expiry armed', () async {
    final expiration = Completer<void>();
    String? clipboardText;
    var denyWrite = false;
    SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
    SensitiveClipboard.debugExpirationDelay = (_) => expiration.future;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (denyWrite) throw StateError('clipboard write denied');
            clipboardText = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });

    await SensitiveClipboard.copyText('first secret');
    expect(clipboardText, 'first secret');

    denyWrite = true;
    await expectLater(
      SensitiveClipboard.copyText('second secret'),
      throwsA(isA<PlatformException>()),
    );

    // The failed write never reached the clipboard, so the first secret is
    // still sitting on it. Its expiry is the only thing that will ever clear
    // it, so the failed copy must not have retired that expiry.
    expect(clipboardText, 'first secret');

    denyWrite = false;
    expiration.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(clipboardText, isEmpty);
  });

  test('an expired copy retries after background clipboard denial', () async {
    final expiration = Completer<void>();
    String? clipboardText;
    var denyRead = true;
    SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
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

  testWidgets('a cancelled fallback expiry leaves no pending timer', (
    tester,
  ) async {
    String? clipboardText;
    SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });

    // No debugExpirationDelay override: this exercises the real timer that
    // production schedules, which must be cancellable so it cannot outlive the
    // screen that copied.
    await SensitiveClipboard.copyText('gift card secret');
    expect(clipboardText, 'gift card secret');

    SensitiveClipboard.debugCancelPendingExpiration();

    // The widget-tree teardown that follows asserts no timer is still pending.
  });

  testWidgets('a repeated copy cancels the earlier real expiry timer', (
    tester,
  ) async {
    String? clipboardText;
    SensitiveClipboard.debugSupportsNativeClipboardOverride = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });

    await SensitiveClipboard.copyText('first secret');
    await SensitiveClipboard.copyText('second secret');
    SensitiveClipboard.debugCancelPendingExpiration();

    // Only the latest copy may hold a timer; if the first one survived, the
    // widget-tree teardown would report a pending timer here.
  });
}
