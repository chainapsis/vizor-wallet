import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/providers/orchard_migration_status_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this._initial);

  final SyncState _initial;

  @override
  Future<SyncState> build() async => _initial;

  void emit(SyncState value) => state = AsyncData(value);
}

SyncState _syncState({
  required bool isSyncing,
  int scannedHeight = 100,
  BigInt? orchard,
  BigInt? orchardPending,
}) {
  return SyncState(
    accountUuid: 'acct-1',
    isSyncing: isSyncing,
    scannedHeight: scannedHeight,
    orchardBalance: orchard ?? BigInt.from(4),
    orchardPendingBalance: orchardPending ?? BigInt.zero,
    ironwoodBalance: BigInt.zero,
    ironwoodPendingBalance: BigInt.zero,
  );
}

rust_sync.MigrationStatus _status(String phase) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 3,
    pendingTxCount: 0,
    signedChildPcztCount: 0,
    pendingPrepTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(60),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [],
  );
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('settledSyncFingerprint', () {
    test('is null while syncing and for missing state', () {
      expect(settledSyncFingerprint(null), isNull);
      expect(settledSyncFingerprint(_syncState(isSyncing: true)), isNull);
    });

    test('is stable for identical settled inputs', () {
      expect(
        settledSyncFingerprint(_syncState(isSyncing: false)),
        settledSyncFingerprint(_syncState(isSyncing: false)),
      );
    });

    test('changes when scanned height or balances change', () {
      final base = settledSyncFingerprint(_syncState(isSyncing: false));
      expect(
        settledSyncFingerprint(
          _syncState(isSyncing: false, scannedHeight: 101),
        ),
        isNot(base),
      );
      expect(
        settledSyncFingerprint(
          _syncState(isSyncing: false, orchard: BigInt.from(9)),
        ),
        isNot(base),
      );
    });
  });

  group('migrationStatusSyncGateProvider', () {
    test('holds while scanning, updates once on settle', () async {
      final fake = _FakeSyncNotifier(_syncState(isSyncing: false));
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => fake)],
      );
      addTearDown(container.dispose);
      final gate = container.listen(migrationStatusSyncGateProvider, (_, _) {});
      await container.read(syncProvider.future);
      await _tick();
      final settled = gate.read();
      expect(settled, isNot(0));

      // Scan starts and balances flap: the gate must not move.
      fake.emit(_syncState(isSyncing: true, orchard: BigInt.zero));
      await _tick();
      expect(gate.read(), settled);
      fake.emit(
        _syncState(isSyncing: true, scannedHeight: 150, orchard: BigInt.two),
      );
      await _tick();
      expect(gate.read(), settled);

      // Sync settles: exactly one new fingerprint.
      fake.emit(_syncState(isSyncing: false, scannedHeight: 150));
      await _tick();
      final after = gate.read();
      expect(after, isNot(settled));

      // Identical settled state again: no change.
      fake.emit(_syncState(isSyncing: false, scannedHeight: 150));
      await _tick();
      expect(gate.read(), after);
    });
  });

  group('migrationBlocksSend', () {
    test('blocks on first load and on error', () {
      expect(
        migrationBlocksSend(const AsyncLoading<rust_sync.MigrationStatus?>()),
        isTrue,
      );
      expect(
        migrationBlocksSend(
          AsyncError<rust_sync.MigrationStatus?>('boom', StackTrace.empty),
        ),
        isTrue,
      );
    });

    test('uses preserved value during reload instead of blocking', () {
      // copyWithPrevious is how Riverpod itself builds the reload state this
      // function must handle; there is no public constructor for it.
      final reloadingIdle = const AsyncLoading<rust_sync.MigrationStatus?>()
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(
            AsyncData<rust_sync.MigrationStatus?>(_status('ready_to_prepare')),
            isRefresh: false,
          );
      expect(migrationBlocksSend(reloadingIdle), isFalse);

      final reloadingActive = const AsyncLoading<rust_sync.MigrationStatus?>()
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(
            AsyncData<rust_sync.MigrationStatus?>(
              _status('waiting_denom_confirmations'),
            ),
            isRefresh: false,
          );
      expect(migrationBlocksSend(reloadingActive), isTrue);
    });

    test('null status (hardware account) does not block once loaded', () {
      expect(
        migrationBlocksSend(const AsyncData<rust_sync.MigrationStatus?>(null)),
        isFalse,
      );
    });

    test('loaded migration phases block sends only while active', () {
      expect(
        migrationBlocksSend(
          AsyncData<rust_sync.MigrationStatus?>(
            _status('waiting_denom_confirmations'),
          ),
        ),
        isTrue,
      );
      expect(
        migrationBlocksSend(
          AsyncData<rust_sync.MigrationStatus?>(_status('ready_to_migrate')),
        ),
        isTrue,
      );
      expect(
        migrationBlocksSend(
          AsyncData<rust_sync.MigrationStatus?>(_status('ready_to_prepare')),
        ),
        isFalse,
      );
    });
  });
}
