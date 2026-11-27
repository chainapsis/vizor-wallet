import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../rust/api/proxy_delegate.dart' as rust;
import '../../../rust/api/proxy_delegation.dart' as rust_proofs;
import '../../../rust/api/voting_session.dart' as rust_session;
import '../../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../../services/voting/voting_api_client.dart';
import '../../../services/voting/voting_models.dart';
import '../../../services/voting/voting_retry.dart';
import '../voting_flow_models.dart';
import 'delegate_ballot_pager.dart';
import 'delegate_error_log.dart';
import 'delegate_key_store.dart';
import 'delegate_mode_models.dart';
import 'delegate_mode_presentation.dart';
import 'delegate_mode_repository.dart';
import 'delegate_verifier_client.dart';
import 'proxy_delegation_repository.dart';

/// A proxy round as delegate mode reads it: the round's facts from the vote
/// server, as ordinary votes read them. A wrong vote end only makes the
/// chain refuse the delegate's ballot.
@immutable
class DelegateModeRound {
  /// Creates the round.
  const DelegateModeRound({
    required this.roundId,
    required this.title,
    required this.proposals,
    required this.voteEnd,
    required this.active,
  });

  /// The round id, lowercase hex.
  final String roundId;

  /// The round title.
  final String title;

  /// Every question in id order.
  final List<VotingProposalView> proposals;

  /// The vote end, the ballot deadline.
  final DateTime voteEnd;

  /// The vote server reports the round ACTIVE. Once it does not, the chain
  /// takes no ballot for it.
  final bool active;
}

/// The proxy rounds the host could read, and whether it read every
/// authenticated round: one whose lookup failed is left out.
typedef DelegateModeRounds = ({List<DelegateModeRound> rounds, bool complete});

/// The app state delegate mode reads: the wallet network and database, the
/// configured vote servers, the proxy rounds, and the registry client's
/// proofs and list.
abstract interface class DelegateModeHost {
  /// The wallet network: `main`, `test` or `regtest`.
  String get network;

  /// The main wallet database path; the voting sidecar lives beside it.
  Future<String> dbPath();

  /// The configured vote servers, with their failover.
  Future<VotingApiClient> voteServers();

  /// The authenticated rounds the vote server reports as proxy rounds, with
  /// a vote end, newest first. A round whose lookup fails is left out, and
  /// the others still come back.
  Future<DelegateModeRounds> rounds();

  /// The attester API URLs the latest config load named.
  List<String> verifierApiUrls();

  /// The participation reader's proofs of [delegateIndices]' registry
  /// entries, in order. Throws [ProxyDelegationError] with
  /// [ProxyDelegationErrorKind.cannotVerify] when none verifies.
  Future<List<rust_proofs.ApiProvenRegistryEntry>> proveEntries(
    List<int> delegateIndices,
  );

  /// The raw `vote` store value at [keyHex], unproven, or null when the key
  /// is absent.
  Future<Uint8List?> storeValue(String keyHex);

  /// The picture Vizor's list gives entry [delegateIndex], or null.
  Future<ProxyDelegatePicture?> listPicture(int delegateIndex);

  /// Takes the voting destructive-operation lease, or returns null while
  /// account deletion or wallet reset holds the data.
  VoidCallback? beginWork();
}

/// Delegate mode over zcash_voting's delegate APIs (contracts-v1 sections
/// 11.12 and 15.1), the attester API and Vizor's participation reader.
///
/// zcash_voting decides everything through the Rust bridge
/// (`rust/src/api/proxy_delegate.rs`, where each call is documented); this
/// class fetches and posts the bytes, proves the delegate's entry, keeps the
/// device's one key in [DelegateKeyStore] and maps the answers onto the
/// screens' models.
///
/// The key's secret is read only after the caller's re-auth, for the one
/// call that signs or shows it, and is never cached or logged. Every call
/// holds the voting destructive-operation lease, so account deletion and
/// wallet reset wait for it.
class CompositeDelegateModeRepository implements DelegateModeRepository {
  /// Creates the repository.
  CompositeDelegateModeRepository({
    required DelegateModeHost host,
    required DelegateKeyStore keys,
    required DelegateVerifierClient verifier,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    this.settleTimeout = const Duration(minutes: 3),
    this.pollInterval = const Duration(seconds: 5),
    this.readsMaxAge = const Duration(seconds: 15),
  }) : _host = host,
       _keys = keys,
       _verifier = verifier,
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed {
    _ballotLists = DelegateBallotPager(
      maxAge: readsMaxAge,
      clock: _clock,
      nextStartAfter: (roundId, startAfter, page) async =>
          (await rust.delegateBallotPage(
            roundId: roundId,
            startAfter: startAfter,
            page: page,
            delegateIndex: null,
          )).nextStartAfter,
      tooManyPages: () => const DelegateModeException(
        DelegateModeErrorKind.unavailable,
        'the delegate ballot list has too many pages', // l10n-ignore: error detail for logs
      ),
    );
  }

