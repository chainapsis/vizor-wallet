import 'dart:convert';

import '../../rust/api/voting.dart' as rust;
import 'voting_http.dart';
import 'voting_file_cache.dart';
import 'voting_retry.dart';

/// Consensus/storage verification is performed in Rust. Never log candidate
/// keys, request URLs, evidence, or raw transport exceptions from this client.
class VotingParticipationBridge {
  const VotingParticipationBridge();
  Future<String> prepare(rust.ApiVotingRoundContext context) =>
      rust.prepareVotingParticipation(ctx: context);
  Future<String> evaluate(
    rust.ApiVotingRoundContext context,
    String fingerprint,
    String evidence,
    DateTime now,
  ) => rust.evaluateVotingParticipation(
    ctx: context,
    fingerprint: fingerprint,
    evidence: evidence,
    nowSeconds: now.millisecondsSinceEpoch ~/ 1000,
  );
}

class VotingParticipationResult {
  const VotingParticipationResult({
    required this.fingerprint,
    required this.usedCount,
    required this.noteCount,
    required this.remainingEligible,
    required this.localState,
    this.complete = true,
    this.snapshotRevision = '0',
    this.observations = const {},
  });
  final String fingerprint;
  final int usedCount;
  final int noteCount;
  final bool remainingEligible;
  final bool localState;
  final bool complete;
  final String snapshotRevision;
  final Map<String, dynamic> observations;
  bool get unavailable =>
      complete && usedCount > 0 && !remainingEligible && !localState;
  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'usedCount': usedCount,
    'noteCount': noteCount,
    'remainingEligible': remainingEligible,
    'localState': localState,
    'complete': complete,
    'snapshotRevision': snapshotRevision,
  };
  factory VotingParticipationResult.fromJson(Map<String, dynamic> j) =>
      VotingParticipationResult(
        fingerprint: j['fingerprint'] as String,
        usedCount: j['usedCount'] as int,
        noteCount: j['noteCount'] as int,
        remainingEligible: j['remainingEligible'] as bool,
        localState: j['localState'] as bool,
        complete: j['complete'] as bool? ?? true,
        snapshotRevision: j['snapshotRevision'] as String? ?? '0',
        observations: Map<String, dynamic>.from(
          j['observations'] as Map? ?? {},
        ),
      );
}

/// Largest answer the participation reader takes from a vote chain RPC
/// host: its own 8 MiB evidence cap (contracts-v1 section 15.1), which a
/// header and validators from a chain with many validators can approach.
const kVotingParticipationMaxResponseBytes = 8 * 1024 * 1024;

/// The vote chain RPC host Vizor ships for [network]: the participation
/// check reads it, and proxy registry proofs fall back to it. Null on
/// regtest, whose harness supplies its own.
Uri? builtInVotingRpcEndpoint(String network) => switch (network) {
  'main' => Uri.parse('https://vote-rpc-primary.valargroup.org'),
  'test' => Uri.parse('https://stage.vote-rpc-primary.valargroup.org'),
  _ => null,
};

/// GETs one vote chain RPC [path] with an optional [query], as one caller
/// routes and retries it.
typedef VoteRpcGet =
    Future<Map<String, dynamic>> Function(
      String path, [
      Map<String, String>? query,
    ]);

/// What the participation reader verifies for vote store keys: a signed
/// header at the host's tip, its validators, and a proven `abci_query` per
/// key at the height that header commits, in key order, read four at a time.
///
/// With [skipFailedQueries], a key whose read fails is left out of [keys]
/// and its query dropped; otherwise the first failure throws.
/// [continueGroups], if given, runs before each group of four and stops the
/// reads once it returns false.
Future<
  ({
    Map<String, dynamic> commit,
    Map<String, dynamic> validators,
    List<String> keys,
    List<Map<String, dynamic>> queries,
  })
