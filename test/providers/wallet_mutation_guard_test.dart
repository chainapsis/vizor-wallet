import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_mutation_guard.dart';

void main() {
  testWidgets('pauses stale sync work even when there are no accounts', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await runWithSyncPausedForAccountMutation(capturedRef, () async {
      events.add('action');
    });

    expect(events, ['pause', 'action', 'resume']);
  });

  testWidgets('can skip resuming after destructive wallet mutation', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await runWithSyncPausedForAccountMutation(capturedRef, () async {
      events.add('action');
    }, resumeAfterMutation: false);

    expect(events, ['pause', 'action']);
  });

  testWidgets('resumes after failed non-destructive mutation by default', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      runWithSyncPausedForAccountMutation(capturedRef, () async {
        events.add('action');
        throw StateError('mutation failed');
      }),
      throwsA(isA<StateError>()),
    );

    expect(events, ['pause', 'action', 'resume']);
  });

  testWidgets(
    'quiesces migration work before sync and resumes it after account addition',
    (tester) async {
      final events = <String>[];
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(_ExistingAccountNotifier.new),
            syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      await runWithSyncPausedForAccountMutation(
        capturedRef,
        () async => events.add('action'),
        quiesceMigrationWork: true,
        migrationLifecycle: _RecordingMigrationLifecycle(events),
      );

      expect(events, [
        'migration-quiesce',
        'pause',
        'action',
        'resume',
        'migration-resume',
      ]);
    },
  );

  testWidgets(
    'resumes quiesced migration work after non-destructive account failure',
    (tester) async {
      final events = <String>[];
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(_ExistingAccountNotifier.new),
            syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        runWithSyncPausedForAccountMutation(
          capturedRef,
          () async {
            events.add('action');
            throw StateError('import failed');
          },
          quiesceMigrationWork: true,
          migrationLifecycle: _RecordingMigrationLifecycle(events),
        ),
        throwsA(isA<StateError>()),
      );

      expect(events, [
        'migration-quiesce',
        'pause',
        'action',
        'resume',
        'migration-resume',
      ]);
    },
  );

  testWidgets(
    'rolls back an ambiguous migration quiesce before skipping the mutation',
    (tester) async {
      final events = <String>[];
      late WidgetRef capturedRef;
      final quiesceError = StateError('quiesce response lost');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(_ExistingAccountNotifier.new),
            syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        runWithSyncPausedForAccountMutation(
          capturedRef,
          () async => events.add('action'),
          migrationLifecycle: _RecordingMigrationLifecycle(
            events,
            quiesceError: quiesceError,
          ),
        ),
        throwsA(same(quiesceError)),
      );

      expect(events, ['migration-quiesce', 'migration-resume']);
    },
  );

  testWidgets(
    'does not mask a committed mutation when migration resume fails',
    (tester) async {
      final events = <String>[];
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(_ExistingAccountNotifier.new),
            syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      final result = await runWithSyncPausedForAccountMutation(
        capturedRef,
        () async {
          events.add('action');
          return 7;
        },
        quiesceMigrationWork: true,
        migrationLifecycle: _RecordingMigrationLifecycle(
          events,
          resumeError: StateError('resume failed'),
        ),
      );

      expect(result, 7);
      expect(events, [
        'migration-quiesce',
        'pause',
        'action',
        'resume',
        'migration-resume',
      ]);
    },
  );

  testWidgets('preserves the mutation error when migration resume also fails', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;
    final mutationError = StateError('import failed');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      runWithSyncPausedForAccountMutation(
        capturedRef,
        () async {
          events.add('action');
          throw mutationError;
        },
        quiesceMigrationWork: true,
        migrationLifecycle: _RecordingMigrationLifecycle(
          events,
          resumeError: StateError('resume failed'),
        ),
      ),
      throwsA(same(mutationError)),
    );

    expect(events, [
      'migration-quiesce',
      'pause',
      'action',
      'resume',
      'migration-resume',
    ]);
  });

  testWidgets('quiesces migration before sync for destructive wrappers', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await runWithSyncPausedForAccountMutation(
      capturedRef,
      () async => events.add('action'),
      migrationLifecycle: _RecordingMigrationLifecycle(events),
    );

    expect(events, [
      'migration-quiesce',
      'pause',
      'action',
      'resume',
      'migration-resume',
    ]);
  });

  testWidgets('wallet reset quiesces migration before foreground sync', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await runWithSyncPausedForWalletReset(capturedRef, () async {
      events.add('clearSensitiveState');
      events.add('resetWallet');
    }, migrationLifecycle: _RecordingMigrationLifecycle(events));

    expect(events, [
      'migration-quiesce',
      'pause',
      'clearSensitiveState',
      'resetWallet',
      'clearCachedWalletDbPath',
      'migration-resume',
    ]);
  });

  testWidgets('wallet reset resumes after pre-delete failure', (tester) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      runWithSyncPausedForWalletReset(capturedRef, () async {
        events.add('resetWallet');
        throw StateError('reset failed');
      }),
      throwsA(isA<StateError>()),
    );

    expect(events, [
      'pause',
      'resetWallet',
      'clearCachedWalletDbPath',
      'resume',
    ]);
  });

  testWidgets('wallet reset stays paused after post-delete failure', (
    tester,
  ) async {
    final events = <String>[];
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          syncProvider.overrideWith(() => _StaleSyncNotifier(events)),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      runWithSyncPausedForWalletReset(capturedRef, () async {
        events.add('resetWallet');
        throw const WalletResetException(
          cause: 'secure storage wipe failed',
          dbDeleted: true,
        );
      }),
      throwsA(isA<WalletResetException>()),
    );

    expect(events, ['pause', 'resetWallet', 'clearCachedWalletDbPath']);
  });
}

class _EmptyAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async => const AccountState();
}

class _ExistingAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: 'account-1',
  );
}

class _RecordingMigrationLifecycle
    extends IronwoodMigrationBackgroundLifecycle {
  _RecordingMigrationLifecycle(
    this.events, {
    this.quiesceError,
    this.resumeError,
  }) : super(isIOS: false, isAndroid: false);

  final List<String> events;
  final Object? quiesceError;
  final Object? resumeError;

  @override
  Future<void> quiesce() async {
    events.add('migration-quiesce');
    final error = quiesceError;
    if (error != null) throw error;
  }

  @override
  Future<void> resumeAfterMutation() async {
    events.add('migration-resume');
    final error = resumeError;
    if (error != null) throw error;
  }
}

class _StaleSyncNotifier extends SyncNotifier {
  _StaleSyncNotifier(this.events);

  final List<String> events;

  @override
  Future<SyncState> build() async => SyncState();

  @override
  bool needsPauseForWalletMutation() => true;

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    events.add('pause');
    return const WalletMutationSyncPause(
      hadActiveSync: true,
      hadPolling: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {
    events.add('resume');
  }

  @override
  void clearCachedWalletDbPath() {
    events.add('clearCachedWalletDbPath');
  }
}
