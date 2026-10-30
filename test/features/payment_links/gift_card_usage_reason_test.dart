import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';

void main() {
  test('empty usage reads preserve saved pending reasons and known usage', () {
    for (final saved in [
      const GiftCardUsage(reason: GiftCardUsageReason.awaitingConfirmation),
      const GiftCardUsage(status: GiftCardUsageStatus.unused),
      const GiftCardUsage(status: GiftCardUsageStatus.used),
    ]) {
      expect(saved.withLatestObservation(null), same(saved));
      expect(saved.withLatestObservation(const GiftCardUsage()), same(saved));
    }
  });

  test('only a newer observed usage replaces the saved snapshot', () {
    final saved = GiftCardUsage(
      status: GiftCardUsageStatus.unused,
      checkedAt: DateTime.utc(2026, 10, 20),
    );
    final older = GiftCardUsage(
      status: GiftCardUsageStatus.spendDetected,
      checkedAt: DateTime.utc(2026, 10, 19),
    );
    final newer = GiftCardUsage(
      status: GiftCardUsageStatus.spendDetected,
      checkedAt: DateTime.utc(2026, 10, 21),
    );
    expect(saved.withLatestObservation(older), same(saved));
    expect(saved.withLatestObservation(newer), same(newer));
    expect(
      newer.withLatestObservation(
        const GiftCardUsage(reason: GiftCardUsageReason.scanIncomplete),
      ),
      same(newer),
    );
  });

  test('legacy unknown records do not imply unconfirmed funding', () {
    final legacy = const GiftCardUsage().toJson()..remove('reason');
    final usage = GiftCardUsage.fromJson(legacy);
    expect(usage.reason, isNull);
    expect(usage.label, 'Unverified');
    expect(GiftCardUsage.fromJson(null).reason, isNull);
  });

  test('each reason survives persistence and account registration', () {
    for (final reason in GiftCardUsageReason.values) {
      final usage = GiftCardUsage.fromJson(
        GiftCardUsage(reason: reason).toJson(),
      ).withAccount('observer');
      expect(usage.reason, reason);
      expect(usage.explanation, isNotEmpty);
      expect(
        usage.label,
        reason == GiftCardUsageReason.awaitingConfirmation
            ? 'Confirming'
            : 'Unverified',
      );
    }
  });

  test('confirmed usage cannot retain a contradictory pending reason', () {
    final invalid = const GiftCardUsage(
      status: GiftCardUsageStatus.unused,
      reason: GiftCardUsageReason.awaitingConfirmation,
    ).toJson();
    expect(() => GiftCardUsage.fromJson(invalid), throwsFormatException);
  });
}
