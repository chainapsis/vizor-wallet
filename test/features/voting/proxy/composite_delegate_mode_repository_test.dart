import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_error_log.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegate.dart' as rust;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_retry.dart';

import 'support/delegate_mode_fakes.dart';
import 'support/mock_delegate_mode_repository.dart';
import 'support/proxy_rust_fake.dart';
import 'support/proxy_values.dart';

/// The device time.
final _now = DateTime(2026, 10, 7, 12);

/// The running round's id.
final _round = '0a' * 32;

/// A closed round's id.
final _closed = '0b' * 32;

/// Expects [future] to fail as delegate mode [kind].
Future<void> _expectMode(Future<Object?> future, DelegateModeErrorKind kind) =>
    expectLater(
      future,
      throwsA(
        isA<DelegateModeException>().having(
          (error) => error.kind,
          'kind',
          kind,
        ),
      ),
    );

/// Requests that got no answer, by what failed: Tor refusing a loopback
/// host as the Tor bridge throws it, a refused connection, a timeout and a
/// TLS failure.
final _transportFailures = <String, Object>{
  'a Tor refusal': 'Tor: connection to 127.0.0.1:1317 refused by the exit',
  'a refused connection': const SocketException('Connection refused'),
  'a timeout': TimeoutException('Network HTTP request timed out'),
  'a TLS failure': const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
};

/// A vote server answer refusing the body before CheckTx: HTTP 400 with no
/// (codespace, code) verdict.
VotingHttpResponse _refusedRequest() =>
    fakeJsonAnswer({'error': 'invalid request'}, status: 400);

/// The op kind each posted body carries.
List<String> _postKinds(FakeDelegateChain chain) => [
  for (final post in chain.posts) post.keys.single,
];

