import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_rounds_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_tree_sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_voting;
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import '../../services/voting/fake_voting_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('config provider loads and refreshes dynamic voting config', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final first = await container.read(votingConfigProvider.future);
    await container.read(votingConfigProvider.notifier).refresh();
    final second = container.read(votingConfigProvider).value;

    expect(first.apiBaseUrl, Uri.parse('https://voting.example'));
    expect(second?.apiBaseUrl, first.apiBaseUrl);
    expect(
      http.requests
          .where(
            (request) =>
                request.uri.toString() ==
                'https://voting.example/static-voting-config.json',
          )
          .length,
      2,
    );
  });

  test('rounds provider merges endorsed and unverified rows', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://voting.example/static-voting-config.json': staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
        '/shielded-vote/v1/rounds': [
          {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          {
            'vote_round_id': kOtherRoundId,
            'title': 'Other',
            'status': 'active',
          },
        ],
        '/shielded-vote/v1/endorsed-rounds/zodl': {
          'endorsed_round_ids': [kRoundId],
        },
      },
    );
    final container = _container(http: http);
    addTearDown(container.dispose);

    final rounds = await container.read(votingRoundsProvider.future);

    expect(rounds, hasLength(2));
    expect(rounds.first.endorsed, isTrue);
    expect(rounds.first.unverified, isFalse);
    expect(rounds.first.roundId, kRoundId);
    expect(rounds.last.endorsed, isFalse);
    expect(rounds.last.unverified, isTrue);
    expect(rounds.last.roundId, kOtherRoundId);
  });

  test('round details normalize base64 vote_round_id to hex', () {
    final details = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(roundId: kEncodedRoundId)..remove('round_id'),
      ),
    );

    expect(details.roundId, kEncodedRoundIdHex);
    expect(details.toRoundParams().voteRoundId, kEncodedRoundIdHex);
  });

  test('round details expose last-moment scheduling window', () {
    final details = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(roundId: kRoundId, ceremonyStart: 1000, voteEnd: 1600),
      ),
    );

    expect(
      details.ceremonyStart,
      DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
    );
    expect(
      details.voteEndTime,
      DateTime.fromMillisecondsSinceEpoch(1600000, isUtc: true),
    );
    expect(details.lastMomentBuffer, const Duration(seconds: 240));
    expect(
      details.isLastMoment(
        DateTime.fromMillisecondsSinceEpoch(1359000, isUtc: true),
      ),
      isFalse,
    );
    expect(
      details.isLastMoment(
        DateTime.fromMillisecondsSinceEpoch(1360000, isUtc: true),
      ),
      isTrue,
    );
  });

  test('round details cap last-moment buffer and reject invalid timing', () {
    final capped = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(
          roundId: kRoundId,
          ceremonyStart: 1000,
          voteEnd: 100000,
        ),
      ),
    );
    final invalid = VotingRoundDetails.fromStatus(
      VotingRoundStatus.fromJson(
        roundStatusJson(roundId: kRoundId, ceremonyStart: 2000, voteEnd: 1000),
      ),
    );

    expect(capped.lastMomentBuffer, const Duration(hours: 6));
    expect(invalid.lastMomentBuffer, isNull);
    expect(
      invalid.isLastMoment(
        DateTime.fromMillisecondsSinceEpoch(1500000, isUtc: true),
      ),
      isFalse,
    );
  });

  test('PIR mismatch fails before Rust delegation work is called', () async {
    final rust = FakeVotingRustApi();
    final pir = FakePirResolver(
      error: PirSnapshotNoMatchingEndpoint(
        expectedSnapshotHeight: 123,
        diagnostics: [
          PirSnapshotEndpointDiagnostic(
            endpoint: Uri.parse('https://pir.example'),
            status: PirSnapshotEndpointStatus.behind,
            reportedHeight: 122,
          ),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, pirResolver: pir);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareDelegation();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.pirDiagnostics, hasLength(1));
    expect(rust.setupCalls, 0);
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test(
    'PIR endpoint without identity is accepted when root height matches',
    () async {
      final rust = FakeVotingRustApi();
      final pir = PirSnapshotResolver(
        httpClient: FakeVotingHttpClient(
          responses: {
            'https://pir.example/root': {'height': 123},
          },
        ),
      );
      final container = _sessionContainer(rust: rust, pirResolver: pir);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareDelegation();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.pirEndpoint, Uri.parse('https://pir.example'));
      expect(
        state.pirDiagnostics.single.status,
        PirSnapshotEndpointStatus.matched,
      );
      expect(rust.setupCalls, 1);
    },
  );

  test('resume after delegated does not rebuild delegation bundle', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 0,
            txHash: 'delegation-tx',
          ),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(seedBytes: [1, 2, 3]);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.setupCalls, 1);
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test('delegation submits chain payload and stores recovery state', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(seedBytes: [1, 2, 3]);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.delegationBundleCalls, [0]);
    expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
    expect(rust.storedVanPositions, ['0:0']);
  });

  test('session keeps using account from initial round load', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(state: recoveryState());
    final activeAccount = _MutableActiveAccount('account-1');
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: recoveryApi,
      activeAccountUuid: activeAccount.call,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    activeAccount.value = 'account-2';
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(seedBytes: [1, 2, 3]);

    expect(rust.accountUuids.toSet(), {'account-1'});
    expect(recoveryApi.walletIds.toSet(), {'account-1'});
  });

  test(
    'delegation submission matches Swift SDK snake case wire shape',
    () async {
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final container = _sessionContainer(http: http);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundles(seedBytes: [1, 2, 3]);

      expect(_postBody(http, '/shielded-vote/v1/delegate-vote'), {
        'rk': base64Encode([2]),
        'spend_auth_sig': base64Encode([3]),
        'sighash': base64Encode([4]),
        'signed_note_nullifier': base64Encode([5]),
        'cmx_new': base64Encode([6]),
        'van_cmx': base64Encode([7]),
        'gov_nullifiers': [
          base64Encode([8]),
        ],
        'proof': base64Encode([1]),
        'vote_round_id': base64Encode(List.filled(32, 0xaa)),
      });
    },
  );

  test('vote progress is isolated by bundle index', () async {
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 2,
        delegationTxHashes: [
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 0,
            txHash: 'delegation-0',
          ),
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 1,
            txHash: 'delegation-1',
          ),
        ],
        votes: [
          vote(bundleIndex: 0, proposalId: 7),
          vote(bundleIndex: 1, proposalId: 7),
        ],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_voting.ApiDraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.submittingShares);
    expect(state.voteProgress.keys.toSet(), {
      const VotingVoteKey(bundleIndex: 0, proposalId: 7),
      const VotingVoteKey(bundleIndex: 1, proposalId: 7),
    });
    expect(rust.voteCommitBundleCalls, [0, 1]);
  });

  test('vote tree pre-sync dedupes warmup for the same round', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    final service = container.read(votingTreePreSyncProvider);
    await Future.wait([
      service.preSyncRound(kRoundId),
      service.preSyncRound(kRoundId),
    ]);
    await service.preSyncRound(kRoundId);

    expect(rust.syncedVoteTrees, [kRoundId]);
  });

  test('vote tree sync runs before each proposal', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_voting.ApiDraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
            rust_voting.ApiDraftVote(
              proposalId: 8,
              choice: 0,
              numOptions: 2,
              vcTreePosition: BigInt.one,
              singleShare: false,
            ),
          ],
        );

    expect(rust.syncedVoteTrees, [kRoundId, kRoundId]);
    expect(rust.voteCommitBundleCalls, [0, 0]);
  });

  test('vote commitments submit shares and record recovery rows', () async {
    final rust = FakeVotingRustApi(emitCommitments: true);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 0,
            txHash: 'delegation-0',
          ),
        ],
        votes: [vote(bundleIndex: 0, proposalId: 7)],
      ),
    );
    final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_voting.ApiDraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );

    expect(rust.recordedShares, hasLength(1));
    expect(rust.recordedShares.single.bundleIndex, 0);
    expect(rust.recordedShares.single.proposalId, 7);
    expect(rust.recordedShares.single.submitAt, BigInt.zero);
    expect(rust.storedVoteTxHashes, ['0:7:vote-tx']);
    expect(rust.storedCommitmentBundles, ['0:7:2:{"proposal_id":7}']);
  });

  test(
    'share submission schedules submit_at before last-moment buffer',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final voteEnd = nowSeconds + 1000;
      final ceremonyStart = nowSeconds - 100;
      final deadline = voteEnd - ((voteEnd - ceremonyStart) * 0.4).round();
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            ceremonyStart: ceremonyStart,
            voteEnd: voteEnd,
          ),
        ),
      );
      final rust = FakeVotingRustApi(emitCommitments: true);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_voting.ApiDelegationTxRecovery(
              bundleIndex: 0,
              txHash: 'delegation-0',
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_voting.ApiDraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      final submitAt = _postBody(http, '/shielded-vote/v1/shares')['submit_at'];
      expect(submitAt, isA<int>());
      expect(submitAt as int, greaterThanOrEqualTo(nowSeconds));
      expect(submitAt, lessThan(deadline));
      expect(rust.recordedShares.single.submitAt, BigInt.from(submitAt));
    },
  );

  test(
    'last-moment vote uses single-share mode and immediate submit_at',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          roundStatus: roundStatusJson(
            roundId: kRoundId,
            ceremonyStart: nowSeconds - 1000,
            voteEnd: nowSeconds + 100,
          ),
        ),
      );
      final rust = FakeVotingRustApi(emitCommitments: true);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_voting.ApiDelegationTxRecovery(
              bundleIndex: 0,
              txHash: 'delegation-0',
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_voting.ApiDraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(rust.draftSingleShareValues, [true]);
      expect(_postBody(http, '/shielded-vote/v1/shares')['submit_at'], 0);
      expect(rust.recordedShares.single.submitAt, BigInt.zero);
    },
  );

  test(
    'vote and share submissions match Swift SDK snake case wire shapes',
    () async {
      final http = FakeVotingHttpClient(responses: votingHttpResponses());
      final rust = FakeVotingRustApi(emitCommitments: true);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_voting.ApiDelegationTxRecovery(
              bundleIndex: 0,
              txHash: 'delegation-0',
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      );
      final container = _sessionContainer(
        http: http,
        rust: rust,
        recoveryApi: recoveryApi,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_voting.ApiDraftVote(
                proposalId: 7,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(_postBody(http, '/shielded-vote/v1/cast-vote'), {
        'van_nullifier': base64Encode(List.filled(32, 1)),
        'vote_authority_note_new': base64Encode(List.filled(32, 2)),
        'vote_commitment': base64Encode(List.filled(32, 3)),
        'proposal_id': 7,
        'proof': base64Encode([4]),
        'vote_round_id': base64Encode(List.filled(32, 0xaa)),
        'vote_comm_tree_anchor_height': 10,
        'r_vpk': base64Encode(List.filled(32, 13)),
        'vote_auth_sig': base64Encode(List.filled(64, 12)),
      });
      expect(_postBody(http, '/shielded-vote/v1/shares'), {
        'vote_round_id': kRoundId,
        'shares_hash': base64Encode(List.filled(32, 7)),
        'proposal_id': 7,
        'vote_decision': 1,
        'enc_share': {
          'c1': base64Encode([8]),
          'c2': base64Encode([9]),
          'share_index': 0,
        },
        'share_index': 0,
        'tree_position': 2,
        'all_enc_shares': [
          {
            'c1': base64Encode([8]),
            'c2': base64Encode([9]),
            'share_index': 0,
          },
        ],
        'share_comms': [base64Encode(List.filled(32, 10))],
        'primary_blind': base64Encode(List.filled(32, 11)),
        'submit_at': 0,
      });
    },
  );

  test('accepted unconfirmed shares do not keep status flow pending', () async {
    final acceptedShare = rust_voting.ApiShareDelegationRecord(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://voting.example'],
      nullifier: Uint8List.fromList(List.filled(32, 1)),
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.zero,
      createdAt: BigInt.one,
    );
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationTxHashes: [
          rust_voting.ApiDelegationTxRecovery(
            bundleIndex: 0,
            txHash: 'delegation-0',
          ),
        ],
        shareDelegations: [acceptedShare],
        unconfirmedShareDelegations: [acceptedShare],
      ),
    );
    final container = _sessionContainer(recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .submitPendingShares();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.done);
    expect(state.resumePlan?.unconfirmedShareDelegations, [acceptedShare]);
  });

  test('session actions are serialized', () async {
    final rust = FakeVotingRustApi(
      setupDelay: const Duration(milliseconds: 10),
    );
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await Future.wait([
      notifier.prepareDelegation(),
      notifier.prepareDelegation(),
    ]);

    expect(rust.setupCalls, 2);
    expect(rust.maxConcurrentSetups, 1);
  });

  test('session dispose clears round-scoped process state', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust);

    await container.read(votingSessionProvider(kRoundId).future);
    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(rust.resetVotingSessionStateCalls, ['account-1:$kRoundId']);
  });

  test('hotkey failure moves session into error phase', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(
      rust: rust,
      hotkeyStore: const FailingVotingHotkeyStore(),
      recoveryApi: FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          delegationTxHashes: [
            rust_voting.ApiDelegationTxRecovery(
              bundleIndex: 0,
              txHash: 'delegation-0',
            ),
          ],
          votes: [vote(bundleIndex: 0, proposalId: 7)],
        ),
      ),
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(
          draftVotes: [
            rust_voting.ApiDraftVote(
              proposalId: 7,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.cause, isA<VotingHotkeyUnavailable>());
    expect(rust.resetVotingSessionStateCalls, contains('account-1:$kRoundId'));
  });
}

