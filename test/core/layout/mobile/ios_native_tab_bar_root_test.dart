@Tags(['mobile'])
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/ios_native_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/ios_native_tab_bar_root.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_navigation_scope.dart';
import 'package:zcash_wallet/src/core/navigation/route_owned_redirect.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

import '../../../support/ios_native_tab_bar_fixture.dart';

const _items = [
  IosNativeTabBarItem(id: '/home', iconName: 'home', label: 'Home'),
  IosNativeTabBarItem(id: '/settings', iconName: 'cog', label: 'Settings'),
];
IosNativeTabBarConfiguration _config(ValueChanged<String> select) =>
    IosNativeTabBarConfiguration(
      items: _items,
      selectedId: '/home',
      onSelect: select,
    );

Widget _shell(ValueChanged<String> select) => AppMobileShell(
  body: const Text('Body'),
  tabBar: const SizedBox(key: ValueKey('legacy'), height: 64),
  nativeTabBar: _config(select),
);

void main() {
  late NativeTabBarFixture native;
  late RouteOwnedNavigationObserver rootObserver;
  setUp(() {
    native = NativeTabBarFixture();
    rootObserver = RouteOwnedNavigationObserver();
  });
  tearDown(() {
    native.dispose();
    rootObserver.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    Widget? home,
    ValueChanged<String>? select,
    bool covered = false,
    bool hard = false,
    Object? sessionIdentity,
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [rootObserver],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, navigator) => AppTheme(
          data: AppThemeData.light,
          child: IosNativeTabBarRootHost(
            covered: covered,
            hideImmediately: hard,
            sessionIdentity: sessionIdentity,
            child: navigator!,
          ),
        ),
        home: home ?? _shell(select ?? (_) {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  _test(
    'owner release invalidates callbacks and cannot release a newer lease',
    (tester) async {
      final coordinator = IosNativeTabBarCoordinator();
      addTearDown(coordinator.dispose);
      final selected = <String>[];
      final first = coordinator.acquireOwner(canSelect: () => true);
      void publish(IosNativeTabBarOwnerLease owner, String name) =>
          owner.publish(
            configuration: _config((id) => selected.add('$name:$id')),
            viewport: const Rect.fromLTWH(0, 0, 402, 874),
            media: const MediaQueryData(size: Size(402, 874)),
            mode: MobileNavigationMode.bottomTabs,
          );
      publish(first, 'first');
      coordinator.select('/home');
      final next = coordinator.acquireOwner(canSelect: () => true);
      publish(next, 'next');
      first.release();
      publish(first, 'stale');
      coordinator.select('/settings');
      next.release();
      coordinator.select('/home');
      expect(selected, ['first:/home', 'next:/settings']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  _test(
    'root owns one native view and the shell retains only a fitting spacer',
    (tester) async {
      await pump(tester);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(find.byKey(const ValueKey('legacy')), findsNothing);
      expect(
        find.byKey(const ValueKey('ios_native_tab_bar_slot')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('ios_native_tab_bar_slot')))
            .height,
        native.height,
      );
      final body = tester.element(find.text('Body'));
      final view = tester.state(find.byType(UiKitView));
      await pump(tester, covered: true);
      expect(native.latest['hidden'], true);
      expect(find.byType(UiKitView), findsNothing);
      expect(find.byType(UiKitView, skipOffstage: false), findsOneWidget);
      expect(tester.element(find.text('Body')), same(body));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('ios_native_tab_bar_slot')))
            .height,
        native.height,
      );
      await pump(tester);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(tester.state(find.byType(UiKitView)), same(view));
      expect(native.created, hasLength(1));
      expect(native.latest['showRequestId'], 1);
    },
  );

  _test(
    'normal exit keeps the root surface above overlays until current hidden '
    'acknowledgement, then removes it from composition',
    (tester) async {
      native.automaticallySettleHidden = false;
      final selected = <String>[];
      await pump(tester, select: selected.add);
      final old = Map.of(native.presentations.values.last);
      await pump(tester, select: selected.add, covered: true);
      expect(native.latest['hidden'], true);
      expect(find.byType(UiKitView), findsOneWidget);
      await native.send('select', {...old, 'id': '/settings'});
      expect(selected, isEmpty);
      await native.send('presentation', {
        ...old,
        'phase': 'hidden',
        'settledHidden': true,
        'interactive': false,
        'revision': 100,
      });
      await tester.pump();
      expect(find.byType(UiKitView), findsOneWidget);
      await native.present(
        interactive: false,
        phase: 'hidden',
        settledHidden: true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsNothing);
      final hidden = Map.of(native.presentations.values.last);
      await pump(tester, select: selected.add);
      expect(find.byType(UiKitView), findsOneWidget);
      await native.send('presentation', {...hidden, 'revision': 1000});
      await tester.pump();
      expect(find.byType(UiKitView), findsOneWidget);
      await native.send('select', {'id': '/settings'});
      expect(selected, ['/settings']);
    },
  );

  _test(
    'security suppression removes painting before native exit acknowledgement',
    (tester) async {
      native.automaticallySettleHidden = false;
      final selected = <String>[];
      await pump(tester, select: selected.add);
      final old = Map.of(native.presentations.values.last);
      await pump(tester, select: selected.add, hard: true);
      expect(native.latest['hideImmediately'], true);
      expect(find.byType(UiKitView), findsNothing);
      expect(find.byType(UiKitView, skipOffstage: false), findsOneWidget);
      await native.send('select', {...old, 'id': '/settings'});
      expect(selected, isEmpty);
      await pump(tester, select: selected.add);
      expect(find.byType(UiKitView), findsOneWidget);
      expect(native.created, hasLength(1));
    },
  );

  _test(
    'root and nested modal coverage hide the same root bar through closing',
    (tester) async {
      final rootKey = GlobalKey<NavigatorState>();
      final innerKey = GlobalKey<NavigatorState>();
      final innerObserver = RouteOwnedNavigationObserver();
      addTearDown(innerObserver.dispose);
      final selected = <String>[];
      final home = Navigator(
        key: innerKey,
        observers: [innerObserver],
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => _shell(selected.add)),
      );
      await pump(tester, home: home, navigatorKey: rootKey);
      final view = tester.state(find.byType(UiKitView));
      for (final key in [innerKey, rootKey]) {
        final dialog = key.currentState!.push<void>(
          DialogRoute<void>(
            context: key.currentContext!,
            builder: (_) => const AlertDialog(content: Text('Cover')),
          ),
        );
        await native.send('select', {'id': '/settings'});
        expect(selected, isEmpty);
        await tester.pumpAndSettle();
        expect(native.latest['hidden'], true);
        final rootHost = find.byType(IosNativeTabBarRootHost);
        final rootStack = tester.widget<Stack>(
          find.descendant(of: rootHost, matching: find.byType(Stack)).first,
        );
        expect(rootStack.children.last, isA<Positioned>());
        await native.send('select', {'id': '/settings'});
        expect(selected, isEmpty);
        key.currentState!.pop();
        await tester.pump(const Duration(milliseconds: 20));
        expect(native.latest['hidden'], true);
        await tester.pumpAndSettle();
        await dialog;
        expect(native.latest['hidden'], false);
        expect(tester.state(find.byType(UiKitView)), same(view));
      }
      expect(native.created, hasLength(1));
    },
  );

  _test('page pop reveals before route completion but keeps input blocked', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final observer = RouteOwnedNavigationObserver();
    addTearDown(observer.dispose);
    final selected = <String>[];
    await pump(
      tester,
      home: Navigator(
        key: key,
        observers: [observer],
        onGenerateRoute: (_) =>
            CupertinoPageRoute<void>(builder: (_) => _shell(selected.add)),
      ),
    );
    final view = tester.state(find.byType(UiKitView));
    final detail = CupertinoPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Detail')),
    );
    key.currentState!.push(detail);
    await tester.pumpAndSettle();
    expect(native.latest['hidden'], true);
    key.currentState!.pop();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(detail.animation!.value, greaterThan(0));
    expect(observer.hasDepartingRoutes, true);
    expect(native.latest['hidden'], false);
    expect(native.latest['inputEnabled'], false);
    await native.present(interactive: true, phase: 'visible');
    await native.send('select', {'id': '/settings'});
    expect(selected, isEmpty);
    await tester.pumpAndSettle();
    expect(native.latest['inputEnabled'], true);
    expect(tester.state(find.byType(UiKitView)), same(view));
    await native.send('select', {'id': '/settings'});
    expect(selected, ['/settings']);
  });

  for (final commit in [false, true]) {
    _test('held Cupertino swipe reveals with input blocked and '
        '${commit ? 'commits' : 'cancels immediately on release'}', (
      tester,
    ) async {
      final key = GlobalKey<NavigatorState>();
      final observer = RouteOwnedNavigationObserver();
      addTearDown(observer.dispose);
      final selected = <String>[];
      await pump(
        tester,
        home: Navigator(
          key: key,
          observers: [observer],
          onGenerateRoute: (_) =>
              CupertinoPageRoute<void>(builder: (_) => _shell(selected.add)),
        ),
      );
      final view = tester.state(find.byType(UiKitView));
      final detail = CupertinoPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      );
      key.currentState!.push(detail);
      await tester.pumpAndSettle();
      expect(native.latest['hidden'], true);
      final gesture = await tester.startGesture(const Offset(1, 200));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(observer.nativeGestureInProgress, true);
      expect(detail.animation!.status, AnimationStatus.forward);
      expect(native.latest['hidden'], false);
      expect(native.latest['inputEnabled'], false);
      // Completing the native entrance cannot bypass the still-held swipe.
      await native.present(interactive: true, phase: 'visible');
      await native.send('select', {'id': '/settings'});
      expect(selected, isEmpty);
      // An unrelated finger must not be mistaken for the back-gesture release.
      final second = await tester.startGesture(
        const Offset(500, 300),
        pointer: 7,
      );
      await second.up();
      await tester.pump();
      await tester.pump();
      expect(native.latest['hidden'], false);
      if (commit) {
        await gesture.moveBy(const Offset(500, 0));
      }
      // Remove release velocity so this tests the route's actual drag threshold.
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(native.latest['hidden'], !commit);
      expect(native.latest['inputEnabled'], false);
      expect(selected, isEmpty);
      await tester.pumpAndSettle();
      if (!commit) {
        expect(detail.isCurrent, true);
        expect(native.latest['hidden'], true);
        key.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(native.latest['hidden'], false);
      expect(native.latest['inputEnabled'], true);
      expect(tester.state(find.byType(UiKitView)), same(view));
      expect(native.created, hasLength(1));
      await native.send('select', {'id': '/settings'});
      expect(selected, ['/settings']);
    });
  }

  for (final commit in [false, true]) {
    _test('accepted edge-pointer handoff stays revealed, then '
        '${commit ? 'commits' : 'cancels'} on the final release', (
      tester,
    ) async {
      final key = GlobalKey<NavigatorState>();
      final observer = RouteOwnedNavigationObserver();
      addTearDown(observer.dispose);
      final selected = <String>[];
      await pump(
        tester,
        home: Navigator(
          key: key,
          observers: [observer],
          onGenerateRoute: (_) =>
              CupertinoPageRoute<void>(builder: (_) => _shell(selected.add)),
        ),
      );
      final view = tester.state(find.byType(UiKitView));
      final detail = CupertinoPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      );
      key.currentState!.push(detail);
      await tester.pumpAndSettle();
      // Both edge pointers join the recognizer before it wins the arena.
      final first = await tester.startGesture(const Offset(1, 200), pointer: 1);
      final second = await tester.startGesture(
        const Offset(1, 300),
        pointer: 7,
      );
      await first.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(native.latest['hidden'], false);
      await second.moveBy(const Offset(60, 0));
      await first.up();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(observer.nativeGestureInProgress, true);
      final before = detail.animation!.value;
      await second.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pump();
      expect(detail.animation!.value, lessThan(before));
      expect(native.latest['hidden'], false);
      expect(native.latest['inputEnabled'], false);
      await native.present(interactive: true, phase: 'visible');
      await native.send('select', {'id': '/settings'});
      expect(selected, isEmpty);
      if (commit) await second.moveBy(const Offset(500, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await second.up();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(native.latest['hidden'], !commit);
      expect(native.latest['inputEnabled'], false);
      await tester.pumpAndSettle();
      if (!commit) {
        expect(detail.isCurrent, true);
        expect(native.latest['hidden'], true);
        key.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(native.latest['inputEnabled'], true);
      expect(tester.state(find.byType(UiKitView)), same(view));
      expect(native.created, hasLength(1));
    });
  }

  _test(
    'an outside finger held down does not delay actual swipe cancellation',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = RouteOwnedNavigationObserver();
      addTearDown(observer.dispose);
      await pump(
        tester,
        home: Navigator(
          key: key,
          observers: [observer],
          onGenerateRoute: (_) =>
              CupertinoPageRoute<void>(builder: (_) => _shell((_) {})),
        ),
      );
      final detail = CupertinoPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      );
      key.currentState!.push(detail);
      await tester.pumpAndSettle();
      final first = await tester.startGesture(const Offset(1, 200), pointer: 1);
      final outside = await tester.startGesture(
        const Offset(500, 300),
        pointer: 7,
      );
      await first.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(native.latest['hidden'], false);
      await tester.pump(const Duration(milliseconds: 300));
      await first.up();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(observer.nativeGestureInProgress, true);
      expect(detail.isCurrent, true);
      expect(native.latest['hidden'], true);
      expect(native.latest['inputEnabled'], false);
      await outside.up();
      await tester.pumpAndSettle();
      expect(native.latest['hidden'], true);
    },
  );

  _test('returning between two details never reveals the tab shell', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final observer = RouteOwnedNavigationObserver();
    addTearDown(observer.dispose);
    await pump(
      tester,
      home: Navigator(
        key: key,
        observers: [observer],
        onGenerateRoute: (_) =>
            CupertinoPageRoute<void>(builder: (_) => _shell((_) {})),
      ),
    );
    for (final label in ['First detail', 'Second detail']) {
      key.currentState!.push(
        CupertinoPageRoute<void>(builder: (_) => Scaffold(body: Text(label))),
      );
      await tester.pumpAndSettle();
    }
    final swipe = await tester.startGesture(const Offset(1, 200));
    await swipe.moveBy(const Offset(550, 0));
    await tester.pump();
    await tester.pump();
    expect(native.latest['hidden'], true);
    await tester.pump(const Duration(milliseconds: 300));
    await swipe.up();
    await tester.pump();
    await tester.pump();
    expect(native.latest['hidden'], true);
    await tester.pumpAndSettle();
    expect(native.latest['hidden'], true);
  });

  _test(
    'disposing a registration during a swipe releases pointer observation',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = RouteOwnedNavigationObserver();
      await pump(
        tester,
        home: Navigator(
          key: key,
          observers: [observer],
          onGenerateRoute: (_) =>
              CupertinoPageRoute<void>(builder: (_) => _shell((_) {})),
        ),
      );
      key.currentState!.push(
        CupertinoPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Detail')),
        ),
      );
      await tester.pumpAndSettle();
      final swipe = await tester.startGesture(const Offset(1, 200));
      await swipe.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      await swipe.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final guard in ['security', 'coverage', 'keyboard', 'navigation hold']) {
    _test('$guard keeps a returning page hidden', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = RouteOwnedNavigationObserver();
      addTearDown(observer.dispose);
      if (guard == 'keyboard') {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
      }
      await pump(
        tester,
        hard: guard == 'security',
        covered: guard == 'coverage',
        home: Navigator(
          key: key,
          observers: [observer],
          onGenerateRoute: (_) => CupertinoPageRoute<void>(
            builder: (_) => AppMobileShell(
              body: const Text('Body'),
              tabBar: const SizedBox(height: 64),
              nativeTabBar: IosNativeTabBarConfiguration(
                items: _items,
                selectedId: '/home',
                onSelect: (_) {},
                inputEnabled: guard != 'navigation hold',
              ),
            ),
          ),
        ),
      );
      key.currentState!.push(
        CupertinoPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Detail')),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.pop();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(observer.hasDepartingRoutes, true);
      expect(native.latest['hidden'], true);
      expect(native.latest['inputEnabled'], false);
      await tester.pumpAndSettle();
      expect(native.latest['hidden'], true);
    });
  }

  _test(
    'releasing a shell retains only its exit surface and rejects old callbacks',
    (tester) async {
      native.automaticallySettleHidden = false;
      final selected = <String>[];
      await pump(tester, select: selected.add);
      final view = tester.state(find.byType(UiKitView));
      await pump(tester, home: const Scaffold(body: Text('Another scope')));
      expect(native.latest['hidden'], true);
      await native.send('select', {'id': '/settings'});
      expect(selected, isEmpty);
      await pump(tester, select: selected.add);
      expect(tester.state(find.byType(UiKitView)), same(view));
      expect(native.latest['hidden'], false);
      expect(native.created, hasLength(1));
    },
  );

  _test('unsupported native capability restores only the legacy bar', (
    tester,
  ) async {
    native.supported = false;
    await pump(tester);
    expect(find.byType(UiKitView), findsNothing);
    expect(find.byKey(const ValueKey('legacy')), findsOneWidget);
    expect(find.byKey(const ValueKey('ios_native_tab_bar_slot')), findsNothing);
  });

  _test('root geometry uses the stable viewport rather than route transforms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const viewport = Rect.fromLTWH(10, 20, 300, 600);
    await pump(
      tester,
      home: Stack(
        children: [
          Positioned.fromRect(
            rect: viewport,
            child: MobileNavigationScope(
              mode: MobileNavigationMode.bottomTabs,
              viewportRect: viewport,
              navigation: MobileBranchNavigation(),
              child: Transform.translate(
                offset: const Offset(-90, 0),
                child: _shell((_) {}),
              ),
            ),
          ),
        ],
      ),
    );
    expect(
      tester.getRect(find.byType(UiKitView)),
      Rect.fromLTWH(
        viewport.left,
        viewport.bottom - native.height,
        viewport.width,
        native.height,
      ),
    );
  });

  _test('ordinary account identity changes refresh ownership without hiding '
      'the account-independent chrome', (tester) async {
    final selected = <String>[];
    await pump(tester, select: selected.add, sessionIdentity: 'account-a');
    final view = tester.state(find.byType(UiKitView));
    await pump(tester, select: selected.add, sessionIdentity: 'account-b');
    expect(tester.state(find.byType(UiKitView)), same(view));
    expect(
      native.updates.every((snapshot) => snapshot['hidden'] == false),
      true,
    );
    await native.send('select', {'id': '/settings'});
    expect(selected, ['/settings']);
  });
}

void _test(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: TargetPlatformVariant.only(TargetPlatform.iOS),
);
