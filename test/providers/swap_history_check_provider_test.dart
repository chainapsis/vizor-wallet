import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/swap_history_check_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart';

/// Counts the syncs a check asks for; these tests have no wallet.
class _Sync extends SyncNotifier {
  int starts = 0;
  @override
  Future<SyncState> build() async => SyncState();
  @override
  void pollSwapRecovery() => starts++;
}

/// NEAR swap privacy, on.
class _Privacy extends NearSwapPrivacyNotifier {
  @override
  bool build() => true;
}

/// NEAR swap privacy, off. The check doesn't depend on it.
class _PrivacyOff extends _Privacy {
  @override
  bool build() => false;
}

/// The setting and a wallet with no saved recovery state, for every container.
List<Override> _wallet({
  Future<SwapRecoveryStatus?> Function()? saved,
  NearSwapPrivacyNotifier Function()? privacy,
}) => [
  nearSwapPrivacyProvider.overrideWith(privacy ?? _Privacy.new),
  swapRecoveryStatusReaderProvider.overrideWithValue(saved ?? () async => null),
];

/// The wallet's recovery state, as the status call reports it.
SwapRecoveryStatus _status({
  bool checking = false,
  bool manual = false,
  bool upgrade = false,
}) => SwapRecoveryStatus(
  roundDue: false,
  awaitingAdmission: false,
  checkingHistory: checking || manual,
  manualCheckActive: manual,
  upgradeRequired: upgrade,
);

/// A check that failed before it started its jobs, as an unreachable service
/// fails it.
const _beforeJobs = ReceiveError(
  message: 'transport: connection refused',
  kind: ReceiveErrorKind.other,
  historyStarted: false,
);

/// A check that failed after it started its jobs, which keep running.
const _afterJobs = ReceiveError(
  message: 'transport: connection refused',
  kind: ReceiveErrorKind.other,
  historyStarted: true,
);

