import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/composite_delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_key_store.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_verifier_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegate.dart' as rust;
import 'package:zcash_wallet/src/rust/api/proxy_delegation.dart' as rust_proofs;
import 'package:zcash_wallet/src/rust/api/proxy_delegator.dart'
    as rust_delegator;
import 'package:zcash_wallet/src/rust/api/voting_session.dart' as rust_session;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_retry.dart';

import 'mock_delegate_mode_repository.dart';
import 'proxy_rust_fake.dart';

/// The vote server base URL delegate-mode tests use.
final kDelegateVoteServer = Uri.parse('https://vote.example');

/// The attester the round config names.
const kDelegateVerifier = 'https://verifier.example';

/// The fake `zvdk1` key number [seed]: the mock's.
String fakeDelegateDk(int seed) => mockDelegateKey(seed).dk;

/// The fake `zvdsk1…` export of key number [seed]: the mock's.
String fakeDelegateSecret(int seed) => mockDelegateSecret(seed);

/// The key a fake export holds, or null for text that is not one.
rust_wire.DelegateKeyInfo? fakeSecretKey(String secret) {
  final seed = RegExp(r'^zvdsk1mock(\d+)$').firstMatch(secret)?.group(1);
  return seed == null ? null : mockDelegateKey(int.parse(seed));
}

/// The fingerprint of a fake `zvdk1` key, as the mock derives it.
String fakeFingerprint(String dk) {
  final chars = dk.substring(5);
  return [for (var i = 0; i < 16; i += 4) chars.substring(i, i + 4)].join('-');
}

/// The bridge's key info for a fake key.
rust_wire.DelegateKeyInfo fakeKeyInfo(String dk) =>
    rust_wire.DelegateKeyInfo(dk: dk, fingerprint: fakeFingerprint(dk));

/// One registry entry on the fake chain: one key for life. Its proven bytes
/// are JSON, which the fake bridge reads as zcash_voting reads the chain's
/// encoding.
class FakeEntry {
  /// Creates the entry.
  FakeEntry(
    this.index, {
    required this.dk,
    required this.handle,
    this.provider = 'x',
    this.proofId = '1790000000000000000',
    this.status = rust_wire.DelegateEntryStatus.active,
  });

  /// Registry index `d`.
  final int index;

  /// The entry's key, `zvdk1…`.
  final String dk;

  /// The account's handle.
  final String handle;

  /// `x` or `github`.
  final String provider;

  /// The post or gist that carries the marker.
  final String proofId;

  /// Active, suspended or retired.
  rust_wire.DelegateEntryStatus status;

  /// Whether the entry is active or suspended.
  bool get live => status != rust_wire.DelegateEntryStatus.retired;

  /// The entry as the participation reader proves it.
  Uint8List bytes() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'index': index,
        'dk': dk,
        'provider': provider,
        'handle': handle,
        'proof_id': proofId,
        'status': status.index,
      }),
    ),
  );

  /// The entry [bytes] encodes.
  static FakeEntry decode(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return FakeEntry(
      json['index'] as int,
      dk: json['dk'] as String,
      handle: json['handle'] as String,
      provider: json['provider'] as String,
      proofId: json['proof_id'] as String,
      status: rust_wire.DelegateEntryStatus.values[json['status'] as int],
    );
  }
}

/// A JSON answer of [status].
VotingHttpResponse fakeJsonAnswer(Object body, {int status = 200}) =>
    VotingHttpResponse(
      statusCode: status,
      bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );

/// The vote chain as delegate mode reads it, in memory, behind the vote
/// server's REST paths: registry entries, the lookup by key, each round's
/// ballot list, pool share counts and the delegate-op endpoint, with the
/// chain's rules for register, retire and ballot ops (contracts-v1 section
/// 5.3).
class FakeDelegateChain implements VotingHttpClient {
  /// Registry entries by index.
  final entries = <int, FakeEntry>{};

  /// Every key ever registered, with its entry. A key is never reused.
  final usedKeys = <String, int>{};

  /// Index of the next new entry.
  int nextIndex = 17;

  /// Ballots by round, then entry.
  final ballots = <String, Map<int, List<int>>>{};

  /// Pool share counts R by round, then entry.
  final shareCounts = <String, Map<int, int>>{};

  /// Whether an accepted op lands at once; otherwise it waits in the
  /// mempool until [land].
  bool landOps = true;

  /// Ops accepted but not landed.
  final mempool = <Map<String, dynamic>>[];

  /// Answers for the next posts, in order: a response, or an error to
  /// throw. When empty, posts are applied.
  final postAnswers = <Object>[];

  /// Ballot posts wait for this before they are answered, when set.
  Completer<void>? holdBallots;

  /// Makes the lookup by key fail in transport.
  bool lookupsDown = false;

