@Tags(['mobile'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_restorer_provider.dart';

void main() {
  test('mobile builds do not start desktop vote share recovery', () async {
    var discoveryCount = 0;
    final container = ProviderContainer(
      overrides: [
        votingPendingShareRoundLoaderProvider.overrideWithValue(({
          required dbPath,
          required accountUuids,
        }) async {
          discoveryCount++;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);

    final restorer = container.read(votingShareTrackingRestorerProvider);
    await restorer.restore();
    await restorer.pause();
    await restorer.resume();
    await pumpEventQueue();

    expect(discoveryCount, 0);
  });
}
