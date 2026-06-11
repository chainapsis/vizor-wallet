import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_chain_txid.dart';

void main() {
  // A real 64-hex (32-byte) display-order hash and its byte-reversed,
  // lowercased wallet-order counterpart. Each two-character byte is read from
  // the end of the string toward the start, so the reversal is the byte
  // sequence flipped (not the character sequence).
  const displayOrder =
      'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
  const walletOrder =
      '99887766554433221100ffeeddccbbaa99887766554433221100ffeeddccbbaa';

  test('byte-reverses a 64-hex hash into wallet order', () {
    expect(swapChainTxidToWalletTxidHex(displayOrder), walletOrder);
  });

  test('reversing twice returns the lowercase input', () {
    final once = swapChainTxidToWalletTxidHex(displayOrder);
    expect(once, isNotNull);
    final twice = swapChainTxidToWalletTxidHex(once);
    expect(twice, displayOrder.toLowerCase());
    // Sanity: the original is already lowercase, so the round trip is exact.
    expect(twice, displayOrder);
  });

  test('strips a 0x prefix before reversing', () {
    expect(swapChainTxidToWalletTxidHex('0x$displayOrder'), walletOrder);
    expect(swapChainTxidToWalletTxidHex('0X$displayOrder'), walletOrder);
  });

  test('lowercases uppercase hex input', () {
    expect(
      swapChainTxidToWalletTxidHex(displayOrder.toUpperCase()),
      walletOrder,
    );
    expect(
      swapChainTxidToWalletTxidHex('0X${displayOrder.toUpperCase()}'),
      walletOrder,
    );
  });

  test('trims surrounding whitespace before validating', () {
    expect(swapChainTxidToWalletTxidHex('  $displayOrder  '), walletOrder);
  });

  group('rejects malformed input by returning null', () {
    test('null', () {
      expect(swapChainTxidToWalletTxidHex(null), isNull);
    });

    test('empty string', () {
      expect(swapChainTxidToWalletTxidHex(''), isNull);
    });

    test('63 characters (one short)', () {
      expect(swapChainTxidToWalletTxidHex(displayOrder.substring(1)), isNull);
    });

    test('65 characters (one long)', () {
      expect(swapChainTxidToWalletTxidHex('${displayOrder}a'), isNull);
    });

    test('non-hex characters at full length', () {
      // 64 chars, but with a 'g' (and a 'z') that are not hex digits.
      const notHex =
          'gabbccddeeff00112233445566778899aabbccddeeff0011223344556677889z';
      expect(notHex.length, 64);
      expect(swapChainTxidToWalletTxidHex(notHex), isNull);
    });

    test('0x prefix on an otherwise too-short hash', () {
      expect(
        swapChainTxidToWalletTxidHex('0x${displayOrder.substring(2)}'),
        isNull,
      );
    });
  });
}
