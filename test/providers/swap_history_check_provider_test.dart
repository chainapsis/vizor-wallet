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
  void continueSwapRecovery() => starts++;
}

/// NEAR swap privacy, on until a test turns it off.
class _Privacy extends NearSwapPrivacyNotifier {
  @override
  bool build() => true;

  /// Turns the setting off, as the Settings toggle does.
  void turnOff() => state = false;

  /// Turns the setting back on, as the Settings toggle does.
  void turnOn() => state = true;
}

/// NEAR swap privacy, off until a test turns it on.
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
  checkingHistory: checking || manual,
  manualCheckActive: manual,
  upgradeRequired: upgrade,
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
    /// A container whose check round fails as the receiver service does when
    /// it can't be reached, and whose saved-state reads answer with `saved`.
    ProviderContainer failing(Future<SwapRecoveryStatus?> Function() saved) {
      final container = ProviderContainer(
        overrides: [
          ..._wallet(saved: saved),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async => throw const ReceiveError(
                message: 'transport: connection refused',
                kind: ReceiveErrorKind.other,
              ),
              cancel: () async {},
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

    test('with a saved job shows it checking again, with Pause', () async {
      final container = failing(() async => _status(manual: true));
      await container.read(swapHistoryCheckProvider.notifier).check();
      await pumpEventQueue();
      expect(
        container.read(swapHistoryCheckProvider),
        isIn([SwapHistoryCheck.checking, SwapHistoryCheck.continuing]),
      );
      expect(container.read(swapHistoryJobSavedProvider), isTrue);
    });

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

    test('shows paused once NEAR swap privacy is turned off', () async {
      final container = await refusing(() => _status(manual: true));
      (container.read(nearSwapPrivacyProvider.notifier) as _Privacy).turnOff();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);
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

  test(
    'turning NEAR swap privacy off between polls pauses the check, and turning '
    'it on shows the saved job again',
    () async {
      final polls = <Completer<SwapRecoveryStatus>>[];
      // The wallet's saved state, which re-enabling the setting reads.
      SwapRecoveryStatus? saved;
      final container = ProviderContainer(
        overrides: [
          ..._wallet(saved: () async => saved),
          syncProvider.overrideWith(_Sync.new),
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async => saved = _status(manual: true),
              cancel: () async {},
              status: () {
                final poll = Completer<SwapRecoveryStatus>();
                polls.add(poll);
                return poll.future;
              },
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final running = container.read(swapHistoryCheckProvider.notifier).check();
      await pumpEventQueue();
      polls.single.complete(_status(manual: true));
      await pumpEventQueue();
      expect(polls, hasLength(2));

      final privacy =
          container.read(nearSwapPrivacyProvider.notifier) as _Privacy;
      privacy.turnOff();
      // A disabled account reports no unfinished check.
      polls.last.complete(_status());
      await running;
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);

      // The wallet still has the job, so turning the setting back on shows it
      // as checking, with Pause, until the wallet finishes it.
      privacy.turnOn();
      await pumpEventQueue();
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.checking,
      );
      polls.last.complete(_status(manual: true));
      await pumpEventQueue();
      expect(
        container.read(swapHistoryCheckProvider),
        SwapHistoryCheck.checking,
      );
      saved = _status();
      polls.last.complete(_status());
      await pumpEventQueue();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
    },
  );

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

  test(
    'a failed read then a privacy toggle still shows the saved job',
    () async {
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

      final privacy =
          container.read(nearSwapPrivacyProvider.notifier) as _Privacy;
      privacy.turnOff();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);
      privacy.turnOn();
      await pumpEventQueue();
      // The wallet resumes the job, so Pause is offered again.
      expect(
        container.read(swapHistoryCheckProvider),
        isIn([SwapHistoryCheck.checking, SwapHistoryCheck.continuing]),
      );
    },
  );

  test('re-enabling after a restart reads the saved job once the change '
      'reaches the wallet', () async {
    var walletChanging = false;
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
            pollInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(swapHistoryCheckProvider);
    await pumpEventQueue();
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.idle);

    // Settings turns the setting on while its change still holds the wallet.
    final transition = container.read(enhancePirTransitionProvider.notifier);
    transition.update(kEnhancePirChangingMessage);
    walletChanging = true;
    (container.read(nearSwapPrivacyProvider.notifier) as _Privacy).turnOn();
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

  test('re-enabling privacy does not resume a check the user paused', () async {
    final (container, _, calls) = setup(checking: [true]);
    final notifier = container.read(swapHistoryCheckProvider.notifier);
    final running = notifier.check();
    await notifier.cancel();
    await running;
    final privacy =
        container.read(nearSwapPrivacyProvider.notifier) as _Privacy;
    privacy.turnOff();
    privacy.turnOn();
    await pumpEventQueue();
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);
    expect(calls, ['begin']);
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
    expect(container.read(swapRecoveryUpdateRequiredProvider), isTrue);

    container.read(swapRecoveryUpdateRequiredProvider.notifier).set(false);
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
