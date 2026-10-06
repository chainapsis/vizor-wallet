import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_claim_account_sheet.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final size in [const Size(1080, 720), const Size(720, 520)]) {
    testWidgets('recipient dialog centers in the content pane at $size', (
      tester,
    ) async {
      await _openSheet(
        tester,
        size: size,
        accountCount: 12,
        withSidebar: true,
        onConfirm: (_) async {},
      );
      final pane = tester.getRect(find.byKey(const ValueKey('content_pane')));
      final modal = tester.getRect(
        find.byKey(const ValueKey('payment_link_claim_account_sheet')),
      );
      expect(modal.center.dx, closeTo(pane.center.dx, 0.01));
      expect(modal.center.dy, closeTo(pane.center.dy, 0.01));
      expect(modal.left, greaterThanOrEqualTo(pane.left));
      expect(modal.right, lessThanOrEqualTo(pane.right));
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Choose receiving account'), findsOneWidget);
    });
  }

  for (final size in [const Size(1080, 720), const Size(720, 520)]) {
    testWidgets('only accounts scroll at $size, with the Claim button fixed', (
      tester,
    ) async {
      String? confirmedAccount;
      await _openSheet(
        tester,
        size: size,
        accountCount: 12,
        onConfirm: (uuid) async => confirmedAccount = uuid,
      );
      final button = find.byKey(
        const ValueKey('payment_link_claim_account_confirm'),
      );
      final headingTop = tester.getTopLeft(
        find.text('Choose receiving account'),
      );
      final amountTop = tester.getTopLeft(find.text('4.45 ZEC'));
      final buttonTop = tester.getTopLeft(button);
      final list = find.byKey(const ValueKey('payment_link_claim_accounts'));
      final last = find.byKey(
        const ValueKey('payment_link_claim_account_account-11'),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getBottomRight(button).dy, lessThan(size.height));
      await tester.scrollUntilVisible(
        last,
        160,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Choose receiving account')),
        headingTop,
      );
      expect(tester.getTopLeft(find.text('4.45 ZEC')), amountTop);
      expect(tester.getTopLeft(button), buttonTop);
      await tester.tap(last);
      await tester.pump();
      expect(confirmedAccount, isNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(confirmedAccount, 'account-11');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'pending recipient confirmation blocks Close, scrim and repeat submit, then releases',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await _openSheet(
        tester,
        accountCount: 2,
        onConfirm: (_) async {
          calls++;
          await gate.future;
        },
      );
      final confirm = find.byKey(
        const ValueKey('payment_link_claim_account_confirm'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Preparing…'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_close')),
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Choose receiving account'), findsOneWidget);
      expect(calls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Choose receiving account'), findsNothing);
    },
  );

  testWidgets(
    'failed confirmation keeps the choice and allows another account to retry',
    (tester) async {
      final attempts = <String>[];
      await _openSheet(
        tester,
        accountCount: 2,
        onConfirm: (uuid) async {
          attempts.add(uuid);
          if (attempts.length == 1) throw StateError('Recipient unavailable');
        },
      );
      final confirm = find.byKey(
        const ValueKey('payment_link_claim_account_confirm'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.text(
          'Couldn’t prepare this gift. Try again or choose another account.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_account-1')),
      );
      await tester.pump();
      expect(find.text('Try again'), findsNothing);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(attempts, ['account-0', 'account-1']);
      expect(find.text('Choose receiving account'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openSheet(
  WidgetTester tester, {
  Size size = const Size(1080, 720),
  bool withSidebar = false,
  required int accountCount,
  required Future<void> Function(String) onConfirm,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.binding.setSurfaceSize(null);
  });
  final pane = Builder(
    key: const ValueKey('content_pane'),
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => showPaymentLinkClaimAccountSheet(
          context: context,
          amountZatoshi: BigInt.from(445000000),
          accounts: [
            for (var i = 0; i < accountCount; i++)
              AccountInfo(uuid: 'account-$i', name: 'Account $i', order: i),
          ],
          activeAccountUuid: 'account-0',
          onConfirm: onConfirm,
        ),
        child: const Text('Open'),
      ),
    ),
  );
  await tester.pumpWidget(
    AppTheme(
      data: AppThemeData.dark,
      child: MaterialApp(
        home: withSidebar
            ? AppDesktopShell(sidebar: const SizedBox(), pane: pane)
            : Scaffold(body: pane),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
