import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_voting;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';

import '../../services/voting/fake_voting_http.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  testWidgets('status screen explains null mnemonic voting requirement', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final http = FakeVotingHttpClient(responses: _votingHttpResponses());
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        syncProvider.overrideWith(_NoopSyncNotifier.new),
        accountProvider.overrideWith(_NoMnemonicAccountNotifier.new),
        votingHttpClientProvider.overrideWithValue(http),
        votingConfigLoaderProvider.overrideWithValue(
          VotingConfigLoader(
            httpClient: http,
            staticConfigSource: StaticVotingConfigSource.parse(
              'https://voting.example/static-voting-config.json',
            ),
          ),
        ),
        votingWalletDbPathProvider.overrideWithValue(() async => 'wallet.db'),
        votingActiveAccountUuidProvider.overrideWithValue(
          () async => 'account-1',
        ),
        votingRpcEndpointConfigProvider.overrideWithValue(
          const RpcEndpointConfig(
            networkName: 'main',
            lightwalletdUrl: 'https://lightwalletd.example:443',
          ),
        ),
        votingRecoveryServiceProvider.overrideWithValue(
          VotingRecoveryService(api: _FakeVotingRecoveryApi()),
        ),
        votingRustApiProvider.overrideWithValue(_NoopVotingRustApi()),
      ],
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Software Account Required'), findsOneWidget);
    expect(
      find.text(
        'Coinholder voting requires a software account. Switch to a software account to vote in this round.',
      ),
      findsOneWidget,
    );
    expect(find.text('Submitting Votes'), findsNothing);
  });

  testWidgets('status screen reports empty draft as retryable error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose at least one vote before submitting.'), findsOne);
    expect(find.text('Retry'), findsOne);
  });

  testWidgets('status screen keeps async session errors specific', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final container = _statusContainer(
      accountOverride: _MnemonicAccountNotifier.new,
      activeAccountUuid: () => throw StateError('active account lookup failed'),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('active account lookup failed'), findsOne);
    expect(find.text('Voting session action failed.'), findsNothing);
    expect(find.text('Retry'), findsOne);
  });

  testWidgets('status screen navigates after successful submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..addAll({
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
          '/shielded-vote/v1/cast-vote': {
            'tx_hash': 'vote-tx',
            'code': 0,
            'log': '',
          },
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
          '/shielded-vote/v1/shares': {'share_id': '0102'},
        }),
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _MnemonicAccountNotifier.new,
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container.read(votingDraftProvider(_draftKey).notifier).setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    await tester.pumpAndSettle();

    expect(find.text('submission confirmed route'), findsOne);
    expect(
      find.text('Choose at least one vote before submitting.'),
      findsNothing,
    );
  });

  testWidgets('hardware status screen scans Keystone signature and submits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final http = FakeVotingHttpClient(
      responses: _votingHttpResponses()
        ..addAll({
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
          '/shielded-vote/v1/cast-vote': {
            'tx_hash': 'vote-tx',
            'code': 0,
            'log': '',
          },
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
          '/shielded-vote/v1/shares': {'share_id': '0102'},
        }),
    );
    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      http: http,
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container
        .read(
          votingDraftProvider(
            const VotingSessionKey(
              roundId: _roundId,
              accountUuid: 'hardware-1',
            ),
          ).notifier,
        )
        .setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _statusHarness(keystoneScanResult: const [3]),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Sign Bundle 1 of 1').evaluate().isNotEmpty) break;
    }

    expect(find.text('Sign Bundle 1 of 1'), findsOneWidget);
    expect(find.text('Scan Signature'), findsOneWidget);
    expect(find.text('Software Account Required'), findsNothing);
    await tester.tap(find.text('Scan Signature'));
    await tester.pumpAndSettle();

    expect(find.text('keystone scan route'), findsOneWidget);
    await tester.tap(find.text('Return Signature'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('submission confirmed route').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('submission confirmed route'), findsOneWidget);
  });

  testWidgets('hardware status screen shows retry when Keystone QR fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      _RustApiFake.failPcztEncoding = false;
      await tester.binding.setSurfaceSize(null);
    });
    _RustApiFake.failPcztEncoding = true;

    final recoveryApi = _MutableVotingRecoveryApi();
    final container = _statusContainer(
      accountOverride: _HardwareAccountNotifier.new,
      activeAccountUuid: () async => 'hardware-1',
      accountIsHardware: true,
      hardwareAccountUuids: const {'hardware-1'},
      recoveryApi: recoveryApi,
      rust: _VotingStatusRustApi(recoveryApi),
      hotkeyStore: const _FakeVotingHotkeyStore([9, 9, 9]),
    );
    addTearDown(container.dispose);
    container
        .read(
          votingDraftProvider(
            const VotingSessionKey(
              roundId: _roundId,
              accountUuid: 'hardware-1',
            ),
          ).notifier,
        )
        .setChoice(1, 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _statusHarness()),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .textContaining('Failed to prepare Keystone voting QR')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(
      find.textContaining('Failed to prepare Keystone voting QR'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Scan Signature'), findsNothing);
  });
}

