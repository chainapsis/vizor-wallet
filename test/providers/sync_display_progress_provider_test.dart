import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_display_progress_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../fakes/fake_sync_notifier.dart';

void main() {
  test('interpolates without republishing SyncState', () async {
    final initial = SyncState(
      isSyncing: true,
      percentage: 0.2,
      displayTargetPercentage: 0.3,
      displayTargetBlocks: 10,
    );
    late FakeSyncNotifier syncNotifier;
    final container = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(
          () => syncNotifier = FakeSyncNotifier(initial),
        ),
      ],
    );
    addTearDown(container.dispose);
    final displaySubscription = container.listen(
      syncDisplayPercentageProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(displaySubscription.close);
    await container.read(syncProvider.future);
    await Future<void>.delayed(Duration.zero);

    var syncUpdates = 0;
    final syncSubscription = container.listen(syncProvider, (_, _) {
      syncUpdates += 1;
    });
    addTearDown(syncSubscription.close);

    expect(container.read(syncDisplayPercentageProvider), 0.2);
    await Future<void>.delayed(const Duration(milliseconds: 110));

    expect(container.read(syncDisplayPercentageProvider), closeTo(0.25, 0.011));
    expect(container.read(syncProvider).requireValue.percentage, 0.2);
    expect(syncUpdates, 0);

    syncNotifier.emit(
      initial.copyWith(
        isSyncing: false,
        isSyncComplete: true,
        percentage: 1,
        displayTargetPercentage: 1,
        displayTargetBlocks: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(syncDisplayPercentageProvider), 1);
  });

  test('whole percentage notifies only when its label changes', () async {
    final initial = SyncState(
      isSyncing: true,
      percentage: 0.2,
      displayTargetPercentage: 0.3,
      displayTargetBlocks: 100,
    );
    final container = ProviderContainer(
      overrides: [syncProvider.overrideWith(() => FakeSyncNotifier(initial))],
    );
    addTearDown(container.dispose);
    var updates = 0;
    final subscription = container.listen(
      syncDisplayWholePercentageProvider,
      (_, _) => updates += 1,
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    await Future<void>.delayed(Duration.zero);
    final initialUpdates = updates;

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(container.read(syncDisplayWholePercentageProvider), 20);
    expect(updates, initialUpdates);
  });
}
