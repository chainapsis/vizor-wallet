import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';

import '../../support/localized_test_scope.dart';

void main() {
  testWidgets('context.l10n reads the nearest app localizations', (
    tester,
  ) async {
    late String label;
    await tester.pumpWidget(
      LocalizedTestScope(
        locale: const Locale('zh'),
        child: Builder(
          builder: (context) {
            label = context.l10n.settingsLanguageLabel;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(label, '语言');
  });

  testWidgets('context.l10n names the fix when localizations are missing', (
    tester,
  ) async {
    Object? error;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            try {
              context.l10n;
            } catch (e) {
              error = e;
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(error, isA<FlutterError>());
    expect('$error', contains('appLocalizationsDelegates'));
    expect('$error', contains('LocalizedTestScope'));
  });
}
