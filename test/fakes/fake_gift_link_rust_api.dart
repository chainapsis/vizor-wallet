import 'dart:typed_data';

import 'package:zcash_wallet/src/rust/frb_generated.dart';

// Public zero-entropy BIP-39 vectors, never for funding real wallets.
final giftTestMnemonic24 = '${List.filled(23, 'abandon').join(' ')} art';
final giftTestMnemonic12 = '${List.filled(11, 'abandon').join(' ')} about';

/// Pure fixture conversion for widget tests. Native tests cover real derivation.
class FakeGiftLinkRustApi implements RustLibApi {
  @override
  Uint8List crateApiWalletGiftMnemonicToEntropy({required String mnemonic}) {
    if (mnemonic == giftTestMnemonic24) return Uint8List(32);
    if (mnemonic == giftTestMnemonic12) return Uint8List(16);
    throw const FormatException('Unknown test mnemonic');
  }

  @override
  String crateApiWalletGiftMnemonicFromEntropy({required List<int> entropy}) {
    if (entropy.any((byte) => byte != 0)) {
      throw const FormatException('Unknown test entropy');
    }
    if (entropy.length == 32) return giftTestMnemonic24;
    if (entropy.length == 16) return giftTestMnemonic12;
    throw const FormatException('Unknown test entropy length');
  }

  @override
  Future<void> crateApiWalletValidateGiftAddress({
    required String mnemonic,
    required String network,
    required String address,
  }) async {
    crateApiWalletGiftMnemonicToEntropy(mnemonic: mnemonic);
    if (address.isEmpty || !['main', 'regtest'].contains(network)) {
      throw const FormatException('Invalid test gift metadata');
    }
  }

  @override
  Future<BigInt> crateApiWalletGetLatestBlockHeight({
    required String lightwalletdUrl,
    required String network,
  }) async => BigInt.from(3500000);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
