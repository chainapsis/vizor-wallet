import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../rust/api/proxy_delegation.dart' as rust_proofs;
import '../../../rust/api/proxy_registry.dart' as rust;
import '../../../services/voting/voting_api_client.dart';
import 'proxy_delegation_repository.dart';
import 'proxy_registry_fetcher.dart';
import 'proxy_registry_proof_client.dart';
import 'proxy_registry_store.dart';
import 'proxy_service_sources.dart';
import 'proxy_wallet_list_source.dart';

/// The registry side of the delegator screens and delegate mode
/// (contracts-v1 sections 11.10, 11.11 and 12): the registry cache, Vizor's
/// signed wallet list, finding delegates and the pre-proving check.
///
/// zcash_voting makes every check behind the Rust bridge
/// (`rust/src/api/proxy_registry.rs`); this class fetches the documents and
/// proofs and keeps them in [ProxyRegistryStore]. The registry cache and the
/// list are refreshed when older than their max ages, and a failed refresh
/// keeps the stored copy. Calls run one at a time, so the stored state moves
/// forward in order.
class ProxyRegistryClient {
  /// Creates the client for [network].
  ///
  /// [chainGet] answers a `GET` under the vote servers. [firstNewIndex]
  /// reads a round's `next_delegate_index_at_creation` from the vote server,
  /// which only labels listings "new this round". [beginWork] takes the
  /// voting destructive-operation lease, or returns null while deletion
  /// holds the data. [builtInProofHost] is Vizor's own vote RPC
  /// host for [network], the proof hosts' last fallback.
  ProxyRegistryClient({
    required this.network,
    required ProxyServiceSources sources,
    required ProxyRegistryStore store,
    required ProxyRegistryFetcher fetcher,
    required ProxyRegistryProofClient proofs,
    required Future<VotingChainAnswer> Function(String path) chainGet,
    required Future<int?> Function(String roundId) firstNewIndex,
    required VoidCallback? Function() beginWork,
    this.builtInProofHost,
    List<String>? walletListUrls,
    ({String keyId, String publicKey})? regtestWalletListKey,
    DateTime Function()? clock,
    this.registryMaxAge = const Duration(minutes: 10),
    this.documentMaxAge = const Duration(hours: 1),
  }) : _sources = sources,
       _store = store,
       _fetcher = fetcher,
       _proofs = proofs,
       _chainGet = chainGet,
       _firstNewIndex = firstNewIndex,
       _beginWork = beginWork,
       _walletListUrls = walletListUrls ?? proxyWalletListUrls(network),
       _regtestWalletListKey = network == 'regtest'
           ? (regtestWalletListKey ?? proxyRegtestWalletListKey())
           : null,
       _clock = clock ?? DateTime.now;

  /// The wallet network: `main`, `test` or `regtest`.
  final String network;

  /// Vizor's vote RPC host for [network], tried after the config's
  /// `proof_rpc_urls`.
  final Uri? builtInProofHost;

  /// How long a downloaded registry cache serves before the next read
  /// downloads it again.
  final Duration registryMaxAge;

  /// How long a fetched wallet list serves before the next read fetches it
  /// again.
  final Duration documentMaxAge;

  final ProxyServiceSources _sources;
  final ProxyRegistryStore _store;
  final ProxyRegistryFetcher _fetcher;
  final ProxyRegistryProofClient _proofs;
  final Future<VotingChainAnswer> Function(String path) _chainGet;
  final Future<int?> Function(String roundId) _firstNewIndex;
  final VoidCallback? Function() _beginWork;
  final List<String> _walletListUrls;
  final ({String keyId, String publicKey})? _regtestWalletListKey;
  final DateTime Function() _clock;

  /// Most registry pages one download takes: 1,000 entries each.
  static const maxRegistryPages = 200;

  /// The tail of the call queue.
  Future<void> _queue = Future.value();

  /// When each document was last refreshed this session.
  DateTime? _registryAt;
  DateTime? _walletListAt;

  /// Whether the regtest list key reached Rust.
  bool _regtestKeyConfigured = false;

  /// Each round's first new index from the vote server, kept for the
  /// session.
  final _firstNewIndexes = <String, int?>{};

  /// Browse: Vizor's list rows, in list order.
  ///
  /// Throws [ProxyDelegationError] with
  /// [ProxyDelegationErrorKind.other] while no registry cache was ever
  /// downloaded.
  Future<ProxyDelegateBrowse> browse(String roundId) =>
      _exclusive(() async => rust.proxyBrowse(view: await _view(roundId)));

  /// Exact handle search over the registry cache's live entries.
  Future<List<ProxyDelegateListing>> search(String roundId, String query) =>
      _exclusive(
        () async =>
            rust.searchProxyDelegates(view: await _view(roundId), query: query),
      );

