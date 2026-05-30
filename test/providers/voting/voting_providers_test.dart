import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
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

  test('config source provider persists named saved sources', () async {
    final store = FakeVotingConfigSourceStore();
    final container = _container(
      http: FakeVotingHttpClient(responses: votingHttpResponses()),
      sourceStore: store,
    );
    addTearDown(container.dispose);

    await container.read(votingConfigSourceProvider.future);
    await container
        .read(votingConfigSourceProvider.notifier)
        .saveSource(
          name: 'Stage',
          sourceUrl: 'https://voting.example/static-voting-config.json',
        );

    final selected = container.read(votingConfigSourceProvider).value!;
    expect(selected.isDefault, isFalse);
    expect(
      selected.sourceUrl,
      'https://voting.example/static-voting-config.json',
    );
    expect(selected.savedSources, hasLength(1));
    expect(selected.savedSources.single.name, 'Stage');
    expect(store.savedSourcesJson, isNotNull);

    final restored = _container(
      http: FakeVotingHttpClient(responses: votingHttpResponses()),
      sourceStore: store,
    );
    addTearDown(restored.dispose);

    final restoredState = await restored.read(
      votingConfigSourceProvider.future,
    );
    expect(restoredState.savedSources, hasLength(1));
    expect(restoredState.savedSources.single.name, 'Stage');
    expect(restoredState.sourceUrl, selected.sourceUrl);
  });

  test('deleting active saved config source falls back to default', () async {
    final store = FakeVotingConfigSourceStore();
    final container = _container(
      http: FakeVotingHttpClient(responses: votingHttpResponses()),
      sourceStore: store,
    );
    addTearDown(container.dispose);

    await container.read(votingConfigSourceProvider.future);
    await container
        .read(votingConfigSourceProvider.notifier)
        .saveSource(
          name: 'Stage',
          sourceUrl: 'https://voting.example/static-voting-config.json',
        );
    final saved = container
        .read(votingConfigSourceProvider)
        .value!
        .savedSources
        .single;

    await container
        .read(votingConfigSourceProvider.notifier)
        .deleteSavedSource(saved.id);

    final next = container.read(votingConfigSourceProvider).value!;
    expect(next.isDefault, isTrue);
    expect(next.sourceUrl, kDefaultStaticVotingConfigSource);
    expect(next.savedSources, isEmpty);
    expect(store.sourceUrl, isNull);
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

  test(
    'rounds provider marks locally completed active rounds as voted',
    () async {
      final http = FakeVotingHttpClient(
        responses: {
          'https://voting.example/static-voting-config.json':
              staticConfigJson(),
          'https://voting.example/dynamic-voting-config.json':
              dynamicConfigJson(),
          '/shielded-vote/v1/rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
          '/shielded-vote/v1/endorsed-rounds/zodl': {
            'endorsed_round_ids': [kRoundId],
          },
        },
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          delegationTxHashes: [
            rust_voting.ApiDelegationTxRecovery(
              bundleIndex: 0,
              txHash: 'delegation-0',
            ),
          ],
          shareDelegations: [
            rust_voting.ApiShareDelegationRecord(
              roundId: kRoundId,
              bundleIndex: 0,
              proposalId: 7,
              shareIndex: 0,
              sentToUrls: const ['https://voting.example'],
              nullifier: Uint8List.fromList(List.filled(32, 1)),
              phase: VotingWorkflowPhase.submittedShare,
              confirmed: false,
              submitAt: BigInt.zero,
              createdAt: BigInt.zero,
            ),
          ],
          unconfirmedShareDelegations: [
            rust_voting.ApiShareDelegationRecord(
              roundId: kRoundId,
              bundleIndex: 0,
              proposalId: 7,
              shareIndex: 0,
              sentToUrls: const ['https://voting.example'],
              nullifier: Uint8List.fromList(List.filled(32, 1)),
              phase: VotingWorkflowPhase.submittedShare,
              confirmed: false,
              submitAt: BigInt.zero,
              createdAt: BigInt.zero,
            ),
          ],
        ),
        roundPlan: rust_voting.ApiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          nextSteps: const [
            rust_voting.ApiNextStep(
              kind: 'confirm_share',
              bundleIndex: 0,
              proposalId: 7,
              choice: 0,
              shareIndex: 0,
            ),
          ],
          openProposals: Uint32List(0),
          allDecided: true,
        ),
      );
      final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
      addTearDown(container.dispose);

      final rounds = await container.read(votingRoundsProvider.future);

      expect(rounds.single.voted, isTrue);
    },
  );

  test(
    'rounds provider loads planner state when summaries omit proposals',
    () async {
      final roundStatusWithProposals = roundStatusJson(roundId: kRoundId)
        ..['proposals'] = [
          {
            'proposal_id': 7,
            'title': 'Question',
            'options': ['Yes', 'No'],
          },
        ];
      final http = FakeVotingHttpClient(
        responses: {
          ...votingHttpResponses(roundStatus: roundStatusWithProposals),
          '/shielded-vote/v1/rounds': [
            {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
          ],
          '/shielded-vote/v1/endorsed-rounds/zodl': {
            'endorsed_round_ids': [kRoundId],
          },
        },
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(),
        roundPlan: rust_voting.ApiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          nextSteps: const [
            rust_voting.ApiNextStep(
              kind: 'vote',
              bundleIndex: 0,
              proposalId: 7,
              choice: 1,
              shareIndex: 0,
            ),
          ],
          openProposals: Uint32List(0),
          allDecided: false,
        ),
      );
      final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
      addTearDown(container.dispose);

      final rounds = await container.read(votingRoundsProvider.future);

      expect(rounds.single.inProgress, isTrue);
      expect(recoveryApi.roundPlanProposalIds, [
        [7],
      ]);
      expect(
        http.requests.any(
          (request) =>
              request.method == 'GET' &&
              request.uri.path == '/shielded-vote/v1/round/$kRoundId',
        ),
        isTrue,
      );
    },
  );

  test('rounds refresh keeps previous data when polling fails', () async {
    final responses = {
      'https://voting.example/static-voting-config.json': staticConfigJson(),
      'https://voting.example/dynamic-voting-config.json': dynamicConfigJson(),
      '/shielded-vote/v1/rounds': [
        {'vote_round_id': kRoundId, 'title': 'Poll', 'status': 'active'},
      ],
      '/shielded-vote/v1/endorsed-rounds/zodl': {
        'endorsed_round_ids': [kRoundId],
      },
    };
    final http = FakeVotingHttpClient(responses: responses);
    final container = _sessionContainer(http: http);
    addTearDown(container.dispose);

    final first = await container.read(votingRoundsProvider.future);
    responses['/shielded-vote/v1/rounds'] = StateError('network down');
    await container.read(votingRoundsProvider.notifier).refresh();

    final refreshed = container.read(votingRoundsProvider);
    expect(refreshed.hasValue, isTrue);
    expect(refreshed.value, first);
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

  test('wallet sync guard waits before delegation setup', () async {
    final rust = FakeVotingRustApi();
    final readiness = FakeVotingWalletSyncReadinessChecker(
      responses: const [
        VotingWalletSyncReadiness(
          scannedHeight: 122,
          snapshotHeight: 123,
          chainTipHeight: 130,
        ),
        VotingWalletSyncReadiness(
          scannedHeight: 123,
          snapshotHeight: 123,
          chainTipHeight: 130,
        ),
      ],
    );
    var syncStartCalls = 0;
    final container = _sessionContainer(
      rust: rust,
      walletSyncReadinessChecker: readiness,
      walletSyncStarter: () {
        syncStartCalls++;
      },
      walletSyncPollInterval: Duration.zero,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareDelegation();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(readiness.calls, 2);
    expect(syncStartCalls, 1);
    expect(rust.setupCalls, 1);
    expect(state.phase, VotingSessionPhase.readyToDelegate);
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

  test('submitted delegation timeout surfaces resumable tx context', () async {
    final httpResponses = votingHttpResponses()
      ..['/shielded-vote/v1/tx/submitted-delegation-tx'] = jsonResponse({
        'error': 'not found',
      }, statusCode: 404);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        delegationWorkflows: [
          rust_voting.ApiDelegationWorkflowRecovery(
            bundleIndex: 0,
            phase: VotingWorkflowPhase.submittedDelegation,
            txHash: 'submitted-delegation-tx',
            vanLeafPosition: null,
          ),
        ],
      ),
    );
    final container = _sessionContainer(
      http: FakeVotingHttpClient(responses: httpResponses),
      recoveryApi: recoveryApi,
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(seedBytes: [1, 2, 3]);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('submitted-delegation-tx'));
    expect(state.error?.message, contains('bundle 0'));
    expect(state.error?.message, contains('Retry to resume confirmation'));
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

  test('delegation stream errors surface the Rust failure', () async {
    final rust = FakeVotingRustApi(
      delegationStreamError: StateError(
        'network: gRPC connect failed: transport error',
      ),
    );
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(seedBytes: [1, 2, 3]);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('gRPC connect failed'));
    expect(
      state.error?.message,
      isNot(contains('Delegation proof completed without submission payload')),
    );
    expect(rust.delegationBundleCalls, [0]);
    expect(rust.storedDelegationTxHashes, isEmpty);
  });

  test('hardware voting prepares Keystone signing request', () async {
    final rust = FakeVotingRustApi();
    final hotkeyStore = FakeVotingHotkeyStore(null);
    final container = _sessionContainer(
      rust: rust,
      accountIsHardware: true,
      hotkeyStore: hotkeyStore,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.keystoneSigning);
    expect(state.isHardwareAccount, isTrue);
    expect(state.keystoneSigningRequest?.bundleIndex, 0);
    expect(hotkeyStore.hotkey, [42, 43, 44]);
    expect(rust.generateVotingHotkeyCalls, 1);
    expect(rust.keystoneDelegationRequestCalls, [0, 0]);
  });

  test(
    'hardware voting permits prepared-only recovery without stored hotkey',
    () async {
      final rust = FakeVotingRustApi();
      final hotkeyStore = FakeVotingHotkeyStore(null);
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          delegationWorkflows: [
            rust_voting.ApiDelegationWorkflowRecovery(
              bundleIndex: 0,
              phase: VotingWorkflowPhase.prepared,
              txHash: null,
              vanLeafPosition: null,
            ),
          ],
        ),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
        hotkeyStore: hotkeyStore,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneSigningRequest?.bundleIndex, 0);
      expect(hotkeyStore.hotkey, [42, 43, 44]);
      expect(rust.setupCalls, 1);
      expect(rust.generateVotingHotkeyCalls, 1);
      expect(rust.keystoneDelegationRequestCalls, [0]);
    },
  );

  test('software delegation entry point rejects hardware sessions', () async {
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(rust: rust, accountIsHardware: true);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundles(seedBytes: [1, 2, 3]);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('Keystone'));
    expect(rust.delegationBundleCalls, isEmpty);
  });

  test(
    'hardware voting rejects wrong Keystone signature without storing',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([99, 0]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneScanError, contains('different voting bundle'));
      expect(rust.storedKeystoneSignatures, isEmpty);
      expect(rust.extractSpendAuthSignatureCalls, 0);
    },
  );

  test(
    'hardware voting rejects duplicate Keystone signature before extraction',
    () async {
      final rust = FakeVotingRustApi();
      rust.storedKeystoneSignatures[1] = rust_voting.ApiKeystoneSignatureRecord(
        bundleIndex: 1,
        sig: Uint8List.fromList(const [7]),
        sighash: Uint8List.fromList(const [99, 0]),
        rk: Uint8List.fromList(const [8]),
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([99, 0]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneScanError, contains('already scanned'));
      expect(rust.extractSpendAuthSignatureCalls, 0);
    },
  );

  test(
    'hardware voting stores valid Keystone signature and becomes ready',
    () async {
      final rust = FakeVotingRustApi();
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([10, 0]);
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.keystoneSigningRequest, isNull);
      expect(state.keystoneSignatures.keys, [0]);
      expect(rust.storedKeystoneSignatures[0]?.sig, [3, 0]);
    },
  );

  test('hardware voting advances signing across multiple bundles', () async {
    final rust = FakeVotingRustApi(bundleCount: 2);
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(bundleCount: 2),
    );
    final container = _sessionContainer(
      rust: rust,
      recoveryApi: recoveryApi,
      accountIsHardware: true,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .prepareKeystoneSigning();
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .handleKeystoneSignedPczt([10, 0]);
    var state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.keystoneSigning);
    expect(state.keystoneSigningRequest?.bundleIndex, 1);
    expect(state.keystoneSignatures.keys, [0]);
    expect(rust.keystoneDelegationRequestCalls, [0, 1]);

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .handleKeystoneSignedPczt([10, 1]);
    state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.readyToDelegate);
    expect(state.keystoneSigningRequest, isNull);
    expect(state.keystoneSignatures.keys, [0, 1]);

    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .delegatePendingBundlesWithKeystoneSignatures();
    state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.delegated);
    expect(rust.keystoneProofBundleCalls, [0, 1]);
    expect(rust.storedDelegationTxHashes, [
      '0:delegation-tx',
      '1:delegation-tx',
    ]);
  });

  test(
    'hardware voting can skip unsigned Keystone bundles after prefix signed',
    () async {
      late FakeVotingRecoveryApi recoveryApi;
      final rust = FakeVotingRustApi(
        bundleCount: 2,
        onDeleteSkippedBundles: (keepCount) {
          recoveryApi.state = recoveryState(bundleCount: keepCount);
        },
      );
      recoveryApi = FakeVotingRecoveryApi(state: recoveryState(bundleCount: 2));
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .handleKeystoneSignedPczt([10, 0]);
      var state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.keystoneSigning);
      expect(state.keystoneSigningRequest?.bundleIndex, 1);
      expect(state.canSkipRemainingKeystoneBundles, isTrue);

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .skipRemainingKeystoneBundles();
      state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.readyToDelegate);
      expect(state.resumePlan?.bundleCount, 1);
      expect(state.keystoneSigningRequest, isNull);
      expect(rust.deleteSkippedBundleKeepCounts, [1]);
      expect(rust.storedKeystoneSignatures.keys, [0]);

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.delegated);
      expect(rust.keystoneProofBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
    },
  );

  test(
    'hardware voting cannot skip across missing Keystone bundle prefix',
    () async {
      final rust = FakeVotingRustApi(bundleCount: 2);
      rust.storedKeystoneSignatures[1] = rust_voting.ApiKeystoneSignatureRecord(
        bundleIndex: 1,
        sig: Uint8List.fromList(const [3, 1]),
        sighash: Uint8List.fromList(const [10, 1]),
        rk: Uint8List.fromList(const [2, 1]),
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(bundleCount: 2),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      var state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.keystoneSigningRequest?.bundleIndex, 0);
      expect(state.canSkipRemainingKeystoneBundles, isFalse);

      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .skipRemainingKeystoneBundles();
      state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('Sign at least one'));
      expect(rust.deleteSkippedBundleKeepCounts, isEmpty);
    },
  );

  test(
    'hardware voting does not regenerate hotkey after stored signature',
    () async {
      final rust = FakeVotingRustApi(bundleCount: 2);
      rust.storedKeystoneSignatures[0] = rust_voting.ApiKeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(bundleCount: 2),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        accountIsHardware: true,
        hotkeyStore: FakeVotingHotkeyStore(null),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .prepareKeystoneSigning();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('missing stored Keystone'));
      expect(rust.generateVotingHotkeyCalls, 0);
      expect(rust.keystoneDelegationRequestCalls, isEmpty);
    },
  );

  test(
    'hardware voting submits delegation with stored Keystone signature',
    () async {
      final rust = FakeVotingRustApi();
      rust.storedKeystoneSignatures[0] = rust_voting.ApiKeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.delegated);
      expect(rust.keystoneProofBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, ['0:delegation-tx']);
      expect(rust.storedVanPositions, ['0:0']);
    },
  );

  test(
    'hardware voting does not regenerate hotkey while submitting signatures',
    () async {
      final rust = FakeVotingRustApi();
      rust.storedKeystoneSignatures[0] = rust_voting.ApiKeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final container = _sessionContainer(
        rust: rust,
        accountIsHardware: true,
        hotkeyStore: FakeVotingHotkeyStore(null),
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('missing stored Keystone'));
      expect(rust.generateVotingHotkeyCalls, 0);
      expect(rust.keystoneProofBundleCalls, isEmpty);
      expect(rust.storedDelegationTxHashes, isEmpty);
    },
  );

  test(
    'hardware voting rejects mismatched Keystone submission payload',
    () async {
      final rust = FakeVotingRustApi(mismatchKeystoneSubmission: true);
      rust.storedKeystoneSignatures[0] = rust_voting.ApiKeystoneSignatureRecord(
        bundleIndex: 0,
        sig: Uint8List.fromList(const [3, 0]),
        sighash: Uint8List.fromList(const [10, 0]),
        rk: Uint8List.fromList(const [2, 0]),
      );
      final container = _sessionContainer(rust: rust, accountIsHardware: true);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .delegatePendingBundlesWithKeystoneSignatures();
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.error);
      expect(state.error?.message, contains('did not match'));
      expect(rust.keystoneProofBundleCalls, [0]);
      expect(rust.storedDelegationTxHashes, isEmpty);
    },
  );

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

  test('draft choices are isolated by pinned voting account', () async {
    final activeAccount = _MutableActiveAccount('account-1');
    final container = _sessionContainer(activeAccountUuid: activeAccount.call);
    addTearDown(container.dispose);

    final session = await container.read(
      votingSessionProvider(kRoundId).future,
    );
    final pinnedDraftKey = VotingSessionKey(
      roundId: kRoundId,
      accountUuid: session.accountUuid!,
    );
    container
        .read(votingDraftProvider(pinnedDraftKey).notifier)
        .setChoice(7, 1);
    activeAccount.value = 'account-2';

    const switchedDraftKey = VotingSessionKey(
      roundId: kRoundId,
      accountUuid: 'account-2',
    );
    expect(
      container.read(votingSessionProvider(kRoundId)).value?.accountUuid,
      'account-1',
    );
    expect(container.read(votingDraftProvider(pinnedDraftKey)).choices, {7: 1});
    expect(container.read(votingDraftProvider(switchedDraftKey)).isEmpty, true);
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

      expect(
        _postBodyJson(http, '/shielded-vote/v1/delegate-vote'),
        _delegationSubmissionWireGolden,
      );
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

  test(
    'vote submission progress displays questions while bundle work advances',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
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
        ),
      );
      final container = _sessionContainer(rust: rust, recoveryApi: recoveryApi);
      addTearDown(container.dispose);
      final observed = <VotingSessionState>[];
      final subscription = container.listen<AsyncValue<VotingSessionState>>(
        votingSessionProvider(kRoundId),
        (_, next) {
          final value = next.asData?.value;
          if (value != null) observed.add(value);
        },
      );
      addTearDown(subscription.close);

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
      final state = container.read(votingSessionProvider(kRoundId)).value!;

      expect(state.phase, VotingSessionPhase.submittingShares);
      expect(state.voteSubmissionCompletedCount, 2);
      expect(state.voteSubmissionTotalCount, 2);
      expect(state.voteSubmissionProgress, 1);
      expect(rust.voteCommitBundleCalls, [0, 1, 0, 1]);

      final activeProgressCounts = observed
          .where((state) => state.voteSubmissionTotalCount == 2)
          .map((state) => state.voteSubmissionCompletedCount)
          .toSet();
      expect(activeProgressCounts, containsAll(<int>{0, 1, 2}));
      expect(
        observed
            .where((state) => state.voteSubmissionTotalCount == 2)
            .map((state) => state.voteSubmissionProgress)
            .whereType<double>(),
        containsAll(<double>[0, 0.25, 0.5, 0.75, 1]),
      );

      final submittingShareStates = observed
          .where((state) => state.phase == VotingSessionPhase.submittingShares)
          .toList(growable: false);
      expect(submittingShareStates, hasLength(1));
      expect(submittingShareStates.single.voteSubmissionCompletedCount, 2);
    },
  );

  test('draft votes persist and can be cleared proposal by proposal', () async {
    final persistence = FakeVotingDraftPersistence();
    final key = const VotingSessionKey(
      roundId: kRoundId,
      accountUuid: 'account-1',
    );
    await persistence.save(key, const VotingDraftState(choices: {7: 1, 8: 0}));
    final container = ProviderContainer(
      overrides: [
        votingDraftPersistenceProvider.overrideWithValue(persistence),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(votingDraftProvider(key).notifier);
    final loaded = await notifier.ensureLoaded();
    expect(loaded.choices, {7: 1, 8: 0});

    notifier.clearChoice(7);
    await Future<void>.delayed(Duration.zero);

    expect((await persistence.load(key)).choices, {8: 0});
  });

  test(
    'partial vote resume submits persisted drafts not already on chain',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
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
          voteTxHashes: [
            rust_voting.ApiVoteTxRecovery(
              bundleIndex: 0,
              proposalId: 7,
              txHash: 'vote-tx-0-7',
            ),
            rust_voting.ApiVoteTxRecovery(
              bundleIndex: 1,
              proposalId: 7,
              txHash: 'vote-tx-1-7',
            ),
          ],
          commitmentBundles: [
            rust_voting.ApiCommitmentBundleRecovery(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(2),
            ),
            rust_voting.ApiCommitmentBundleRecovery(
              bundleIndex: 1,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(3),
            ),
          ],
        ),
      );
      final persistence = FakeVotingDraftPersistence();
      const draftKey = VotingSessionKey(
        roundId: kRoundId,
        accountUuid: 'account-1',
      );
      await persistence.save(
        draftKey,
        const VotingDraftState(choices: {7: 1, 8: 0, 9: 1}),
      );
      final container = _sessionContainer(
        rust: rust,
        recoveryApi: recoveryApi,
        draftPersistence: persistence,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      final loadedDraft = await container
          .read(votingDraftProvider(draftKey).notifier)
          .ensureLoaded();
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: loadedDraft.toDraftVotes([
              VotingProposalView(
                id: 7,
                title: 'One',
                description: '',
                options: [
                  VotingOptionView(index: 0, label: 'No'),
                  VotingOptionView(index: 1, label: 'Yes'),
                ],
              ),
              VotingProposalView(
                id: 8,
                title: 'Two',
                description: '',
                options: [
                  VotingOptionView(index: 0, label: 'No'),
                  VotingOptionView(index: 1, label: 'Yes'),
                ],
              ),
              VotingProposalView(
                id: 9,
                title: 'Three',
                description: '',
                options: [
                  VotingOptionView(index: 0, label: 'No'),
                  VotingOptionView(index: 1, label: 'Yes'),
                ],
              ),
            ]),
          );

      expect(rust.voteCommitmentKeys, ['0:8', '1:8', '0:9', '1:9']);
      expect((await persistence.load(draftKey)).choices, {7: 1, 8: 0, 9: 1});
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .submitPendingShares();
      expect((await persistence.load(draftKey)).choices, isEmpty);
    },
  );

  test(
    'resume submits interrupted earlier bundle before later proposal casts',
    () async {
      final rust = FakeVotingRustApi(emitCommitments: true, bundleCount: 2);
      final recoveryApi = FakeVotingRecoveryApi(
        roundPlan: rust_voting.ApiRoundPlan(
          roundId: kRoundId,
          pendingRecovery: true,
          nextSteps: const [
            rust_voting.ApiNextStep(
              kind: 'submit_vote',
              bundleIndex: 1,
              proposalId: 7,
              shareIndex: 0,
              choice: 0,
            ),
            rust_voting.ApiNextStep(
              kind: 'cast_vote',
              bundleIndex: 0,
              proposalId: 8,
              shareIndex: 0,
              choice: 1,
            ),
            rust_voting.ApiNextStep(
              kind: 'cast_vote',
              bundleIndex: 1,
              proposalId: 8,
              shareIndex: 0,
              choice: 1,
            ),
          ],
          openProposals: Uint32List.fromList(const [9]),
          allDecided: false,
        ),
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
          voteTxHashes: [
            rust_voting.ApiVoteTxRecovery(
              bundleIndex: 0,
              proposalId: 7,
              txHash: 'vote-tx-0-7',
            ),
          ],
          commitmentBundles: [
            rust_voting.ApiCommitmentBundleRecovery(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(2),
            ),
            rust_voting.ApiCommitmentBundleRecovery(
              bundleIndex: 1,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(3),
            ),
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
              rust_voting.ApiDraftVote(
                proposalId: 8,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(rust.recoveredVoteCommitmentKeys, ['1:7']);
      expect(rust.voteCommitmentKeys, ['0:8', '1:8']);
      expect(rust.operationLog.take(5).toList(), [
        'recover_vote:1:7',
        'mark_vote_submitted:1:7',
        'mark_vote_confirmed:1:7',
        'record_share:1:7:0',
        'build_vote:0:8',
      ]);
    },
  );

  test('resume submits missing shares before later proposal casts', () async {
    final rust = FakeVotingRustApi(
      emitCommitments: true,
      bundleCount: 2,
      commitmentShareCount: 2,
    );
    final existingShare = rust_voting.ApiShareDelegationRecord(
      roundId: kRoundId,
      bundleIndex: 1,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://voting.example'],
      nullifier: Uint8List.fromList(List.filled(32, 1)),
      phase: VotingWorkflowPhase.confirmed,
      confirmed: true,
      submitAt: BigInt.zero,
      createdAt: BigInt.zero,
    );
    final recoveryApi = FakeVotingRecoveryApi(
      roundPlan: rust_voting.ApiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_voting.ApiNextStep(
            kind: 'submit_shares',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 1,
            choice: 0,
          ),
          rust_voting.ApiNextStep(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
          rust_voting.ApiNextStep(
            kind: 'cast_vote',
            bundleIndex: 1,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
        ],
        openProposals: Uint32List.fromList(const [9]),
        allDecided: false,
      ),
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
        votes: [vote(bundleIndex: 1, proposalId: 7)],
        voteTxHashes: [
          rust_voting.ApiVoteTxRecovery(
            bundleIndex: 1,
            proposalId: 7,
            txHash: 'vote-tx-1-7',
          ),
        ],
        commitmentBundles: [
          rust_voting.ApiCommitmentBundleRecovery(
            bundleIndex: 1,
            proposalId: 7,
            commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
            vcTreePosition: BigInt.from(55),
          ),
        ],
        shareDelegations: [existingShare],
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
              proposalId: 8,
              choice: 1,
              numOptions: 2,
              vcTreePosition: BigInt.zero,
              singleShare: false,
            ),
          ],
        );

    expect(rust.recoveredVoteCommitmentKeys, ['1:7']);
    expect(
      rust.recordedShares
          .where((share) => share.bundleIndex == 1 && share.proposalId == 7)
          .map((share) => share.shareIndex)
          .toList(),
      [1],
    );
    expect(rust.storedVoteTxHashes, isNot(contains('1:7:vote-tx')));
    expect(rust.voteCommitmentKeys, ['0:8', '1:8']);
    expect(rust.operationLog.take(3).toList(), [
      'recover_vote:1:7',
      'record_share:1:7:1',
      'build_vote:0:8',
    ]);
  });

  test(
    'resume refreshes planner after vote confirmation before later proposal casts',
    () async {
      final httpResponses = votingHttpResponses()
        ..['/shielded-vote/v1/tx/submitted-vote-tx'] = {
          'height': 11,
          'code': 0,
          'log': '',
          'events': [
            {
              'type': 'cast_vote',
              'attributes': [
                {'key': 'leaf_index', 'value': '1,55'},
              ],
            },
          ],
        };
      final rust = FakeVotingRustApi(
        emitCommitments: true,
        bundleCount: 2,
        commitmentShareCount: 2,
      );
      final beforeConfirmation = rust_voting.ApiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_voting.ApiNextStep(
            kind: 'poll_vote',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 0,
            choice: 0,
          ),
          rust_voting.ApiNextStep(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
          rust_voting.ApiNextStep(
            kind: 'cast_vote',
            bundleIndex: 1,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
      final afterConfirmation = rust_voting.ApiRoundPlan(
        roundId: kRoundId,
        pendingRecovery: true,
        nextSteps: const [
          rust_voting.ApiNextStep(
            kind: 'submit_shares',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 0,
            choice: 0,
          ),
          rust_voting.ApiNextStep(
            kind: 'submit_shares',
            bundleIndex: 1,
            proposalId: 7,
            shareIndex: 1,
            choice: 0,
          ),
          rust_voting.ApiNextStep(
            kind: 'cast_vote',
            bundleIndex: 0,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
          rust_voting.ApiNextStep(
            kind: 'cast_vote',
            bundleIndex: 1,
            proposalId: 8,
            shareIndex: 0,
            choice: 1,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: false,
      );
      final recoveryApi = FakeVotingRecoveryApi(
        roundPlanSequence: [
          beforeConfirmation,
          beforeConfirmation,
          afterConfirmation,
        ],
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
          votes: [vote(bundleIndex: 1, proposalId: 7)],
          voteWorkflows: [
            rust_voting.ApiVoteWorkflowRecovery(
              bundleIndex: 1,
              proposalId: 7,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'submitted-vote-tx',
              vcTreePosition: null,
              hasCommitmentBundle: true,
            ),
          ],
          voteTxHashes: [
            rust_voting.ApiVoteTxRecovery(
              bundleIndex: 1,
              proposalId: 7,
              txHash: 'submitted-vote-tx',
            ),
          ],
          commitmentBundles: [
            rust_voting.ApiCommitmentBundleRecovery(
              bundleIndex: 1,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(proposalId: 7),
              vcTreePosition: BigInt.from(55),
            ),
          ],
        ),
      );
      final container = _sessionContainer(
        http: FakeVotingHttpClient(responses: httpResponses),
        rust: rust,
        recoveryApi: recoveryApi,
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(
            draftVotes: [
              rust_voting.ApiDraftVote(
                proposalId: 8,
                choice: 1,
                numOptions: 2,
                vcTreePosition: BigInt.zero,
                singleShare: false,
              ),
            ],
          );

      expect(rust.recoveredVoteCommitmentKeys, ['1:7']);
      expect(
        rust.recordedShares
            .where((share) => share.bundleIndex == 1 && share.proposalId == 7)
            .map((share) => share.shareIndex)
            .toList(),
        [0, 1],
      );
      expect(rust.voteCommitmentKeys, ['0:8', '1:8']);
      expect(rust.operationLog.take(5).toList(), [
        'mark_vote_confirmed:1:7',
        'recover_vote:1:7',
        'record_share:1:7:0',
        'record_share:1:7:1',
        'build_vote:0:8',
      ]);
    },
  );

  test('submitted vote timeout surfaces resumable tx context', () async {
    final httpResponses = votingHttpResponses()
      ..['/shielded-vote/v1/tx/submitted-vote-tx'] = jsonResponse({
        'error': 'not found',
      }, statusCode: 404);
    final rust = FakeVotingRustApi();
    final recoveryApi = FakeVotingRecoveryApi(
      state: recoveryState(
        bundleCount: 1,
        votes: [vote(bundleIndex: 0, proposalId: 7)],
        voteWorkflows: [
          rust_voting.ApiVoteWorkflowRecovery(
            bundleIndex: 0,
            proposalId: 7,
            phase: VotingWorkflowPhase.submittedVote,
            txHash: 'submitted-vote-tx',
            vcTreePosition: null,
            hasCommitmentBundle: true,
          ),
        ],
        voteTxHashes: [
          rust_voting.ApiVoteTxRecovery(
            bundleIndex: 0,
            proposalId: 7,
            txHash: 'submitted-vote-tx',
          ),
        ],
        commitmentBundles: [
          rust_voting.ApiCommitmentBundleRecovery(
            bundleIndex: 0,
            proposalId: 7,
            commitmentBundleJson: '{"proposal_id":7}',
            vcTreePosition: BigInt.zero,
          ),
        ],
      ),
    );
    final container = _sessionContainer(
      http: FakeVotingHttpClient(responses: httpResponses),
      rust: rust,
      recoveryApi: recoveryApi,
      txConfirmationPolling: _fastTxConfirmationPolling,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .castVotes(draftVotes: const []);
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('submitted-vote-tx'));
    expect(state.error?.message, contains('bundle 0, proposal 7'));
    expect(state.error?.message, contains('Retry to resume confirmation'));
    expect(rust.voteCommitBundleCalls, isEmpty);
  });

  test(
    'recovery-only vote confirmation does not rewrite ballot intents',
    () async {
      final httpResponses = votingHttpResponses()
        ..['/shielded-vote/v1/tx/submitted-vote-tx'] = {
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
        };
      final rust = FakeVotingRustApi();
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          votes: [vote(bundleIndex: 0, proposalId: 7)],
          voteWorkflows: [
            rust_voting.ApiVoteWorkflowRecovery(
              bundleIndex: 0,
              proposalId: 7,
              phase: VotingWorkflowPhase.submittedVote,
              txHash: 'submitted-vote-tx',
              vcTreePosition: null,
              hasCommitmentBundle: true,
            ),
          ],
          voteTxHashes: [
            rust_voting.ApiVoteTxRecovery(
              bundleIndex: 0,
              proposalId: 7,
              txHash: 'submitted-vote-tx',
            ),
          ],
          commitmentBundles: [
            rust_voting.ApiCommitmentBundleRecovery(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: '{"proposal_id":7}',
              vcTreePosition: BigInt.zero,
            ),
          ],
        ),
      );
      final container = _sessionContainer(
        http: FakeVotingHttpClient(responses: httpResponses),
        rust: rust,
        recoveryApi: recoveryApi,
        txConfirmationPolling: _fastTxConfirmationPolling,
      );
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .castVotes(draftVotes: const [], allProposalIds: const [7, 8]);

      expect(recoveryApi.ballotIntents, isEmpty);
      expect(rust.voteCommitBundleCalls, isEmpty);
      expect(rust.storedCommitmentBundles, ['0:7:2']);
    },
  );

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
          allProposalIds: const [7, 8],
          proposalOptionCounts: const {8: 4},
        );

    expect(recoveryApi.ballotIntents, ['7:2:false:1', '8:4:true:null']);
    expect(rust.recordedShares, hasLength(1));
    expect(rust.recordedShares.single.bundleIndex, 0);
    expect(rust.recordedShares.single.proposalId, 7);
    expect(rust.recordedShares.single.submitAt, BigInt.zero);
    expect(rust.storedVoteTxHashes, ['0:7:vote-tx']);
    expect(rust.storedCommitmentBundles, ['0:7:2']);
  });

  test('ballot intent write failure aborts before vote submission', () async {
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
      setBallotIntentError: StateError('intent write failed'),
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
          allProposalIds: const [7, 8],
          proposalOptionCounts: const {8: 4},
        );

    final state = container.read(votingSessionProvider(kRoundId)).value!;
    expect(state.phase, VotingSessionPhase.error);
    expect(state.error?.message, contains('intent write failed'));
    expect(recoveryApi.ballotIntents, isEmpty);
    expect(rust.voteCommitBundleCalls, isEmpty);
    expect(rust.storedVoteTxHashes, isEmpty);
    expect(rust.recordedShares, isEmpty);
  });

  test('initial share submission uses planned helper targets', () async {
    final helperUrls = [
      for (var i = 1; i <= 6; i++)
        {'url': 'https://helper-$i.example', 'label': 'helper-$i'},
    ];
    final http = FakeVotingHttpClient(
      responses: votingHttpResponses(
        dynamicConfig: dynamicConfigJson(voteServers: helperUrls),
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

    final sharePosts = http.requests.where(
      (request) =>
          request.method == 'POST' &&
          request.uri.path == '/shielded-vote/v1/shares',
    );
    expect(sharePosts.map((request) => request.uri.host), [
      'helper-1.example',
      'helper-2.example',
      'helper-3.example',
    ]);
    expect(rust.recordedShares.single.sentToUrls, [
      'https://helper-1.example',
      'https://helper-2.example',
      'https://helper-3.example',
    ]);
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

      expect(
        _postBodyJson(http, '/shielded-vote/v1/cast-vote'),
        _voteCommitmentWireGolden,
      );
      expect(
        _postBodyJson(http, '/shielded-vote/v1/shares'),
        _voteShareWireGolden,
      );
    },
  );

  test('accepted unconfirmed shares confirm from any accepted helper', () async {
    final shareNullifier = Uint8List.fromList(List.filled(32, 1));
    final shareId = _hexFromBytes(shareNullifier);
    final acceptedShare = rust_voting.ApiShareDelegationRecord(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const [
        'https://helper-a.example',
        'https://helper-b.example',
      ],
      nullifier: shareNullifier,
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
    final rust = FakeVotingRustApi();
    final container = _sessionContainer(
      http: FakeVotingHttpClient(
        responses:
            votingHttpResponses(
              dynamicConfig: dynamicConfigJson(
                voteServers: const [
                  {'url': 'https://helper-a.example', 'label': 'helper-a'},
                  {'url': 'https://helper-b.example', 'label': 'helper-b'},
                ],
              ),
            )..addAll({
              'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  {'status': 'pending'},
              'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                  {'status': 'confirmed'},
            }),
      ),
      rust: rust,
      recoveryApi: recoveryApi,
    );
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .submitPendingShares();
    final state = container.read(votingSessionProvider(kRoundId)).value!;

    expect(state.phase, VotingSessionPhase.done);
    expect(state.resumePlan?.unconfirmedShareDelegations, [acceptedShare]);
    expect(rust.confirmedShares, ['0:7:0']);
  });

  test(
    'share recovery waits until submit_at plus grace before polling',
    () async {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final shareNullifier = Uint8List.fromList(List.filled(32, 3));
      final futureShare = rust_voting.ApiShareDelegationRecord(
        roundId: kRoundId,
        bundleIndex: 0,
        proposalId: 7,
        shareIndex: 0,
        sentToUrls: const ['https://helper-a.example'],
        nullifier: shareNullifier,
        phase: VotingWorkflowPhase.submittedShare,
        confirmed: false,
        submitAt: BigInt.from(nowSeconds + 100),
        createdAt: BigInt.from(nowSeconds),
      );
      final recoveryApi = FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 1,
          commitmentBundles: [
            rust_voting.ApiCommitmentBundleRecovery(
              bundleIndex: 0,
              proposalId: 7,
              commitmentBundleJson: commitmentBundleRecoveryJson(),
              vcTreePosition: BigInt.from(42),
            ),
          ],
          shareDelegations: [futureShare],
          unconfirmedShareDelegations: [futureShare],
        ),
      );
      final http = FakeVotingHttpClient(
        responses: votingHttpResponses(
          dynamicConfig: dynamicConfigJson(
            voteServers: const [
              {'url': 'https://helper-a.example', 'label': 'helper-a'},
              {'url': 'https://helper-b.example', 'label': 'helper-b'},
            ],
          ),
        ),
      );
      final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
      addTearDown(container.dispose);

      await container.read(votingSessionProvider(kRoundId).future);
      await container
          .read(votingSessionProvider(kRoundId).notifier)
          .submitPendingShares();

      expect(
        http.requests.where(
          (request) => request.uri.path.contains('/share-status/'),
        ),
        isEmpty,
      );
      expect(
        http.requests.where(
          (request) =>
              request.method == 'POST' &&
              request.uri.host == 'helper-b.example',
        ),
        isEmpty,
      );
      expect(recoveryApi.addedSentServers, isEmpty);
    },
  );

  test('pending share recovery resubmits helpers missed initially', () async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shareNullifier = Uint8List.fromList(List.filled(32, 2));
    final shareId = _hexFromBytes(shareNullifier);
    final pendingShare = rust_voting.ApiShareDelegationRecord(
      roundId: kRoundId,
      bundleIndex: 0,
      proposalId: 7,
      shareIndex: 0,
      sentToUrls: const ['https://helper-a.example'],
      nullifier: shareNullifier,
      phase: VotingWorkflowPhase.submittedShare,
      confirmed: false,
      submitAt: BigInt.from(123),
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
        commitmentBundles: [
          rust_voting.ApiCommitmentBundleRecovery(
            bundleIndex: 0,
            proposalId: 7,
            commitmentBundleJson: commitmentBundleRecoveryJson(),
            vcTreePosition: BigInt.from(42),
          ),
        ],
        shareDelegations: [pendingShare],
        unconfirmedShareDelegations: [pendingShare],
      ),
    );
    final http = FakeVotingHttpClient(
      responses:
          votingHttpResponses(
            roundStatus: roundStatusJson(
              roundId: kRoundId,
              ceremonyStart: 0,
              voteEnd: nowSeconds + 1000,
            ),
            dynamicConfig: dynamicConfigJson(
              voteServers: const [
                {'url': 'https://helper-a.example', 'label': 'helper-a'},
                {'url': 'https://helper-b.example', 'label': 'helper-b'},
              ],
            ),
          )..addAll({
            'https://helper-a.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'pending'},
            'https://helper-b.example/shielded-vote/v1/share-status/$kRoundId/$shareId':
                {'status': 'pending'},
          }),
    );
    final container = _sessionContainer(http: http, recoveryApi: recoveryApi);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .submitPendingShares();

    final helperBPost = http.requests.singleWhere(
      (request) =>
          request.method == 'POST' && request.uri.host == 'helper-b.example',
    );
    expect(helperBPost.uri.path, '/shielded-vote/v1/shares');
    expect(helperBPost.body?['vote_round_id'], kRoundId);
    expect(helperBPost.body?['tree_position'], 42);
    expect(helperBPost.body?['submit_at'], 0);
    expect(helperBPost.body?['enc_share'], {
      'c1': base64Encode([8]),
      'c2': base64Encode([9]),
      'share_index': 0,
    });
    expect(recoveryApi.addedSentServers, [
      _AddedSentServers(0, 7, 0, const ['https://helper-b.example']),
    ]);
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

  test('delegation PIR warmup owns and zeros task-local seed bytes', () async {
    final precomputeGate = Completer<void>();
    final rust = FakeVotingRustApi(precomputeGate: precomputeGate);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);
    final seedBytes = [1, 2, 3];

    await container.read(votingSessionProvider(kRoundId).future);
    await container
        .read(votingSessionProvider(kRoundId).notifier)
        .precomputeDelegationPir(seedBytes: seedBytes);
    await rust.precomputeStarted.future;

    seedBytes.fillRange(0, seedBytes.length, 0);
    expect(rust.precomputeSeedRefs.single, [1, 2, 3]);
    expect(identical(rust.precomputeSeedRefs.single, seedBytes), isFalse);

    precomputeGate.complete();
    await rust.precomputeFinished.future;
    await Future<void>.delayed(Duration.zero);

    expect(rust.precomputeSeedRefs.single, [0, 0, 0]);
  });

  test('delegation phase activates while waiting for PIR warmup', () async {
    final precomputeGate = Completer<void>();
    final rust = FakeVotingRustApi(precomputeGate: precomputeGate);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.precomputeDelegationPir(seedBytes: [1, 2, 3]);
    await rust.precomputeStarted.future;

    final delegationFuture = notifier.delegatePendingBundles(
      seedBytes: [1, 2, 3],
    );

    VotingSessionState? activeState;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
      final state = container.read(votingSessionProvider(kRoundId)).value;
      if (state?.phase == VotingSessionPhase.delegating) {
        activeState = state;
        break;
      }
    }

    expect(activeState?.currentBundleIndex, 0);
    expect(rust.delegationBundleCalls, isEmpty);

    precomputeGate.complete();
    await delegationFuture;

    final finalState = container.read(votingSessionProvider(kRoundId)).value!;
    expect(finalState.phase, VotingSessionPhase.delegated);
    expect(rust.delegationBundleCalls, [0]);
  });

  test('delegation PIR warmup failure is a non-fatal cache miss', () async {
    final rust = FakeVotingRustApi(failPrecompute: true);
    final container = _sessionContainer(rust: rust);
    addTearDown(container.dispose);

    await container.read(votingSessionProvider(kRoundId).future);
    final notifier = container.read(votingSessionProvider(kRoundId).notifier);
    await notifier.precomputeDelegationPir(seedBytes: [1, 2, 3]);
    await notifier.delegatePendingBundles(seedBytes: [1, 2, 3]);

    expect(rust.precomputedDelegationPir, [0]);
    expect(rust.delegationBundleCalls, [0]);
    expect(rust.resetVotingSessionStateCalls, isEmpty);
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

ProviderContainer _container({
  required VotingHttpClient http,
  VotingConfigSourceStore? sourceStore,
}) {
  return ProviderContainer(
    overrides: [
      votingConfigSourceStoreProvider.overrideWithValue(
        sourceStore ?? FakeVotingConfigSourceStore(),
      ),
      votingHttpClientProvider.overrideWithValue(http),
      votingConfigLoaderProvider.overrideWithValue(
        VotingConfigLoader(
          httpClient: http,
          staticConfigSource: StaticVotingConfigSource.parse(
            'https://voting.example/static-voting-config.json',
          ),
        ),
      ),
      votingActiveAccountUuidProvider.overrideWithValue(() async => null),
    ],
  );
}

ProviderContainer _sessionContainer({
  FakeVotingHttpClient? http,
  FakeVotingRustApi? rust,
  FakeVotingRecoveryApi? recoveryApi,
  VotingDraftPersistence? draftPersistence,
  PirSnapshotResolver? pirResolver,
  VotingHotkeyStore? hotkeyStore,
  Future<String?> Function()? activeAccountUuid,
  bool accountIsHardware = false,
  Set<String>? hardwareAccountUuids,
  VotingTxConfirmationPolling? txConfirmationPolling,
  VotingWalletSyncReadinessChecker? walletSyncReadinessChecker,
  void Function()? walletSyncStarter,
  Duration? walletSyncPollInterval,
}) {
  final effectiveHttp =
      http ?? FakeVotingHttpClient(responses: votingHttpResponses());
  final effectiveHardwareAccountUuids =
      hardwareAccountUuids ?? (accountIsHardware ? {'account-1'} : <String>{});
  return ProviderContainer(
    overrides: [
      votingConfigSourceStoreProvider.overrideWithValue(
        FakeVotingConfigSourceStore(),
      ),
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
      votingAccountIsHardwareProvider.overrideWithValue(
        (uuid) async => effectiveHardwareAccountUuids.contains(uuid),
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
      votingDraftPersistenceProvider.overrideWithValue(
        draftPersistence ?? FakeVotingDraftPersistence(),
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
      votingHotkeyStoreProvider.overrideWithValue(
        hotkeyStore ?? FakeVotingHotkeyStore([9, 9, 9]),
      ),
      votingWalletSyncReadinessCheckerProvider.overrideWithValue(
        walletSyncReadinessChecker ?? FakeVotingWalletSyncReadinessChecker(),
      ),
      votingWalletSyncStarterProvider.overrideWithValue(
        walletSyncStarter ?? () {},
      ),
      votingWalletSyncPollIntervalProvider.overrideWithValue(
        walletSyncPollInterval ?? Duration.zero,
      ),
      if (txConfirmationPolling != null)
        votingTxConfirmationPollingProvider.overrideWithValue(
          txConfirmationPolling,
        ),
    ],
  );
}

Map<String, dynamic> _postBody(FakeVotingHttpClient http, String path) {
  final request = http.requests.singleWhere(
    (request) => request.method == 'POST' && request.uri.path == path,
  );
  return request.body!;
}

String _postBodyJson(FakeVotingHttpClient http, String path) =>
    jsonEncode(_postBody(http, path));

Map<String, Object> votingHttpResponses({
  Map<String, dynamic>? roundStatus,
  Map<String, dynamic>? dynamicConfig,
}) => {
  'https://voting.example/static-voting-config.json': staticConfigJson(),
  'https://voting.example/dynamic-voting-config.json':
      dynamicConfig ?? dynamicConfigJson(),
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
const _roundIdBase64 = 'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqo=';
const _bytes1x32Base64 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _bytes2x32Base64 = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';
const _bytes3x32Base64 = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=';
const _bytes7x32Base64 = 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=';
const _bytes10x32Base64 = 'CgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo=';
const _bytes11x32Base64 = 'CwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws=';
const _bytes12x64Base64 =
    'DAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA==';
const _bytes13x32Base64 = 'DQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0NDQ0=';
const _delegationSubmissionWireGolden =
    '{"rk":"Ag==","spend_auth_sig":"Aw==","sighash":"BA==","signed_note_nullifier":"BQ==","cmx_new":"Bg==","van_cmx":"Bw==","gov_nullifiers":["CA=="],"proof":"AQ==","vote_round_id":"$_roundIdBase64"}';
const _voteCommitmentWireGolden =
    '{"van_nullifier":"$_bytes1x32Base64","vote_authority_note_new":"$_bytes2x32Base64","vote_commitment":"$_bytes3x32Base64","proposal_id":7,"proof":"BA==","vote_round_id":"$_roundIdBase64","vote_comm_tree_anchor_height":10,"r_vpk":"$_bytes13x32Base64","vote_auth_sig":"$_bytes12x64Base64"}';
const _voteShareWireGolden =
    '{"vote_round_id":"$kRoundId","shares_hash":"$_bytes7x32Base64","proposal_id":7,"vote_decision":1,"enc_share":{"c1":"CA==","c2":"CQ==","share_index":0},"share_index":0,"tree_position":2,"all_enc_shares":[{"c1":"CA==","c2":"CQ==","share_index":0}],"share_comms":["$_bytes10x32Base64"],"primary_blind":"$_bytes11x32Base64","submit_at":0}';
const _fastTxConfirmationPolling = VotingTxConfirmationPolling(
  attempts: 1,
  delay: Duration.zero,
);

Map<String, dynamic> staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _hex32},
  ],
};

Map<String, dynamic> dynamicConfigJson({
  List<Map<String, String>> voteServers = const [
    {'url': 'https://voting.example', 'label': 'primary'},
  ],
}) => {
  'config_version': 1,
  'vote_servers': voteServers,
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
  'ceremony_phase_start': ?ceremonyStart,
  'vote_end_time': ?voteEnd,
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
  );
}

String commitmentBundleRecoveryJson({int proposalId = 7, int shareIndex = 0}) {
  return jsonEncode({
    'format': 'vizor_vote_commitment_bundle_recovery_v1',
    'share_payloads': [
      {
        'shares_hash': _hexFromBytes(List.filled(32, 7)),
        'proposal_id': proposalId,
        'vote_decision': 1,
        'enc_share': {
          'c1': _hexFromBytes([8]),
          'c2': _hexFromBytes([9]),
          'share_index': shareIndex,
        },
        'tree_position': 2,
        'all_enc_shares': [
          {
            'c1': _hexFromBytes([8]),
            'c2': _hexFromBytes([9]),
            'share_index': shareIndex,
          },
        ],
        'share_comms': [_hexFromBytes(List.filled(32, 10))],
        'primary_blind': _hexFromBytes(List.filled(32, 11)),
      },
    ],
  });
}

String _hexFromBytes(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

List<int> _bytesFromHex(String hex) {
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

class FakeVotingRecoveryApi implements VotingRecoveryApi {
  rust_voting.ApiRoundRecoveryState state;
  rust_voting.ApiRoundPlan? roundPlan;
  final List<rust_voting.ApiRoundPlan>? roundPlanSequence;
  final walletIds = <String>[];
  final addedSentServers = <_AddedSentServers>[];
  final ballotIntents = <String>[];
  final roundPlanProposalIds = <List<int>>[];
  final Object? setBallotIntentError;
  var _roundPlanCallCount = 0;

  FakeVotingRecoveryApi({
    required this.state,
    this.roundPlan,
    this.roundPlanSequence,
    this.setBallotIntentError,
  });

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) async {
    addedSentServers.add(
      _AddedSentServers(bundleIndex, proposalId, shareIndex, newUrls),
    );
  }

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

  @override
  Future<rust_voting.ApiRoundPlan> getRoundPlan({
    required String dbPath,
    required String walletId,
    required String roundId,
    required List<int> proposalIds,
  }) async {
    roundPlanProposalIds.add(List<int>.from(proposalIds));
    final sequence = roundPlanSequence;
    if (sequence != null && sequence.isNotEmpty) {
      var index = _roundPlanCallCount;
      _roundPlanCallCount++;
      if (index >= sequence.length) index = sequence.length - 1;
      return sequence[index];
    }
    return roundPlan ??
        rust_voting.ApiRoundPlan(
          roundId: roundId,
          pendingRecovery: false,
          nextSteps: const [],
          openProposals: Uint32List.fromList(proposalIds),
          allDecided: false,
        );
  }

  @override
  Future<void> setBallotIntent({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  }) async {
    final error = setBallotIntentError;
    if (error != null) {
      throw error;
    }
    ballotIntents.add('$proposalId:$numOptions:$skipped:${choice ?? 'null'}');
  }
}

class FakeVotingDraftPersistence implements VotingDraftPersistence {
  final _stored = <VotingSessionKey, VotingDraftState>{};

  @override
  Future<VotingDraftState> load(VotingSessionKey key) async {
    return _stored[key] ?? const VotingDraftState();
  }

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {
    if (draft.choices.isEmpty) {
      _stored.remove(key);
    } else {
      _stored[key] = VotingDraftState(choices: Map.of(draft.choices));
    }
  }
}

class _AddedSentServers {
  const _AddedSentServers(
    this.bundleIndex,
    this.proposalId,
    this.shareIndex,
    this.newUrls,
  );

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final List<String> newUrls;

  @override
  bool operator ==(Object other) =>
      other is _AddedSentServers &&
      other.bundleIndex == bundleIndex &&
      other.proposalId == proposalId &&
      other.shareIndex == shareIndex &&
      _listEquals(other.newUrls, newUrls);

  @override
  int get hashCode => Object.hash(bundleIndex, proposalId, shareIndex, newUrls);

  @override
  String toString() =>
      '_AddedSentServers($bundleIndex, $proposalId, $shareIndex, $newUrls)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
  List<int>? hotkey;

  FakeVotingHotkeyStore(this.hotkey);

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
  }) async {
    this.hotkey = List<int>.from(hotkey);
  }

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

class FakeVotingConfigSourceStore implements VotingConfigSourceStore {
  FakeVotingConfigSourceStore({this.sourceUrl, this.savedSourcesJson});

  String? sourceUrl;
  String? savedSourcesJson;

  @override
  Future<String?> readSourceUrl() async => sourceUrl;

  @override
  Future<void> writeSourceUrl(String sourceUrl) async {
    this.sourceUrl = sourceUrl;
  }

  @override
  Future<void> resetSourceUrl() async {
    sourceUrl = null;
  }

  @override
  Future<String?> readSavedSourcesJson() async => savedSourcesJson;

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) async {
    this.savedSourcesJson = savedSourcesJson;
  }
}

