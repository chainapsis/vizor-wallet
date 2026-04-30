import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_table.dart';

void main() {
  testWidgets('pagination keeps tab traversal after focused page is selected', (
    tester,
  ) async {
    var currentPage = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: StatefulBuilder(
            builder: (context, setState) {
              return ActivityTablePagination(
                currentPage: currentPage,
                totalPages: 3,
                onPageChanged: (page) {
                  setState(() {
                    currentPage = page;
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusContainsText('2'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(currentPage, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusContainsText('3'), isTrue);
  });

  testWidgets('pagination can be pinned to the bottom of full-height table', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(768, 500));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: SizedBox(
            width: 768,
            height: 500,
            child: ActivityTable(
              rows: [for (var i = 0; i < 6; i++) _row('Sent $i')],
              showPagination: true,
              pinPaginationToBottom: true,
              currentPage: 1,
              totalPages: 10,
            ),
          ),
        ),
      ),
    );

    final selectedPageShell = find.ancestor(
      of: find.text('1'),
      matching: find.byType(AnimatedContainer),
    );

    expect(selectedPageShell, findsOneWidget);
    expect(
      tester.getTopLeft(selectedPageShell).dy,
      moreOrLessEquals(464, epsilon: 0.1),
    );
  });

  testWidgets('pagination is hidden when there is only one page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: ActivityTable(
            rows: [_row('Sent')],
            showPagination: true,
            currentPage: 1,
            totalPages: 1,
          ),
        ),
      ),
    );

    expect(find.byType(ActivityTablePagination), findsNothing);
  });

  testWidgets(
    'headers render without sort indicators while sorting is disabled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(768, 240));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: const SizedBox(width: 752, child: ActivityTable(rows: [])),
          ),
        ),
      );

      final arrowFinder = find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.arrowDown,
      );

      expect(arrowFinder, findsNothing);

      final mutedColor = AppThemeData.light.colors.text.muted;
      for (final label in ['Tx Type', 'Amount', 'Status', 'Time Stamp']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style?.color, mutedColor);
      }
    },
  );
}

ActivityRowData _row(String title) {
  return ActivityRowData(
    title: title,
    leadingIconName: AppIcons.plane,
    leadingBackgroundColor: const Color(0xFFE1E1E1),
    leadingIconColor: const Color(0xFF4D5252),
    subtitle: 'Shielded',
    subtitleIconName: AppIcons.shieldKeyholeOutline,
    amountText: '-1.00 ZEC',
    statusText: 'Completed',
    timestampText: 'Apr, 25 10:25',
  );
}

bool _primaryFocusContainsText(String value) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;

  var found = false;
  void visit(Element element) {
    if (found) return;
    final widget = element.widget;
    if (widget is Text && widget.data == value) {
      found = true;
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return found;
}