  /// Thrown by every GET when set, as a transport failure.
  Object? readFailure;

  /// Every op body posted, in order.
  final posts = <Map<String, dynamic>>[];

  /// Every GET path, in order.
  final reads = <String>[];

  /// Registers an entry of [dk] for [handle].
  FakeEntry register(String handle, String dk, {String provider = 'x'}) {
    final entry = FakeEntry(
      nextIndex++,
      dk: dk,
      handle: handle,
      provider: provider,
    );
    entries[entry.index] = entry;
    usedKeys[dk] = entry.index;
    return entry;
  }

  /// The live entry of [handle] on [provider], if any.
  FakeEntry? liveEntry(String provider, String handle) => entries.values
      .where(
        (entry) =>
            entry.live && entry.provider == provider && entry.handle == handle,
      )
      .firstOrNull;

  /// Applies every op waiting in the mempool.
  void land() {
    for (final op in [...mempool]) {
      _apply(op);
    }
    mempool.clear();
  }

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async {
    reads.add(uri.path);
    if (readFailure case final failure?) throw failure;
    final path = uri.pathSegments;
    final route = path.sublist(path.indexOf('v1') + 1);
    switch (route) {
      case ['delegates', 'by-key', final dk]:
        if (lookupsDown) throw const SocketException('vote server down');
        final index = usedKeys[dk];
        if (index == null) {
          return fakeJsonAnswer({
            'error': 'delegate key $dk was never registered',
          }, status: 404);
        }
        return fakeJsonAnswer({
          'delegate': {'index': index},
        });
      case ['delegate-ballots', final round]:
        final listed = ballots[round] ?? const {};
        return fakeJsonAnswer({
          'ballots': [
            for (final index in listed.keys.toList()..sort())
              {'delegate_index': index, 'options': listed[index]},
          ],
          'next_start_after': 0,
        });
      case ['proxy-delegation-params']:
        return fakeJsonAnswer({'params': <String, Object>{}});
    }
    return fakeJsonAnswer({'error': 'not found'}, status: 404);
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration? timeout,
    int? maxBodyBytes,
  }) async {
    posts.add(body);
    if (body.containsKey('ballot')) await holdBallots?.future;
    if (postAnswers.isNotEmpty) {
      final answer = postAnswers.removeAt(0);
      if (answer is VotingHttpResponse) return answer;
      throw answer;
    }
    final refusal = _refusal(body);
    if (refusal != null) {
      return fakeJsonAnswer({
        'code': refusal,
        'codespace': 'vote',
        'log': 'refused with $refusal',
      }, status: 422);
    }
    if (landOps) {
      _apply(body);
    } else {
      mempool.add(body);
    }
    return fakeJsonAnswer({'tx_hash': 'AB' * 32, 'code': 0, 'codespace': ''});
  }

  /// The code the chain refuses [op] with, if any.
  int? _refusal(Map<String, dynamic> op) {
    if (op['register'] case final Map register) {
      if (usedKeys.containsKey(register['dk'])) return 61;
      final taken = liveEntry(
        register['provider'] as String,
        register['handle'] as String,
      );
      return taken == null ? null : 62;
    }
    final fields = (op['retire'] ?? op['ballot']) as Map;
    final entry = entries[fields['delegate_index']];
    if (entry == null) return 53;
    if (op.containsKey('ballot')) {
      final listed = ballots[fields['round']] ?? const {};
      if (listed.containsKey(entry.index)) return 57;
    }
    return switch (entry.status) {
      rust_wire.DelegateEntryStatus.active => null,
      rust_wire.DelegateEntryStatus.suspended => 54,
      rust_wire.DelegateEntryStatus.retired => 55,
    };
  }

  /// Lands [op].
  void _apply(Map<String, dynamic> op) {
    if (op['register'] case final Map register) {
      // The chain stores each register op at most once.
      if (_refusal(op) != null) return;
      register_(register);
    } else if (op['retire'] case final Map retire) {
      entries[retire['delegate_index']]!.status =
          rust_wire.DelegateEntryStatus.retired;
    } else if (op['ballot'] case final Map ballot) {
      (ballots[ballot['round'] as String] ??= {})[ballot['delegate_index']
          as int] = List<int>.from(
        ballot['options'] as List,
      );
    }
  }

  /// Writes the entry a register op creates.
  void register_(Map op) => register(
    op['handle'] as String,
    op['dk'] as String,
    provider: op['provider'] as String,
  );
}

/// The attester API in memory (contracts-v1 section 12.4): it attests a
/// key for the account the post link names.
class FakeVerifierHosts implements VotingHttpClient {
  /// The attester's clock, in unix seconds: an attestation is valid from
  /// 300 s before it for an hour after it.
  int nowSeconds = 1790000000;

