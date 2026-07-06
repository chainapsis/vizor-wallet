import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/multisig/screens/multisig_signing_home_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_signing_request_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('keeps selected signer requests visible while waiting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness([
        _record(
          signingRequestId: 'request-waiting',
          requesterParticipantId: 'participant-a',
          localParticipantId: 'participant-b',
          selectedParticipantIds: const ['participant-a', 'participant-b'],
          round1ParticipantIds: const ['participant-b'],
          localStateJson: '{"round1_sent":true}',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Waiting for signatures'), findsOneWidget);
    expect(find.text('uregtest1recipient'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('No active multisig sends'), findsNothing);
  });

  testWidgets(
    'shows completed shares as an action without local Round 2 state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _harness([
          _record(
            signingRequestId: 'request-ready',
            requesterParticipantId: 'participant-a',
            localParticipantId: 'participant-b',
            selectedParticipantIds: const ['participant-a', 'participant-b'],
            round1ParticipantIds: const ['participant-a', 'participant-b'],
            round2ParticipantIds: const ['participant-a', 'participant-b'],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Action needed'), findsOneWidget);
      expect(find.text('Ready to send'), findsOneWidget);
      expect(find.text('Signed 2/2'), findsOneWidget);
      expect(find.text('No active multisig sends'), findsNothing);
    },
  );

  testWidgets('hides already sent requests from the active work list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness([
        _record(
          signingRequestId: 'request-broadcasted',
          requesterParticipantId: 'participant-a',
          localParticipantId: 'participant-b',
          selectedParticipantIds: const ['participant-a', 'participant-b'],
          round1ParticipantIds: const ['participant-a', 'participant-b'],
          round2ParticipantIds: const ['participant-a', 'participant-b'],
          broadcastTxid: 'txid-1',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No active multisig sends'), findsOneWidget);
    expect(find.text('uregtest1recipient'), findsNothing);
    expect(find.text('Ready to send'), findsNothing);
  });
}

Widget _harness(List<MultisigSigningRequestRecord> records) {
  final router = GoRouter(
    initialLocation: '/multisig',
    routes: [
      GoRoute(
        path: '/multisig',
        builder: (_, _) => const MultisigSigningHomeScreen(),
      ),
      GoRoute(
        path: '/multisig/connect',
        builder: (_, _) => const Text('setup'),
      ),
      GoRoute(
        path: '/multisig/sign/:signingRequestId',
        builder: (_, _) => const Text('detail'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      multisigAccountMaterialStoreProvider.overrideWithValue(
        _FakeAccountMaterialStore(),
      ),
      multisigSigningRequestsProvider.overrideWith(
        () => _FakeSigningRequestsNotifier(records),
      ),
      syncProvider.overrideWith(() => _FakeSyncNotifier()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/multisig',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Multisig',
        order: 0,
        kind: AccountKind.multisig,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'uregtest1multisig',
  ),
  initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('account-1'),
  network: 'test',
  rpcEndpointConfig: defaultRpcEndpointConfig('test'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSigningRequestsNotifier extends MultisigSigningRequestsNotifier {
  _FakeSigningRequestsNotifier(this.records);

  final List<MultisigSigningRequestRecord> records;

  @override
  Future<List<MultisigSigningRequestRecord>> build() async => records;

  @override
  Future<void> refreshForAccount(String accountUuid) async {}
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(accountUuid: 'account-1');
}

class _FakeAccountMaterialStore implements MultisigAccountMaterialStore {
  @override
  Future<MultisigAccountMaterial?> read(
    String accountUuid, {
    bool requireUnlockedSession = true,
  }) async => null;

  @override
  Future<List<MultisigAccountMaterial>> readAll({
    bool requireUnlockedSession = true,
  }) async => const [];

  @override
  Future<void> write(MultisigAccountMaterial material) async {}

  @override
  Future<void> delete(String accountUuid) async {}
}

MultisigSigningRequestRecord _record({
  required String signingRequestId,
  required String requesterParticipantId,
  required String localParticipantId,
  required List<String> selectedParticipantIds,
  List<String> round1ParticipantIds = const <String>[],
  List<String> round2ParticipantIds = const <String>[],
  String? localStateJson,
  String? broadcastTxid,
  bool broadcastResultSent = false,
}) {
  return MultisigSigningRequestRecord(
    signingRequestId: signingRequestId,
    accountUuid: 'account-1',
    sessionId: 'session-1',
    localParticipantId: localParticipantId,
    requesterParticipantId: requesterParticipantId,
    selectedParticipantIds: selectedParticipantIds,
    pcztB64: 'AQID',
    pcztHash: 'pczt-hash',
    needsSaplingParams: false,
    amountZatoshi: '100000000',
    feeZatoshi: '1000',
    recipientAddress: 'uregtest1recipient',
    addressType: 'unified',
    state: 'open',
    createdAt: 1,
    updatedAt: 1,
    round1ParticipantIds: round1ParticipantIds,
    round2ParticipantIds: round2ParticipantIds,
    localStateJson: localStateJson,
    broadcastTxid: broadcastTxid,
    broadcastResultSent: broadcastResultSent,
  );
}
