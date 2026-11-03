import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_service_status_client.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';

void main() {
  testWidgets(
    'independent failures remove old feed but preserve valid other feed',
    (tester) async {
      final source = _Source();
      final container = ProviderContainer(
        overrides: [
          nearIntentsServiceStatusSourceProvider.overrideWithValue(source),
          nearIntentsServiceStatusClockProvider.overrideWithValue(
            tester.binding.clock.now,
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
      expect(state.incidentsFetchedAt, isNull);
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
    final source = _Source()..gate = Completer<List<NearIntentsServiceIssue>>();
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
    source.gate!.complete([
      const NearIntentsServiceIssue(chains: {'*'}),
    ]);
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
  testWidgets('time boundaries refresh presentation without waiting for HTTP', (
    tester,
  ) async {
    final now = tester.binding.clock.now();
    final source = _Source()
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
        nearIntentsServiceStatusClockProvider.overrideWithValue(
          tester.binding.clock.now,
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
  Completer<List<NearIntentsServiceIssue>>? gate;
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
  Future<List<NearIntentsServiceIssue>> loadIncidents({
    Future<void>? cancelSignal,
  }) async {
    incidentCalls++;
    if (failIncidents) throw const FormatException('Invalid JSON');
    return gate?.future ?? Future.value(incidents);
  }

  @override
  Future<List<NearIntentsServiceIssue>> loadMaintenance({
    Future<void>? cancelSignal,
  }) async {
    maintenanceCalls++;
    if (failMaintenance) throw Exception('HTTP failure');
    return maintenance;
  }
}
