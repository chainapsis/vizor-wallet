import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/familiar_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/familiar_widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  FamiliarWidgetService buildService({bool supported = true}) {
    return FamiliarWidgetService(
      channel: channel,
      supportsFamiliarWidget: () => supported,
    );
  }

  test('update sends only the normalized profile picture id', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return true;
    });

    await buildService().update(profilePictureId: 'wizard');

    expect(sent!.method, 'updateFamiliar');
    // The account name must never be sent to the unauthenticated widget.
    expect(sent!.arguments, {'profilePictureId': 'pfp-11'});
  });

  test('update normalizes an unknown profile picture id to the default', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return true;
    });

    await buildService().update(profilePictureId: 'unknown');

    expect(sent!.arguments, {'profilePictureId': 'pfp-01'});
  });

  test(
    'update skips native channel when familiar widgets are unsupported',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      await buildService(supported: false).update(profilePictureId: 'pfp-02');

      expect(calls, isEmpty);
    },
  );
}
