import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/widgets/one_time_address_label.dart';
import '../../../support/test_l10n.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

/// Registers the one-time address label tests, so the desktop and mobile
/// lanes check the same cases.
void oneTimeAddressLabelTests() {
  Future<void> pump(WidgetTester tester, Widget label) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: Scaffold(body: Center(child: label)),
    ),
  );

  final labels = {
    'review label': const OneTimeAddressLabel(role: OneTimeAddressRole.refund),
    'composer slot': const OneTimeAddressSlot(
      role: OneTimeAddressRole.refund,
      height: 40,
    ),
  };

  for (final MapEntry(key: name, value: label) in labels.entries) {
    for (final (keyName, key) in [
      ('Enter', LogicalKeyboardKey.enter),
      ('Space', LogicalKeyboardKey.space),
    ]) {
      testWidgets('$keyName opens the $name explanation', (tester) async {
        await pump(tester, label);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(
          find.text(OneTimeAddressRole.refund.explanation(testL10n)),
          findsOne,
        );
        await tester.pump(const Duration(seconds: 10));
      });
    }

    testWidgets('the $name semantic tap opens its explanation', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, label);
      final node = find.semantics.byAction(SemanticsAction.tap);
      expect(node, findsOne);
      tester.semantics.tap(node);
      await tester.pump();
      expect(
        find.text(OneTimeAddressRole.refund.explanation(testL10n)),
        findsOne,
      );
      await tester.pump(const Duration(seconds: 10));
      semantics.dispose();
    });
  }
}
