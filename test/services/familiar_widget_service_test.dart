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

  test('update sends normalized familiar snapshot to native channel', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return true;
    });

    await buildService().update(
      profilePictureId: 'wizard',
      accountName: '  Orchard  ',
    );

    expect(sent!.method, 'updateFamiliar');
    expect(sent!.arguments, {
      'profilePictureId': 'pfp-11',
      'accountName': 'Orchard',
    });
  });

  test('update falls back to Vizor for blank account names', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return true;
    });

    await buildService().update(profilePictureId: 'unknown', accountName: '  ');

    expect(sent!.arguments, {
      'profilePictureId': 'pfp-01',
      'accountName': 'Vizor',
    });
  });

  test(
    'update skips native channel when familiar widgets are unsupported',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      await buildService(
        supported: false,
      ).update(profilePictureId: 'pfp-02', accountName: 'Account 1');

      expect(calls, isEmpty);
    },
  );
}
