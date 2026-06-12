import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/address_book_use_cases.dart';

void main() {
  testWidgets('open context menu keeps the Widgetbook AppTheme in Overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => AppTheme(
                data: AppThemeData.light,
                child: Builder(builder: buildAddressBookSolanaMenuUseCase),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit contact'), findsOneWidget);
  });

  testWidgets('remove contact modal use case renders in AppTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(builder: buildAddressBookRemoveContactModalUseCase),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Remove contact'), findsWidgets);
    expect(
      find.text('Mike will be removed from your contacts.'),
      findsOneWidget,
    );
  });

  testWidgets('network selector empty use case renders no-result state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(builder: buildAddressBookNetworkModalEmptyUseCase),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No networks found'), findsOneWidget);
  });
}
