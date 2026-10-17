import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

void main() {
  test('recognizes usdttron: prefix and strips it from the address', () {
    final match = detectSwapPrefixedAddress(
      'usdttron:TXYZabc123def456ghi789jkl012mno345',
    );

    expect(match, isNotNull);
    expect(match!.symbol, 'USDT');
    expect(match.chainTicker, 'tron');
    expect(match.address, 'TXYZabc123def456ghi789jkl012mno345');
  });

  test('matches the prefix case-insensitively', () {
    final match = detectSwapPrefixedAddress('USDTTRON:TAbc123');

    expect(match, isNotNull);
    expect(match!.symbol, 'USDT');
    expect(match.chainTicker, 'tron');
    expect(match.address, 'TAbc123');
  });

  test('trims surrounding whitespace on input and address', () {
    final match = detectSwapPrefixedAddress('  usdttron: TAbc123  ');

    expect(match, isNotNull);
    expect(match!.address, 'TAbc123');
  });

  test('returns null for an unrecognized prefix', () {
    expect(detectSwapPrefixedAddress('bitcoin:1abc'), isNull);
  });

  test('returns null for a plain address with no prefix', () {
    expect(detectSwapPrefixedAddress('TAbc123'), isNull);
  });

  test('returns null for an empty address after the prefix', () {
    expect(detectSwapPrefixedAddress('usdttron:'), isNull);
    expect(detectSwapPrefixedAddress('usdttron:   '), isNull);
  });

  test('returns null for an empty or blank input', () {
    expect(detectSwapPrefixedAddress(''), isNull);
    expect(detectSwapPrefixedAddress('   '), isNull);
  });

  test('does not treat a leading colon as a prefix separator', () {
    expect(detectSwapPrefixedAddress(':TAbc123'), isNull);
  });
}
