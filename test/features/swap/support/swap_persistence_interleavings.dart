part of '../swap_screen_test.dart';

// Random interleavings of swap activity persistence through the real swap
// notifier, activity tracker and deletion-safe store. Every storage read and
// save, every wallet reservation start and every provider status request waits
// on a held future, and each seed releases them in its own random order while
// it starts swaps, refreshes statuses, switches accounts and deletes one.

/// Seeds each run checks. Raise it locally with
/// `--dart-define=SWAP_INTERLEAVING_SEEDS=5000`.
const _interleavingSeeds = int.fromEnvironment(
  'SWAP_INTERLEAVING_SEEDS',
  defaultValue: 150,
);

/// The first seed, to replay a failure with
/// `--dart-define=SWAP_INTERLEAVING_FIRST_SEED=<seed>` and one seed.
const _interleavingFirstSeed = int.fromEnvironment(
  'SWAP_INTERLEAVING_FIRST_SEED',
  defaultValue: 1,
);

/// Prints each seed's steps and releases, to replay a failure.
const _interleavingTrace = bool.fromEnvironment('SWAP_INTERLEAVING_TRACE');

/// Prints `line` when tracing.
void _trace(String line) {
  // ignore: avoid_print
  if (_interleavingTrace) print('interleaving: $line');
}

/// What the seeds of one run covered, printed at its end.
final _interleavingTotals = <String, int>{};

/// Counts one `event` toward [_interleavingTotals].
void _count(String event) =>
    _interleavingTotals[event] = (_interleavingTotals[event] ?? 0) + 1;

/// One held operation, released by the seed's driver.
class _HeldOp {
  _HeldOp(this.label, {required this.canFail, this.failRate});

  final String label;
  final bool canFail;

  /// How often it fails whenever released, or null to fail only as often as
  /// the release asks.
  final double? failRate;
  final done = Completer<bool>();
}

/// Every held operation of one seed.
class _HeldOps {
  final pending = <_HeldOp>[];

  /// Waits until the driver releases this operation, throwing if it releases
  /// it as failed.
  Future<void> wait(
    String label, {
    bool canFail = false,
    double? failRate,
  }) async {
    final op = _HeldOp(label, canFail: canFail, failRate: failRate);
    _trace('hold $label');
    pending.add(op);
    if (await op.done.future) {
      throw StateError('Secure storage is unavailable ($label).');
    }
  }

  /// Releases one pending operation chosen by `rng`, failing a save with
  /// probability `failure`. Returns whether one was pending.
  bool releaseOne(Random rng, {double failure = 0}) {
    if (pending.isEmpty) return false;
    final op = pending.removeAt(rng.nextInt(pending.length));
    final failed = op.canFail && rng.nextDouble() < (op.failRate ?? failure);
    if (failed) _count(op.failRate == null ? 'failed saves' : 'refused starts');
    _trace('release ${op.label}${failed ? ' (fails)' : ''}');
    op.done.complete(failed);
    return true;
  }
}

/// Swap activity storage whose reads and saves each wait on a held operation.
class _HeldActivityStore extends _FakeSwapPersistenceStore {
  _HeldActivityStore(this.ops);

  final _HeldOps ops;

  /// What `accountUuid` has stored, read without waiting.
  List<String> storedIds(String accountUuid) => [
    for (final intent in _intentsByAccount[accountUuid] ?? const <SwapIntent>[])
      intent.id,
  ];

  /// The swaps `accountUuid` has stored, read without waiting.
  List<SwapIntent> stored(String accountUuid) =>
      _intentsByAccount[accountUuid] ?? const [];

  /// Whether `accountUuid` has anything stored.
  bool hasStored(String accountUuid) =>
      _intentsByAccount.containsKey(accountUuid);

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    await ops.wait('load $accountUuid');
    return super.loadRecords(accountUuid: accountUuid);
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    await ops.wait('save $accountUuid', canFail: true);
    return super.saveRecords(accountUuid: accountUuid, records: records);
  }
}

