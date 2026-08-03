@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

void main() {
  testWidgets('mobile accounts menu hides the shortcut for Keystone', (
    tester,
  ) async {
    await _pumpMobileAccountsUseCase(tester, buildMobileAccountsUseCase);

    await tester.tap(
      find.byKey(const ValueKey('mobile_accounts_menu_preview-account-2')),
    );
    await tester.pumpAndSettle();

    expect(find.text('View secret phrase'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_accounts_menu_preview-account-3')),
    );
    await tester.pumpAndSettle();

    expect(find.text('View secret phrase'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_account_menu_card')))
          .width,
      208,
    );
    expect(
      find.ancestor(
        of: find.text('View secret phrase'),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('View secret phrase')).overflow,
      TextOverflow.ellipsis,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile account menu use cases distinguish software and '
      'Keystone accounts', (tester) async {
    await _pumpMobileAccountsUseCase(
      tester,
      buildMobileAccountsSoftwareMenuUseCase,
    );

    expect(find.text('View secret phrase'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpMobileAccountsUseCase(
      tester,
      buildMobileAccountsKeystoneMenuUseCase,
    );

    expect(find.text('View secret phrase'), findsNothing);
    expect(find.text('Copy address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpMobileAccountsUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      builder: (context, child) =>
          AppTheme(data: AppThemeData.light, child: child!),
      home: Builder(builder: builder),
    ),
  );
  await tester.pumpAndSettle();
}
