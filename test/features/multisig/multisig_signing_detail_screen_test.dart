import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/multisig/screens/multisig_signing_detail_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_signing_request_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('shows send action once all approvals are ready', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(
        _record(
          round1ParticipantIds: const ['participant-a', 'participant-b'],
          round2ParticipantIds: const ['participant-a', 'participant-b'],
          localStateJson: '{"round1_sent":true}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Finish approval'), findsNothing);
    final sendButton = tester.widget<AppButton>(
      find.ancestor(
        of: find.text('Send now'),
        matching: find.byType(AppButton),
      ),
    );

    expect(sendButton.onPressed, isNotNull);
    expect(find.text('Ready to send'), findsWidgets);
    expect(
      find.text(
        'All required approvals are collected. Send this transaction to the network.',
      ),
      findsOneWidget,
    );
  });
}

Widget _harness(MultisigSigningRequestRecord record) {
  final router = GoRouter(
    initialLocation: '/multisig/sign/${record.signingRequestId}',
    routes: [
      GoRoute(path: '/multisig', builder: (_, _) => const Text('home')),
      GoRoute(
        path: '/multisig/sign/:signingRequestId',
        builder: (_, state) => MultisigSigningDetailScreen(
          signingRequestId: state.pathParameters['signingRequestId']!,
        ),
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
        () => _FakeSigningRequestsNotifier([record]),
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

  @override
  Future<MultisigSigningRequestRecord?> refreshRequestProgress({
    required String accountUuid,
    required String signingRequestId,
  }) async => records.firstWhere(
    (record) => record.signingRequestId == signingRequestId,
  );
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
  List<String> round1ParticipantIds = const <String>[],
  List<String> round2ParticipantIds = const <String>[],
  String? localStateJson,
}) {
  return MultisigSigningRequestRecord(
    signingRequestId: 'request-ready',
    accountUuid: 'account-1',
    sessionId: 'session-1',
    localParticipantId: 'participant-b',
    requesterParticipantId: 'participant-a',
    selectedParticipantIds: const ['participant-a', 'participant-b'],
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
  );
}
