import 'dart:convert';
import 'dart:typed_data';

import '../../../rust/api/proxy_delegation.dart' as rust;
import '../../../services/voting/voting_http.dart';
import '../../../services/voting/voting_participation_client.dart';
import '../../../services/voting/voting_retry.dart';
import 'proxy_delegation_repository.dart';
import 'proxy_registry_fetcher.dart';

/// Requests proofs of delegate registry entries (contracts-v1 section
/// 11.6) from the `proof_rpc_urls` and verifies them in Rust.
///
/// Hosts are tried in order. A transport error, a transient answer that
/// outlasts one retry, invalid evidence or any other failure moves on to the
/// next host. When none is left or [deadline] passes, every cause becomes
/// one [ProxyDelegationError] with [ProxyDelegationErrorKind.cannotVerify].
/// The requests name the chosen delegates, so no error carries a key, URL or
/// body.
class ProxyRegistryProofClient {
  /// Creates the client.
  ProxyRegistryProofClient(
    this.http, {
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  /// Route-aware HTTP.
  final VotingHttpClient http;

  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  /// Longest wait for one request.
  static const requestTimeout = Duration(seconds: 10);

  /// Longest one [prove] call spends across every host.
  static const deadline = Duration(minutes: 2);

  /// Largest response accepted from a proof host: the participation
  /// reader's 8 MiB evidence cap (contracts-v1 section 15.1). The transport
  /// stops reading past it.
  static const maxResponseBytes = 8 * 1024 * 1024;

  /// Proves the registry entries of [delegateIndices] on [network] in one
  /// evidence answer from the first of [proofRpcUrls] that serves valid
  /// evidence, returning each entry's bytes or its proven absence, in
  /// order.
  Future<List<rust.ApiProvenRegistryEntry>> prove({
    required String network,
    required List<Uri> proofRpcUrls,
    required List<int> delegateIndices,
  }) async {
    if (delegateIndices.isEmpty) return const [];
    final List<String> keys;
    try {
      keys = await rust.proxyRegistryEntryKeys(
        delegateIndices: delegateIndices,
      );
    } catch (_) {
      throw _cannotVerify;
    }
    final end = _clock().add(deadline);
    for (final host in proofRpcUrls) {
      if (!_clock().isBefore(end)) break;
      if (!proxyRegistryHostAllowed(network, host)) continue;
      try {
        final evidence = await _evidence(host, keys, end);
        final entries = await rust.verifyProxyRegistryEntries(
          network: network,
          delegateIndices: delegateIndices,
          evidence: jsonEncode(evidence),
          nowSeconds: _clock().millisecondsSinceEpoch ~/ 1000,
        );
        if (entries.length != delegateIndices.length ||
            Iterable.generate(
              entries.length,
            ).any((i) => entries[i].delegateIndex != delegateIndices[i])) {
          throw StateError('Proven entries out of order');
        }
        return entries;
      } catch (_) {
        // The next host may answer.
      }
    }
    throw _cannotVerify;
  }

  /// The raw value at the `vote` store key [keyHex] from the first of
  /// [proofRpcUrls] that answers, or null when the key is absent.
  ///
  /// The query is not proven: it serves values the contract leaves
  /// unproven, such as a delegate's pool share count (contracts section 8).
  /// Hosts are tried as for [prove]. Throws [StateError] when none answers.
  Future<Uint8List?> storeValue({
    required String network,
    required List<Uri> proofRpcUrls,
    required String keyHex,
  }) async {
    final end = _clock().add(deadline);
    for (final host in proofRpcUrls) {
      if (!_clock().isBefore(end)) break;
      if (!proxyRegistryHostAllowed(network, host)) continue;
      try {
        final answer = await _get(host, '/abci_query', {
          'path': '"/store/vote/key"',
          'data': '0x$keyHex',
        }, end);
        final response =
            (answer['result'] as Map)['response'] as Map<String, dynamic>;
        final code = response['code'];
        if (code != null && code != 0) {
          throw StateError('Store query refused');
        }
        final value = response['value'];
        if (value == null || value == '') return null;
        return base64Decode(value as String);
      } catch (_) {
        // The next host may answer.
      }
    }
    throw StateError('No proof host answered the store query');
  }

  static const _cannotVerify = ProxyDelegationError(
    kind: ProxyDelegationErrorKind.cannotVerify,
  );

  /// [host]'s evidence for [keys] ([fetchVoteStoreEvidence]); any failed
  /// read fails it.
  Future<Map<String, Object>> _evidence(
    Uri host,
    List<String> keys,
    DateTime end,
  ) async {
    final evidence = await fetchVoteStoreEvidence(
      keys,
      get: (path, [query]) => _get(host, path, query, end),
    );
    return {
      'commit': evidence.commit,
      'validators': evidence.validators,
      'queries': evidence.queries,
    };
  }

  /// GETs [path] under [host], retrying one transient failure, before [end].
  Future<Map<String, dynamic>> _get(
    Uri host,
    String path,
    Map<String, String>? query,
    DateTime end,
  ) => withVotingRetry(
    policy: VotingRetryPolicy(
      name: 'proxy-registry-proof',
      delays: const [Duration(milliseconds: 300)],
      shouldRetry: (error) =>
          error is _TransientProofResponse || isRetryableVotingError(error),
    ),
    delay: _delay,
    isCancelled: () => !_clock().isBefore(end),
    operation: () async {
      final remaining = end.difference(_clock());
      if (remaining <= Duration.zero) {
        throw StateError('Registry proof deadline exceeded');
      }
      final base = host.path.endsWith('/')
          ? host.path.substring(0, host.path.length - 1)
          : host.path;
      final response = await http.get(
        host.replace(path: '$base$path', queryParameters: query),
        timeout: remaining < requestTimeout ? remaining : requestTimeout,
        maxBodyBytes: maxResponseBytes,
      );
      if (const [429, 500, 502, 503, 504].contains(response.statusCode)) {
        throw const _TransientProofResponse();
      }
      if (response.statusCode != 200 ||
          response.bodyBytes.length > maxResponseBytes) {
        throw StateError('Registry proof response unavailable');
      }
      return response.decodeJsonObject();
    },
  );
}

/// A transient answer from a proof host; carries nothing it was asked.
class _TransientProofResponse implements Exception {
  const _TransientProofResponse();
}
