@Tags(['mobile'])
library;

import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/sync_keep_awake_interaction_listener.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';

void main() {
  testWidgets(
    'platform semantics actions refresh activity without consuming them',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      Widget app() => _interactionApp(container, onTap: () => taps++);
      await tester.pumpWidget(app());
      var revision = container.read(syncKeepAwakeInteractionProvider).revision;
      final node = tester.getSemantics(
        find.byKey(const ValueKey('action_target')),
      );
      void send(SemanticsAction type, {int? nodeId, int? viewId}) {
        tester.binding.platformDispatcher.onSemanticsActionEvent!(
          SemanticsActionEvent(
            type: type,
            viewId: viewId ?? tester.view.viewId,
            nodeId: nodeId ?? node.id,
          ),
        );
      }

      send(SemanticsAction.tap);
      await tester.pump();
      expect(taps, 1);
      expect(
        container.read(syncKeepAwakeInteractionProvider).revision,
        ++revision,
      );
      // Rebuilding must not register a second global listener.
      await tester.pumpWidget(app());
      send(SemanticsAction.tap);
      await tester.pump();
      expect(taps, 2);
      expect(
        container.read(syncKeepAwakeInteractionProvider).revision,
        ++revision,
      );
      for (final action in [
        SemanticsAction.didGainAccessibilityFocus,
        SemanticsAction.didLoseAccessibilityFocus,
        SemanticsAction.showOnScreen,
        SemanticsAction.focus,
      ]) {
        send(action);
      }
      send(SemanticsAction.tap, nodeId: 999999);
      send(SemanticsAction.tap, viewId: 999999);
      // The target does not expose a scroll handler.
      send(SemanticsAction.scrollUp);
      await tester.pump();
      expect(
        container.read(syncKeepAwakeInteractionProvider).revision,
        revision,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      send(SemanticsAction.tap);
      await tester.pump();
      expect(
        container.read(syncKeepAwakeInteractionProvider).revision,
        revision,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'keyboard activity is observed but key handling still reaches the field',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var handled = 0;
      await tester.pumpWidget(
        _interactionApp(
          container,
          child: Focus(
            focusNode: focus,
            onKeyEvent: (_, _) {
              handled++;
              return KeyEventResult.handled;
            },
            child: const Text('Keyboard target'),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      final revision = container
          .read(syncKeepAwakeInteractionProvider)
          .revision;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      expect(handled, 3);
      expect(
        container.read(syncKeepAwakeInteractionProvider).revision,
        revision + 2,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      expect(
        container.read(syncKeepAwakeInteractionProvider).revision,
        revision + 2,
      );
    },
  );

  testWidgets('locked or background apps do not extend their idle deadline', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_interactionApp(container));
    final node = tester.getSemantics(
      find.byKey(const ValueKey('action_target')),
    );
    void tapAction() =>
        tester.binding.platformDispatcher.onSemanticsActionEvent!(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            viewId: tester.view.viewId,
            nodeId: node.id,
          ),
        );
    final revision = container.read(syncKeepAwakeInteractionProvider).revision;
    container.read(syncKeepAwakePrivacyLockProvider.notifier).lock();
    tapAction();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.tap(find.byKey(const ValueKey('action_target')));
    expect(container.read(syncKeepAwakeInteractionProvider).revision, revision);
    container.read(syncKeepAwakePrivacyLockProvider.notifier).unlock();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tapAction();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(
      container.read(syncKeepAwakeInteractionProvider).revision,
      revision + 1,
    );
    // unlock() itself records an interaction; background actions add none.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    semantics.dispose();
  });

  testWidgets('records mobile pointer interactions without consuming them', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var taps = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SyncKeepAwakeInteractionListener(
              child: Center(
                child: GestureDetector(
                  key: const ValueKey('target'),
                  onTap: () => taps += 1,
                  child: const SizedBox.square(
                    dimension: 120,
                    child: Center(child: Text('Tap target')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final initialRevision = container
        .read(syncKeepAwakeInteractionProvider)
        .revision;

    await tester.tap(find.byKey(const ValueKey('target')));
    await tester.pump();

    expect(taps, 1);
    expect(
      container.read(syncKeepAwakeInteractionProvider).revision,
      greaterThan(initialRevision),
    );

    final afterTapRevision = container
        .read(syncKeepAwakeInteractionProvider)
        .revision;

    await tester.drag(find.byKey(const ValueKey('target')), const Offset(8, 0));
    await tester.pump();

    expect(
      container.read(syncKeepAwakeInteractionProvider).revision,
      greaterThan(afterTapRevision),
    );
  });
}

Widget _interactionApp(
  ProviderContainer container, {
  VoidCallback? onTap,
  Widget? child,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: SyncKeepAwakeInteractionListener(
        child:
            child ??
            GestureDetector(
              key: const ValueKey('action_target'),
              onTap: onTap ?? () {},
              child: const SizedBox.square(
                dimension: 120,
                child: Text('Action target'),
              ),
            ),
      ),
    ),
  ),
);