/// Incoming reservations whose start waits on a held operation, and fails
/// when the driver fails it, as a stale reservation does.
class _HeldReservationStore extends Fake implements ReceiveReservationStore {
  _HeldReservationStore(this.ops);

  final _HeldOps ops;
  final _accepted = <String, SwapQuote>{};

  /// Deposit addresses whose reservation start succeeded.
  final started = <String>{};

  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async =>
      'request-$reservation';

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {
    if (accepted != null) _accepted[request] = accepted;
  }

  @override
  Future<ReceiveDeposit> start(String request) async {
    // A quarter of starts are refused, whether or not saves fail.
    await ops.wait('start $request', canFail: true, failRate: 0.25);
    final deposit = _accepted[request]!.depositInstruction;
    started.add(deposit.address);
    return ReceiveDeposit(
      address: deposit.address,
      memo: deposit.memo,
      deadlineSeconds: PlatformInt64Util.from(0),
    );
  }
}

/// A provider that gives every quote its own deposit address and holds every
/// status request.
class _HeldStatusSwapProvider extends _FakeSwapProvider {
  _HeldStatusSwapProvider(this.ops) : super(zecDepositMemo: null);

  final _HeldOps ops;
  var _quotes = 0;

  @override
  String get externalDepositAddress => '0xdeposit-${++_quotes}';

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    await ops.wait('status $intentId');
    return super.getStatus(intentId, depositMemo: depositMemo);
  }
}

/// The deletion-safe store, recording every merge that would put an older
/// copy of a swap over a newer saved one.
class _CheckedSwapActivityStore extends DeletionSafeSwapActivityStore {
  _CheckedSwapActivityStore(super.inner);

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) {
    _trace('replace $accountUuid ${[for (final r in records) r.id]}');
    return super.saveRecords(accountUuid: accountUuid, records: records);
  }

  final regressions = <String>[];

  @override
  Future<void> update({
    required String accountUuid,
    required List<SwapIntentRecord> Function(List<SwapIntentRecord> saved)
    transform,
  }) => super.update(
    accountUuid: accountUuid,
    transform: (saved) {
      final merged = transform(saved);
      _trace(
        'merge $accountUuid ${[for (final r in saved) r.id]} -> ${[for (final r in merged) r.id]}',
      );
      final before = {for (final record in saved) record.id: record};
      for (final after in merged) {
        final old = before[after.id];
        if (old == null) continue;
        final lost = <String>[
          if (old.depositClaimedAt != null && after.depositClaimedAt == null)
            'depositClaimedAt',
          if ((old.depositTxHash ?? '').isNotEmpty &&
              (after.depositTxHash ?? '').isEmpty)
            'depositTxHash',
          if (old.lastStatusCheckedAt != null &&
              (after.lastStatusCheckedAt == null ||
                  after.lastStatusCheckedAt!.isBefore(
                    old.lastStatusCheckedAt!,
                  )))
            'lastStatusCheckedAt',
          if (old.status.isTerminal && !after.status.isTerminal) 'status',
          if (!old.startPending && after.startPending) 'startPending',
        ];
        if (lost.isNotEmpty) {
          regressions.add('merge regressed ${after.id} $lost');
        }
      }
      return merged;
    },
  );
}

/// NEAR swap privacy the driver turns on and off.
class _DrivenPrivacy extends NearSwapPrivacyNotifier {
  @override
  bool build() => true;

  @override
  Future<void> set(bool enabled) async => state = enabled;
}

/// A swap whose start finished: its id, the account it started on, and
/// whether the active account changed while it started.
typedef _StartedSwap = ({String id, String account, bool switched});

