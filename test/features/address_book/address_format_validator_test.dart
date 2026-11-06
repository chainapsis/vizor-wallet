import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_format_validator.dart';
import '../../support/test_l10n.dart';

/// The error-severity message, in English.
String? _issue(
  AddressBookNetwork network,
  String address, {
  ZcashNetwork? zcashNetwork,
}) => addressFormatIssue(
  network,
  address,
  zcashNetwork: zcashNetwork,
)?.localizedMessage(testL10n);

void main() {
  group('addressFormatIssue', () {
    test('empty address has no opinion (handled by emptiness validators)', () {
      expect(_issue(AddressBookNetwork.ethereum, ''), isNull);
      expect(_issue(AddressBookNetwork.ethereum, '   '), isNull);
    });

    test('unsupported networks always pass', () {
      for (final network in [
        AddressBookNetwork.ton,
        AddressBookNetwork.cardano,
        AddressBookNetwork.stellar,
        AddressBookNetwork.xrp,
        AddressBookNetwork.sui,
        AddressBookNetwork.dogecoin,
      ]) {
        expect(
          _issue(network, 'literally anything goes here'),
          isNull,
          reason: '${network.id} has no validator',
        );
      }
    });

    group('EVM family', () {
      const valid = '0x52908400098527886E0F7030069857D2E4169EE7';
      for (final network in [
        AddressBookNetwork.ethereum,
        AddressBookNetwork.base,
        AddressBookNetwork.arbitrum,
        AddressBookNetwork.optimism,
        AddressBookNetwork.polygon,
        AddressBookNetwork.binanceSmartChain,
        AddressBookNetwork.avalanche,
        AddressBookNetwork.gnosis,
        AddressBookNetwork.scroll,
        AddressBookNetwork.xLayer,
        AddressBookNetwork.plasma,
        AddressBookNetwork.abstractChain,
        AddressBookNetwork.monad,
        AddressBookNetwork.bera,
      ]) {
        test('${network.id} accepts a 0x + 40 hex address', () {
          expect(_issue(network, valid), isNull);
        });
      }

      test('rejects missing 0x prefix', () {
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '52908400098527886E0F7030069857D2E4169EE7',
          ),
          contains('EVM'),
        );
      });

      test('rejects wrong length', () {
        expect(_issue(AddressBookNetwork.ethereum, '0x1234'), isNotNull);
      });

      test('rejects non-hex characters', () {
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '0xZZ908400098527886E0F7030069857D2E4169EE7',
          ),
          isNotNull,
        );
      });

      test('accepts an uppercase 0X prefix', () {
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '0X52908400098527886E0F7030069857D2E4169EE7',
          ),
          isNull,
        );
      });

      test('accepts all-lowercase (no checksum info to verify)', () {
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '0xde709f2102306220921060314715629080e2fb77',
          ),
          isNull,
        );
      });

      test('accepts correctly EIP-55 checksummed addresses', () {
        for (final addr in [
          '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
          '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
          '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
        ]) {
          expect(
            _issue(AddressBookNetwork.ethereum, addr),
            isNull,
            reason: addr,
          );
        }
      });

      test('rejects a mixed-case address with a broken checksum', () {
        // Valid address with one letter's case flipped.
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          ),
          contains('EVM'),
        );
      });

      test('accepts real-world checksummed mainnet addresses', () {
        for (final addr in [
          '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045', // vitalik.eth
          '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC
          '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
          '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D', // Uniswap V2 router
        ]) {
          expect(_issue(AddressBookNetwork.base, addr), isNull, reason: addr);
        }
      });

      test('accepts the lowercase form of a real address', () {
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
          ),
          isNull,
        );
      });

      test('rejects 39- and 41-hex lengths', () {
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '0x52908400098527886E0F7030069857D2E4169EE',
          ),
          isNotNull,
        );
        expect(
          _issue(
            AddressBookNetwork.ethereum,
            '0x52908400098527886E0F7030069857D2E4169EE77',
          ),
          isNotNull,
        );
      });
    });

    group('Bitcoin', () {
      test('accepts P2PKH (1...)', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
          ),
          isNull,
        );
      });

      test('accepts P2SH (3...)', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy',
          ),
          isNull,
        );
      });

      test('accepts bech32 (bc1...)', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
          ),
          isNull,
        );
      });

      test('accepts taproot (bc1p...)', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr',
          ),
          isNull,
        );
      });

      test('accepts the genesis P2PKH address', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
          ),
          isNull,
        );
      });

      test('rejects a legacy address with a bad base58check checksum', () {
        // Genesis P2PKH with the last character flipped (a -> b): valid base58
        // charset and length, but the double-SHA256 checksum no longer holds.
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb',
          ),
          contains('Bitcoin'),
        );
      });

      test('rejects a native segwit address with a bad checksum', () {
        // Last character flipped (…f3t4 -> …f3t5): valid charset/length but the
        // bech32 checksum no longer holds, so it must be rejected.
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5',
          ),
          contains('Bitcoin'),
        );
      });

      test('rejects a testnet segwit address (tb1...) on mainnet', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
          ),
          isNotNull,
        );
      });

      test('rejects mixed-case bech32', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            'bc1qw508d6qejxtdg4y5r3zarvarY0c5xw7kv8f3t4',
          ),
          isNotNull,
        );
      });

      test('rejects an EVM address', () {
        expect(
          _issue(
            AddressBookNetwork.bitcoin,
            '0x52908400098527886E0F7030069857D2E4169EE7',
          ),
          contains('Bitcoin'),
        );
      });
    });

    group('Zcash', () {
      test('accepts a unified address (u1...)', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            'u1l9f0l4348negsncgr9pxd9d3qaxagmqv3lnexcplmrfn8vnnlnzfm4hd2gxn'
            'wrdwy55q9xs8dwd56tppd0aqgg9k4n2x9p3zg3sx',
          ),
          isNull,
        );
      });

      test('accepts a transparent address (t1...)', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            't1HsdDMzmJfq4vc7T17XYjEkLMLvbgM1fCi',
          ),
          isNull,
        );
      });

      test('accepts a sapling address (zs1...)', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            'zs1z7rejlpsa98s2rrrfkwmaxu53e4ue0ulcrw0h4x5g8jl04tak0d3mm47'
            'vdtahatqrlkngh9sly',
          ),
          isNull,
        );
      });

      test('accepts a P2SH transparent address (t3...)', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            't3Vz22vK5z2LcKEdg16Yv4FFneEL1zg9ojd',
          ),
          isNull,
        );
      });

      test('accepts TEX addresses for the active Zcash network', () {
        const mainnetTex = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';
        const testnetTex = 'textest1qyqszqgpqyqszqgpqyqszqgpqyqszqgpfcjgfy';
        const regtestTex = 'texregtest1qyqszqgpqyqszqgpqyqszqgpqyqszqgpfcjgfy';

        expect(
          _issue(
            AddressBookNetwork.zcash,
            mainnetTex,
            zcashNetwork: ZcashNetwork.mainnet,
          ),
          isNull,
        );
        expect(
          _issue(
            AddressBookNetwork.zcash,
            testnetTex,
            zcashNetwork: ZcashNetwork.testnet,
          ),
          isNull,
        );
        expect(
          _issue(
            AddressBookNetwork.zcash,
            regtestTex,
            zcashNetwork: ZcashNetwork.regtest,
          ),
          isNull,
        );
      });

      test('rejects an EVM address tagged as Zcash', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            '0x52908400098527886E0F7030069857D2E4169EE7',
          ),
          contains('Zcash'),
        );
      });

      test('rejects obvious garbage', () {
        expect(_issue(AddressBookNetwork.zcash, 'not an address'), isNotNull);
      });

      test('on mainnet, rejects testnet-prefixed addresses', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            'utest1qpw508d6qejxtdg4y5r3zarvary0c5xw7kqqqqqq',
            zcashNetwork: ZcashNetwork.mainnet,
          ),
          isNotNull,
        );
        expect(
          _issue(
            AddressBookNetwork.zcash,
            'tm9iNYCVAhLLa4rJtfqqHauR5xL1REdpiDs',
            zcashNetwork: ZcashNetwork.mainnet,
          ),
          isNotNull,
        );
        expect(
          _issue(
            AddressBookNetwork.zcash,
            'textest1qyqszqgpqyqszqgpqyqszqgpqyqszqgpfcjgfy',
            zcashNetwork: ZcashNetwork.mainnet,
          ),
          isNotNull,
        );
      });

      test('honours the active Zcash network for its own prefixes', () {
        const testnetUa = 'utest1qpw508d6qejxtdg4y5r3zarvary0c5xw7kqqqqqq';
        expect(
          _issue(
            AddressBookNetwork.zcash,
            testnetUa,
            zcashNetwork: ZcashNetwork.testnet,
          ),
          isNull,
        );
        // A mainnet t-addr is not valid on testnet.
        expect(
          _issue(
            AddressBookNetwork.zcash,
            't1HsdDMzmJfq4vc7T17XYjEkLMLvbgM1fCi',
            zcashNetwork: ZcashNetwork.testnet,
          ),
          isNotNull,
        );
      });

      test('accepts a checksum-valid testnet t-addr on testnet', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            'tm9iNYCVAhLLa4rJtfqqHauR5xL1REdpiDs',
            zcashNetwork: ZcashNetwork.testnet,
          ),
          isNull,
        );
      });

      test('rejects a t-addr with a corrupted Base58Check checksum', () {
        // Last character of the valid vector flipped (i -> j).
        expect(
          _issue(
            AddressBookNetwork.zcash,
            't1HsdDMzmJfq4vc7T17XYjEkLMLvbgM1fCj',
          ),
          isNotNull,
        );
      });

      test('rejects checksum-free base58 padding behind a t1 prefix', () {
        expect(
          _issue(
            AddressBookNetwork.zcash,
            't1zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
          ),
          isNotNull,
        );
      });
    });

    group('Solana', () {
      test('accepts a base58 32-44 char address', () {
        expect(
          _issue(
            AddressBookNetwork.solana,
            '7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs',
          ),
          isNull,
        );
      });

      test('rejects an EVM 0x address', () {
        expect(
          _issue(
            AddressBookNetwork.solana,
            '0x52908400098527886E0F7030069857D2E4169EE7',
          ),
          contains('Solana'),
        );
      });

      test('accepts real-world mint addresses', () {
        for (final addr in [
          'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', // USDC mint
          'So11111111111111111111111111111111111111112', // wrapped SOL
        ]) {
          expect(_issue(AddressBookNetwork.solana, addr), isNull, reason: addr);
        }
      });

      test('rejects too-short input', () {
        expect(_issue(AddressBookNetwork.solana, 'abc'), isNotNull);
      });

      test('rejects input longer than 44 chars', () {
        expect(
          _issue(
            AddressBookNetwork.solana,
            '7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs7EYnh',
          ),
          isNotNull,
        );
      });

      test('rejects non-base58 characters (0, O, I, l)', () {
        expect(
          _issue(
            AddressBookNetwork.solana,
            '0OIl00000000000000000000000000000000',
          ),
          isNotNull,
        );
      });

      test('rejects charset-valid strings that do not decode to 32 bytes', () {
        for (final addr in [
          // 34 chars of '2' decodes to ~25 bytes — structurally impossible.
          '2222222222222222222222222222222222',
          // 44 chars of 'z' decodes to 33 bytes — too large for a pubkey.
          'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
        ]) {
          expect(
            _issue(AddressBookNetwork.solana, addr),
            isNotNull,
            reason: addr,
          );
        }
      });

      test('accepts the 32-char system program address (32 zero bytes)', () {
        expect(
          _issue(AddressBookNetwork.solana, '11111111111111111111111111111111'),
          isNull,
        );
      });
    });

    group('NEAR', () {
      test('accepts an implicit 64-hex account', () {
        expect(
          _issue(
            AddressBookNetwork.near,
            '98793cd91a3f870fb126f66285808c7e094afcfc4eda8a970f6648cdf0dbdb24',
          ),
          isNull,
        );
      });

      test('accepts named and sub-accounts', () {
        for (final acct in [
          'alice.near',
          'app.sub.near',
          'aurora',
          'token.sweat',
          'app.nearcrowd.near',
          'root.near',
          'a.b',
        ]) {
          expect(_issue(AddressBookNetwork.near, acct), isNull, reason: acct);
        }
      });

      test('rejects uppercase / invalid characters', () {
        expect(_issue(AddressBookNetwork.near, 'Alice.NEAR'), isNotNull);
        expect(_issue(AddressBookNetwork.near, 'a'), isNotNull);
      });

      test('rejects an over-long named account (>64)', () {
        expect(_issue(AddressBookNetwork.near, '${'a' * 65}.near'), isNotNull);
      });

      test('rejects consecutive / leading / trailing separators', () {
        for (final acct in [
          'foo..bar.near', // consecutive dots
          'a--b', // consecutive dashes
          'app_.near', // separator adjacent to dot
          '.alice.near', // leading separator
          'alice.near.', // trailing separator
        ]) {
          expect(
            _issue(AddressBookNetwork.near, acct),
            isNotNull,
            reason: acct,
          );
        }
      });

      test('warns on bare top-level names without blocking the hard gate', () {
        for (final acct in ['alice', 'aurora', 'sweat']) {
          final finding = addressFormatCheck(AddressBookNetwork.near, acct);
          expect(
            finding?.severity,
            AddressFormatSeverity.warning,
            reason: acct,
          );
          expect(
            finding?.localizedMessage(testL10n),
            contains('.near'),
            reason: acct,
          );
          // The error-only view used by the swap hard gate stays silent, so
          // real registrar-created top-level accounts are never blocked.
          expect(_issue(AddressBookNetwork.near, acct), isNull, reason: acct);
        }
      });

      test('does not warn on dotted names or implicit accounts', () {
        for (final acct in [
          'alice.near',
          'token.sweat',
          // NEAR-implicit (64 hex).
          '98793cd91a3f870fb126f66285808c7e094afcfc4eda8a970f6648cdf0dbdb24',
          // ETH-implicit (0x + 40 lowercase hex).
          '0x32400084c286cf3e17e7b677ea9583e60a000324',
        ]) {
          expect(
            addressFormatCheck(AddressBookNetwork.near, acct),
            isNull,
            reason: acct,
          );
        }
      });

      test('grammar violations are error severity, not warnings', () {
        expect(
          addressFormatCheck(AddressBookNetwork.near, 'Alice.NEAR')?.severity,
          AddressFormatSeverity.error,
        );
      });
    });
  });
}
