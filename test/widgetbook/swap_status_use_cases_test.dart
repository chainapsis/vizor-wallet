import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/swap_use_cases.dart';

void main() {
  testWidgets('swap status use case switches between tabs and detail rows', (
    tester,
  ) async {
    await _pumpSwapUseCase(tester, buildSwapStatusIncompleteDepositUseCase);

    expect(tester.takeException(), isNull);

    // The redesigned details tab renders all rows directly in the detail card,
    // with no More/Less expansion stage.
    expect(
      find.byKey(const ValueKey('swap_status_detail_rows')),
      findsOneWidget,
    );
    expect(find.text('Deposit USDC to'), findsOneWidget);
    expect(find.text('Refund fee'), findsOneWidget);
    expect(find.text('More details'), findsNothing);
    expect(find.text('Less details'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_status_tab_progress')));
    await tester.pump();

    expect(find.byKey(const ValueKey('swap_progress_route')), findsOneWidget);
    expect(find.byKey(const ValueKey('swap_status_detail_rows')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_status_tab_details')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_status_detail_rows')),
      findsOneWidget,
    );
    expect(find.text('Refund fee'), findsOneWidget);
  });
}

Future<void> _pumpSwapUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: 1080,
            height: 720,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
