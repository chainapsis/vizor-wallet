/// What a QR code scanned into an address field turned out to be.
///
/// Swap, Pay and the address book scan for a destination on one chain, not
/// for a payment to answer. A payment URI is still the usual way a wallet
/// shows its address, so the scan reads the recipient out of one — but only
/// when the URI is for the field's own chain. The rest of the request is
/// left out. The send flow answers `zcash:` requests in full and keeps its
/// own resolver (`send_scan_result.dart`).
library;

import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_format_validator.dart';
import 'address_scan_payload.dart';

/// Why a scan cannot fill the address field it was opened from.
enum AddressScanRejection {
  /// Not an address or a payment URI the scanner reads: a web link, another
  /// feature's QR code, a contract call that names no recipient.
  unsupported,

  /// A payment URI for a different chain than the field's.
  wrongNetwork,

  /// An address the field's chain cannot accept;
  /// [AddressScanRejected.finding] says why.
  invalidAddress,
}

sealed class AddressScanResolution {
  const AddressScanResolution();
}

class AddressScanAccepted extends AddressScanResolution {
  const AddressScanAccepted(this.address);

  final String address;
}

class AddressScanRejected extends AddressScanResolution {
  const AddressScanRejected(this.reason, {this.finding, this.network});

  final AddressScanRejection reason;
  final AddressFormatFinding? finding;

  /// For [AddressScanRejection.wrongNetwork], the chain the code is for, or
  /// null when it names none the app knows.
  final AddressBookNetwork? network;
}

const _unsupported = AddressScanRejected(AddressScanRejection.unsupported);
const _wrongNetwork = AddressScanRejected(AddressScanRejection.wrongNetwork);

AddressScanRejected _wrongNetworkFor(AddressBookNetwork? network) =>
    AddressScanRejected(AddressScanRejection.wrongNetwork, network: network);

/// Resolves a scanned payload for an address field on [network].
///
/// [network] is null when the field's chain has no [AddressBookNetwork]; a
/// bare address is then taken as scanned, as is an EVM address in an
/// `ethereum:` URI that names no chain. Any other payment URI is refused
/// because nothing confirms it is for that chain.
///
/// Text without a URI scheme is accepted exactly when [addressFormatIssue]
/// accepts it, so the scanner is neither stricter nor looser than the field.
/// Never throws: a scanner callback has nowhere to report an exception.
AddressScanResolution resolveAddressScan(
  String raw, {
  required AddressBookNetwork? network,
}) {
  final input = raw.trim();
  if (input.isEmpty) return _unsupported;

  final uri = _ScannedUri.tryParse(input);
  if (uri == null) return _checked(input, network);

  switch (uri.scheme) {
    case 'zcash':
      if (network != AddressBookNetwork.zcash) {
        return _wrongNetworkFor(AddressBookNetwork.zcash);
      }
      final address = normalizeAddressScanPayload(input);
      // With no recipient to recover, the payload comes back as scanned.
      if (address == null || _ScannedUri.tryParse(address) != null) {
        return _unsupported;
      }
      return _checked(address, network);
    case 'ethereum' || 'eth':
      return _resolveEthereum(uri, network);
  }

  final uriNetwork = _uriSchemeNetworks[uri.scheme];
  if (uriNetwork == null) return _unsupported;
  if (uriNetwork != network) return _wrongNetworkFor(uriNetwork);
  var body = uri.decodedBody;
  if (body == null) return _unsupported;
  if (network == AddressBookNetwork.ton) {
    // Tonkeeper's `ton://transfer/<address>`. A `bin` payload makes it a
    // contract call rather than a payment to the address.
    if (!body.toLowerCase().startsWith(_tonTransfer) ||
        uri.hasParameter('bin')) {
      return _unsupported;
    }
    body = body.substring(_tonTransfer.length);
  }
  final separator = body.indexOf('/');
  final address = (separator == -1 ? body : body.substring(0, separator))
      .trim();
  if (address.isEmpty) return _unsupported;
  return _checked(
    // A CashAddr's prefix is part of the address, not a payment scheme. A
    // legacy address has none.
    network == AddressBookNetwork.bitcoinCash &&
            !_legacyBase58.hasMatch(address)
        ? 'bitcoincash:${address.toLowerCase()}'
        : address,
    network,
  );
}

