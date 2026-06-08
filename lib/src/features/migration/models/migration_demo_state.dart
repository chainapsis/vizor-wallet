import 'dart:convert';

/// Persisted, time-derived state for the (faked) Orchard→Ironwood migration.
///
/// The migration is theater: all transfers are broadcast immediately.
/// Everything time-based here is computed from [startedAtEpochMs] against a
/// caller-supplied `now`, so it stays pure and testable.
class MigrationDemoState {
  const MigrationDemoState({
    required this.accountUuid,
    required this.startedAtEpochMs,
    required this.totalDurationMs,
    required this.displayAmountZatoshi,
    required this.transferOffsetsMs,
    required this.txids,
  });

  final String accountUuid;
  final int startedAtEpochMs;
  final int totalDurationMs;
  final BigInt displayAmountZatoshi;

  /// Per-transfer "fires at" offsets from start (ms), ascending, first == 0.
  final List<int> transferOffsetsMs;
  final List<String> txids;

  static const int defaultDurationMs = 24 * 60 * 60 * 1000;

  int _rawElapsed(DateTime now) =>
      now.millisecondsSinceEpoch - startedAtEpochMs;

  int elapsedMs(DateTime now) => _rawElapsed(now).clamp(0, totalDurationMs);

  double progressFraction(DateTime now) =>
      totalDurationMs == 0 ? 1.0 : elapsedMs(now) / totalDurationMs;

  Duration remaining(DateTime now) =>
      Duration(milliseconds: totalDurationMs - elapsedMs(now));

  Duration sinceStart(DateTime now) => Duration(milliseconds: elapsedMs(now));

  bool isComplete(DateTime now) => _rawElapsed(now) >= totalDurationMs;

  List<bool> transfersSent(DateTime now) {
    final elapsed = _rawElapsed(now);
    return [for (final o in transferOffsetsMs) elapsed >= o];
  }

  Duration transferEta(int index, DateTime now) {
    final delta = transferOffsetsMs[index] - _rawElapsed(now);
    return Duration(milliseconds: delta < 0 ? 0 : delta);
  }

  Map<String, dynamic> toJson() => {
    'accountUuid': accountUuid,
    'startedAtEpochMs': startedAtEpochMs,
    'totalDurationMs': totalDurationMs,
    'displayAmountZatoshi': displayAmountZatoshi.toString(),
    'transferOffsetsMs': transferOffsetsMs,
    'txids': txids,
  };

  static MigrationDemoState fromJson(Map<String, dynamic> json) =>
      MigrationDemoState(
        accountUuid: json['accountUuid'] as String,
        startedAtEpochMs: json['startedAtEpochMs'] as int,
        totalDurationMs: json['totalDurationMs'] as int,
        displayAmountZatoshi: BigInt.parse(
          json['displayAmountZatoshi'] as String,
        ),
        transferOffsetsMs: (json['transferOffsetsMs'] as List)
            .map((e) => e as int)
            .toList(),
        txids: (json['txids'] as List).map((e) => e as String).toList(),
      );

  String encode() => jsonEncode(toJson());

  static MigrationDemoState decode(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