>
fetchVoteStoreEvidence(
  List<String> keys, {
  required VoteRpcGet get,
  bool skipFailedQueries = false,
  bool Function()? continueGroups,
}) async {
  final commit = await get('/commit');
  final header =
      ((commit['result'] as Map)['signed_header'] as Map)['header'] as Map;
  final height = int.parse(header['height'] as String);
  if (height <= 1) throw StateError('Voting chain is not ready');
  final validators = await get('/validators', {
    'height': '$height',
    'per_page': '100',
  });
  Future<Map<String, dynamic>> read(String key) => get('/abci_query', {
    'path': '"/store/vote/key"',
    'data': '0x$key',
    'height': '${height - 1}',
    'prove': 'true',
  });
  final queries = <Map<String, dynamic>>[];
  final queryKeys = <String>[];
  for (var start = 0; start < keys.length; start += 4) {
    if (continueGroups?.call() == false) break;
    final group = keys.skip(start).take(4).toList();
    final results = await Future.wait(
      group.map((key) async {
        if (!skipFailedQueries) return read(key);
        try {
          return await read(key);
        } catch (_) {
          return null;
        }
      }),
    );
    for (var i = 0; i < group.length; i++) {
      if (results[i] case final result?) {
        queryKeys.add(group[i]);
        queries.add(result);
      }
    }
  }
  return (
    commit: commit,
    validators: validators,
    keys: queryKeys,
    queries: queries,
  );
}

