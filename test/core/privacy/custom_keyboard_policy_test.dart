import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/custom_keyboard_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zcash.wallet/keyboard_policy');
  final calls = <Object?>[];

  setUp(() {
    calls.clear();
    CustomKeyboardPolicy.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add((call.arguments as Map)['rejected']);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('iOS sends once per transition, however many screens hold', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    CustomKeyboardPolicy.hold();
    CustomKeyboardPolicy.hold();
    expect(calls, [true]);

    CustomKeyboardPolicy.release();
    expect(calls, [true]);
    CustomKeyboardPolicy.release();
    expect(calls, [true, false]);

    // An unmatched release neither underflows nor re-sends.
    CustomKeyboardPolicy.release();
    CustomKeyboardPolicy.hold();
    expect(calls, [true, false, true]);
  });

  // No other embedder registers the channel; a send there would only fail.
  for (final platform in TargetPlatform.values) {
    if (platform == TargetPlatform.iOS) continue;
    test('$platform never calls the native channel', () {
      debugDefaultTargetPlatformOverride = platform;
      CustomKeyboardPolicy.hold();
      CustomKeyboardPolicy.release();
      expect(calls, isEmpty);
    });
  }
}
