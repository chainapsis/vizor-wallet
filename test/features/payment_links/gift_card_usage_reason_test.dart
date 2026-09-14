import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';

void main() {
  test('legacy unknown records do not imply unconfirmed funding', () {
    final legacy = const GiftCardUsage().toJson()..remove('reason');
    final usage = GiftCardUsage.fromJson(legacy);
    expect(usage.reason, isNull);
    expect(usage.label, 'Usage not verified');
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
            ? 'Awaiting confirmation'
            : 'Usage not verified',
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
