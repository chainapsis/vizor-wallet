import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kIncomingUriChannelName);
  late List<String> nativeCalls;

  setUp(() {
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          return switch (call.method) {
            'takePendingUris' => <String>['vizor://payment-link?p=cold'],
            'ready' => null,
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('drains cold-start URIs before announcing readiness', () async {
    final service = IncomingUriService(channel: channel);
    final received = <String>[];
    final subscription = service.uriStream.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.dispose();
    });

    await service.initialize();

    expect(nativeCalls, ['takePendingUris', 'ready']);
    expect(received, ['vizor://payment-link?p=cold']);
  });

  test('forwards warm URIs after initialization', () async {
    final service = IncomingUriService(channel: channel);
    final received = <String>[];
    final subscription = service.uriStream.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.dispose();
    });
    await service.initialize();

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kIncomingUriChannelName,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onUris', <String>['vizor://payment-link?p=warm']),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);

    expect(received.last, 'vizor://payment-link?p=warm');
  });
}
