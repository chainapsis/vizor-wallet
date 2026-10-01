@Tags(['mobile'])
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';

void main() {
  testWidgets('mobile leading activity avatar uses the mobile asset size', (
    tester,
  ) async {
    await _pumpActivityFeed(tester, rows: [_row(title: 'Sent')]);

    final avatar = tester.getSize(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(avatar.width, AppAssetSizeMobile.size);
    expect(avatar.height, AppAssetSizeMobile.size);
  });

  testWidgets('mobile leading activity icon uses the mobile asset icon size', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      rows: [_row(title: 'Sent', leadingIconName: AppIcons.plane)],
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.plane &&
            widget.size == AppAssetSizeMobile.icon,
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile sub-line icon uses the medium icon token', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      rows: [
        _row(
          title: 'Sent',
          subtitle: 'Shielded',
          subtitleIconName: AppIcons.shieldKeyholeOutline,
        ),
      ],
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.shieldKeyholeOutline &&
            widget.size == AppIconSize.medium,
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile sub-line text uses the 16px label token', (tester) async {
    await _pumpActivityFeed(
      tester,
      rows: [_row(title: 'Sent', subtitle: 'Shielded')],
    );

    final subtitle = tester.widget<Text>(find.text('Shielded'));
    expect(subtitle.style?.fontSize, AppTypographyMobile.labelLarge.fontSize);
  });

  testWidgets('mobile activity card surface has no drop shadow', (
    tester,
  ) async {
    await _pumpActivityFeed(tester, rows: [_row(title: 'Sent')]);

    final card = tester.widget<DecoratedBox>(
      find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
          return false;
        }
        final decoration = widget.decoration as BoxDecoration;
        return decoration.color ==
                AppThemeData.light.colors.background.ground &&
            decoration.borderRadius == BorderRadius.circular(AppRadii.large);
      }).first,
    );
    final decoration = card.decoration as BoxDecoration;
    expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
  });

  testWidgets('long subtitles ellipsize instead of stacking the row', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      width: 460,
      rows: [
        _row(
          title: 'Paid',
          subtitle: 'from shielded ZEC · Ethereum',
          amountText: '-101.23 USDC',
        ),
      ],
    );

    expect(tester.getSize(find.byType(ActivityFeedRow)).height, 44);
    expect(
      tester.getTopLeft(find.text('-101.23 USDC')).dy,
      lessThan(tester.getBottomLeft(find.text('Paid')).dy),
    );
  });

  testWidgets('amounts that fit beside the first title word stay whole', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      width: 460,
      rows: [_row(title: 'Sent', amountText: '-123.456789 ZEC')],
    );

    expect(tester.getSize(find.byType(ActivityFeedRow)).height, 44);
    final amount = tester.renderObject<RenderParagraph>(
      find.text('-123.456789 ZEC'),
    );
    expect(amount.didExceedMaxLines, isFalse);
  });

  testWidgets('rows stack when the amount crowds out the first title word', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      width: 460,
      rows: [_row(title: 'Payment in progress', amountText: '-123.456789 ZEC')],
    );

    expect(
      tester.getTopLeft(find.text('-123.456789 ZEC')).dy,
      greaterThan(tester.getBottomLeft(find.text('Payment in progress')).dy),
    );
  });

  testWidgets('a wrapped status keeps its icon beside the text', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      width: 300,
      rows: [
        _row(
          title: 'Swapping...',
          amountText: '-1.234K USDT',
          statusText: 'Incomplete deposit',
          statusIconName: AppIcons.warning,
        ),
      ],
    );

    final status = tester.renderObject<RenderParagraph>(
      find.text('Incomplete deposit'),
    );
    final boxes = status.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 18),
    );
    expect(boxes.map((box) => box.top).toSet(), hasLength(2));
    expect(boxes.map((box) => box.left).reduce(math.min), lessThan(0.5));
  });

  test('mobile outgoing amount color matches the title accent', () {
    final colors = AppThemeData.light.colors;
    expect(outgoingAmountColor(colors), colors.text.accent);
  });
}

Future<void> _pumpActivityFeed(
  WidgetTester tester, {
  required List<ActivityRowData> rows,
  double width = 420,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: width,
            child: ActivityFeed(
              cardWidth: null,
              sections: [
                ActivityFeedSectionData(title: 'This week', rows: rows),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

ActivityRowData _row({
  required String title,
  String leadingIconName = AppIcons.plane,
  String? subtitle,
  String? subtitleIconName,
  String amountText = '1.00 ZEC',
  String statusText = 'Completed',
  String? statusIconName,
}) {
  return ActivityRowData(
    title: title,
    leadingIconName: leadingIconName,
    leadingBackgroundColor: const Color(0xFFE1E1E1),
    leadingIconColor: const Color(0xFF4D5252),
    subtitle: subtitle,
    subtitleIconName: subtitleIconName,
    amountText: amountText,
    statusText: statusText,
    statusIconName: statusIconName,
    timestampText: 'Today, 13:11',
  );
}
