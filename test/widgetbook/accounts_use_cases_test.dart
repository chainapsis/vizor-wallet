import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

void main() {
  testWidgets('accounts other menu use case renders account actions', (
    tester,
  ) async {
    await _pumpAccountsUseCase(tester, buildAccountsOtherMenuUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsOneWidget);
    expect(find.text('Edit name'), findsOneWidget);
    expect(find.text('Change picture'), findsOneWidget);
    expect(find.text('Remove account'), findsOneWidget);
  });

  testWidgets('accounts current menu use case renders edit actions and copy', (
    tester,
  ) async {
    await _pumpAccountsUseCase(tester, buildAccountsCurrentMenuUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Edit name'), findsOneWidget);
    expect(find.text('Change picture'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsNothing);
    expect(find.text('Remove account'), findsNothing);
  });

  testWidgets('accounts modal use cases render each modal state', (
    tester,
  ) async {
    await _pumpAccountsUseCase(tester, buildAccountsEditAccountUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Account name'), findsWidgets);

    await _pumpAccountsUseCase(tester, buildAccountsProfilePictureUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Select profile picture'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('profile_picture_option_');
      }),
      findsNWidgets(15),
    );

    await _pumpAccountsUseCase(tester, buildAccountsRemoveUseCase);
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Are you sure you want to remove'),
      findsOneWidget,
    );
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('accounts many use case renders scrollable account set', (
    tester,
  ) async {
    await _pumpAccountsUseCase(tester, buildAccountsManyUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Primary Vault'), findsWidgets);
    expect(find.text('Account 20'), findsOneWidget);
  });
}

Future<void> _pumpAccountsUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = const Size(1512, 982);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Builder(
        builder: (context) => MediaQuery(
          // The previewed sidebar renders the syncing state, whose shimmer +
          // breathing glow animate forever; disable animations so
          // pumpAndSettle can settle (size/scale preserved via copyWith).
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AppTheme(
            data: AppThemeData.light,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
