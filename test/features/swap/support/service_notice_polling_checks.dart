import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/route_owned_redirect.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_service_status_client.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/near_intents_service_notice_host.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import 'service_status_fixture.dart';

const _notice = ValueKey('near_intents_service_notice');
const _ok = ValueKey('near_intents_service_notice_ok');

void serviceNoticePollingChecks() {
  testWidgets(
    'retained inactive tabs neither poll nor present service notices',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app(tester));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 35));
      expect(harness.source.calls, 0);
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(harness.source.calls, 1);
      harness.router.go('/home');
      await tester.pumpAndSettle();
      expect(
        find.byType(NearIntentsServiceNoticeHost, skipOffstage: false),
        findsOneWidget,
      );
      expect(harness.source.disposals, 1);
      harness.source.id = 'new-incident';
      await tester.pump(const Duration(seconds: 65));
      await tester.pumpAndSettle();
      expect(harness.source.calls, 1);
      expect(find.byKey(_notice, skipOffstage: false), findsNothing);
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(harness.source.calls, 2);
      expect(find.byKey(_notice), findsOneWidget);
    },
  );

  testWidgets(
    'leaving a retained tab cancels pending queries and ignores late notices',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.source.pending = Completer<NearIntentsServiceFeed>();
      await tester.pumpWidget(harness.app(tester));
      await tester.pumpAndSettle();
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(harness.source.calls, 1);
      harness.router.go('/home');
      await tester.pumpAndSettle();
      expect(harness.source.pendingCancelled, isTrue);
      harness.source.id = 'A';
      harness.source.pending!.complete(harness.source.feed);
      harness.source.pending = null;
      await tester.pumpAndSettle();
      expect(find.byKey(_notice, skipOffstage: false), findsNothing);
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(harness.source.calls, 2);
      expect(find.byKey(_notice), findsOneWidget);
      await tester.tap(find.byKey(_ok));
      await tester.pumpAndSettle();
      harness.router.go('/home');
      await tester.pumpAndSettle();
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(harness.source.calls, 3);
      expect(
        find.byKey(_notice),
        findsNothing,
        reason: 'The retained composer preserves its seen issue IDs',
      );
    },
  );

  testWidgets(
    'a root review route pauses a nested composer and return reloads',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app(tester));
      await tester.pumpAndSettle();
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(harness.source.calls, 1);
      unawaited(harness.router.push<void>('/review'));
      await tester.pumpAndSettle();
      expect(harness.source.disposals, 1);
      await tester.pump(const Duration(seconds: 65));
      expect(harness.source.calls, 1);
      harness.router.pop();
      await tester.pumpAndSettle();
      expect(harness.source.calls, 2);
    },
  );

  testWidgets(
    'another transparent modal pauses polling without losing the composer',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app(tester));
      await tester.pumpAndSettle();
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      final context = harness.root.currentState!.context;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Other modal')),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.source.disposals, 1);
      await tester.pump(const Duration(seconds: 65));
      expect(harness.source.calls, 1);
      harness.root.currentState!.pop();
      await tester.pumpAndSettle();
      expect(harness.source.calls, 2);
    },
  );

  testWidgets(
    'first-step and inline-modal flags control subscription lifetime',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app(tester));
      await tester.pumpAndSettle();
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      harness.availability.value = (enabled: false, blocked: false);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 65));
      expect(harness.source.calls, 1);
      harness.availability.value = (enabled: true, blocked: false);
      await tester.pumpAndSettle();
      expect(harness.source.calls, 2);
      harness.availability.value = (enabled: true, blocked: true);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 65));
      expect(harness.source.calls, 2);
      harness.availability.value = (enabled: true, blocked: false);
      await tester.pumpAndSettle();
      expect(harness.source.calls, 3);
    },
  );

  testWidgets(
    'own notice presentation and dismissal keep the same polling subscription',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.source.id = 'A';
      await tester.pumpWidget(harness.app(tester));
      await tester.pumpAndSettle();
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(find.byKey(_notice), findsOneWidget);
      expect(harness.source.calls, 1);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(harness.source.calls, 2);
      await tester.tap(find.byKey(_ok));
      await tester.pumpAndSettle();
      expect(harness.source.calls, 2);
      expect(harness.source.disposals, 0);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(harness.source.calls, 3);
      expect(find.byKey(_notice), findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'changing tabs removes an owned notice without showing it over home',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.source.id = 'A';
      await tester.pumpWidget(harness.app(tester));
      await tester.pumpAndSettle();
      harness.router.go('/swap');
      await tester.pumpAndSettle();
      expect(find.byKey(_notice), findsOneWidget);
      harness.router.go('/home');
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(_notice, skipOffstage: false), findsNothing);
      await tester.pump(const Duration(seconds: 65));
      expect(harness.source.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Harness {
  final source = _Source();
  final root = GlobalKey<NavigatorState>();
  final availability = ValueNotifier((enabled: true, blocked: false));
  late final router = GoRouter(
    navigatorKey: root,
    initialLocation: '/home',
    observers: [RouteOwnedNavigationObserver()],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const Center(child: Text('Home')),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/swap',
                builder: (_, _) => ValueListenableBuilder(
                  valueListenable: availability,
                  builder: (_, value, _) => NearIntentsServiceNoticeHost(
                    direction: SwapDirection.zecToExternal,
                    externalAsset: SwapAsset.usdc,
                    enabled: value.enabled,
                    blocked: value.blocked,
                    child: const Center(child: Text('Composer')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/review',
        builder: (_, _) => const Scaffold(body: Text('Review')),
      ),
    ],
  );
  Widget app(WidgetTester tester) => ProviderScope(
    overrides: [
      nearIntentsServiceStatusSourceProvider.overrideWith((ref) {
        ref.onDispose(() => source.disposals++);
        return source;
      }),
      nearIntentsServiceElapsedProvider.overrideWithValue(
        fakeServiceElapsed(tester),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: appLocalizationsDelegates,
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    ),
  );
  void dispose() {
    router.dispose();
    availability.dispose();
  }
}

class _Source implements NearIntentsServiceStatusSource {
  int calls = 0;
  int disposals = 0;
  String? id;
  bool pendingCancelled = false;
  Completer<NearIntentsServiceFeed>? pending;
  NearIntentsServiceFeed get feed => NearIntentsServiceFeed(
    serverTime: DateTime.utc(2100),
    issues: [
      if (id != null) NearIntentsServiceIssue(id: id, chains: const {'*'}),
    ],
  );
  @override
  Future<NearIntentsServiceFeed> loadIncidents({
    Future<void>? cancelSignal,
  }) async {
    calls++;
    if (pending != null) {
      unawaited(cancelSignal?.then((_) => pendingCancelled = true));
      return pending!.future;
    }
    return feed;
  }

  @override
  Future<NearIntentsServiceFeed> loadMaintenance({
    Future<void>? cancelSignal,
  }) async =>
      NearIntentsServiceFeed(serverTime: DateTime.utc(2100), issues: const []);
}
