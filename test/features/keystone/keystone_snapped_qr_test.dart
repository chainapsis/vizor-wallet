import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_snapped_qr.dart';

// The length of one voting frame, which the byte-mode encoder turns into an
// 85-module symbol at error-correction level M.
final _votingFrame = 'UR:ZCASH-SIGN-BATCH/1-155/${'A' * 440}';

QrImage _qr(String data) => QrImage(
  QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
);

void main() {
  group('keystoneQrImage', () {
    test('encodes an upper-case UR in alphanumeric mode', () {
      final byteMode = _qr(_votingFrame);
      final image = keystoneQrImage(
        _votingFrame,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );

      expect(byteMode.moduleCount, 85);
      expect(image.moduleCount, 69);
    });

    test('picks the smallest symbol that holds the text', () {
      // Version 1 at level M holds 20 alphanumeric characters.
      expect(
        keystoneQrImage(
          'A' * 20,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        ).moduleCount,
        21,
      );
      expect(
        keystoneQrImage(
          'A' * 21,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        ).moduleCount,
        25,
      );
    });

    test('encodes text outside the alphanumeric set as bytes', () {
      const lowerCase = 'ur:zcash-pczt/test';

      expect(
        keystoneQrImage(
          lowerCase,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        ).moduleCount,
        _qr(lowerCase).moduleCount,
      );
    });
  });

  group('KeystoneQrPixelGrid.fit', () {
    test('gives each module the largest whole pixel count that fits', () {
      final grid = KeystoneQrPixelGrid.fit(
        boxPixels: 230,
        moduleCount: 85,
        quietZoneModules: 4,
      )!;

      // 93 modules across 230 pixels leaves 2 whole pixels per module.
      expect(grid.modulePixels, 2);
      expect(grid.inset, (230 - 85 * 2) ~/ 2);
    });

    test('always leaves at least the quiet zone around the symbol', () {
      for (var box = 93.0; box < 800; box += 7.5) {
        final grid = KeystoneQrPixelGrid.fit(
          boxPixels: box,
          moduleCount: 85,
          quietZoneModules: 4,
        )!;

        expect(grid.inset, greaterThanOrEqualTo(4 * grid.modulePixels));
        expect(grid.inset * 2 + 85 * grid.modulePixels, lessThanOrEqualTo(box));
      }
    });

    test('treats a box a hair under a whole pixel count as that count', () {
      final grid = KeystoneQrPixelGrid.fit(
        boxPixels: 459.99999999,
        moduleCount: 85,
        quietZoneModules: 4,
      )!;

      expect(grid.modulePixels, 460 ~/ 93);
    });

    test('refuses a box too small for one pixel per module', () {
      expect(
        KeystoneQrPixelGrid.fit(
          boxPixels: 92,
          moduleCount: 85,
          quietZoneModules: 4,
        ),
        isNull,
      );
    });
  });

  for (final devicePixelRatio in [1.0, 2.0]) {
    testWidgets(
      'paints only pure ink and paper at ${devicePixelRatio}x when placed '
      'between pixels',
      (tester) async {
        tester.view.devicePixelRatio = devicePixelRatio;
        tester.view.physicalSize = Size(400, 400) * devicePixelRatio;
        addTearDown(tester.view.reset);
        final qr = _qr(_votingFrame);
        expect(qr.moduleCount, 85);
        final boundary = GlobalKey();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    // A fractional origin, as centring in an odd-sized
                    // window produces.
                    padding: const EdgeInsets.only(left: 10.3, top: 20.7),
                    child: SizedBox.square(
                      dimension: 230,
                      child: KeystoneSnappedQr(
                        qrImage: qr,
                        color: const Color(0xFF000000),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final renderQr = tester.renderObject<RenderKeystoneSnappedQr>(
          find.byType(KeystoneSnappedQr),
        );
        final grid = renderQr.debugLastPixelGrid!;
        expect(grid.modulePixels, (230 * devicePixelRatio).floor() ~/ 93);

        final renderBoundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundary),
        );
        final width = (400 * devicePixelRatio).round();
        final pixels = await tester.runAsync(() async {
          final image = await renderBoundary.toImage(
            pixelRatio: devicePixelRatio,
          );
          expect(image.width, width);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!;
        });
        int redAt(int x, int y) => pixels!.getUint8((y * width + x) * 4);

        // No pixel is anything but ink or paper.
        var dark = 0;
        for (var offset = 0; offset < pixels!.lengthInBytes; offset += 4) {
          final red = pixels.getUint8(offset);
          expect(red == 0 || red == 255, isTrue, reason: 'grey pixel $red');
          if (red == 0) dark++;
        }

        // Every dark module is exactly modulePixels square.
        var darkModules = 0;
        for (var row = 0; row < qr.moduleCount; row++) {
          for (var column = 0; column < qr.moduleCount; column++) {
            if (qr.isDark(row, column)) darkModules++;
          }
        }
        expect(dark, darkModules * grid.modulePixels * grid.modulePixels);

        // The symbol starts on the device pixel nearest the box's corner,
        // inset by the quiet zone: the top-left finder pattern's corner.
        final left = (10.3 * devicePixelRatio).round() + grid.inset;
        final top = (20.7 * devicePixelRatio).round() + grid.inset;
        expect(redAt(left, top), 0);
        expect(redAt(left - 1, top), 255);
        expect(redAt(left, top - 1), 255);
      },
    );
  }

  testWidgets('falls back to an unsnapped symbol under a rotation', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Transform.rotate(
            angle: 0.3,
            child: SizedBox.square(
              dimension: 230,
              child: KeystoneSnappedQr(
                qrImage: _qr(_votingFrame),
                color: const Color(0xFF000000),
              ),
            ),
          ),
        ),
      ),
    );

    final renderQr = tester.renderObject<RenderKeystoneSnappedQr>(
      find.byType(KeystoneSnappedQr),
    );
    expect(renderQr.debugLastPixelGrid, isNull);
    expect(tester.takeException(), isNull);
  });
}
