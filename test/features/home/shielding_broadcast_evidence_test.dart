import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/pending_activity_evidence_provider.dart';

void main() {
  Future<WidgetRef> mount(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) {
            widgetRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await container.read(accountProvider.future);
    return widgetRef;
  }

  for (final status in [
    'broadcasted',
    'pending_broadcast',
    'partial_broadcast',
    'broadcast_unknown',
    'broadcasted_storage_failed',
  ]) {
    testWidgets('shielding ETA evidence for $status', (tester) async {
      final container = ProviderContainer(
        overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
      );
      addTearDown(container.dispose);
      final ref = await mount(tester, container);
      observeShieldingBroadcast(
        ref: ref,
        accountUuid: 'account-1',
        status: status,
        txids: [' txid-1 ', 'txid-2', ''],
      );
      final observed = container
          .read(pendingActivityEvidenceProvider)
          .observedAt;
      expect(
        observed.keys,
        status == 'broadcasted'
            ? unorderedEquals([
                ('account-1', 'txid-1'),
                ('account-1', 'txid-2'),
              ])
            : isEmpty,
      );
      container.read(pendingActivityEvidenceProvider.notifier).clear();
    });
  }

  testWidgets(
    'a successful broadcast still needs fresh network evidence for ETA',
    (tester) async {
      var now = DateTime.utc(2026, 10, 15);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          activityEtaClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final ref = await mount(tester, container);
      void observe() => observeShieldingBroadcast(
        ref: ref,
        accountUuid: 'account-1',
        status: 'broadcasted',
        txids: ['txid-1'],
      );
      String? label() => container
          .read(pendingActivityEvidenceProvider)
          .labelFor('account-1', 'txid-1', 100);
      final evidence = container.read(pendingActivityEvidenceProvider.notifier);
      observe();
      expect(label(), isNull);
      evidence.networkChecked(100);
      expect(label(), 'Est. 1–3 min');
      now = now.add(const Duration(minutes: 5));
      observe();
      evidence.networkChecked(100);
      expect(
        label(),
        'Taking longer',
        reason: 'retries retain the first observation',
      );
      evidence.invalidateNetwork(connectionFailed: true);
      expect(label(), isNull);
      evidence.clear();
    },
  );

  for (final account in <String?>[null, 'deleted-account']) {
    testWidgets('does not record an absent account: $account', (tester) async {
      final container = ProviderContainer(
        overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
      );
      addTearDown(container.dispose);
      final ref = await mount(tester, container);
      observeShieldingBroadcast(
        ref: ref,
        accountUuid: account,
        status: 'broadcasted',
        txids: ['txid-1'],
      );
      expect(
        container.read(pendingActivityEvidenceProvider).observedAt,
        isEmpty,
      );
    });
  }

  testWidgets('records the original account after switching accounts', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(activeAccount: 'account-2'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final ref = await mount(tester, container);
    observeShieldingBroadcast(
      ref: ref,
      accountUuid: 'account-1',
      status: 'broadcasted',
      txids: ['txid-1'],
    );
    expect(container.read(pendingActivityEvidenceProvider).observedAt.keys, [
      ('account-1', 'txid-1'),
    ]);
    container.read(pendingActivityEvidenceProvider.notifier).clear();
  });

  testWidgets('does not restore evidence while locked or after disposal', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(unlocked: false)),
      ],
    );
    addTearDown(container.dispose);
    final ref = await mount(tester, container);
    void observe() => observeShieldingBroadcast(
      ref: ref,
      accountUuid: 'account-1',
      status: 'broadcasted',
      txids: ['txid-1'],
    );
    observe();
    expect(container.read(pendingActivityEvidenceProvider).observedAt, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    observe();
    expect(container.read(pendingActivityEvidenceProvider).observedAt, isEmpty);
  });
}

AppBootstrapState _bootstrap({
  bool unlocked = true,
  String activeAccount = 'account-1',
}) => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: AccountState(
    accounts: const [
      AccountInfo(uuid: 'account-1', name: 'First', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Second', order: 1),
    ],
    activeAccountUuid: activeAccount,
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: unlocked,
  passwordRotationRecoveryFailed: false,
);
