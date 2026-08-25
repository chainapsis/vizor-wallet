import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_private_state_sync.dart';
import 'package:zcash_wallet/src/providers/voting/voting_private_state_lifecycle_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

void main() {
  test('sweeps local and remote completions for every account', () async {
    final repository = _RecordingRepository();
    final sweep = VotingPrivateCompletionSweep(
      sync: VotingPrivateStateSync(repository),
      accountUuidLoader: () async => ['account-1', 'account-2'],
      dbPathLoader: () async => 'wallet.db',
      networkLoader: () => 'main',
      roundLoader: () async => const [
        VotingPrivateRoundCandidate(roundId: 'round-1', proposalIds: [7]),
        VotingPrivateRoundCandidate(roundId: 'round-2', proposalIds: [8]),
      ],
      localCompletionLoader:
          ({required dbPath, required accountUuid, required round}) async {
            if (accountUuid == 'account-1' && round.roundId == 'round-1') {
              return VotingLocalCompletionState(
                blocksRemote: false,
                record: VotingCompletionRecord(
                  roundId: round.roundId,
                  completedAtSeconds: 1,
                  choicesByProposalId: const {7: 1},
                ),
              );
            }
            if (accountUuid == 'account-2' && round.roundId == 'round-1') {
              return const VotingLocalCompletionState(blocksRemote: true);
            }
            return const VotingLocalCompletionState(blocksRemote: false);
          },
    );

    await sweep.synchronizeAll();

    expect(repository.creates, ['account-1:round-v1:round-1']);
    expect(repository.reads, [
      'account-1:round-v1:round-2',
      'account-2:round-v1:round-2',
    ]);
  });

  test('coalesces overlapping completion refresh requests', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var refreshCount = 0;
    final coordinator = VotingPrivateStateLifecycleCoordinator(
      activeAccountUuidLoader: () async => 'account-1',
      isLocked: () => false,
      retryDelay: Duration.zero,
      refresh: () async {
        refreshCount++;
        if (refreshCount == 1) {
          started.complete();
          await release.future;
        }
      },
    );
    addTearDown(coordinator.dispose);

    final first = coordinator.synchronize();
    await started.future;
    final second = coordinator.synchronize();
    release.complete();
    await Future.wait([first, second]);
    await pumpEventQueue();

    expect(refreshCount, 2);
  });

  test('stays paused while locked and resumes explicitly', () async {
    var locked = true;
    var refreshCount = 0;
    final coordinator = VotingPrivateStateLifecycleCoordinator(
      activeAccountUuidLoader: () async => 'account-1',
      isLocked: () => locked,
      retryDelay: Duration.zero,
      refresh: () async => refreshCount++,
    );
    addTearDown(coordinator.dispose);

    await coordinator.synchronize();
    expect(refreshCount, 0);

    locked = false;
    await coordinator.resume();
    expect(refreshCount, 1);
  });

  test('completion revision changes only for new account-round content', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(
      votingPrivateCompletionRevisionProvider.notifier,
    );
    const account = PrivateStateAccount(
      dbPath: 'wallet.db',
      network: 'main',
      accountUuid: 'account-1',
    );
    final first = VotingCompletionRecord(
      roundId: 'round-1',
      completedAtSeconds: 1,
      choicesByProposalId: const {7: 0},
    );

    notifier.observe(account: account, record: first);
    notifier.observe(account: account, record: first);
    expect(container.read(votingPrivateCompletionRevisionProvider), 1);

    notifier.observe(
      account: account,
      record: VotingCompletionRecord(
        roundId: 'round-1',
        completedAtSeconds: 2,
        choicesByProposalId: const {7: 1},
      ),
    );
    expect(container.read(votingPrivateCompletionRevisionProvider), 2);
  });
}

class _RecordingRepository implements PrivateStateObjectRepository {
  final List<String> creates = [];
  final List<String> reads = [];

  @override
  Future<PrivateStateWriteResult> compareAndSet({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateVersion currentVersion,
    required Uint8List plaintext,
  }) => throw UnimplementedError();

  @override
  Future<PrivateStateWriteResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    creates.add('${account.accountUuid}:${key.itemKey}');
    return PrivateStateWriteStored(
      PrivateStateVersion(revision: BigInt.one, envelopeHashBase64: 'hash'),
    );
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    reads.add('${account.accountUuid}:${key.itemKey}');
    return const PrivateStateReadAbsent();
  }
}