  final DelegateModeHost _host;
  final DelegateKeyStore _keys;
  final DelegateVerifierClient _verifier;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  /// How long a registration or Retire is followed before the call gives
  /// up; it then settles on a later status read.
  final Duration settleTimeout;

  /// The wait between two reads while an op settles.
  final Duration pollInterval;

  /// How long proofs, round facts and ballot lists serve repeated reads.
  final Duration readsMaxAge;

  /// How many posts of one op without a verdict before the call stops.
  static const maxPostAttempts = 3;

  /// While a registration settles, its stored op is resent every this many
  /// reads, in case it left the mempool.
  static const _resendEvery = 4;

  /// The provider the key's last attestation was asked for, which the
  /// register op must bind.
  final _attestedProviders = <String, rust_wire.ProxyDelegateProvider>{};

  ({DateTime at, DelegateModeRounds read})? _rounds;
  ({DateTime at, rust_proofs.ApiProvenRegistryEntry entry})? _proof;
  late final DelegateBallotPager _ballotLists;
  final _lastCounts = <String, Uint8List?>{};

  @override
  Future<DelegateModeView> status() => _call(() async {
    final scope = await _scope();
    final held = await rust.deviceDelegateKey(scope: scope);
    if (held == null) return const DelegateModeView();
    rust_proofs.ApiProvenRegistryEntry? entry;
    if (held.delegateIndex case final index?) {
      entry = await _prove(index);
    } else {
      // The key may have registered since: a stored register op that
      // landed, or an import. The lookup by key names the entry to prove;
      // one the chain cannot answer or prove waits for later.
      try {
        final index = await _lookUp(held.key.dk);
        if (index != null) entry = await _prove(index, fresh: true);
      } catch (error) {
        _log('the key has no proven entry yet', error);
      }
    }
    rust_wire.DelegateModeStatus? status;
    try {
      status = await rust.delegateModeStatus(scope: scope, entry: entry);
    } on rust.ApiDelegateModeError catch (error) {
      // A looked-up entry that is not the key's settles nothing.
      if (held.delegateIndex != null ||
          error.kind != rust.ApiDelegateModeErrorKind.entryUnverifiable) {
        rethrow;
      }
      _log('the looked-up entry is not the key\'s', error);
      status = await rust.delegateModeStatus(scope: scope, entry: null);
    }
    ProxyDelegatePicture? picture;
    if (status?.entry case final view?) {
      try {
        picture = await _host.listPicture(view.delegateIndex);
      } catch (error) {
        _log('no picture for the dashboard', error);
      }
    }
    return DelegateModeView(status: status, picture: picture);
  });

  @override
  Future<DelegateKeyInfo> createKey() => _call(() async {
    final scope = await _scope();
    await _requireNoKey(scope);
    final created = await rust.createDelegateKey();
    await _storeKey(scope, created.key.dk, created.secret);
    return created.key;
  });

  @override
  Future<DelegateKeyInfo> importKey(String text) => _call(() async {
    final secret = text.trim();
    final key = await rust.importDelegateKey(secret: secret);
    if (key == null) throw const DelegateKeyImportException();
    final scope = await _scope();
    await _requireNoKey(scope);
    await _storeKey(scope, key.dk, secret);
    return key;
  });

  @override
  Future<String> exportKey() => _call(() async {
    final held = await rust.deviceDelegateKey(scope: await _scope());
    final secret = held == null ? null : await _keys.read(held.key.dk);
    if (secret == null) throw const _NoSigningKey();
    return secret;
  });

  @override
  Future<void> startOver() => _call(() async {
    final scope = await _scope();
    final held = await rust.deviceDelegateKey(scope: scope);
    if (held == null) return;
    if (held.delegateIndex case final index?) {
      final status = await rust.delegateModeStatus(
        scope: scope,
        entry: await _prove(index, fresh: true),
      );
      if (status?.entry?.status != rust_wire.DelegateEntryStatus.retired) {
        throw const DelegateModeException(
          DelegateModeErrorKind.other,
          "the key's entry is live",
        );
      }
    }
    // The record goes first, with its pending register op, so a failure
    // never leaves a recorded key without its secret.
    await rust.forgetDelegateKey(scope: scope);
    await _keys.delete(held.key.dk);
    _attestedProviders.clear();
    _proof = null;
  });

  @override
  Future<String> markerText(DelegateKeyInfo key) =>
      _call(() => rust.delegateMarkerText(dk: key.dk));

