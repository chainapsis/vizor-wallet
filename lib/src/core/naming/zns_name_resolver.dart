/// Zcash Name Service (ZNS) forward lookup for the send flow.
///
/// A ZNS name (`alice.zcash`, or the short form `alice.zec`) resolves to a
/// unified address through the ZNS resolver's JSON-RPC `resolve` verb. Every
/// request goes through [NetworkHttpClient], so a lookup takes the Tor route
/// whenever the user turned Tor on and fails closed while Tor is unavailable.
///
/// The resolver's answer is trusted as is. The current resolver publishes no
/// signature or inclusion proof for a registration, so the send flow keeps
/// the resolved address visible on review and in the verify-address step.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show log;
import '../../providers/rpc_endpoint_provider.dart';
import '../config/network_config.dart';
import '../network/network_http_client.dart';

/// Mainnet resolvers in the order the ZNS SDK tries them. The second one is
/// a fallback used only when the first cannot be reached.
const kZnsMainnetResolverUrls = <String>[
  'https://main.zcashnames.com',
  'https://light.zcash.me/zns-mainnet',
];

const kZnsTestnetResolverUrls = <String>['https://light.zcash.me/zns-testnet'];

/// Suffix the wallet shows after a resolved name.
const kZnsDisplaySuffix = '.zcash';

const _znsInputSuffixes = <String>['.zcash', '.zec'];

/// The registry accepts 1-63 lowercase ASCII letters or digits.
final _znsNamePattern = RegExp(r'^[a-z0-9]{1,63}$');

/// A `resolve` reply holds one small JSON record.
const _maxResolveResponseBytes = 64 * 1024;

/// Returns the bare registry name for recipient [input] (`Alice.ZEC` gives
/// `alice`), or null when the input is not a ZNS name.
///
/// Only input that ends in `.zcash` or `.zec` counts. A bare word is never
/// looked up, so partially typed addresses and contact searches stay local.
String? znsNameFromRecipientInput(String input) {
  final lower = input.trim().toLowerCase();
  for (final suffix in _znsInputSuffixes) {
    if (!lower.endsWith(suffix)) continue;
    final name = lower.substring(0, lower.length - suffix.length);
    return _znsNamePattern.hasMatch(name) ? name : null;
  }
  return null;
}

/// A live registration: the bare [name] and the [address] it points to.
class ZnsResolution {
  const ZnsResolution({required this.name, required this.address});

  final String name;
  final String address;

  /// [name] with the canonical `.zcash` suffix, for display.
  String get displayName => '$name$kZnsDisplaySuffix';

  @override
  bool operator ==(Object other) =>
      other is ZnsResolution && other.name == name && other.address == address;

  @override
  int get hashCode => Object.hash(name, address);
}

/// A lookup that produced no answer: no resolver could be reached, or the
/// reply could not be read. A missing registration is not an error.
class ZnsLookupException implements Exception {
  const ZnsLookupException(this.message);

  final String message;

  @override
  String toString() => 'ZnsLookupException: $message';
}

abstract interface class ZnsNameResolver {
  /// Returns the live registration for bare [name], or null when the name is
  /// not registered, was released, or has expired.
  ///
  /// Throws [ZnsLookupException] when no resolver answered usefully.
  Future<ZnsResolution?> resolve(String name);
}