ProviderContainer _statusContainer({
  FakeVotingHttpClient? http,
  AccountNotifier Function()? accountOverride,
  Future<String?> Function()? activeAccountUuid,
  bool accountIsHardware = false,
  Set<String>? hardwareAccountUuids,
  VotingRecoveryApi? recoveryApi,
  VotingRustApi? rust,
  VotingHotkeyStore? hotkeyStore,
}) {
  final effectiveHttp =
      http ?? FakeVotingHttpClient(responses: _votingHttpResponses());
  final effectiveHardwareAccountUuids =
      hardwareAccountUuids ??
      (accountIsHardware ? {'account-1', 'hardware-1'} : <String>{});
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(_NoopSyncNotifier.new),
      if (accountOverride != null)
        accountProvider.overrideWith(accountOverride),
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
        VotingRecoveryService(api: recoveryApi ?? _FakeVotingRecoveryApi()),
      ),
      votingPirResolverProvider.overrideWithValue(
        const _MatchedPirSnapshotResolver(),
      ),
      votingRustApiProvider.overrideWithValue(rust ?? _NoopVotingRustApi()),
      if (hotkeyStore != null)
        votingHotkeyStoreProvider.overrideWithValue(hotkeyStore),
      votingTxConfirmationPollingProvider.overrideWithValue(
        const VotingTxConfirmationPolling(attempts: 1, delay: Duration.zero),
      ),
    ],
  );
}

Widget _statusHarness({List<int>? keystoneScanResult}) {
  final router = GoRouter(
    initialLocation: '/voting/poll/$_roundId/status',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/status',
        builder: (_, state) =>
            VotingStatusScreen(roundId: state.pathParameters['roundId']!),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/submitted',
        builder: (_, _) => const Text('submission confirmed route'),
      ),
      GoRoute(
        path: '/voting/keystone/scan',
        builder: (_, _) =>
            _ScanReturnScreen(result: keystoneScanResult ?? const [3]),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings route'),
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

class _ScanReturnScreen extends StatelessWidget {
  const _ScanReturnScreen({required this.result});

  final List<int> result;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('keystone scan route'),
          TextButton(
            onPressed: () => context.pop<List<int>>(result),
            child: const Text('Return Signature'),
          ),
        ],
      ),
    );
  }
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/voting/poll/$_roundId/status',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1votingstatusaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Map<String, Object> _votingHttpResponses() => {
  'https://voting.example/static-voting-config.json': _staticConfigJson(),
  'https://voting.example/dynamic-voting-config.json': _dynamicConfigJson(),
  '/shielded-vote/v1/round/$_roundId': {'round': _roundStatusJson()},
};

const _roundId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _draftKey = VotingSessionKey(roundId: _roundId, accountUuid: 'account-1');
const _hex32 =
    '0101010101010101010101010101010101010101010101010101010101010101';

Map<String, dynamic> _staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _hex32},
  ],
};

Map<String, dynamic> _dynamicConfigJson() => {
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
    _roundId: {
      'auth_version': 1,
      'ea_pk': _hex32,
      'signatures': [
        {'key_id': 'demo', 'alg': 'ed25519', 'sig': _hex32},
      ],
    },
  },
};

