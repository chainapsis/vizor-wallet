import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/platform/device_power.dart';
import 'package:zcash_wallet/src/providers/sync_scan_slowdown_provider.dart';

void main() {
  late ProviderContainer container;
  late SyncScanSlowdownNotifier slowdown;

  SyncScanSlowdown? state() => container.read(syncScanSlowdownProvider);

  setUp(() {
    container = ProviderContainer();
    slowdown = container.read(syncScanSlowdownProvider.notifier);
  });

  tearDown(() => container.dispose());

  testWidgets('a hot device slows a sync job only after it ran three minutes', (
    tester,
  ) async {
    slowdown
      ..updateDevicePower(SyncScanSlowdown.heat)
      ..updateSyncJob('a', complete: false);
    await tester.pump(kSyncScanSlowdownAfter - const Duration(seconds: 1));
    expect(state(), isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(state(), SyncScanSlowdown.heat);

    slowdown.updateDevicePower(SyncScanSlowdown.powerSaving);
    expect(state(), SyncScanSlowdown.powerSaving);
    slowdown.updateDevicePower(null);
    expect(state(), isNull);
  });

  testWidgets('the same job keeps its clock, and a new one starts over', (
    tester,
  ) async {
    slowdown
      ..updateDevicePower(SyncScanSlowdown.powerSaving)
      ..updateSyncJob('a', complete: false);
    await tester.pump(const Duration(minutes: 2));
    // A retry's states carry the same job, or none before its queue is known.
    slowdown
      ..updateSyncJob('', complete: false)
      ..updateSyncJob('a', complete: false);
    await tester.pump(const Duration(minutes: 1));
    expect(state(), SyncScanSlowdown.powerSaving);

    slowdown.updateSyncJob('b', complete: false);
    expect(state(), isNull);
    await tester.pump(kSyncScanSlowdownAfter);
    expect(state(), SyncScanSlowdown.powerSaving);
  });

  testWidgets('a completed sync stops the clock', (tester) async {
    slowdown
      ..updateDevicePower(SyncScanSlowdown.heat)
      ..updateSyncJob('a', complete: false);
    await tester.pump(kSyncScanSlowdownAfter);
    expect(state(), SyncScanSlowdown.heat);

    slowdown.updateSyncJob('a', complete: true);
    expect(state(), isNull);
    await tester.pump(kSyncScanSlowdownAfter);
    expect(state(), isNull);

    // The next sync is a new job, which starts at full speed.
    slowdown.updateSyncJob('c', complete: false);
    expect(state(), isNull);
    await tester.pump(kSyncScanSlowdownAfter);
    expect(state(), SyncScanSlowdown.heat);
  });
}
