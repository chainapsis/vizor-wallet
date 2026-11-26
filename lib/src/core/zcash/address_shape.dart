/// The shape of a Zcash address, as regular-expression fragments: a bech32m
/// address with one of the Zcash human-readable parts, or a
/// Base58Check transparent address. Shape only, with no checksum: it tells an
/// address-shaped word apart from the words around it and nothing more. Log
/// redaction masks every match; the share intake hands the first one to the
/// payment-request card, whose precheck says whether it is real and for which
/// network.
///
/// The HRPs are the zakura-protocol 3.0.0 constants
/// (constants/{mainnet,testnet,regtest}.rs). Ironwood shares the Orchard
/// receiver, so it has no HRP of its own. Longer prefixes come first.
library;

const _addressHrps = [
  'zregtestsapling',
  'ztestsapling',
  'texregtest',
  'uregtest',
  'textest',
  'utest',
  'tex',
  'zs',
  'u',
];

const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

/// The shortest encoding of any address is a TEX address: 20 bytes, 38
/// characters.
const _bech32MinData = 38;

/// Base58Check prefixes 0x1cb8/0x1cbd (mainnet), 0x1d25/0x1cba (test/regtest)
/// encode as t1/t3 and tm/t2; every transparent address is 35 characters.
const _transparent = r'(?:t1|t3|tm|t2)[1-9A-HJ-NP-Za-km-z]{33}';

/// A bech32 string with one of [hrps], in either letter case throughout.
String bech32Shape(List<String> hrps) {
  final lower = hrps.join('|');
  final upper = hrps.map((hrp) => hrp.toUpperCase()).join('|');
  final upperCharset = _bech32Charset.toUpperCase();
  return '(?:(?:$lower)1[$_bech32Charset]{$_bech32MinData,}' // l10n-ignore: regular expression
      '|(?:$upper)1[$upperCharset]{$_bech32MinData,})';
}

/// Any Zcash address.
final zcashAddressShape = '(?:${bech32Shape(_addressHrps)}|$_transparent)';