  @override
  Future<DelegateAttestation> attest({
    required ProxyDelegateProvider provider,
    required String proofUrl,
    required DelegateKeyInfo key,
  }) => _guard(() async {
    final request = await rust.delegateAttestRequest(
      provider: provider,
      proofUrl: proofUrl,
      dk: key.dk,
    );
    // Only a section 12.4 code with its paired status is the attester's
    // word. Any other answer comes from a host that does not speak the API,
    // so the next host is asked.
    final attestation = await _verifier.post(
      network: _host.network,
      urls: _host.verifierApiUrls(),
      path: request.path,
      body: request.body,
      accept: (answer) async {
        try {
          return await rust.parseDelegateAttestAnswer(
            dk: key.dk,
            status: answer.statusCode,
            body: answer.body,
          );
        } on DelegateVerifierRefusal catch (refusal) {
          if (refusal.error == DelegateVerifierError.unknown) {
            throw DelegateVerifierAnswerUnusable(refusal);
          }
          rethrow;
        }
      },
    );
    if (attestation == null) {
      throw const DelegateModeException(
        DelegateModeErrorKind.unavailable,
        'no attester answered',
      );
    }
    _attestedProviders[key.dk] = provider;
    return attestation;
  });

  @override
  Future<DelegateRegisterResult> register(
    DelegateAttestation attestation, {
    required DelegateReauthCheck reauth,
  }) => _call(() async {
    final scope = await _scope();
    final dk = attestation.key.dk;
    Uint8List? params;
    try {
      params = await (await _host.voteServers()).getProxyDelegationParamsBody();
    } catch (error) {
      _log('the register op is built without the verifier set', error);
    }
    final op = await rust.prepareDelegateRegisterOp(
      scope: scope,
      attestation: attestation,
      provider: _attestedProviders[dk] ?? attestation.provider,
      proxyParams: params,
      secret: await _secret(dk, reauth),
      nowSeconds: _now(),
    );
    final answer = await _post(op);
    switch (answer.kind) {
      case rust.ApiDelegateOpAnswerKind.requestRefused:
        throw _requestRefused(answer);
      case rust.ApiDelegateOpAnswerKind.rejected:
        return _registerRejected(answer);
      case rust.ApiDelegateOpAnswerKind.accepted:
      case rust.ApiDelegateOpAnswerKind.alreadyApplied:
      case rust.ApiDelegateOpAnswerKind.noVerdict:
        return _settleRegistration(scope, dk);
    }
  }, failure: 'the registration failed'); // l10n-ignore: error detail for logs

  @override
  Future<List<DelegateRound>> rounds() => _call(() async {
    final scope = await _scope();
    final index = await _entryIndex(scope);
    final entry = index == null ? null : await _prove(index);
    return [
      for (final round in await _roundList())
        await _roundView(scope, round, index, entry),
    ];
  });

  @override
  Future<DelegateRound> round(String roundId) => _call(() async {
    final scope = await _scope();
    final index = await _entryIndex(scope);
    final entry = index == null ? null : await _prove(index);
    return _roundView(scope, await _findRound(roundId), index, entry);
  });

  @override
  Future<ApiBallotPreflight> preflight(String roundId, List<int> options) =>
      _call(() async {
        final scope = await _scope();
        final index = await _entryIndex(scope);
        if (index == null) {
          return ApiBallotPreflight(
            alreadySubmitted: false,
            options: Uint32List(0),
            sameOptions: false,
          );
        }
        return rust.delegateBallotPreflight(
          scope: scope,
          roundId: roundId,
          delegateIndex: index,
          chainBallot: await _chainBallot(roundId, index, fresh: true),
          options: options,
        );
      });

  @override
  Future<ApiBallotSubmitResult> submitBallot(
    String roundId,
    List<int> options, {
    required DelegateReauthCheck reauth,
    void Function()? onSigned,
  }) => _call(() async {
    final scope = await _scope();
    final index = await _entryIndex(scope);
    if (index == null) {
      throw const DelegateModeException(
        DelegateModeErrorKind.other,
        'no delegate entry on this device',
      );
    }
    final stored = await rust.storedDelegateBallot(
      scope: scope,
      roundId: roundId,
      delegateIndex: index,
    );
    final rust.ApiSignedDelegateOp op;
    if (stored != null) {
      if (!listEquals([...stored.options], options)) {
        throw const DelegateModeException(
          DelegateModeErrorKind.other,
          'a different ballot is already signed for this round',
        );
      }
      // A retry posts the stored op unchanged: nothing new is signed, so
      // no re-auth shows.
      op = stored.op;
    } else {
      op = await _signBallot(scope, roundId, index, options, reauth);
    }
    onSigned?.call();
    try {
      return await _ballotResult(scope, roundId, index, await _post(op));
    } catch (error) {
      // The op is stored, so whatever failed here, the ballot is the one
      // resendStoredBallot keeps sending.
      _log('the stored ballot has no verdict yet', error);
      throw DelegateBallotStoredException(describeDelegateError(error));
    }
  });