ProviderContainer _container({required VotingHttpClient http}) {
  return ProviderContainer(
    overrides: [
      votingHttpClientProvider.overrideWithValue(http),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: http,
          staticConfigSource: StaticVotingConfigSource.parse(
            'https://voting.example/static-voting-config.json',
          ),
        ),
      ),
    ],
  );
}

ProviderContainer _sessionContainer({
  FakeVotingHttpClient? http,
  FakeVotingRustApi? rust,
  FakeVotingRecoveryApi? recoveryApi,
  PirSnapshotResolver? pirResolver,
  VotingHotkeyStore hotkeyStore = const FakeVotingHotkeyStore([9, 9, 9]),
  Future<String?> Function()? activeAccountUuid,
}) {
  final effectiveHttp =
      http ?? FakeVotingHttpClient(responses: votingHttpResponses());
  return ProviderContainer(
    overrides: [
      votingHttpClientProvider.overrideWithValue(effectiveHttp),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: effectiveHttp,
          staticConfigSource: StaticVotingConfigSource.parse(
            'https://voting.example/static-voting-config.json',
          ),
        ),
      ),
      votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
      votingActiveAccountUuidProvider.overrideWithValue(
        activeAccountUuid ?? () async => 'account-1',
      ),
      votingRpcEndpointConfigProvider.overrideWithValue(
        const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: 'https://lightwalletd.example:443',
        ),
      ),
      votingRecoveryServiceProvider.overrideWithValue(
        VotingRecoveryService(
          api: recoveryApi ?? FakeVotingRecoveryApi(state: recoveryState()),
        ),
      ),
      votingPirResolverProvider.overrideWithValue(
        pirResolver ??
            FakePirResolver(
              resolution: PirSnapshotResolution(
                endpoint: Uri.parse('https://pir.example'),
                diagnostics: [
                  PirSnapshotEndpointDiagnostic(
                    endpoint: Uri.parse('https://pir.example'),
                    status: PirSnapshotEndpointStatus.matched,
                    reportedHeight: 123,
                  ),
                ],
              ),
            ),
      ),
      votingRustApiProvider.overrideWithValue(rust ?? FakeVotingRustApi()),
      votingHotkeyStoreProvider.overrideWithValue(hotkeyStore),
    ],
  );
}

