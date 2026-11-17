import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';

void main() {
  test('swap shows each address book chain with its label and icon', () {
    for (final network in AddressBookNetwork.values) {
      final asset = SwapAsset.live(
        assetId: 'test-${network.id}',
        symbol: 'TEST',
        blockchain: network.id,
        decimals: 6,
      );
      expect(asset.chainLabel, network.label, reason: network.id);
      expect(asset.chainIconAsset, network.assetPath, reason: network.id);
      expect(File(network.assetPath).existsSync(), isTrue, reason: network.id);
    }
  });

  test('built-in swap assets name their chain as the table does', () {
    for (final asset in SwapAsset.values) {
      expect(
        asset.chainLabel,
        swapChainDisplayName(asset.chainTicker),
        reason: asset.name,
      );
    }
  });

  test('swap chains map to contacts networks, EVM where the address is', () {
    final expected = {
      'hood': (AddressBookNetwork.robinhoodChain, true),
      'hypercore': (AddressBookNetwork.hyperCore, true),
      'movement': (AddressBookNetwork.movement, false),
      'qtc': (AddressBookNetwork.quantus, false),
      'fogo': (AddressBookNetwork.fogo, false),
      'miden': (AddressBookNetwork.miden, false),
      'prl': (AddressBookNetwork.pearl, false),
    };
    expected.forEach((ticker, value) {
      final (network, isEvm) = value;
      expect(AddressBookNetwork.tryFromChainTicker(ticker), network);
      expect(network.isEvm, isEvm, reason: ticker);
    });
  });
}