  /// Refusals for the next requests, in order: status and wire code, with
  /// an optional `retry_after`.
  final refusals = <({int status, String code, int? retryAfter})>[];

  /// Raw answers for the next requests, in order, before refusals and
  /// attestations: a status and its body.
  final rawAnswers = <({int status, String body})>[];

  /// Makes every request fail in transport, with [downError].
  bool down = false;

  /// What a request throws while [down].
  Object downError = const SocketException('verifier down');

  /// Every request body, in order.
  final requests = <Map<String, dynamic>>[];

  /// Every request's host, in order.
  final hosts = <String>[];

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) => throw UnsupportedError('The attester is only posted to');

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration? timeout,
    int? maxBodyBytes,
  }) async {
    requests.add(body);
    hosts.add(uri.host);
    if (down) throw downError;
    if (rawAnswers.isNotEmpty) {
      final answer = rawAnswers.removeAt(0);
      return VotingHttpResponse(
        statusCode: answer.status,
        bodyBytes: Uint8List.fromList(utf8.encode(answer.body)),
      );
    }
    if (refusals.isNotEmpty) {
      final refusal = refusals.removeAt(0);
      return fakeJsonAnswer({
        'error': refusal.code,
        'message': 'scripted',
        'retry_after': ?refusal.retryAfter,
      }, status: refusal.status);
    }
    final link = Uri.parse(body['proof_url'] as String).pathSegments;
    return fakeJsonAnswer({
      'provider': body['provider'],
      'handle': link.first,
      'proof_id': link.last,
      'attestations': [
        {
          'verifier_id': 1,
          'not_before': nowSeconds - 300,
          'expires_at': nowSeconds + 3600,
          'sig': 'c2ln',
        },
      ],
    });
  }
}

/// zcash_voting's delegate-mode calls in memory, on the rules the Rust
/// bridge tests pin: the device's one key record, the entry read from its
/// proven bytes, ops as JSON the fake chain applies, and the stored ballots.
class FakeProxyDelegateRust {
  /// The device's key, `zvdk1…`, or null when it holds none.
  String? heldDk;

  /// The entry a proven entry showed the key in.
  int? heldIndex;

  /// The key's stored register op, until a proven entry settles it.
  Map<String, dynamic>? pendingRegister;

  /// Ballots signed on this device by `round/index`.
  final stored = <String, ({List<int> options, Map<String, dynamic> op})>{};

  /// The keys whose export a signing call was given, in order.
  final signedWith = <String>[];

  /// Names of the calls made, in order.
  final calls = <String>[];

  /// Thrown by [recordKey] when set, as a failed write.
  Object? recordFailure;

  int _created = 0;

  Future<rust.ApiNewDelegateKey> createKey() async {
    calls.add('createKey');
    final seed = 1000 + ++_created;
    return rust.ApiNewDelegateKey(
      key: fakeKeyInfo(fakeDelegateDk(seed)),
      secret: fakeDelegateSecret(seed),
    );
  }

  Future<rust_wire.DelegateKeyInfo?> importKey(String secret) async {
    calls.add('importKey');
    return fakeSecretKey(secret);
  }

  Future<void> recordKey(
    rust.ApiDelegateModeScope scope, {
    required String dk,
    required BigInt nowSeconds,
  }) async {
    calls.add('recordKey');
    if (recordFailure case final failure?) throw failure;
    _hold(dk);
  }

  /// Records [dk] as the device's key, refusing a second one.
  void _hold(String dk) {
    if (heldDk != null && heldDk != dk) {
      throw const rust.ApiDelegateModeError(
        kind: rust.ApiDelegateModeErrorKind.other,
        message: 'the device already holds another delegate key',
      );
    }
    heldDk = dk;
  }

  Future<rust.ApiDeviceDelegateKey?> deviceKey(
    rust.ApiDelegateModeScope scope,
  ) async => switch (heldDk) {
    final dk? => rust.ApiDeviceDelegateKey(
      key: fakeKeyInfo(dk),
      delegateIndex: heldIndex,
    ),
    null => null,
  };

  Future<void> forgetKey(rust.ApiDelegateModeScope scope) async {
    calls.add('forgetKey');
    heldDk = null;
    heldIndex = null;
    pendingRegister = null;
  }

  Future<String> byKeyPath(String dk) async =>
      '/shielded-vote/v1/delegates/by-key/$dk';

  Future<int?> parseByKeyAnswer({
    required String dk,
    required int status,
    required Uint8List body,
  }) async {
    final text = utf8.decode(body);
    if (status == 200) return (jsonDecode(text) as Map)['delegate']['index'];
    if (status == 404 && text.contains('$dk was never registered')) return null;
    throw rust.ApiDelegateModeError(
      kind: rust.ApiDelegateModeErrorKind.chainAnswer,
      message: 'HTTP $status',
    );
  }