Map<String, dynamic> _roundStatusJson() => {
  'vote_round_id': _roundId,
  'round_id': _roundId,
  'title': 'Poll',
  'status': 'active',
  'snapshot_height': 123,
  'ea_pk': _hex32,
  'nc_root': _hex32,
  'nullifier_imt_root': _hex32,
  'proposals': [
    {
      'proposal_id': 1,
      'title': 'First proposal',
      'options': ['Yes', 'No'],
    },
  ],
};

rust_voting.ApiRoundRecoveryState _recoveryState({
  List<rust_voting.ApiDelegationTxRecovery> delegationTxHashes = const [],
  List<rust_voting.ApiVoteTxRecovery> voteTxHashes = const [],
}) {
  return rust_voting.ApiRoundRecoveryState(
    roundId: _roundId,
    bundleCount: 1,
    delegationWorkflows: const [],
    delegationTxHashes: delegationTxHashes,
    votes: const [],
    voteWorkflows: const [],
    voteTxHashes: voteTxHashes,
    commitmentBundles: const [],
    shareWorkflows: const [],
    shareDelegations: const [],
    unconfirmedShareDelegations: const [],
  );
}

class _NoMnemonicAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _bootstrap.initialAccountState;

  @override
  Future<String?> getActiveMnemonic() async => null;

  @override
  Future<String?> getMnemonicForAccount(String uuid) async => null;
}

class _MnemonicAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _bootstrap.initialAccountState;

  @override
  Future<String?> getActiveMnemonic() async => 'abandon abandon abandon';

  @override
  Future<String?> getMnemonicForAccount(String uuid) async {
    return uuid == 'account-1' ? 'abandon abandon abandon' : null;
  }
}

class _HardwareAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'hardware-1',
        name: 'Keystone',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'hardware-1',
    activeAddress: 'u1hardwarevotingaddress',
  );
}

class _FakeVotingRecoveryApi implements VotingRecoveryApi {
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
    return _recoveryState();
  }
}

class _MutableVotingRecoveryApi extends _FakeVotingRecoveryApi {
  rust_voting.ApiRoundRecoveryState state = _recoveryState();

  @override
  Future<rust_voting.ApiRoundRecoveryState> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    return state;
  }
}

class _NoopVotingRustApi implements VotingRustApi {
  @override
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String walletId,
    String? roundId,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async {
    return SyncState();
  }
}

class _MatchedPirSnapshotResolver implements PirSnapshotResolver {
  const _MatchedPirSnapshotResolver();

  @override
  Future<PirSnapshotResolution> resolve({
    required List<Uri> endpoints,
    required int expectedSnapshotHeight,
  }) async {
    return PirSnapshotResolution(
      endpoint: Uri.parse('https://pir.example'),
      diagnostics: [
        PirSnapshotEndpointDiagnostic(
          endpoint: Uri.parse('https://pir.example'),
          status: PirSnapshotEndpointStatus.matched,
          reportedHeight: expectedSnapshotHeight,
        ),
      ],
    );
  }
}

class _FakeVotingHotkeyStore implements VotingHotkeyStore {
  const _FakeVotingHotkeyStore(this.hotkey);

  final List<int> hotkey;

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

class _VotingStatusRustApi extends _NoopVotingRustApi {
  _VotingStatusRustApi(this.recoveryApi);