  @override
  Future<DelegateBallotResend> resendStoredBallot(String roundId) =>
      _call(() async {
        final scope = await _scope();
        final index = await _entryIndex(scope);
        if (index == null) return const DelegateBallotResend.done();
        final stored = await rust.storedDelegateBallot(
          scope: scope,
          roundId: roundId,
          delegateIndex: index,
        );
        if (stored == null) return const DelegateBallotResend.done();
        final listed = await _chainBallot(roundId, index, fresh: true);
        if (listed != null) {
          // A different listed ballot, from another device, is a conflict:
          // this one never lands.
          final result = await rust.existingDelegateBallotResult(
            scope: scope,
            roundId: roundId,
            delegateIndex: index,
            chainBallot: listed,
          );
          return result != null && result.rejected
              ? DelegateBallotResend.posted(result)
              : const DelegateBallotResend.done();
        }
        final round = await _findRound(roundId);
        if (!round.active) return const DelegateBallotResend.done();
        switch (await _ballotBlock(scope, round, await _prove(index))) {
          case null:
            break;
          case rust_wire.DelegateBallotBlock.suspended:
            // A suspension may be lifted before voting ends.
            return const DelegateBallotResend.blocked();
          case rust_wire.DelegateBallotBlock.retired ||
              rust_wire.DelegateBallotBlock.notRegistered:
            return const DelegateBallotResend.done();
        }
        // The chain's answer, not the device clock, ends the resends
        // (contracts-v1 §11.12): code 4 once voting ended, or the round
        // no longer ACTIVE above.
        final result = await _ballotResult(
          scope,
          roundId,
          index,
          await _post(stored.op, attempts: 1),
        );
        if (result.blocksForNow) {
          // The proof said the entry could ballot; check again until a
          // lift.
          return const DelegateBallotResend.blocked();
        }
        return DelegateBallotResend.posted(result);
      });

  @override
  Future<DelegateStoredBallotRounds> storedBallotRounds() => _call(() async {
    final scope = await _scope();
    final index = await _entryIndex(scope);
    if (index == null) return (roundIds: const <String>[], complete: true);
    final read = await _readRounds();
    final roundIds = [
      for (final round in read.rounds)
        if (round.active &&
            await rust.storedDelegateBallot(
                  scope: scope,
                  roundId: round.roundId,
                  delegateIndex: index,
                ) !=
                null)
          round.roundId,
    ];
    return (roundIds: roundIds, complete: read.complete);
  });

  /// The submit result for the vote servers' [answer] to entry [index]'s
  /// ballot in [roundId].
  Future<ApiBallotSubmitResult> _ballotResult(
    rust.ApiDelegateModeScope scope,
    String roundId,
    int index,
    rust.ApiDelegateOpAnswer answer,
  ) async {
    switch (answer.kind) {
      case rust.ApiDelegateOpAnswerKind.accepted:
        _ballotLists.forget(roundId);
        return const ApiBallotSubmitResult(kind: ApiBallotSubmitKind.accepted);
      case rust.ApiDelegateOpAnswerKind.requestRefused:
        throw _requestRefused(answer);
      case rust.ApiDelegateOpAnswerKind.rejected:
        final rejection = ApiBallotSubmitResult(
          kind: ApiBallotSubmitKind.rejected,
          codespace: answer.codespace ?? '',
          code: answer.code ?? 0,
          reason: answer.detail ?? '',
        );
        // The cached proof missed a suspension; the next read proves the
        // entry again.
        if (rejection.blocksForNow) _proof = null;
        return rejection;
      case rust.ApiDelegateOpAnswerKind.noVerdict:
        throw const DelegateModeException(
          DelegateModeErrorKind.unavailable,
          'no verdict on the ballot',
        );
      case rust.ApiDelegateOpAnswerKind.alreadyApplied:
        return _existingBallot(scope, roundId, index);
    }
  }

