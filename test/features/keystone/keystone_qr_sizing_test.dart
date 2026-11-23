import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/keystone/services/keystone_qr_encoder.dart';
import 'package:zcash_wallet/src/features/keystone/services/keystone_qr_sizing.dart';

import '../../support/keystone_qr_fixtures.dart';
import '../../support/voting_qr_frames.dart';

void main() {
  test('preserves the old renderer pattern with the larger border', () {
    final sizing = KeystoneQrSizing.fromParts(votingQrFrames);
    for (final ratio in [1.0, 1.25, 2.0, 3.0]) {
      for (final previousSize in [120.0, 214.0, 320.0]) {
        final surface = sizing.sizePreservingPattern(previousSize, ratio);
        final pitch = (surface * ratio / (votingQrModuleCount + 8) + 1e-9)
            .floor();
        final oldPattern = previousSize * (1 - 6 / votingQrModuleCount);
        expect(
          pitch * votingQrModuleCount / ratio,
          greaterThanOrEqualTo(oldPattern),
        );
      }
    }
  });
  test(
    'current transport fixtures use the independently checked QR version',
    () {
      for (final part in votingQrFrames) {
        expect(encodeKeystoneQrImage(part).moduleCount, votingQrModuleCount);
      }
    },
  );

  test(
    'reserves a four-module border without rounding the data pattern down',
    () {
      final parts = [
        ...votingQrFrames,
        for (final fixture in keystoneQrDensityFixtures) fixture.part,
        '한글' * 60,
        'lowercase byte data' * 25,
      ];
      final sizing = KeystoneQrSizing.fromParts(parts);
      for (final ratio in [1.0, 1.25, 1.5, 1.75, 2.0, 3.0]) {
        for (final target in [360.0, 426.0]) {
          final size = sizing.sizeForPattern(target, ratio);
          for (final part in parts) {
            final count = encodeKeystoneQrImage(part).moduleCount;
            final pitch = (size * ratio / (count + 8) + 1e-9).floor();
            expect(count * pitch / ratio, greaterThanOrEqualTo(target));
          }
        }
        final minimum = sizing.minimumSize(ratio, pixelsPerModule: 3);
        final largest = parts
            .map((part) => encodeKeystoneQrImage(part).moduleCount)
            .reduce(math.max);
        expect(minimum, (largest + 8) * 3 / ratio);
      }
    },
  );
}