class FakeVotingWalletSyncReadinessChecker
    implements VotingWalletSyncReadinessChecker {
  FakeVotingWalletSyncReadinessChecker({this.responses = const []});

  final List<VotingWalletSyncReadiness> responses;
  int calls = 0;

  @override
  Future<VotingWalletSyncReadiness> check({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  }) async {
    final index = calls;
    calls++;
    if (responses.isNotEmpty) {
      return responses[index < responses.length ? index : responses.length - 1];
    }
    return VotingWalletSyncReadiness(
      scannedHeight: snapshotHeight,
      snapshotHeight: snapshotHeight,
      chainTipHeight: snapshotHeight,
    );
  }
}

class FakeVotingRustApi implements VotingRustApi {
  FakeVotingRustApi({
    this.setupDelay = Duration.zero,
    this.emitCommitments = false,
    this.precomputeGate,
    this.failPrecompute = false,
    this.bundleCount = 1,
    this.commitmentShareCount = 1,
    this.mismatchKeystoneSubmission = false,
    this.delegationStreamError,
    this.onDeleteSkippedBundles,
  });

  final Duration setupDelay;
  final bool emitCommitments;
  final Completer<void>? precomputeGate;
  final bool failPrecompute;
  final int bundleCount;
  final int commitmentShareCount;
  final bool mismatchKeystoneSubmission;
  final Object? delegationStreamError;
  final void Function(int keepCount)? onDeleteSkippedBundles;
  int setupCalls = 0;
  int _activeSetups = 0;
  int maxConcurrentSetups = 0;
  final delegationBundleCalls = <int>[];
  final voteCommitBundleCalls = <int>[];
  final voteCommitmentKeys = <String>[];
  final recoveredVoteCommitmentKeys = <String>[];
  final storedDelegationTxHashes = <String>[];
  final storedVoteTxHashes = <String>[];
  final storedCommitmentBundles = <String>[];
  final storedVanPositions = <String>[];
  final operationLog = <String>[];
  final recordedShares = <_RecordedShare>[];
  final syncedVoteTrees = <String>[];
  final precomputedDelegationPir = <int>[];
  final precomputeSeedRefs = <List<int>>[];
  final precomputeStarted = Completer<void>();
  final precomputeFinished = Completer<void>();
  final resetVotingSessionStateCalls = <String>[];
  final draftSingleShareValues = <bool>[];
  final accountUuids = <String>[];
  final confirmedShares = <String>[];
  final keystoneDelegationRequestCalls = <int>[];
  final keystoneProofBundleCalls = <int>[];
  final deleteSkippedBundleKeepCounts = <int>[];
  final storedKeystoneSignatures =
      <int, rust_voting.ApiKeystoneSignatureRecord>{};
  int generateVotingHotkeyCalls = 0;
  int extractSpendAuthSignatureCalls = 0;