  @override
  Future<DelegateRetireResult> retire({required DelegateReauthCheck reauth}) =>
      _call(() async {
        final scope = await _scope();
        final held = await rust.deviceDelegateKey(scope: scope);
        final index = held?.delegateIndex;
        if (held == null || index == null) {
          throw const DelegateModeException(
            DelegateModeErrorKind.other,
            'no delegate entry on this device',
          );
        }
        try {
          final op = await rust.buildDelegateRetireOp(
            scope: scope,
            entry: await _prove(index, fresh: true),
            secret: await _secret(held.key.dk, reauth),
          );
          final answer = await _post(op);
          switch (answer.kind) {
            case rust.ApiDelegateOpAnswerKind.noVerdict:
              throw const DelegateModeException(
                DelegateModeErrorKind.unavailable,
                'no verdict on the retirement',
              );
            case rust.ApiDelegateOpAnswerKind.requestRefused:
              throw _requestRefused(answer);
            case rust.ApiDelegateOpAnswerKind.rejected:
              return DelegateRetireResult.rejected(
                codespace: answer.codespace ?? '',
                code: answer.code ?? 0,
                reason: answer.detail ?? '',
              );
            case rust.ApiDelegateOpAnswerKind.alreadyApplied:
              return const DelegateRetireResult.retired();
            case rust.ApiDelegateOpAnswerKind.accepted:
              return await _settleRetire(index);
          }
        } finally {
          _proof = null;
        }
      }, failure: 'the retirement failed'); // l10n-ignore: error detail for logs

  /// Signs [options] as entry [index]'s ballot for [roundId] with the
  /// entry's key, read after [reauth] only for this.
  Future<rust.ApiSignedDelegateOp> _signBallot(
    rust.ApiDelegateModeScope scope,
    String roundId,
    int index,
    List<int> options,
    DelegateReauthCheck reauth,
  ) async {
    final round = await _findRound(roundId);
    final entry = await _prove(index, fresh: true);
    final held = await rust.deviceDelegateKey(scope: scope);
    if (held == null || await _ballotBlock(scope, round, entry) != null) {
      throw const DelegateModeException(
        DelegateModeErrorKind.other,
        "this device cannot sign the round's ballot",
      );
    }
    return rust.signDelegateBallot(
      scope: scope,
      round: _timing(round),
      entry: entry,
      proposals: [
        for (final proposal in round.proposals)
          rust_session.ApiProposalRosterEntry(
            proposalId: proposal.id,
            numOptions: proposal.options.length,
          ),
      ],
      options: options,
      secret: await _secret(held.key.dk, reauth),
      nowSeconds: _now(),
    );
  }

  /// Why the device cannot sign [round]'s ballot for the proven [entry],
  /// or null when it can.
  Future<rust_wire.DelegateBallotBlock?> _ballotBlock(
    rust.ApiDelegateModeScope scope,
    DelegateModeRound round,
    rust_proofs.ApiProvenRegistryEntry entry,
  ) async => (await rust.delegateRoundView(
    scope: scope,
    round: _timing(round),
    entry: entry,
    chainBallot: null,
    poolShareCount: null,
    nowSeconds: _now(),
  )).ballotBlock;

  /// Settles a code 57 answer from the delegate's ballot in the round's
  /// whole list, reading the list again while it does not show it yet.
  Future<ApiBallotSubmitResult> _existingBallot(
    rust.ApiDelegateModeScope scope,
    String roundId,
    int index,
  ) async {
    for (var attempt = 0; attempt < maxPostAttempts; attempt++) {
      if (attempt > 0) await _delay(pollInterval);
      final result = await rust.existingDelegateBallotResult(
        scope: scope,
        roundId: roundId,
        delegateIndex: index,
        chainBallot: await _chainBallot(roundId, index, fresh: true),
      );
      if (result != null) return result;
    }
    throw const DelegateModeException(
      DelegateModeErrorKind.unavailable,
      'the ballot list does not show the stored ballot yet',
    );
  }

  /// Follows a retire op CheckTx accepted until the entry, proven again,
  /// is retired (contracts-v1 section 11.12). Past [settleTimeout] the call
  /// is unavailable and a later status read shows the retirement.
  Future<DelegateRetireResult> _settleRetire(int index) async {
    for (var poll = 0; poll < _maxPolls; poll++) {
      if (poll > 0) await _delay(pollInterval);
      final rust_wire.DelegateModeStatus? status;
      try {
        status = await rust.delegateModeStatus(
          scope: await _scope(),
          entry: await _prove(index, fresh: true),
        );
      } on DelegateModeException catch (error) {
        if (error.kind != DelegateModeErrorKind.cannotVerify) rethrow;
        continue;
      }
      if (status?.entry?.status == rust_wire.DelegateEntryStatus.retired) {
        return const DelegateRetireResult.retired();
      }
    }
    throw const DelegateModeException(
      DelegateModeErrorKind.unavailable,
      'the retirement has not landed yet',
    );
  }

