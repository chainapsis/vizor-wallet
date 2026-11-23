import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/address_line_text.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/features/swap/widgets/one_time_address_label.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

/// Registers the [ReviewInfoRow.trailing] and full-address action layout
/// tests, so the desktop and mobile lanes check the same cases.
void reviewInfoRowTrailingTests() {
  testWidgets('a long value beside a one-time address label never '
      'overflows at 320px and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => AppTheme(
          data: AppThemeData.light,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
        home: const Center(
          child: ReviewInfoRow(
            label: 'Refund to',
            value: '2.5 ZEC',
            leading: ReviewInfoIconCircle(iconName: AppIcons.wallet),
            bottomLeftText: r'≈ $123,456,789.00 USD',
            trailing: OneTimeAddressLabel(role: OneTimeAddressRole.refund),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The address label keeps room for its icon.
    expect(find.byType(OneTimeAddressLabel).hitTestable(), findsOneWidget);
  });

  const address = 'u19509151 ... d190591';
  Future<void> pumpAddressRow(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width + 40, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: Center(
          child: SizedBox(
            width: width,
            child: ReviewInfoRow(
              label: 'To',
              value: 'Mike',
              leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
              bottomLeftIconName: AppIcons.shieldKeyhole,
              bottomLeftText: address,
              trailingActionLabel: 'Full address',
              onTrailingAction: () {},
            ),
          ),
        ),
      ),
    );
  }

  final action = find.widgetWithText(AppButton, 'Full address');

  /// The row width the address and the action need on one line, measured
  /// with the lane's own text metrics.
  Future<({double addressEnd, double action})> measure(
    WidgetTester tester,
  ) async {
    await pumpAddressRow(tester, 2000);
    final rowLeft = tester.getTopLeft(find.byType(ReviewInfoRow)).dx;
    return (
      addressEnd: tester.getTopRight(find.text(address)).dx - rowLeft,
      action: tester.getSize(action).width,
    );
  }

  testWidgets('the full-address action stays beside an address that fits', (
    tester,
  ) async {
    final need = await measure(tester);
    await pumpAddressRow(tester, need.addressEnd + need.action + 4);

    expect(
      tester.getCenter(action).dy,
      moreOrLessEquals(tester.getCenter(find.text(address)).dy, epsilon: 1),
    );
    expect(
      tester.getTopRight(action).dx,
      moreOrLessEquals(tester.getTopRight(find.byType(ReviewInfoRow)).dx),
    );
  });

  testWidgets('the full-address action moves below an address that does '
      'not fit beside it, and the address stays whole', (tester) async {
    final need = await measure(tester);
    await pumpAddressRow(tester, need.addressEnd + need.action / 2);

    expect(tester.takeException(), isNull);
    final paragraph =
        tester.renderObject(find.text(address)) as RenderParagraph;
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      tester.getTopLeft(action).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text(address)).dy),
    );
    // Still at the end of the row, under where it sat.
    expect(
      tester.getTopRight(action).dx,
      moreOrLessEquals(tester.getTopRight(find.byType(ReviewInfoRow)).dx),
    );
  });

  testWidgets('a saved contact line keeps the address beside the action and '
      'moves the name to a line above', (tester) async {
    const line = AddressLine(
      before: 'To: ',
      label: 'Treasury',
      address: address,
    );
    Future<void> pumpContactRow(double width) async {
      tester.view.physicalSize = Size(width + 40, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          builder: (context, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
          home: Center(
            child: SizedBox(
              width: width,
              child: ReviewInfoRow(
                label: "You're receiving",
                value: '100.12 USDC',
                leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
                bottomLeftAddress: line,
                trailingActionLabel: 'Full address',
                onTrailingAction: () {},
              ),
            ),
          ),
        ),
      );
    }

    // Wide enough for the address beside the action, not the whole line.
    final need = await measure(tester);
    await pumpContactRow(need.addressEnd + need.action + 4);

    final shown = tester.widget<Text>(
      find.descendant(
        of: find.byType(AddressLineText),
        matching: find.byType(Text),
      ),
    );
    expect(shown.data, 'To: Treasury\n$address');
    final text = find.byType(AddressLineText);
    expect(
      tester.getTopLeft(action).dy,
      lessThan(tester.getBottomLeft(text).dy),
    );
    expect(
      tester.getTopRight(action).dx,
      moreOrLessEquals(tester.getTopRight(find.byType(ReviewInfoRow)).dx),
    );
  });
}
