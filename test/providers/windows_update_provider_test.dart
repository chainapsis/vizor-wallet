import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/windows_update_provider.dart';
import 'package:zcash_wallet/src/services/windows_update_service.dart';

void main() {
  test('an automatic startup check survives a native failure', () async {
    final service = _FakeWindowsUpdateService(
      checkError: PlatformException(code: 'feed_unreachable'),
    );
    final container = ProviderContainer(
      overrides: [
        windowsUpdateTorEnabledProvider.overrideWithValue(() => false),
        windowsUpdateServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(windowsUpdateProvider.notifier);

    // Callers start this unawaited; an escaping error would be unhandled.
    await notifier.runStartupCheck();

    final state = container.read(windowsUpdateProvider);
    expect(state.status, WindowsUpdateStatus.failed);
    // Nothing the user asked for, so the prompt must not interrupt them.
    expect(state.failure?.userInitiated, isFalse);
    expect(service.checkCalls, 1);

    // The spent check must be retryable once the route recovers.
    await notifier.runStartupCheck();
    expect(service.checkCalls, 2);
  });

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

  test('download reports a reserved native route as not started', () async {
    final service = _FakeWindowsUpdateService(
      downloadError: PlatformException(
        code: 'update_route_transition',
        message: 'Software update routing is changing.',
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
    expect(result.message, 'Software update routing is changing.');
    expect(
      container.read(windowsUpdateProvider).status,
      WindowsUpdateStatus.failed,
    );
  });

  test('check surfaces a reserved native route', () async {
    final service = _FakeWindowsUpdateService(
      checkError: PlatformException(
        code: 'update_route_transition',
        message: 'Software update routing is changing.',
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

    await container.read(windowsUpdateProvider.notifier).checkForUpdates();

    expect(
      container.read(windowsUpdateProvider).message,
      'Software update routing is changing.',
    );
  });

  test('apply surfaces a reserved native route', () async {
    final service = _FakeWindowsUpdateService(
      applyError: PlatformException(
        code: 'update_route_transition',
        message: 'Software update routing is changing.',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        windowsUpdateTorEnabledProvider.overrideWithValue(() => false),
        windowsUpdateServiceProvider.overrideWithValue(service),
        windowsUpdateProvider.overrideWith(_ReadyWindowsUpdateNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(windowsUpdateProvider.notifier)
        .applyUpdateAndRestart();

    expect(
      container.read(windowsUpdateProvider).message,
      'Software update routing is changing.',
    );
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

  test('download maps an unexpected failure to update copy', () async {
    final service = _FakeWindowsUpdateService(
      downloadError: StateError(
        'SocketException: connection refused (127.0.0.1:9150)',
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
    expect(result.message, kWindowsUpdateGenericFailureMessage);
    expect(
      container.read(windowsUpdateProvider).message,
      kWindowsUpdateGenericFailureMessage,
    );
  });

  test('download keeps a native failure message from the updater', () async {
    final service = _FakeWindowsUpdateService(
      downloadError: PlatformException(
        code: 'update_failed',
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

    expect(result.message, 'Signed feed verification failed.');
  });

  test('check reports the blocked Tor update route', () async {
    final service = _FakeWindowsUpdateService(
      stateResult: _snapshot(status: 'available', torProxyReady: false),
    );
    final container = ProviderContainer(
      overrides: [
        windowsUpdateTorEnabledProvider.overrideWithValue(() => true),
        windowsUpdateServiceProvider.overrideWithValue(service),
        windowsUpdateProvider.overrideWith(_AvailableWindowsUpdateNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(windowsUpdateProvider.notifier).checkForUpdates();

    final state = container.read(windowsUpdateProvider);
    expect(state.status, WindowsUpdateStatus.failed);
    expect(state.message, kWindowsTorUpdateRouteUnavailableMessage);
    expect(state.canCheck, isTrue);
    expect(service.checkCalls, 0);
  });

  test('check runs once the Tor updater proxy is ready', () async {
    final service = _FakeWindowsUpdateService(
      stateResult: _snapshot(status: 'available', torProxyReady: true),
      checkResult: _snapshot(status: 'noUpdate', torProxyReady: true),
    );
    final container = ProviderContainer(
      overrides: [
        windowsUpdateTorEnabledProvider.overrideWithValue(() => true),
        windowsUpdateServiceProvider.overrideWithValue(service),
        windowsUpdateProvider.overrideWith(_AvailableWindowsUpdateNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(windowsUpdateProvider.notifier).checkForUpdates();

    expect(
      container.read(windowsUpdateProvider).status,
      WindowsUpdateStatus.noUpdate,
    );
    expect(service.checkCalls, 1);
  });

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

class _ReadyWindowsUpdateNotifier extends WindowsUpdateNotifier {
  @override
  WindowsUpdateState build() => const WindowsUpdateState(
    supported: true,
    status: WindowsUpdateStatus.ready,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: 100,
    pendingRestart: true,
    torProxyReady: false,
    message: '',
  );
}

class _FakeWindowsUpdateService extends WindowsUpdateService {
  _FakeWindowsUpdateService({
    this.stateResult,
    this.checkResult,
    this.downloadResult,
    this.downloadError,
    this.checkError,
    this.applyError,
  });

  final WindowsUpdateSnapshot? stateResult;
  final WindowsUpdateSnapshot? checkResult;
  final WindowsUpdateSnapshot? downloadResult;
  final Object? downloadError;
  final Object? checkError;
  final Object? applyError;
  var checkCalls = 0;
  var downloadCalls = 0;

  @override
  Future<WindowsUpdateSnapshot> getState() async =>
      stateResult ?? _snapshot(status: 'available', torProxyReady: true);

  @override
  Future<WindowsUpdateSnapshot> checkForUpdates() async {
    checkCalls++;
    if (checkError case final error?) throw error;
    return checkResult ?? _snapshot(status: 'checking');
  }

  @override
  Future<WindowsUpdateSnapshot> downloadUpdate() async {
    downloadCalls++;
    if (downloadError case final error?) throw error;
    return downloadResult ?? _snapshot(status: 'downloading');
  }

  @override
  Future<WindowsUpdateSnapshot> applyUpdateAndRestart() async {
    if (applyError case final error?) throw error;
    return _snapshot(status: 'applying');
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
