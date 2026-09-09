import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_content_view.dart';
import 'package:zcash_wallet/widgetbook/ledger_transfer_preview.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_amount_adjustment_prompt.dart';

import '../figma_compare/figma_compare_font_loader.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;
void main() {
  setUp(() async {
    await loadFigmaCompareFonts();
  });

  Future<void> mount(
    WidgetTester tester,
    LedgerTransferScenario scenario, {
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(
      _mobile ? const Size(393, 900) : const Size(1280, 900),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: AppTheme(
            data: dark ? AppThemeData.dark : AppThemeData.light,
            child: LedgerTransferPreview(scenario: scenario),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder reviewButton() => find.byKey(
    ValueKey(_mobile ? 'mobile_send_review_button' : 'send_review_button'),
  );

  Finder amountInput() => find.descendant(
    of: find.byKey(
      ValueKey(_mobile ? 'mobile_send_amount_input' : 'send_amount_field'),
    ),
    matching: find.byType(EditableText),
  );

  testWidgets('Review discloses the adjustment before changing the draft', (
    tester,
  ) async {
    await mount(tester, LedgerTransferScenario.send);
    final review = reviewButton();
    final reviewPosition = tester.getTopLeft(review);
    expect(find.text('Ledger requires a smaller transfer.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('send_amount_suggestion_guide')),
      findsNothing,
    );
    expect(tester.widget<AppButton>(review).onPressed, isNotNull);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.byType(SendAmountAdjustmentPrompt), findsOneWidget);
    expect(
      find.byKey(
        ValueKey(
          _mobile
              ? 'send_amount_adjustment_sheet'
              : 'send_amount_adjustment_dialog',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('2 ZEC'), findsOneWidget);
    expect(find.text('1.24 ZEC'), findsOneWidget);
    expect(find.byType(SendReviewContentView), findsNothing);
    expect(tester.widget<EditableText>(amountInput()).controller.text, '2.00');

    await tester.tap(
      find.byKey(const ValueKey('send_amount_adjustment_review')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SendAmountAdjustmentPrompt), findsNothing);
    expect(find.byType(SendReviewContentView), findsOneWidget);
    expect(find.text('1.24 ZEC'), findsOneWidget);
    expect(find.text('For dinner'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    GoRouter.of(tester.element(find.byType(SendReviewContentView))).pop();
    await tester.pumpAndSettle();
    expect(find.text('1.24'), findsOneWidget);
    expect(find.text('Ledger requires a smaller transfer.'), findsNothing);
    expect(tester.getTopLeft(review), reviewPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit amount preserves the draft and restores input focus', (
    tester,
  ) async {
    await mount(tester, LedgerTransferScenario.send);
    await tester.tap(amountInput());
    await tester.pumpAndSettle();
    await tester.tap(reviewButton());
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(amountInput()).focusNode.hasFocus,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('send_amount_adjustment_edit')));
    await tester.pumpAndSettle();
    expect(find.byType(SendAmountAdjustmentPrompt), findsNothing);
    expect(find.byType(SendReviewContentView), findsNothing);
    final field = tester.widget<EditableText>(amountInput());
    expect(field.controller.text, '2.00');
    expect(field.focusNode.hasFocus, isTrue);
    expect(tester.widget<AppButton>(reviewButton()).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dismissing the prompt leaves the amount intact and allows reopening',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, LedgerTransferScenario.send);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      try {
        await tester.tap(find.bySemanticsLabel('Close'));
      } finally {
        semantics.dispose();
      }
      await tester.pumpAndSettle();
      expect(find.text('2.00'), findsOneWidget);
      expect(find.byType(SendReviewContentView), findsNothing);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      expect(find.byType(SendAmountAdjustmentPrompt), findsOneWidget);
      // System back also dismisses the pane overlay without popping Send.
      await Navigator.of(
        tester.element(find.byType(SendAmountAdjustmentPrompt)),
      ).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('2.00'), findsOneWidget);
      expect(tester.widget<AppButton>(reviewButton()).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  if (!_mobile) {
    testWidgets('desktop adjustment is centered only in the content pane', (
      tester,
    ) async {
      await mount(tester, LedgerTransferScenario.send);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      for (final size in [const Size(1280, 900), const Size(1080, 720)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        final pane = tester.getRect(find.byType(AppDesktopPane));
        final sidebar = tester.getRect(find.byType(AppMainSidebar));
        final overlay = tester.getRect(
          find.byKey(const ValueKey('send_amount_adjustment_overlay')),
        );
        final card = tester.getRect(find.byType(AppModalCard));
        expect(overlay, pane);
        expect(overlay.overlaps(sidebar), isFalse);
        expect(card.center.dx, closeTo(pane.center.dx, 0.1));
        expect(card.center.dy, closeTo(pane.center.dy, 0.1));
        expect(pane.contains(card.topLeft), isTrue);
        expect(pane.contains(card.bottomRight), isTrue);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      }
      // The pane scrim dismisses the prompt and does not change the draft.
      final pane = tester.getRect(find.byType(AppDesktopPane));
      await tester.tapAt(pane.topLeft + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(SendAmountAdjustmentPrompt), findsNothing);
      expect(find.text('2.00'), findsOneWidget);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SendAmountAdjustmentPrompt), findsNothing);
      expect(find.text('2.00'), findsOneWidget);
      expect(tester.widget<AppButton>(reviewButton()).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving Send cancels the pending pane adjustment', (
      tester,
    ) async {
      await mount(tester, LedgerTransferScenario.send);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      expect(find.byType(SendAmountAdjustmentPrompt), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'feasible amounts skip the prompt and invalid amounts stay blocked',
    (tester) async {
      await mount(tester, LedgerTransferScenario.ready);
      expect(find.text('Ledger requires a smaller transfer.'), findsNothing);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      expect(find.byType(SendAmountAdjustmentPrompt), findsNothing);
      expect(find.byType(SendReviewContentView), findsOneWidget);
      GoRouter.of(tester.element(find.byType(SendReviewContentView))).pop();
      await tester.pumpAndSettle();
      await tester.enterText(amountInput(), '0');
      await tester.pumpAndSettle();
      expect(tester.widget<AppButton>(reviewButton()).onPressed, isNull);
      expect(find.byType(SendAmountAdjustmentPrompt), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the review prompt fits a small viewport and retains its actions',
    (tester) async {
      await mount(tester, LedgerTransferScenario.send);
      await tester.binding.setSurfaceSize(
        _mobile ? const Size(320, 640) : const Size(1080, 720),
      );
      await tester.pumpAndSettle();
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      final confirm = find.byKey(
        const ValueKey('send_amount_adjustment_review'),
      );
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(SendReviewContentView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  const dir = String.fromEnvironment('LEDGER_PREVIEW_CAPTURE_DIR');
  if (dir.isNotEmpty) {
    for (final dark in [false, true]) {
      testWidgets(
        'captures the review prompt flow in ${dark ? 'dark' : 'light'}',
        (tester) async {
          await mount(tester, LedgerTransferScenario.send, dark: dark);
          Future<void> capture(String state) => expectLater(
            find.byKey(const ValueKey('capture')),
            matchesGoldenFile(
              Uri.file('$dir/review-$state-${dark ? 'dark' : 'light'}.png'),
            ),
          );
          await capture('hint');
          await tester.tap(reviewButton());
          await tester.pumpAndSettle();
          await capture('prompt');
          await tester.tap(
            find.byKey(const ValueKey('send_amount_adjustment_review')),
          );
          await tester.pumpAndSettle();
          await capture('updated');
        },
      );
    }
  }
}