  Future<rust_wire.DelegateModeStatus?> status(
    rust.ApiDelegateModeScope scope, {
    required rust_proofs.ApiProvenRegistryEntry? entry,
  }) async {
    calls.add('status');
    final dk = heldDk;
    if (dk == null) return null;
    // An entry proven absent counts as none.
    final proven = entry?.entry == null ? null : _entry(entry!);
    if (proven != null) {
      if (proven.dk != dk || (heldIndex ?? proven.index) != proven.index) {
        throw const rust.ApiDelegateModeError(
          kind: rust.ApiDelegateModeErrorKind.entryUnverifiable,
          message: "the entry is not the device's",
        );
      }
      heldIndex = proven.index;
      pendingRegister = null;
    }
    return rust_wire.DelegateModeStatus(
      key: fakeKeyInfo(dk),
      entry: proven == null
          ? null
          : rust_wire.DelegateEntryView(
              delegateIndex: proven.index,
              provider: _provider(proven.provider),
              handle: proven.handle,
              proofId: proven.proofId,
              status: proven.status,
              statusReason: 0,
            ),
      registrationPending: proven == null && pendingRegister != null,
    );
  }

  Future<String> markerText(String dk) async => 'zcash-vote-delegate v1 $dk';

  Future<rust.ApiVerifierRequest> attestRequest({
    required rust_wire.ProxyDelegateProvider provider,
    required String proofUrl,
    required String dk,
  }) async => rust.ApiVerifierRequest(
    path: '/v1/attest',
    body: Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'provider': provider == rust_wire.ProxyDelegateProvider.x ? 1 : 2,
          'proof_url': proofUrl,
          'dk': dk,
        }),
      ),
    ),
  );

  Future<rust_wire.DelegateAttestation> parseAttestAnswer({
    required String dk,
    required int status,
    required Uint8List body,
  }) async {
    // As zcash_voting's parse_attest_response: a section 12.4 code counts
    // only with its paired status, and anything malformed is `unknown`.
    Never unknown(String detail) => throw rust_wire.DelegateVerifierRefusal(
      error: rust_wire.DelegateVerifierError.unknown,
      detail: detail,
    );
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    } catch (_) {
      unknown('not JSON');
    }
    if (status != 200) {
      final code = json['error'];
      final paired = code is String ? _verifierCodes[code] : null;
      if (paired == null || paired.$2 != status) {
        unknown('HTTP $status with error $code');
      }
      throw rust_wire.DelegateVerifierRefusal(
        error: paired.$1,
        retryAfter: switch (json['retry_after']) {
          final int seconds => BigInt.from(seconds),
          _ => null,
        },
        detail: json['message'] as String?,
      );
    }
    try {
      return rust_wire.DelegateAttestation(
        key: fakeKeyInfo(dk),
        provider: json['provider'] == 2
            ? rust_wire.ProxyDelegateProvider.gitHub
            : rust_wire.ProxyDelegateProvider.x,
        handle: json['handle'] as String,
        proofId: json['proof_id'] as String,
        attestations: [
          for (final signature in json['attestations'] as List)
            rust_wire.DelegateAttestationSignature(
              verifierId: signature['verifier_id'] as int,
              notBefore: BigInt.from(signature['not_before'] as int),
              expiresAt: BigInt.from(signature['expires_at'] as int),
              sig: signature['sig'] as String,
            ),
        ],
      );
    } on TypeError {
      unknown('the attest answer does not parse');
    }
  }

  /// The section 12.4 error codes with the status each pairs with.
  static const _verifierCodes = {
    'bad_request': (rust_wire.DelegateVerifierError.badRequest, 400),
    'post_not_found': (rust_wire.DelegateVerifierError.postNotFound, 404),
    'marker_mismatch': (rust_wire.DelegateVerifierError.markerMismatch, 409),
    'rate_limited': (rust_wire.DelegateVerifierError.rateLimited, 429),
    'provider_unavailable': (
      rust_wire.DelegateVerifierError.providerUnavailable,
      503,
    ),
  };

  Future<rust.ApiSignedDelegateOp> prepareRegisterOp(
    rust.ApiDelegateModeScope scope, {
    required rust_wire.DelegateAttestation attestation,
    required rust_wire.ProxyDelegateProvider provider,
    required Uint8List? proxyParams,
    required String secret,
    required BigInt nowSeconds,
  }) async {
    calls.add('prepareRegisterOp');
    final dk = attestation.key.dk;
    // As check_attestation: the attested key is the signer's, on the
    // provider the marker was posted on.
    if (_signer(secret) != dk || provider != attestation.provider) {
      throw const rust.ApiDelegateModeError(
        kind: rust.ApiDelegateModeErrorKind.other,
        message: 'the attestation does not bind the post',
      );
    }
    _hold(dk);
    if (heldIndex != null) {
      throw const rust.ApiDelegateModeError(
        kind: rust.ApiDelegateModeErrorKind.other,
        message: 'registered',
      );
    }
    final op = {
      'register': {
        'dk': dk,
        'delegate_index': 0,
        'provider': provider == rust_wire.ProxyDelegateProvider.x
            ? 'x'
            : 'github',
        'handle': attestation.handle,
        'proof_id': attestation.proofId,
      },
    };
    pendingRegister = op;
    return _op(rust.ApiDelegateOpKind.register, op);
  }

  Future<rust.ApiSignedDelegateOp?> pendingRegisterOp(
    rust.ApiDelegateModeScope scope,
  ) async => switch (pendingRegister) {
    final pending? => _op(rust.ApiDelegateOpKind.register, pending),
    null => null,
  };

  Future<String> opPath() async => '/shielded-vote/v1/delegate-op';

  Future<rust.ApiDelegateOpAnswer> parseOpAnswer({
    required rust.ApiDelegateOpKind op,
    required int status,
    required Uint8List body,
  }) async {
    if (status == 400) {
      return const rust.ApiDelegateOpAnswer(
        kind: rust.ApiDelegateOpAnswerKind.requestRefused,
        detail: 'bad request',
      );
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    } catch (_) {
      return const rust.ApiDelegateOpAnswer(
        kind: rust.ApiDelegateOpAnswerKind.noVerdict,
      );
    }
    final code = json['code'] as int?;
    if (status == 200 && code == 0) {
      return rust.ApiDelegateOpAnswer(
        kind: rust.ApiDelegateOpAnswerKind.accepted,
        txHash: json['tx_hash'] as String?,
      );
    }
    if (status != 422 || code == null || code == 0) {
      return const rust.ApiDelegateOpAnswer(
        kind: rust.ApiDelegateOpAnswerKind.noVerdict,
      );
    }
    final codespace = json['codespace'] as String;
    final applied = switch (op) {
      rust.ApiDelegateOpKind.register => 61,
      rust.ApiDelegateOpKind.retire => 55,
      rust.ApiDelegateOpKind.ballot => 57,
    };
    return rust.ApiDelegateOpAnswer(
      kind: codespace == 'vote' && code == applied
          ? rust.ApiDelegateOpAnswerKind.alreadyApplied
          : rust.ApiDelegateOpAnswerKind.rejected,
      codespace: codespace,
      code: code,
      detail: json['log'] as String?,
    );
  }

  Future<String> ballotsPagePath({
    required String roundId,
    required int startAfter,
  }) async =>
      '/shielded-vote/v1/delegate-ballots/$roundId'
      '?start_after=$startAfter&limit=1000';

  Future<rust.ApiDelegateBallotSearch> ballotPage({
    required String roundId,
    required int startAfter,
    required Uint8List page,
    required int? delegateIndex,
  }) async {
    final json = jsonDecode(utf8.decode(page)) as Map<String, dynamic>;
    rust.ApiChainDelegateBallot? found;
    for (final ballot in json['ballots'] as List) {
      if (ballot['delegate_index'] == delegateIndex) {
        found = rust.ApiChainDelegateBallot(
          delegateIndex: delegateIndex!,
          options: Uint32List.fromList(List<int>.from(ballot['options'])),
          height: BigInt.from(12),
        );
      }
    }
    final after = json['next_start_after'] as int;
    return rust.ApiDelegateBallotSearch(
      nextStartAfter: after == 0 ? null : after,
      ballot: found,
    );
  }

  Future<String> poolShareCountKey({
    required String roundId,
    required int delegateIndex,
  }) async => '0b$roundId/$delegateIndex';

  Future<rust.ApiDelegateRound> roundView(
    rust.ApiDelegateModeScope scope, {
    required rust.ApiDelegateRoundTiming round,
    required rust_proofs.ApiProvenRegistryEntry? entry,
    required rust.ApiChainDelegateBallot? chainBallot,
    required Uint8List? poolShareCount,
    required BigInt nowSeconds,
  }) async {
    final proven = entry == null ? null : _entry(entry);
    final closed = nowSeconds >= round.voteEndTime;
    final options = chainBallot?.options;
    final local = proven == null
        ? null
        : stored['${round.roundId}/${proven.index}'];
    return rust.ApiDelegateRound(
      roundId: round.roundId,
      voteEndTime: round.voteEndTime,
      revealedShares: poolShareCount == null
          ? BigInt.zero
          : BigInt.from(ByteData.sublistView(poolShareCount).getUint64(0)),
      ballot: rust_delegator.ApiDelegateBallotView(
        kind: switch ((options != null, closed)) {
          (true, false) => rust_delegator.ApiDelegateBallotKind.submitted,
          (true, true) => rust_delegator.ApiDelegateBallotKind.counted,
          (false, false) => rust_delegator.ApiDelegateBallotKind.noBallotYet,
          (false, true) => rust_delegator.ApiDelegateBallotKind.notCounted,
        },
        options: options ?? Uint32List(0),
      ),
      storedBallot: chainBallot == null && local != null
          ? Uint32List.fromList(local.options)
          : null,
      ballotBlock: proven == null
          ? rust_wire.DelegateBallotBlock.notRegistered
          : _block(proven),
    );
  }

  Future<rust.ApiBallotPreflight> preflight(
    rust.ApiDelegateModeScope scope, {
    required String roundId,
    required int delegateIndex,
    required rust.ApiChainDelegateBallot? chainBallot,
    required List<int> options,
  }) async {
    calls.add('preflight');
    final existing =
        chainBallot?.options.toList() ??
        stored['$roundId/$delegateIndex']?.options;
    return rust.ApiBallotPreflight(
      alreadySubmitted: existing != null,
      options: Uint32List.fromList(existing ?? const []),
      sameOptions: existing != null && listEquals(existing, options),
    );
  }

  Future<rust.ApiSignedDelegateOp> signBallot(
    rust.ApiDelegateModeScope scope, {
    required rust.ApiDelegateRoundTiming round,
    required rust_proofs.ApiProvenRegistryEntry entry,
    required List<rust_session.ApiProposalRosterEntry> proposals,
    required List<int> options,
    required String secret,
    required BigInt nowSeconds,
  }) async {
    calls.add('signBallot');
    final proven = _entry(entry);
    final signer = _signer(secret);
    rust.ApiDelegateModeError refuse(String why) => rust.ApiDelegateModeError(
      kind: rust.ApiDelegateModeErrorKind.other,
      message: why,
    );
    final key = '${round.roundId}/${proven.index}';
    final existing = stored[key];
    if (existing != null) {
      if (!listEquals(existing.options, options)) {
        throw refuse('a different ballot is stored');
      }
      return _op(rust.ApiDelegateOpKind.ballot, existing.op);
    }
    if (nowSeconds >= round.voteEndTime) throw refuse('voting ended');
    if (options.length != proposals.length) throw refuse('incomplete');
    for (final (i, proposal) in proposals.indexed) {
      if (options[i] >= proposal.numOptions) throw refuse('no such option');
    }
    if (_block(proven) != null) throw refuse('blocked');
    if (proven.dk != signer) throw refuse("not the entry's key");
    final op = {
      'ballot': {
        'round': round.roundId,
        'delegate_index': proven.index,
        'options': options,
        'dk': signer,
      },
    };
    stored[key] = (options: [...options], op: op);
    return _op(rust.ApiDelegateOpKind.ballot, op);
  }

  Future<rust.ApiStoredDelegateBallot?> storedBallot(
    rust.ApiDelegateModeScope scope, {
    required String roundId,
    required int delegateIndex,
  }) async {
    final ballot = stored['$roundId/$delegateIndex'];
    if (ballot == null) return null;
    return rust.ApiStoredDelegateBallot(
      options: Uint32List.fromList(ballot.options),
      op: _op(rust.ApiDelegateOpKind.ballot, ballot.op),
    );
  }

  Future<rust.ApiBallotSubmitResult?> existingBallotResult(
    rust.ApiDelegateModeScope scope, {
    required String roundId,
    required int delegateIndex,
    required rust.ApiChainDelegateBallot? chainBallot,
  }) async {
    final ballot = stored['$roundId/$delegateIndex'];
    if (ballot == null || chainBallot == null) return null;
    return listEquals(chainBallot.options.toList(), ballot.options)
        ? const rust.ApiBallotSubmitResult(
            kind: rust.ApiBallotSubmitKind.alreadyAccepted,
          )
        : const rust.ApiBallotSubmitResult(
            kind: rust.ApiBallotSubmitKind.rejected,
            codespace: 'vote',
            code: 57,
            reason: 'a different ballot is listed',
          );
  }

  Future<rust.ApiSignedDelegateOp> retireOp(
    rust.ApiDelegateModeScope scope, {
    required rust_proofs.ApiProvenRegistryEntry entry,
    required String secret,
  }) async {
    calls.add('retireOp');
    final proven = _entry(entry);
    final signer = _signer(secret);
    if (proven.dk != signer) {
      throw const rust.ApiDelegateModeError(
        kind: rust.ApiDelegateModeErrorKind.entryUnverifiable,
        message: "only the entry's key retires it",
      );
    }
    return _op(rust.ApiDelegateOpKind.retire, {
      'retire': {'delegate_index': proven.index, 'dk': signer},
    });
  }

  /// The key [secret] signs for, as Rust's `signing_key` reads it.
  String _signer(String secret) {
    final key = fakeSecretKey(secret);
    if (key == null) {
      throw const rust.ApiDelegateModeError(
        kind: rust.ApiDelegateModeErrorKind.other,
        message: "the delegate key's secret is not a zvdsk1 export",
      );
    }
    signedWith.add(key.dk);
    return key.dk;
  }

  /// The entry a proof carries; an absent one is refused as zcash_voting
  /// refuses it.
  FakeEntry _entry(rust_proofs.ApiProvenRegistryEntry proof) {
    final bytes = proof.entry;
    if (bytes == null) {
      throw const rust.ApiDelegateModeError(
        kind: rust.ApiDelegateModeErrorKind.entryUnverifiable,
        message: 'proven absent',
      );
    }
    return FakeEntry.decode(bytes);
  }

  /// Why [entry] may not ballot, if it may not.
  static rust_wire.DelegateBallotBlock? _block(FakeEntry entry) =>
      switch (entry.status) {
        rust_wire.DelegateEntryStatus.active => null,
        rust_wire.DelegateEntryStatus.suspended =>
          rust_wire.DelegateBallotBlock.suspended,
        rust_wire.DelegateEntryStatus.retired =>
          rust_wire.DelegateBallotBlock.retired,
      };

  /// The bridge's provider for a fake entry's.
  static rust_wire.ProxyDelegateProvider _provider(String provider) =>
      provider == 'github'
      ? rust_wire.ProxyDelegateProvider.gitHub
      : rust_wire.ProxyDelegateProvider.x;

  /// A signed op of [kind] carrying [op] as its body.
  rust.ApiSignedDelegateOp _op(
    rust.ApiDelegateOpKind kind,
    Map<String, dynamic> op,
  ) {
    final fields = op.values.single as Map;
    return rust.ApiSignedDelegateOp(
      kind: kind,
      delegateIndex: fields['delegate_index'] as int,
      dk: fields['dk'] as String,
      body: Uint8List.fromList(utf8.encode(jsonEncode(op))),
    );
  }
}

