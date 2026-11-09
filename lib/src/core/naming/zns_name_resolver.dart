/// Zcash Name Service (ZNS) forward lookup for the send flow.
///
/// A ZNS name (`alice.zcash`, or the short form `alice.zec`) resolves to a
/// unified address. The wallet never asks a resolver about one name: it
/// downloads the whole registry index with the resolver's JSON-RPC
/// `list_names` verb and looks the name up on the device, so the resolver
/// cannot learn which name, or whose address, a user is about to pay. Every
/// request goes through [NetworkHttpClient], so the download takes the Tor
/// route whenever the user turned Tor on and fails closed while Tor is
/// unavailable.
///
/// Before its first download from a host, the client checks that the host
/// serves the published registry: its `status` viewing key must match. Past
/// that, the resolver's index is trusted. The resolver publishes no
/// signature or inclusion proof for a registration, so the send flow keeps
/// the resolved address visible on review and in the verify-address step.
///
/// Expiry is the ZNS Mint's job: it releases an expired name on chain, and
/// the resolver then drops it. The ZNS wallet guide tells wallets not to
/// judge expiry themselves, so this client does not.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show log;
import '../../providers/rpc_endpoint_provider.dart';
import '../config/network_config.dart';
import '../network/network_http_client.dart';
import 'zns_names_setting.dart';

/// Mainnet resolvers in the order the ZNS SDK tries them. The second one is
/// a fallback used only when the first cannot be reached.
const kZnsMainnetResolverUrls = <String>[
  'https://main.zcashnames.com',
  'https://light.zcash.me/zns-mainnet',
];

const kZnsTestnetResolverUrls = <String>['https://light.zcash.me/zns-testnet'];

/// Registry viewing keys as the ZNS TypeScript SDK publishes them
/// (`ZNS_NETWORKS` in zcashme/zns-resolver `sdk/typescript/src/zns.ts`).
const kZnsMainnetRegistryViewingKey =
    'uview1209ld9y4fr2sel9q87kfjg7xm2sy53e3qf7dvcw3w8jwhhjpldl8z0vk0a6hve'
    'g4jk7xcn0rc9mr8yg77djfpc0uxrm5pqzt8q7ul4w0nvs3x5q9vmk9nm2crywtqaeale'
    'k4mp47ur7ywu7g4g4xcdlwv6gnqzvu5panv5je2ps6rxmx4856unlt5wde8fpz8uhrqc'
    'hmwhn2j252h3cyx5phad877xezerm6ex8l5kcfjw02ll7m0nspfufamh3ae9ea48395e'
    'lptspnv6vvc70j2gcjrdze9syt8kpr2kc67flvg8687thdkpha7lpt9r4p9wjty90q2v'
    '2yjanqsr2zrecrqs7lfx9cpkmshf7jyh2vvwfqnyzwtpuy7p72hm2mjhperdafvm9u5r'
    'wa6s6urcy0uw30f687e3jnmas45qfqtwyz39kf6kxklfrdn7t4hkz56jegmlr8s8hwmt'
    '9wa8vz8zlmm76lrmzyj82nzpeqfu572njq';

const kZnsTestnetRegistryViewingKey =
    'uviewtest1gkq78nsemsvs4qekadrv6qlqdmvcv2cct8k3c8cwycedpk90p8rtkx24qe'
    '8q73gg2ark8crqmmaavrerf7cxu0sp50an54crmeaalfxl72aetxnr89ksad4lvxzmnk'
    'yejhhwn65euzamt9wsukgfemeayhcesreasarmq600lfeju3qenh05e5e5cz6nhhsw3c'
    'fdcd3d08d0nxswxmkkxl2fq0hzv6t5dm3ftnz4y76236a49v3us4uq2tlsewf86tjtfw'
    'm6kue348me04rm7dw6uawv8myw7t5tyx2t453clhjz5f55lvh7hnvr8g8zt8lf4sy5rz'
    'q23ntp7g5ly6kyz2nkwfek06llhjtuz2fft9rg6cuuwg4n7299vajnmq6swg3sf563r0'
    'jjzuwuvfpjhmfmydar9dcu3fkuawt6u8qu08vhg5mthrcggrjuhht6f0perh0tqmdfrt'
    'gzvhjymay7h9ymvfxgd4r56uz6zrsf5gnvw5jy';