/// Runs one seed and returns the invariants it broke.
Future<List<String>> _runInterleaving(WidgetTester tester, int seed) async {
  final rng = Random(seed);
  final ops = _HeldOps();
  final inner = _HeldActivityStore(ops);
  final store = _CheckedSwapActivityStore(inner);
  final provider = _HeldStatusSwapProvider(ops);
  final reservations = _CountingReservations('u1incoming');
  final reservationStore = _HeldReservationStore(ops);
  var privacyOn = true;
  // Half the seeds inject failed saves, which ordinary swaps also lose.
  final failure = rng.nextBool() ? 0.2 : 0.0;

  await tester.pumpWidget(
    _routerHarness(
      GoRouter(
        initialLocation: '/swap',
        routes: [
          GoRoute(path: '/swap', builder: (_, _) => const SizedBox.shrink()),
        ],
      ),
      swapProvider: provider,
      seedSwapActivityFixtures: false,
      activityStore: store,
      reservationStore: reservationStore,
      reserveSwapAddress: ({required accountUuid, required direction}) async =>
          privacyOn
          ? reservations.reserve(accountUuid: accountUuid, direction: direction)
          : null,
      bootstrap: _twoAccountBootstrap,
      accountNotifier: () =>
          _FakeSwapAccountNotifier(_twoAccountBootstrap.initialAccountState),
      nearSwapPrivacy: _DrivenPrivacy.new,
      statusPollInterval: const Duration(days: 1),
      priceRefreshInterval: const Duration(days: 1),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SizedBox)),
  );
  final notifier = container.read(swapStateProvider.notifier);
  final accounts = container.read(accountProvider.notifier);
  String active() => container.read(accountProvider).value!.activeAccountUuid!;

  // Accounts switched to whose swaps may not have loaded yet. Once nothing
  // is held, every load has finished.
  final loading = <String>{};
  // Status refreshes in flight, by the account they started on.
  final refreshing = <String, int>{};
  final privateIds = <String>{};
  // Private swaps whose funding instructions were visible, on screen or in
  // storage, before the wallet locked their reservation.
  final exposedEarly = <String>{};

  /// Records every private swap whose funding instructions could be shown
  /// before its wallet start succeeded.
  void checkHidden() {
    final visible = [
      ...container.read(swapStateProvider).intents,
      for (final account in ['account-1', 'account-2'])
        ...inner.stored(account),
    ];
    for (final intent in visible) {
      if (!privateIds.contains(intent.id) ||
          reservationStore.started.contains(intent.id)) {
        continue;
      }
      if (!intent.startPending ||
          SwapActivityDepositInstruction.fromIntent(intent) != null) {
        exposedEarly.add(intent.id);
      }
    }
  }

  /// Lets microtasks and short timers run.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      checkHidden();
    }
    if (ops.pending.isEmpty) loading.clear();
  }

  /// Waits for `future`, releasing held operations while it is stuck on them.
  Future<T?> drive<T>(Future<T> future) async {
    T? result;
    var finished = false;
    future.then(
      (value) {
        result = value;
        finished = true;
      },
      onError: (Object _) {
        finished = true;
      },
    );
    for (var i = 0; i < 200 && !finished; i++) {
      await settle();
      if (!finished) ops.releaseOne(rng);
    }
    return result;
  }

  final started = <_StartedSwap>[];
  // Ordinary swaps a #1037 wipe can reach (see the switch below).
  final exposed = <String>{};
  String? startingAccount;
  String? startingId;
  final deleted = <String>{};
  // Refused private starts whose account switched while they ran.
  final refusedAcrossSwitch = <String>{};
  Future<void>? starting;

  for (var step = 0; step < 14; step++) {
    final roll = rng.nextInt(100);
    if (roll < 22 && starting == null && !deleted.contains(active())) {
      final private = rng.nextInt(3) > 0;
      if (!private) {
        // An ordinary start that finishes before its account's swaps load is
        // overwritten by the load, as on #1037 (filed separately), so ordinary
        // starts begin once everything held so far is done.
        while (ops.releaseOne(rng)) {
          await settle();
        }
      }
      if (privacyOn != private) {
        privacyOn = private;
        await container.read(nearSwapPrivacyProvider.notifier).set(private);
      }
      _trace('${private ? 'private' : 'ordinary'} start on ${active()}');
      notifier.selectDirection(SwapDirection.externalToZec);
      notifier.updateAmount('25');
      notifier.updateDestination('0x52908400098527886e0f7030069857d2e4169ee7');
      await drive(notifier.showReview());
      final quote = container.read(swapStateProvider).reviewQuote;
      if (quote == null) continue;
      final account = active();
      var switchedDuring = false;
      final id = quote.depositInstruction.address;
      if (quote.receiveRequestId != null) {
        privateIds.add(id);
        if (loading.contains(account)) {
          // A start while its account's swaps load can be overwritten by the
          // load, as an ordinary one is on #1037 (filed separately).
          _count('private starts before a load');
          exposed.add(id);
        }
      }
      startingAccount = account;
      startingId = id;
      final switchWatch = container.listen(
        accountProvider.select((value) => value.value?.activeAccountUuid),
        (_, _) => switchedDuring = true,
      );
      starting = notifier
          .startIntent()
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() {
            switchWatch.close();
            _trace('start of $id finished');
            // A private swap started once its wallet reservation did.
            if (privateIds.contains(id)
                ? reservationStore.started.contains(id)
                : provider.startedQuotes.any(
                    (q) => q.depositInstruction.address == id,
                  )) {
              _count(
                privateIds.contains(id) ? 'private starts' : 'ordinary starts',
              );
              if (switchedDuring) _count('starts across a switch');
              started.add((id: id, account: account, switched: switchedDuring));
            }
            if (privateIds.contains(id) &&
                !reservationStore.started.contains(id) &&
                switchedDuring) {
              // A reload during the start can show it again after its removal,
              // and a later save of that screen store it again.
              _count('refused starts across a switch');
              refusedAcrossSwitch.add(id);
            }
            starting = null;
            startingAccount = null;
            startingId = null;
          });
    } else if (roll < 37) {
      if (loading.contains(active())) {
        // A refresh before the account's swaps load can save its screen,
        // still holding the other account's swaps, over its storage, as on
        // #1037 (filed separately).
        _count('refreshes before a load');
        for (final swap in started) {
          if (swap.account == active()) exposed.add(swap.id);
        }
      }
      _trace('refresh on ${active()}');
      _count('refreshes');
      final account = active();
      refreshing[account] = (refreshing[account] ?? 0) + 1;
      unawaited(
        notifier.refreshOpenIntentStatuses().whenComplete(
          () => refreshing[account] = refreshing[account]! - 1,
        ),
      );
    } else if (roll < 52) {
      final target = active() == 'account-1' ? 'account-2' : 'account-1';
      if (!deleted.contains(target)) {
        if (loading.contains(active()) || (refreshing[active()] ?? 0) > 0) {
          // Leaving an account before its swaps load saves its screen, still
          // holding the other account's swaps, over its storage. A refresh
          // that finishes after a switch away and back does the same. Either
          // wipes its ordinary swaps, as on #1037 (filed separately).
          _count('switches away before a load');
          for (final swap in started) {
            if (swap.account == active()) exposed.add(swap.id);
          }
          if (startingAccount == active()) exposed.add(startingId!);
        }
        loading.add(target);
        _trace('switch to $target');
        _count('switches');
        await accounts.switchAccount(target);
      }
    } else if (roll < 56 &&
        !deleted.contains('account-2') &&
        active() == 'account-1') {
      deleted.add('account-2');
      _trace('delete account-2');
      _count('deletions');
      unawaited(store.deleteForAccount(accountUuid: 'account-2'));
    } else {
      for (var n = rng.nextInt(4); n >= 0; n--) {
        ops.releaseOne(rng, failure: failure);
      }
    }
    await settle();
  }

  // Let everything finish: release every held operation, without failures.
  for (var i = 0; i < 400; i++) {
    if (!ops.releaseOne(rng) && starting == null) {
      await tester.pump(const Duration(seconds: 30));
      if (ops.pending.isEmpty && starting == null) break;
    }
    await settle();
  }

  final broken = <String>[];
  if (ops.pending.isNotEmpty || starting != null) {
    broken.add('did not settle: ${ops.pending.map((op) => op.label)}');
  }
  final shown = container.read(swapStateProvider).intents;
  final screen = {for (final intent in shown) intent.id};
  for (final swap in started) {
    if (deleted.contains(swap.account)) continue;
    final stored = inner.storedIds(swap.account);
    final isPrivate = privateIds.contains(swap.id);
    // A swap a #1037 wipe reached can be lost, private or not (filed
    // separately). An ordinary one that finished after an account switch, or
    // whose save failed, can be lost too. A private one is saved before its
    // wallet start, so neither loses it.
    if (exposed.contains(swap.id) ||
        (!isPrivate && (swap.switched || failure > 0))) {
      continue;
    }
    _count(isPrivate ? 'private checked' : 'ordinary checked');
    if (!stored.contains(swap.id)) {
      broken.add(
        '${isPrivate ? 'private' : 'ordinary'} ${swap.id} missing from '
        '${swap.account} storage $stored',
      );
    }
    if (isPrivate && swap.account == active() && !screen.contains(swap.id)) {
      broken.add('private ${swap.id} missing from the screen $screen');
    }
    if (shown.any((intent) => intent.id == swap.id && intent.startPending)) {
      broken.add('started ${swap.id} is still shown as starting');
    }
    // A failed save can leave its flip unsaved, which a later launch handles.
    if (isPrivate && failure == 0) {
      final record = inner
          .stored(swap.account)
          .where((intent) => intent.id == swap.id);
      if (record.any((intent) => intent.startPending)) {
        broken.add('started ${swap.id} is still saved as starting');
      }
    }
  }
  // A private swap whose wallet start never succeeded is removed, unless a
  // failed save kept its removal from landing or an account switch during the
  // start let a reload bring it back.
  if (failure == 0) {
    for (final id in privateIds) {
      if (reservationStore.started.contains(id) ||
          refusedAcrossSwitch.contains(id)) {
        continue;
      }
      for (final account in ['account-1', 'account-2']) {
        if (inner.storedIds(account).contains(id)) {
          broken.add('unstarted $id still stored for $account');
        }
      }
      if (screen.contains(id)) broken.add('unstarted $id still on the screen');
    }
  }
  broken.addAll(store.regressions);
  for (final id in exposedEarly) {
    broken.add('instructions for $id visible before its wallet start');
  }
  for (final account in deleted) {
    if (inner.hasStored(account)) {
      broken.add('deleted $account still stores ${inner.storedIds(account)}');
    }
  }
  for (final account in ['account-1', 'account-2']) {
    final ids = inner.storedIds(account);
    if (ids.toSet().length != ids.length) {
      broken.add('$account stores duplicates $ids');
    }
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(days: 2));
  return broken;
}

/// Registers the randomized swap persistence test.
void _swapPersistenceInterleavingTests() {
  testWidgets('random swap persistence interleavings keep every invariant', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final failures = <String>[];
    for (
      var seed = _interleavingFirstSeed;
      seed < _interleavingFirstSeed + _interleavingSeeds;
      seed++
    ) {
      // A failed save that nothing awaits surfaces as an uncaught error, as a
      // failed account-switch save does on #1037 (filed separately). Any
      // other uncaught error fails the seed.
      final uncaught = <String>[];
      final result = Completer<List<String>>();
      runZonedGuarded(
        () async {
          try {
            result.complete(await _runInterleaving(tester, seed));
          } catch (error) {
            result.complete(['threw $error']);
          }
        },
        (error, _) {
          if (!'$error'.contains('Secure storage is unavailable')) {
            uncaught.add('$error');
          }
        },
      );
      final broken = [...await result.future, ...uncaught];
      if (broken.isNotEmpty) failures.add('seed $seed: ${broken.join('; ')}');
    }
    // ignore: avoid_print
    print(
      'swap persistence interleavings: $_interleavingSeeds seeds from '
      '$_interleavingFirstSeed, $_interleavingTotals',
    );
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  });
}
