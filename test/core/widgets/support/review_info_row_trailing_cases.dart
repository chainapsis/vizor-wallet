import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/features/swap/widgets/one_time_address_label.dart';

/// Registers the [ReviewInfoRow.trailing] layout tests, so the desktop and
/// mobile lanes check the same cases.
void reviewInfoRowTrailingTests() {
  testWidgets('a long value beside a one-time address label never '
      'overflows at 320px and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
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
}