/// Suffix the wallet shows after a resolved name.
const kZnsDisplaySuffix = '.zcash';

const _znsInputSuffixes = <String>['.zcash', '.zec'];

/// The registry accepts 1-63 lowercase ASCII letters or digits.
final _znsNamePattern = RegExp(r'^[a-z0-9]{1,63}$');

/// Every call is one request on its own connection, so a fixed id suffices.
const _rpcRequestId = 1;

/// Names asked for per `list_names` page. The resolver caps a page at 500.
const kZnsIndexPageSize = 500;

/// The most names the wallet downloads. Past this the index is refused
/// rather than queried name by name, which would hand the resolver the
/// name being paid. Mainnet held 357 names in November 2026.
const kZnsMaxIndexNames = 20000;

/// A full page of 500 records is about 180 KB of JSON.
const _maxReplyBytes = 1024 * 1024;

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

/// A host that failed rather than answered: an HTTP error, a reply that is
/// not JSON-RPC (such as a proxy's error page), or a JSON-RPC error. The
/// next host is tried.
class ZnsHostUnavailableException extends ZnsLookupException {
  const ZnsHostUnavailableException(super.message);
}

abstract interface class ZnsNameResolver {
  /// Returns the registration for bare [name], or null when the name is not
  /// registered.
  ///
  /// Throws [ZnsLookupException] when no resolver answered usefully.
  Future<ZnsResolution?> resolve(String name);
}

/// Resolves names against a downloaded copy of the whole registry index.
///
/// The copy is kept for [maxAge]. A lookup on an older copy downloads the
/// index again first, so a name updated or released on chain reaches the
/// wallet within [maxAge] plus the resolver's own sync lag. Lookups that
/// arrive while a download runs share it. A failed download is not kept.
///
/// The index is always downloaded whole. The resolver's `events` verb could
/// sync it incrementally, but a reorg deletes events above the fork and can
/// reuse their ids, so an incremental copy could silently miss a change.
class ZnsIndexNameResolver implements ZnsNameResolver {
  ZnsIndexNameResolver({
    required List<Uri> endpoints,
    required this.registryViewingKey,
    NetworkHttpClient? networkClient,
    this.timeout = const Duration(seconds: 15),
    this.maxAge = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : assert(endpoints.isNotEmpty),
       _endpoints = List.unmodifiable(endpoints),
       _client = networkClient ?? NetworkHttpClient(),
       _clock = clock ?? DateTime.now;

  final List<Uri> _endpoints;
  final NetworkHttpClient _client;
  final DateTime Function() _clock;

  /// Timeout for each request.
  final Duration timeout;

  /// How long a downloaded index answers lookups.
  final Duration maxAge;

  /// The viewing key every host must report in `status`.
  final String registryViewingKey;

  /// Hosts that already proved they serve [registryViewingKey].
  final _verifiedEndpoints = <Uri>{};

  Map<String, ZnsResolution>? _index;
  DateTime? _indexFetchedAt;
  Future<Map<String, ZnsResolution>>? _download;

  @override
  Future<ZnsResolution?> resolve(String name) async {
    final index = await _currentIndex();
    return index[name];
  }

  Future<Map<String, ZnsResolution>> _currentIndex() {
    final index = _index;
    final fetchedAt = _indexFetchedAt;
    if (index != null &&
        fetchedAt != null &&
        _clock().difference(fetchedAt) < maxAge) {
      return Future.value(index);
    }
    return _download ??= _downloadIndex().whenComplete(() => _download = null);
  }

  Future<Map<String, ZnsResolution>> _downloadIndex() async {
    for (final endpoint in _endpoints) {
      try {
        await _verifyRegistry(endpoint);
        final index = await _downloadFrom(endpoint);
        _index = index;
        _indexFetchedAt = _clock();
        return index;
      } on ZnsHostUnavailableException catch (e) {
        log('ZNS: resolver ${endpoint.host} failed: ${e.message}');
        continue;
      } on ZnsLookupException {
        // The host answered: another registry, a malformed record, or an
        // index too large to download. That answer is final and is not
        // retried elsewhere.
        rethrow;
      } catch (e) {
        log('ZNS: resolver ${endpoint.host} unreachable: $e');
        continue;
      }
    }
    throw const ZnsLookupException('No ZNS resolver could be reached');
  }

  /// Downloads every page of the index from [endpoint]. A page that shows
  /// the index changed during the download restarts it, a few times.
  Future<Map<String, ZnsResolution>> _downloadFrom(Uri endpoint) async {
    const attempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        return await _downloadPages(endpoint);
      } on _ZnsIndexChangedException {
        if (attempt == attempts) {
          throw const ZnsHostUnavailableException(
            'index kept changing during the download',
          );
        }
      }
    }
  }

