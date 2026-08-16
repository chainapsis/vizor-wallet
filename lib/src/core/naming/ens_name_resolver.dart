import 'dart:convert';

import '../../features/address_book/models/address_book_contact.dart';
import '../../features/address_book/models/address_format_validator.dart';
import 'ens_codec.dart';
import 'ens_name.dart';
import 'ens_rpc_transport.dart';

/// Reasons an ENS name resolution can fail, mapped to user-displayable
/// messages via [EnsResolutionException.message].
enum EnsResolutionFailure { invalidName, notRegistered, noRecord, network }

/// Thrown by [EnsNameResolver] when a name cannot be resolved. [message] is
/// sentence-case and safe to show directly to the user.
class EnsResolutionException implements Exception {
  const EnsResolutionException(this.kind, this.message);

  final EnsResolutionFailure kind;
  final String message;

  @override
  String toString() => 'EnsResolutionException: $message';
}

const _offchainLookupSelector = '0x556f1830';
final _ethCoinType = BigInt.from(60);
final _zecCoinType = BigInt.from(133);

/// Resolves ENS names to EVM addresses (ENSIP-11 chain-specific records,
/// falling back to the ETH record) and Zcash addresses (SLIP-44 coin type
/// 133), via ENSIP-10 `resolve(bytes,bytes)` on the UniversalResolver.
class EnsNameResolver {
  EnsNameResolver(this._transport, {this.universalResolver = kUniversalResolver});

  /// Canonical mainnet UniversalResolver address (ENS deployment).
  static const kUniversalResolver = '0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe';

  final EnsRpcTransport _transport;
  final String universalResolver;

  /// Resolve to an EVM 0x address for [chainId] (ENSIP-11 coin type),
  /// falling back to the ETH record (coin type 60) when the chain-specific
  /// record is empty. Returns an EIP-55 checksummed address.
  Future<String> resolveEvmAddress(String name, {required int chainId}) async {
    final normalized = _normalize(name);
    final dnsName = dnsEncodeName(normalized);
    final node = namehash(normalized);

    var payload = await _fetchRecordPayload(
      dnsName: dnsName,
      node: node,
      coinType: evmCoinType(chainId),
    );

    if (_isEmptyOrZero(payload) && chainId != 1) {
      payload = await _fetchRecordPayload(
        dnsName: dnsName,
        node: node,
        coinType: _ethCoinType,
      );
    }

    if (_isEmptyOrZero(payload)) {
      throw const EnsResolutionException(
        EnsResolutionFailure.noRecord,
        'Name has no address for this chain',
      );
    }
    return decodeAddressWord(payload);
  }

  /// Resolve the ZEC record (SLIP-44 coin type 133). No fallback: a name
  /// without a usable ZEC record throws [EnsResolutionFailure.noRecord].
  /// Returns the Zcash address string.
  Future<String> resolveZcashAddress(String name) async {
    final normalized = _normalize(name);
    final dnsName = dnsEncodeName(normalized);
    final node = namehash(normalized);

    final payload = await _fetchRecordPayload(
      dnsName: dnsName,
      node: node,
      coinType: _zecCoinType,
    );

    if (payload.isEmpty) {
      throw const EnsResolutionException(
        EnsResolutionFailure.noRecord,
        'Name has no usable Zcash address record',
      );
    }

    String? text;
    try {
      text = utf8.decode(payload, allowMalformed: false);
    } on FormatException {
      text = null;
    }

    if (text != null) {
      final finding = addressFormatCheck(AddressBookNetwork.zcash, text);
      if (finding == null || finding.severity != AddressFormatSeverity.error) {
        return text;
      }
    }

    // Binary ENSIP-9 P2PKH/P2SH re-encoding is out of scope for v1: there is
    // no base58check ENCODE helper in-tree, and hand-rolling one risks
    // mis-encoding funds. Anything that isn't a valid UTF-8 Zcash address
    // string is treated as having no usable record.
    throw const EnsResolutionException(
      EnsResolutionFailure.noRecord,
      'Name has no usable Zcash address record',
    );
  }

  String _normalize(String name) {
    try {
      return normalizeEnsName(name);
    } on EnsNameException catch (e) {
      throw EnsResolutionException(EnsResolutionFailure.invalidName, e.message);
    }
  }

  /// Maximum number of EIP-3668 CCIP-Read redirect hops before giving up.
  static const _maxCcipRedirectHops = 4;

  Future<List<int>> _fetchRecordPayload({
    required List<int> dnsName,
    required List<int> node,
    required BigInt coinType,
  }) async {
    final innerCall = encodeAddrCoinCall(node, coinType);
    final data = encodeUniversalResolve(dnsName, innerCall);

    final resultBytes = await _resolveWithCcipRead(
      to: universalResolver,
      data: data,
      hopsRemaining: _maxCcipRedirectHops,
    );

    final outer = decodeUniversalResolveResult(resultBytes);
    return decodeBytesResult(outer);
  }

  /// Calls [to] with [data] and, on an EIP-3668 `OffchainLookup` revert,
  /// fetches from the gateway URLs and re-calls the callback, up to
  /// [hopsRemaining] redirect hops. Returns the raw success return bytes
  /// (still `(bytes,address)`-encoded, as with the direct success path).
  Future<List<int>> _resolveWithCcipRead({
    required String to,
    required List<int> data,
    required int hopsRemaining,
  }) async {
    final String result;
    try {
      result = await _transport.ethCall(to: to, data: hexEncode(data));
    } on EnsRpcException catch (e) {
      final revertData = e.revertData;
      if (revertData == null) {
        throw const EnsResolutionException(
          EnsResolutionFailure.network,
          'Could not resolve name',
        );
      }
      if (revertData.toLowerCase().startsWith(_offchainLookupSelector)) {
        if (hopsRemaining <= 0) {
          throw const EnsResolutionException(
            EnsResolutionFailure.network,
            'Could not resolve name',
          );
        }
        final lookup = decodeOffchainLookup(hexDecode(revertData));
        if (lookup == null) {
          throw const EnsResolutionException(
            EnsResolutionFailure.network,
            'Could not resolve name',
          );
        }
        final response = await _fetchFromGateways(lookup);
        final callbackData = encodeCcipCallback(
          hexDecode(lookup.callbackSelector),
          hexDecode(response),
          hexDecode(lookup.extraData),
        );
        return _resolveWithCcipRead(
          to: lookup.sender,
          data: callbackData,
          hopsRemaining: hopsRemaining - 1,
        );
      }
      throw const EnsResolutionException(
        EnsResolutionFailure.notRegistered,
        'Name is not registered',
      );
    }

    return hexDecode(result);
  }

  /// Tries each gateway URL in order via [EnsRpcTransport.ccipFetch],
  /// returning the first successful response. Throws
  /// [EnsResolutionFailure.network] when every gateway fails.
  Future<String> _fetchFromGateways(OffchainLookupData lookup) async {
    for (final url in lookup.urls) {
      try {
        return await _transport.ccipFetch(
          url: url,
          sender: lookup.sender,
          data: lookup.callData,
        );
      } catch (_) {
        continue;
      }
    }
    throw const EnsResolutionException(
      EnsResolutionFailure.network,
      'Could not resolve name',
    );
  }
}

bool _isEmptyOrZero(List<int> bytes) =>
    bytes.isEmpty || bytes.every((b) => b == 0);