Map<String, dynamic> _postBody(FakeVotingHttpClient http, String path) {
  final request = http.requests.singleWhere(
    (request) => request.method == 'POST' && request.uri.path == path,
  );
  return request.body!;
}

Map<String, Object> votingHttpResponses({
  Map<String, dynamic>? roundStatus,
}) => {
  'https://voting.example/static-voting-config.json': staticConfigJson(),
  'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
  '/shielded-vote/v1/round/$kRoundId': {
    'round': roundStatus ?? roundStatusJson(roundId: kRoundId),
  },
  '/shielded-vote/v1/delegate-vote': {
    'tx_hash': 'delegation-tx',
    'code': 0,
    'log': '',
  },
  '/shielded-vote/v1/tx/delegation-tx': {
    'height': 10,
    'code': 0,
    'log': '',
    'events': [
      {
        'type': 'delegate_vote',
        'attributes': [
          {'key': 'leaf_index', 'value': '0'},
        ],
      },
    ],
  },
  '/shielded-vote/v1/cast-vote': {'tx_hash': 'vote-tx', 'code': 0, 'log': ''},
  '/shielded-vote/v1/tx/vote-tx': {
    'height': 11,
    'code': 0,
    'log': '',
    'events': [
      {
        'type': 'cast_vote',
        'attributes': [
          {'key': 'leaf_index', 'value': '1,2'},
        ],
      },
    ],
  },
  '/shielded-vote/v1/share-status/$kRoundId/0102': {'status': 'confirmed'},
};