  Future<Map<String, ZnsResolution>> _downloadPages(Uri endpoint) async {
    final index = <String, ZnsResolution>{};
    String? lastName;
    int? total;
    var received = 0;
    while (total == null || received < total) {
      final response = await _call(endpoint, 'list_names', {
        'limit': kZnsIndexPageSize,
        'offset': received,
      });
      final page = parseZnsNamesPage(
        statusCode: response.statusCode,
        body: response.bodyBytes,
      );
      if (page.total > kZnsMaxIndexNames) {
        throw ZnsLookupException(
          'ZNS index holds ${page.total} names, more than the wallet downloads',
        );
      }
      if (total != null && page.total != total) {
        throw const _ZnsIndexChangedException();
      }
      total = page.total;
      if (page.names.isEmpty && received < total) {
        throw const _ZnsIndexChangedException();
      }
      // The resolver lists names in order. A name out of order means a
      // registration moved the pages under the download. A release that
      // moves them the other way can hide one name from this copy; that
      // name then reads as unregistered until the next download, which
      // blocks the send rather than misdirecting it.
      for (final resolution in page.names) {
        final previous = lastName;
        if (previous != null && resolution.name.compareTo(previous) <= 0) {
          throw const _ZnsIndexChangedException();
        }
        lastName = resolution.name;
        // A released record keeps its slot in the paging but is no
        // registration.
        if (resolution.address.isNotEmpty) {
          index[resolution.name] = resolution;
        }
      }
      received += page.names.length;
    }
    return Map.unmodifiable(index);
  }

  /// Checks once per host that it serves the published registry. A host that
  /// reports another viewing key could map names anywhere, so its answers
  /// are refused.
  Future<void> _verifyRegistry(Uri endpoint) async {
    if (_verifiedEndpoints.contains(endpoint)) return;
    final response = await _call(endpoint, 'status', const {});
    final viewingKey = parseZnsStatusViewingKey(
      statusCode: response.statusCode,
      body: response.bodyBytes,
    );
    if (viewingKey != registryViewingKey) {
      throw ZnsLookupException(
        'ZNS resolver ${endpoint.host} serves another registry',
      );
    }
    _verifiedEndpoints.add(endpoint);
  }

  Future<NetworkHttpResponse> _call(
    Uri endpoint,
    String method,
    Map<String, Object?> params,
  ) {
    return _client.request(
      'POST',
      endpoint,
      headers: {
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      },
      bodyBytes: utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': _rpcRequestId,
          'method': method,
          'params': params,
        }),
      ),
      timeout: timeout,
      maxBodyBytes: _maxReplyBytes,
      // A redirect could hand the download to a host nobody chose.
      maxRedirects: 0,
    );
  }
}

/// The index moved between two pages of one download.
class _ZnsIndexChangedException implements Exception {
  const _ZnsIndexChangedException();
}

/// The `result` of one JSON-RPC reply. Throws [ZnsHostUnavailableException]
/// for an HTTP failure, a reply that is not a JSON-RPC 2.0 response to this
/// request, or a JSON-RPC error.
///
/// A missing `result` is a host failure: a proxy's JSON error page must not
/// read as an empty index, which would skip the fallback host.
Object? _rpcResult(int statusCode, List<int> body) {
  if (statusCode < 200 || statusCode >= 300) {
    throw ZnsHostUnavailableException('HTTP $statusCode');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(body));
  } on FormatException {
    throw const ZnsHostUnavailableException('reply is not JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ZnsHostUnavailableException('reply is not an object');
  }
  if (decoded['jsonrpc'] != '2.0' || decoded['id'] != _rpcRequestId) {
    throw const ZnsHostUnavailableException(
      'reply is not a JSON-RPC 2.0 response to this request',
    );
  }
  final error = decoded['error'];
  if (error != null) {
    final message = error is Map ? error['message'] : null;
    throw ZnsHostUnavailableException('JSON-RPC error ${message ?? error}');
  }
  if (!decoded.containsKey('result')) {
    throw const ZnsHostUnavailableException('reply has no result');
  }
  return decoded['result'];
}