const _tonTransfer = 'transfer/';
final _legacyBase58 = RegExp('^[13]');

/// URI schemes that carry an address as their path, BIP-21 style, or after
/// `transfer/` for TON.
const _uriSchemeNetworks = {
  'bitcoin': AddressBookNetwork.bitcoin,
  'bitcoincash': AddressBookNetwork.bitcoinCash,
  'dash': AddressBookNetwork.dash,
  'dogecoin': AddressBookNetwork.dogecoin,
  'litecoin': AddressBookNetwork.litecoin,
  'near': AddressBookNetwork.near,
  'solana': AddressBookNetwork.solana,
  'ton': AddressBookNetwork.ton,
  'tron': AddressBookNetwork.tron,
};

/// EIP-155 chain IDs of the EVM chains an address field can be on, checked
/// against chainid.network. An ID missing here is refused rather than guessed:
/// that costs a paste, while a wrong entry would accept another chain's
/// request.
const _evmChainNetworks = {
  1: AddressBookNetwork.ethereum,
  10: AddressBookNetwork.optimism,
  56: AddressBookNetwork.binanceSmartChain,
  100: AddressBookNetwork.gnosis,
  137: AddressBookNetwork.polygon,
  143: AddressBookNetwork.monad,
  196: AddressBookNetwork.xLayer,
  2741: AddressBookNetwork.abstractChain,
  4663: AddressBookNetwork.robinhoodChain,
  8453: AddressBookNetwork.base,
  9745: AddressBookNetwork.plasma,
  42161: AddressBookNetwork.arbitrum,
  43114: AddressBookNetwork.avalanche,
  80094: AddressBookNetwork.bera,
  534352: AddressBookNetwork.scroll,
};

final _decimalChainId = RegExp(r'^[0-9]+$');
final _hexChainId = RegExp(r'^0[xX][0-9a-fA-F]+$');

/// EIP-681 writes a chain ID in decimal. Some wallets write it in hex, and
/// MetaMask reads both.
int? _parseChainId(String value) {
  if (_decimalChainId.hasMatch(value)) return int.tryParse(value);
  if (_hexChainId.hasMatch(value)) {
    return int.tryParse(value.substring(2), radix: 16);
  }
  return null;
}

/// EIP-681: `ethereum:[pay-]<target>[@<chain id>][/<function>][?<params>]`.
AddressScanResolution _resolveEthereum(
  _ScannedUri uri,
  AddressBookNetwork? network,
) {
  var body = uri.decodedBody;
  // EIP-681 has no fragment; one can hide a call after the target.
  if (body == null || uri.hasFragment) return _unsupported;
  if (body.toLowerCase().startsWith('pay-')) body = body.substring(4);

  String? function;
  final functionStart = body.indexOf('/');
  if (functionStart != -1) {
    function = body.substring(functionStart + 1);
    body = body.substring(0, functionStart);
  }

  final chainStart = body.indexOf('@');
  if (chainStart != -1) {
    final chainNetwork =
        _evmChainNetworks[_parseChainId(body.substring(chainStart + 1))];
    body = body.substring(0, chainStart);
    // A named chain has to be the field's. The address is the same on every
    // EVM chain, but a contract wallet or an exchange deposit address may
    // belong to someone else there.
    if (chainNetwork == null) return _wrongNetwork;
    if (chainNetwork != network) return _wrongNetworkFor(chainNetwork);
  } else if (network != null && !network.isEvm) {
    // No chain ID means "the chain you are on", which only an EVM field is.
    // A field on a chain the app doesn't know may be one, as for a bare
    // address.
    return _wrongNetwork;
  }
  final evmNetwork = network ?? AddressBookNetwork.ethereum;

  if (function == null || function.isEmpty) {
    // An `address` argument belongs to a call. Without one, it is unclear
    // whether it or the target is the payee: the target may be a token.
    if (uri.hasParameter('address')) return _unsupported;
    final target = body.trim();
    if (target.isEmpty) return _unsupported;
    return _checked(target, evmNetwork);
  }
  // A token transfer's target is the token contract; its recipient is the
  // `address` argument. Any other call names no recipient at all.
  final recipient = function.toLowerCase() == 'transfer'
      ? uri.parameter('address')
      : null;
  if (recipient == null || recipient.trim().isEmpty) return _unsupported;
  return _checked(recipient.trim(), evmNetwork);
}