  /// Follows a posted register op of key [dk] until the lookup by key names
  /// an entry whose proof holds the key (contracts-v1 section 11.12),
  /// resending the stored op byte for byte while the chain shows nothing.
  /// Past [settleTimeout] the call is unavailable and the stored op settles
  /// on a later status read.
  Future<DelegateRegisterResult> _settleRegistration(
    rust.ApiDelegateModeScope scope,
    String dk,
  ) async {
    _proof = null;
    for (var poll = 0; poll < _maxPolls; poll++) {
      if (poll > 0) {
        await _delay(pollInterval);
        if (poll % _resendEvery == 0) {
          final pending = await rust.pendingDelegateRegisterOp(scope: scope);
          if (pending != null) {
            final answer = await _post(pending, attempts: 1);
            if (answer.kind == rust.ApiDelegateOpAnswerKind.rejected) {
              return _registerRejected(answer);
            }
          }
        }
      }
      try {
        final index = await _lookUp(dk);
        if (index == null) continue;
        final status = await rust.delegateModeStatus(
          scope: scope,
          entry: await _prove(index, fresh: true),
        );
        // The proof trails the lookup by a block; it is proven again.
        if (status?.entry case final entry?) {
          return DelegateRegisterResult.registered(
            delegateIndex: entry.delegateIndex,
          );
        }
      } on DelegateModeException catch (error) {
        if (error.kind == DelegateModeErrorKind.other) rethrow;
      } catch (error) {
        if (error is rust.ApiDelegateModeError &&
            error.kind != rust.ApiDelegateModeErrorKind.chainAnswer &&
            error.kind != rust.ApiDelegateModeErrorKind.entryUnverifiable) {
          rethrow;
        }
        _log('the registration is not settled yet', error);
      }
    }
    throw const DelegateModeException(
      DelegateModeErrorKind.unavailable,
      'the registration has not settled yet',
    );
  }

  /// The registration result for a register op the chain rejected. The
  /// stored op stays: only a proven entry or the user's start over clears
  /// it.
  DelegateRegisterResult _registerRejected(rust.ApiDelegateOpAnswer answer) =>
      DelegateRegisterResult.rejected(
        codespace: answer.codespace ?? '',
        code: answer.code ?? 0,
        reason: answer.detail ?? '',
      );

  /// Posts [op] to the vote servers, resending the same body after an
  /// answer without a verdict, at most [attempts] times.
  Future<rust.ApiDelegateOpAnswer> _post(
    rust.ApiSignedDelegateOp op, {
    int attempts = maxPostAttempts,
  }) async {
    final api = await _host.voteServers();
    final path = await rust.delegateOpPath();
    for (var attempt = 1; ; attempt++) {
      rust.ApiDelegateOpAnswer answer;
      try {
        final reply = await api.postChainBody(path, op.body);
        answer = await rust.parseDelegateOpAnswer(
          op: op.kind,
          status: reply.statusCode,
          body: reply.body,
        );
      } catch (error) {
        if (error is ArgumentError) rethrow;
        _log('a delegate op got no answer', error);
        answer = const rust.ApiDelegateOpAnswer(
          kind: rust.ApiDelegateOpAnswerKind.noVerdict,
        );
      }
      if (answer.kind != rust.ApiDelegateOpAnswerKind.noVerdict ||
          attempt >= attempts) {
        return answer;
      }
      await _delay(pollInterval);
    }
  }

  /// One round's view for entry [index], proven as [entry].
  Future<DelegateRound> _roundView(
    rust.ApiDelegateModeScope scope,
    DelegateModeRound round,
    int? index,
    rust_proofs.ApiProvenRegistryEntry? entry,
  ) async {
    final view = await rust.delegateRoundView(
      scope: scope,
      round: _timing(round),
      entry: entry,
      chainBallot: index == null
          ? null
          : await _chainBallot(round.roundId, index),
      poolShareCount: index == null
          ? null
          : await _shareCount(round.roundId, index),
      nowSeconds: _now(),
    );
    return DelegateRound(
      view: view,
      title: round.title,
      proposals: round.proposals,
    );
  }

  /// Entry [index]'s ballot in [roundId]'s whole ballot list, if listed.
  Future<rust.ApiChainDelegateBallot?> _chainBallot(
    String roundId,
    int index, {
    bool fresh = false,
  }) async {
    int? startAfter = 0;
    for (final page in await _pages(roundId, fresh: fresh)) {
      final search = await rust.delegateBallotPage(
        roundId: roundId,
        startAfter: startAfter!,
        page: page,
        delegateIndex: index,
      );
      if (search.ballot != null) return search.ballot;
      startAfter = search.nextStartAfter;
    }
    return null;
  }

