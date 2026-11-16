import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';
import 'package:zcash_wallet/src/core/zcash/spendable_wait.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/send/widgets/spendable_wait_breakdown.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/spendable_wait_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

final _wait = SpendableWait(
  availableNow: BigInt.from(100000000),
  changeWaiting: BigInt.from(120000000),
  receivedWaiting: BigInt.from(130000000),
  changeWait: const AvailableIn.minutes(1, 2),
  receivedWait: const AvailableIn.minutes(1, 3),
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  home: AppTheme(
    data: AppThemeData.light,
    child: Center(child: SizedBox(width: 360, child: child)),
  ),
);

void main() {
  testWidgets('lists what is spendable, each wait and the total', (
    tester,
  ) async {
    await tester.pumpWidget(_app(SpendableWaitBreakdown(wait: _wait)));

    expect(find.text('Available now'), findsOneWidget);
    expect(find.text('1 ZEC'), findsOneWidget);
    expect(find.text('Finishing your last payment'), findsOneWidget);
    expect(find.text('Available in 1–2 min'), findsOneWidget);
    expect(find.text('+1.2 ZEC'), findsOneWidget);
    expect(find.text('Just received'), findsOneWidget);
    expect(find.text('Available in 1–3 min'), findsOneWidget);
    expect(find.text('+1.3 ZEC'), findsOneWidget);
    expect(find.text('3.5 ZEC'), findsOneWidget);
  });

  testWidgets('privacy mode masks every amount', (tester) async {
    await tester.pumpWidget(
      _app(SpendableWaitBreakdown(wait: _wait, privacyModeEnabled: true)),
    );

    for (final amount in ['1 ZEC', '+1.2 ZEC', '+1.3 ZEC', '3.5 ZEC']) {
      expect(find.text(amount), findsNothing);
    }
    expect(find.textContaining('1.2'), findsNothing);
    expect(find.textContaining('1.3'), findsNothing);
    expect(find.textContaining('3.5'), findsNothing);
    expect(find.text('Available in 1–3 min'), findsOneWidget);
  });

  for (final privacy in [false, true]) {
    testWidgets('the desktop link ${privacy ? 'masks' : 'shows'} the spendable '
        'amount and opens the popover', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spendableWaitProvider.overrideWith((ref, accountUuid) => _wait),
            privacyModeProvider.overrideWith(() => _FixedPrivacy(privacy)),
          ],
          child: _app(
            const Align(
              alignment: Alignment.topLeft,
              child: SendAvailableNowLink(accountUuid: 'account-1'),
            ),
          ),
        ),
      );

      expect(
        find.text(privacy ? '****** ZEC available now' : '1 ZEC available now'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('send_available_now_link')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('send_available_now_popover')),
        findsOneWidget,
      );
      expect(find.text('+1.3 ZEC'), privacy ? findsNothing : findsOneWidget);
      expect(
        find.textContaining('3.5'),
        privacy ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets('a confirming receipt row says when it is available', (
    tester,
  ) async {
    const clock = (
      tipHeight: 1000,
      spacing: BlockSpacing(
        preNu7BlockSeconds: 75,
        nu7BlockSeconds: 25,
        nu7ActivationHeight: 1,
      ),
      catchingUp: false,
    );
    late ActivityRowData waiting;
    late ActivityRowData withoutClock;
    late ActivityRowData spendable;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            waiting = buildTransactionActivityRow(
              context: context,
              transaction: _received(minedHeight: 1000),
              spendableWaitClock: clock,
            );
            withoutClock = buildTransactionActivityRow(
              context: context,
              transaction: _received(minedHeight: 1000),
            );
            spendable = buildTransactionActivityRow(
              context: context,
              transaction: _received(minedHeight: 990),
              spendableWaitClock: clock,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(waiting.title, 'Received');
    expect(waiting.subtitle, 'Available in 1–3 min');
    expect(withoutClock.subtitle, isNot(contains('Available')));
    expect(spendable.subtitle, withoutClock.subtitle);
  });
}

class _FixedPrivacy extends PrivacyModeNotifier {
  _FixedPrivacy(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;
}

rust_sync.TransactionInfo _received({required int minedHeight}) {
  return rust_sync.TransactionInfo(
    txidHex: 'received-$minedHeight',
    minedHeight: BigInt.from(minedHeight),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    feeState: rust_sync.TransactionFeeState.notApplicable,
    detailsComplete: true,
    provisional: false,
    amountIncludesFee: false,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.from(130000000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