/// A delegate key store in memory.
class MemoryDelegateKeyStore implements DelegateKeyStore {
  /// Stored exports by key.
  final secrets = <String, String>{};

  /// Whether the wallet is unlocked; a locked wallet reads nothing.
  bool unlocked = true;

  /// How many times an export was read.
  int reads = 0;

  @override
  Future<void> write(String dk, String secret) async => secrets[dk] = secret;

  @override
  Future<String?> read(String dk) async {
    reads++;
    return unlocked ? secrets[dk] : null;
  }

  @override
  Future<void> delete(String dk) async => secrets.remove(dk);
}

/// A proxy round for delegate-mode tests ending at [voteEnd], with two
/// questions of two and three options.
DelegateModeRound fakeDelegateRound({
  required String roundId,
  required DateTime voteEnd,
  String title = 'Q4 funding',
  bool active = true,
}) {
  return DelegateModeRound(
    roundId: roundId,
    title: title,
    active: active,
    proposals: const [
      VotingProposalView(
        id: 1,
        title: 'Fund the wallet grant',
        description: '',
        options: [
          VotingOptionView(index: 0, label: 'Yes'),
          VotingOptionView(index: 1, label: 'No'),
        ],
      ),
      VotingProposalView(
        id: 2,
        title: 'Pick a dev fund split',
        description: '',
        options: [
          VotingOptionView(index: 0, label: 'Split A'),
          VotingOptionView(index: 1, label: 'Split B'),
          VotingOptionView(index: 2, label: 'Split C'),
        ],
      ),
    ],
    voteEnd: voteEnd,
  );
}

