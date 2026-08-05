import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/windows_update_provider.dart';
import 'package:zcash_wallet/src/services/windows_update_service.dart';

void main() {
  test('download preserves the native Windows update failure detail', () async {
    final service = _FakeWindowsUpdateService(
      downloadResult: _snapshot(
        status: 'failed',
        message: 'Signed feed verification failed.',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        windowsUpdateTorEnabledProvider.overrideWithValue(() => false),
        windowsUpdateServiceProvider.overrideWithValue(service),
        windowsUpdateProvider.overrideWith(_AvailableWindowsUpdateNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(windowsUpdateProvider.notifier)
        .downloadUpdate();

    expect(result.started, isFalse);
    expect(result.message, 'Signed feed verification failed.');
    expect(
      container.read(windowsUpdateProvider).message,
      'Signed feed verification failed.',
    );
    expect(service.downloadCalls, 1);
  });

  test(
    'download stays blocked while the Tor updater proxy is not ready',
    () async {
      final service = _FakeWindowsUpdateService(
        stateResult: _snapshot(status: 'available', torProxyReady: false),
      );
      final container = ProviderContainer(
        overrides: [
          windowsUpdateTorEnabledProvider.overrideWithValue(() => true),
          windowsUpdateServiceProvider.overrideWithValue(service),
          windowsUpdateProvider.overrideWith(
            _AvailableWindowsUpdateNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(windowsUpdateProvider.notifier)
          .downloadUpdate();

      expect(result.started, isFalse);
      expect(result.message, kWindowsTorUpdateRouteUnavailableMessage);
      expect(service.downloadCalls, 0);
    },
  );

  test(
    'download reads the current Tor route after switching to direct',
    () async {
      var torEnabled = true;
      var routeReads = 0;
      final service = _FakeWindowsUpdateService(
        stateResult: _snapshot(status: 'available', torProxyReady: false),
      );
      final container = ProviderContainer(
        overrides: [
          windowsUpdateTorEnabledProvider.overrideWithValue(() {
            routeReads++;
            return torEnabled;
          }),
          windowsUpdateServiceProvider.overrideWithValue(service),
          windowsUpdateProvider.overrideWith(
            _AvailableWindowsUpdateNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final torResult = await container
          .read(windowsUpdateProvider.notifier)
          .downloadUpdate();
      expect(torResult.started, isFalse);
      expect(service.downloadCalls, 0);

      torEnabled = false;
      final directResult = await container
          .read(windowsUpdateProvider.notifier)
          .downloadUpdate();

      expect(directResult.started, isTrue);
      expect(service.downloadCalls, 1);
      expect(routeReads, 2);
    },
  );
}

class _AvailableWindowsUpdateNotifier extends WindowsUpdateNotifier {
  @override
  WindowsUpdateState build() => const WindowsUpdateState(
    supported: true,
    status: WindowsUpdateStatus.available,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: 0,
    pendingRestart: false,
    torProxyReady: false,
    message: '',
  );
}

class _FakeWindowsUpdateService extends WindowsUpdateService {
  _FakeWindowsUpdateService({this.stateResult, this.downloadResult});

  final WindowsUpdateSnapshot? stateResult;
  final WindowsUpdateSnapshot? downloadResult;
  var downloadCalls = 0;

  @override
  Future<WindowsUpdateSnapshot> getState() async =>
      stateResult ?? _snapshot(status: 'available', torProxyReady: true);

  @override
  Future<WindowsUpdateSnapshot> downloadUpdate() async {
    downloadCalls++;
    return downloadResult ?? _snapshot(status: 'downloading');
  }
}

WindowsUpdateSnapshot _snapshot({
  required String status,
  bool torProxyReady = false,
  String message = '',
}) {
  return WindowsUpdateSnapshot(
    supported: true,
    busy: status == 'downloading',
    status: status,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: status == 'downloading' ? 1 : 0,
    pendingRestart: false,
    torProxyReady: torProxyReady,
    message: message,
  );
}
