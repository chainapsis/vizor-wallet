import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/primitives.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/review_buttons_stack.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  group('ReviewInfoRow', () {
    testWidgets('renders label, headline value, badge, and ghost action', (
      tester,
    ) async {
      var actionTaps = 0;
      await _pump(
        tester,
        ReviewInfoRow(
          label: 'To',
          value: 'u195091 ... 190591',
          leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
          bottomLeftIconName: AppIcons.shieldKeyhole,
          bottomLeftText: 'Shielded',
          trailingActionLabel: 'Show full address',
          onTrailingAction: () => actionTaps++,
        ),
      );

      expect(
        tester.getSize(find.byType(ReviewInfoRow)).height,
        ReviewInfoRow.height,
      );

      final valueText = tester.widget<Text>(find.text('u195091 ... 190591'));
      expect(valueText.style?.fontFamily, 'Young Serif');
      expect(valueText.style?.fontSize, 32);
      expect(valueText.style?.decoration, isNull);
      expect(valueText.style?.color, AppThemeData.light.colors.text.accent);

      expect(find.text('To'), findsOneWidget);
      expect(find.text('Shielded'), findsOneWidget);
      final action = find.widgetWithText(AppButton, 'Show full address');
      final actionButton = tester.widget<AppButton>(action);
      expect(actionButton.size, AppButtonSize.small);
      expect(actionButton.variant, AppButtonVariant.ghost);
      expect(actionButton.iconGap, 0);
      expect(tester.getSize(action).height, 24);
      expect(actionButton.child, isA<Padding>());
      expect(
        (actionButton.child as Padding).padding,
        const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      );

      await tester.tap(find.text('Show full address'));
      await tester.pump();
      expect(actionTaps, 1);
    });

    testWidgets('strikes through the value in the failed variant', (
      tester,
    ) async {
      await _pump(
        tester,
        const ReviewInfoRow(
          label: 'To',
          value: 'u195091 ... 190591',
          leading: ReviewInfoIconCircle(iconName: AppIcons.wallet),
          struckThrough: true,
        ),
      );

      final valueText = tester.widget<Text>(find.text('u195091 ... 190591'));
      expect(valueText.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('omits the ghost action when no label is provided', (
      tester,
    ) async {
      await _pump(
        tester,
        const ReviewInfoRow(
          label: 'Amount',
          value: '123.12 ZEC',
          leading: ReviewInfoIconCircle(iconName: AppIcons.wallet),
          bottomLeftText: r'$250.12',
        ),
      );

      expect(find.byType(AppButton), findsNothing);
      expect(find.text(r'$250.12'), findsOneWidget);
    });
  });

  group('ReviewListRow', () {
    testWidgets('renders label/value with color tokens and icons', (
      tester,
    ) async {
      final positive = AppThemeData.light.colors.text.positiveStrong;
      await _pump(
        tester,
        ReviewListRow(
          label: 'Status',
          value: 'Completed',
          valueColor: positive,
          leadingIconName: AppIcons.checkCircle,
        ),
      );

      expect(
        tester.getSize(find.byType(ReviewListRow)).height,
        ReviewListRow.height,
      );
      final valueText = tester.widget<Text>(find.text('Completed'));
      expect(valueText.style?.color, positive);
      final labelText = tester.widget<Text>(find.text('Status'));
      expect(labelText.style?.color, AppThemeData.light.colors.text.secondary);
      final icon = tester.widget<AppIcon>(find.byType(AppIcon));
      expect(icon.name, AppIcons.checkCircle);
      expect(icon.color, positive);
    });

    testWidgets('value cluster tap fires onPressed', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        ReviewListRow(
          label: 'Tx ID',
          value: '0123123124512512',
          trailingIconName: AppIcons.arrowTopRight,
          onPressed: () => taps++,
        ),
      );

      await tester.tap(find.text('0123123124512512'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('ReviewWrapCard', () {
    testWidgets('uses the theme ground surface and 24px radius by default', (
      tester,
    ) async {
      await _pump(
        tester,
        const ReviewWrapCard(
          children: [
            ReviewListRow(label: 'Message', value: 'Hello'),
            ReviewWrapDivider(),
            ReviewListRow(label: 'Tx fee', value: '0.012 ZEC'),
          ],
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ReviewWrapCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppThemeData.light.colors.background.ground);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadii.large));
      expect(find.byType(ReviewWrapDivider), findsOneWidget);
    });

    testWidgets('surfaceColor pins the failed card dark in light theme', (
      tester,
    ) async {
      await _pump(
        tester,
        const ReviewWrapCard(
          surfaceColor: Primitives.p50Dark,
          children: [ReviewListRow(label: 'Status', value: 'Failed')],
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ReviewWrapCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, Primitives.p50Dark);
      expect(decoration.color, const Color(0xFF1B1F1F));
    });
  });

  group('ReviewButtonsStack', () {
    testWidgets('stacks a 44px primary over a ghost secondary', (tester) async {
      var confirmed = 0;
      var cancelled = 0;
      await _pump(
        tester,
        ReviewButtonsStack(
          primaryLabel: 'Confirm & send',
          primaryLeadingIconName: AppIcons.plane,
          onPrimaryPressed: () => confirmed++,
          secondaryLabel: 'Cancel',
          onSecondaryPressed: () => cancelled++,
        ),
      );

      final buttons = tester
          .widgetList<AppButton>(find.byType(AppButton))
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons[0].variant, AppButtonVariant.primary);
      expect(buttons[0].size, AppButtonSize.large);
      expect(buttons[1].variant, AppButtonVariant.ghost);

      final primaryFinder = find.widgetWithText(AppButton, 'Confirm & send');
      expect(tester.getSize(primaryFinder).height, 44);
      expect(tester.getSize(primaryFinder).width, greaterThanOrEqualTo(196));

      await tester.tap(primaryFinder);
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pump();
      expect(confirmed, 1);
      expect(cancelled, 1);
    });
  });

  group('AppButton mediumLarge', () {
    testWidgets('renders the 36px modal CTA height', (tester) async {
      await _pump(
        tester,
        AppButton(
          onPressed: () {},
          size: AppButtonSize.mediumLarge,
          child: const Text('Add to contacts'),
        ),
      );

      expect(
        tester
            .getSize(find.widgetWithText(AppButton, 'Add to contacts'))
            .height,
        36,
      );
    });
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: AppWindowSizing.contentAreaMaxWidth,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
