import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../models/migration_demo_state.dart';
import '../models/migration_schedule.dart';
import '../services/migration_demo_store.dart';

final migrationDemoProvider =
    AsyncNotifierProvider<MigrationDemoNotifier, MigrationDemoState?>(
      MigrationDemoNotifier.new,
    );

class MigrationDemoNotifier extends AsyncNotifier<MigrationDemoState?> {
  final MigrationDemoStore _store = MigrationDemoStore();

  @override
  Future<MigrationDemoState?> build() async {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return null;
    return _store.read(accountUuid);
  }

  /// Records that a migration just started (all txs already broadcast).
  Future<void> startDemo({
    required BigInt displayAmountZatoshi,
    required List<String> txids,
  }) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    await startDemoForAccount(
      accountUuid: accountUuid,
      displayAmountZatoshi: displayAmountZatoshi,
      txids: txids,
    );
  }

  /// Records that a migration started for a specific account.
  Future<void> startDemoForAccount({
    required String accountUuid,
    required BigInt displayAmountZatoshi,
    required List<String> txids,
  }) async {
    final demo = buildMigrationDemoState(
      accountUuid: accountUuid,
      displayAmountZatoshi: displayAmountZatoshi,
      txids: txids,
      now: DateTime.now(),
      random: Random(),
    );
    await _store.write(demo);
    state = AsyncData(demo);
  }

  /// Clears the demo so the tab returns to its idle/landing state.
  Future<void> reset() async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid != null) {
      await _store.clear(accountUuid);
    }
    state = const AsyncData(null);
  }
}
