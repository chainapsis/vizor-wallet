import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_confidential_ui.dart';

Widget _mark({required bool on, required int reveal}) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  builder: (context, child) => AppTheme(data: AppThemeData.dark, child: child!),
  home: Center(
    child: SwapConfidentialIcon(on: on, reveal: reveal, labeled: on),
  ),
);

Color? _color(WidgetTester tester) =>
    tester.widget<AppIcon>(find.byType(AppIcon)).color;

void main() {
  test('a turn outside the settings plays at once, on and off', () {
    final counter = SwapConfidentialRevealCounter();
    expect(counter.changed(confidential: true, settingsOpen: false), isTrue);
    expect(counter.value, 1);
    expect(counter.changed(confidential: false, settingsOpen: false), isTrue);
    expect(counter.value, 2);
  });

  test('a turn inside the settings waits for them to close', () {
    for (final confidential in [true, false]) {
      final counter = SwapConfidentialRevealCounter();
      expect(
        counter.changed(confidential: confidential, settingsOpen: true),
        isFalse,
      );
      expect(counter.value, 0);
      expect(counter.settingsClosed(confidential: confidential), isTrue);
      expect(counter.value, 1);
      // Closing again with nothing pending plays nothing.
      expect(counter.settingsClosed(confidential: confidential), isFalse);
      expect(counter.value, 1);
    }
  });

  test('turning back before the settings close plays nothing', () {
    for (final first in [true, false]) {
      final counter = SwapConfidentialRevealCounter();
      counter.changed(confidential: first, settingsOpen: true);
      counter.changed(confidential: !first, settingsOpen: true);
      expect(counter.settingsClosed(confidential: !first), isFalse);
      expect(counter.value, 0);
    }
  });

  test('a pending turn the route no longer matches is dropped', () {
    final counter = SwapConfidentialRevealCounter();
    counter.changed(confidential: false, settingsOpen: true);
    expect(counter.settingsClosed(confidential: true), isFalse);
    expect(counter.value, 0);
  });

  testWidgets('a mark turned off while shown fades; one built later is still', (
    tester,
  ) async {
    final muted = AppThemeData.dark.colors.icon.muted;
    // Built after its turn off (a step or page returned to): no replay.
    await tester.pumpWidget(_mark(on: false, reveal: 2));
    expect(_color(tester), muted);

    // Turning on, then off while it is shown, drains the colour.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_mark(on: false, reveal: 0));
    await tester.pumpWidget(_mark(on: true, reveal: 1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_mark(on: false, reveal: 2));
    await tester.pump(kSwapConfidentialConcealDuration * 0.4);
    expect(_color(tester), isNot(muted));
    await tester.pumpAndSettle();
    expect(_color(tester), muted);

    // Turned off without a play (the count did not rise): still.
    await tester.pumpWidget(_mark(on: true, reveal: 3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_mark(on: false, reveal: 3));
    await tester.pump();
    expect(_color(tester), muted);
  });
}