/// [DelegateModeHost] over [FakeDelegateChain]: its entries proven, its
/// share counts read raw, and its REST paths behind a real
/// [VotingApiClient].
class FakeDelegateModeHost implements DelegateModeHost {
  /// Creates the host.
  FakeDelegateModeHost(this.chain);

  /// The chain everything reads.
  final FakeDelegateChain chain;

  /// The proxy rounds, newest first.
  final rounds_ = <DelegateModeRound>[];

  /// Makes every proof fail as cannot-verify.
  bool proofsFail = false;

  /// How many of the next proofs trail the lookup by key by a block: each
  /// proves the entry absent.
  int laggingProofs = 0;

  /// Makes every share count read fail.
  bool storeDown = false;

  /// Vizor's list pictures by entry.
  final pictures = <int, ProxyDelegatePicture>{};

  /// The destructive-operation drain.
  final drain = VotingShareTrackingRegistry();

  /// Every proof request, in order.
  final proofRequests = <List<int>>[];

  @override
  String get network => 'main';

  @override
  Future<String> dbPath() async => '/tmp/wallet.db';

  @override
  Future<VotingApiClient> voteServers() async => VotingApiClient(
    baseUrl: kDelegateVoteServer,
    httpClient: chain,
    readRetryPolicy: VotingRetryPolicy.transientHttp(
      name: 'test-delegate-read',
      delays: const [],
    ),
    delay: (_) async {},
  );

