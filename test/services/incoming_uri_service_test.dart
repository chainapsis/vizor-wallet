import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kIncomingUriChannelName);
  late List<String> nativeCalls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          return switch (call.method) {
            'takePendingUris' => <String>[
              'https://example.test/payment-links/open#v1=cold',
            ],
            'ready' => null,
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('leaves desktop URI intake disabled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final service = IncomingUriService(channel: channel);
    addTearDown(service.dispose);

    await service.initialize();

    expect(nativeCalls, isEmpty);
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
    expect(received, ['https://example.test/payment-links/open#v1=cold']);
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
            const MethodCall('onUris', <String>[
              'https://example.test/payment-links/open#v1=warm',
            ]),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);

    expect(received.last, 'https://example.test/payment-links/open#v1=warm');
  });

  test('diagnostics describe the envelope without exposing the secret', () {
    const secret = 'do-not-log-this-bearer-payload';
    final summary = incomingUriDiagnosticSummary(
      'https://link.vizor.cash/payment-links/open#v1=$secret',
    );

    expect(summary, 'origin=trusted route=payment_link query=none fragment=v1');
    expect(summary, isNot(contains(secret)));
    expect(summary, isNot(contains('link.vizor.cash')));
  });
}
