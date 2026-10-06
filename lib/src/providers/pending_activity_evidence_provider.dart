import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

const kActivityEtaFreshness = Duration(seconds: 30);
const kActivityLongWait = Duration(minutes: 5);
const kActivityFundingLongWait = Duration(minutes: 8);

/// Broadcast responses and wallet history can use opposite txid byte orders.
/// Use one local identity; never use the canonical form for network queries.
String activityTxidKey(String txid) {
  final value = txid.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) return value;
  final reversed = List.generate(
    32,
    (i) => value.substring(62 - i * 2, 64 - i * 2),
  ).join();
  return value.compareTo(reversed) < 0 ? value : reversed;
}

final activityEtaClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Session-only evidence. A local pending transaction is not evidence of
/// propagation. Restarting the app requires a new successful broadcast or
/// mempool observation before showing an estimate.
class PendingActivityEvidence {
  const PendingActivityEvidence({
    required this.now,
    this.networkCheckedAt,
    this.checkedTip,
    this.foreground = true,
    this.connectionFailed = false,
    this.observedAt = const {},
    this.unavailableHistoryAccounts = const {},
  });

  final DateTime now;
  final DateTime? networkCheckedAt;
  final int? checkedTip;
  final bool foreground;
  final bool connectionFailed;
  final Map<(String, String), DateTime> observedAt;
  final Set<String> unavailableHistoryAccounts;

  String? labelFor(
    String accountUuid,
    String txid,
    int scannedHeight, {
    bool waitingForFunding = false,
  }) {
    final checked = networkCheckedAt;
    final observed = observedAt[(accountUuid, activityTxidKey(txid))];
    if (unavailableHistoryAccounts.contains(accountUuid) ||
        !foreground ||
        checked == null ||
        observed == null ||
        checkedTip == null ||
        scannedHeight < checkedTip!) {
      return null;
    }
    final freshness = now.difference(checked);
    final elapsed = now.difference(observed);
    if (freshness.isNegative ||
        freshness >= kActivityEtaFreshness ||
        elapsed.isNegative) {
      return null;
    }
    final longWait = waitingForFunding
        ? kActivityFundingLongWait
        : kActivityLongWait;
    return elapsed >= longWait
        ? 'Taking longer'
        : waitingForFunding
        ? 'Est. 2–6 min'
        : 'Est. 1–3 min';
  }
}

final pendingActivityEvidenceProvider =
    NotifierProvider<
      PendingActivityEvidenceController,
      PendingActivityEvidence
    >(PendingActivityEvidenceController.new);

class PendingActivityEvidenceController
    extends Notifier<PendingActivityEvidence> {
  Timer? _timer;
  late DateTime Function() _clock;

  @override
  PendingActivityEvidence build() {
    _clock = ref.watch(activityEtaClockProvider);
    ref.onDispose(() => _timer?.cancel());
    return PendingActivityEvidence(now: _clock());
  }

  void observe({required String accountUuid, required Iterable<String> txids}) {
    final now = _clock();
    final observations = {...state.observedAt};
    // Bound session memory without inferring transaction failure from age.
    observations.removeWhere(
      (_, at) => now.difference(at) > const Duration(days: 1),
    );
    for (final txid in txids) {
      if (accountUuid.isEmpty || txid.trim().isEmpty) continue;
      observations.putIfAbsent((accountUuid, activityTxidKey(txid)), () => now);
    }
    while (observations.length > 512) {
      observations.remove(observations.keys.first);
    }
    state = PendingActivityEvidence(
      now: now,
      observedAt: Map.unmodifiable(observations),
      unavailableHistoryAccounts: state.unavailableHistoryAccounts,
      networkCheckedAt: state.networkCheckedAt,
      checkedTip: state.checkedTip,
      foreground: state.foreground,
      connectionFailed: state.connectionFailed,
    );
    _scheduleClock();
  }

  void networkChecked(int tip, {bool allowBackground = false}) {
    if (!state.foreground && !allowBackground) return;
    final now = _clock();
    state = PendingActivityEvidence(
      now: now,
      observedAt: state.observedAt,
      unavailableHistoryAccounts: state.unavailableHistoryAccounts,
      networkCheckedAt: now,
      checkedTip: tip,
      foreground: state.foreground,
    );
  }

  void invalidateNetwork({bool connectionFailed = false}) {
    state = PendingActivityEvidence(
      now: _clock(),
      observedAt: state.observedAt,
      unavailableHistoryAccounts: state.unavailableHistoryAccounts,
      foreground: state.foreground,
      connectionFailed: connectionFailed,
    );
  }

  void setForeground(bool foreground) {
    state = PendingActivityEvidence(
      now: _clock(),
      observedAt: state.observedAt,
      unavailableHistoryAccounts: state.unavailableHistoryAccounts,
      foreground: foreground,
      networkCheckedAt: state.networkCheckedAt,
      checkedTip: state.checkedTip,
      connectionFailed: state.connectionFailed,
    );
    _scheduleClock();
  }

  void historyReadCompleted(String accountUuid, {required bool available}) {
    final unavailable = {...state.unavailableHistoryAccounts};
    available ? unavailable.remove(accountUuid) : unavailable.add(accountUuid);
    state = PendingActivityEvidence(
      now: _clock(),
      observedAt: state.observedAt,
      unavailableHistoryAccounts: Set.unmodifiable(unavailable),
      networkCheckedAt: state.networkCheckedAt,
      checkedTip: state.checkedTip,
      foreground: state.foreground,
      connectionFailed: state.connectionFailed,
    );
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    state = PendingActivityEvidence(
      now: _clock(),
      foreground: state.foreground,
    );
  }

  void _scheduleClock() {
    _timer?.cancel();
    _timer = null;
    if (!state.foreground || state.observedAt.isEmpty) return;
    // One shared low-frequency clock; no timers or network requests per row.
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      state = PendingActivityEvidence(
        now: _clock(),
        observedAt: state.observedAt,
        unavailableHistoryAccounts: state.unavailableHistoryAccounts,
        networkCheckedAt: state.networkCheckedAt,
        checkedTip: state.checkedTip,
        foreground: state.foreground,
        connectionFailed: state.connectionFailed,
      );
    });
  }
}
