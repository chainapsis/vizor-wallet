import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';

void main() {
  test('address book network catalog covers current 1Click chains', () {
    const currentOneClickChains = [
      'abs',
      'adi',
      'aleo',
      'aptos',
      'arb',
      'avax',
      'base',
      'bch',
      'bera',
      'bsc',
      'btc',
      'cardano',
      'dash',
      'doge',
      'eth',
      'gnosis',
      'ltc',
      'monad',
      'near',
      'op',
      'plasma',
      'pol',
      'scroll',
      'sol',
      'starknet',
      'stellar',
      'sui',
      'ton',
      'tron',
      'xlayer',
      'xrp',
      'zec',
    ];

    expect([
      for (final chain in currentOneClickChains)
        AddressBookNetwork.tryFromChainTicker(chain),
    ], everyElement(isNotNull));
  });

  test('address book network aliases migrate earlier persisted ids', () {
    expect(AddressBookNetwork.tryFromId('zcash'), AddressBookNetwork.zcash);
    expect(AddressBookNetwork.tryFromId('solana'), AddressBookNetwork.solana);
    expect(
      AddressBookNetwork.tryFromId('ethereum'),
      AddressBookNetwork.ethereum,
    );
    expect(AddressBookNetwork.tryFromId('usdc'), AddressBookNetwork.ethereum);
    expect(AddressBookNetwork.tryFromId('futurechain'), isNull);
  });

  test('address book contact JSON rejects unknown persisted networks', () {
    expect(
      AddressBookContact.tryFromJson(const {
        'id': 'future',
        'label': 'Future Chain',
        'network': 'futurechain',
        'address': '0xfuture',
      }),
      isNull,
    );
  });
}