  /// How many times [rounds] was read.
  int roundReads = 0;

  /// Rounds whose lookup fails, left out of [rounds].
  final failingRounds = <String>{};

  @override
  Future<DelegateModeRounds> rounds() async {
    roundReads++;
    return (
      rounds: [
        for (final round in rounds_)
          if (!failingRounds.contains(round.roundId)) round,
      ],
      complete: failingRounds.isEmpty,
    );
  }

  /// The attester API URLs the config names, in order.
  List<String> verifierUrls = const [kDelegateVerifier];

  @override
  List<String> verifierApiUrls() => verifierUrls;

  @override
  Future<List<rust_proofs.ApiProvenRegistryEntry>> proveEntries(
    List<int> delegateIndices,
  ) async {
    proofRequests.add(delegateIndices);
    if (proofsFail) {
      throw const ProxyDelegationError(
        kind: ProxyDelegationErrorKind.cannotVerify,
      );
    }
    final lagging = laggingProofs > 0;
    if (lagging) laggingProofs--;
    return [
      for (final index in delegateIndices)
        rust_proofs.ApiProvenRegistryEntry(
          delegateIndex: index,
          entry: lagging ? null : chain.entries[index]?.bytes(),
        ),
    ];
  }

  @override
  Future<Uint8List?> storeValue(String keyHex) async {
    if (storeDown) throw StateError('No proof host answered');
    final [round, index] = keyHex.substring(2).split('/');
    final count = chain.shareCounts[round]?[int.parse(index)];
    if (count == null) return null;
    return (ByteData(8)..setUint64(0, count)).buffer.asUint8List();
  }

