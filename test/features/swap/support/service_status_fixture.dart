import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';

class FixtureServiceStatusNotifier extends NearIntentsServiceStatusNotifier {
  FixtureServiceStatusNotifier([this.fixture]);
  final NearIntentsServiceStatus? fixture;
  void publish(NearIntentsServiceStatus value) => state = value;
  @override
  NearIntentsServiceStatus build() =>
      fixture ?? const NearIntentsServiceStatus();
}

Duration Function() fakeServiceElapsed(WidgetTester tester) {
  final start = tester.binding.clock.now();
  return () => tester.binding.clock.now().difference(start);
}

NearIntentsServiceStatus serviceStatusSnapshot({
  required DateTime serverTime,
  List<NearIntentsServiceIssue> incidents = const [],
  List<NearIntentsServiceIssue> maintenance = const [],
  Duration elapsed = Duration.zero,
  Duration receivedAt = Duration.zero,
}) => NearIntentsServiceStatus(
  elapsed: elapsed,
  incidentFeed: NearIntentsServiceObservation(
    feed: NearIntentsServiceFeed(issues: incidents, serverTime: serverTime),
    receivedAt: receivedAt,
  ),
  maintenanceFeed: NearIntentsServiceObservation(
    feed: NearIntentsServiceFeed(issues: maintenance, serverTime: serverTime),
    receivedAt: receivedAt,
  ),
);

NearIntentsServiceStatus serviceStatusFixture({
  bool future = false,
  int windows = 1,
}) {
  final now = DateTime.utc(2026, 11, 3, 10);
  return serviceStatusSnapshot(
    serverTime: now,
    maintenance: [
      for (var i = 0; i < windows; i++)
        NearIntentsServiceIssue(
          chains: const {'*'},
          active: !future,
          startsAt: now.add(Duration(minutes: (future ? 60 : -30) + i)),
          finishesAt: now.add(Duration(minutes: 120 + i)),
        ),
    ],
  );
}
