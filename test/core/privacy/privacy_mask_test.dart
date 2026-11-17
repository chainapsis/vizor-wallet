import 'package:flutter/painting.dart';
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
      '•••••• $kZcashDefaultCurrencyTicker',
    );
    expect(
      hideAmountIfPrivacyMode(
        '123456789.12345678 $kZcashDefaultCurrencyTicker',
        privacyModeEnabled: true,
      ),
      '•••••• $kZcashDefaultCurrencyTicker',
    );
  });

  test('privacy mask keeps caller-selected context suffix', () {
    expect(
      hideAmountIfPrivacyMode(
        '1.23 zec',
        privacyModeEnabled: true,
        denomination: 'zec',
      ),
      '•••••• zec',
    );
    expect(
      hideIfPrivacyMode('0.0001', privacyModeEnabled: true, suffix: ' ZEC'),
      '•••••• ZEC',
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

  test('serif mask span draws all bullets but the last tight', () {
    const style = TextStyle(fontFamily: 'Young Serif', fontSize: 40);
    final span = serifPrivacyMaskSpan('+•••••• ', style);

    expect(span.toPlainText(), '+•••••• ');
    expect(span.style, style);
    final children = span.children!.cast<TextSpan>();
    expect(children.map((child) => child.text), ['+', '•••••', '• ']);
    expect(
      children[1].style?.letterSpacing,
      kSerifPrivacyMaskLetterSpacingEm * 40,
    );
    expect(children[0].style, isNull);
    expect(children[2].style, isNull);
  });

  test('serif mask span leaves text without a mask as one span', () {
    const style = TextStyle(fontFamily: 'Young Serif', fontSize: 40);
    final span = serifPrivacyMaskSpan('2.5 ', style);

    expect(span.text, '2.5 ');
    expect(span.style, style);
    expect(span.children, isNull);
  });
}
