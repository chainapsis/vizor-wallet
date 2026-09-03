import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/donation_use_cases.dart';

void main() {
  testWidgets('donation status use case matches the route back target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(builder: buildDonationStatusInProgressUseCase),
        ),
      ),
    );
    await tester.pump();

    final toolbar = find.byType(AppPaneToolbar);
    expect(
      find.descendant(of: toolbar, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: toolbar, matching: find.text('Send')),
      findsNothing,
    );
  });
}