const kRoundId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const kOtherRoundId =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const kEncodedRoundId = 'El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv/3RE=';
const kEncodedRoundIdHex =
    '125e5475f653b074d5f4c36730852695f356416c2b6c3042516a912e5bffdd11';
const _hex32 =
    '0101010101010101010101010101010101010101010101010101010101010101';

Map<String, dynamic> staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _hex32},
  ],
};

Map<String, dynamic> dynamicConfigJson() => {
  'config_version': 1,
  'vote_servers': [
    {'url': 'https://voting.example', 'label': 'primary'},
  ],
  'pir_endpoints': [
    {'url': 'https://pir.example', 'label': 'pir'},
  ],
  'supported_versions': {
    'pir': ['v0'],
    'vote_protocol': 'v0',
    'tally': 'v0',
    'vote_server': 'v1',
  },
  'rounds': {
    kRoundId: {
      'auth_version': 1,
      'ea_pk': _hex32,
      'signatures': [
        {'key_id': 'demo', 'alg': 'ed25519', 'sig': _hex32},
      ],
    },
  },
};

Map<String, dynamic> roundStatusJson({
  required String roundId,
  int? ceremonyStart,
  int? voteEnd,
}) => {
  'vote_round_id': roundId,
  'round_id': roundId,
  'title': 'Poll',
  'status': 'active',
  'snapshot_height': 123,
  'ea_pk': _hex32,
  'nc_root': _hex32,
  'nullifier_imt_root': _hex32,
  if (ceremonyStart != null) 'ceremony_phase_start': ceremonyStart,
  if (voteEnd != null) 'vote_end_time': voteEnd,
};

