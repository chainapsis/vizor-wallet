@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/ios_native_tab_bar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

const _items = [
  IosNativeTabBarItem(id: '/home', iconName: 'home', label: 'Home'),
  IosNativeTabBarItem(id: '/swap', iconName: 'swap_arrows', label: 'Swap'),
  IosNativeTabBarItem(id: '/activity', iconName: 'history', label: 'Activity'),
  IosNativeTabBarItem(id: '/settings', iconName: 'cog', label: 'Settings'),
];

Future<Uint8List> _fakeIcon(AssetBundle _, String name, double _) async =>
    Uint8List.fromList(name.codeUnits);

void main() {
  late _NativeFixture native;
  setUp(() {
    native = _NativeFixture();
  });
  tearDown(() {
    native.dispose();
  });

  IosNativeTabBarConfiguration config({
    String selected = '/home',
    List<IosNativeTabBarItem> items = _items,
    ValueChanged<String>? onSelect,
    bool hidden = false,
  }) => IosNativeTabBarConfiguration(
    items: items,
    selectedId: selected,
    onSelect: onSelect ?? (_) {},
    hidden: hidden,
  );

  Future<void> pump(
    WidgetTester tester,
    IosNativeTabBarConfiguration configuration, {
    IosNativeTabBarIconLoader loader = _fakeIcon,
    Brightness brightness = Brightness.light,
    TextDirection direction = TextDirection.ltr,
    double keyboard = 0,
    GlobalKey<NavigatorState>? navigatorKey,
    VoidCallback? onGlobalTap,
    Key? hostKey,
  }) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: Directionality(
              textDirection: direction,
              child: IosNativeTabBarHost(
                key: hostKey,
                configuration: configuration,
                iconLoader: loader,
                builder: (_, bar) => Scaffold(
                  body: const Text('Body'),
                  bottomNavigationBar:
                      bar ??
                      const SizedBox(key: ValueKey('fallback'), height: 64),
                ),
              ),
            ),
          ),
        ),
        brightness: brightness,
        navigatorKey: navigatorKey,
        onGlobalTap: onGlobalTap,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  bool ignoresNativePointers(WidgetTester tester) => tester
      .widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(UiKitView),
              matching: find.byType(IgnorePointer),
            )
            .first,
      )
      .ignoring;

  bool excludesNativeSemantics(WidgetTester tester) => tester
      .widget<ExcludeSemantics>(
        find
            .ancestor(
              of: find.byType(UiKitView),
              matching: find.byType(ExcludeSemantics),
            )
            .first,
      )
      .excluding;

  _testWidgets('entrance waits for native readiness before claiming pointers, '
      'exposing semantics or accepting selection', (tester) async {
    native.automaticallyPresent = false;
    final selected = <String>[];
    var globalTaps = 0;
    await pump(
      tester,
      config(onSelect: selected.add),
      onGlobalTap: () => globalTaps++,
    );
    final rect = tester.getRect(find.byType(UiKitView));
    expect(ignoresNativePointers(tester), true);
    expect(excludesNativeSemantics(tester), true);
    expect(
      tester.widget<UiKitView>(find.byType(UiKitView)).gestureRecognizers,
      isEmpty,
    );
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(globalTaps, 1);
    expect(native.gestureCalls, isNot(contains('acceptGesture')));
    await native.send('select', {'id': '/settings'});
    expect(selected, isEmpty);

    await native.present(interactive: true);
    await tester.pump();
    expect(ignoresNativePointers(tester), false);
    expect(excludesNativeSemantics(tester), false);
    expect(tester.getRect(find.byType(UiKitView)), rect);
    await native.send('select', {'id': '/settings'});
    expect(selected, ['/settings']);
  });

  _testWidgets(
    'hide blocks input immediately and keeps the native layout slot',
    (tester) async {
      final selected = <String>[];
      await pump(tester, config(onSelect: selected.add));
      final rect = tester.getRect(find.byType(UiKitView));
      final view = tester.state(find.byType(UiKitView));
      final oldStatus = Map.of(native.presentations.values.last);
      native.updateDelay = Completer<void>();
      await pump(tester, config(onSelect: selected.add, hidden: true));
      expect(ignoresNativePointers(tester), true);
      expect(excludesNativeSemantics(tester), true);
      expect(tester.getRect(find.byType(UiKitView)), rect);
      expect(tester.state(find.byType(UiKitView)), same(view));
      await native.send('select', {...oldStatus, 'id': '/settings'});
      expect(selected, isEmpty);
      native.updateDelay!.complete();
      await tester.pump();
    },
  );

  _testWidgets(
    'hide then show rejects old ready acknowledgements and selections',
    (tester) async {
      final selected = <String>[];
      await pump(tester, config(onSelect: selected.add));
      final oldStatus = Map.of(native.presentations.values.last);
      native.automaticallyPresent = false;
      await pump(tester, config(onSelect: selected.add, hidden: true));
      await pump(tester, config(onSelect: selected.add));
      expect(native.latest['visibilityEpoch'], 2);
      expect(ignoresNativePointers(tester), true);
      await native.send('presentation', {
        ...oldStatus,
        'revision': 1000,
        'interactive': true,
      });
      await tester.pump();
      expect(ignoresNativePointers(tester), true);
      await native.send('select', {...oldStatus, 'id': '/activity'});
      expect(selected, isEmpty);
      await native.present(interactive: true);
      await tester.pump();
      expect(ignoresNativePointers(tester), false);
      await native.send('select', {...oldStatus, 'id': '/activity'});
      expect(selected, isEmpty);
      await native.send('select', {'id': '/activity'});
      expect(selected, ['/activity']);
    },
  );

  _testWidgets('out-of-order presentation revisions cannot revoke readiness or '
      'authorize an old selection', (tester) async {
    native.automaticallyPresent = false;
    final selected = <String>[];
    await pump(tester, config(onSelect: selected.add));
    await native.present(interactive: true, revision: 5);
    await native.send('presentation', {
      'visibilityEpoch': 0,
      'revision': 4,
      'interactive': false,
    });
    await tester.pump();
    expect(ignoresNativePointers(tester), false);
    await native.send('select', {'id': '/activity', 'revision': 4});
    expect(selected, isEmpty);
    await native.send('select', {'id': '/activity'});
    expect(selected, ['/activity']);
  });

  _testWidgets(
    'an older getPresentation reply cannot overwrite a newer callback',
    (tester) async {
      final query = Completer<Map>();
      native.presentationResponse = query.future;
      native.automaticallyPresent = false;
      await pump(tester, config());
      await native.present(interactive: true, revision: 5);
      await tester.pump();
      expect(ignoresNativePointers(tester), false);
      query.complete({
        'visibilityEpoch': 0,
        'revision': 0,
        'interactive': false,
      });
      await tester.pump();
      expect(ignoresNativePointers(tester), false);
    },
  );

  _testWidgets(
    'a getPresentation reply from before hide-show cannot enable the '
    'new entrance',
    (tester) async {
      final query = Completer<Map>();
      native.presentationResponse = query.future;
      native.automaticallyPresent = false;
      final selected = <String>[];
      await pump(tester, config(onSelect: selected.add));
      await pump(tester, config(onSelect: selected.add, hidden: true));
      await pump(tester, config(onSelect: selected.add));
      query.complete({
        'visibilityEpoch': 0,
        'revision': 100,
        'interactive': true,
      });
      await tester.pump();
      expect(ignoresNativePointers(tester), true);
      await native.send('select', {'id': '/activity'});
      expect(selected, isEmpty);
      await native.present(interactive: true);
      await tester.pump();
      await native.send('select', {'id': '/activity'});
      expect(selected, ['/activity']);
    },
  );

  _testWidgets('view replacement resets readiness and ignores the previous '
      'view query', (tester) async {
    final oldQuery = Completer<Map>();
    native.presentationResponse = oldQuery.future;
    native.automaticallyPresent = false;
    await pump(tester, config(), hostKey: const ValueKey('old'));
    await native.present(interactive: true, revision: 5);
    await tester.pump();
    expect(ignoresNativePointers(tester), false);
    native.presentationResponse = null;
    await pump(tester, config(), hostKey: const ValueKey('new'));
    expect(native.created, hasLength(2));
    expect(ignoresNativePointers(tester), true);
    oldQuery.complete({
      'visibilityEpoch': 0,
      'revision': 100,
      'interactive': true,
    });
    await tester.pump();
    expect(ignoresNativePointers(tester), true);
  });

  _testWidgets('coalesced hide-show updates preserve the visibility epoch', (
    tester,
  ) async {
    native.updateDelay = Completer<void>();
    final selected = <String>[];
    await pump(tester, config(onSelect: selected.add));
    expect(ignoresNativePointers(tester), false);
    await pump(tester, config(onSelect: selected.add, hidden: true));
    await pump(tester, config(onSelect: selected.add));
    expect(native.updates, hasLength(1));
    expect(ignoresNativePointers(tester), true);
    await native.send('select', {'id': '/settings'});
    expect(selected, isEmpty);
    native.updateDelay!.complete();
    await tester.pump();
    await tester.pump();
    expect(native.updates.last['visibilityEpoch'], 2);
    expect(native.updates.last['hidden'], false);
    expect(ignoresNativePointers(tester), false);
  });

  _testWidgets('latest content updates reach native during an entrance without '
      'authorizing early selection', (tester) async {
    native.automaticallyPresent = false;
    final selected = <String>[];
    await pump(tester, config(onSelect: selected.add));
    await pump(
      tester,
      config(
        selected: '/settings',
        items: [
          for (final item in _items.where((item) => item.id != '/swap'))
            IosNativeTabBarItem(
              id: item.id,
              iconName: item.iconName,
              label: '${item.label} latest',
            ),
        ],
        onSelect: selected.add,
      ),
      brightness: Brightness.dark,
    );
    expect(native.latest['visibilityEpoch'], 0);
    expect(native.latest['selectedId'], '/settings');
    expect(native.latest['brightness'], 'dark');
    expect((native.latest['items'] as List).map((item) => item['label']), [
      'Home latest',
      'Activity latest',
      'Settings latest',
    ]);
    expect(ignoresNativePointers(tester), true);
    await native.send('select', {'id': '/activity'});
    expect(selected, isEmpty);
    await native.present(interactive: true);
    await tester.pump();
    await native.send('select', {'id': '/activity'});
    expect(selected, ['/activity']);
    expect(native.created, hasLength(1));
  });

  _testWidgets('older iOS keeps the original bar and does not prepare icons', (
    tester,
  ) async {
    native.supported = false;
    var loads = 0;
    await pump(
      tester,
      config(),
      loader: (bundle, name, scale) {
        loads++;
        return _fakeIcon(bundle, name, scale);
      },
    );
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
    expect(loads, 0);
  });

  _testWidgets('Android does not query native capability', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pump(tester, config());
    expect(native.capabilityReads, 0);
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
  });

  _testWidgets('waits for icon preparation without losing the shell body', (
    tester,
  ) async {
    final icon = Completer<Uint8List>();
    await pump(tester, config(), loader: (_, _, _) => icon.future);
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    final body = tester.element(find.text('Body'));
    icon.complete(Uint8List(4));
    await tester.pump();
    await tester.pump();
    expect(find.byType(UiKitView), findsOneWidget);
    expect(tester.element(find.text('Body')), same(body));
    expect(native.created, hasLength(1));
  });

  _testWidgets('UIKit selection commits once per event and supports reselect', (
    tester,
  ) async {
    final selected = <String>[];
    await pump(tester, config(onSelect: selected.add));
    expect(selected, isEmpty);
    await native.send('select', {'id': '/activity'});
    expect(selected, ['/activity']);
    await tester.pump();
    await native.send('select', {'id': '/activity'});
    expect(selected, ['/activity', '/activity']);
    await tester.pump();
    // The owner did not accept navigation; restore its selectedId.
    expect(native.latest['selectedId'], '/home');
  });

  _testWidgets('selected item tint follows the existing app theme token', (
    tester,
  ) async {
    await pump(tester, config());
    final view = tester.state(find.byType(UiKitView));
    expect(
      native.latest['selectedTintColor'],
      AppThemeData.light.colors.navPanel.activeIcon.toARGB32(),
    );
    await pump(tester, config(), brightness: Brightness.dark);
    expect(
      native.latest['selectedTintColor'],
      AppThemeData.dark.colors.navPanel.activeIcon.toARGB32(),
    );
    expect(tester.state(find.byType(UiKitView)), same(view));
    expect(native.created, hasLength(1));
  });

  _testWidgets(
    'stationary touch reaches UIKit before the global tap detector',
    (tester) async {
      final selected = <String>[];
      var globalTaps = 0;
      await pump(
        tester,
        config(onSelect: selected.add),
        onGlobalTap: () => globalTaps++,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(UiKitView)),
      );
      await tester.pump();
      expect(native.gestureCalls, contains('acceptGesture'));
      await tester.pump(const Duration(seconds: 1));
      expect(selected, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(globalTaps, 0);
      expect(selected, isEmpty);
      // Claiming the pointer starts native interaction, not screen navigation.
      // Only the native delegate's committed selection changes the destination.
      await native.send('select', {'id': '/activity'});
      expect(selected, ['/activity']);
      await tester.pump();
    },
  );

  _testWidgets('a modal barrier still blocks native pointer ownership', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final selected = <String>[];
    var globalTaps = 0;
    await pump(
      tester,
      config(onSelect: selected.add),
      navigatorKey: navigatorKey,
      onGlobalTap: () => globalTaps++,
    );
    final position = tester.getCenter(find.byType(UiKitView));
    unawaited(
      showDialog<void>(
        context: navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Covered')),
      ),
    );
    await tester.pumpAndSettle();
    native.gestureCalls.clear();

    await tester.tapAt(position);
    await tester.pumpAndSettle();
    expect(native.gestureCalls, isNot(contains('acceptGesture')));
    expect(globalTaps, 0);
    expect(selected, isEmpty);
  });

  _testWidgets('hidden native bars do not consume tap-to-unfocus input', (
    tester,
  ) async {
    var globalTaps = 0;
    await pump(tester, config(hidden: true), onGlobalTap: () => globalTaps++);
    await tester.tapAt(tester.getCenter(find.byType(UiKitView)));
    await tester.pump();
    expect(globalTaps, 1);
    expect(native.gestureCalls, isNot(contains('acceptGesture')));
  });

  _testWidgets(
    'selection, labels, theme and RTL preserve the same native view',
    (tester) async {
      var loads = 0;
      Future<Uint8List> loader(AssetBundle bundle, String name, double scale) {
        loads++;
        return _fakeIcon(bundle, name, scale);
      }

      await pump(tester, config(), loader: loader);
      final firstView = tester.state(find.byType(UiKitView));
      await pump(
        tester,
        config(
          selected: '/settings',
          items: [
            for (final item in _items)
              IosNativeTabBarItem(
                id: item.id,
                iconName: item.iconName,
                label: '${item.label} translated',
              ),
          ],
        ),
        loader: loader,
        brightness: Brightness.dark,
        direction: TextDirection.rtl,
      );
      expect(tester.state(find.byType(UiKitView)), same(firstView));
      expect(native.created, hasLength(1));
      expect(loads, _items.length);
      expect(native.latest['selectedId'], '/settings');
      expect(native.latest['brightness'], 'dark');
      expect(native.latest['direction'], 'rtl');
      expect(
        (native.latest['items'] as List).first['label'],
        'Home translated',
      );
    },
  );

  _testWidgets('removed Swap callbacks never select a different index', (
    tester,
  ) async {
    final selected = <String>[];
    await pump(tester, config(onSelect: selected.add));
    await pump(
      tester,
      config(
        items: _items.where((item) => item.id != '/swap').toList(),
        selected: '/activity',
        onSelect: selected.add,
      ),
    );
    await native.send('select', {'id': '/swap'});
    await tester.pump();
    expect(selected, isEmpty);
    expect(native.latest['selectedId'], '/activity');
    await native.send('select', {'id': '/settings'});
    expect(selected, ['/settings']);
  });

  _testWidgets('hidden and keyboard-covered bars reject native callbacks', (
    tester,
  ) async {
    final selected = <String>[];
    await pump(tester, config(onSelect: selected.add, hidden: true));
    expect(native.latest['hidden'], true);
    await native.send('select', {'id': '/settings'});
    expect(selected, isEmpty);
    await pump(tester, config(onSelect: selected.add), keyboard: 300);
    expect(native.latest['hidden'], true);
    await native.send('select', {'id': '/settings'});
    expect(selected, isEmpty);
    await pump(tester, config(onSelect: selected.add));
    expect(native.latest['hidden'], false);
    expect(native.created, hasLength(1));
  });

  _testWidgets('a route pushed over the shell hides and disables native tabs', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final selected = <String>[];
    await tester.pumpWidget(
      _app(
        IosNativeTabBarHost(
          configuration: config(onSelect: selected.add),
          iconLoader: _fakeIcon,
          builder: (_, bar) =>
              Scaffold(body: const Text('Shell'), bottomNavigationBar: bar),
        ),
        navigatorKey: key,
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      key.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Detail'))),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(native.latest['hidden'], true);
    await native.send('select', {'id': '/settings'});
    expect(selected, isEmpty);
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(native.latest['hidden'], false);
    expect(native.created, hasLength(1));
  });

  _testWidgets(
    'native height updates resize the platform view without padding',
    (tester) async {
      await pump(tester, config());
      expect(tester.getSize(find.byType(UiKitView)).height, native.height);
      await native.send('layout', {'height': 101.0});
      await tester.pump();
      expect(tester.getSize(find.byType(UiKitView)).height, 101);
      await native.send('layout', {'height': -1.0});
      await tester.pump();
      expect(tester.getSize(find.byType(UiKitView)).height, 101);
    },
  );

  _testWidgets('disposing while icons load does not mount a late native view', (
    tester,
  ) async {
    final icon = Completer<Uint8List>();
    await pump(tester, config(), loader: (_, _, _) => icon.future);
    await tester.pumpWidget(const SizedBox());
    icon.complete(Uint8List(4));
    await tester.pump();
    expect(native.created, isEmpty);
    expect(tester.takeException(), isNull);
  });

  _testWidgets('obsolete icon loads cannot restore removed destinations', (
    tester,
  ) async {
    final oldIcon = Completer<Uint8List>();
    final newIcon = Completer<Uint8List>();
    Future<Uint8List> loader(AssetBundle _, String name, double _) =>
        name == 'home' ? oldIcon.future : newIcon.future;
    await pump(tester, config(items: [_items.first]), loader: loader);
    await pump(
      tester,
      config(items: [_items.last], selected: '/settings'),
      loader: loader,
    );
    newIcon.complete(Uint8List(4));
    await tester.pump();
    await tester.pump();
    oldIcon.complete(Uint8List(8));
    await tester.pump();
    expect(native.latest['selectedId'], '/settings');
    expect((native.latest['items'] as List).single['id'], '/settings');
    expect(native.created, hasLength(1));
  });

  _testWidgets('AppMobileShell uses native total height at the screen edges', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.viewPadding = FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        AppMobileShell(
          body: const SizedBox.expand(),
          tabBar: AppMobileTabBar(
            items: const [
              AppMobileTabItem(iconName: 'home', label: 'Home'),
              AppMobileTabItem(iconName: 'cog', label: 'Settings'),
            ],
            currentIndex: 0,
            onSelect: (_) {},
          ),
          nativeTabBar: config(items: [_items.first, _items.last]),
        ),
      ),
    );
    // Real SVG decoding/rasterization runs outside the fake async clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump();
    expect(find.byType(UiKitView), findsOneWidget);
    expect(
      tester.getRect(find.byType(UiKitView)),
      Rect.fromLTWH(0, 852 - native.height, 393, native.height),
    );
    expect(find.byType(AppMobileTabBar), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, true);
  });
}

