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
  Future<void> downloadUpdate() async {
    events.add('download');
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
