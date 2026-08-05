import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/unlock_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/windows_update_provider.dart';

import 'fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('windows update prompt is visible on unlock route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_appHarness());
    await tester.pump();

    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.text('Update 9.9.9 available'), findsOneWidget);
    expect(find.text('Download now or keep working.'), findsOneWidget);
  });

  testWidgets('Tor-connected download asks before continuing through Tor', (
    tester,
  ) async {
    final downloads = <String>[];
    await tester.pumpWidget(
      _appHarness(
        windowsUpdateOverride: windowsUpdateProvider.overrideWith(
          () => _RecordingAvailableWindowsUpdateNotifier(downloads),
        ),
        extraOverrides: [
          networkPrivacyProvider.overrideWith(_TorOnPrivacyNotifier.new),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(AppButton, 'Download'));
    await tester.pumpAndSettle();

    expect(find.text('Use Tor for this update?'), findsOneWidget);
    expect(downloads, isEmpty);

    await tester.tap(find.widgetWithText(AppButton, 'Continue with Tor'));
    await tester.pumpAndSettle();

    expect(downloads, ['download']);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UnlockScreen)),
    );
    expect(container.read(networkPrivacyProvider).torEnabled, isTrue);
  });

  testWidgets('direct update waits until Tor has been turned off', (
    tester,
  ) async {
    final events = <String>[];
    final torDisabled = Completer<void>();
    await tester.pumpWidget(
      _appHarness(
        windowsUpdateOverride: windowsUpdateProvider.overrideWith(
          () => _RecordingAvailableWindowsUpdateNotifier(events),
        ),
        extraOverrides: [
          networkPrivacyProvider.overrideWith(
            () => _DeferredTorDisablePrivacyNotifier(events, torDisabled),
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(AppButton, 'Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Turn off Tor and update'));
    await tester.pump();

    expect(events, ['disable:start']);

    torDisabled.complete();
    await tester.pumpAndSettle();

    expect(events, ['disable:start', 'disable:done', 'download']);
  });

  testWidgets('failed Tor disable keeps the update blocked and explains why', (
    tester,
  ) async {
    final events = <String>[];
    await tester.pumpWidget(
      _appHarness(
        windowsUpdateOverride: windowsUpdateProvider.overrideWith(
          () => _RecordingAvailableWindowsUpdateNotifier(events),
        ),
        extraOverrides: [
          networkPrivacyProvider.overrideWith(
            () => _FailingTorDisablePrivacyNotifier(events),
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(AppButton, 'Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Turn off Tor and update'));
    await tester.pumpAndSettle();

    expect(events, ['disable']);
    expect(find.text("Couldn't turn off Tor"), findsOneWidget);
    expect(
      find.textContaining('Tor remains on, so Vizor kept the update blocked.'),
      findsOneWidget,
    );
    expect(downloadsFrom(events), isEmpty);
  });

  testWidgets('unavailable Tor updater route stays fail-closed with guidance', (
    tester,
  ) async {
    final events = <String>[];
    await tester.pumpWidget(
      _appHarness(
        windowsUpdateOverride: windowsUpdateProvider.overrideWith(
          () => _RecordingAvailableWindowsUpdateNotifier(events),
        ),
        extraOverrides: [
          networkPrivacyProvider.overrideWith(
            _TorUpdatesUnavailablePrivacyNotifier.new,
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(AppButton, 'Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Continue with Tor'));
    await tester.pumpAndSettle();

    expect(find.text('Software updates unavailable over Tor'), findsOneWidget);
    expect(find.textContaining('Retry updates in Settings'), findsOneWidget);
    expect(downloadsFrom(events), isEmpty);
  });

  testWidgets('background download failure stays visible with retry guidance', (
    tester,
  ) async {
    final events = <String>[];
    await tester.pumpWidget(
      _appHarness(
        windowsUpdateOverride: windowsUpdateProvider.overrideWith(
          () => _BackgroundFailureWindowsUpdateNotifier(events),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Downloading update'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(UnlockScreen)),
    );
    final notifier = container.read(windowsUpdateProvider.notifier);
    (notifier as _BackgroundFailureWindowsUpdateNotifier).failDownload();
    await tester.pumpAndSettle();

    expect(find.text('Update failed'), findsOneWidget);
    expect(find.text('Signed feed verification failed.'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Dismiss'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Try again'));
    await tester.pump();

    expect(events, ['retry']);
  });

  testWidgets(
    'Tor-connected startup checks once without route-switch duplication',
    (tester) async {
      final checks = <String>[];
      await tester.pumpWidget(
        _appHarness(
          windowsUpdateOverride: windowsUpdateProvider.overrideWith(
            () => _TrackingWindowsUpdateNotifier(checks),
          ),
          extraOverrides: [
            networkPrivacyProvider.overrideWith(_TorOnPrivacyNotifier.new),
          ],
        ),
      );
      await tester.pump();
      expect(checks, ['check']);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(UnlockScreen)),
      );
      final notifier = container.read(networkPrivacyProvider.notifier);
      (notifier as _TorOnPrivacyNotifier).setDirect();
      await tester.pump();

      expect(checks, ['check']);
    },
  );

  testWidgets('restored Tor updater route retries the startup check', (
    tester,
  ) async {
    final checks = <String>[];
    await tester.pumpWidget(
      _appHarness(
        windowsUpdateOverride: windowsUpdateProvider.overrideWith(
          () => _TrackingWindowsUpdateNotifier(checks),
        ),
        extraOverrides: [
          networkPrivacyProvider.overrideWith(
            _TorUpdatesUnavailablePrivacyNotifier.new,
          ),
        ],
      ),
    );
    await tester.pump();
    expect(checks, ['check']);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(UnlockScreen)),
    );
    final notifier = container.read(networkPrivacyProvider.notifier);
    (notifier as _TorUpdatesUnavailablePrivacyNotifier).restoreUpdates();
    await tester.pump();

    expect(checks, ['check', 'check']);
  });
}

Widget _appHarness({
  Override? windowsUpdateOverride,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_lockedBootstrap),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      windowsUpdateOverride ??
          windowsUpdateProvider.overrideWith(
            _AvailableWindowsUpdateNotifier.new,
          ),
      ...extraOverrides,
    ],
    child: const ZcashWalletApp(),
  );
}

final _lockedBootstrap = AppBootstrapState(
  initialLocation: '/unlock',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: false,
  passwordRotationRecoveryFailed: false,
);

class _AvailableWindowsUpdateNotifier extends WindowsUpdateNotifier {
  @override
  WindowsUpdateState build() {
    return const WindowsUpdateState(
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
}

class _RecordingAvailableWindowsUpdateNotifier
    extends _AvailableWindowsUpdateNotifier {
  _RecordingAvailableWindowsUpdateNotifier(this.events);

  final List<String> events;

  @override
  Future<WindowsUpdateDownloadResult> downloadUpdate() async {
    events.add('download');
    return const WindowsUpdateDownloadResult.started();
  }
}

class _TrackingWindowsUpdateNotifier extends WindowsUpdateNotifier {
  _TrackingWindowsUpdateNotifier(this.checks);

  final List<String> checks;

  @override
  WindowsUpdateState build() => WindowsUpdateState.initial();

  @override
  Future<void> checkOnStartup() async {
    checks.add('check');
  }
}

class _BackgroundFailureWindowsUpdateNotifier extends WindowsUpdateNotifier {
  _BackgroundFailureWindowsUpdateNotifier(this.events);

  final List<String> events;

  @override
  WindowsUpdateState build() => const WindowsUpdateState(
    supported: true,
    status: WindowsUpdateStatus.downloading,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: 42,
    pendingRestart: false,
    torProxyReady: true,
    message: '',
  );

  void failDownload() {
    state = const WindowsUpdateState(
      supported: true,
      status: WindowsUpdateStatus.failed,
      currentVersion: '1.0.0',
      appId: 'Vizor',
      repoUrl: 'https://updates.example.invalid/vizor',
      availableVersion: '9.9.9',
      downloadProgress: 42,
      pendingRestart: false,
      torProxyReady: true,
      message: 'Signed feed verification failed.',
    );
  }

  @override
  Future<void> checkForUpdates() async {
    events.add('retry');
  }
}

class _TorOnPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connected,
  );

  void setDirect() {
    state = const NetworkPrivacyState.off();
  }
}

class _DeferredTorDisablePrivacyNotifier extends _TorOnPrivacyNotifier {
  _DeferredTorDisablePrivacyNotifier(this.events, this.torDisabled);

  final List<String> events;
  final Completer<void> torDisabled;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    assert(!enabled);
    events.add('disable:start');
    await torDisabled.future;
    state = const NetworkPrivacyState.off();
    events.add('disable:done');
  }
}

class _FailingTorDisablePrivacyNotifier extends _TorOnPrivacyNotifier {
  _FailingTorDisablePrivacyNotifier(this.events);

  final List<String> events;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    assert(!enabled);
    events.add('disable');
    state = const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      targetTorEnabled: false,
      error: 'sync did not stop',
    );
  }
}

class _TorUpdatesUnavailablePrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connected,
    softwareUpdatesAvailable: false,
  );

  void restoreUpdates() {
    state = const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connected,
    );
  }
}

List<String> downloadsFrom(List<String> events) =>
    events.where((event) => event == 'download').toList();