  @override
  Future<rust_voting.ApiVotingBundleSetupResult> setupDelegationBundles({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    int? maxRealNotesPerBundle,
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
      bundleCount: bundleCount,
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
    int? maxRealNotesPerBundle,
  }) async* {
    accountUuids.add(accountUuid);
    delegationBundleCalls.add(bundleIndex);
    final error = delegationStreamError;
    if (error != null) throw error;
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
  Future<List<int>> generateVotingHotkey({required String network}) async {
    generateVotingHotkeyCalls++;
    return [42, 43, 44];
  }

  @override
  Future<rust_voting.ApiKeystoneDelegationRequest>
  buildKeystoneDelegationRequest({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> hotkeySeed,
    required int bundleIndex,
    int? maxRealNotesPerBundle,
  }) async {
    accountUuids.add(accountUuid);
    keystoneDelegationRequestCalls.add(bundleIndex);
    return rust_voting.ApiKeystoneDelegationRequest(
      pcztBytes: Uint8List.fromList([20, bundleIndex]),
      redactedPcztBytes: Uint8List.fromList([21, bundleIndex]),
      pcztSighash: Uint8List.fromList([10, bundleIndex]),
      rk: Uint8List.fromList([2, bundleIndex]),
      actionIndex: 0,
      displayMemo:
          'I am authorizing this hotkey managed by my wallet to vote on $roundName with 0.00000100 ZEC.',
      eligibleWeightZatoshi: BigInt.from(100),
      delegatedWeightZatoshi: BigInt.from(100),
      bundleCount: bundleCount,
      bundleIndex: bundleIndex,
    );
  }

  @override
  Future<List<int>> extractPcztSighash({required List<int> pcztBytes}) async {
    return List<int>.from(pcztBytes);
  }

  @override
  Future<List<int>> extractSpendAuthSignatureFromSignedPczt({
    required List<int> signedPcztBytes,
    required int actionIndex,
  }) async {
    extractSpendAuthSignatureCalls++;
    return [3, actionIndex];
  }

  @override
  Future<void> storeKeystoneSignature({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required List<int> sig,
    required List<int> sighash,
    required List<int> rk,
  }) async {
    storedKeystoneSignatures[bundleIndex] =
        rust_voting.ApiKeystoneSignatureRecord(
          bundleIndex: bundleIndex,
          sig: Uint8List.fromList(sig),
          sighash: Uint8List.fromList(sighash),
          rk: Uint8List.fromList(rk),
        );
  }

  @override
  Future<List<rust_voting.ApiKeystoneSignatureRecord>> getKeystoneSignatures({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    final records = storedKeystoneSignatures.values.toList()
      ..sort((a, b) => a.bundleIndex.compareTo(b.bundleIndex));
    return records;
  }

  @override
  Future<int> deleteSkippedBundles({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int keepCount,
  }) async {
    deleteSkippedBundleKeepCounts.add(keepCount);
    final removed = storedKeystoneSignatures.keys
        .where((bundleIndex) => bundleIndex >= keepCount)
        .toList();
    for (final bundleIndex in removed) {
      storedKeystoneSignatures.remove(bundleIndex);
    }
    onDeleteSkippedBundles?.call(keepCount);
    return bundleCount - keepCount;
  }

  @override
  Stream<rust_voting.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> hotkeySeed,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
    int? maxRealNotesPerBundle,
  }) async* {
    accountUuids.add(accountUuid);
    keystoneProofBundleCalls.add(bundleIndex);
    final signature = storedKeystoneSignatures[bundleIndex];
    final rk = mismatchKeystoneSubmission
        ? const [99]
        : signature?.rk ?? const [2];
    yield rust_voting.ApiDelegationProofEvent(
      phase: 'result',
      proofProgress: null,
      signedDelegationPayload: rust_voting.ApiSignedDelegationPayload(
        pcztBytes: Uint8List.fromList(const []),
        status: 'ready_for_submission',
        message: null,
        proof: Uint8List.fromList(const [1]),
        rk: Uint8List.fromList(rk),
        spendAuthSig: Uint8List.fromList(keystoneSig),
        sighash: Uint8List.fromList(keystoneSighash),
        nfSigned: Uint8List.fromList(const [5]),
        cmxNew: Uint8List.fromList(const [6]),
        govComm: Uint8List.fromList(const [7]),
        govNullifiers: [
          Uint8List.fromList(const [8]),
        ],
        voteRoundId: roundParams.voteRoundId,
        eligibleWeightZatoshi: BigInt.from(100),
        delegatedWeightZatoshi: BigInt.from(100),
        bundleCount: bundleCount,
        bundleIndex: bundleIndex,
      ),
    );
  }

