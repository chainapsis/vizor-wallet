import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import 'support/delegate_mode_fakes.dart';
import 'support/proxy_rust_fake.dart';

/// The device time.
final _now = DateTime(2026, 10, 7, 12);

/// The running round's id.
final _round = '0a' * 32;

/// The wallet's lock, which tests flip.
class _Security extends AppSecurityNotifier {
  _Security({required this.locked});

  /// Whether the wallet starts locked.
  final bool locked;

  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: true, isUnlocked: !locked);

  /// Unlocks the wallet.
  void setUnlocked() => state = state.copyWith(isUnlocked: true);
}

void main() {
  useProxyRustFake();

  late RealDelegateMode mode;

  setUp(() async {
    mode = RealDelegateMode(now: _now);
    mode.host.rounds_.add(
      fakeDelegateRound(
        roundId: _round,
        voteEnd: _now.add(const Duration(days: 3)),
      ),
    );
    mode.registeredKey(1);
    // The ballot is signed and stored, then every post goes unanswered.
    mode.chain.postAnswers.addAll(
      List.filled(3, const SocketException('reset')),
    );
    await expectLater(
      mode.repository.submitBallot(_round, [1, 2], reauth: mode.reauth),
      throwsA(isA<DelegateBallotStoredException>()),
    );
  });

  /// The app after a restart, its wallet [locked] or not, over the same
  /// device and chain, or [repository]. Nothing opens delegate mode.
  ProviderContainer restartedApp({
    bool locked = false,
    DelegateModeRepository? repository,
  }) {
    final container = ProviderContainer(
      overrides: [
        proxyClockProvider.overrideWithValue(() => _now),
        delegateModeRepositoryProvider.overrideWithValue(
          repository ?? mode.restarted(),
        ),
        appSecurityProvider.overrideWith(() => _Security(locked: locked)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('after a restart a stored ballot with no verdict is resent '
      'without opening delegate mode', (tester) async {
    final posted = mode.chain.posts.length;
    final container = restartedApp();
    await container.read(delegateBallotResendRestorerProvider).restore();

    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted + 1);
    expect(
      mode.chain.posts.last,
      mode.chain.posts.first,
      reason: 'the same bytes',
    );
    expect(mode.chain.ballots[_round]?[17], [1, 2]);

    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(
      mode.chain.posts.length,
      posted + 1,
      reason: 'the list shows it, so the resends stop',
    );
  });

  testWidgets('a round that cannot be read leaves the others resending, '
      'and is found again on the retry', (tester) async {
    final other = '0c' * 32;
    mode.host.rounds_.add(
      fakeDelegateRound(
        roundId: other,
        voteEnd: _now.add(const Duration(days: 3)),
      ),
    );
    mode.chain.postAnswers.addAll(
      List.filled(3, const SocketException('reset')),
    );
    await expectLater(
      mode.restarted().submitBallot(other, [0, 1], reauth: mode.reauth),
      throwsA(isA<DelegateBallotStoredException>()),
    );
    mode.host.failingRounds.add(other);
    final container = restartedApp(
      repository: mode.restarted(readsMaxAge: Duration.zero),
    );
    await container.read(delegateBallotResendRestorerProvider).restore();
    await tester.pump();
    expect(mode.chain.ballots[_round]?[17], [1, 2]);
    expect(mode.chain.ballots[other], isNull);

    mode.host.failingRounds.clear();
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.ballots[other]?[17], [0, 1]);
    container.dispose();
  });

  testWidgets('a suspension the chain reports before the proof shows it '
      'keeps the resends checking until it lifts', (tester) async {
    final repository = mode.restarted();
    final container = restartedApp(repository: repository);
    // The entry is suspended after the resend read its proof, so the
    // chain refuses the post.
    mode.chain.postAnswers.add(
      fakeJsonAnswer({
        'code': 54,
        'codespace': 'vote',
        'log': 'delegate suspended',
      }, status: 422),
    );
    final posted = mode.chain.posts.length;
    await container.read(delegateBallotResendRestorerProvider).restore();
    await tester.pump();
    expect(mode.chain.posts.length, posted + 1, reason: 'refused with 54');

    mode.chain.entries[17]!.status = rust_wire.DelegateEntryStatus.suspended;
    final proofReads = mode.host.proofRequests.length;
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted + 1, reason: 'proven suspended');
    expect(
      mode.host.proofRequests.length,
      greaterThan(proofReads),
      reason: 'the refusal dropped the cached proof',
    );

    mode.chain.entries[17]!.status = rust_wire.DelegateEntryStatus.active;
    mode.now = mode.now.add(repository.readsMaxAge);
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted + 2);
    expect(mode.chain.ballots[_round]?[17], [1, 2]);
    container.dispose();
  });

  testWidgets('a suspension posts nothing, and resends resume once it '
      'lifts', (tester) async {
    mode.chain.entries[17]!.status = rust_wire.DelegateEntryStatus.suspended;
    final repository = mode.restarted();
    final posted = mode.chain.posts.length;
    final container = restartedApp(repository: repository);
    await container.read(delegateBallotResendRestorerProvider).restore();
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted);

    mode.chain.entries[17]!.status = rust_wire.DelegateEntryStatus.active;
    mode.now = mode.now.add(repository.readsMaxAge);
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted + 1);
    expect(mode.chain.ballots[_round]?[17], [1, 2]);
    container.dispose();
  });

  testWidgets("a retired entry's stored ballot is not resent after a "
      'restart', (tester) async {
    mode.chain.entries[17]!.status = rust_wire.DelegateEntryStatus.retired;
    final posted = mode.chain.posts.length;
    final container = restartedApp();
    await container.read(delegateBallotResendRestorerProvider).restore();

    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted);
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted, reason: 'the resends stopped');
  });

  testWidgets('with less than one interval left, the first resend goes '
      'out right after discovery', (tester) async {
    final voteEnd = _now.add(const Duration(seconds: 10));
    mode.host.rounds_[0] = fakeDelegateRound(roundId: _round, voteEnd: voteEnd);
    final posted = mode.chain.posts.length;
    final container = restartedApp();
    await container.read(delegateBallotResendRestorerProvider).restore();
    await tester.pump();
    expect(mode.chain.posts.length, posted + 1);
    expect(mode.chain.ballots[_round]?[17], [1, 2]);
    container.dispose();
  });

  testWidgets('a locked wallet resends nothing until it unlocks', (
    tester,
  ) async {
    final posted = mode.chain.posts.length;
    final container = restartedApp(locked: true);
    container.read(delegateBallotResendRestorerProvider);
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted);

    (container.read(appSecurityProvider.notifier) as _Security).setUnlocked();
    await tester.pump();
    await tester.pump(kDelegateBallotResendInterval);
    await tester.pump();
    expect(mode.chain.posts.length, posted + 1);
    container.dispose();
  });
}