Widget _app(
  Widget home, {
  Brightness brightness = Brightness.light,
  GlobalKey<NavigatorState>? navigatorKey,
  VoidCallback? onGlobalTap,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  theme: ThemeData(brightness: brightness),
  themeAnimationDuration: Duration.zero,
  localizationsDelegates: appLocalizationsDelegates,
  builder: (_, child) => AppTheme(
    data: brightness == Brightness.dark
        ? AppThemeData.dark
        : AppThemeData.light,
    child: onGlobalTap == null
        ? child!
        : GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onGlobalTap,
            child: child!,
          ),
  ),
  home: home,
);

class _NativeFixture {
  _NativeFixture() {
    messenger.setMockMethodCallHandler(IosNativeTabBarHost.channel, (
      call,
    ) async {
      capabilityReads++;
      return {'supported': supported};
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'acceptGesture' || call.method == 'rejectGesture') {
        gestureCalls.add(call.method);
      }
      if (call.method == 'create') {
        final args = call.arguments as Map;
        final id = args['id'] as int;
        final bytes = args['params'] as Uint8List;
        created[id] =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(bytes),
                )
                as Map;
        latest = created[id]!;
        presentations[id] = {
          'visibilityEpoch': latest['visibilityEpoch'],
          'revision': 0,
          'interactive': automaticallyPresent && latest['hidden'] != true,
        };
        final channel = MethodChannel('com.zcash.wallet/native_tab_bar/$id');
        channels[id] = channel;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'update') {
            latest = call.arguments as Map;
            updates.add(Map.of(latest));
            final previous = presentations[id]!;
            if (previous['visibilityEpoch'] != latest['visibilityEpoch']) {
              presentations[id] = {
                'visibilityEpoch': latest['visibilityEpoch'],
                'revision': (previous['revision'] as int) + 1,
                'interactive': automaticallyPresent && latest['hidden'] != true,
              };
              unawaited(send('presentation', presentations[id]!));
            }
            await updateDelay?.future;
          } else if (call.method == 'getHeight') {
            return height;
          } else if (call.method == 'getPresentation') {
            return presentationResponse ?? presentations[id];
          }
          return null;
        });
      }
      return null;
    });
  }

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  bool supported = true;
  int capabilityReads = 0;
  double height = 83;
  bool automaticallyPresent = true;
  Future<Map>? presentationResponse;
  Completer<void>? updateDelay;
  final created = <int, Map>{};
  final presentations = <int, Map>{};
  final updates = <Map>[];
  final gestureCalls = <String>[];
  final channels = <int, MethodChannel>{};
  Map latest = {};

  Future<void> send(String method, Object? arguments) async {
    final channel = channels.values.last;
    if (method == 'select' && arguments is Map) {
      arguments = {...presentations.values.last, ...arguments};
    }
    final complete = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) => complete.complete(),
    );
    await complete.future;
  }

  Future<void> present({
    required bool interactive,
    int? epoch,
    int? revision,
  }) async {
    final id = channels.keys.last;
    final status = {
      'visibilityEpoch': epoch ?? latest['visibilityEpoch'],
      'revision': revision ?? (presentations[id]!['revision'] as int) + 1,
      'interactive': interactive,
    };
    presentations[id] = status;
    await send('presentation', status);
  }

  void dispose() {
    messenger.setMockMethodCallHandler(IosNativeTabBarHost.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels.values) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

void _testWidgets(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: TargetPlatformVariant.only(TargetPlatform.iOS),
);