  @override
  Future<String> delegationSubmissionWireJson({
    required rust_voting.ApiSignedDelegationPayload submission,
  }) async {
    return jsonEncode({
      'rk': base64Encode(submission.rk),
      'spend_auth_sig': base64Encode(submission.spendAuthSig),
      'sighash': base64Encode(submission.sighash),
      'signed_note_nullifier': base64Encode(submission.nfSigned),
      'cmx_new': base64Encode(submission.cmxNew),
      'van_cmx': base64Encode(submission.govComm),
      'gov_nullifiers': submission.govNullifiers.map(base64Encode).toList(),
      'proof': base64Encode(submission.proof),
      'vote_round_id': base64Encode(_bytesFromHex(submission.voteRoundId)),
    });
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
    int? maxRealNotesPerBundle,
  }) async {
    accountUuids.add(accountUuid);
    precomputedDelegationPir.add(bundleIndex);
    precomputeSeedRefs.add(seedBytes);
    if (!precomputeStarted.isCompleted) {
      precomputeStarted.complete();
    }
    try {
      await precomputeGate?.future;
      if (failPrecompute) {
        throw StateError('precompute failed');
      }
    } finally {
      if (!precomputeFinished.isCompleted) {
        precomputeFinished.complete();
      }
    }
    return rust_voting.ApiDelegationPirPrecomputeResult(
      cachedCount: 0,
      fetchedCount: 1,
      bundleCount: bundleCount,
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
      voteCommitmentKeys.add('$bundleIndex:${draft.proposalId}');
      operationLog.add('build_vote:$bundleIndex:${draft.proposalId}');
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
                shareCount: commitmentShareCount,
              )
            : null,
      );
    }
  }

  @override
  Future<rust_voting.ApiSignedVoteCommitments> recoverVoteCommitment({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
  }) async {
    recoveredVoteCommitmentKeys.add('$bundleIndex:$proposalId');
    operationLog.add('recover_vote:$bundleIndex:$proposalId');
    return _commitments(
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      choice: 1,
      shareCount: commitmentShareCount,
    );
  }

  @override
  Future<String> voteCommitmentWireJson({
    required rust_voting.ApiSignedVoteCommitment commitment,
  }) async {
    return jsonEncode({
      'van_nullifier': base64Encode(commitment.vanNullifier),
      'vote_authority_note_new': base64Encode(commitment.voteAuthorityNoteNew),
      'vote_commitment': base64Encode(commitment.voteCommitment),
      'proposal_id': commitment.proposalId,
      'proof': base64Encode(commitment.proof),
      'vote_round_id': base64Encode(_bytesFromHex(commitment.voteRoundId)),
      'vote_comm_tree_anchor_height': commitment.anchorHeight,
      'r_vpk': base64Encode(commitment.rVpkBytes),
      'vote_auth_sig': base64Encode(commitment.voteAuthSig),
    });
  }

  @override
  Future<String> voteShareWireJson({
    required rust_voting.ApiVoteSharePayload payload,
    BigInt? vcTreePosition,
    required BigInt submitAt,
  }) async {
    return jsonEncode(
      _shareWireMap(
        sharesHash: payload.sharesHash,
        proposalId: payload.proposalId,
        voteDecision: payload.voteDecision,
        encryptedShare: payload.encryptedShare,
        treePosition: vcTreePosition ?? payload.treePosition,
        allEncryptedShares: payload.allEncryptedShares,
        shareComms: payload.shareComms,
        primaryBlind: payload.primaryBlind,
        submitAt: submitAt,
      ),
    );
  }

  @override
  Future<List<rust_voting.ApiShareSubmissionPlan>> planShareSubmissions({
    required int shareCount,
    required List<String> serverUrls,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    BigInt? lastMomentBufferSeconds,
    required bool singleShare,
  }) async {
    final targetCount = serverUrls.isEmpty ? 0 : (serverUrls.length / 2).ceil();
    final now = nowSeconds.toInt();
    final voteEnd = voteEndTimeSeconds.toInt();
    final buffer = lastMomentBufferSeconds?.toInt();
    final deadline = buffer == null ? now : voteEnd - buffer;
    final submitAt = singleShare || buffer == null || deadline <= now
        ? BigInt.zero
        : BigInt.from(now + 1);
    return [
      for (var i = 0; i < shareCount; i++)
        rust_voting.ApiShareSubmissionPlan(
          submitAt: submitAt,
          targetCount: targetCount,
          targetServers: serverUrls.take(targetCount).toList(growable: false),
        ),
    ];
  }

  @override
  Future<int> shareTrackingFlags({
    required rust_voting.ApiShareDelegationRecord share,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  }) async {
    final now = nowSeconds.toInt();
    final base = share.submitAt > BigInt.zero
        ? share.submitAt.toInt()
        : share.createdAt.toInt();
    var flags = 0;
    if (!share.confirmed && now >= base + 10) {
      flags |= 1;
    }
    final voteEnd = voteEndTimeSeconds?.toInt();
    if (!share.confirmed && voteEnd != null) {
      final remaining = (voteEnd - base).clamp(0, 1 << 31).toInt();
      final threshold = (remaining ~/ 4).clamp(30, 3600).toInt();
      if (now >= base + threshold && voteEnd > now + 10) {
        flags |= 2;
      }
    }
    return flags;
  }

  @override
  Future<BigInt?> nextShareTrackingDelaySeconds({
    required List<rust_voting.ApiShareDelegationRecord> shares,
    required BigInt nowSeconds,
  }) async {
    final now = nowSeconds.toInt();
    int? nextSecond;
    var hasUnconfirmed = false;
    for (final share in shares.where((share) => !share.confirmed)) {
      hasUnconfirmed = true;
      final base = share.submitAt > BigInt.zero
          ? share.submitAt.toInt()
          : share.createdAt.toInt();
      final checkAt = base + 10;
      if (checkAt > now && (nextSecond == null || checkAt < nextSecond)) {
        nextSecond = checkAt;
      }
    }
    if (!hasUnconfirmed) return null;
    final delay = nextSecond == null
        ? 15
        : (nextSecond - now).clamp(0, 30).toInt();
    return BigInt.from(delay < 3 ? 3 : delay);
  }

  @override
  Future<String> recoveredVoteShareWireJson({
    required String commitmentBundleJson,
    required int proposalId,
    required int shareIndex,
    required BigInt vcTreePosition,
    required BigInt submitAt,
  }) async {
    final decoded = jsonDecode(commitmentBundleJson) as Map<String, dynamic>;
    final payloads = decoded['share_payloads'] as List<dynamic>;
    final payload = payloads.cast<Map<String, dynamic>>().singleWhere((
      payload,
    ) {
      final encShare = payload['enc_share'] as Map<String, dynamic>;
      return payload['proposal_id'] == proposalId &&
          encShare['share_index'] == shareIndex;
    });
    final encShare = payload['enc_share'] as Map<String, dynamic>;
    return jsonEncode({
      'shares_hash': base64Encode(
        _bytesFromHex(payload['shares_hash'] as String),
      ),
      'proposal_id': proposalId,
      'vote_decision': payload['vote_decision'],
      'enc_share': {
        'c1': base64Encode(_bytesFromHex(encShare['c1'] as String)),
        'c2': base64Encode(_bytesFromHex(encShare['c2'] as String)),
        'share_index': shareIndex,
      },
      'share_index': shareIndex,
      'tree_position': vcTreePosition.toInt(),
      'all_enc_shares': (payload['all_enc_shares'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (share) => {
              'c1': base64Encode(_bytesFromHex(share['c1'] as String)),
              'c2': base64Encode(_bytesFromHex(share['c2'] as String)),
              'share_index': share['share_index'],
            },
          )
          .toList(),
      'share_comms': (payload['share_comms'] as List<dynamic>)
          .cast<String>()
          .map((hex) => base64Encode(_bytesFromHex(hex)))
          .toList(),
      'primary_blind': base64Encode(
        _bytesFromHex(payload['primary_blind'] as String),
      ),
      'submit_at': submitAt.toInt(),
    });
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
    operationLog.add('mark_vote_submitted:$bundleIndex:$proposalId');
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
  }) async {
    _addUnique(storedVoteTxHashes, '$bundleIndex:$proposalId:$txHash');
    operationLog.add('mark_vote_confirmed:$bundleIndex:$proposalId');
    storedVanPositions.add('$bundleIndex:$vanPosition');
    storedCommitmentBundles.add('$bundleIndex:$proposalId:$vcTreePosition');
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
    required BigInt submitAt,
  }) async {
    operationLog.add('record_share:$bundleIndex:$proposalId:$shareIndex');
    recordedShares.add(
      _RecordedShare(
        bundleIndex: bundleIndex,
        proposalId: proposalId,
        shareIndex: shareIndex,
        submitAt: submitAt,
        sentToUrls: sentToUrls,
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
  }) async {
    confirmedShares.add('$bundleIndex:$proposalId:$shareIndex');
  }

  @override
  Future<List<int>> deriveHotkey({
    required List<int> seedBytes,
    required String roundId,
    required String accountUuid,
    required String network,
  }) async {
    return [
      roundId.length,
      accountUuid.length,
      network.length,
      ...seedBytes.take(2),
    ];
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
    required this.sentToUrls,
  });

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final BigInt submitAt;
  final List<String> sentToUrls;
}

