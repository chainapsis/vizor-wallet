import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_qr_export.dart';
import 'package:zcash_wallet/src/features/receive/services/request_qr_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  const origin = Rect.fromLTWH(10, 20, 44, 44);
  late Directory temporaryDirectory;
  late List<MethodCall> calls;
  var outcome = 'com.apple.UIKit.activity.SaveToFiles';

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'vizor-qr-share-test-',
    );
    calls = [];
    outcome = 'com.apple.UIKit.activity.SaveToFiles';
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => temporaryDirectory.path,
    );
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      calls.add(call);
      return outcome;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(shareChannel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
    await temporaryDirectory.delete(recursive: true);
  });

  for (final giftCard in [true, false]) {
    test(
      '${giftCard ? 'Gift Card' : 'ZIP321'} shares only one PNG with no text attachment',
      () async {
        final String expectedName;
        if (giftCard) {
          expect(
            await sharePaymentLinkQr(png: png, sharePositionOrigin: origin),
            isTrue,
          );
          expectedName = 'vizor-gift-card.png';
        } else {
          await defaultRequestShare(
            png: png,
            fileName: kRequestQrShareFileName,
          );
          expectedName = kRequestQrShareFileName;
        }
        expect(calls, hasLength(1));
        expect(calls.single.method, 'share');
        final arguments = calls.single.arguments as Map<Object?, Object?>;
        expect(arguments.containsKey('text'), isFalse);
        expect(arguments.containsKey('uri'), isFalse);
        expect(arguments['mimeTypes'], ['image/png']);
        final paths = arguments['paths'] as List<Object?>;
        expect(paths, hasLength(1));
        final file = File(paths.single! as String);
        expect(file.uri.pathSegments.last, expectedName);
        expect(await file.readAsBytes(), png);
        if (giftCard) {
          expect(arguments['originX'], origin.left);
          expect(arguments['originY'], origin.top);
          expect(arguments['originWidth'], origin.width);
          expect(arguments['originHeight'], origin.height);
        }
      },
    );
  }

  test('dismissing a Gift Card share does not mark it shared', () async {
    outcome = ''; // share_plus reports a dismissed native sheet as empty.
    expect(
      await sharePaymentLinkQr(png: png, sharePositionOrigin: origin),
      isFalse,
    );
  });

  test('native share failure reaches each caller for its error UI', () async {
    messenger.setMockMethodCallHandler(shareChannel, (_) async {
      throw PlatformException(code: 'share_failed');
    });
    await expectLater(
      sharePaymentLinkQr(png: png, sharePositionOrigin: origin),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      defaultRequestShare(png: png, fileName: kRequestQrShareFileName),
      throwsA(isA<PlatformException>()),
    );
  });
}
