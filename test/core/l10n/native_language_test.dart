import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/native_language.dart';

void main() {
  Widget app({
    required Locale? locale,
    required List<AppLanguage> languages,
    required List<String> sent,
  }) => MaterialApp(
    locale: locale,
    supportedLocales: [for (final language in languages) language.locale],
    localizationsDelegates: appLocalizationsDelegates,
    builder: (context, child) =>
        NativeLanguageSync(send: (tag) async => sent.add(tag), child: child!),
    home: const SizedBox(),
  );

  testWidgets('sends the shown language once and again when it changes', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      app(locale: null, languages: AppLanguage.values, sent: sent),
    );
    expect(sent, ['en']);

    await tester.pumpWidget(
      app(
        locale: const Locale('ko'),
        languages: AppLanguage.values,
        sent: sent,
      ),
    );
    await tester.pumpAndSettle();
    expect(sent, ['en', 'ko']);

    await tester.pumpWidget(
      app(
        locale: const Locale('ko'),
        languages: AppLanguage.values,
        sent: sent,
      ),
    );
    await tester.pumpAndSettle();
    expect(sent, ['en', 'ko']);
  });

  testWidgets('sends English when the build offers English only', (
    tester,
  ) async {
    final sent = <String>[];
    tester.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      app(locale: null, languages: const [AppLanguage.en], sent: sent),
    );
    expect(sent, ['en']);
  });

  testWidgets('follows the device language when the build offers it', (
    tester,
  ) async {
    final sent = <String>[];
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(
      app(locale: null, languages: AppLanguage.values, sent: sent),
    );
    expect(sent, ['zh']);
  });
}
