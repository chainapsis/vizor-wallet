@Tags(['mobile'])
library;

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