  /// Paste or scan: the registry cache's entry [text] names.
  Future<ApiDelegateLookup> lookup(String roundId, String text) => _exclusive(
    () async =>
        rust.lookupProxyDelegate(view: await _view(roundId), text: text),
  );

  /// The pre-proving check at confirm: each chosen entry proven in one
  /// evidence answer, one result per choice in order.
  ///
  /// Throws [ProxyDelegationError] with
  /// [ProxyDelegationErrorKind.cannotVerify] when no proof host serves
  /// evidence the participation reader verifies.
  Future<List<ApiConfirmedDelegate>> check(
    String roundId,
    List<ProxyDelegateChoice> choices,
  ) => _exclusive(() async {
    final walletList = await _walletList();
    final proven = await proveEntries(
      {for (final choice in choices) choice.delegateIndex}.toList(),
    );
    return rust.checkProxyDelegates(
      network: network,
      walletList: walletList,
      firstNewIndex: await _newFrom(roundId),
      request: ProxyAllocationRequest(roundId: roundId, choices: choices),
      proven: proven,
    );
  });

  /// Proves the registry entries of [delegateIndices] on the proof hosts
  /// with the participation reader, in order. Delegate mode proves its own
  /// entry this way.
  ///
  /// Throws [ProxyDelegationErrorKind.cannotVerify] when no proof host
  /// serves evidence the reader verifies.
  Future<List<rust_proofs.ApiProvenRegistryEntry>> proveEntries(
    List<int> delegateIndices,
  ) => _proofs.prove(
    network: network,
    proofRpcUrls: _proofHosts(),
    delegateIndices: delegateIndices,
  );

  /// The raw `vote` store value at [keyHex] from the proof hosts, unproven,
  /// or null when the key is absent. Throws [StateError] when no host
  /// answers.
  Future<Uint8List?> storeValue(String keyHex) => _proofs.storeValue(
    network: network,
    proofRpcUrls: _proofHosts(),
    keyHex: keyHex,
  );

  /// The picture Vizor's list gives entry [delegateIndex], for the
  /// delegate's own dashboard, or null.
  Future<ProxyDelegatePicture?> listPicture(int delegateIndex) =>
      _exclusive(() async {
        final list = await _walletList();
        if (list == null) return null;
        final webp = await rust.proxyWalletListPicture(
          network: network,
          walletList: list,
          delegateIndex: delegateIndex,
        );
        return webp == null ? null : ProxyDelegatePicture.of(webp);
      });

  /// The verifier API URLs the latest config load named, most preferred
  /// first; none before one.
  List<String> verifierApiUrls() =>
      _sources.of(network)?.verifierApiUrls ?? const [];

  /// The proof hosts: the config's `proof_rpc_urls`, then Vizor's own host,
  /// so a substituted URL list cannot block verification.
  List<Uri> _proofHosts() {
    final hosts = <Uri>[];
    final seen = <String>{};
    final listed = _sources.of(network)?.proofRpcUrls ?? const [];
    for (final host in [...listed.map(Uri.tryParse), builtInProofHost]) {
      if (host != null && seen.add(host.toString())) hosts.add(host);
    }
    return hosts;
  }

  /// The view a delegator finds delegates with in [roundId], refreshing the
  /// registry cache and the wallet list when stale.
  Future<rust.ApiProxyRegistryView> _view(String roundId) async =>
      rust.ApiProxyRegistryView(
        network: network,
        registryCache: await _registryCache(),
        walletList: await _walletList(),
        firstNewIndex: await _newFrom(roundId),
      );

  /// The registry cache, downloaded again when older than [registryMaxAge].
  /// A failed download keeps the stored cache; without one it throws.
  Future<String> _registryCache() async {
    final stored = await _store.readRegistryCache(network);
    if (stored != null && _fresh(_registryAt, registryMaxAge)) return stored;
    try {
      final downloaded = await _downloadRegistry();
      await _store.writeRegistryCache(network, downloaded);
      _registryAt = _clock();
      return downloaded;
    } catch (error) {
      _log('registry not downloaded', error);
      if (stored != null) return stored;
      throw const ProxyDelegationError(
        kind: ProxyDelegationErrorKind.other,
        detail: 'the delegate registry could not be downloaded',
      );
    }
  }

  /// Every registry page from the vote servers, in order, as one cache.
  Future<String> _downloadRegistry() async {
    final pages = <rust.ApiRegistryPage>[];
    int? startAfter = 0;
    while (startAfter != null) {
      if (pages.length >= maxRegistryPages) {
        throw StateError('the registry has too many pages');
      }
      final answer = await _chainGet(
        rust.proxyRegistryPagePath(startAfter: startAfter),
      );
      final next = await rust.proxyRegistryNextStartAfter(
        startAfter: startAfter,
        status: answer.statusCode,
        body: answer.body,
      );
      pages.add(
        rust.ApiRegistryPage(startAfter: startAfter, body: answer.body),
      );
      startAfter = next;
    }
    final cache = await rust.buildProxyRegistryCache(
      network: network,
      pages: pages,
    );
    return cache.json;
  }

