import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegation.dart' as rust_proofs;
import 'package:zcash_wallet/src/rust/api/proxy_registry.dart' as rust;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';

/// A round id in canonical form.
const kRegistryTestRoundId =
    '0101010101010101010101010101010101010101010101010101010101010101';

/// A dynamic config document with the proxy extension's URL lists, or no
/// extension when [proxy] is false. v1's members ride along unread.
Uint8List fakeDynamicConfig({
  bool proxy = true,
  List<String> proofRpcUrls = const ['https://rpc-a.example'],
  List<String> verifierApiUrls = const [],
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'config_version': 1,
      if (proxy)
        'extensions': {
          'proxy_delegation_v1': {
            'rounds': {'ignored': true},
            'verifier_api_urls': verifierApiUrls,
            'proof_rpc_urls': proofRpcUrls,
          },
        },
    }),
  ),
);

/// A load that fetched [documents].
VotingDynamicConfigFetch fakeConfigFetch(List<Uint8List> documents) =>
    VotingDynamicConfigFetch(documents: documents);

/// A fake registry page listing [indices], continuing after [next] (0 on
/// the last page).
Uint8List fakeRegistryPage(List<int> indices, {int next = 0}) =>
    Uint8List.fromList(
      utf8.encode(jsonEncode({'delegates': indices, 'next': next})),
    );

/// A fake wallet list of [version] naming [rows] by index, signed by the
/// pinned key unless [signed] is false.
Uint8List fakeWalletList(
  int version, {
  List<int> rows = const [],
  bool signed = true,
}) => Uint8List.fromList(
  utf8.encode(jsonEncode({'version': version, 'rows': rows, 'signed': signed})),
);

/// One registered delegate the fake registry describes.
class FakeListing {
  /// Creates the delegate.
  FakeListing(
    this.index,
    this.handle, {
    this.name,
    this.picture,
    this.status = rust_wire.DelegateEntryStatus.active,
  });

  /// The registry index; even indices are on GitHub, odd ones on X.
  final int index;

  /// The entry's handle.
  final String handle;

  /// The wallet list's name.
  final String? name;

  /// The wallet list's picture.
  final List<int>? picture;

  /// Whether the entry is active, suspended or retired.
  final rust_wire.DelegateEntryStatus status;

  /// The entry's key.
  String get dk => 'zvdk1fake$index';

  /// Its fingerprint.
  String get fingerprint => 'fp$index-aaaa-bbbb-cccc';

  /// The entry's provider.
  rust_wire.ProxyDelegateProvider get provider => index.isEven
      ? rust_wire.ProxyDelegateProvider.gitHub
      : rust_wire.ProxyDelegateProvider.x;

  /// The listing as the bridge returns it, with the wallet list's content
  /// when [inList], and new this round from [firstNewIndex] on.
  rust_wire.ProxyDelegateListing toApi({
    bool inList = false,
    int? firstNewIndex,
  }) {
    final picture = this.picture;
    return rust_wire.ProxyDelegateListing(
      index: index,
      provider: provider,
      handle: handle,
      key: rust_wire.DelegateKeyInfo(dk: dk, fingerprint: fingerprint),
      reviewed: inList && status == rust_wire.DelegateEntryStatus.active,
      displayName: inList ? name : null,
      statement: null,
      picture: inList && picture != null ? Uint8List.fromList(picture) : null,
      newThisRound: firstNewIndex != null && index >= firstNewIndex,
      status: status,
    );
  }
}

/// Stands in for zcash_voting's registry client, which Dart tests cannot
/// load. It reads the fake documents above and applies the registry's rules
/// in miniature: pages chain by their last index, only a signed list of a
/// higher version is adopted, search and paste read the cache, and a check
/// needs each chosen entry proven with the choice's key, provider and
/// handle. The Dart plumbing around the bridge is what these fakes test; the
/// rules themselves are tested in Rust.
class FakeProxyRegistryRust {
  /// The delegates the fake registry describes, by index.
  final listings = <int, FakeListing>{};

  /// The requests of every check that ran, with their proofs.
  final checked =
      <
        ({
          rust_wire.ProxyAllocationRequest request,
          List<rust_proofs.ApiProvenRegistryEntry> proven,
          int? firstNewIndex,
        })
      >[];

  /// Every regtest list key configured.
  final regtestKeys = <String>[];

