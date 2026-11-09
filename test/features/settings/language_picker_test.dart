import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/widgets/language_picker.dart';

Widget _modal({
  AppLanguage current = AppLanguage.en,
  Future<void> Function(AppLanguage)? onUpdate,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: appSupportedLocales(preview: true),
    localizationsDelegates: appLocalizationsDelegates,
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: DesktopLanguageModal(
            current: current,
            available: AppLanguage.values,
            onCancel: () {},
            onUpdate: onUpdate ?? (_) async {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('lists each language by its own name, without System', (
    tester,
  ) async {
    await tester.pumpWidget(_modal());

    for (final language in AppLanguage.values) {
      expect(
        find.byKey(ValueKey('language_option_${language.tag}')),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('language_option_system')), findsNothing);
    expect(find.textContaining('System'), findsNothing);
  });

  testWidgets('a failed save keeps the modal open with an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _modal(onUpdate: (_) async => throw StateError('storage unavailable')),
    );

    await tester.tap(find.byKey(const ValueKey('language_option_zh')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('account_modal_action_button')));
    await tester.pump();

    expect(find.text("Couldn't update language."), findsOneWidget);
    expect(find.byKey(const ValueKey('language_option_zh')), findsOneWidget);
  });

  testWidgets('the picker speaks the current UI language', (tester) async {
    await tester.pumpWidget(_modal(locale: const Locale('zh')));

    expect(find.text('语言'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    // Language names stay in their own script whatever the UI language is.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);
  });
}