void main() {
  useProxyRustFake();

  late RealDelegateMode mode;

  setUp(() {
    mode = RealDelegateMode(now: _now);
    mode.host.rounds_.addAll([
      fakeDelegateRound(
        roundId: _round,
        voteEnd: _now.add(const Duration(days: 3)),
      ),
      fakeDelegateRound(
        roundId: _closed,
        voteEnd: _now.subtract(const Duration(days: 20)),
        title: 'Q3 funding',
        active: false,
      ),
    ]);
  });

  /// The key info of fake key [dk].
  DelegateKeyInfo info(String dk) =>
      DelegateKeyInfo(dk: dk, fingerprint: fakeFingerprint(dk));

  /// Attests [dk] from [handle]'s post on X.
  Future<DelegateAttestation> attestX(String dk, {String handle = 'alice'}) =>
      mode.repository.attest(
        provider: ProxyDelegateProvider.x,
        proofUrl: 'https://x.com/$handle/status/1790000000000000000',
        key: info(dk),
      );

  group('the device key', () {
    test('a created key is stored as its export, then recorded, and the '
        'device holds only one', () async {
      final key = await mode.repository.createKey();
      expect(mode.keys.secrets, {key.dk: startsWith('zvdsk1')});
      expect(mode.bridge.heldDk, key.dk);
      expect(await mode.repository.exportKey(), mode.keys.secrets[key.dk]);

      await _expectMode(
        mode.repository.createKey(),
        DelegateModeErrorKind.other,
      );
      await _expectMode(
        mode.repository.importKey(mockDelegateSecret(2)),
        DelegateModeErrorKind.other,
      );
      expect(mode.keys.secrets.keys, [key.dk]);
    });

    test('import takes only an export, stores it without a request, and '
        'the next status finds its entry by key', () async {
      for (final text in ['', mockDelegateKey(1).dk, 'abandon abandon about']) {
        await expectLater(
          mode.repository.importKey(text),
          throwsA(isA<DelegateKeyImportException>()),
        );
      }
      expect(mode.keys.secrets, isEmpty);
      expect(mode.bridge.heldDk, isNull);

      final entry = mode.chain.register('alice', mockDelegateKey(1).dk);
      final key = await mode.repository.importKey(
        ' ${mockDelegateSecret(1)}\n',
      );
      expect(key.dk, entry.dk);
      expect(mode.keys.secrets, {entry.dk: mockDelegateSecret(1)});
      expect(mode.chain.reads, isEmpty);

      final status = await mode.repository.status();
      expect(
        (
          status.entry?.delegateIndex,
          status.entry?.handle,
          status.entry?.provider,
        ),
        (17, 'alice', ProxyDelegateProvider.x),
      );
      expect(mode.bridge.heldIndex, 17);
    });

    test('a key that cannot be recorded leaves no export behind', () async {
      mode.bridge.recordFailure = StateError('disk full');
      await expectLater(mode.repository.createKey(), throwsStateError);
      expect(mode.keys.secrets, isEmpty);
    });
  });

  group('status', () {
    test('a lookup the chain cannot answer, or names another key\'s entry, '
        'leaves the key unregistered without failing', () async {
      mode.holdsKey(1);
      mode.chain.lookupsDown = true;
      expect((await mode.repository.status()).registered, isFalse);

      mode.chain.lookupsDown = false;
      mode.chain.register('bob', mockDelegateKey(2).dk);
      mode.chain.usedKeys[mockDelegateKey(1).dk] = 17;
      expect((await mode.restarted().status()).registered, isFalse);
      expect(mode.bridge.heldIndex, isNull);
    });

    test('the handle, provider and status come from the proven entry, and '
        'an entry the reader cannot prove is cannot-verify', () async {
      final entry = mode.registeredKey(1, handle: 'alice_votes');
      mode.host.pictures[17] = ProxyDelegatePicture.of(Uint8List(4));
      var status = await mode.repository.status();
      expect(
        (status.entry?.handle, status.entry?.status, status.picture != null),
        ('alice_votes', DelegateEntryStatus.active, true),
      );
      expect(mode.chain.reads, isEmpty, reason: 'the entry is recorded');

      entry.status = rust_wire.DelegateEntryStatus.suspended;
      status = await mode.restarted().status();
      expect((status.suspended, status.retired), (true, false));
      entry.status = rust_wire.DelegateEntryStatus.retired;
      expect((await mode.restarted().status()).retired, isTrue);

      mode.host.proofsFail = true;
      await _expectMode(
        mode.restarted().status(),
        DelegateModeErrorKind.cannotVerify,
      );
    });
  });

  group('attester', () {
    test('the marker has one form, and an attestation carries the handle '
        'and proof post the attester read', () async {
      final dk = mode.holdsKey(1);
      expect(
        await mode.repository.markerText(info(dk)),
        'zcash-vote-delegate v1 $dk',
      );
      final attestation = await mode.repository.attest(
        provider: ProxyDelegateProvider.gitHub,
        proofUrl: 'https://gist.github.com/alice/aa5a315d',
        key: info(dk),
      );
      expect(attestation.key.dk, dk);
      expect(attestation.provider, rust_wire.ProxyDelegateProvider.gitHub);
      expect((attestation.handle, attestation.proofId), ('alice', 'aa5a315d'));
      expect(mode.verifier.requests.single['provider'], 2);
    });
  });

  group('verifier failover', () {
    late DelegateKeyInfo key;

    setUp(() {
      final dk = mode.holdsKey(1);
      key = DelegateKeyInfo(dk: dk, fingerprint: fakeFingerprint(dk));
      mode.host.verifierUrls = const [
        'https://verifier-a.example',
        'https://verifier-b.example',
      ];
    });

    /// Attests [key] from alice's post on X.
    Future<DelegateAttestation> attest() => mode.repository.attest(
      provider: ProxyDelegateProvider.x,
      proofUrl: 'https://x.com/alice/status/1',
      key: key,
    );

    test(
      'a 200 without the attestation moves on to the next verifier',
      () async {
        mode.verifier.rawAnswers.add((status: 200, body: '{}'));
        final attestation = await attest();
        expect(attestation.handle, 'alice');
        expect(mode.verifier.hosts, [
          'verifier-a.example',
          'verifier-b.example',
        ]);
      },
    );

    test('a paired refusal is final', () async {
      mode.verifier.refusals.add((
        status: 409,
        code: 'marker_mismatch',
        retryAfter: null,
      ));
      await expectLater(
        attest(),
        throwsA(
          isA<DelegateVerifierRefusal>().having(
            (e) => e.error,
            'error',
            DelegateVerifierError.markerMismatch,
          ),
        ),
      );
      expect(mode.verifier.hosts, ['verifier-a.example']);
    });
  });

  group('register', () {
    test(
      'a registration is signed after one re-auth, posted once and '
      'settles when the lookup by key names an entry holding the key',
      () async {
        final dk = mode.holdsKey(1);
        final result = await mode.repository.register(
          await attestX(dk),
          reauth: mode.reauth,
        );
        expect(
          result,
          const DelegateRegisterResult.registered(delegateIndex: 17),
        );
        expect(_postKinds(mode.chain), ['register']);
        expect(mode.reauths, 1);
        expect(mode.bridge.signedWith, [dk]);
        final entry = mode.chain.entries[17]!;
        expect((entry.handle, entry.dk), ('alice', dk));
        final status = await mode.repository.status();
        expect(
          (status.entry?.delegateIndex, status.entry?.handle),
          (17, 'alice'),
        );
        expect(status.registrationPending, isFalse);
      },
    );

    test('a dismissed re-auth signs and posts nothing', () async {
      final dk = mode.holdsKey(1);
      final attestation = await attestX(dk);
      mode.reauthAllows = false;
      await _expectMode(
        mode.repository.register(attestation, reauth: mode.reauth),
        DelegateModeErrorKind.cancelled,
      );
      expect(mode.keys.reads, 0);
      expect(mode.bridge.signedWith, isEmpty);
      expect(mode.chain.posts, isEmpty);
    });

    test('a proof that trails the lookup by key is proven again', () async {
      final dk = mode.holdsKey(1);
      final attestation = await attestX(dk);
      mode.host.laggingProofs = 2;
      expect(
        await mode.repository.register(attestation, reauth: mode.reauth),
        const DelegateRegisterResult.registered(delegateIndex: 17),
      );
      expect(mode.host.proofRequests, hasLength(3));
    });

    test('code 61 settles from the entry that holds the key', () async {
      final dk = mode.holdsKey(1);
      final attestation = await attestX(dk);
      // An earlier post of the same op landed.
      mode.chain.register('alice', dk);
      expect(
        await mode.repository.register(attestation, reauth: mode.reauth),
        const DelegateRegisterResult.registered(delegateIndex: 17),
      );
    });

    test('an answer without a verdict resends the same body', () async {
      final dk = mode.holdsKey(1);
      final attestation = await attestX(dk);
      mode.chain.postAnswers.addAll([
        const SocketException('reset'),
        fakeJsonAnswer({'error': 'busy'}, status: 503),
      ]);
      expect(
        await mode.repository.register(attestation, reauth: mode.reauth),
        const DelegateRegisterResult.registered(delegateIndex: 17),
      );
      expect(mode.chain.posts, hasLength(3));
      expect({
        for (final post in mode.chain.posts) jsonEncode(post),
      }, hasLength(1));
    });

    test('a registration that has not landed is left pending, resent while '
        'it settles, and settles on a later status read', () async {
      final dk = mode.holdsKey(1);
      final attestation = await attestX(dk);
      mode.chain.landOps = false;
      await _expectMode(
        mode.repository.register(attestation, reauth: mode.reauth),
        DelegateModeErrorKind.unavailable,
      );
      expect(mode.chain.posts.length, greaterThan(1));
      expect({
        for (final post in mode.chain.posts) jsonEncode(post),
      }, hasLength(1));
      var status = await mode.repository.status();
      expect((status.registered, status.registrationPending), (false, true));

      mode.chain.land();
      status = await mode.repository.status();
      expect(
        (status.entry?.delegateIndex, status.registrationPending),
        (17, false),
      );
    });

    test('an attestation that does not bind the post signs nothing', () async {
      final dk = mode.holdsKey(1);
      final attestation = await mode.repository.attest(
        provider: ProxyDelegateProvider.gitHub,
        proofUrl: 'https://gist.github.com/alice/aa5a315d',
        key: info(dk),
      );
      // The attester answered for another provider than the one asked.
      await _expectMode(
        mode.repository.register(
          DelegateAttestation(
            key: attestation.key,
            provider: rust_wire.ProxyDelegateProvider.x,
            handle: attestation.handle,
            proofId: attestation.proofId,
            attestations: attestation.attestations,
          ),
          reauth: mode.reauth,
        ),
        DelegateModeErrorKind.other,
      );
      expect(mode.chain.posts, isEmpty);
    });
  });

  group('rounds and ballots', () {
    late FakeEntry entry;

    setUp(() {
      entry = mode.registeredKey(1);
      mode.chain.shareCounts[_round] = {17: 37};
    });

    /// Stores a signed ballot of [1, 2] whose posts got no answer.
    Future<void> storeUnanswered() async {
      mode.chain.postAnswers.addAll(
        List.filled(3, const SocketException('reset')),
      );
      await expectLater(
        mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        throwsA(isA<DelegateBallotStoredException>()),
      );
    }

    test(
      'each proxy round shows the count, the ballot and what blocks it',
      () async {
        mode.chain.ballots[_closed] = {
          17: [0, 2],
        };
        final rounds = await mode.repository.rounds();
        expect(rounds.map((round) => round.view.roundId), [_round, _closed]);
        final [running, closed] = rounds;
        expect(running.title, 'Q4 funding');
        expect(running.proposals, hasLength(2));
        expect(running.view.revealedShares, BigInt.from(37));
        expect(
          running.view.ballot,
          isProxyBallot(ApiDelegateBallotKind.noBallotYet),
        );
        expect(running.view.ballotBlock, isNull);
        expect(
          closed.view.ballot,
          isProxyBallot(ApiDelegateBallotKind.counted, [0, 2]),
        );
        expect(closed.view.revealedShares, BigInt.zero);
        expect(
          (await mode.repository.round(_round)).view.revealedShares,
          BigInt.from(37),
        );
      },
    );

    test('preflight compares with the ballot on chain', () async {
      Matcher found(bool submitted, List<int> options, bool same) =>
          isA<ApiBallotPreflight>()
              .having((p) => p.alreadySubmitted, 'alreadySubmitted', submitted)
              .having((p) => p.options, 'options', options)
              .having((p) => p.sameOptions, 'sameOptions', same);
      Future<ApiBallotPreflight> preflight(List<int> options) =>
          mode.repository.preflight(_round, options);

      expect(await preflight([0, 1]), found(false, [], false));
      mode.chain.ballots[_round] = {
        17: [0, 1],
      };
      expect(await preflight([0, 1]), found(true, [0, 1], true));
      expect(await preflight([1, 1]), found(true, [0, 1], false));
    });

    test("a ballot is signed with the entry's key after one re-auth and "
        'posted once', () async {
      expect(
        await mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        ballotSubmit(ApiBallotSubmitKind.accepted),
      );
      expect(mode.bridge.signedWith, [entry.dk]);
      expect((mode.reauths, mode.keys.reads), (1, 1));
      expect(mode.chain.ballots[_round]?[17], [1, 2]);
      final round = await mode.repository.round(_round);
      expect(
        round.view.ballot,
        isProxyBallot(ApiDelegateBallotKind.submitted, [1, 2]),
      );
    });

    test('an unanswered ballot stays stored and a retry resends it '
        'without re-auth or the key', () async {
      mode.chain.postAnswers.addAll([
        const SocketException('reset'),
        const SocketException('reset'),
        const SocketException('reset'),
      ]);
      await _expectMode(
        mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        DelegateModeErrorKind.unavailable,
      );
      expect((await mode.repository.round(_round)).view.storedBallot, [1, 2]);
      await _expectMode(
        mode.repository.submitBallot(_round, [0, 0], reauth: mode.reauth),
        DelegateModeErrorKind.other,
      );

      mode.keys.unlocked = false;
      expect(
        await mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        ballotSubmit(ApiBallotSubmitKind.accepted),
      );
      expect((mode.reauths, mode.keys.reads), (1, 1), reason: 'nothing signs');
      expect(
        {for (final post in mode.chain.posts) jsonEncode(post)},
        hasLength(1),
        reason: 'the same body',
      );
    });

    test('a background resend posts the stored bytes once while the list '
        'lacks them, without re-auth or the key', () async {
      expect(
        await mode.repository.resendStoredBallot(_round),
        const DelegateBallotResend.done(),
      );
      expect(mode.chain.posts, isEmpty, reason: 'nothing stored');
      mode.chain.postAnswers.addAll(
        List.filled(4, const SocketException('reset')),
      );
      await expectLater(
        mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        throwsA(isA<DelegateBallotStoredException>()),
      );
      await _expectMode(
        mode.repository.resendStoredBallot(_round),
        DelegateModeErrorKind.unavailable,
      );
      expect(mode.chain.posts, hasLength(4), reason: 'one post per resend');

      mode.keys.unlocked = false;
      expect(
        await mode.repository.resendStoredBallot(_round),
        DelegateBallotResend.posted(ballotSubmit(ApiBallotSubmitKind.accepted)),
      );
      expect((mode.reauths, mode.keys.reads), (1, 1), reason: 'nothing signs');
      expect(
        {for (final post in mode.chain.posts) jsonEncode(post)},
        hasLength(1),
        reason: 'the same body',
      );
      expect(
        await mode.repository.resendStoredBallot(_round),
        const DelegateBallotResend.done(),
      );
      expect(mode.chain.posts, hasLength(5), reason: 'listed, so not sent');
    });

    test('a resend that finds another device\'s ballot listed reports the '
        'conflict, and one that finds its own is done', () async {
      await storeUnanswered();
      final posted = mode.chain.posts.length;
      mode.chain.ballots[_round] = {
        17: [0, 0],
      };
      expect(
        await mode.repository.resendStoredBallot(_round),
        DelegateBallotResend.posted(
          ballotRejected(57, reason: 'a different ballot is listed'),
        ),
      );
      mode.chain.ballots[_round] = {
        17: [1, 2],
      };
      expect(
        await mode.repository.resendStoredBallot(_round),
        const DelegateBallotResend.done(),
      );
      expect(mode.chain.posts, hasLength(posted), reason: 'listed, not sent');
    });

    test('after a restart the running rounds with a stored ballot are '
        'found again', () async {
      await storeUnanswered();
      mode.bridge.stored['$_closed/17'] = (
        options: const [0, 2],
        op: const <String, dynamic>{},
      );

      expect((await mode.restarted().storedBallotRounds()).roundIds, [
        _round,
      ], reason: 'the closed round is over');
    });

    test('a device without a delegate key finds no stored ballot and reads '
        'no round', () async {
      final fresh = RealDelegateMode(now: _now);
      fresh.host.rounds_.addAll(mode.host.rounds_);
      expect((await fresh.repository.storedBallotRounds()).roundIds, isEmpty);
      expect(fresh.host.roundReads, 0);
      expect(fresh.chain.reads, isEmpty);
    });

    test('a background resend ends on the chain\'s word, not the device '
        'clock', () async {
      await storeUnanswered();
      final posted = mode.chain.posts.length;
      // A fast clock: past the vote end, but the round is still ACTIVE.
      mode.now = _now.add(const Duration(days: 4));
      final repository = mode.restarted();
      expect((await repository.storedBallotRounds()).roundIds, [_round]);
      expect(
        await repository.resendStoredBallot(_round),
        isA<DelegateBallotResendPosted>(),
      );
      expect(mode.chain.posts, hasLength(posted + 1));

      mode.host.rounds_[0] = fakeDelegateRound(
        roundId: _round,
        voteEnd: _now.add(const Duration(days: 3)),
        active: false,
      );
      mode.chain.ballots.remove(_round);
      final closed = mode.restarted();
      expect((await closed.storedBallotRounds()).roundIds, isEmpty);
      expect(
        await closed.resendStoredBallot(_round),
        const DelegateBallotResend.done(),
      );
      expect(mode.chain.posts, hasLength(posted + 1));
    });

    test('a suspension the chain answers is checked again with a new '
        'proof; other rejections stay final', () async {
      await storeUnanswered();
      VotingHttpResponse refusal(int code) => fakeJsonAnswer({
        'code': code,
        'codespace': 'vote',
        'log': 'refused with $code',
      }, status: 422);
      // The second post gets no answer, so nothing lands meanwhile.
      mode.chain.postAnswers.addAll([
        refusal(54),
        const SocketException('reset'),
      ]);
      expect(
        await mode.repository.resendStoredBallot(_round),
        const DelegateBallotResend.blocked(),
      );
      final proofs = mode.host.proofRequests.length;
      await _expectMode(
        mode.repository.resendStoredBallot(_round),
        DelegateModeErrorKind.unavailable,
      );
      expect(
        mode.host.proofRequests.length,
        greaterThan(proofs),
        reason: 'the suspension drops the cached proof',
      );
      mode.chain.postAnswers.add(refusal(58));
      expect(
        await mode.repository.resendStoredBallot(_round),
        isA<DelegateBallotResendPosted>().having(
          (resend) => resend.result,
          'result',
          isA<ApiBallotSubmitResult>()
              .having((r) => r.rejected, 'rejected', isTrue)
              .having((r) => r.code, 'code', 58),
        ),
      );
    });

    test('code 57 is success only when the list shows this ballot', () async {
      mode.chain.ballots[_round] = {
        17: [1, 2],
      };
      expect(
        await mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        ballotSubmit(ApiBallotSubmitKind.alreadyAccepted),
      );

      mode.bridge.stored.clear();
      mode.chain.ballots[_round] = {
        17: [0, 0],
      };
      expect(
        await mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        ballotRejected(57, reason: 'a different ballot is listed'),
      );
    });

    test('a suspended or retired entry signs nothing, and its stored ballot '
        'waits while suspended and is given up once retired', () async {
      await storeUnanswered();
      final posted = mode.chain.posts.length;
      for (final (status, block, resend) in [
        (
          rust_wire.DelegateEntryStatus.suspended,
          DelegateBallotBlock.suspended,
          const DelegateBallotResend.blocked(),
        ),
        (
          rust_wire.DelegateEntryStatus.retired,
          DelegateBallotBlock.retired,
          const DelegateBallotResend.done(),
        ),
      ]) {
        entry.status = status;
        final repository = mode.restarted();
        expect((await repository.round(_round)).view.ballotBlock, block);
        expect(await repository.resendStoredBallot(_round), resend);
        mode.bridge.stored.clear();
        await _expectMode(
          repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
          DelegateModeErrorKind.other,
        );
        mode.bridge.stored['$_round/17'] = (
          options: const [1, 2],
          op: const {
            'ballot': {'round': '', 'delegate_index': 17, 'dk': ''},
          },
        );
      }
      expect(mode.chain.posts, hasLength(posted), reason: 'nothing is posted');
      expect(mode.reauths, 1, reason: 'a blocked ballot asks for nothing');
    });
  });

  group('retire', () {
    test("Retire is one op signed by the entry's key after one re-auth, "
        'and counts once the entry is proven retired', () async {
      final entry = mode.registeredKey(1);
      expect(
        await mode.repository.retire(reauth: mode.reauth),
        const DelegateRetireResult.retired(),
      );
      expect(_postKinds(mode.chain), ['retire']);
      expect(mode.reauths, 1);
      expect(mode.bridge.signedWith, [entry.dk]);
      expect(entry.status, rust_wire.DelegateEntryStatus.retired);
      expect((await mode.repository.status()).retired, isTrue);
    });

    test('code 55 counts as retired, and a suspended entry cannot retire '
        'itself', () async {
      final entry = mode.registeredKey(1);
      entry.status = rust_wire.DelegateEntryStatus.suspended;
      expect(
        await mode.repository.retire(reauth: mode.reauth),
        isA<DelegateRetireRejected>().having((r) => r.code, 'code', 54),
      );
      entry.status = rust_wire.DelegateEntryStatus.retired;
      expect(
        await mode.repository.retire(reauth: mode.reauth),
        const DelegateRetireResult.retired(),
      );
    });

    test('a dismissed re-auth, or a device without an entry, retires '
        'nothing', () async {
      await _expectMode(
        mode.repository.retire(reauth: mode.reauth),
        DelegateModeErrorKind.other,
      );
      mode.registeredKey(1);
      mode.reauthAllows = false;
      await _expectMode(
        mode.repository.retire(reauth: mode.reauth),
        DelegateModeErrorKind.cancelled,
      );
      expect(mode.chain.posts, isEmpty);
    });
  });

  group('starting over', () {
    test('a device whose entry is retired forgets its key and can register '
        'a new one', () async {
      final entry = mode.registeredKey(1);
      await _expectMode(
        mode.repository.startOver(),
        DelegateModeErrorKind.other,
      );
      expect(
        mode.bridge.heldDk,
        entry.dk,
        reason: 'a live entry keeps its key',
      );

      await mode.repository.retire(reauth: mode.reauth);
      await mode.repository.startOver();
      expect(mode.bridge.heldDk, isNull);
      expect(mode.keys.secrets, isEmpty);
      expect((await mode.repository.status()).key, isNull);

      final next = await mode.repository.createKey();
      expect(
        await mode.repository.register(
          await attestX(next.dk),
          reauth: mode.reauth,
        ),
        const DelegateRegisterResult.registered(delegateIndex: 18),
      );
    });

    test('a key without a proven entry goes with its stored op, whatever '
        'the chain or the clock says', () async {
      final dk = mode.holdsKey(1);
      mode.verifier.nowSeconds = _now.millisecondsSinceEpoch ~/ 1000;
      mode.chain.landOps = false;
      await _expectMode(
        mode.repository.register(await attestX(dk), reauth: mode.reauth),
        DelegateModeErrorKind.unavailable,
      );
      expect(mode.bridge.pendingRegister, isNotNull);
      mode.chain.lookupsDown = true;
      final reads = mode.chain.reads.length;
      await mode.repository.startOver();
      expect(mode.chain.reads.length, reads, reason: 'nothing is looked up');
      expect(mode.bridge.heldDk, isNull);
      expect(mode.bridge.pendingRegister, isNull);
      expect(mode.keys.secrets, isEmpty);
    });

    test('a rejected registration keeps its stored op', () async {
      mode.chain.register('alice', mockDelegateKey(2).dk);
      final dk = mode.holdsKey(1);
      expect(
        await mode.repository.register(await attestX(dk), reauth: mode.reauth),
        isA<DelegateRegisterRejected>().having((r) => r.code, 'code', 62),
      );
      expect((await mode.repository.status()).registrationPending, isTrue);
    });
  });

  test('nothing runs while deletion holds the voting data', () async {
    mode.registeredKey(1);
    final draining = mode.host.drain.quiesceAndDrain(accountUuid: 'account-1');
    await _expectMode(mode.repository.status(), DelegateModeErrorKind.other);
    await _expectMode(
      mode.repository.retire(reauth: mode.reauth),
      DelegateModeErrorKind.other,
    );
    await draining;
    expect(mode.chain.reads, isEmpty);
    expect(mode.chain.posts, isEmpty);
    mode.host.drain.resume(accountUuid: 'account-1');
  });

  test('no key or export ever reaches a log line', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add('$message');
    addTearDown(() => debugPrint = previous);
    final key = await mode.repository.createKey();
    mode.chain.lookupsDown = true;
    await mode.repository.status();
    mode.chain.lookupsDown = false;
    mode.chain.postAnswers.add(const SocketException('reset'));
    await mode.repository.register(await attestX(key.dk), reauth: mode.reauth);
    expect(logs, isNotEmpty);
    for (final line in logs) {
      expect(line, isNot(contains(key.dk)));
      expect(line, isNot(contains(mode.keys.secrets[key.dk])));
    }
  });

  group('only a chain verdict is a rejection', () {
    /// Attests [dk] from alice's post on X.
    Future<DelegateAttestation> attest(String dk) => mode.repository.attest(
      provider: ProxyDelegateProvider.x,
      proofUrl: 'https://x.com/alice/status/1',
      key: DelegateKeyInfo(dk: dk, fingerprint: fakeFingerprint(dk)),
    );

    // One failure kind stands for every request that got no answer; the
    // classification test below covers each kind.
    const what = 'a Tor refusal';
    final failure = _transportFailures[what]!;

    test('$what posting a registration is unavailable', () async {
      final dk = mode.holdsKey(1);
      final attestation = await attest(dk);
      mode.chain.postAnswers.addAll(List.filled(50, failure));
      await _expectMode(
        mode.repository.register(attestation, reauth: mode.reauth),
        DelegateModeErrorKind.unavailable,
      );
      expect(mode.chain.entries, isEmpty);
    });

    test('$what posting a ballot is unavailable and keeps it', () async {
      mode.registeredKey(1);
      mode.chain.postAnswers.addAll(List.filled(3, failure));
      await _expectMode(
        mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        DelegateModeErrorKind.unavailable,
      );
      expect((await mode.repository.round(_round)).view.storedBallot, [1, 2]);
    });

    test('$what posting Retire is unavailable', () async {
      mode.registeredKey(1);
      mode.chain.postAnswers.addAll(List.filled(3, failure));
      await _expectMode(
        mode.repository.retire(reauth: mode.reauth),
        DelegateModeErrorKind.unavailable,
      );
    });

    test('$what at every verifier is unreachable', () async {
      final dk = mode.holdsKey(1);
      mode.host.verifierUrls = const [
        'https://verifier-a.example',
        'https://verifier-b.example',
      ];
      mode.verifier
        ..down = true
        ..downError = failure;
      await expectLater(
        attest(dk),
        throwsA(
          isA<DelegateModeException>().having(
            (e) => e.kind,
            'kind',
            DelegateModeErrorKind.unavailable,
          ),
        ),
      );
      expect(mode.verifier.hosts, hasLength(2));
    });

    test('$what on a read is unavailable', () async {
      mode.registeredKey(1);
      mode.chain.readFailure = failure;
      await _expectMode(
        mode.repository.round(_round),
        DelegateModeErrorKind.unavailable,
      );
    });

    test('a refused registration or Retire request is not a chain '
        'rejection', () async {
      final dk = mode.holdsKey(1);
      final attestation = await attest(dk);
      mode.chain.postAnswers.add(_refusedRequest());
      await _expectMode(
        mode.repository.register(attestation, reauth: mode.reauth),
        DelegateModeErrorKind.other,
      );

      mode.registeredKey(1);
      mode.chain.postAnswers.add(_refusedRequest());
      await _expectMode(
        mode.repository.retire(reauth: mode.reauth),
        DelegateModeErrorKind.other,
      );
    });

    test('a refused ballot request is not a chain rejection: the stored '
        'ballot is sent again', () async {
      mode.registeredKey(1);
      mode.chain.postAnswers.add(_refusedRequest());
      await expectLater(
        mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
        throwsA(isA<DelegateBallotStoredException>()),
      );
      expect(
        await mode.repository.resendStoredBallot(_round),
        DelegateBallotResend.posted(ballotSubmit(ApiBallotSubmitKind.accepted)),
      );
    });
  });

  group('error logs and transport failures', () {
    test('gives the type and message, redacting URLs and keys', () {
      final dk = 'zvdk1${'q' * 58}';
      expect(
        describeDelegateError(
          SocketException(
            'Connection refused, url https://vote.example/v1/delegates/by-key/$dk',
          ),
        ),
        'SocketException: SocketException: Connection refused, url <url>',
      );
      expect(
        describeDelegateError('Tor: refused $dk'),
        'String: Tor: refused <redacted>',
      );
      expect(
        describeDelegateError(
          rust.ApiDelegateModeError(
            kind: rust.ApiDelegateModeErrorKind.other,
            message: 'the attestation is for key $dk, not zvdk1other',
          ),
        ),
        'other: the attestation is for key <redacted>, not zvdk1other',
      );
      expect(
        describeDelegateError('x' * 10 + ' y' * 300),
        hasLength(lessThan(240)),
      );
    });

    test('counts only requests without an answer as transport failures', () {
      for (final failure in [
        ..._transportFailures.values,
        const HttpException('Connection closed'),
      ]) {
        expect(isVotingTransportError(failure), isTrue, reason: '$failure');
      }
      for (final other in [
        StateError('records'),
        const DelegateModeException(DelegateModeErrorKind.other),
        ArgumentError('body'),
      ]) {
        expect(isVotingTransportError(other), isFalse, reason: '$other');
      }
    });
  });
}
