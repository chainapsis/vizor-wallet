import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';

class FixtureServiceStatusNotifier extends NearIntentsServiceStatusNotifier {
  FixtureServiceStatusNotifier([this.fixture]);
  final NearIntentsServiceStatus? fixture;

  void publish(NearIntentsServiceStatus value) => state = value;

  @override
  NearIntentsServiceStatus build() =>
      fixture ?? NearIntentsServiceStatus(now: DateTime.utc(2026, 11, 3));
}

NearIntentsServiceStatus serviceStatusFixture({
  bool future = false,
  int windows = 1,
}) {
  final now = DateTime.utc(2026, 11, 3, 10);
  return NearIntentsServiceStatus(
    now: now,
    maintenanceFetchedAt: now,
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