rust_voting.ApiRoundRecoveryState recoveryState({
  int bundleCount = 1,
  List<rust_voting.ApiDelegationWorkflowRecovery> delegationWorkflows =
      const [],
  List<rust_voting.ApiDelegationTxRecovery> delegationTxHashes = const [],
  List<rust_voting.ApiVoteRecord> votes = const [],
  List<rust_voting.ApiVoteWorkflowRecovery> voteWorkflows = const [],
  List<rust_voting.ApiVoteTxRecovery> voteTxHashes = const [],
  List<rust_voting.ApiCommitmentBundleRecovery> commitmentBundles = const [],
  List<rust_voting.ApiShareWorkflowRecovery> shareWorkflows = const [],
  List<rust_voting.ApiShareDelegationRecord> shareDelegations = const [],
  List<rust_voting.ApiShareDelegationRecord> unconfirmedShareDelegations =
      const [],
}) {
  return rust_voting.ApiRoundRecoveryState(
    roundId: kRoundId,
    bundleCount: bundleCount,
    delegationWorkflows: delegationWorkflows,
    delegationTxHashes: delegationTxHashes,
    votes: votes,
    voteWorkflows: voteWorkflows,
    voteTxHashes: voteTxHashes,
    commitmentBundles: commitmentBundles,
    shareWorkflows: shareWorkflows,
    shareDelegations: shareDelegations,
    unconfirmedShareDelegations: unconfirmedShareDelegations,
  );
}

