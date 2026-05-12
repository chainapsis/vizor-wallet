import 'dart:async';

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
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_voting;
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';

import '../../services/voting/fake_voting_http.dart';

void main() {
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
    container.read(votingDraftProvider(_roundId).notifier).setChoice(1, 0);

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
}

Widget _statusHarness() {
  final router = GoRouter(
    initialLocation: '/voting/poll/$_roundId/status',
    routes: [
      GoRoute(
        path: '/voting/poll/:roundId/status',
        builder: (_, state) =>
            VotingStatusScreen(roundId: state.pathParameters['roundId']!),
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

rust_voting.ApiRoundRecoveryState _recoveryState() {
  return rust_voting.ApiRoundRecoveryState(
    roundId: _roundId,
    bundleCount: 1,
    delegationWorkflows: const [],
    delegationTxHashes: const [],
    votes: const [],
    voteWorkflows: const [],
    voteTxHashes: const [],
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
