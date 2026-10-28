import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_privacy_mask.dart';

void main() {
  test('swap amount masks keep the amount own symbol', () {
    String mask(String text, {int maskLength = 6}) => swapAmountTextForPrivacy(
      text,
      privacyModeEnabled: true,
      maskLength: maskLength,
    );

    expect(mask('0.21 USDC'), '****** USDC');
    expect(mask('4 SOL'), '****** SOL');
    expect(mask('1.2500 ZEC'), '****** ZEC');
    expect(mask('0 USDC'), '****** USDC');
    expect(mask('-0.0030 ZEC', maskLength: 3), '*** ZEC');
    expect(mask('+12.13 ZEC', maskLength: 3), '*** ZEC');
    expect(mask('1,234.56 USDC'), '****** USDC');
    expect(mask('<0.000001 USDC'), '****** USDC');
    expect(mask('1.5'), '******');
  });

  test('swap amount masks fail closed on unrecognized text with a number', () {
    String mask(String text) =>
        swapAmountTextForPrivacy(text, privacyModeEnabled: true);

    expect(mask('≈ 1.2 USDC'), '******');
    expect(mask(r'1.2 USDC (≈ $1.20)'), '******');
    expect(mask('1.2 USDC refunded'), '******');
  });

  test('swap amount masks leave fixed copy and placeholders visible', () {
    for (final text in [
      'Included in shown rate',
      'Included',
      'Not reported',
      'Configured quote',
      '--',
      '',
    ]) {
      expect(swapAmountTextForPrivacy(text, privacyModeEnabled: true), text);
    }
  });

  test('swap amount masks are a no-op with privacy mode off', () {
    expect(
      swapAmountTextForPrivacy('0.21 USDC', privacyModeEnabled: false),
      '0.21 USDC',
    );
    expect(
      swapFiatTextForPrivacy(r'$12.34', privacyModeEnabled: false),
      r'$12.34',
    );
  });

  test('swap fiat masks are bare and keep the empty placeholder', () {
    expect(
      swapFiatTextForPrivacy(r'$12.34', privacyModeEnabled: true),
      '******',
    );
    expect(
      swapFiatTextForPrivacy(r'$1.2K', privacyModeEnabled: true),
      '******',
    );
    expect(swapFiatTextForPrivacy(r'$--', privacyModeEnabled: true), r'$--');
  });
}
