import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/validated_paste_region.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focus;
  setUp(() {
    controller = TextEditingController(text: 'old recipient');
    focus = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focus.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpField(
    WidgetTester tester,
    Future<void> Function(String) onPaste,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValidatedPasteRegion(
            controller: controller,
            onPaste: onPaste,
            builder: (menu) => TextField(
              controller: controller,
              focusNode: focus,
              contextMenuBuilder: menu,
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
  }

  Future<void> keyboardPaste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  for (final accept in [true, false]) {
    testWidgets('keyboard paste validates selection before commit ($accept)', (
      tester,
    ) async {
      final decision = Completer<void>();
      String? candidate;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': 'new'} : null,
      );
      await pumpField(tester, (value) async {
        candidate = value;
        await decision.future;
        if (accept) controller.text = value;
      });
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await keyboardPaste(tester);
      expect(candidate, 'new recipient');
      expect(controller.text, 'old recipient');
      decision.complete();
      await tester.pump();
      expect(controller.text, accept ? 'new recipient' : 'old recipient');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final change in ['edit', 'edit-back', 'route', 'route-back']) {
    testWidgets('clipboard result is discarded after $change', (tester) async {
      final clipboard = Completer<Map<String, dynamic>>();
      final candidates = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? clipboard.future : null,
      );
      await pumpField(tester, (value) async {
        candidates.add(value);
      });
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 13,
      );
      await keyboardPaste(tester);
      if (change.startsWith('edit')) {
        final before = controller.value;
        controller.text = 'changed draft';
        if (change == 'edit-back') controller.value = before;
      } else {
        final context = tester.element(find.byType(TextField));
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Next')),
            ),
          ),
        );
      }
      await tester.pumpAndSettle();
      if (change == 'route-back') {
        Navigator.of(tester.element(find.text('Next'))).pop();
        await tester.pumpAndSettle();
      }
      clipboard.complete({'text': 'late recipient'});
      await tester.pumpAndSettle();
      expect(candidates, isEmpty);
      expect(
        controller.text,
        change == 'edit' ? 'changed draft' : 'old recipient',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('clipboard result is discarded when paste context changes', (
    tester,
  ) async {
    final clipboard = Completer<Map<String, dynamic>>();
    final candidates = <String>[];
    final inputContext = ValueNotifier<int>(0);
    addTearDown(inputContext.dispose);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? clipboard.future : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: inputContext,
            builder: (_, value, _) => ValidatedPasteRegion(
              controller: controller,
              pasteContext: value,
              onPaste: (candidate) async {
                candidates.add(candidate);
              },
              builder: (menu) => TextField(
                controller: controller,
                focusNode: focus,
                contextMenuBuilder: menu,
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await keyboardPaste(tester);
    inputContext.value++;
    await tester.pump();
    clipboard.complete({'text': 'obsolete recipient'});
    await tester.pumpAndSettle();
    expect(candidates, isEmpty);
    expect(controller.text, 'old recipient');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live context change discards clipboard before a rebuild', (
    tester,
  ) async {
    final clipboard = Completer<Map<String, dynamic>>();
    final candidates = <String>[];
    var inputContext = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? clipboard.future : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValidatedPasteRegion(
            controller: controller,
            pasteContext: inputContext,
            readPasteContext: () => inputContext,
            onPaste: (candidate) async {
              candidates.add(candidate);
            },
            builder: (menu) => TextField(
              controller: controller,
              focusNode: focus,
              contextMenuBuilder: menu,
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await keyboardPaste(tester);
    inputContext++;
    // No setState or frame: the widget still holds its old pasteContext value.
    clipboard.complete({'text': 'obsolete recipient'});
    await tester.pumpAndSettle();
    expect(candidates, isEmpty);
    expect(controller.text, 'old recipient');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('context menu paste uses validation and keeps rejected text', (
    tester,
  ) async {
    final candidates = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'bad recipient'}
          : call.method == 'Clipboard.hasStrings'
          ? {'value': true}
          : null,
    );
    await pumpField(tester, (value) async {
      candidates.add(value);
    });
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 13);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    await editable.clipboardStatus.update();
    editable.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste').last);
    await tester.pump();
    expect(candidates, ['bad recipient']);
    expect(controller.text, 'old recipient');
    await tester.pumpWidget(const SizedBox());
  });
}
