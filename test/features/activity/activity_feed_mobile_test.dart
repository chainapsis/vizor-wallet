@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

void main() {
  testWidgets('mobile leading activity avatar is a 44px circle', (
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
    expect(avatar, const Size.square(44));
  });

  testWidgets('mobile leading activity icon is a 20px glyph', (tester) async {
    await _pumpActivityFeed(
      tester,
      rows: [_row(title: 'Sent', leadingIconName: AppIcons.plane)],
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.plane &&
            widget.size == 20,
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile sub-line shows the filled shield at the medium size', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      rows: [
        _row(
          title: 'Sent',
          subtitle: 'Shielded',
          subtitleIconName: AppIcons.shieldKeyhole,
        ),
      ],
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.shieldKeyhole &&
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

  testWidgets('mobile activity rows sit on the page with no card', (
    tester,
  ) async {
    await _pumpActivityFeed(tester, rows: [_row(title: 'Sent')]);

    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
          return false;
        }
        final decoration = widget.decoration as BoxDecoration;
        return decoration.color ==
                AppThemeData.light.colors.background.ground &&
            decoration.borderRadius == BorderRadius.circular(AppRadii.large);
      }),
      findsNothing,
    );
  });

  test('mobile outgoing amount color matches the title accent', () {
    final colors = AppThemeData.light.colors;
    expect(outgoingAmountColor(colors), colors.text.accent);
  });
}

Future<void> _pumpActivityFeed(
  WidgetTester tester, {
  required List<ActivityRowData> rows,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: 420,
            child: ActivityFeed(
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
}) {
  return ActivityRowData(
    title: title,
    leadingIconName: leadingIconName,
    leadingBackgroundColor: const Color(0xFFE1E1E1),
    leadingIconColor: const Color(0xFF4D5252),
    subtitle: subtitle,
    subtitleIconName: subtitleIconName,
    amountText: '1.00 $kZcashDefaultCurrencyTicker',
    statusText: 'Completed',
    statusIsRoutine: true,
    timestampText: 'Today, 13:11',
  );
}
