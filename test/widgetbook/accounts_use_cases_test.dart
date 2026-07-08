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
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Remove account'), findsOneWidget);
  });

  testWidgets('accounts current menu use case renders account actions', (
    tester,
  ) async {
    await _pumpAccountsUseCase(tester, buildAccountsCurrentMenuUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsNothing);
    expect(find.text('Remove account'), findsOneWidget);
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

  testWidgets('utility screen use cases render about and legal pages', (
    tester,
  ) async {
    await _pumpAccountsUseCase(tester, buildAboutUtilityUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('About Vizor Wallet'), findsOneWidget);
    expect(find.text('Github'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);

    await _pumpAccountsUseCase(tester, buildTermsUtilityUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Terms of Usage'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);

    await _pumpAccountsUseCase(tester, buildPrivacyUtilityUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('mobile accounts use case renders the mobile screen', (
    tester,
  ) async {
    await _pumpMobileAccountsUseCase(tester, buildMobileAccountsUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_accounts_menu_preview-account-2')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsOneWidget);
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Remove account'), findsOneWidget);
  });

  testWidgets('mobile accounts menu opens the edit sheet', (tester) async {
    await _pumpMobileAccountsUseCase(tester, buildMobileAccountsUseCase);

    await tester.tap(
      find.byKey(const ValueKey('mobile_accounts_menu_preview-account-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_account_menu_edit')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Account name'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_account_edit_save')),
      findsOneWidget,
    );
  });

  testWidgets('mobile accounts menu opens the remove sheet', (tester) async {
    await _pumpMobileAccountsUseCase(tester, buildMobileAccountsUseCase);

    await tester.tap(
      find.byKey(const ValueKey('mobile_accounts_menu_preview-account-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_account_menu_remove')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining("can't be reverted"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_account_remove_confirm')),
      findsOneWidget,
    );
  });

  testWidgets('mobile accounts modal use cases render edit and remove states', (
    tester,
  ) async {
    await _pumpMobileAccountsUseCase(
      tester,
      buildMobileAccountsEditAccountUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Account name'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_account_edit_save')),
      findsOneWidget,
    );

    await _pumpMobileAccountsUseCase(
      tester,
      buildMobileAccountsRemoveAccountUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining("can't be reverted"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_account_remove_confirm')),
      findsOneWidget,
    );
  });

  testWidgets('mobile home use cases render target states', (tester) async {
    await _pumpMobileHomeUseCase(tester, buildMobileHomeDefaultUseCase);
    _expectNoFlutterException(tester);
    expect(find.text('Shielded balance'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);

    await _pumpMobileHomeUseCase(tester, buildMobileHomeNoBalanceUseCase);
    _expectNoFlutterException(tester);
    expect(find.text('Receive your first ZEC'), findsOneWidget);

    await _pumpMobileHomeUseCase(tester, buildMobileHomeImportingUseCase);
    _expectNoFlutterException(tester);
    expect(find.text('34%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_home_importing_background')),
      findsOneWidget,
    );
  });

  testWidgets('mobile home accounts modal use case opens the switcher sheet', (
    tester,
  ) async {
    await _pumpMobileHomeUseCase(tester, buildMobileHomeAccountsModalUseCase);

    _expectNoFlutterException(tester);
    expect(find.text('Other accounts'), findsOneWidget);
    expect(find.text('Manage accounts'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_accounts_add')), findsOneWidget);
  });
}

void _expectNoFlutterException(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception is FlutterError) {
    fail(exception.toStringDeep());
  }
  expect(exception, isNull);
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

Future<void> _pumpMobileHomeUseCase(
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
          AppTheme(data: AppThemeData.dark, child: child!),
      home: Builder(builder: builder),
    ),
  );
  await tester.pumpAndSettle();
}
