@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/multisig/screens/mobile/mobile_multisig_inbox_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_signing_request_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('groups active multisig sends and opens the detail route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _harness([
        _record(signingRequestId: 'needs-action'),
        _record(
          signingRequestId: 'ready-to-send',
          amountZatoshi: '200000',
          round1ParticipantIds: const ['participant-a', 'participant-b'],
          round2ParticipantIds: const ['participant-a', 'participant-b'],
          localStateJson: '{"round1_sent":true,"round2_sent":true}',
        ),
        _record(
          signingRequestId: 'waiting',
          amountZatoshi: '300000',
          round1ParticipantIds: const ['participant-a'],
          localStateJson: '{"round1_sent":true}',
        ),
        _record(
          signingRequestId: 'review-only',
          amountZatoshi: '400000',
          selectedParticipantIds: const ['participant-b', 'participant-c'],
        ),
        _record(
          signingRequestId: 'share-result',
          amountZatoshi: '500000',
          broadcastTxid: 'txid',
        ),
        _record(
          signingRequestId: 'broadcasted',
          amountZatoshi: '600000',
          broadcastTxid: 'txid-complete',
          broadcastResultSent: true,
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('3 sends need your action'), findsOneWidget);
    expect(find.text('Needs your action'), findsOneWidget);
    expect(find.text('Share result'), findsOneWidget);
    expect(find.text('Ready to send'), findsWidgets);
    expect(find.text('Waiting for others'), findsOneWidget);
    expect(find.text('Review only'), findsWidgets);
    expect(find.textContaining('broadcasted'), findsNothing);

    await tester.tap(find.text('Needs approval'));
    await tester.pumpAndSettle();

    expect(find.text('detail needs-action'), findsOneWidget);
  });

  testWidgets(
    'shows an empty state for multisig accounts without active sends',
    (tester) async {
      await tester.pumpWidget(_harness(const []));
      await tester.pump();
      await tester.pump();

      expect(find.text('No active multisig sends'), findsOneWidget);
      expect(
        find.text(
          'New requests will appear here when they need your attention.',
        ),
        findsOneWidget,
      );
    },
  );
}

Widget _harness(List<MultisigSigningRequestRecord> records) {
  final router = GoRouter(
    initialLocation: '/multisig',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(
        path: '/multisig',
        builder: (_, _) => const MobileMultisigInboxScreen(),
      ),
      GoRoute(
        path: '/multisig/sign/:signingRequestId',
        builder: (_, state) =>
            Text('detail ${state.pathParameters['signingRequestId']}'),
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
  String amountZatoshi = '100000',
  List<String> selectedParticipantIds = const [
    'participant-a',
    'participant-b',
  ],
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
    localParticipantId: 'participant-a',
    requesterParticipantId: 'participant-b',
    selectedParticipantIds: selectedParticipantIds,
    pcztB64: 'AQID',
    pcztHash: 'pczt-hash',
    needsSaplingParams: false,
    amountZatoshi: amountZatoshi,
    feeZatoshi: '1000',
    recipientAddress: 'uregtest1recipientaddress',
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
