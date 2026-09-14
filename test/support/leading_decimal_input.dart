import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the platform editing channel, including the cursor after the
/// formatter inserts a zero. The next digit is inserted at that actual cursor.
Future<void> expectLeadingDecimalInput(
  WidgetTester tester,
  Finder field, {
  VoidCallback? onIncompleteAmount,
}) async {
  for (final separator in ['.', ',']) {
    await tester.enterText(field, '');
    await tester.enterText(field, separator);
    await tester.pump();
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final controller = tester.widget<EditableText>(editable).controller;
    expect(controller.text, '0.');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    onIncompleteAmount?.call();

    final value = controller.value;
    final offset = value.selection.extentOffset;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(offset, offset, '5'),
        selection: TextSelection.collapsed(offset: offset + 1),
      ),
    );
    // Allow asynchronous fee validation and any resulting rebuild to finish.
    await tester.pumpAndSettle();
    expect(controller.text, '0.5');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(tester.takeException(), isNull);
  }
}