class VotingParticipationClient {
  VotingParticipationClient(
    this.http,
    this.bridge, {
    this.regtestEndpoint,
    this.cache,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;
  final Future<void> Function(Duration) _delay;
  final VotingFileCache? cache;
  final Map<String, Map<String, dynamic>> _memory = {};

  /// Local integration transport; ignored for mainnet and testnet.
  final Uri? regtestEndpoint;
  final VotingHttpClient http;
  final VotingParticipationBridge bridge;
  static const requestTimeout = Duration(seconds: 10);

  String scopeFor(rust.ApiVotingRoundContext context) => jsonEncode([
    context.network,
    context.roundParams.voteRoundId,
    context.roundParams.snapshotHeight.toString(),
    'governance-v1',
  ]);

  /// Called only after the existing durable delegation confirmation. No RPC.
  Future<void> refreshLocal(
    rust.ApiVotingRoundContext context, {
    bool Function()? isCurrent,
  }) async {
    void guard() {
      if (isCurrent?.call() == false) {
        throw StateError('Voting local reconciliation cancelled');
      }
    }

    guard();
    final candidates =
        jsonDecode(await bridge.prepare(context)) as Map<String, dynamic>;
    guard();
    final scope = scopeFor(context);
    final memoryKey = '${context.accountUuid}|$scope';
    final known =
        await cache?.readNotes(context.accountUuid, scope) ??
        _memory[memoryKey] ??
        <String, dynamic>{};
    guard();
    for (final key in candidates['confirmed'] as List? ?? []) {
      known[key as String] = {'used': true, 'height': 0};
    }
    if (cache != null) {
      await cache!.writeNotes(
        context.accountUuid,
        scope,
        known,
        isCurrent: isCurrent,
      );
      guard();
    } else {
      _memory[memoryKey] = known;
    }
  }

  Future<VotingParticipationResult> check(
    rust.ApiVotingRoundContext context,
    DateTime Function() clock,
    bool Function() isCurrent,
  ) async {
    final endpoint = switch (context.network) {
      'main' || 'test' => builtInVotingRpcEndpoint(context.network)!,
      'regtest'
          when regtestEndpoint != null &&
              regtestEndpoint!.scheme == 'http' &&
              const [
                '127.0.0.1',
                'localhost',
                '::1',
              ].contains(regtestEndpoint!.host) =>
        regtestEndpoint!,
      _ => throw StateError('Unsupported voting participation network'),
    };
    final deadline = clock().add(const Duration(minutes: 4));
    void guard() {
      if (!isCurrent()) {
        throw StateError('Voting participation check cancelled');
      }
    }

    Future<Map<String, dynamic>> get(
      String path, [
      Map<String, String>? query,
    ]) => withVotingRetry(
      policy: VotingRetryPolicy(
        name: 'participation-read',
        delays: const [Duration(milliseconds: 300)],
        shouldRetry: (error) =>
            error is _TransientParticipationResponse ||
            isRetryableVotingError(error),
      ),
      delay: _delay,
      isCancelled: () => !isCurrent() || !clock().isBefore(deadline),
      operation: () async {
        guard();
        final remaining = deadline.difference(clock());
        if (remaining <= Duration.zero) {
          throw StateError('Voting participation read deadline exceeded');
        }
        final response = await http.get(
          endpoint.replace(path: path, queryParameters: query),
          timeout: remaining < requestTimeout ? remaining : requestTimeout,
        );
        guard();
        if (const [429, 500, 502, 503, 504].contains(response.statusCode)) {
          throw const _TransientParticipationResponse();
        }
        if (response.statusCode != 200 ||
            response.bodyBytes.length > kVotingParticipationMaxResponseBytes) {
          throw StateError('Voting participation response unavailable');
        }
        return response.decodeJsonObject();
      },
    );

    Future<VotingParticipationResult> evaluate(
      String fingerprint,
      String evidence,
    ) async {
      guard();
      final result = await bridge.evaluate(
        context,
        fingerprint,
        evidence,
        clock(),
      );
      guard();
      return VotingParticipationResult.fromJson(
        jsonDecode(result) as Map<String, dynamic>,
      );
    }

    guard();
    final revision =
        await cache?.snapshotRevision(
          context.roundParams.snapshotHeight.toInt(),
        ) ??
        '0';
    final candidates =
        jsonDecode(await bridge.prepare(context)) as Map<String, dynamic>;
    guard();
    final scope = scopeFor(context);
    final memoryKey = '${context.accountUuid}|$scope';
    final known =
        await cache?.readNotes(context.accountUuid, scope) ??
        _memory[memoryKey] ??
        <String, dynamic>{};
    guard();
    for (final key in candidates['confirmed'] as List? ?? []) {
      known[key as String] = {'used': true, 'height': 0};
    }
    final allKeys = (candidates['keys'] as List).cast<String>();
    final keys = allKeys.where((k) => !known.containsKey(k)).toList();
    Future<VotingParticipationResult> finish(
      Map<String, dynamic> evidence,
    ) async {
      final result = await evaluate(
        candidates['fingerprint'] as String,
        jsonEncode({
          ...evidence,
          'cached': {
            for (final key in allKeys)
              if (known.containsKey(key)) key: known[key],
          },
        }),
      );
      guard();
      final merged = {...known, ...result.observations};
      if (cache != null) {
        await cache!.writeNotes(context.accountUuid, scope, merged);
      } else {
        _memory[memoryKey] = merged;
      }
      if (cache != null &&
          await cache!.snapshotRevision(
                context.roundParams.snapshotHeight.toInt(),
              ) !=
              revision) {
        throw StateError('Voting snapshot changed during inspection');
      }
      return VotingParticipationResult.fromJson({
        ...result.toJson(),
        'observations': result.observations,
        'snapshotRevision': revision,
      });
    }

    if (keys.length > 1024) {
      throw StateError('Voting participation note limit exceeded');
    }
    if (keys.isEmpty) {
      // Recompute eligibility from the current snapshot using verified local
      // observations. No chain requests are needed for already-known notes.
      return finish({'queryKeys': <String>[]});
    }
    // Preserve successful reads even when a sibling request fails. Rust
    // validates the common header once and each proof independently.
    final evidence = await fetchVoteStoreEvidence(
      keys,
      get: get,
      skipFailedQueries: true,
      continueGroups: () {
        guard();
        return clock().isBefore(deadline);
      },
    );
    guard();
    return finish({
      'commit': evidence.commit,
      'validators': evidence.validators,
      'queries': evidence.queries,
      'queryKeys': evidence.keys,
    });
  }
}

// No queried identifiers or response bodies in retryable HTTP errors.
class _TransientParticipationResponse implements Exception {
  const _TransientParticipationResponse();
}
