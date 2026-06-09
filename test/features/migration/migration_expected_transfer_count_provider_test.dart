import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/providers/migration_expected_transfer_count_provider.dart';

void main() {
  test('migration expected count round-trips through persisted json', () {
    final startedAt = DateTime.utc(2026, 6, 9, 3, 0);
    final count = MigrationExpectedTransferCount(
      count: 2,
      firstTxid: 'ABCD',
      startedAt: startedAt,
    );

    final restored = MigrationExpectedTransferCount.fromJson(count.toJson());

    expect(restored, isNotNull);
    expect(restored!.count, 2);
    expect(restored.firstTxid, 'abcd');
    expect(restored.startedAt, startedAt);
  });

  test('migration expected count expires after delayed broadcast window', () {
    final startedAt = DateTime.utc(2026, 6, 9, 3, 0);
    final count = MigrationExpectedTransferCount(
      count: 2,
      firstTxid: 'abcd',
      startedAt: startedAt,
    );

    expect(count.isExpired(startedAt.add(const Duration(seconds: 104))), false);
    expect(count.isExpired(startedAt.add(const Duration(seconds: 106))), true);
  });

  test('migration expected count rejects malformed persisted json', () {
    expect(MigrationExpectedTransferCount.fromJson(null), isNull);
    expect(
      MigrationExpectedTransferCount.fromJson({
        'count': 0,
        'firstTxid': 'abcd',
        'startedAt': DateTime.utc(2026).toIso8601String(),
      }),
      isNull,
    );
    expect(
      MigrationExpectedTransferCount.fromJson({
        'count': 2,
        'firstTxid': '',
        'startedAt': DateTime.utc(2026).toIso8601String(),
      }),
      isNull,
    );
  });
}
