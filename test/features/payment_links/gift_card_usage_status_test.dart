import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_tracking_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/gift_card_usage_status.dart';

void main() {
  testWidgets('only the failed card displays a card-specific update error', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        giftCardUsageProvider(
          'bad',
        ).overrideWith((ref) async => const GiftCardUsage()),
        giftCardUsageProvider(
          'good',
        ).overrideWith((ref) async => const GiftCardUsage()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: const Scaffold(
              body: Column(
                children: [
                  GiftCardUsageStatusView(key: ValueKey('bad'), address: 'bad'),
                  GiftCardUsageStatusView(
                    key: ValueKey('good'),
                    address: 'good',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final notifier = container.read(giftCardTrackingStateProvider.notifier);
    final failures = {'bad'};
    notifier.update(false, false, failures);
    failures.clear(); // Published state must not share a mutable caller set.
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bad')),
        matching: find.textContaining('Update failed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('good')),
        matching: find.textContaining('Update failed'),
      ),
      findsNothing,
    );
    notifier.update(false, true);
    await tester.pump();
    expect(find.textContaining('Update failed'), findsNWidgets(2));
    notifier.update(false, false);
    await tester.pump();
    expect(find.textContaining('Update failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'shows cached use independently of update errors and refreshes reactively',
    (tester) async {
      var usage = GiftCardUsage(
        status: GiftCardUsageStatus.unused,
        checkedAt: DateTime.utc(2026),
      );
      final container = ProviderContainer(
        overrides: [
          giftCardUsageProvider('card').overrideWith((ref) async => usage),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: const Scaffold(
                body: GiftCardUsageStatusView(
                  address: 'card',
                  showCheckedAt: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Card use: Unused'), findsOneWidget);
      container
          .read(giftCardTrackingStateProvider.notifier)
          .update(false, true);
      await tester.pump();
      expect(find.text('Card use: Unused · Update failed'), findsOneWidget);
      usage = GiftCardUsage(
        status: GiftCardUsageStatus.used,
        checkedAt: DateTime.utc(2026),
        cleaned: true,
      );
      container.invalidate(giftCardUsageProvider('card'));
      await tester.pumpAndSettle();
      expect(find.text('Card use: Used'), findsOneWidget);
      expect(find.textContaining('Last checked:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
