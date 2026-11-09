import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/navigation/route_owned_redirect.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_service_status_client.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/near_intents_service_notice.dart';
import 'package:zcash_wallet/src/features/swap/widgets/near_intents_service_notice_host.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import 'service_status_fixture.dart';
import 'service_notice_polling_checks.dart';

const _modal = ValueKey('near_intents_service_notice');
const _ok = ValueKey('near_intents_service_notice_ok');
NearIntentsServiceStatus _incident(String id, {String chain = '*'}) {
  final now = DateTime.utc(2026, 11, 3);
  return serviceStatusSnapshot(
    serverTime: now,
    incidents: [
      NearIntentsServiceIssue(chains: {chain}, id: id),
    ],
  );
}

Widget _app({
  NearIntentsServiceStatus? status,
  GlobalKey<NavigatorState>? navigator,
  Widget? page,
  ServiceStatusPageLauncher? launcher,
  bool nested = false,
  _TrackingSource? source,
  Duration Function()? clock,
}) {
  final content =
      page ??
      const NearIntentsServiceNoticeHost(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        child: Center(child: Text('Composer')),
      );
  return ProviderScope(
    overrides: [
      if (source == null)
        nearIntentsServiceStatusProvider.overrideWith(
          () => FixtureServiceStatusNotifier(status),
        )
      else
        nearIntentsServiceStatusSourceProvider.overrideWith((ref) {
          ref.onDispose(() => source.disposed = true);
          return source;
        }),
      if (clock != null)
        nearIntentsServiceElapsedProvider.overrideWithValue(clock),
      if (launcher != null)
        nearIntentsServiceStatusPageLauncherProvider.overrideWithValue(
          launcher,
        ),
    ],
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      navigatorKey: navigator,
      navigatorObservers: [RouteOwnedNavigationObserver()],
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      home: Scaffold(
        body: nested
            ? Navigator(
                observers: [RouteOwnedNavigationObserver()],
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: (_) => content),
              )
            : content,
      ),
    ),
  );
}

FixtureServiceStatusNotifier _notifier(WidgetTester tester) =>
    ProviderScope.containerOf(
          tester.element(
            find
                .byType(NearIntentsServiceNoticeHost, skipOffstage: false)
                .first,
          ),
        ).read(nearIntentsServiceStatusProvider.notifier)
        as FixtureServiceStatusNotifier;

