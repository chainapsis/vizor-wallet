import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    show DelegateAttestationSignature;

import 'mock_proxy_delegation_repository.dart';
import 'proxy_values.dart';

/// One round in a [DelegateModeMockScenario]. Fields are mutable so tests
/// can move a round between states; the mock derives what blocks its ballot
/// from the entry's status, as the ballot builder does.
class DelegateMockRound {
  /// Creates the round.
  DelegateMockRound({
    required this.roundId,
    required this.title,
    required this.proposals,
    required this.voteEndTime,
    BigInt? revealedShares,
    ApiDelegateBallotView? ballot,
    this.storedBallot,
  }) : revealedShares = revealedShares ?? BigInt.zero,
       ballot = ballot ?? proxyBallot(ApiDelegateBallotKind.noBallotYet);

  /// Round id.
  final String roundId;

  /// Round title.
  String title;

  /// Questions in id order.
  List<VotingProposalView> proposals;

  /// `vote_end_time`.
  DateTime voteEndTime;

  /// Revealed pool shares R.
  BigInt revealedShares;

  /// The delegate's published ballot.
  ApiDelegateBallotView ballot;

  /// A signed ballot not yet seen on chain.
  List<int>? storedBallot;
}

/// Mutable inputs for [MockDelegateModeRepository]. Tests change fields
/// between steps to move the mock through every state.
class DelegateModeMockScenario {
  /// Creates a scenario.
  DelegateModeMockScenario({
    this.status = const DelegateModeView(),
    List<DelegateMockRound>? rounds,
    Map<String, DelegateModeView>? importable,
    List<Object>? verifierErrors,
    List<DelegateRegisterResult>? registerResults,
    List<ApiBallotSubmitResult>? submitResults,
    this.submitUnavailable = 0,
    List<DelegateRetireResult>? retireResults,
  }) : rounds = rounds ?? [],
       importable = importable ?? {},
       verifierErrors = verifierErrors ?? [],
       registerResults = registerResults ?? [],
       submitResults = submitResults ?? [],
       retireResults = retireResults ?? [];

  /// The device's delegate key and its entry.
  DelegateModeView status;

  /// Proxy rounds, newest first.
  List<DelegateMockRound> rounds;

  /// The status importing each `zvdsk1…` export yields.
  Map<String, DelegateModeView> importable;

  /// Successive attester failures, each a [DelegateVerifierRefusal] or what
  /// attest throws when no attester answers; when empty, attest succeeds.
  List<Object> verifierErrors;

  /// Successive register outcomes; when empty, register lands.
  List<DelegateRegisterResult> registerResults;

  /// Successive submit outcomes; when empty, the chain accepts.
  List<ApiBallotSubmitResult> submitResults;

  /// How many submits fail without an answer before one goes through.
  int submitUnavailable;

  /// Successive Retire outcomes; when empty, the entry retires.
  List<DelegateRetireResult> retireResults;

  /// Makes [MockDelegateModeRepository.createKey] throw.
  Object? createError;

  /// Makes [MockDelegateModeRepository.register] throw after its re-auth.
  Object? registerError;

  /// Makes [MockDelegateModeRepository.retire] throw after its re-auth.
  Object? retireError;
}

/// The mock key number [seed], with the export [mockDelegateSecret] gives.
DelegateKeyInfo mockDelegateKey(int seed) =>
    mockProxyDelegateKey('delegate-key:$seed');

/// The `zvdsk1…` export of [mockDelegateKey] number [seed]; not a real
/// encoding.
String mockDelegateSecret(int seed) => 'zvdsk1mock$seed';