class ZnsJsonRpcNameResolver implements ZnsNameResolver {
  ZnsJsonRpcNameResolver({
    required List<Uri> endpoints,
    NetworkHttpClient? networkClient,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : assert(endpoints.isNotEmpty),
       _endpoints = List.unmodifiable(endpoints),
       _client = networkClient ?? NetworkHttpClient(),
       _now = now ?? DateTime.now;

  final List<Uri> _endpoints;
  final NetworkHttpClient _client;
  final DateTime Function() _now;
  final Duration timeout;

  @override
  Future<ZnsResolution?> resolve(String name) async {
    final body = utf8.encode(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'resolve',
        'params': {'query': name},
      }),
    );
    for (final endpoint in _endpoints) {
      final NetworkHttpResponse response;
      try {
        response = await _client.request(
          'POST',
          endpoint,
          headers: {
            HttpHeaders.acceptHeader: 'application/json',
            HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
          },
          bodyBytes: body,
          timeout: timeout,
          maxBodyBytes: _maxResolveResponseBytes,
          // A redirect could hand the lookup to a host nobody chose.
          maxRedirects: 0,
        );
      } catch (e) {
        // Unreachable: try the next resolver. A resolver that answered is
        // final, so an HTTP or JSON-RPC error below is never retried.
        log('ZNS: resolver ${endpoint.host} unreachable: $e');
        continue;
      }
      return parseZnsResolveResponse(
        statusCode: response.statusCode,
        body: response.bodyBytes,
        requestedName: name,
        now: _now(),
      );
    }
    throw const ZnsLookupException('No ZNS resolver could be reached');
  }
}

/// Reads one `resolve` reply for [requestedName].
///
/// Returns null for no registration, a `release` record, or an `expires_at`
/// at or before [now]. Throws [ZnsLookupException] for any reply that is not
/// a well-formed record for the requested name.
ZnsResolution? parseZnsResolveResponse({
  required int statusCode,
  required List<int> body,
  required String requestedName,
  required DateTime now,
}) {
  if (statusCode < 200 || statusCode >= 300) {
    throw ZnsLookupException('ZNS resolver returned HTTP $statusCode');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(body));
  } on FormatException {
    throw const ZnsLookupException('ZNS resolver reply is not JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ZnsLookupException('ZNS resolver reply is not an object');
  }
  final error = decoded['error'];
  if (error != null) {
    final message = error is Map ? error['message'] : null;
    throw ZnsLookupException('ZNS resolver error: ${message ?? error}');
  }
  final result = decoded['result'];
  if (result == null) return null;
  if (result is! Map<String, dynamic>) {
    throw const ZnsLookupException('ZNS resolver record is not an object');
  }

  final name = result['name'];
  final address = result['address'];
  final lastAction = result['last_action'];
  final expiresAt = result['expires_at'];
  if (name != requestedName) {
    throw const ZnsLookupException('ZNS resolver answered for another name');
  }
  if (address is! String || address.trim().isEmpty) {
    throw const ZnsLookupException('ZNS resolver record has no address');
  }
  if (lastAction == 'release') return null;
  if (lastAction != 'claim' && lastAction != 'update') {
    throw ZnsLookupException('ZNS resolver record has action $lastAction');
  }
  if (expiresAt is! String) {
    throw const ZnsLookupException('ZNS resolver record has no expiry');
  }
  if (expiresAt != 'none') {
    final expiresAtSeconds = int.tryParse(expiresAt);
    if (expiresAtSeconds == null) {
      throw ZnsLookupException('ZNS resolver expiry $expiresAt is unreadable');
    }
    if (expiresAtSeconds * 1000 <= now.millisecondsSinceEpoch) return null;
  }
  return ZnsResolution(name: name as String, address: address.trim());
}

/// The resolver for the wallet's network, or null where ZNS has no registry
/// (regtest).
final znsNameResolverProvider = Provider<ZnsNameResolver?>((ref) {
  final network = ref.watch(
    rpcEndpointProvider.select((config) => config.network),
  );
  final urls = switch (network) {
    ZcashNetwork.mainnet => kZnsMainnetResolverUrls,
    ZcashNetwork.testnet => kZnsTestnetResolverUrls,
    ZcashNetwork.regtest => null,
  };
  if (urls == null) return null;
  final client = NetworkHttpClient();
  ref.onDispose(client.close);
  return ZnsJsonRpcNameResolver(
    endpoints: [for (final url in urls) Uri.parse(url)],
    networkClient: client,
  );
});
