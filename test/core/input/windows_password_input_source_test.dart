import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zcash_wallet/src/core/input/app_password_input_source.dart';

import '../../fakes/fake_password_input_source.dart';

void main() {
  const windowChannel = MethodChannel('window_manager');
  late FakePlatform platform;
  late FakeStore store;
  late AppPasswordInputSource service;
  late Future<bool> Function() queryFocus;

  setUp(() {
    platform = FakePlatform()
      ..current = {'platform': 'windows', 'id': 'saved.latin'};
    store = FakeStore();
    service = AppPasswordInputSource(
      enabled: true,
      useWindowsFocus: true,
      platform: platform,
      store: store,
    );
    queryFocus = () async => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) {
          expect(call.method, 'isFocused');
          return queryFocus();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
    expect(windowManager.listeners, isEmpty);
    service.dispose();
  });

  Future<void> event(WidgetTester tester, String name) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onEvent', {'eventName': name}),
      ),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> mount(WidgetTester tester, {bool autofocus = true}) async {
    await service.remember(await service.capture());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appPasswordInputSourceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const TextField(key: Key('before')),
                AppPasswordInput(
                  child: TextField(
                    key: const Key('password'),
                    autofocus: autofocus,
                  ),
                ),
                const TextField(key: Key('after')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Windows cold autofocus works without a Flutter lifecycle', (
    tester,
  ) async {
    expect(tester.binding.lifecycleState, isNull);
    await mount(tester);
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
  });

  testWidgets(
    'hidden startup defers once; duplicate focus keeps pending work',
    (tester) async {
      queryFocus = () async => false;
      store.pendingRead = Completer();
      await mount(tester);
      expect(platform.restored, isEmpty);
      await event(tester, 'focus');
      await event(tester, 'focus');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      store.pendingRead!.complete(store.value);
      await tester.pumpAndSettle();
      expect(platform.restored, hasLength(1));
      await event(tester, 'blur');
      await event(tester, 'focus');
      expect(platform.restored, hasLength(1));
    },
  );

  testWidgets('an old focus query cannot override a newer window blur', (
    tester,
  ) async {
    final pending = Completer<bool>();
    queryFocus = () => pending.future;
    await mount(tester);
    await event(tester, 'blur');
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(platform.restored, isEmpty);
    await event(tester, 'focus');
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
  });

  for (final nativeFirst in [true, false]) {
    testWidgets(
      'view focus parking does not restore again (native first: $nativeFirst)',
      (tester) async {
        await mount(tester);
        await tester.pumpAndSettle();
        expect(platform.restored, hasLength(1));
        platform.current = {'platform': 'windows', 'id': 'manual.choice'};
        if (nativeFirst) await event(tester, 'blur');
        tester.binding.handleViewFocusChanged(
          ViewFocusEvent(
            viewId: tester.view.viewId,
            state: ViewFocusState.unfocused,
            direction: ViewFocusDirection.undefined,
          ),
        );
        await tester.pump();
        if (!nativeFirst) await event(tester, 'blur');
        if (nativeFirst) await event(tester, 'focus');
        tester.binding.handleViewFocusChanged(
          ViewFocusEvent(
            viewId: tester.view.viewId,
            state: ViewFocusState.focused,
            direction: ViewFocusDirection.undefined,
          ),
        );
        await tester.pump();
        if (!nativeFirst) await event(tester, 'focus');
        await tester.pumpAndSettle();
        expect(platform.restored, hasLength(1));
        // A subsequent deliberate field change is still a new restore attempt.
        await tester.tap(find.byKey(const Key('before')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('password')));
        await tester.pumpAndSettle();
        expect(platform.restored, hasLength(2));
      },
    );
  }

  testWidgets('a late inactive query cannot cancel a native focus restore', (
    tester,
  ) async {
    final pending = Completer<bool>();
    queryFocus = () => pending.future;
    store.pendingRead = Completer();
    await mount(tester);
    await event(tester, 'focus');
    pending.complete(false);
    await tester.pump();
    store.pendingRead!.complete(store.value);
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
  });

  testWidgets('failed initial focus query recovers on native activation', (
    tester,
  ) async {
    queryFocus = () async => throw PlatformException(code: 'unavailable');
    await mount(tester);
    expect(platform.restored, isEmpty);
    await event(tester, 'focus');
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
  });

  testWidgets('macOS keeps lifecycle and key-release cancellation unchanged', (
    tester,
  ) async {
    service = AppPasswordInputSource(
      enabled: true,
      platform: platform,
      store: store,
    );
    platform.current = source;
    queryFocus = () async =>
        throw StateError('macOS must not query Windows focus');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    store.pendingRead = Completer();
    await mount(tester, autofocus: false);
    expect(windowManager.listeners, isEmpty);
    await tester.tap(find.byKey(const Key('before')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(platform.captures, 2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    store.pendingRead!.complete(store.value);
    await tester.pumpAndSettle();
    expect(platform.restored, isEmpty);
  });

  for (final backwards in [false, true]) {
    testWidgets(
      '${backwards ? 'Shift+Tab' : 'Tab'} release allows restoration',
      (tester) async {
        store.pendingRead = Completer();
        await mount(tester, autofocus: false);
        await tester.tap(find.byKey(Key(backwards ? 'after' : 'before')));
        await tester.pumpAndSettle();
        if (backwards) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final editor = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('password')),
            matching: find.byType(EditableText),
          ),
        );
        expect(editor.focusNode.hasFocus, isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        if (backwards) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        store.pendingRead!.complete(store.value);
        await tester.pumpAndSettle();
        expect(platform.restored, hasLength(1));
      },
    );
  }

  for (final cancellation in [
    'key',
    'edit',
    'composition',
    'blur',
    'field',
    'dispose',
    'manual',
  ]) {
    testWidgets('$cancellation cancels Windows pending restore without retry', (
      tester,
    ) async {
      store.pendingRead = Completer();
      await mount(tester);
      switch (cancellation) {
        case 'key':
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        case 'edit':
          await tester.enterText(find.byKey(const Key('password')), 'sample');
        case 'composition':
          final editor = tester.widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('password')),
              matching: find.byType(EditableText),
            ),
          );
          editor.controller.value = editor.controller.value.copyWith(
            composing: const TextRange.collapsed(0),
          );
        case 'blur':
          await event(tester, 'blur');
        case 'field':
          await tester.tap(find.byKey(const Key('before')));
          await tester.pump();
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'manual':
          platform.current = {'platform': 'windows', 'id': 'user.choice'};
      }
      store.pendingRead!.complete(store.value);
      await tester.pumpAndSettle();
      await event(tester, 'blur');
      await event(tester, 'focus');
      await tester.pumpAndSettle();
      expect(platform.restored, isEmpty);
    });
  }

  testWidgets(
    'typing before initial activation also cancels deferred restore',
    (tester) async {
      queryFocus = () async => false;
      await mount(tester);
      await tester.enterText(find.byKey(const Key('password')), 'sample');
      await event(tester, 'focus');
      await tester.pumpAndSettle();
      expect(platform.restored, isEmpty);
    },
  );

  test(
    'Windows reads native outcome while macOS keeps the void contract',
    () async {
      final calls = <String>[];
      final messages = <String?>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        MethodChannelPasswordInputSource.channel,
        (call) async {
          calls.add(call.method);
          return call.method == 'restoreWithResult' ? false : null;
        },
      );
      try {
        await MethodChannelPasswordInputSource().restore({}, {});
        expect(messages, isEmpty);
        await MethodChannelPasswordInputSource(windows: true).restore({}, {});
        expect(calls, ['restore', 'restoreWithResult']);
        expect(messages, [
          'Windows password input source: restoration not confirmed.',
        ]);
      } finally {
        debugPrint = previous;
        messenger.setMockMethodCallHandler(
          MethodChannelPasswordInputSource.channel,
          null,
        );
      }
    },
  );
}
