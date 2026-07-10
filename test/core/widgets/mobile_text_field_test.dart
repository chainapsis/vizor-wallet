import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/mobile_text_field.dart';

void main() {
  testWidgets('shell tap outside the inner text field moves caret to end', (
    tester,
  ) async {
    const text = 't1zcashrecipientaddress';
    final controller = TextEditingController.fromValue(
      TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      ),
    );
    final focusNode = FocusNode();
    var rootTapCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        onRootTap: () => rootTapCount += 1,
        child: SizedBox(
          width: 320,
          child: MobileTextField(
            controller: controller,
            focusNode: focusNode,
            hintText: 'Search',
            leading: const SizedBox(width: 56, height: 60),
          ),
        ),
      ),
    );

    final shellRect = tester.getRect(find.byType(MobileTextField));
    await tester.tapAt(Offset(shellRect.left + 12, shellRect.center.dy));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, text.length);
    expect(rootTapCount, isZero);
  });

  testWidgets('trailing action keeps its tap handling', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var trailingTapCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: SizedBox(
          width: 320,
          child: MobileTextField(
            controller: controller,
            focusNode: focusNode,
            hintText: 'Search',
            trailing: GestureDetector(
              key: const ValueKey('mobile_text_field_trailing_action'),
              behavior: HitTestBehavior.opaque,
              onTap: () => trailingTapCount += 1,
              child: const SizedBox(width: 48, height: 60),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_text_field_trailing_action')),
    );
    await tester.pump();

    expect(trailingTapCount, 1);
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('disabled field ignores both shell and text input taps', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0xrecipient');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    Widget field({required bool enabled}) => _ThemedHarness(
      child: SizedBox(
        width: 320,
        child: MobileTextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
        ),
      ),
    );

    await tester.pumpWidget(field(enabled: true));
    await tester.tap(find.byType(MobileTextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.pumpWidget(field(enabled: false));
    await tester.pump();

    await tester.tap(find.byType(MobileTextField));
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(focusNode.hasFocus, isFalse);
    expect(controller.text, '0xrecipient');
    expect(tester.takeException(), isNull);
  });
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({required this.child, this.onRootTap});

  final Widget child;
  final VoidCallback? onRootTap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: GestureDetector(
            onTap: onRootTap,
            behavior: HitTestBehavior.translucent,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