  final _MutableVotingRecoveryApi recoveryApi;
  final storedKeystoneSignatures =
      <int, rust_voting.ApiKeystoneSignatureRecord>{};

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
  Future<List<int>> generateVotingHotkey() async {
    return [42, 43, 44];
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
  }) async {
    return rust_voting.ApiKeystoneDelegationRequest(
      pcztBytes: Uint8List.fromList(const [1]),
      redactedPcztBytes: Uint8List.fromList(const [2]),
      pcztSighash: Uint8List.fromList(const [3]),
      rk: Uint8List.fromList(const [4]),
      actionIndex: 0,
      eligibleWeightZatoshi: BigInt.from(100),
      delegatedWeightZatoshi: BigInt.from(100),
      bundleCount: 1,
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
    return [5, actionIndex];
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
  }) async* {
    final signature = storedKeystoneSignatures[bundleIndex];
    yield rust_voting.ApiDelegationProofEvent(
      phase: 'result',
      proofProgress: null,
      signedDelegationPayload: rust_voting.ApiSignedDelegationPayload(
        pcztBytes: Uint8List.fromList(const []),
        status: 'ready_for_submission',
        message: null,
        proof: Uint8List.fromList(const [1]),
        rk: Uint8List.fromList(signature?.rk ?? const [4]),
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
        bundleCount: 1,
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
  Future<void> markDelegationSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  }) async {}

  @override
  Future<void> markDelegationConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
    required int vanLeafPosition,
  }) async {
    recoveryApi.state = _recoveryState(
      delegationTxHashes: [
        rust_voting.ApiDelegationTxRecovery(
          bundleIndex: bundleIndex,
          txHash: txHash,
        ),
      ],
    );
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String walletId,
    required String roundId,
    required String nodeUrl,
  }) async {
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
    for (final draft in draftVotes) {
      yield rust_voting.ApiVoteCommitEvent(
        phase: 'result',
        proposalId: draft.proposalId,
        bundleIndex: bundleIndex,
        proofProgress: null,
        commitments: _commitments(
          roundId: roundId,
          bundleIndex: bundleIndex,
          proposalId: draft.proposalId,
          choice: draft.choice,
        ),
      );
    }
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
    return jsonEncode({
      'shares_hash': base64Encode(payload.sharesHash),
      'proposal_id': payload.proposalId,
      'vote_decision': payload.voteDecision,
      'enc_share': _wireShare(payload.encryptedShare),
      'share_index': payload.encryptedShare.shareIndex,
      'tree_position': (vcTreePosition ?? payload.treePosition).toInt(),
      'all_enc_shares': payload.allEncryptedShares.map(_wireShare).toList(),
      'share_comms': payload.shareComms.map(base64Encode).toList(),
      'primary_blind': base64Encode(payload.primaryBlind),
      'submit_at': submitAt.toInt(),
    });
  }

  @override
  Future<String> recoveredVoteShareWireJson({
    required String commitmentBundleJson,
    required int proposalId,
    required int shareIndex,
    required BigInt vcTreePosition,
    required BigInt submitAt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> markVoteSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) async {}

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
    recoveryApi.state = _recoveryState(
      delegationTxHashes: [
        rust_voting.ApiDelegationTxRecovery(
          bundleIndex: bundleIndex,
          txHash: 'delegation-tx',
        ),
      ],
      voteTxHashes: [
        rust_voting.ApiVoteTxRecovery(
          bundleIndex: bundleIndex,
          proposalId: proposalId,
          txHash: txHash,
        ),
      ],
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
}

Map<String, dynamic> _wireShare(rust_voting.ApiWireEncryptedShare share) {
  return {
    'c1': base64Encode(share.ciphertext1),
    'c2': base64Encode(share.ciphertext2),
    'share_index': share.shareIndex,
  };
}

List<int> _bytesFromHex(String hex) {
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

rust_voting.ApiSignedVoteCommitments _commitments({
  required String roundId,
  required int bundleIndex,
  required int proposalId,
  required int choice,
}) {
  final wireShare = rust_voting.ApiWireEncryptedShare(
    ciphertext1: Uint8List.fromList(const [8]),
    ciphertext2: Uint8List.fromList(const [9]),
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
        proof: Uint8List.fromList(const [4]),
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

class _RustApiFake implements RustLibApi {
  static bool failPcztEncoding = false;

  @override
  Future<Uint8List> crateApiWalletDeriveSeed({required String mnemonic}) async {
    return Uint8List.fromList(List.filled(64, 1));
  }

  @override
  Future<List<String>> crateApiKeystoneEncodePcztUrParts({
    required List<int> pcztBytes,
    required BigInt maxFragmentLen,
  }) async {
    if (failPcztEncoding) {
      throw StateError('forced PCZT encoding failure');
    }
    return const ['ur:zcash-pczt/test'];
  }

  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  void crateApiSyncCancelFullSync() {}

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  void crateApiSyncStopMempoolObserver() {}

  @override
  Stream<rust_sync.ApiMempoolTxEvent> crateApiSyncStartMempoolObserver({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
  }) {
    return const Stream.empty();
  }

  @override
  Stream<rust_sync.ApiSyncProgressEvent> crateApiSyncStartFullSync({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required int mode,
  }) {
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