  /// The chain each network's documents name.
  static const chains = {'main': 'zvote-1', 'test': 'svote-1'};

  Future<rust.ApiProxyServiceUrls?> serviceUrls(List<int> document) async {
    final extension =
        ((jsonDecode(utf8.decode(document)) as Map)['extensions']
            as Map?)?['proxy_delegation_v1'];
    if (extension == null) return null;
    return rust.ApiProxyServiceUrls(
      verifierApiUrls: List<String>.from(extension['verifier_api_urls']),
      proofRpcUrls: List<String>.from(extension['proof_rpc_urls']),
    );
  }

  String registryPagePath(int startAfter) =>
      '/shielded-vote/v1/delegates?start_after=$startAfter&limit=1000';

  Future<int?> registryNextStartAfter({
    required int startAfter,
    required int status,
    required List<int> body,
  }) async {
    if (status != 200) throw _invalid('status $status');
    final next = (jsonDecode(utf8.decode(body)) as Map)['next'] as int;
    return next == 0 ? null : next;
  }

  Future<rust.ApiProxyRegistryCache> buildRegistryCache({
    required String network,
    required List<rust.ApiRegistryPage> pages,
  }) async {
    final indices = [
      for (final page in pages)
        ...((jsonDecode(utf8.decode(page.body)) as Map)['delegates'] as List)
            .cast<int>(),
    ];
    return rust.ApiProxyRegistryCache(
      json: jsonEncode({'chain': chains[network], 'entries': indices}),
      entries: indices.length,
    );
  }

  Future<void> configureRegtestWalletListKey({
    required String keyId,
    required String publicKey,
  }) async => regtestKeys.add('$keyId:$publicKey');

  Future<rust.ApiWalletListResolution> resolveWalletList({
    required String network,
    required List<int> document,
    Uint8List? stored,
  }) async {
    final storedVersion = _listVersion(stored);
    final json = _json(document);
    if (json == null || json['signed'] != true) {
      return rust.ApiWalletListResolution(
        update: rust.ApiWalletListUpdate.rejected,
        detail: 'NoPinnedSignature',
        version: _big(storedVersion),
      );
    }
    final version = json['version'] as int;
    if (storedVersion == null || version > storedVersion) {
      return rust.ApiWalletListResolution(
        update: rust.ApiWalletListUpdate.adopted,
        version: BigInt.from(version),
      );
    }
    return rust.ApiWalletListResolution(
      update: version == storedVersion
          ? rust.ApiWalletListUpdate.unchanged
          : rust.ApiWalletListUpdate.older,
      version: BigInt.from(storedVersion),
    );
  }

  Future<Uint8List?> walletListPicture({
    required String network,
    required List<int> walletList,
    required int delegateIndex,
  }) async {
    if (!_rows(walletList).contains(delegateIndex)) return null;
    final picture = listings[delegateIndex]?.picture;
    return picture == null ? null : Uint8List.fromList(picture);
  }

  Future<rust_wire.ProxyDelegateBrowse> browse(
    rust.ApiProxyRegistryView view,
  ) async {
    final cached = _cached(view);
    final list = view.walletList;
    if (list == null) {
      return const rust_wire.ProxyDelegateBrowse(
        listed: [],
        listUnavailable: true,
      );
    }
    return rust_wire.ProxyDelegateBrowse(
      listed: [
        for (final index in _rows(list))
          if (cached.contains(index))
            ?listings[index]?.toApi(
              inList: true,
              firstNewIndex: view.firstNewIndex,
            ),
      ],
      listUnavailable: false,
    );
  }

  /// The cached live entries whose handle is [query], trimmed, without one
  /// leading `@` and lowercased.
  Future<List<rust_wire.ProxyDelegateListing>> search(
    rust.ApiProxyRegistryView view,
    String query,
  ) async {
    var needle = query.trim().toLowerCase();
    if (needle.startsWith('@')) needle = needle.substring(1);
    return [
      for (final listing in _found(view))
        if (listing.handle == needle &&
            listing.status != rust_wire.DelegateEntryStatus.retired)
          _listed(view, listing),
    ];
  }

