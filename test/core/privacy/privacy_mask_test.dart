import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/privacy_mask.dart';

void main() {
  test('privacy mask does not depend on source text length', () {
    expect(
      hideAmountIfPrivacyMode('0.01 ZEC', privacyModeEnabled: true),
      '****** ZEC',
    );
    expect(
      hideAmountIfPrivacyMode(
        '123456789.12345678 ZEC',
        privacyModeEnabled: true,
      ),
      '****** ZEC',
    );
  });

  test('privacy mask keeps caller-selected context suffix', () {
    expect(
      hideAmountIfPrivacyMode(
        '1.23 zec',
        privacyModeEnabled: true,
        denomination: 'zec',
      ),
      '****** zec',
    );
    expect(
      hideIfPrivacyMode('0.0001', privacyModeEnabled: true, suffix: ' ZEC'),
      '****** ZEC',
    );
  });

  test('privacy helper preserves visible text when disabled', () {
    expect(
      hideAmountIfPrivacyMode(
        '123456789.12345678 ZEC',
        privacyModeEnabled: false,
      ),
      '123456789.12345678 ZEC',
    );
  });
}
