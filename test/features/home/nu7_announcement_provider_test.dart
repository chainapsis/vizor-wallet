import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';
import 'package:zcash_wallet/src/features/home/providers/nu7_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/block_spacing_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _activation = 3_543_405;

void main() {
  test('stays hidden until the tip reaches activation', () async {
    final container = _container(tip: _activation - 1);
    addTearDown(container.dispose);

    final state = await _read(container);

    expect(state.visible, isFalse);
  });

  test('shows once the tip reaches activation', () async {
    final container = _container(tip: _activation);
    addTearDown(container.dispose);

    final state = await _read(container);

    expect(state.visible, isTrue);
    expect(state.network, 'main');
  });

  test('stays hidden on a network where it was seen', () async {
    final store = _MemoryNu7AnnouncementStore()..seen.add('main');
    final container = _container(tip: _activation, store: store);
    addTearDown(container.dispose);

    final state = await _read(container);

    expect(state.visible, isFalse);
  });

  test('skips a wallet whose accounts all began after activation', () async {
    final container = _container(
      tip: _activation + 100,
      birthdays: [_activation, _activation + 50],
    );
    addTearDown(container.dispose);

    final state = await _read(container);

    expect(state.visible, isFalse);
  });

  test('shows when any account predates activation', () async {
    final container = _container(
      tip: _activation + 100,
      birthdays: [_activation + 50, _activation - 10_000],
    );
    addTearDown(container.dispose);

    final state = await _read(container);

    expect(state.visible, isTrue);
  });

  test('stays hidden while NU7 is unscheduled', () async {
    final container = _container(tip: _activation, activation: null);
    addTearDown(container.dispose);

    final state = await _read(container);

    expect(state.visible, isFalse);
  });
}

Future<Nu7AnnouncementState> _read(ProviderContainer container) async {
  await container.read(accountProvider.future);
  await container.read(syncProvider.future);
  return container.read(nu7AnnouncementProvider.future);
}

ProviderContainer _container({
  required int tip,
  int? activation = _activation,
  List<int?> birthdays = const [3_000_000],
  Nu7AnnouncementStore? store,
}) {
  const endpoint = RpcEndpointConfig(
    networkName: 'main',
    lightwalletdUrl: 'https://zec.example:443',
    presetId: kCustomRpcEndpointPresetId,
  );
  final accounts = [
    for (final (index, birthday) in birthdays.indexed)
      AccountInfo(
        uuid: 'account-$index',
        name: 'Account $index',
        order: index,
        birthdayHeight: birthday,
      ),
  ];
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/home',
          initialAccountState: const AccountState(),
          initialSyncSnapshot: AppSyncSnapshot.empty,
          network: endpoint.networkName,
          rpcEndpointConfig: endpoint,
          themeMode: ThemeMode.system,
          privacyModeEnabled: false,
          isPasswordConfigured: true,
          isUnlocked: true,
          passwordRotationRecoveryFailed: false,
        ),
      ),
      blockSpacingProvider.overrideWithValue(
        BlockSpacing(
          preNu7BlockSeconds: 75,
          nu7BlockSeconds: 25,
          nu7ActivationHeight: activation,
        ),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(scannedHeight: tip, chainTipHeight: tip),
        ),
      ),
      accountProvider.overrideWith(() => _FakeAccountNotifier(accounts)),
      nu7AnnouncementStoreProvider.overrideWithValue(
        store ?? _MemoryNu7AnnouncementStore(),
      ),
    ],
  );
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.accounts);

  final List<AccountInfo> accounts;

  @override
  FutureOr<AccountState> build() =>
      AccountState(accounts: accounts, activeAccountUuid: accounts.first.uuid);
}

class _MemoryNu7AnnouncementStore implements Nu7AnnouncementStore {
  final seen = <String>{};

  @override
  Future<bool> isSeen(String network) async => seen.contains(network);

  @override
  Future<void> markSeen(String network) async => seen.add(network);
}