  /// [roundId]'s whole ballot list, page by page, fetched again once older
  /// than [readsMaxAge] or when [fresh].
  Future<List<Uint8List>> _pages(String roundId, {bool fresh = false}) =>
      _ballotLists.pages(
        roundId,
        fresh: fresh,
        open: () async {
          final api = await _host.voteServers();
          return (startAfter) async {
            final answer = await api.getChainAnswer(
              await rust.delegateBallotsPagePath(
                roundId: roundId,
                startAfter: startAfter,
              ),
            );
            if (answer.statusCode != 200) {
              throw DelegateModeException(
                DelegateModeErrorKind.unavailable,
                'the ballot list answered HTTP ${answer.statusCode}',
              );
            }
            return answer.body;
          };
        },
      );

  /// Entry [index]'s pool share count in [roundId], the raw store value.
  /// The count is display only, so a failed read shows the last value read
  /// this session, or none.
  Future<Uint8List?> _shareCount(String roundId, int index) async {
    final key = '$roundId/$index';
    try {
      final value = await _host.storeValue(
        await rust.delegatePoolShareCountKey(
          roundId: roundId,
          delegateIndex: index,
        ),
      );
      _lastCounts[key] = value;
      return value;
    } catch (error) {
      _log('the share count keeps its last value', error);
      return _lastCounts[key];
    }
  }

  /// The proxy rounds the host could read.
  Future<List<DelegateModeRound>> _roundList() async =>
      (await _readRounds()).rounds;

  /// The host's last read of the proxy rounds, kept for [readsMaxAge].
  Future<DelegateModeRounds> _readRounds() async {
    final cached = _rounds;
    if (cached != null && _young(cached.at)) return cached.read;
    final read = await _host.rounds();
    _rounds = (at: _clock(), read: read);
    return read;
  }

  /// The round [roundId] among the proxy rounds.
  Future<DelegateModeRound> _findRound(String roundId) async {
    final id = roundId.toLowerCase();
    for (final round in await _roundList()) {
      if (round.roundId == id) return round;
    }
    throw DelegateModeException(
      DelegateModeErrorKind.other,
      'round $roundId is not a proxy round',
    );
  }

  /// Entry [index] as the participation reader proves it, kept for
  /// [readsMaxAge] unless [fresh].
  Future<rust_proofs.ApiProvenRegistryEntry> _prove(
    int index, {
    bool fresh = false,
  }) async {
    final cached = _proof;
    if (!fresh &&
        cached != null &&
        cached.entry.delegateIndex == index &&
        _young(cached.at)) {
      return cached.entry;
    }
    final List<rust_proofs.ApiProvenRegistryEntry> proven;
    try {
      proven = await _host.proveEntries([index]);
    } on ProxyDelegationError catch (error) {
      throw DelegateModeException(
        error.kind == ProxyDelegationErrorKind.cannotVerify
            ? DelegateModeErrorKind.cannotVerify
            : DelegateModeErrorKind.other,
        error.detail,
      );
    }
    if (proven.length != 1 || proven.single.delegateIndex != index) {
      throw const DelegateModeException(DelegateModeErrorKind.cannotVerify);
    }
    _proof = (at: _clock(), entry: proven.single);
    return proven.single;
  }

  /// The entry the lookup by key names for [dk], or null when the chain
  /// says the key was never registered. Throws when the chain cannot say.
  Future<int?> _lookUp(String dk) async {
    final api = await _host.voteServers();
    final answer = await api.getChainAnswer(
      await rust.delegateByKeyPath(dk: dk),
    );
    return rust.parseDelegateByKeyAnswer(
      dk: dk,
      status: answer.statusCode,
      body: answer.body,
    );
  }

  /// The entry the device's key is recorded in, or null before a proven
  /// entry showed it.
  Future<int?> _entryIndex(rust.ApiDelegateModeScope scope) async =>
      (await rust.deviceDelegateKey(scope: scope))?.delegateIndex;

  /// Refuses while the device already holds a delegate key: it holds one.
  Future<void> _requireNoKey(rust.ApiDelegateModeScope scope) async {
    if (await rust.deviceDelegateKey(scope: scope) != null) {
      throw const DelegateModeException(
        DelegateModeErrorKind.other,
        'the device already holds a delegate key',
      );
    }
  }

  /// Stores [secret] as [dk]'s export, then records the key; a key that
  /// cannot be recorded leaves no secret behind.
  Future<void> _storeKey(
    rust.ApiDelegateModeScope scope,
    String dk,
    String secret,
  ) async {
    await _keys.write(dk, secret);
    try {
      await rust.recordDelegateKey(scope: scope, dk: dk, nowSeconds: _now());
    } catch (_) {
      await _keys.delete(dk);
      rethrow;
    }
  }