  /// Vizor's newest verified wallet list, fetched again when older than
  /// [documentMaxAge]. A list that does not verify, or the same or a lower
  /// version, leaves the stored one and the next mirror is tried; without
  /// one, browse is empty.
  Future<Uint8List?> _walletList() async {
    final stored = await _store.readWalletList(network);
    if (_fresh(_walletListAt, documentMaxAge)) return stored;
    await _configureRegtestKey();
    var newest = stored;
    final adopted = await _fetcher.first(
      network: network,
      urls: _walletListUrls,
      role: 'wallet list', // l10n-ignore: log label
      headers: ProxyRegistryFetcher.noCache,
      accept: (body) async {
        final resolution = await rust.resolveProxyWalletList(
          network: network,
          document: body,
          stored: stored,
        );
        switch (resolution.update) {
          case rust.ApiWalletListUpdate.adopted:
            return body;
          case rust.ApiWalletListUpdate.unchanged:
          case rust.ApiWalletListUpdate.older:
            return null;
          case rust.ApiWalletListUpdate.conflictingPayload:
          case rust.ApiWalletListUpdate.rejected:
            debugPrint(
              '[zcash] Proxy registry: wallet list kept '
              '(${resolution.update.name}'
              '${resolution.detail == null ? '' : ': ${resolution.detail}'})',
            );
            throw StateError('wallet list ${resolution.update.name}');
        }
      },
    );
    if (adopted != null) {
      await _store.writeWalletList(network, adopted);
      newest = adopted;
    }
    _walletListAt = _clock();
    return newest;
  }

  /// Hands the regtest harness's list key to Rust once.
  Future<void> _configureRegtestKey() async {
    final key = _regtestWalletListKey;
    if (key == null || _regtestKeyConfigured) return;
    try {
      await rust.configureRegtestWalletListKey(
        keyId: key.keyId,
        publicKey: key.publicKey,
      );
      _regtestKeyConfigured = true;
    } catch (error) {
      _log('regtest wallet list key refused', error);
    }
  }

  /// The round's first new index from the vote server, read once per
  /// session.
  Future<int?> _newFrom(String roundId) async =>
      _firstNewIndexes.containsKey(roundId)
      ? _firstNewIndexes[roundId]
      : _firstNewIndexes[roundId] = await _firstNewIndex(roundId);

  /// Whether a refresh at [at] still serves for [maxAge].
  bool _fresh(DateTime? at, Duration maxAge) =>
      at != null && _clock().difference(at) < maxAge;

  /// Runs [call] after every call queued before it, holding the voting
  /// destructive-operation lease throughout, so no write lands after
  /// deletion. Refused while deletion holds the voting data.
  Future<T> _exclusive<T>(Future<T> Function() call) {
    final result = _queue.then((_) async {
      final release = _beginWork();
      if (release == null) {
        throw const ProxyDelegationError(
          kind: ProxyDelegationErrorKind.other,
          detail: 'voting data is being deleted',
        );
      }
      try {
        return await call();
      } finally {
        release();
      }
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Logs a passed-over registry step.
  static void _log(String what, Object error) => debugPrint(
    '[zcash] Proxy registry: $what: ${describeProxyRegistryError(error)}',
  );
}

/// The round's `proxy_delegation.next_delegate_index_at_creation` from the
/// chain's round JSON, or null when the round carries none. It only marks
/// listings "new this round", so it is read unverified.
int? proxyNextDelegateIndexAtCreation(Map<String, dynamic> roundJson) {
  final state = _proxyState(roundJson);
  final index = state?['next_delegate_index_at_creation'];
  return switch (index) {
    final int value when value > 0 => value,
    final String text => int.tryParse(text),
    _ => null,
  };
}

/// Whether the chain's round JSON says the round offers proxy delegation;
/// availability decides for real.
bool proxyRoundEnabled(Map<String, dynamic> roundJson) =>
    _proxyState(roundJson)?['enabled'] == true;

/// The round JSON's `proxy_delegation` object, at the top level or under
/// `round`.
Map<dynamic, dynamic>? _proxyState(Map<String, dynamic> roundJson) {
  final direct = roundJson['proxy_delegation'];
  if (direct is Map) return direct;
  final round = roundJson['round'];
  if (round is Map && round['proxy_delegation'] is Map) {
    return round['proxy_delegation'] as Map;
  }
  return null;
}