/// Reads the registry viewing key from one `status` reply.
String parseZnsStatusViewingKey({
  required int statusCode,
  required List<int> body,
}) {
  final result = _rpcResult(statusCode, body);
  final viewingKey = result is Map<String, dynamic>
      ? result['viewing_key']
      : null;
  if (viewingKey is! String || viewingKey.isEmpty) {
    throw const ZnsHostUnavailableException('status has no viewing key');
  }
  return viewingKey;
}

/// One `list_names` page: the records on it, and the [total] count of
/// names in the whole index.
///
/// A record whose last action is `release` comes back with an empty
/// address. The resolver deletes a released name, so one should never
/// arrive; the download skips it.
typedef ZnsNamesPage = ({List<ZnsResolution> names, int total});

/// Reads one `list_names` reply. Throws [ZnsHostUnavailableException] when
/// the reply is not a page, and [ZnsLookupException] when a record on it is
/// malformed: one bad record refuses the whole index, because the wallet
/// cannot tell what else the host got wrong.
ZnsNamesPage parseZnsNamesPage({
  required int statusCode,
  required List<int> body,
}) {
  final result = _rpcResult(statusCode, body);
  if (result is! Map<String, dynamic>) {
    throw const ZnsHostUnavailableException('list_names reply is not a page');
  }
  final items = result['items'];
  final total = result['total'];
  if (items is! List || total is! int || total < 0) {
    throw const ZnsHostUnavailableException('list_names reply is not a page');
  }
  final names = <ZnsResolution>[];
  for (final item in items) {
    names.add(_parseIndexRecord(item));
  }
  return (names: List.unmodifiable(names), total: total);
}

ZnsResolution _parseIndexRecord(Object? record) {
  if (record is! Map<String, dynamic>) {
    throw const ZnsLookupException('ZNS index record is not an object');
  }
  final name = record['name'];
  final address = record['address'];
  final lastAction = record['last_action'];
  if (name is! String || !_znsNamePattern.hasMatch(name)) {
    throw ZnsLookupException('ZNS index record has an invalid name $name');
  }
  if (lastAction == 'release') return ZnsResolution(name: name, address: '');
  if (lastAction != 'claim' && lastAction != 'update') {
    throw ZnsLookupException('ZNS index record has action $lastAction');
  }
  if (address is! String || address.trim().isEmpty) {
    throw const ZnsLookupException('ZNS index record has no address');
  }
  return ZnsResolution(name: name, address: address.trim());
}

/// Thrown by [kZnsNamesOffResolver]: the user has not turned names on.
class ZnsNamesOffException implements Exception {
  const ZnsNamesOffException();

  @override
  String toString() => 'ZnsNamesOffException: Zcash names are off';
}

/// The resolver while the user has names off. It makes no request.
const ZnsNameResolver kZnsNamesOffResolver = _ZnsNamesOffResolver();

class _ZnsNamesOffResolver implements ZnsNameResolver {
  const _ZnsNamesOffResolver();

  @override
  Future<ZnsResolution?> resolve(String name) =>
      Future.error(const ZnsNamesOffException());
}

/// The resolver for the wallet's network: [kZnsNamesOffResolver] while the
/// user has names off, or null where ZNS has no registry (regtest).
final znsNameResolverProvider = Provider<ZnsNameResolver?>((ref) {
  if (!ref.watch(znsNamesOnProvider)) return kZnsNamesOffResolver;
  final network = ref.watch(
    rpcEndpointProvider.select((config) => config.network),
  );
  final registry = switch (network) {
    ZcashNetwork.mainnet => (
      urls: kZnsMainnetResolverUrls,
      viewingKey: kZnsMainnetRegistryViewingKey,
    ),
    ZcashNetwork.testnet => (
      urls: kZnsTestnetResolverUrls,
      viewingKey: kZnsTestnetRegistryViewingKey,
    ),
    ZcashNetwork.regtest => null,
  };
  if (registry == null) return null;
  final client = NetworkHttpClient();
  ref.onDispose(client.close);
  return ZnsIndexNameResolver(
    endpoints: [for (final url in registry.urls) Uri.parse(url)],
    registryViewingKey: registry.viewingKey,
    networkClient: client,
  );
});
