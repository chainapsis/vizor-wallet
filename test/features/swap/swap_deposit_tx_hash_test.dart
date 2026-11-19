import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_tx_hash.dart';

void main() {
  const hex =
      '4f2c9a1e7b3d5f8a0c6e2b9d4f1a7c3e5b8d0f2a6c9e1b4d7f0a3c5e8b2d6f9a';

  test('a hash of the deposit chain passes, trimmed', () {
    expect(swapDepositTxHashOrNull('ltc', '  $hex\n'), hex);
    expect(
      swapDepositTxHashOrNull('btc', hex.toUpperCase()),
      hex.toUpperCase(),
    );
    expect(swapDepositTxHashOrNull('eth', '0x$hex'), '0x$hex');
    expect(swapDepositTxHashOrNull('base', '0x$hex'), '0x$hex');
    expect(swapDepositTxHashOrNull('aptos', '0x$hex'), '0x$hex');
    const solana =
        '5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzrFmBV6UjKdiSZkQUW';
    expect(swapDepositTxHashOrNull('sol', solana), solana);
    const near = 'EfMTmKcGPqA3V1g9NEjRRCJAkGqzQsCbfAyP2wwZQdvq';
    expect(swapDepositTxHashOrNull('near', near), near);
    expect(swapDepositTxHashOrNull('starknet', '0x4a7b'), '0x4a7b');
    // A chain the wallet has no format for takes a plain token.
    expect(
      swapDepositTxHashOrNull('newchain', 'at1abcdef0123456789'),
      isNotNull,
    );
  });

  test('text that is not a hash of the deposit chain is refused', () {
    for (final (chain, input) in [
      // Another chain's format.
      ('ltc', '0x$hex'),
      ('eth', hex),
      ('sol', '0x$hex'),
      // Too short, or an address.
      ('ltc', hex.substring(1)),
      ('ltc', 'ltc1qdraftrefund8x2m4k7p9s3v6w0y5z2c8n4q'),
      ('eth', '0x52908400098527886E0F7030069857D2E4169EE7'),
      // A pasted phrase never leaves the device.
      ('newchain', 'abandon ability able about above absent absorb'),
      ('ltc', ''),
    ]) {
      expect(
        swapDepositTxHashOrNull(chain, input),
        isNull,
        reason: '$chain $input',
      );
    }
  });
}
