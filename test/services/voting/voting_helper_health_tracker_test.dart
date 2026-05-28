import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_helper_health_tracker.dart';

void main() {
  test('temporarily deprioritizes repeatedly failing helpers', () {
    var now = DateTime.utc(2026, 1, 1);
    final tracker = VotingHelperHealthTracker(
      failureThreshold: 2,
      cooldown: const Duration(seconds: 30),
      now: () => now,
    );
    const servers = ['https://a.example', 'https://b.example'];

    tracker.recordFailure(servers.first);
    expect(tracker.candidateServers(servers), servers);

    tracker.recordFailure(servers.first);
    expect(tracker.candidateServers(servers), [servers.last, servers.first]);

    now = now.add(const Duration(seconds: 31));
    expect(tracker.candidateServers(servers), servers);
  });

  test('falls back to all helpers when every helper is degraded', () {
    final tracker = VotingHelperHealthTracker(failureThreshold: 1);
    const servers = ['https://a.example', 'https://b.example'];

    tracker.recordFailure(servers.first);
    tracker.recordFailure(servers.last);

    expect(tracker.candidateServers(servers), servers);
  });

  test('success closes a helper circuit', () {
    final tracker = VotingHelperHealthTracker(failureThreshold: 1);
    const servers = ['https://a.example', 'https://b.example'];

    tracker.recordFailure(servers.first);
    expect(tracker.candidateServers(servers), [servers.last, servers.first]);

    tracker.recordSuccess(servers.first);
    expect(tracker.candidateServers(servers), servers);
  });
}
