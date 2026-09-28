import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/input/app_password_input_source.dart';

import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/widgets/confirm_access_card.dart';

import '../../fakes/fake_password_input_source.dart';

void main() {
  late FakePlatform platform;
  late FakeStore store;
  late AppPasswordInputSource service;
  setUp(() {
    platform = FakePlatform();
    store = FakeStore();
    service = AppPasswordInputSource(
      enabled: true,
      platform: platform,
      store: store,
    );
  });

  test(
    'capture does not persist; success remembers the submission snapshot',
    () async {
      final candidate = await service.capture();
      expect(store.value, isNull);
      platform.current = {'platform': 'macos', 'id': 'changed.after.submit'};
      await service.remember(candidate);
      expect(jsonDecode(store.value!)['source'], source);
    },
  );
  test('missing capture never replaces an existing preference', () async {
    store.value = 'existing';
    platform.current = null;
    await service.remember(await service.capture());
    expect(store.value, 'existing');
  });
  test('disabled service performs no platform calls or writes', () async {
    final disabled = AppPasswordInputSource(
      enabled: false,
      platform: platform,
      store: store,
    );
    await disabled.remember(await disabled.capture());
    await disabled.restore(isCurrent: () => true);
    await disabled.clear();
    expect(platform.captures, 0);
    expect(store.writes, 0);
  });
  test(
    'reset invalidates candidates and clears after an older write',
    () async {
      final candidate = await service.capture();
      store.pendingWrite = Completer<void>();
      final write = service.remember(candidate);
      await Future<void>.delayed(Duration.zero);
      final reset = service.clear();
      final staleWrite = service.remember(candidate);
      store.pendingWrite!.complete();
      await Future.wait([write, reset, staleWrite]);
      expect(store.value, isNull);
      expect(store.writes, 1);
    },
  );
  test('reset while capture is pending rejects the candidate', () async {
    platform.pending = Completer();
    final capture = service.capture();
    await service.clear();
    platform.pending!.complete(source);
    expect(await capture, isNull);
  });
  test('a candidate belongs only to its service lifetime', () async {
    final candidate = await service.capture();
    final other = AppPasswordInputSource(
      enabled: true,
      platform: platform,
      store: store,
    );
    await other.remember(candidate);
    service.dispose();
    await service.remember(candidate);
    expect(store.value, isNull);
  });
  test(
    'malformed, missing and foreign-platform settings are ignored',
    () async {
      for (final value in [
        null,
        'invalid',
        '{}',
        '{"version":2,"source":{}}',
        '{"version":1,"source":{"platform":"windows"}}',
      ]) {
        store.value = value;
        await service.restore(isCurrent: () => true);
      }
      expect(platform.restored, isEmpty);
    },
  );
  test('focus loss while loading prevents late restore', () async {
    await service.remember(await service.capture());
    store.pendingRead = Completer();
    var current = true;
    final restore = service.restore(isCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    store.pendingRead!.complete(store.value);
    await restore;
    expect(platform.restored, isEmpty);
  });
  test('manual input-source change while loading is preserved', () async {
    await service.remember(await service.capture());
    store.pendingRead = Completer();
    final restore = service.restore(isCurrent: () => true);
    await Future<void>.delayed(Duration.zero);
    platform.current = {'platform': 'macos', 'id': 'user.choice'};
    store.pendingRead!.complete(store.value);
    await restore;
    expect(platform.restored, isEmpty);
  });
  test('platform and persistence failures never escape', () async {
    platform.fail = true;
    expect(await service.capture(), isNull);
    await service.restore(isCurrent: () => true);
    platform.fail = false;
    final candidate = await service.capture();
    store.fail = true;
    await service.remember(candidate);
    await service.restore(isCurrent: () => true);
  });

  Future<void> mount(WidgetTester tester, {bool inactive = false}) async {
    tester.binding.handleAppLifecycleStateChanged(
      inactive ? AppLifecycleState.inactive : AppLifecycleState.resumed,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appPasswordInputSourceProvider.overrideWithValue(service)],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AppPasswordInput(child: TextField(key: Key('password'))),
                TextField(key: Key('ordinary')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'viewing key card autofocus restores after cursor initialization',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await service.remember(await service.capture());
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      expect(controller.selection.isValid, isFalse);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPasswordInputSourceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Scaffold(
                body: Center(
                  child: ConfirmAccessCard(
                    subtitle: 'To view the viewing key.',
                    controller: controller,
                    errorText: null,
                    isSubmitting: false,
                    canSubmit: false,
                    onChanged: () {},
                    onSubmit: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(platform.restored, hasLength(1));
    },
  );

  testWidgets(
    'IME composition change without text change cancels pending restore',
    (tester) async {
      await service.remember(await service.capture());
      store.pendingRead = Completer();
      await mount(tester);
      await tester.tap(find.byKey(const Key('password')));
      await tester.pump();
      final editor = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('password')),
          matching: find.byType(EditableText),
        ),
      );
      editor.controller.value = editor.controller.value.copyWith(
        composing: const TextRange.collapsed(0),
      );
      store.pendingRead!.complete(store.value);
      await tester.pumpAndSettle();
      expect(platform.restored, isEmpty);
    },
  );

  testWidgets('only opted-in field restores once; blur never switches back', (
    tester,
  ) async {
    await service.remember(await service.capture());
    await mount(tester);
    await tester.tap(find.byKey(const Key('ordinary')));
    await tester.pumpAndSettle();
    expect(platform.restored, isEmpty);
    await tester.tap(find.byKey(const Key('password')));
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
    await tester.enterText(find.byKey(const Key('password')), 'password');
    await tester.tap(find.byKey(const Key('ordinary')));
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
  });
  testWidgets('inactive startup focus restores on activation only once', (
    tester,
  ) async {
    await service.remember(await service.capture());
    await mount(tester, inactive: true);
    await tester.tap(find.byKey(const Key('password')));
    await tester.pumpAndSettle();
    expect(platform.restored, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.restored, hasLength(1));
  });
  testWidgets('typing while preference loads cancels restore', (tester) async {
    await service.remember(await service.capture());
    store.pendingRead = Completer();
    await mount(tester);
    await tester.tap(find.byKey(const Key('password')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('password')), 'started');
    store.pendingRead!.complete(store.value);
    await tester.pumpAndSettle();
    expect(platform.restored, isEmpty);
    expect(find.text('started'), findsOneWidget);
  });
  testWidgets('disposing a focused field cancels a pending restore', (
    tester,
  ) async {
    await service.remember(await service.capture());
    store.pendingRead = Completer();
    await mount(tester);
    await tester.tap(find.byKey(const Key('password')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    store.pendingRead!.complete(store.value);
    await tester.pumpAndSettle();
    expect(platform.restored, isEmpty);
  });
}
