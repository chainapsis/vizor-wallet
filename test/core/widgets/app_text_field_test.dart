import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';

void main() {
  testWidgets('single-line padded input area focuses on the first tap', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: SizedBox(
          width: 352,
          child: AppTextField(
            label: 'Send to',
            controller: controller,
            focusNode: focusNode,
            hintText: 'Zcash address',
            leading: const AppIcon(AppIcons.users),
            showClearButton: true,
          ),
        ),
      ),
    );

    final textFieldRect = tester.getRect(find.byType(TextField));

    // This lands in the styled field padding below the actual EditableText.
    // It used to be classified as "inside the TextField region", so the shell
    // skipped its own focus fallback while the TextField itself never saw it.
    await tester.tapAt(
      Offset(textFieldRect.center.dx, textFieldRect.bottom + 3),
    );
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('multiline clear button uses the Figma hit target', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Memo');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: _SizedTextArea(
          controller: controller,
          scrollController: scrollController,
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    final clearFinder = find.byKey(
      const ValueKey('app-text-field-multiline-clear-button'),
    );
    expect(clearFinder, findsOneWidget);
    expect(tester.getSize(clearFinder), const Size(40, 48));

    final fieldRect = tester.getRect(find.byType(AppTextField));
    final clearRect = tester.getRect(clearFinder);
    expect(clearRect.right, fieldRect.right);

    // Tap inside the 40px target but outside the centered 20px glyph.
    await tester.tapAt(Offset(clearRect.left + 2, clearRect.center.dy));
    await tester.pump();

    expect(controller.text, isEmpty);
  });

  testWidgets('multiline keeps the right gutter when clear button is hidden', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Memo');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: _SizedTextArea(
          controller: controller,
          scrollController: scrollController,
        ),
      ),
    );

    final clearSlotFinder = find.byKey(
      const ValueKey('app-text-field-multiline-clear-slot'),
    );
    expect(clearSlotFinder, findsOneWidget);
    expect(tester.getSize(clearSlotFinder), const Size(40, 48));
    expect(find.bySemanticsLabel('Clear text'), findsNothing);

    final fieldRect = tester.getRect(find.byType(AppTextField));
    final textFieldRect = tester.getRect(find.byType(TextField));
    expect(textFieldRect.right, lessThanOrEqualTo(fieldRect.right - 40));
  });

  testWidgets('multiline clear button works while hovered without focus', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Memo');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: _SizedTextArea(
          controller: controller,
          scrollController: scrollController,
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getRect(find.byType(TextField)).center);
    addTearDown(mouse.removePointer);
    await tester.pump();

    final clearFinder = find.byKey(
      const ValueKey('app-text-field-multiline-clear-button'),
    );
    expect(clearFinder, findsOneWidget);

    await tester.tapAt(tester.getRect(clearFinder).center);
    await tester.pump();

    expect(controller.text, isEmpty);
  });

  testWidgets('multiline close action can show without text', (tester) async {
    final controller = TextEditingController();
    final scrollController = ScrollController();
    var closed = false;
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: _SizedTextArea(
          controller: controller,
          scrollController: scrollController,
          clearButtonRequiresText: false,
          clearButtonSemanticLabel: 'Close message',
          onClear: () => closed = true,
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    final closeFinder = find.bySemanticsLabel('Close message');
    expect(closeFinder, findsOneWidget);

    await tester.tap(closeFinder);
    await tester.pump();

    expect(closed, isTrue);
  });

  testWidgets('multiline scrollbar sits on the field edge', (tester) async {
    final controller = TextEditingController(
      text: List.generate(40, (index) => 'Memo line $index').join('\n'),
    );
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: _SizedTextArea(
          controller: controller,
          scrollController: scrollController,
        ),
      ),
    );
    await tester.pump();

    final clearFinder = find.byKey(
      const ValueKey('app-text-field-multiline-clear-button'),
    );
    final scrollbarFinder = find.byKey(
      const ValueKey('app-text-field-multiline-scrollbar'),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(clearFinder, findsOneWidget);
    expect(scrollbarFinder, findsOneWidget);
    expect(tester.getSize(scrollbarFinder), const Size(12, 148));
    expect(
      find.descendant(
        of: find.byType(AppTextField),
        matching: find.byType(Scrollbar),
      ),
      findsNothing,
    );

    final fieldRect = tester.getRect(find.byType(AppTextField));
    final clearRect = tester.getRect(clearFinder);
    final scrollbarRect = tester.getRect(scrollbarFinder);

    expect(scrollbarRect.right, moreOrLessEquals(fieldRect.right - 1.5));
    expect(scrollbarRect.top, moreOrLessEquals(clearRect.top - 1.5));
  });

  testWidgets('multiline scrollbar thumb tracks content and offset', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: List.generate(40, (index) => 'Memo line $index').join('\n'),
    );
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        child: _SizedTextArea(
          controller: controller,
          scrollController: scrollController,
        ),
      ),
    );
    await tester.pump();

    final thumbFinder = find.byKey(
      const ValueKey('app-text-field-multiline-scrollbar-thumb'),
    );
    expect(thumbFinder, findsOneWidget);

    final thumbRectBefore = tester.getRect(thumbFinder);
    expect(thumbRectBefore.height, lessThanOrEqualTo(62));
    expect(thumbRectBefore.height, greaterThanOrEqualTo(24));

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();

    final thumbRectAfter = tester.getRect(thumbFinder);
    expect(thumbRectAfter.top, greaterThan(thumbRectBefore.top));
  });
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }
}

class _SizedTextArea extends StatelessWidget {
  const _SizedTextArea({
    required this.controller,
    required this.scrollController,
    this.clearButtonRequiresText = true,
    this.clearButtonSemanticLabel = 'Clear text',
    this.onClear,
  });

  final TextEditingController controller;
  final ScrollController scrollController;
  final bool clearButtonRequiresText;
  final String clearButtonSemanticLabel;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 352,
      child: AppTextField(
        label: 'Message',
        rightLabel: '-32/512',
        controller: controller,
        scrollController: scrollController,
        leading: const AppIcon(AppIcons.scroll),
        showClearButton: true,
        clearButtonRequiresText: clearButtonRequiresText,
        clearButtonSemanticLabel: clearButtonSemanticLabel,
        onClear: onClear,
        minLines: 6,
        maxLines: 6,
      ),
    );
  }
}