void serviceNoticeWidgetChecks() {
  serviceNoticePollingChecks();
  testWidgets(
    'maintenance times identify their scope alongside an independent incident',
    (tester) async {
      final original = serviceStatusFixture();
      final window = original.maintenance.single;
      await tester.pumpWidget(
        _app(
          status: serviceStatusSnapshot(
            serverTime: original.maintenanceFeed!.feed.serverTime,
            incidents: const [
              NearIntentsServiceIssue(id: 'outage', chains: {'*'}),
            ],
            maintenance: [
              NearIntentsServiceIssue(
                chains: {'eth'},
                startsAt: window.startsAt,
                finishesAt: window.finishesAt,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Service notice'), findsOneWidget);
      expect(find.text('Maintenance window: Ethereum'), findsOneWidget);
      expect(find.text('All chains'), findsOneWidget);
      expect(find.textContaining('Expected end:'), findsOneWidget);
    },
  );

  testWidgets(
    'removing a composer removes its owned modal without changing its replacement',
    (tester) async {
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        _app(
          status: _incident('A'),
          page: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return visible
                  ? const NearIntentsServiceNoticeHost(
                      direction: SwapDirection.zecToExternal,
                      externalAsset: SwapAsset.usdc,
                      child: Text('Composer'),
                    )
                  : const Text('Replacement');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsOneWidget);
      update(() => visible = false);
      await tester.pumpAndSettle();
      expect(find.text('Replacement'), findsOneWidget);
      expect(find.byKey(_modal), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'polling stays alive under its own modal; background clears it without re-alerting on resume',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final source = _TrackingSource();
      await tester.pumpWidget(
        _app(source: source, clock: fakeServiceElapsed(tester)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(source.calls, 2);
      expect(source.disposed, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsNothing);
      // Paused apps stop rendering frames; validate cleared provider data
      // rather than expecting a new frame while the renderer is suspended.
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NearIntentsServiceNoticeHost)),
      );
      expect(
        container.read(nearIntentsServiceStatusProvider).incidents,
        isEmpty,
      );
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(source.calls, 3);
      expect(find.byKey(_modal), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(source.disposed, isTrue);
    },
  );

  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    testWidgets(
      'modal scrolls long windows and enlarged text in ${identical(theme, AppThemeData.dark) ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            home: AppTheme(
              data: theme,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 568),
                  textScaler: TextScaler.linear(1.6),
                ),
                child: NearIntentsServiceNoticeModal(
                  notice: serviceStatusFixture(
                    windows: 5,
                  ).noticeFor(inputChain: 'zec', outputChain: 'eth')!,
                  onClose: () {},
                  onDetails: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_ok).hitTestable(), findsOneWidget);
        expect(find.textContaining('delays'), findsNothing);
        expect(find.textContaining('Start:'), findsNWidgets(5));
        expect(find.textContaining('(UTC'), findsNWidgets(10));
        final logo = find.byWidgetPredicate(
          (widget) =>
              widget is SvgPicture && widget.semanticsLabel == 'NEAR Intents',
        );
        await tester.ensureVisible(logo);
        await tester.pumpAndSettle();
        final bodyRect = tester.getRect(
          find.byKey(const ValueKey('near_intents_service_notice_body')),
        );
        expect(tester.getRect(logo).top, greaterThanOrEqualTo(bodyRect.top));
        expect(
          tester.getRect(logo).bottom,
          lessThanOrEqualTo(bodyRect.bottom + 0.01),
        );
        expect(find.byKey(_ok).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('incident has no invented times and opens the fixed status URL', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      _app(
        status: _incident('A'),
        launcher: (uri) async {
          opened = uri;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Service notice'), findsOneWidget);
    expect(find.text('Swaps may not work right now.'), findsOneWidget);
    expect(find.textContaining('Start:'), findsNothing);
    expect(find.textContaining('Expected end:'), findsNothing);
    expect(find.text('All chains'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('near_intents_service_notice_details')),
    );
    await tester.pumpAndSettle();
    expect(
      opened.toString(),
      'https://partners.near-intents.org/shield/status',
    );
    await tester.tap(find.byKey(_ok));
    await tester.pumpAndSettle();
    expect(find.byKey(_modal), findsNothing);
  });

  testWidgets(
    'polling, failures and recovery do not reopen a dismissed incident; a new ID does',
    (tester) async {
      await tester.pumpWidget(_app(status: _incident('A')));
      await tester.pumpAndSettle();
      final notifier = _notifier(tester);
      await tester.tap(find.byKey(_ok));
      await tester.pumpAndSettle();
      for (final status in [
        _incident('A'),
        const NearIntentsServiceStatus(),
        _incident('A'),
      ]) {
        notifier.publish(status);
        await tester.pumpAndSettle();
        expect(find.byKey(_modal), findsNothing);
      }
      notifier.publish(_incident('B'));
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsOneWidget);
      notifier.publish(const NearIntentsServiceStatus());
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsNothing);
      expect(find.text('Composer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future schedules stay hidden and current maintenance updates while open',
    (tester) async {
      await tester.pumpWidget(_app(status: serviceStatusFixture(future: true)));
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsNothing);
      final notifier = _notifier(tester);
      notifier.publish(serviceStatusFixture());
      await tester.pumpAndSettle();
      expect(find.text('Maintenance notice'), findsOneWidget);
      final original = serviceStatusFixture();
      final window = original.maintenance.single;
      notifier.publish(
        serviceStatusSnapshot(
          serverTime: original.maintenanceFeed!.feed.serverTime,
          maintenance: [
            NearIntentsServiceIssue(
              chains: window.chains,
              startsAt: window.startsAt,
              finishesAt: window.finishesAt!.add(const Duration(hours: 1)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Expected end: ${formatNearIntentsServiceTime(window.finishesAt!.add(const Duration(hours: 1)))}',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(_ok));
      await tester.pumpAndSettle();
      notifier.publish(original);
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsNothing);
    },
  );

  testWidgets(
    'unrelated chains stay hidden and a chain change can reveal an issue',
    (tester) async {
      var asset = SwapAsset.sol;
      late StateSetter update;
      await tester.pumpWidget(
        _app(
          status: _incident('A', chain: 'eth'),
          page: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return NearIntentsServiceNoticeHost(
                direction: SwapDirection.zecToExternal,
                externalAsset: asset,
                child: const Text('Composer'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsNothing);
      update(() => asset = SwapAsset.eth);
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsOneWidget);
      expect(find.text('Ethereum'), findsOneWidget);
      update(() => asset = SwapAsset.sol);
      await tester.pumpAndSettle();
      expect(find.byKey(_modal), findsNothing);
    },
  );

  testWidgets('a root route above a nested composer prevents notice stacking', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final source = _TrackingSource()..id = null;
    await tester.pumpWidget(
      _app(
        navigator: navigator,
        nested: true,
        source: source,
        clock: fakeServiceElapsed(tester),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Review')),
      ),
    );
    await tester.pumpAndSettle();
    source.id = 'A';
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(source.calls, 1);
    expect(find.byKey(_modal, skipOffstage: false), findsNothing);
    expect(find.text('Review'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(_modal), findsOneWidget);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Review again')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review again'), findsOneWidget);
    expect(find.byKey(_modal, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'local maintenance time includes date, 24-hour time and a numeric zone',
    () {
      final time = DateTime(2026, 11, 4, 0, 15);
      expect(
        formatNearIntentsServiceTime(time),
        matches(r'^2026-11-04 00:15 \(UTC[+-]\d{2}:\d{2}\)$'),
      );
    },
  );
}

class _TrackingSource implements NearIntentsServiceStatusSource {
  int calls = 0;
  String? id = 'A';
  bool disposed = false;
  @override
  Future<NearIntentsServiceFeed> loadIncidents({
    Future<void>? cancelSignal,
  }) async {
    calls++;
    return NearIntentsServiceFeed(
      serverTime: DateTime.utc(2026, 11, 3),
      issues: [
        if (id != null) NearIntentsServiceIssue(id: id, chains: const {'*'}),
      ],
    );
  }

  @override
  Future<NearIntentsServiceFeed> loadMaintenance({
    Future<void>? cancelSignal,
  }) async => NearIntentsServiceFeed(
    serverTime: DateTime.utc(2026, 11, 3),
    issues: const [],
  );
}
