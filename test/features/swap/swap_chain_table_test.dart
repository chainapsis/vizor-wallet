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
}
