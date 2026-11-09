import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_service_status_client.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';

import 'support/service_status_fixture.dart';

void main() {
  testWidgets(
    'independent failures remove old feed but preserve valid other feed',
    (tester) async {
      final source = _Source();
      final container = ProviderContainer(
        overrides: [
          nearIntentsServiceStatusSourceProvider.overrideWithValue(source),
          nearIntentsServiceElapsedProvider.overrideWithValue(
            fakeServiceElapsed(tester),
          ),
        ],
      );
      final sub = container.listen(nearIntentsServiceStatusProvider, (_, _) {});
      addTearDown(() {
        sub.close();
        container.dispose();
      });
      await tester.pump();
      expect(
        container.read(nearIntentsServiceStatusProvider).incidents,
        isNotEmpty,
      );
      expect(
        container.read(nearIntentsServiceStatusProvider).maintenance,
        isNotEmpty,
      );
      source.failIncidents = true;
      await container.read(nearIntentsServiceStatusProvider.notifier).refresh();
      var state = container.read(nearIntentsServiceStatusProvider);
      expect(state.incidents, isEmpty);
      expect(state.incidentFeed, isNull);
      expect(state.maintenance, isNotEmpty);
      source.failMaintenance = true;
      await container.read(nearIntentsServiceStatusProvider.notifier).refresh();
      state = container.read(nearIntentsServiceStatusProvider);
      expect(state.noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
      source.failIncidents = false;
      source.failMaintenance = false;
      await container.read(nearIntentsServiceStatusProvider.notifier).refresh();
      expect(
        container.read(nearIntentsServiceStatusProvider).incidents,
        isNotEmpty,
      );
      container.dispose();
    },
  );
  testWidgets('multiple readers share polling; disposal cancels it', (
    tester,
  ) async {
    final source = _Source();
    var sourceDisposals = 0;
    final container = ProviderContainer(
      overrides: [
        nearIntentsServiceStatusSourceProvider.overrideWith((ref) {
          ref.onDispose(() => sourceDisposals++);
          return source;
        }),
      ],
    );
    final a = container.listen(nearIntentsServiceStatusProvider, (_, _) {});
    final b = container.listen(nearIntentsServiceStatusProvider, (_, _) {});
    await tester.pump();
    await tester.pump();
    expect(sourceDisposals, 0);
    expect(source.incidentCalls, 1);
    expect(source.maintenanceCalls, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(source.incidentCalls, 2);
    a.close();
    b.close();
    container.dispose();
    expect(sourceDisposals, 1);
    await tester.pump(const Duration(seconds: 60));
    expect(source.incidentCalls, 2);
  });
  testWidgets('background cancels and drops late responses; resume reloads', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final source = _Source()..gate = Completer<NearIntentsServiceFeed>();
    final container = ProviderContainer(
      overrides: [
        nearIntentsServiceStatusSourceProvider.overrideWithValue(source),
      ],
    );
    final sub = container.listen(nearIntentsServiceStatusProvider, (_, _) {});
    addTearDown(() {
      sub.close();
      container.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pump();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    source.gate!.complete(
      NearIntentsServiceFeed(
        serverTime: source.serverTime,
        issues: const [
          NearIntentsServiceIssue(chains: {'*'}),
        ],
      ),
    );
    await tester.pump();
    expect(container.read(nearIntentsServiceStatusProvider).incidents, isEmpty);
    expect(
      container.read(nearIntentsServiceStatusProvider).maintenance,
      isEmpty,
    );
    final calls = source.incidentCalls;
    await tester.pump(const Duration(seconds: 30));
    expect(source.incidentCalls, calls);
    source.gate = null;
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(source.incidentCalls, calls + 1);
    expect(
      container.read(nearIntentsServiceStatusProvider).incidents,
      isNotEmpty,
    );
    container.dispose();
  });
  testWidgets(
    'monotonic expiry still clears notices while the next requests are pending',
    (tester) async {
      final source = _Source();
      final container = ProviderContainer(
        overrides: [
          nearIntentsServiceStatusSourceProvider.overrideWithValue(source),
          nearIntentsServiceElapsedProvider.overrideWithValue(
            fakeServiceElapsed(tester),
          ),
        ],
      );
      final sub = container.listen(nearIntentsServiceStatusProvider, (_, _) {});
      addTearDown(() {
        sub.close();
        container.dispose();
      });
      NearIntentsServiceStatus status() =>
          container.read(nearIntentsServiceStatusProvider);
      await tester.pump();
      expect(
        status().noticeFor(inputChain: 'zec', outputChain: 'eth'),
        isNotNull,
      );
      source.gate = Completer<NearIntentsServiceFeed>();
      source.maintenanceGate = Completer<NearIntentsServiceFeed>();
      await tester.pump(const Duration(seconds: 30));
      expect(source.incidentCalls, 2);
      await tester.pump(const Duration(seconds: 29));
      expect(
        status().noticeFor(inputChain: 'zec', outputChain: 'eth'),
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(status().elapsed, const Duration(seconds: 60));
      expect(status().noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
      // Disposed/background generations must also ignore the late timed responses.
      container.dispose();
      final late = NearIntentsServiceFeed(
        serverTime: DateTime.utc(2100),
        issues: const [
          NearIntentsServiceIssue(chains: {'*'}),
        ],
      );
      source.gate!.complete(late);
      source.maintenanceGate!.complete(late);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('time boundaries refresh presentation without waiting for HTTP', (
    tester,
  ) async {
    final now = DateTime.utc(2100, 1, 1);
    final source = _Source()
      ..serverTime = now
      ..incidents = []
      ..maintenance = [
        NearIntentsServiceIssue(
          chains: {'*'},
          startsAt: now.add(const Duration(seconds: 1)),
          finishesAt: now.add(const Duration(seconds: 2)),
        ),
      ];
    final container = ProviderContainer(
      overrides: [
        nearIntentsServiceStatusSourceProvider.overrideWithValue(source),
        nearIntentsServiceElapsedProvider.overrideWithValue(
          fakeServiceElapsed(tester),
        ),
      ],
    );
    final sub = container.listen(nearIntentsServiceStatusProvider, (_, _) {});
    addTearDown(() {
      sub.close();
      container.dispose();
    });
    await tester.pump();
    NearIntentsServiceNoticeData? notice() => container
        .read(nearIntentsServiceStatusProvider)
        .noticeFor(inputChain: 'zec', outputChain: 'eth');
    expect(notice(), isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(notice(), isNotNull);
    await tester.pump(const Duration(seconds: 1));
    expect(notice(), isNull);
    expect(source.incidentCalls, 1);
    container.dispose();
  });
}

class _Source implements NearIntentsServiceStatusSource {
  var incidentCalls = 0;
  var maintenanceCalls = 0;
  var failIncidents = false;
  var failMaintenance = false;
  Completer<NearIntentsServiceFeed>? gate;
  Completer<NearIntentsServiceFeed>? maintenanceGate;
  DateTime serverTime = DateTime.utc(2026, 11, 2, 13);
  List<NearIntentsServiceIssue> incidents = [
    const NearIntentsServiceIssue(chains: {'*'}),
  ];
  List<NearIntentsServiceIssue> maintenance = [
    NearIntentsServiceIssue(
      chains: {'eth'},
      startsAt: DateTime.utc(2026, 11, 2),
      finishesAt: DateTime.utc(2026, 11, 3),
    ),
  ];
  @override
  Future<NearIntentsServiceFeed> loadIncidents({
    Future<void>? cancelSignal,
  }) async {
    incidentCalls++;
    if (failIncidents) throw const FormatException('Invalid JSON');
    return gate?.future ??
        Future.value(
          NearIntentsServiceFeed(issues: incidents, serverTime: serverTime),
        );
  }

  @override
  Future<NearIntentsServiceFeed> loadMaintenance({
    Future<void>? cancelSignal,
  }) async {
    maintenanceCalls++;
    if (failMaintenance) throw Exception('HTTP failure');
    return maintenanceGate?.future ??
        NearIntentsServiceFeed(issues: maintenance, serverTime: serverTime);
  }
}