rust_voting.ApiVoteRecord vote({
  required int bundleIndex,
  required int proposalId,
}) {
  return rust_voting.ApiVoteRecord(
    proposalId: proposalId,
    bundleIndex: bundleIndex,
    choice: 1,
    submitted: false,
  );
}

class FakeVotingRecoveryApi implements VotingRecoveryApi {
  rust_voting.ApiRoundRecoveryState state;
  final walletIds = <String>[];

  FakeVotingRecoveryApi({required this.state});

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) async {}

  @override
  Future<void> clearRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {}

  @override
  Future<rust_voting.ApiRoundRecoveryState> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    walletIds.add(walletId);
    return state;
  }
}

class _MutableActiveAccount {
  _MutableActiveAccount(this.value);

  String? value;

  Future<String?> call() async => value;
}

class FakePirResolver implements PirSnapshotResolver {
  final PirSnapshotResolution? resolution;
  final Object? error;

  const FakePirResolver({this.resolution, this.error});

  @override
  Future<PirSnapshotResolution> resolve({
    required List<Uri> endpoints,
    required int expectedSnapshotHeight,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    return resolution!;
  }
}

class FakeVotingHotkeyStore implements VotingHotkeyStore {
  final List<int> hotkey;

  const FakeVotingHotkeyStore(this.hotkey);

  @override
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) async {
    return hotkey;
  }

  @override
  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) async {}

  @override
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) async {}
}

class FailingVotingHotkeyStore implements VotingHotkeyStore {
  const FailingVotingHotkeyStore();

  @override
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) {
    throw const VotingHotkeyUnavailable('missing test hotkey');
  }

  @override
  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) async {}

  @override
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) async {}
}

class FakeVotingRustApi implements VotingRustApi {
  FakeVotingRustApi({
    this.setupDelay = Duration.zero,
    this.emitCommitments = false,
  });

  final Duration setupDelay;
  final bool emitCommitments;
  int setupCalls = 0;
  int _activeSetups = 0;
  int maxConcurrentSetups = 0;
  final delegationBundleCalls = <int>[];
  final voteCommitBundleCalls = <int>[];
  final storedDelegationTxHashes = <String>[];
  final storedVoteTxHashes = <String>[];
  final storedCommitmentBundles = <String>[];
  final storedVanPositions = <String>[];
  final recordedShares = <_RecordedShare>[];
  final syncedVoteTrees = <String>[];
  final precomputedDelegationPir = <int>[];
  final resetVotingSessionStateCalls = <String>[];
  final draftSingleShareValues = <bool>[];
  final accountUuids = <String>[];

  @override
  Future<rust_voting.ApiVotingBundleSetupResult> setupDelegationBundles({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
  }) async {
    accountUuids.add(accountUuid);
    _activeSetups++;
    if (_activeSetups > maxConcurrentSetups) {
      maxConcurrentSetups = _activeSetups;
    }
    if (setupDelay > Duration.zero) {
      await Future<void>.delayed(setupDelay);
    }
    setupCalls++;
    _activeSetups--;
    return rust_voting.ApiVotingBundleSetupResult(
      bundleCount: 1,
      eligibleWeightZatoshi: BigInt.from(100),
    );
  }

