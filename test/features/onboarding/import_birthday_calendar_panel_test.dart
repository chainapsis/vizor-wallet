import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_calendar_overlay.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

Widget _app({DateTime? initialMonth}) {
  return MaterialApp(
    localizationsDelegates:
        AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    home: Center(
      child: ImportBirthdayCalendarPanel(
        initialMonth: initialMonth ?? DateTime(2026, 7),
        selectedDate: null,
        firstDate: DateTime(2020, 1, 1),
        lastDate: DateTime(2026, 12, 31),
        onDateSelected: (_) {},
      ),
    ),
  );
}

Finder _navButton(String iconName) {
  return find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.name == iconName,
  );
}

void main() {
  // VZR-75: the panel must keep one fixed size while paging months and
  // switching between the day / month / year modes — a 5-row month
  // jumping to a 6-row month used to reflow the whole sheet.
  testWidgets('the panel height never changes across months and modes', (
    tester,
  ) async {
    // July 2026 lays out in 5 weeks; August 2026 needs 6.
    await tester.pumpWidget(_app(initialMonth: DateTime(2026, 7)));

    final panel = find.byType(ImportBirthdayCalendarPanel);
    final size = tester.getSize(panel);

    // Page into the 6-row month and back.
    await tester.tap(_navButton(AppIcons.chevronForward));
    await tester.pump();
    expect(find.text('August 2026'), findsOneWidget);
    expect(tester.getSize(panel), size);

    await tester.tap(_navButton(AppIcons.chevronBackward));
    await tester.pump();
    expect(find.text('July 2026'), findsOneWidget);
    expect(tester.getSize(panel), size);

    // Mode switches reuse the same box: day -> month -> year.
    await tester.tap(find.text('July 2026'));
    await tester.pump();
    expect(find.text('Jan'), findsOneWidget);
    expect(tester.getSize(panel), size);

    await tester.tap(find.text('2026'));
    await tester.pump();
    expect(find.text('2025'), findsOneWidget);
    expect(tester.getSize(panel), size);

    // Year paging keeps it stable too.
    await tester.tap(_navButton(AppIcons.chevronBackward));
    await tester.pump();
    expect(tester.getSize(panel), size);
  });

  testWidgets('the day grid always shows six weeks', (tester) async {
    // February 2026 starts on a Sunday and spans exactly 4 weeks — the
    // shortest possible layout still renders six rows of cells.
    await tester.pumpWidget(_app(initialMonth: DateTime(2026, 2)));

    final panel = find.byType(ImportBirthdayCalendarPanel);
    final shortMonthSize = tester.getSize(panel);

    await tester.tap(_navButton(AppIcons.chevronForward));
    await tester.pump();
    expect(find.text('March 2026'), findsOneWidget);
    expect(tester.getSize(panel), shortMonthSize);
  });
}
