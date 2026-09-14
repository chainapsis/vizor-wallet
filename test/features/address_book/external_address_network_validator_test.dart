import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_format_validator.dart';

void main() {
  // Base58 vectors generated independently with Python hashlib, using version
  // bytes from the respective chainparams.cpp and payload bytes 00..13.
  const legacy = {
    AddressBookNetwork.litecoin: (
      [
        'LKDyUEtTR1HXamkiEphisSiBJu6o3ZPE34',
        'M7uBSTV2qNDHDe2tHfNMqhFkZucgRMpJQk',
        '31h38a54tFMrR8kzBnP2241MFD2EUHtGha',
      ],
      [
        'mfWyW5fc9NUj75YAnFgoRLrjxgLDn2MMth',
        'QLc1KKsLWovHm79aV22uihS3bwgECPid8z',
      ],
    ),
    AddressBookNetwork.dogecoin: (
      [
        'D597kHXGdkwkryF9oGhz9Bp1ypTpD1u99Z',
        '9rSHsR8xxKEkKW8Tbv3SGBdiwnQGWZ4bdM',
      ],
      [
        'nUCBUJGBZjQUjwpLq6MSPbQKDgr7DPLQiL',
        '2MsFFCK16VhsCcvPXruztdzzcTZEQCbNKjJ',
      ],
    ),
    AddressBookNetwork.dash: (
      [
        'Xags3HEXJ4G4Uuf8va2eSxLCw2KCyEhiJ7',
        '7SQfxmMEhETVQuHwTQ3XMS11AkrcJwJS18',
      ],
      [
        'yLKU4EJxjbv8peagVRM3UykZDJoaUUrXSn',
        '8eRUv6F6pmr7sCiCXf3UoopN4GdSSt6SgR',
      ],
    ),
  };
  for (final entry in legacy.entries) {
    test(
      '${entry.key.label}: accepts mainnet, rejects testnet and corruption',
      () {
        for (final value in entry.value.$1) {
          expect(addressFormatIssue(entry.key, value), isNull);
          expect(
            addressFormatIssue(
              entry.key,
              '${value.substring(0, value.length - 1)}1',
            ),
            isNotNull,
          );
        }
        for (final value in entry.value.$2) {
          expect(addressFormatIssue(entry.key, value), isNotNull);
        }
      },
    );
  }

  test('Litecoin MWEB retains mainnet acceptance and rejects testnet', () {
    // Independently encoded with Python using Litecoin's Bech32 layout.
    const mainnet =
        'ltcmweb1qqfumuen7l8wthtz45p3ftn58pvrs9xlumvkuu2xet8egzkcklqtesqnehen8a7wuhwk9tgrzjh8gwzc8q2dlekedec5djk0js9d3d7qhnqat7pqw';
    const testnet =
        'tmweb1qqfumuen7l8wthtz45p3ftn58pvrs9xlumvkuu2xet8egzkcklqtesqnehen8a7wuhwk9tgrzjh8gwzc8q2dlekedec5djk0js9d3d7qhnquzlkue';
    const shortPayload =
        'ltcmweb1qqfumuen7l8wthtz45p3ftn58pvrs9xlumvkuu2xet8egzkcklqtesq849er';
    expect(addressFormatIssue(AddressBookNetwork.litecoin, mainnet), isNull);
    expect(addressFormatIssue(AddressBookNetwork.litecoin, testnet), isNotNull);
    expect(
      addressFormatIssue(AddressBookNetwork.litecoin, shortPayload),
      isNotNull,
    );
    expect(
      addressFormatIssue(
        AddressBookNetwork.litecoin,
        '${mainnet.substring(0, mainnet.length - 1)}q',
      ),
      isNotNull,
    );
  });

  test(
    'CashAddr supports optional prefix and rejects network/checksum changes',
    () {
      // CashAddr specification vector.
      const body = 'qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a';
      for (final value in [
        body,
        'bitcoincash:$body',
        'BITCOINCASH:${body.toUpperCase()}',
        '1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu',
      ]) {
        expect(
          addressFormatIssue(AddressBookNetwork.bitcoinCash, value),
          isNull,
        );
      }
      for (final value in [
        'bchtest:$body',
        'bchreg:$body',
        'bitcoincash:${body.toUpperCase()}',
        '${body.substring(0, body.length - 1)}q',
        'mfWyW5fc9NUj75YAnFgoRLrjxgLDn2MMth',
      ]) {
        expect(
          addressFormatIssue(AddressBookNetwork.bitcoinCash, value),
          isNotNull,
        );
      }
    },
  );

  test(
    'TON rejects checksummed testnet-only flags and checksum corruption',
    () {
      // Python binascii.crc_hqx vectors, account bytes 00..1f.
      for (final value in [
        'EQAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHx2j',
        'UQAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH0Bm',
      ]) {
        expect(addressFormatIssue(AddressBookNetwork.ton, value), isNull);
      }
      for (final value in [
        'kQAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH6Yp',
        '0QAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eH_vs',
        'EQAAAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHx2q',
      ]) {
        expect(addressFormatIssue(AddressBookNetwork.ton, value), isNotNull);
      }
      expect(
        addressFormatIssue(AddressBookNetwork.ton, '0:${'ab' * 32}'),
        isNull,
      );
    },
  );

  test('Cardano Shelley validates the encoded network, not just the HRP', () {
    for (final value in [
      'addr1qyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcur50p7gppyg3jgffxyu5zj23t9skjutesxyerxdp4xcmskm46z7',
      'addr1vyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcjrvarg',
    ]) {
      expect(addressFormatIssue(AddressBookNetwork.cardano, value), isNull);
    }
    for (final value in [
      'addr_test1qqqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcur50p7gppyg3jgffxyu5zj23t9skjutesxyerxdp4xcms4dg6wp',
      'addr1qqqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcur50p7gppyg3jgffxyu5zj23t9skjutesxyerxdp4xcms8duasr',
      'addr1vqqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcj3uvr0',
    ]) {
      expect(addressFormatIssue(AddressBookNetwork.cardano, value), isNotNull);
    }
  });

  // Pointer vectors independently encoded with Python (CIP-19 / Bech32).
  test('Cardano pointer type 4 accepts numeric boundary vectors', () {
    const vectors = {
      'zero': 'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqqqq6tvnq5',
      'maximum':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xu0llll7lurlalc8lmljhdavc',
      'non-minimal in-range':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xuqqzqqrqqql0c37e',
    };
    for (final entry in vectors.entries) {
      expect(
        addressFormatIssue(AddressBookNetwork.cardano, entry.value),
        isNull,
        reason: entry.key,
      );
    }
  });

  test('Cardano pointer type 4 rejects numeric boundary vectors', () {
    const vectors = {
      'slot overflow':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xusszqgqqqqqq75m7sn',
      'transaction overflow':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqsjqqqqq3guusr',
      'certificate overflow':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqzzgqqqujyd3g',
      'long overflow':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xllllllllllllllllllluqqqqqzn78y7',
      'unterminated':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqzqq7075md',
      'extra component':
          'addr1gyqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqqqqqnu7hdz',
    };
    for (final entry in vectors.entries) {
      expect(
        addressFormatIssue(AddressBookNetwork.cardano, entry.value),
        isNotNull,
        reason: entry.key,
      );
    }
  });

  test('Cardano pointer type 5 accepts numeric boundary vectors', () {
    const vectors = {
      'zero': 'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqqqqhsjg4t',
      'maximum':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xu0llll7lurlalc8lmlq0krke',
      'non-minimal in-range':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xuqqzqqrqqqusmhq5',
    };
    for (final entry in vectors.entries) {
      expect(
        addressFormatIssue(AddressBookNetwork.cardano, entry.value),
        isNull,
        reason: entry.key,
      );
    }
  });

  test('Cardano pointer type 5 rejects numeric boundary vectors', () {
    const vectors = {
      'slot overflow':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xusszqgqqqqqqxs0s8j',
      'transaction overflow':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqsjqqqqqncx74w',
      'certificate overflow':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqzzgqqq7z7059',
      'long overflow':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xllllllllllllllllllluqqqqqzzhykg',
      'unterminated':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqzqqn5q0wj',
      'extra component':
          'addr12yqqzqsrqszsvpcgpy9qkrqdpc83qygjzv2p29shrqv35xcqqqqqqy2ha7h',
    };
    for (final entry in vectors.entries) {
      expect(
        addressFormatIssue(AddressBookNetwork.cardano, entry.value),
        isNotNull,
        reason: entry.key,
      );
    }
  });

  test('Cardano Byron reads network attribute and verifies CRC32', () {
    // Independent Python CBOR framing + zlib.crc32 vectors.
    const mainnet =
        'Ae2tdPwUPEYvonZpzjqm9roCdj4Aipuz6AAer9TVPHMWhr6qojNk1w4qoxj';
    const testnet =
        'FHnt4NL7yPXgQT5ZnAPNapmLwUprsURSZQDSoX1R8iW8emHmuZtJ3pcHr1VNEP1';
    expect(addressFormatIssue(AddressBookNetwork.cardano, mainnet), isNull);
    // Valid CRC32, but reserved Byron address type 1.
    expect(
      addressFormatIssue(
        AddressBookNetwork.cardano,
        'Ae2tdPwUPEYvonZpzjqm9roCdj4Aipuz6AAer9TVPHMWhr6qojNkWrA71yF',
      ),
      isNotNull,
    );
    expect(addressFormatIssue(AddressBookNetwork.cardano, testnet), isNotNull);
    expect(
      addressFormatIssue(AddressBookNetwork.cardano, '${mainnet}1'),
      isNotNull,
    );
  });

  test('NEAR blocks explicit testnet names but keeps implicit accounts', () {
    for (final value in ['testnet', 'alice.testnet', 'sub.alice.testnet']) {
      expect(addressFormatIssue(AddressBookNetwork.near, value), isNotNull);
    }
    for (final value in ['alice.near', 'ab' * 32]) {
      expect(addressFormatIssue(AddressBookNetwork.near, value), isNull);
    }
  });
}
