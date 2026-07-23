@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

void main() {
  testWidgets('migration recovery preview completes without production IO', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: buildMobileIronwoodMigrationRecoveryRequiredUseCase,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration recovery required.'), findsOneWidget);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Rebuild migration?'), findsOneWidget);
    expect(
      find.textContaining(
        'rebuild the migration for only your remaining balance',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('outbox'), findsNothing);
    await tester.tap(find.text('Rebuild'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Migration recovery required.'), findsNothing);
    expect(find.text('Recover'), findsNothing);
  });
}
