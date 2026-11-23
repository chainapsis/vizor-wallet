import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/features/keystone/services/keystone_qr_encoder.dart';

import '../../support/keystone_qr_fixtures.dart';

void main() {
  for (final fixture in keystoneQrDensityFixtures) {
    test(
      '${fixture.fragmentLength}-byte UR uses a less dense QR at level M',
      () {
        final image = encodeKeystoneQrImage(fixture.part);
        final legacy = QrImage(
          QrCode.fromData(
            data: fixture.part,
            errorCorrectLevel: QrErrorCorrectLevel.M,
          ),
        );

        expect(image.errorCorrectLevel, QrErrorCorrectLevel.M);
        expect(legacy.moduleCount, fixture.byteModuleCount);
        expect(image.moduleCount, fixture.alphanumericModuleCount);
        expect(image.moduleCount, lessThan(legacy.moduleCount));
      },
    );
  }

  // Level-M alphanumeric capacities at version/count-field boundaries.
  // https://www.qrcode.com/en/about/version.html
  for (final boundary in [
    (capacity: 20, version: 1),
    (capacity: 262, version: 9),
    (capacity: 1542, version: 26),
  ]) {
    test('selects the minimum version across version ${boundary.version}', () {
      expect(
        encodeKeystoneQrImage('A' * boundary.capacity).typeNumber,
        boundary.version,
      );
      expect(
        encodeKeystoneQrImage('A' * (boundary.capacity + 1)).typeNumber,
        boundary.version + 1,
      );
    });
  }

  test('supports the full QR alphanumeric alphabet', () {
    const alphabet = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
    final image = encodeKeystoneQrImage(alphabet);
    expect(image.typeNumber, 3);
  });

  test('supports version 40 and reports capacity overflow', () {
    expect(encodeKeystoneQrImage('A' * 3391).typeNumber, 40);
    expect(
      () => encodeKeystoneQrImage('A' * 3392),
      throwsA(isA<InputTooLongException>()),
    );
  });

  for (final data in [
    '',
    'ur:zcash-pczt/test',
    'UR:TEST/A\n',
    'UR:TEST/A?B',
    '한글',
  ]) {
    test('preserves byte encoding for ${data.codeUnits}', () {
      final expected = QrImage(
        QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
      final image = encodeKeystoneQrImage(data);
      expect(image.moduleCount, expected.moduleCount);
      expect(image.errorCorrectLevel, QrErrorCorrectLevel.M);
      for (var y = 0; y < image.moduleCount; y++) {
        for (var x = 0; x < image.moduleCount; x++) {
          expect(image.isDark(y, x), expected.isDark(y, x));
        }
      }
    });
  }
}
