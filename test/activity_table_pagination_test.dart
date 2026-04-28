import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
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
