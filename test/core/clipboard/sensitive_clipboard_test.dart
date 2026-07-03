import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/clipboard/sensitive_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeChannel = MethodChannel('com.zcash.wallet/sensitive_clipboard');

  tearDown(() {
    SensitiveClipboard.debugIsIosOverride = null;
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

  test('non-iOS copy falls back to the Flutter clipboard', () async {
    final copied = <String>[];
    SensitiveClipboard.debugIsIosOverride = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });

    await SensitiveClipboard.copyText('charlie delta');

    expect(copied, ['charlie delta']);
  });
}
