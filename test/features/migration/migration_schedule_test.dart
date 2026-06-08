import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_demo_state.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_schedule.dart';

void main() {
  test('builds a staggered, ascending schedule with first transfer at 0', () {
    final now = DateTime.fromMillisecondsSinceEpoch(5000000);
    final state = buildMigrationDemoState(
      accountUuid: 'acc-1',
      displayAmountZatoshi: BigInt.from(42),
      txids: const ['a', 'b', 'c'],
      now: now,
      random: Random(7),
    );

    expect(state.accountUuid, 'acc-1');
    expect(state.startedAtEpochMs, 5000000);
    expect(state.totalDurationMs, MigrationDemoState.defaultDurationMs);
    expect(state.transferOffsetsMs.length, 3);
    expect(state.transferOffsetsMs.first, 0);
    // Ascending and within the window.
    final sorted = [...state.transferOffsetsMs]..sort();
    expect(state.transferOffsetsMs, sorted);
    expect(
      state.transferOffsetsMs.last,
      lessThan(MigrationDemoState.defaultDurationMs),
    );
    // Transfers 2 and 3 are staggered (not both at 0).
    expect(state.transferOffsetsMs[1], greaterThan(0));
  });

  test('matches the number of returned txids', () {
    final state = buildMigrationDemoState(
      accountUuid: 'acc-1',
      displayAmountZatoshi: BigInt.from(42),
      txids: const ['a', 'b'],
      now: DateTime.fromMillisecondsSinceEpoch(0),
      random: Random(7),
    );

    expect(state.transferOffsetsMs.length, 2);
    expect(state.transferOffsetsMs.first, 0);
    expect(state.transferOffsetsMs.last, greaterThan(0));
  });

  test('keeps one visible transfer when no txids are present', () {
    final state = buildMigrationDemoState(
      accountUuid: 'acc-1',
      displayAmountZatoshi: BigInt.from(42),
      txids: const [],
      now: DateTime.fromMillisecondsSinceEpoch(0),
      random: Random(7),
    );

    expect(state.transferOffsetsMs, const [0]);
  });

  test('is deterministic for a fixed seed', () {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final a = buildMigrationDemoState(
      accountUuid: 'x',
      displayAmountZatoshi: BigInt.one,
      txids: const [],
      now: now,
      random: Random(1),
    );
    final b = buildMigrationDemoState(
      accountUuid: 'x',
      displayAmountZatoshi: BigInt.one,
      txids: const [],
      now: now,
      random: Random(1),
    );
    expect(a.transferOffsetsMs, b.transferOffsetsMs);
  });
}
