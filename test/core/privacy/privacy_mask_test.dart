import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/privacy/privacy_mask.dart';

void main() {
  test('privacy mask does not depend on source text length', () {
    expect(
      hideAmountIfPrivacyMode(
        '0.01 $kZcashDefaultCurrencyTicker',
        privacyModeEnabled: true,
      ),
      '****** $kZcashDefaultCurrencyTicker',
    );
    expect(
      hideAmountIfPrivacyMode(
        '123456789.12345678 $kZcashDefaultCurrencyTicker',
        privacyModeEnabled: true,
      ),
      '****** $kZcashDefaultCurrencyTicker',
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
        '123456789.12345678 $kZcashDefaultCurrencyTicker',
        privacyModeEnabled: false,
      ),
      '123456789.12345678 $kZcashDefaultCurrencyTicker',
    );
  });
}
