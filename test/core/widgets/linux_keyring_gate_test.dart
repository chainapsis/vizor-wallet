import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/linux_keyring_gate.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

Widget _app(
  LinuxKeyringCoordinator coordinator, {
  Widget child = const Text('Wallet screen'),
  AppThemeData theme = AppThemeData.light,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  builder: (context, child) => AppTheme(
    data: theme,
    child: LinuxKeyringGate(coordinator: coordinator, child: child!),
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('paints the startup host before loading the app exactly once', (
    tester,
  ) async {
    final coordinator = LinuxKeyringCoordinator.testing();
    addTearDown(coordinator.dispose);
    final loadedApp = Completer<Widget>();
    var loadCalls = 0;
    var appBuilds = 0;
    Future<Widget> loadApp() {
      loadCalls++;
      expect(find.text('Opening Vizor'), findsOneWidget);
      expect(
        SchedulerBinding.instance.schedulerPhase,
        SchedulerPhase.postFrameCallbacks,
      );
      return loadedApp.future;
    }

    await tester.pumpWidget(
      LinuxKeyringStartupHost(coordinator: coordinator, loadApp: loadApp),
    );
    coordinator.setStateForTesting(
      const LinuxKeyringState(phase: LinuxKeyringPhase.retrying),
    );
    await tester.pump();
    expect(find.text('Trying secure storage'), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
    expect(loadCalls, 1);
    expect(appBuilds, 0);
    expect(find.text('Wallet screen'), findsNothing);
    expect(find.text('Welcome'), findsNothing);

    loadedApp.complete(
      Builder(
        builder: (_) {
          appBuilds++;
          return _app(coordinator);
        },
      ),
    );
    coordinator.setStateForTesting(const LinuxKeyringState());
    await tester.pump();
    await tester.pump();
    expect(appBuilds, 1);
    expect(loadCalls, 1);
    expect(find.text('Wallet screen'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets(
    'unexpected startup errors remain visible without retrying load',
    (tester) async {
      final coordinator = LinuxKeyringCoordinator.testing();
      addTearDown(coordinator.dispose);
      var loadCalls = 0;
      await tester.pumpWidget(
        LinuxKeyringStartupHost(
          coordinator: coordinator,
          loadApp: () async {
            loadCalls++;
            throw StateError('Private native error details');
          },
        ),
      );
      await tester.pump();
      expect(find.text('Unable to open Vizor'), findsOneWidget);
      expect(find.textContaining('Private native'), findsNothing);
      expect(find.text('Quit'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(loadCalls, 1);
    },
  );

  testWidgets('blocks input and preserves the mounted wallet screen', (
    tester,
  ) async {
    final coordinator = LinuxKeyringCoordinator.testing();
    addTearDown(coordinator.dispose);
    var taps = 0;
    var builds = 0;
    var escapeEvents = 0;
    await tester.pumpWidget(
      _app(
        coordinator,
        child: Builder(
          builder: (_) {
            builds++;
            return Focus(
              onKeyEvent: (_, event) {
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  escapeEvents++;
                }
                return KeyEventResult.ignored;
              },
              child: Align(
                alignment: Alignment.topLeft,
                child: AppButton(
                  onPressed: () => taps++,
                  child: const Text('Wallet action'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Wallet action'));
    await tester.pump();
    expect(taps, 1);
    final screenBuilds = builds;
    final buttonState = tester.state(find.byType(AppButton));

    coordinator.setStateForTesting(
      const LinuxKeyringState(phase: LinuxKeyringPhase.retrying),
    );
    await tester.pump();
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.text('Wallet action')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(taps, 1);
    expect(escapeEvents, 0);
    expect(find.text('Trying secure storage'), findsOneWidget);
    expect(find.text('Unlock keyring'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(builds, screenBuilds);

    coordinator.setStateForTesting(
      const LinuxKeyringState(phase: LinuxKeyringPhase.working),
    );
    await tester.pump();
    expect(find.text('Trying secure storage'), findsNothing);
    expect(tester.state(find.byType(AppButton)), same(buttonState));
    await tester.tap(find.text('Wallet action'));
    expect(taps, 2);
  });

  testWidgets('blocks router back until storage recovery ends', (tester) async {
    final coordinator = LinuxKeyringCoordinator.testing();
    addTearDown(coordinator.dispose);
    final router = GoRouter(
      initialLocation: '/details',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Wallet home')),
          routes: [
            GoRoute(
              path: 'details',
              builder: (_, _) => const Scaffold(body: Text('Wallet details')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => AppTheme(
          data: AppThemeData.light,
          child: LinuxKeyringGate(coordinator: coordinator, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    coordinator.setStateForTesting(
      const LinuxKeyringState(phase: LinuxKeyringPhase.keyringLocked),
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/details');
    expect(find.text('Unlock your keyring'), findsOneWidget);

    coordinator.setStateForTesting(const LinuxKeyringState());
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets(
    'upstream error shows retry and preserves the same wallet screen',
    (tester) async {
      final coordinator = LinuxKeyringCoordinator.testing();
      addTearDown(coordinator.dispose);
      final reply = Completer<String>();
      var calls = 0;
      final pending = coordinator.runStorageOperation(() async {
        if (++calls == 1) throw PlatformException(code: 'KeyringLocked');
        return reply.future;
      }, isRead: true);
      await tester.pumpWidget(_app(coordinator));
      await tester.pump();
      expect(find.text('Unlock your keyring'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(calls, 1);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(calls, 2);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Trying secure storage'), findsOneWidget);
      reply.complete('same wallet');
      await tester.pump();
      expect(await pending, 'same wallet');
      expect(find.text('Wallet screen'), findsOneWidget);
      expect(find.text('Trying secure storage'), findsNothing);
    },
  );

  testWidgets(
    'cancel abandons a failed read without making another native call',
    (tester) async {
      final coordinator = LinuxKeyringCoordinator.testing();
      addTearDown(coordinator.dispose);
      var calls = 0;
      final pending = coordinator.runStorageOperation(() async {
        calls++;
        throw PlatformException(code: 'KeyringLocked');
      }, isRead: true);
      final failed = expectLater(
        pending,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'storage_cancelled',
          ),
        ),
      );
      await tester.pumpWidget(_app(coordinator));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await failed;
      expect(calls, 1);
      expect(find.text('Unlock your keyring'), findsNothing);
      expect(find.text('Wallet screen'), findsOneWidget);
    },
  );

  testWidgets(
    'pending wallet mutations and uncertain saves cannot be cancelled',
    (tester) async {
      final coordinator = LinuxKeyringCoordinator.testing();
      addTearDown(coordinator.dispose);
      final finish = Completer<void>();
      final mutation = coordinator.runMutation(() => finish.future);
      coordinator.setStateForTesting(
        const LinuxKeyringState(
          phase: LinuxKeyringPhase.keyringLocked,
          requestId: 42,
          canCancel: true,
        ),
      );
      await tester.pumpWidget(_app(coordinator));
      expect(find.text('Cancel'), findsNothing);
      finish.complete();
      await mutation;
      await tester.pump();
      expect(find.text('Cancel'), findsOneWidget);

      coordinator.setStateForTesting(
        const LinuxKeyringState(
          phase: LinuxKeyringPhase.outcomeUnknown,
          canCancel: true,
        ),
      );
      await tester.pump();
      expect(find.text('Unable to confirm the save'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Quit'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    },
  );

  testWidgets(
    'unavailable keyring offers retry and quit without wallet reset',
    (tester) async {
      final coordinator = LinuxKeyringCoordinator.testing();
      addTearDown(coordinator.dispose);
      coordinator.setStateForTesting(
        const LinuxKeyringState(
          phase: LinuxKeyringPhase.serviceUnavailable,
          requestId: 42,
        ),
      );
      var quitCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') quitCalls++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_app(coordinator));
      expect(find.text('Secure storage is unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Reset wallet'), findsNothing);
      await tester.tap(find.text('Quit'));
      expect(quitCalls, 1);
    },
  );

  testWidgets('disabled coordinator leaves the app interactive', (
    tester,
  ) async {
    final coordinator = LinuxKeyringCoordinator.testing(enabled: false);
    addTearDown(coordinator.dispose);
    coordinator.setStateForTesting(
      const LinuxKeyringState(
        phase: LinuxKeyringPhase.serviceUnavailable,
        requestId: 42,
      ),
    );
    var taps = 0;
    await tester.pumpWidget(
      _app(
        coordinator,
        child: AppButton(
          onPressed: () => taps++,
          child: const Text('Wallet action'),
        ),
      ),
    );
    expect(find.text('Secure storage is unavailable'), findsNothing);
    await tester.tap(find.text('Wallet action'));
    expect(taps, 1);
  });

  testWidgets('keyring notices fit a compact desktop window in both themes', (
    tester,
  ) async {
    await loadFigmaCompareFonts();
    tester.view.physicalSize = const Size(640, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coordinator = LinuxKeyringCoordinator.testing();
    addTearDown(coordinator.dispose);
    final boundaryKey = GlobalKey();
    const captureDirectory = String.fromEnvironment('KEYRING_CAPTURE_DIR');

    for (final theme in [AppThemeData.light, AppThemeData.dark]) {
      for (final phase in [
        LinuxKeyringPhase.retrying,
        LinuxKeyringPhase.keyringLocked,
        LinuxKeyringPhase.serviceUnavailable,
        LinuxKeyringPhase.storageCorrupt,
        LinuxKeyringPhase.outcomeUnknown,
      ]) {
        coordinator.setStateForTesting(
          LinuxKeyringState(
            phase: phase,
            requestId: 42,
            canCancel: phase != LinuxKeyringPhase.retrying,
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: _app(
              coordinator,
              theme: theme,
              child: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is ModalBarrier &&
                widget.color == theme.colors.background.neutralScrim &&
                !widget.dismissible,
          ),
          findsOneWidget,
        );
        if (captureDirectory.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final capture = await boundary.toImage();
            final bytes = await capture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final themeName = theme == AppThemeData.dark ? 'dark' : 'light';
            final file = File('$captureDirectory/$themeName-${phase.name}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            capture.dispose();
          });
        }
      }
    }
  });
}