  /// Finds `#d` and `d` in the cache, and a cached key by [FakeListing.dk]
  /// or fingerprint.
  Future<rust.ApiDelegateLookup> lookup(
    rust.ApiProxyRegistryView view,
    String text,
  ) async {
    final trimmed = text.trim();
    final digits = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    final index = int.tryParse(digits);
    final recognized =
        index != null ||
        trimmed.startsWith('zvdk1') ||
        trimmed.startsWith('fp');
    if (!recognized) {
      return const rust.ApiDelegateLookup(
        kind: rust.ApiDelegateLookupKind.unrecognized,
      );
    }
    for (final listing in _found(view)) {
      if (listing.index == index ||
          listing.dk == trimmed ||
          listing.fingerprint == trimmed) {
        return rust.ApiDelegateLookup(
          kind: rust.ApiDelegateLookupKind.found,
          listing: _listed(view, listing),
        );
      }
    }
    return const rust.ApiDelegateLookup(
      kind: rust.ApiDelegateLookupKind.notFound,
    );
  }

  /// One verdict per choice, in zcash_voting's order: an entry without a
  /// proof cannot be verified, one proven absent is not found, then the
  /// proven entry must be the choice's and active.
  Future<List<rust.ApiConfirmedDelegate>> checkDelegates({
    required String network,
    Uint8List? walletList,
    int? firstNewIndex,
    required rust_wire.ProxyAllocationRequest request,
    required List<rust_proofs.ApiProvenRegistryEntry> proven,
  }) async {
    checked.add((
      request: request,
      proven: proven,
      firstNewIndex: firstNewIndex,
    ));
    final rows = _rows(walletList);
    return [
      for (final choice in request.choices)
        () {
          final proof = proven
              .where((entry) => entry.delegateIndex == choice.delegateIndex)
              .firstOrNull;
          if (proof == null) {
            return const rust.ApiConfirmedDelegate(
              check: rust_wire.DelegateCheck.cannotVerify,
            );
          }
          final listing = listings[choice.delegateIndex];
          if (proof.entry == null || listing == null) {
            return const rust.ApiConfirmedDelegate(
              check: rust_wire.DelegateCheck.notFound,
            );
          }
          final picked =
              listing.dk == choice.dk &&
              listing.provider == choice.provider &&
              listing.handle == choice.handle;
          return rust.ApiConfirmedDelegate(
            check: !picked
                ? rust_wire.DelegateCheck.mismatch
                : switch (listing.status) {
                    rust_wire.DelegateEntryStatus.active =>
                      rust_wire.DelegateCheck.ok,
                    rust_wire.DelegateEntryStatus.suspended =>
                      rust_wire.DelegateCheck.suspended,
                    rust_wire.DelegateEntryStatus.retired =>
                      rust_wire.DelegateCheck.retired,
                  },
            listing: listing.toApi(
              inList: rows.contains(choice.delegateIndex),
              firstNewIndex: firstNewIndex,
            ),
          );
        }(),
    ];
  }

  /// The delegates [view]'s cache holds.
  Iterable<FakeListing> _found(rust.ApiProxyRegistryView view) {
    final cached = _cached(view);
    return listings.values.where((listing) => cached.contains(listing.index));
  }

  /// [listing] as [view] shows it.
  rust_wire.ProxyDelegateListing _listed(
    rust.ApiProxyRegistryView view,
    FakeListing listing,
  ) => listing.toApi(
    inList: _rows(view.walletList).contains(listing.index),
    firstNewIndex: view.firstNewIndex,
  );

  /// The indices [view]'s cache holds, refusing another chain's cache.
  List<int> _cached(rust.ApiProxyRegistryView view) {
    final json = jsonDecode(view.registryCache) as Map;
    if (json['chain'] != chains[view.network]) {
      throw _invalid('the stored registry cache is another chain\'s');
    }
    return (json['entries'] as List).cast<int>();
  }

  /// The rows of a stored fake list.
  static List<int> _rows(List<int>? list) =>
      ((_json(list)?['rows'] as List?) ?? const []).cast<int>();

  /// The version of a stored fake list.
  static int? _listVersion(List<int>? list) => _json(list)?['version'] as int?;

  /// [bytes] as a JSON object, or null.
  static Map? _json(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// [value] as a bridge integer.
  static BigInt? _big(int? value) => value == null ? null : BigInt.from(value);

  /// An invalid-input error, as zcash_voting reports one.
  static rust.ApiProxyRegistryError _invalid(String message) =>
      rust.ApiProxyRegistryError(message: message);
}