  @override
  Stream<rust_voting.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
  }) async* {
    accountUuids.add(accountUuid);
    delegationBundleCalls.add(bundleIndex);
    yield rust_voting.ApiDelegationProofEvent(
      phase: 'result',
      proofProgress: null,
      signedDelegationPayload: rust_voting.ApiSignedDelegationPayload(
        pcztBytes: Uint8List.fromList(const []),
        status: 'ready_for_submission',
        message: null,
        proof: Uint8List.fromList(const [1]),
        rk: Uint8List.fromList(const [2]),
        spendAuthSig: Uint8List.fromList(const [3]),
        sighash: Uint8List.fromList(const [4]),
        nfSigned: Uint8List.fromList(const [5]),
        cmxNew: Uint8List.fromList(const [6]),
        govComm: Uint8List.fromList(const [7]),
        govNullifiers: [
          Uint8List.fromList(const [8]),
        ],
        voteRoundId: roundParams.voteRoundId,
        eligibleWeightZatoshi: BigInt.from(100),
        delegatedWeightZatoshi: BigInt.from(100),
        bundleCount: 1,
        bundleIndex: bundleIndex,
      ),
    );
  }

  @override
  Future<rust_voting.ApiDelegationPirPrecomputeResult> precomputeDelegationPir({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
  }) async {
    accountUuids.add(accountUuid);
    precomputedDelegationPir.add(bundleIndex);
    return rust_voting.ApiDelegationPirPrecomputeResult(
      cachedCount: 0,
      fetchedCount: 1,
      bundleCount: 1,
      bundleIndex: bundleIndex,
    );
  }

  @override
  Future<void> storeDelegationTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  }) async {
    _addUnique(storedDelegationTxHashes, '$bundleIndex:$txHash');
  }

  @override
  Future<void> markDelegationSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  }) async {
    _addUnique(storedDelegationTxHashes, '$bundleIndex:$txHash');
  }

  @override
  Future<void> markDelegationConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
    required int vanLeafPosition,
  }) async {
    _addUnique(storedDelegationTxHashes, '$bundleIndex:$txHash');
    storedVanPositions.add('$bundleIndex:$vanLeafPosition');
  }

  @override
  Future<void> storeVanPosition({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int position,
  }) async {
    storedVanPositions.add('$bundleIndex:$position');
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String walletId,
    required String roundId,
    required String nodeUrl,
  }) async {
    syncedVoteTrees.add(roundId);
    return 10;
  }

  @override
  Future<rust_voting.ApiVanWitness> generateVanWitness({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  }) async {
    return rust_voting.ApiVanWitness(
      authPath: const [],
      position: bundleIndex,
      anchorHeight: anchorHeight,
    );
  }

  @override
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String walletId,
    String? roundId,
  }) async {
    resetVotingSessionStateCalls.add('$walletId:${roundId ?? '*'}');
  }

  @override
  Stream<rust_voting.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String walletId,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> hotkeySeed,
    required rust_voting.ApiVanWitness vanWitness,
    required List<rust_voting.ApiDraftVote> draftVotes,
  }) async* {
    voteCommitBundleCalls.add(bundleIndex);
    for (final draft in draftVotes) {
      draftSingleShareValues.add(draft.singleShare);
      yield rust_voting.ApiVoteCommitEvent(
        phase: 'result',
        proposalId: draft.proposalId,
        bundleIndex: bundleIndex,
        proofProgress: null,
        commitments: emitCommitments
            ? _commitments(
                roundId: roundId,
                bundleIndex: bundleIndex,
                proposalId: draft.proposalId,
                choice: draft.choice,
              )
            : null,
      );
    }
  }

  @override
  Future<void> storeVoteTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) async {
    _addUnique(storedVoteTxHashes, '$bundleIndex:$proposalId:$txHash');
  }

  @override
  Future<void> markVoteSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) async {
    _addUnique(storedVoteTxHashes, '$bundleIndex:$proposalId:$txHash');
  }

  @override
  Future<void> markVoteConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required int vanPosition,
    required BigInt vcTreePosition,
    required String commitmentBundleJson,
  }) async {
    _addUnique(storedVoteTxHashes, '$bundleIndex:$proposalId:$txHash');
    storedVanPositions.add('$bundleIndex:$vanPosition');
    storedCommitmentBundles.add(
      '$bundleIndex:$proposalId:$vcTreePosition:$commitmentBundleJson',
    );
  }

  @override
  Future<void> storeCommitmentBundle({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String commitmentBundleJson,
    required BigInt vcTreePosition,
  }) async {
    storedCommitmentBundles.add(
      '$bundleIndex:$proposalId:$vcTreePosition:$commitmentBundleJson',
    );
  }

  @override
  Future<void> recordShareDelegation({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> sentToUrls,
    required List<int> nullifier,
    required BigInt submitAt,
  }) async {
    recordedShares.add(
      _RecordedShare(
        bundleIndex: bundleIndex,
        proposalId: proposalId,
        shareIndex: shareIndex,
        submitAt: submitAt,
      ),
    );
  }

  @override
  Future<void> markShareConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) async {}

  @override
  Future<String> computeShareNullifierHex({
    required List<int> voteCommitment,
    required int shareIndex,
    required List<int> primaryBlind,
  }) async {
    return List.filled(
      32,
      shareIndex,
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Future<List<int>> deriveHotkey({
    required List<int> seedBytes,
    required String roundId,
    required String accountUuid,
  }) async {
    return [roundId.length, accountUuid.length, ...seedBytes.take(2)];
  }
}

void _addUnique<T>(List<T> values, T value) {
  if (!values.contains(value)) {
    values.add(value);
  }
}

class _RecordedShare {
  const _RecordedShare({
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.submitAt,
  });

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final BigInt submitAt;
}

rust_voting.ApiSignedVoteCommitments _commitments({
  required String roundId,
  required int bundleIndex,
  required int proposalId,
  required int choice,
}) {
  final wireShare = rust_voting.ApiWireEncryptedShare(
    ciphertext1: Uint8List.fromList([8]),
    ciphertext2: Uint8List.fromList([9]),
    shareIndex: 0,
  );
  return rust_voting.ApiSignedVoteCommitments(
    bundleIndex: bundleIndex,
    commitments: [
      rust_voting.ApiSignedVoteCommitment(
        proposalId: proposalId,
        choice: choice,
        voteRoundId: roundId,
        vanNullifier: Uint8List.fromList(List.filled(32, 1)),
        voteAuthorityNoteNew: Uint8List.fromList(List.filled(32, 2)),
        voteCommitment: Uint8List.fromList(List.filled(32, 3)),
        proof: Uint8List.fromList([4]),
        encryptedShares: [wireShare],
        sharePayloads: [
          rust_voting.ApiVoteSharePayload(
            sharesHash: Uint8List.fromList(List.filled(32, 7)),
            proposalId: proposalId,
            voteDecision: choice,
            encryptedShare: wireShare,
            treePosition: BigInt.from(9),
            allEncryptedShares: [wireShare],
            shareComms: [Uint8List.fromList(List.filled(32, 10))],
            primaryBlind: Uint8List.fromList(List.filled(32, 11)),
          ),
        ],
        anchorHeight: 10,
        sharesHash: Uint8List.fromList(List.filled(32, 7)),
        shareComms: [Uint8List.fromList(List.filled(32, 10))],
        rVpkBytes: Uint8List.fromList(List.filled(32, 13)),
        voteAuthSig: Uint8List.fromList(List.filled(64, 12)),
        commitmentBundleJson: '{"proposal_id":$proposalId}',
      ),
    ],
  );
}