/// The delegate-mode data source of the screen tests.
class MockDelegateModeRepository implements DelegateModeRepository {
  /// Creates a mock over [scenario], reading time from [clock].
  MockDelegateModeRepository(this.scenario, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Inputs; tests may change them between steps.
  final DelegateModeMockScenario scenario;
  final DateTime Function() _clock;
  int _created = 0;

  /// Calls, for assertions.
  int exportCalls = 0;

  /// See [exportCalls].
  int attestCalls = 0;

  /// Registrations that passed their re-auth.
  int registerCalls = 0;

  /// See [exportCalls].
  int preflightCalls = 0;

  /// Retires that passed their re-auth.
  int retireCalls = 0;

  /// See [exportCalls].
  int startOverCalls = 0;

  /// Every ballot submitted after its re-auth, or resent, in order.
  final List<List<int>> submitted = [];

  /// Every stored ballot resent in the background, in order.
  final List<List<int>> resent = [];

  /// Proof links sent to the attester, in order.
  final List<String> proofUrls = [];

  /// The export of the device's key.
  String? secret;

  /// Confirms presence through [reauth] before the key signs.
  Future<void> _unlock(DelegateReauthCheck reauth) async {
    if (!await reauth()) {
      throw const DelegateModeException(DelegateModeErrorKind.cancelled);
    }
  }

  @override
  Future<DelegateModeView> status() async => scenario.status;

  @override
  Future<DelegateKeyInfo> createKey() async {
    if (scenario.createError case final error?) throw error;
    final seed = ++_created;
    secret = mockDelegateSecret(seed);
    final key = mockDelegateKey(seed);
    scenario.status = delegateModeView(key: key);
    return key;
  }

  @override
  Future<DelegateKeyInfo> importKey(String text) async {
    final imported = scenario.importable[text.trim()];
    final key = imported?.key;
    if (imported == null || key == null) {
      throw const DelegateKeyImportException();
    }
    secret = text.trim();
    scenario.status = imported;
    return key;
  }

  @override
  Future<String> exportKey() async {
    exportCalls++;
    final secret = this.secret;
    if (secret == null) {
      throw const DelegateModeException(
        DelegateModeErrorKind.other,
        "the key's secret is not on this device",
      );
    }
    return secret;
  }

  @override
  Future<void> startOver() async {
    startOverCalls++;
    final status = scenario.status;
    if (status.registered && !status.retired) {
      throw const DelegateModeException(
        DelegateModeErrorKind.other,
        "the key's entry is not retired",
      );
    }
    secret = null;
    scenario.status = const DelegateModeView();
  }

  @override
  Future<String> markerText(DelegateKeyInfo key) async =>
      'zcash-vote-delegate v1 ${key.dk}';

  @override
  Future<DelegateAttestation> attest({
    required ProxyDelegateProvider provider,
    required String proofUrl,
    required DelegateKeyInfo key,
  }) async {
    attestCalls++;
    proofUrls.add(proofUrl);
    if (scenario.verifierErrors.isNotEmpty) {
      throw scenario.verifierErrors.removeAt(0);
    }
    final notBefore = BigInt.from(_clock().millisecondsSinceEpoch ~/ 1000);
    return DelegateAttestation(
      key: key,
      provider: provider,
      handle: 'alice_votes',
      proofId: '1790000000000000000',
      attestations: [
        DelegateAttestationSignature(
          verifierId: 1,
          notBefore: notBefore,
          expiresAt: notBefore + BigInt.from(3600),
          sig: 'bW9jaw==',
        ),
      ],
    );
  }

  @override
  Future<DelegateRegisterResult> register(
    DelegateAttestation attestation, {
    required DelegateReauthCheck reauth,
  }) async {
    await _unlock(reauth);
    registerCalls++;
    if (scenario.registerError case final error?) throw error;
    if (scenario.registerResults.isNotEmpty) {
      final scripted = scenario.registerResults.removeAt(0);
      if (scripted is DelegateRegisterRejected) return scripted;
    }
    const index = 17;
    scenario.status = delegateModeView(
      key: attestation.key,
      delegateIndex: index,
      provider: attestation.provider,
      handle: attestation.handle,
      picture: scenario.status.picture,
    );
    return DelegateRegisterResult.registered(delegateIndex: index);
  }

  @override
  Future<List<DelegateRound>> rounds() async {
    return [for (final round in scenario.rounds) _view(round)];
  }

  @override
  Future<DelegateRound> round(String roundId) async {
    return _view(_find(roundId));
  }

  @override
  Future<ApiBallotPreflight> preflight(
    String roundId,
    List<int> options,
  ) async {
    preflightCalls++;
    final stored = _view(_find(roundId)).onChainOptions;
    return ApiBallotPreflight(
      alreadySubmitted: stored != null,
      options: Uint32List.fromList(stored ?? const []),
      sameOptions: stored != null && listEquals(stored, options),
    );
  }

  @override
  Future<ApiBallotSubmitResult> submitBallot(
    String roundId,
    List<int> options, {
    required DelegateReauthCheck reauth,
    void Function()? onSigned,
  }) async {
    final round = _find(roundId);
    final stored = round.storedBallot;
    if (stored != null && !listEquals(stored, options)) {
      // The ballot builder only ever resubmits the identical stored ballot.
      throw const DelegateModeException(
        DelegateModeErrorKind.other,
        'a different ballot is already signed',
      );
    }
    // A resend posts the stored ballot unchanged: nothing new is signed.
    if (stored == null) {
      if (_block() != null) {
        throw const DelegateModeException(
          DelegateModeErrorKind.other,
          "this device cannot sign the round's ballot",
        );
      }
      await _unlock(reauth);
    }
    submitted.add([...options]);
    round.storedBallot = [...options];
    onSigned?.call();
    try {
      return _post(round, options);
    } on DelegateModeException {
      throw const DelegateBallotStoredException();
    }
  }

  @override
  Future<DelegateBallotResend> resendStoredBallot(String roundId) async {
    final round = _find(roundId);
    final stored = round.storedBallot;
    if (stored == null ||
        round.ballot.kind != ApiDelegateBallotKind.noBallotYet) {
      return const DelegateBallotResend.done();
    }
    switch (_block()) {
      case DelegateBallotBlock.suspended:
        return const DelegateBallotResend.blocked();
      case DelegateBallotBlock.retired || DelegateBallotBlock.notRegistered:
        return const DelegateBallotResend.done();
      case null:
        break;
    }
    resent.add([...stored]);
    return DelegateBallotResend.posted(_post(round, stored));
  }

  @override
  Future<DelegateStoredBallotRounds> storedBallotRounds() async => (
    roundIds: [
      for (final round in scenario.rounds)
        if (round.storedBallot != null) round.roundId,
    ],
    complete: true,
  );

  /// Posts [round]'s stored ballot [options] and lands it as the scenario
  /// says.
  ApiBallotSubmitResult _post(DelegateMockRound round, List<int> options) {
    if (scenario.submitUnavailable > 0) {
      scenario.submitUnavailable--;
      throw const DelegateModeException(DelegateModeErrorKind.unavailable);
    }
    final result = scenario.submitResults.isEmpty
        ? ballotSubmit(ApiBallotSubmitKind.accepted)
        : scenario.submitResults.removeAt(0);
    // A rejected ballot stays stored, as the only one the device submits
    // for the round.
    if (result.rejected) return result;
    round.storedBallot = null;
    round.ballot = proxyBallot(ApiDelegateBallotKind.submitted, [...options]);
    return result;
  }

  @override
  Future<DelegateRetireResult> retire({
    required DelegateReauthCheck reauth,
  }) async {
    await _unlock(reauth);
    retireCalls++;
    if (scenario.retireError case final error?) throw error;
    if (scenario.retireResults.isNotEmpty) {
      final scripted = scenario.retireResults.removeAt(0);
      if (scripted is! DelegateRetired) return scripted;
    }
    scenario.status = delegateModeViewWith(
      scenario.status,
      DelegateEntryStatus.retired,
    );
    return const DelegateRetireResult.retired();
  }

  /// The scenario round [roundId].
  DelegateMockRound _find(String roundId) {
    for (final round in scenario.rounds) {
      if (round.roundId == roundId) return round;
    }
    throw DelegateModeException(
      DelegateModeErrorKind.other,
      'unknown round $roundId',
    );
  }

  /// The round as the screens see it.
  DelegateRound _view(DelegateMockRound round) => DelegateRound(
    view: ApiDelegateRound(
      roundId: round.roundId,
      voteEndTime: proxyUnixSeconds(round.voteEndTime),
      revealedShares: round.revealedShares,
      ballot: round.ballot,
      storedBallot: switch (round.storedBallot) {
        final stored? => Uint32List.fromList(stored),
        null => null,
      },
      ballotBlock: _block(),
    ),
    title: round.title,
    proposals: round.proposals,
  );

  /// Why the device cannot sign a ballot, from the entry's status.
  DelegateBallotBlock? _block() => switch (scenario.status.entry?.status) {
    null => DelegateBallotBlock.notRegistered,
    DelegateEntryStatus.active => null,
    DelegateEntryStatus.suspended => DelegateBallotBlock.suspended,
    DelegateEntryStatus.retired => DelegateBallotBlock.retired,
  };
}