AddressScanResolution _checked(String address, AddressBookNetwork? network) {
  final finding = network == null ? null : addressFormatIssue(network, address);
  if (finding != null) {
    return AddressScanRejected(
      AddressScanRejection.invalidAddress,
      finding: finding,
    );
  }
  return AddressScanAccepted(address);
}

/// A scanned `scheme:body?query#fragment`, split without `Uri`: its accessors
/// throw on a malformed percent-escape, and it lowercases an authority, which
/// corrupts a mixed-case address written as `scheme://address`.
class _ScannedUri {
  _ScannedUri._(this.scheme, this._body, this._query, this._fragment);

  /// Null when [input] has no URI scheme. A scheme starts with a letter, so a
  /// TON raw address (`0:…`) is not one.
  static _ScannedUri? tryParse(String input) {
    final match = _schemePattern.firstMatch(input);
    if (match == null) return null;
    var rest = input.substring(match.end);
    String? fragment;
    final fragmentStart = rest.indexOf('#');
    if (fragmentStart != -1) {
      fragment = rest.substring(fragmentStart + 1);
      rest = rest.substring(0, fragmentStart);
    }
    var query = '';
    final queryStart = rest.indexOf('?');
    if (queryStart != -1) {
      query = rest.substring(queryStart + 1);
      rest = rest.substring(0, queryStart);
    }
    if (rest.startsWith('//')) rest = rest.substring(2);
    return _ScannedUri._(match.group(1)!.toLowerCase(), rest, query, fragment);
  }

  static final _schemePattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):');

  /// Lowercased; QR codes are often all uppercase.
  final String scheme;
  final String _body;
  final String _query;
  final String? _fragment;

  /// The part between the scheme and the query, or null when it cannot be
  /// percent-decoded.
  String? get decodedBody => _tryDecode(_body, Uri.decodeComponent);

  bool get hasFragment => _fragment?.isNotEmpty ?? false;

  /// Whether [name] appears at all, even repeated or undecodable.
  bool hasParameter(String name) =>
      _query.split('&').any((parameter) => _parameterName(parameter) == name);

  /// The value of [name], or null when it is absent, repeated or cannot be
  /// decoded. A repeated recipient has no single reading.
  String? parameter(String name) {
    String? found;
    for (final parameter in _query.split('&')) {
      if (parameter.isEmpty) continue;
      final separator = parameter.indexOf('=');
      if (_parameterName(parameter) != name) continue;
      if (found != null || separator == -1) return null;
      found = _tryDecode(
        parameter.substring(separator + 1),
        Uri.decodeQueryComponent,
      );
      if (found == null) return null;
    }
    return found;
  }

  /// Lowercased, and as written when it cannot be decoded.
  static String _parameterName(String parameter) {
    final separator = parameter.indexOf('=');
    final name = separator == -1
        ? parameter
        : parameter.substring(0, separator);
    return (_tryDecode(name, Uri.decodeQueryComponent) ?? name).toLowerCase();
  }
}

String? _tryDecode(String value, String Function(String) decode) {
  try {
    return decode(value);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}