void main() {
  /// A container whose wallet reports `checking` until it runs out, and whose
  /// check fails to start when `failBegin`.
  (ProviderContainer, _Sync, List<String>) setup({
    required List<bool> checking,
    bool failBegin = false,
    Duration maxWait = const Duration(minutes: 1),
  }) {
    final sync = _Sync();
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        ..._wallet(),
        syncProvider.overrideWith(() => sync),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            cancel: () async {},
            begin: () async {
              calls.add('begin');
              if (failBegin) throw StateError('wallet busy');
            },
            status: () async {
              calls.add('poll');
              return _status(
                checking: checking.isEmpty ? false : checking.removeAt(0),
              );
            },
            pollInterval: Duration.zero,
            maxWait: maxWait,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, sync, calls);
  }

  test(
    'starts once and continues recovery until the wallet finishes it',
    () async {
      final (container, sync, calls) = setup(checking: [true, true, false]);
      final notifier = container.read(swapHistoryCheckProvider.notifier);
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.idle);
      final running = notifier.check();
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.checking,
      );
      // A second tap while it runs does nothing.
      await notifier.check();
      await running;
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
      expect(calls, ['begin', 'poll', 'poll', 'poll']);
      expect(sync.starts, 3);
    },
  );

  test('leaves a long check to later recovery rounds', () async {
    final (container, _, _) = setup(
      checking: [true, true, true],
      maxWait: Duration.zero,
    );
    await container.read(swapHistoryCheckProvider.notifier).check();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.continuing,
    );
  });

  test('reports a check the wallet could not start', () async {
    final (container, sync, calls) = setup(checking: [], failBegin: true);
    await container.read(swapHistoryCheckProvider.notifier).check();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.notStarted,
    );
    expect(calls, ['begin']);
    expect(sync.starts, 0);
  });

  group('a round that fails', () {
    /// A container whose check round fails with `error`, by default as the
    /// receiver service does when it can't be reached, and whose saved-state
    /// reads answer with `saved`.
    ProviderContainer failing(
      Future<SwapRecoveryStatus?> Function() saved, {
      ReceiveError? error,
      Future<void> Function()? cancel,
    }) {
      final container = ProviderContainer(
        overrides: [
          ..._wallet(saved: saved),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async =>
                  throw error ??
                      const ReceiveError(
                        message: 'transport: connection refused',
                        kind: ReceiveErrorKind.other,
                      ),
              cancel: cancel ?? () async {},
              status: () async => _status(manual: true),
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('with no saved job reports the failed round', () async {
      final container = failing(() async => _status());
      await container.read(swapHistoryCheckProvider.notifier).check();
      await pumpEventQueue();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.failed);
      expect(container.read(swapHistoryJobSavedProvider), isFalse);
    });

    for (final (name, error, shown) in [
      ('before its jobs started', _beforeJobs, SwapHistoryCheck.failed),
      // Jobs start on every account or none, so one refusing fails the round
      // as a wallet behind the service does.
      (
        'because an account refused its job',
        const ReceiveError(
          message: 'Swap history check has not started.',
          kind: ReceiveErrorKind.waitingForSync,
          historyStarted: false,
        ),
        SwapHistoryCheck.waitingForSync,
      ),
    ]) {
      test('$name, with an earlier check\'s job running, stays as it '
          'is, with Pause, after that job finishes', () async {
        var running = true;
        Future<SwapRecoveryStatus> saved() async => _status(manual: running);
        final container = failing(saved, error: error);
        await container.read(swapHistoryCheckProvider.notifier).check();
        await pumpEventQueue();
        expect(container.read(swapHistoryCheckProvider), shown);
        expect(container.read(swapHistoryJobSavedProvider), isTrue);

        // A background round finishes the earlier job.
        running = false;
        container.read(swapRecoveryRoundsProvider.notifier).ended();
        await pumpEventQueue();
        expect(container.read(swapHistoryCheckProvider), shown);
        expect(container.read(swapHistoryJobSavedProvider), isFalse);
      });
    }

    for (final pauseFails in [false, true]) {
      test('before its jobs started stays failed when Pause on an earlier '
          'check\'s job ${pauseFails ? 'fails' : 'succeeds'}, and after that '
          'job ends', () async {
        var running = true;
        Future<SwapRecoveryStatus> saved() async => _status(manual: running);
        final container = failing(
          saved,
          error: _beforeJobs,
          cancel: () async {
            if (pauseFails) throw StateError('database is locked');
            running = false;
          },
        );
        final history = container.read(swapHistoryCheckProvider.notifier);
        await history.check();
        await pumpEventQueue();
        expect(container.read(swapHistoryJobSavedProvider), isTrue);
        await history.cancel();
        expect(
          container.read(swapHistoryCheckProvider),
          SwapHistoryCheck.failed,
        );
        expect(container.read(swapHistoryJobSavedProvider), pauseFails);

        running = false;
        container.read(swapRecoveryRoundsProvider.notifier).ended();
        await pumpEventQueue();
        expect(
          container.read(swapHistoryCheckProvider),
          SwapHistoryCheck.failed,
        );
      });
    }

    for (final pauseFails in [false, true]) {
      test(
        'after its jobs started shows them checking, with Pause, and a '
        'Pause that ${pauseFails ? 'fails shows done once they end' : 'succeeds shows paused'}',
        () async {
          var running = true;
          Future<SwapRecoveryStatus> saved() async => _status(manual: running);
          final container = failing(
            saved,
            error: _afterJobs,
            cancel: () async {
              if (pauseFails) throw StateError('database is locked');
              running = false;
            },
          );
          final history = container.read(swapHistoryCheckProvider.notifier);
          await history.check();
          await pumpEventQueue();
          expect(
            container.read(swapHistoryCheckProvider),
            isIn([SwapHistoryCheck.checking, SwapHistoryCheck.continuing]),
          );
          expect(container.read(swapHistoryJobSavedProvider), isTrue);
          await history.cancel();
          expect(
            container.read(swapHistoryCheckProvider),
            pauseFails ? SwapHistoryCheck.pauseFailed : SwapHistoryCheck.paused,
          );
          if (pauseFails) {
            running = false;
            container.read(swapRecoveryRoundsProvider.notifier).ended();
            await pumpEventQueue();
            expect(
              container.read(swapHistoryCheckProvider),
              SwapHistoryCheck.done,
            );
          }
        },
      );
    }

    test('while a wallet change refuses reads reports the change', () async {
      final container = failing(
        () async =>
            throw StateError('The wallet is changing. Try again in a moment.'),
      );
      await container.read(swapHistoryCheckProvider.notifier).check();
      await pumpEventQueue();
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.walletChanged,
      );
    });

    test("while Rust can't read the wallet still reports the failed "
        'round', () async {
      final container = failing(
        () async => throw const ReceiveError(
          message: 'database is locked',
          kind: ReceiveErrorKind.other,
        ),
      );
      await container.read(swapHistoryCheckProvider.notifier).check();
      await pumpEventQueue();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.failed);
    });
  });

  test(
    'a progress read refused during a wallet change keeps watching',
    () async {
      final answers = <Object>[
        StateError('The wallet is changing. Try again in a moment.'),
        _status(manual: true),
        _status(),
      ];
      final container = ProviderContainer(
        overrides: [
          ..._wallet(),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {},
              cancel: () async {},
              status: () async => switch (answers.removeAt(0)) {
                final SwapRecoveryStatus status => status,
                final Object error => throw error,
              },
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(swapHistoryCheckProvider.notifier).check();
      expect(answers, isEmpty);
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
    },
  );

  group('a pause the wallet refuses', () {
    /// A container showing a saved job, resumed after a restart, whose pause
    /// fails, and whose saved-state reads answer from `saved`.
    Future<ProviderContainer> refusing(
      SwapRecoveryStatus Function() saved,
    ) async {
      final container = ProviderContainer(
        overrides: [
          ..._wallet(saved: () async => saved()),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {},
              cancel: () async => throw StateError('database is locked'),
              status: () async => saved(),
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(swapHistoryCheckProvider);
      await pumpEventQueue();
      expect(container.read(swapHistoryJobSavedProvider), isTrue);
      await container.read(swapHistoryCheckProvider.notifier).cancel();
      return container;
    }

    test('keeps Pause offered while the wallet has the job, then shows done '
        'once a round ends it', () async {
      var manual = true;
      final container = await refusing(() => _status(manual: manual));
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.pauseFailed,
      );
      expect(container.read(swapHistoryJobSavedProvider), isTrue);

      // A round ending with the job still saved leaves the refusal shown.
      container.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.pauseFailed,
      );

      manual = false;
      container.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
      expect(container.read(swapHistoryJobSavedProvider), isFalse);
    });

    test('with no saved job shows paused', () async {
      final cancel = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          ..._wallet(),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () => cancel.future,
              cancel: () async => throw StateError('database is locked'),
              status: () async => _status(),
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(swapHistoryCheckProvider.notifier);
      final running = notifier.check();
      await notifier.cancel();
      cancel.complete();
      await running;
      expect(container.read(swapHistoryJobSavedProvider), isFalse);
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);
    });
  });

  test(
    'checks every enrolled address without starting ordinary sync',
    () async {
      var begun = 0;
      final sync = _Sync();
      final container = ProviderContainer(
        overrides: [
          ..._wallet(),
          syncProvider.overrideWith(() => sync),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async => begun++,
              cancel: () async {},
              status: () async => _status(),
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(swapHistoryCheckProvider.notifier).check();
      expect(begun, 1);
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
      expect(sync.starts, 1);
    },
  );

  test('a held start cannot resume recovery after pause', () async {
    final start = Completer<void>();
    final sync = _Sync();
    var cancelled = false;
    final container = ProviderContainer(
      overrides: [
        ..._wallet(),
        syncProvider.overrideWith(() => sync),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () => start.future,
            cancel: () async {
              cancelled = true;
            },
            status: () async => _status(),
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(swapHistoryCheckProvider.notifier);
    final running = notifier.check();
    await notifier.cancel();
    start.complete();
    await running;
    expect(cancelled, isTrue);
    expect(sync.starts, 0);
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);
  });

  test('a held completion cannot overwrite pause', () async {
    final pollStarted = Completer<void>();
    final poll = Completer<SwapRecoveryStatus>();
    final container = ProviderContainer(
      overrides: [
        ..._wallet(),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async {},
            cancel: () async {},
            status: () {
              pollStarted.complete();
              return poll.future;
            },
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(swapHistoryCheckProvider.notifier);
    final running = notifier.check();
    await pollStarted.future;
    await notifier.cancel();
    poll.complete(_status());
    await running;
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);
  });

  test(
    'stops with an update request when the service needs a newer app',
    () async {
      final sync = _Sync();
      final container = ProviderContainer(
        overrides: [
          ..._wallet(),
          syncProvider.overrideWith(() => sync),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {},
              cancel: () async {},
              status: () async => _status(checking: true, upgrade: true),
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(swapHistoryCheckProvider.notifier).check();
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.updateRequired,
      );
    },
  );

  test('a start the service refuses as outdated asks for an update', () async {
    final container = ProviderContainer(
      overrides: [
        ..._wallet(),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async => throw const ReceiveError(
              message: 'Update Vizor',
              kind: ReceiveErrorKind.upgradeRequired,
            ),
            cancel: () async {},
            status: () async => _status(),
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(swapHistoryCheckProvider.notifier).check();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.updateRequired,
    );
  });

  test('runs and finishes with NEAR swap privacy off', () async {
    var polls = 0;
    final container = ProviderContainer(
      overrides: [
        ..._wallet(privacy: _PrivacyOff.new),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async {},
            cancel: () async {},
            status: () async => _status(manual: polls++ == 0),
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(swapHistoryCheckProvider.notifier).check();
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
    expect(polls, 2);
  });

  test(
    'a check left to continue shows done once a round ends the job',
    () async {
      var saved = true;
      final container = ProviderContainer(
        overrides: [
          ..._wallet(saved: () async => _status(manual: saved)),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {},
              cancel: () async {},
              status: () async => _status(manual: saved),
              pollInterval: Duration.zero,
              maxWait: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(swapHistoryCheckProvider.notifier).check();
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.continuing,
      );
      expect(container.read(swapHistoryJobSavedProvider), isTrue);

      // A background round finishes the job.
      saved = false;
      container.read(swapRecoveryRoundsProvider.notifier).ended();
      await pumpEventQueue();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
      expect(container.read(swapHistoryJobSavedProvider), isFalse);
    },
  );

  test('a failed read still shows the saved job', () async {
    var failNext = true;
    final container = ProviderContainer(
      overrides: [
        ..._wallet(saved: () async => _status(manual: true)),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async {},
            cancel: () async {},
            status: () async {
              if (failNext) {
                failNext = false;
                throw StateError('database is locked');
              }
              return _status(manual: true);
            },
            pollInterval: Duration.zero,
            maxWait: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // The startup read sees the saved job, then a status read fails. The job
    // is still saved, so it stays offered for pausing rather than failed.
    container.read(swapHistoryCheckProvider);
    await pumpEventQueue();
    expect(failNext, isFalse, reason: 'the failing read happened');
    expect(container.read(swapHistoryJobSavedProvider), isTrue);
    expect(
      container.read(swapHistoryCheckProvider),
      isIn([SwapHistoryCheck.checking, SwapHistoryCheck.continuing]),
    );
  });

  test('after a restart with NEAR swap privacy off, the saved job shows once '
      'a setting change releases the wallet', () async {
    var walletChanging = true;
    final container = ProviderContainer(
      overrides: [
        ..._wallet(
          privacy: _PrivacyOff.new,
          saved: () async {
            if (walletChanging) {
              throw StateError(
                'The wallet is changing. Try again in a moment.',
              );
            }
            return _status(manual: true);
          },
        ),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async {},
            cancel: () async {},
            status: () async => _status(manual: true),
            pollInterval: const Duration(days: 1),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // A setting change holds the wallet, so the startup read is refused.
    final transition = container.read(enhancePirTransitionProvider.notifier);
    transition.update(kEnhancePirChangingMessage);
    container.read(swapHistoryCheckProvider);
    await pumpEventQueue();
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.idle);

    walletChanging = false;
    transition.update(null);
    await pumpEventQueue();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.checking,
      reason: 'the resumed job shows with Pause',
    );
  });

  test('a round that finds the service compatible ends a manual update '
      'request', () async {
    final container = ProviderContainer(
      overrides: [
        ..._wallet(),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async {},
            cancel: () async {},
            status: () async => _status(checking: true, upgrade: true),
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(swapHistoryCheckProvider.notifier).check();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.updateRequired,
    );
    // A round that finds the service compatible clears the wallet's saved
    // request, which this wallet reports as none.
    container.read(swapRecoveryRoundsProvider.notifier).ended();
    await pumpEventQueue();
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.idle);
  });

  test('a check ahead of wallet sync waits instead of failing', () async {
    final container = ProviderContainer(
      overrides: [
        ..._wallet(),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async => throw const ReceiveError(
              message: 'Swap history check has not started.',
              kind: ReceiveErrorKind.waitingForSync,
            ),
            cancel: () async {},
            status: () async => _status(),
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(swapHistoryCheckProvider.notifier).check();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.waitingForSync,
    );
  });

  test('a check before the service reaches a new wallet waits for the '
      'service', () async {
    final container = ProviderContainer(
      overrides: [
        ..._wallet(),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async => throw const ReceiveError(
              message:
                  "The swap recovery service hasn't caught up with this "
                  'wallet yet. Try again in a few minutes.',
              kind: ReceiveErrorKind.waitingForService,
            ),
            cancel: () async {},
            status: () async => _status(),
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(swapHistoryCheckProvider.notifier).check();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.waitingForService,
    );
  });

  group('after a restart', () {
    /// A container whose wallet saved `saved` before the restart and answers
    /// polls with `polls`, recording cancellations in `cancels`.
    ProviderContainer restarted(
      SwapRecoveryStatus saved,
      List<SwapRecoveryStatus> polls,
      List<String> cancels,
    ) {
      final container = ProviderContainer(
        overrides: [
          nearSwapPrivacyProvider.overrideWith(_Privacy.new),
          swapRecoveryStatusReaderProvider.overrideWithValue(() async => saved),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {},
              cancel: () async => cancels.add('cancel'),
              status: () async => polls.removeAt(0),
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'a resumed manual check shows as checking and can be paused',
      () async {
        final cancels = <String>[];
        final container = restarted(_status(manual: true), [
          for (var i = 0; i < 50; i++) _status(manual: true),
        ], cancels);
        container.read(swapHistoryCheckProvider);
        await pumpEventQueue();
        expect(
          container.read(swapHistoryCheckProvider),
          SwapHistoryCheck.checking,
          reason: 'shown with Pause while later rounds resume it',
        );
        await container.read(swapHistoryCheckProvider.notifier).cancel();
        expect(cancels, ['cancel']);
        expect(
          container.read(swapHistoryCheckProvider),
          SwapHistoryCheck.paused,
        );
      },
    );

    test('seed recovery alone leaves the check idle', () async {
      final container = restarted(_status(checking: true), [], []);
      container.read(swapHistoryCheckProvider);
      await pumpEventQueue();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.idle);
    });
  });

  test('a saved-state read that overlaps Pause cannot undo it', () async {
    final reads = <Completer<SwapRecoveryStatus?>>[];
    final cancel = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        ..._wallet(
          saved: () {
            final read = Completer<SwapRecoveryStatus?>();
            reads.add(read);
            return read.future;
          },
        ),
        syncProvider.overrideWith(_Sync.new),
        swapHistoryApiProvider.overrideWithValue(
          SwapHistoryApi(
            begin: () async {},
            cancel: () => cancel.future,
            status: () async => _status(manual: true),
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(swapHistoryCheckProvider);
    await pumpEventQueue();
    // A saved-state read is outstanding when the user pauses.
    expect(reads, isNotEmpty);
    final before = reads.length;
    final notifier = container.read(swapHistoryCheckProvider.notifier);
    final pausing = notifier.cancel();
    // A round ends while the pause waits for the wallet. No read starts.
    container.read(swapRecoveryRoundsProvider.notifier).ended();
    await pumpEventQueue();
    expect(reads, hasLength(before));
    cancel.complete();
    await pausing;
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);

    // The reads from before the pause answer with the job still active.
    for (final read in reads) {
      read.complete(_status(manual: true));
    }
    await pumpEventQueue();
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.paused,
      reason: 'the stale read is dropped',
    );
    expect(container.read(swapHistoryJobSavedProvider), isFalse);
  });
}