  @override
  Future<ProxyDelegatePicture?> listPicture(int delegateIndex) async =>
      pictures[delegateIndex];

  @override
  VoidCallback? beginWork() => drain.beginBackgroundWork();
}

/// The real repository over every fake, sharing one chain.
class RealDelegateMode {
  /// Creates delegate mode at [now] and installs its [bridge] as Rust's
  /// delegate-mode calls. A test file calls `useProxyRustFake()` first; a
  /// second instance in one test takes Rust over from the first.
  RealDelegateMode({required this.now}) {
    proxyRust.delegate = bridge;
    host = FakeDelegateModeHost(chain);
    repository = restarted();
  }

  /// The device time the repository reads; tests may move it.
  DateTime now;

  /// The vote chain.
  final chain = FakeDelegateChain();

  /// zcash_voting's side.
  final bridge = FakeProxyDelegateRust();

  /// The key store.
  final keys = MemoryDelegateKeyStore();

  /// The attester API.
  final verifier = FakeVerifierHosts();

  /// How many times signing asked the app's re-auth.
  int reauths = 0;

  /// The answer to the app's re-auth.
  bool reauthAllows = true;

  /// The re-auth every signing call in these tests passes.
  Future<bool> reauth() async {
    reauths++;
    return reauthAllows;
  }

  /// The app state.
  late final FakeDelegateModeHost host;

  /// The repository under test.
  late final CompositeDelegateModeRepository repository;

  /// Another repository over the same device and chain, as the app builds
  /// it after a restart: nothing cached in memory carries over. Its reads
  /// serve for [readsMaxAge], by default the app's.
  CompositeDelegateModeRepository restarted({
    Duration readsMaxAge = const Duration(seconds: 15),
  }) => CompositeDelegateModeRepository(
    readsMaxAge: readsMaxAge,
    host: host,
    keys: keys,
    verifier: DelegateVerifierClient(verifier),
    clock: () => now,
    delay: (_) async {},
    settleTimeout: const Duration(seconds: 30),
    pollInterval: const Duration(seconds: 5),
  );

  /// Key number [seed] on this device, stored and recorded as zcash_voting
  /// would, without going through the repository. Returns its key.
  String holdsKey(int seed) {
    final dk = fakeDelegateDk(seed);
    keys.secrets[dk] = fakeDelegateSecret(seed);
    bridge.heldDk = dk;
    return dk;
  }

  /// Key number [seed] registered as [handle] on the chain and held here,
  /// its record mirrored. Returns its entry.
  FakeEntry registeredKey(int seed, {String handle = 'alice'}) {
    final entry = chain.register(handle, holdsKey(seed));
    bridge.heldIndex = entry.index;
    return entry;
  }
}
