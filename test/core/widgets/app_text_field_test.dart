import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_text_field.dart';

void main() {
  testWidgets('single-line padded input area wins over root unfocus', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var rootTapCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        includeRootUnfocus: true,
        onRootTap: () => rootTapCount += 1,
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
    expect(rootTapCount, isZero);
  });

  testWidgets('root unfocus still clears focus outside app text field', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var rootTapCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        includeRootUnfocus: true,
        onRootTap: () => rootTapCount += 1,
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

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(rootTapCount, 1);
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('message text does not use tooltip when it fits', (tester) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        child: SizedBox(
          width: 352,
          height: 86,
          child: AppTextField(label: 'Send to', messageText: 'Valid address'),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('truncated message text uses below-preferred tooltip', (
    tester,
  ) async {
    const message =
        'Use only English letters, numbers, and symbols before continuing.';

    await tester.pumpWidget(
      const _ThemedHarness(
        child: SizedBox(
          width: 128,
          height: 86,
          child: AppTextField(label: 'Password', messageText: message),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, message);
    expect(tooltip.preferBelow, isTrue);
  });

  testWidgets('truncated message tooltip anchors to icon and text row', (
    tester,
  ) async {
    const message =
        'Use only English letters, numbers, and symbols before continuing.';

    await tester.pumpWidget(
      const _ThemedHarness(
        child: SizedBox(
          width: 128,
          height: 86,
          child: AppTextField(
            label: 'Password',
            messageText: message,
            tone: AppTextFieldTone.destructive,
          ),
        ),
      ),
    );

    final tooltipTarget = find.descendant(
      of: find.byType(Tooltip),
      matching: find.byKey(
        const ValueKey('app-text-field-message-tooltip-target'),
      ),
    );
    final iconSlot = find.byKey(
      const ValueKey('app-text-field-message-icon-slot'),
    );

    expect(tooltipTarget, findsOneWidget);
    expect(iconSlot, findsOneWidget);

    final fieldRect = tester.getRect(find.byType(AppTextField));
    final targetRect = tester.getRect(tooltipTarget);
    final textRect = tester.getRect(find.text(message));

    expect(targetRect.left, moreOrLessEquals(fieldRect.left));
    expect(targetRect.width, moreOrLessEquals(fieldRect.width));
    expect(textRect.left, greaterThan(targetRect.left));
  });

  testWidgets('truncated message tooltip can show full message overlay', (
    tester,
  ) async {
    const message =
        'Use only English letters, numbers, and symbols before continuing.';

    await tester.pumpWidget(
      const _ThemedHarness(
        child: SizedBox(
          width: 128,
          height: 86,
          child: AppTextField(
            label: 'Password',
            messageText: message,
            tone: AppTextFieldTone.destructive,
          ),
        ),
      ),
    );

    final tooltipState = tester.state<TooltipState>(find.byType(Tooltip));
    expect(tooltipState.ensureTooltipVisible(), isTrue);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text(message), findsNWidgets(2));
  });

  testWidgets('truncated message tooltip does not block root unfocus', (
    tester,
  ) async {
    const message =
        'Use only English letters, numbers, and symbols before continuing.';
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var rootTapCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _ThemedHarness(
        includeRootUnfocus: true,
        onRootTap: () => rootTapCount += 1,
        child: SizedBox(
          width: 128,
          height: 86,
          child: AppTextField(
            label: 'Password',
            controller: controller,
            focusNode: focusNode,
            messageText: message,
            tone: AppTextFieldTone.destructive,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(tester.getRect(find.text(message)).center);
    await tester.pump();

    expect(rootTapCount, 1);
    expect(focusNode.hasFocus, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(
      tester
          .getRect(
            find.byKey(const ValueKey('app-text-field-message-icon-slot')),
          )
          .center,
    );
    await tester.pump();

    expect(rootTapCount, 2);
    expect(focusNode.hasFocus, isFalse);
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

  testWidgets('single-line hint labels the editable for screen readers', (
    tester,
  ) async {
    // The single-line path draws its own hint instead of the
    // InputDecorator's; MergeSemantics must fold that hint into the
    // editable's node so label-less fields (search inputs) stay named.
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 352,
                child: AppTextField(
                  label: 'Search',
                  showLabel: false,
                  controller: controller,
                  hintText: 'Search for label or network',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(find.byType(EditableText));
    expect(node.flagsCollection.isTextField, isTrue);
    expect(node.label, 'Search for label or network');

    // With text entered the hint disappears, matching the decorator's
    // empty-only hint semantics; the value carries the content instead.
    await tester.enterText(find.byType(EditableText), 'zec');
    await tester.pump();
    final filledNode = tester.getSemantics(find.byType(EditableText));
    expect(filledNode.label, isEmpty);
    expect(filledNode.value, 'zec');

    handle.dispose();
  });
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({
    required this.child,
    this.includeRootUnfocus = false,
    this.onRootTap,
  });

  final Widget child;
  final bool includeRootUnfocus;
  final VoidCallback? onRootTap;

  @override
  Widget build(BuildContext context) {
    final body = Center(child: child);

    return MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: includeRootUnfocus
              ? GestureDetector(
                  onTap: () {
                    onRootTap?.call();
                    final primary = FocusManager.instance.primaryFocus;
                    if (primary != null && primary is! FocusScopeNode) {
                      primary.unfocus();
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: body,
                )
              : body,
        ),
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