  /// [dk]'s secret, read after [reauth] confirmed the user's presence.
  /// Throws [DelegateModeException] with [DelegateModeErrorKind.cancelled]
  /// when the user backs out.
  Future<String> _secret(String dk, DelegateReauthCheck reauth) async {
    if (!await reauth()) {
      throw const DelegateModeException(DelegateModeErrorKind.cancelled);
    }
    final secret = await _keys.read(dk);
    if (secret == null) throw const _NoSigningKey();
    return secret;
  }

  /// The sidecar scope delegate mode uses.
  Future<rust.ApiDelegateModeScope> _scope() async => rust.ApiDelegateModeScope(
    dbPath: await _host.dbPath(),
    network: _host.network,
  );

  /// [round]'s timing as the bridge takes it.
  rust.ApiDelegateRoundTiming _timing(DelegateModeRound round) =>
      rust.ApiDelegateRoundTiming(
        roundId: round.roundId,
        voteEndTime: proxyUnixSeconds(round.voteEnd),
      );

  /// The device time in unix seconds.
  BigInt _now() => proxyUnixSeconds(_clock());

  /// Whether a read made at [at] still serves.
  bool _young(DateTime at) => _clock().difference(at) < readsMaxAge;

  /// How many reads one settle makes at most.
  int get _maxPolls => math.max(
    1,
    (settleTimeout.inMilliseconds / pollInterval.inMilliseconds).ceil(),
  );

  /// Runs [call] holding the voting destructive-operation lease, mapping
  /// its failures as [_guard] does. With [failure], a failure other than a
  /// dismissed re-auth is logged under that name before it is mapped.
  Future<T> _call<T>(Future<T> Function() call, {String? failure}) async {
    final release = _host.beginWork();
    if (release == null) {
      throw const DelegateModeException(
        DelegateModeErrorKind.other,
        'voting data is being deleted',
      );
    }
    try {
      return await _guard(() async {
        try {
          return await call();
        } catch (error) {
          if (failure != null && !delegateSigningCancelled(error)) {
            _log(failure, error);
          }
          rethrow;
        }
      });
    } finally {
      release();
    }
  }
}

/// The device's key has no secret in secure storage.
class _NoSigningKey implements Exception {
  const _NoSigningKey();
}

/// Runs [call], turning zcash_voting's and the network's failures into the
/// screens' exceptions; the screens' own exceptions pass through.
Future<T> _guard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on _NoSigningKey {
    throw const DelegateModeException(
      DelegateModeErrorKind.other,
      "the key's secret is not on this device",
    );
  } on DelegateModeException {
    rethrow;
  } on DelegateKeyImportException {
    rethrow;
  } on DelegateVerifierRefusal {
    rethrow;
  } on rust.ApiDelegateModeError catch (error) {
    throw delegateModeExceptionFromBridge(error);
  } on ProxyDelegationError catch (error) {
    throw DelegateModeException(
      error.kind == ProxyDelegationErrorKind.cannotVerify
          ? DelegateModeErrorKind.cannotVerify
          : DelegateModeErrorKind.other,
      error.detail,
    );
  } catch (error) {
    if (error is VotingHttpException ||
        isRetryableVotingError(error) ||
        isVotingTransportError(error)) {
      _log('a request got no answer', error);
      throw DelegateModeException(
        DelegateModeErrorKind.unavailable,
        describeDelegateError(error),
      );
    }
    rethrow;
  }
}

/// The failure for an op the vote server refused before CheckTx (HTTP 400).
/// It carries no (codespace, code) verdict, so it is not shown as the
/// chain's rejection.
DelegateModeException _requestRefused(rust.ApiDelegateOpAnswer answer) {
  _log('the vote server refused a delegate op', answer.detail ?? '');
  return const DelegateModeException(
    DelegateModeErrorKind.other,
    'the vote server refused the op before CheckTx', // l10n-ignore: error detail for logs
  );
}

/// Logs a passed-over delegate-mode step; names no key or secret, see
/// [describeDelegateError].
void _log(String what, Object error) {
  debugPrint('[zcash] Delegate mode: $what: ${describeDelegateError(error)}');
}

/// The screens' exception for a bridged delegate-mode failure.
DelegateModeException delegateModeExceptionFromBridge(
  rust.ApiDelegateModeError error,
) => DelegateModeException(switch (error.kind) {
  rust.ApiDelegateModeErrorKind.entryUnverifiable =>
    DelegateModeErrorKind.cannotVerify,
  rust.ApiDelegateModeErrorKind.chainAnswer =>
    DelegateModeErrorKind.unavailable,
  rust.ApiDelegateModeErrorKind.other => DelegateModeErrorKind.other,
}, error.kind.name);