rust_voting.ApiSignedVoteCommitments _commitments({
  required String roundId,
  required int bundleIndex,
  required int proposalId,
  required int choice,
  int shareCount = 1,
}) {
  final wireShares = [
    for (var shareIndex = 0; shareIndex < shareCount; shareIndex++)
      rust_voting.ApiWireEncryptedShare(
        ciphertext1: Uint8List.fromList(
          shareCount == 1 ? [8] : [8, shareIndex],
        ),
        ciphertext2: Uint8List.fromList(
          shareCount == 1 ? [9] : [9, shareIndex],
        ),
        shareIndex: shareIndex,
      ),
  ];
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
        encryptedShares: wireShares,
        sharePayloads: [
          for (final wireShare in wireShares)
            rust_voting.ApiVoteSharePayload(
              sharesHash: Uint8List.fromList(List.filled(32, 7)),
              proposalId: proposalId,
              voteDecision: choice,
              encryptedShare: wireShare,
              treePosition: BigInt.from(9),
              allEncryptedShares: wireShares,
              shareComms: [
                for (var i = 0; i < shareCount; i++)
                  Uint8List.fromList(List.filled(32, 10 + i)),
              ],
              primaryBlind: Uint8List.fromList(
                List.filled(32, 11 + wireShare.shareIndex),
              ),
            ),
        ],
        anchorHeight: 10,
        sharesHash: Uint8List.fromList(List.filled(32, 7)),
        shareComms: [
          for (var i = 0; i < shareCount; i++)
            Uint8List.fromList(List.filled(32, 10 + i)),
        ],
        rVpkBytes: Uint8List.fromList(List.filled(32, 13)),
        voteAuthSig: Uint8List.fromList(List.filled(64, 12)),
        commitmentBundleJson: '{"proposal_id":$proposalId}',
      ),
    ],
  );
}

Map<String, dynamic> _shareWireMap({
  required List<int> sharesHash,
  required int proposalId,
  required int voteDecision,
  required rust_voting.ApiWireEncryptedShare encryptedShare,
  required BigInt treePosition,
  required List<rust_voting.ApiWireEncryptedShare> allEncryptedShares,
  required List<List<int>> shareComms,
  required List<int> primaryBlind,
  required BigInt submitAt,
}) {
  Map<String, dynamic> wireShare(rust_voting.ApiWireEncryptedShare share) {
    return {
      'c1': base64Encode(share.ciphertext1),
      'c2': base64Encode(share.ciphertext2),
      'share_index': share.shareIndex,
    };
  }

  return {
    'shares_hash': base64Encode(sharesHash),
    'proposal_id': proposalId,
    'vote_decision': voteDecision,
    'enc_share': wireShare(encryptedShare),
    'share_index': encryptedShare.shareIndex,
    'tree_position': treePosition.toInt(),
    'all_enc_shares': allEncryptedShares.map(wireShare).toList(),
    'share_comms': shareComms.map(base64Encode).toList(),
    'primary_blind': base64Encode(primaryBlind),
    'submit_at': submitAt.toInt(),
  };
}
