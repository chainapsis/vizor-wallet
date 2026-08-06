@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_list_row.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_settings_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/theme_mode_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'John',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1settingsaddress',
);

const _hardwareAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Keystone',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1settingsaddress',
);

AppBootstrapState _bootstrap([AccountState accountState = _accountState]) =>
    AppBootstrapState(
      initialLocation: '/settings',
      initialAccountState: accountState,
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      themeMode: ThemeMode.dark,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
    );

/// Skips the secure-storage write so theme selection works without a
/// platform channel in widget tests.
class _FakeThemeModeNotifier extends ThemeModeNotifier {
  @override
  Future<void> set(ThemeMode mode) async {
    state = mode;
  }
}

class _FakeBiometricNotifier extends BiometricUnlockNotifier {
  _FakeBiometricNotifier(this.initialState);

  final BiometricUnlockState initialState;
  int disableCount = 0;

  @override
  Future<BiometricUnlockState> build() async => initialState;

  @override
  Future<void> disable() async {
    disableCount++;
    final current = state.value ?? initialState;
    state = AsyncData(current.copyWith(enabled: false));
  }
}

class _FakeSyncKeepAwakeNotifier extends SyncKeepAwakeNotifier {
  _FakeSyncKeepAwakeNotifier([
    this.initialState = const SyncKeepAwakeSettings(
      enabled: false,
      promptSeen: false,
    ),
  ]);

  final SyncKeepAwakeSettings initialState;
  bool? lastEnabled;
  bool? lastMarkPromptSeen;

  @override
  SyncKeepAwakeSettings build() => initialState;

  @override
  Future<void> setEnabled(bool enabled, {bool markPromptSeen = true}) async {
    lastEnabled = enabled;
    lastMarkPromptSeen = markPromptSeen;
    state = state.copyWith(
      enabled: enabled,
      promptSeen: markPromptSeen ? true : null,
    );
  }
}

Widget _app({
  AccountState accountState = _accountState,
  BiometricUnlockState? biometric,
  BiometricUnlockNotifier Function()? biometricNotifier,
  _FakeSyncKeepAwakeNotifier? syncKeepAwakeNotifier,
  NetworkPrivacyState? networkPrivacyState,
  List<bool>? networkPrivacyCalls,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(accountState)),
      if (networkPrivacyState != null)
        networkPrivacyProvider.overrideWith(
          () => _FakeNetworkPrivacyNotifier(
            networkPrivacyState,
            networkPrivacyCalls ?? <bool>[],
          ),
        ),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      themeModeProvider.overrideWith(_FakeThemeModeNotifier.new),
      syncKeepAwakeProvider.overrideWith(
        () => syncKeepAwakeNotifier ?? _FakeSyncKeepAwakeNotifier(),
      ),
      if (biometricNotifier != null)
        biometricUnlockProvider.overrideWith(biometricNotifier)
      else if (biometric != null)
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricNotifier(biometric),
        ),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      home: const MobileSettingsScreen(),
    ),
  );
}

class _FakeNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _FakeNetworkPrivacyNotifier(this._state, this.calls);

  final NetworkPrivacyState _state;

  /// Routes requested by the card. `retry()` funnels through here too.
  final List<bool> calls;

  @override
  NetworkPrivacyState build() => _state;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    calls.add(enabled);
  }
}

void main() {
  setUp(() {
    // Phone-sized surface so the lazily-built list renders every group.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1200)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('the Tor card reports the off route', (tester) async {
    await tester.pumpWidget(
      _app(networkPrivacyState: const NetworkPrivacyState.off()),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mobile_settings_tor_row')),
      200,
    );
    expect(find.text('Use Tor'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('mobile_settings_tor_description')),
          )
          .data,
      contains('connect directly'),
    );
  });

  testWidgets('tapping the Tor row asks for the other route', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _app(
        networkPrivacyState: const NetworkPrivacyState.off(),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('mobile_settings_tor_row'));
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(calls, [true]);
  });

  testWidgets('the Tor toggle matches the keep-awake toggle', (tester) async {
    await tester.pumpWidget(
      _app(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connected,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final torThumb = find.byKey(
      const ValueKey('mobile_settings_tor_toggle_thumb'),
    );
    final torTrack = find.byKey(const ValueKey('mobile_settings_tor_toggle'));
    await tester.scrollUntilVisible(torThumb, 200);
    expect(
      tester.getSize(torThumb),
      tester.getSize(
        find.byKey(
          const ValueKey('mobile_settings_sync_keep_awake_toggle_thumb'),
        ),
      ),
    );
    expect(
      tester.getSize(torTrack),
      tester.getSize(
        find.byKey(const ValueKey('mobile_settings_sync_keep_awake_toggle')),
      ),
    );
    expect(
      tester.getCenter(torThumb).dx,
      greaterThan(tester.getCenter(torTrack).dx),
    );
  });

  testWidgets(
    'a connected Tor route names the conditions background work needs',
    (tester) async {
      await tester.pumpWidget(
        _app(
          networkPrivacyState: const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connected,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mobile_settings_tor_row')),
        200,
      );
      expect(find.text('Connected'), findsOneWidget);
      final description = tester
          .widget<Text>(
            find.byKey(const ValueKey('mobile_settings_tor_description')),
          )
          .data;
      expect(
        description,
        contains(
          'A migration in progress advances in the background only while '
          'charging on an unmetered network.',
        ),
      );
      // The card must not carry the old foreground-only promise: background
      // work does happen on a Tor route once the gate passes.
      expect(description, isNot(contains('only advances while Vizor is open')));
    },
  );

  testWidgets('a connecting Tor route says requests are paused', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _app(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
        ),
        networkPrivacyCalls: calls,
      ),
    );
    // pump() only: a connecting card must never be pumpAndSettle'd if it ever
    // animates.
    await tester.pump();

    final row = find.byKey(const ValueKey('mobile_settings_tor_row'));
    await tester.scrollUntilVisible(row, 200);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('mobile_settings_tor_description')),
          )
          .data,
      contains('wait until the Tor connection is ready'),
    );
    // Busy means the toggle cannot be driven into a second transition.
    expect(tester.widget<GestureDetector>(row).onTap, isNull);
    await tester.tap(row);
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('a failed Tor route stays blocked and offers a retry', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _app(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pumpAndSettle();

    final retry = find.byKey(const ValueKey('mobile_settings_tor_retry'));
    await tester.scrollUntilVisible(retry, 200);
    expect(find.text('Failed'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('mobile_settings_tor_description')),
          )
          .data,
      contains('Requests stay blocked'),
    );
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(calls, [true]);
  });

  testWidgets('a failed switch to direct says Tor is still carrying traffic', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _app(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
          targetTorEnabled: false,
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pumpAndSettle();

    final retry = find.byKey(const ValueKey('mobile_settings_tor_retry'));
    await tester.scrollUntilVisible(retry, 200);
    expect(find.text('Switch failed'), findsOneWidget);
    final description = tester
        .widget<Text>(
          find.byKey(const ValueKey('mobile_settings_tor_description')),
        )
        .data;
    expect(description, contains('could not switch to a direct connection'));
    expect(description, contains('Tor is still on'));
    expect(description, isNot(contains('Requests stay blocked')));
    expect(find.text('Try direct connection'), findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(calls, [false]);
  });

  testWidgets('the Tor row publishes its status to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mobile_settings_tor_retry')),
      200,
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('mobile_settings_tor_row')),
      ),
      isSemantics(label: 'Use Tor', value: 'Failed', isButton: true),
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('mobile_settings_tor_retry')),
      ),
      isSemantics(label: 'Try again', isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  testWidgets('the Tor retry action is a touch-sized target', (tester) async {
    await tester.pumpWidget(
      _app(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final retry = find.byKey(const ValueKey('mobile_settings_tor_retry'));
    await tester.scrollUntilVisible(retry, 200);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
  });

  testWidgets('renders the grouped settings with live values', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('John'), findsOneWidget);
    expect(find.text('Knight'), findsOneWidget);
    final pfpRow = find.byKey(const ValueKey('mobile_settings_pfp_row'));
    final pfp = find.descendant(
      of: pfpRow,
      matching: find.byType(AppProfilePicture),
    );
    expect(
      tester.getTopLeft(pfp).dx,
      lessThan(tester.getTopLeft(find.text('Knight')).dx),
    );
    expect(
      _chevronIn(tester, const ValueKey('mobile_settings_seed_row')).color,
      AppThemeData.dark.colors.icon.accent,
    );
    expect(
      _chevronIn(tester, const ValueKey('mobile_settings_pfp_row')).color,
      AppThemeData.dark.colors.icon.accent,
    );
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Syncing'), findsOneWidget);
    final keepAwakeRow = find.byKey(
      const ValueKey('mobile_settings_sync_keep_awake_row'),
    );
    expect(keepAwakeRow, findsOneWidget);
    expect(
      find.descendant(
        of: keepAwakeRow,
        matching: find.text('Keep screen awake'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Prevents your phone from sleeping so sync can finish faster. The app '
        'still locks after 1 minute of inactivity.',
      ),
      findsOneWidget,
    );
    // The About entry stays hidden until the legal documents are ready.
    expect(find.text('About Vizor'), findsNothing);
    // Endpoint shows the live RPC host:port.
    expect(
      find.text(defaultRpcEndpointConfig('main').hostPort),
      findsOneWidget,
    );
  });

  testWidgets('theme row opens the sheet and applies the selection', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    expect(find.text('System (Auto)'), findsOneWidget);
    final modal = find.byType(MobileModalScaffold);
    final modalTitle = find.descendant(of: modal, matching: find.text('Theme'));
    final closeIcon = find.descendant(
      of: modal,
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.cross,
      ),
    );
    final titleCenterY = tester.getCenter(modalTitle).dy;
    final closeCenterY = tester.getCenter(closeIcon).dy;
    expect(titleCenterY, greaterThan(closeCenterY));
    expect(titleCenterY - closeCenterY, lessThanOrEqualTo(16));
    expect(tester.widget<AppIcon>(closeIcon).size, 20);
    expect(
      _leadingIconOpacityIn(
        tester,
        const ValueKey('mobile_theme_option_light'),
      ),
      0.5,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_theme_option_system')))
          .height,
      64,
    );
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey('mobile_theme_option_light')),
              )
              .dy -
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('mobile_theme_option_system')),
              )
              .dy,
      AppSpacing.xs,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mobile_theme_update'))).dy -
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('mobile_theme_option_dark')),
              )
              .dy,
      AppSpacing.md,
    );
    expect(
      find.byKey(const ValueKey('mobile_theme_option_light')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_theme_option_dark')),
      findsOneWidget,
    );

    // Selection commits through Update, not on tap.
    await tester.tap(find.byKey(const ValueKey('mobile_theme_option_light')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mobile_theme_update')));
    await tester.pumpAndSettle();

    // Sheet closed and the row value reflects the new mode.
    expect(find.text('System (Auto)'), findsNothing);
    expect(find.text('Light'), findsOneWidget);
  });

  testWidgets('sync keep-awake row toggles the persisted setting', (
    tester,
  ) async {
    final notifier = _FakeSyncKeepAwakeNotifier();
    await tester.pumpWidget(_app(syncKeepAwakeNotifier: notifier));
    await tester.pump();

    final row = find.byKey(
      const ValueKey('mobile_settings_sync_keep_awake_row'),
    );
    expect(
      find.descendant(of: row, matching: find.text('Keep screen awake')),
      findsOneWidget,
    );
    final thumb = find.byKey(
      const ValueKey('mobile_settings_sync_keep_awake_toggle_thumb'),
    );
    final track = find.byKey(
      const ValueKey('mobile_settings_sync_keep_awake_toggle'),
    );
    final offThumbLeft = tester.getTopLeft(thumb).dx;
    final trackCenterX = tester.getCenter(track).dx;

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(notifier.lastEnabled, isTrue);
    expect(notifier.lastMarkPromptSeen, isTrue);
    expect(tester.getTopLeft(thumb).dx, greaterThan(offThumbLeft));
    expect(tester.getCenter(thumb).dx, greaterThan(trackCenterX));
  });

  testWidgets('sync keep-awake row reflects persisted enabled state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        syncKeepAwakeNotifier: _FakeSyncKeepAwakeNotifier(
          const SyncKeepAwakeSettings(enabled: true, promptSeen: true),
        ),
      ),
    );
    await tester.pump();

    final row = find.byKey(
      const ValueKey('mobile_settings_sync_keep_awake_row'),
    );
    final thumb = find.byKey(
      const ValueKey('mobile_settings_sync_keep_awake_toggle_thumb'),
    );
    final track = find.byKey(
      const ValueKey('mobile_settings_sync_keep_awake_toggle'),
    );
    expect(
      find.descendant(of: row, matching: find.text('Keep screen awake')),
      findsOneWidget,
    );
    expect(tester.getCenter(thumb).dx, greaterThan(tester.getCenter(track).dx));
  });

  testWidgets('every settings row renders active', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (final label in [
      'Contacts',
      'Secret Passphrase',
      'Keep screen awake',
    ]) {
      final row = tester.widget<Text>(find.text(label));
      expect(
        row.style?.color,
        isNot(AppThemeData.dark.colors.text.disabled),
        reason: '$label should be enabled',
      );
    }
  });

  testWidgets('hardware accounts disable the secret passphrase row', (
    tester,
  ) async {
    await tester.pumpWidget(_app(accountState: _hardwareAccountState));
    await tester.pump();

    final rowFinder = find.byKey(const ValueKey('mobile_settings_seed_row'));
    final row = tester.widget<MobileListRow>(rowFinder);
    final label = tester.widget<Text>(find.text('Secret Passphrase'));
    final chevron = _chevronIn(
      tester,
      const ValueKey('mobile_settings_seed_row'),
    );

    expect(row.enabled, isFalse);
    expect(row.onTap, isNull);
    expect(label.style?.color, AppThemeData.dark.colors.text.disabled);
    expect(chevron.color, AppThemeData.dark.colors.icon.disabled);
  });

  testWidgets('labels Face ID hardware by brand', (tester) async {
    await tester.pumpWidget(
      _app(
        biometric: const BiometricUnlockState(
          availability: BiometricAvailability(
            supported: true,
            enrolled: true,
            kind: BiometricKind.face,
          ),
          enabled: true,
        ),
      ),
    );
    await tester.pump();

    final row = find.byKey(const ValueKey('mobile_settings_biometric_row'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Face ID')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Biometrics')),
      findsNothing,
    );
    expect(find.descendant(of: row, matching: find.text('On')), findsOneWidget);
  });

  testWidgets('asks before turning off Face ID unlock', (tester) async {
    final biometricNotifier = _FakeBiometricNotifier(
      const BiometricUnlockState(
        availability: BiometricAvailability(
          supported: true,
          enrolled: true,
          kind: BiometricKind.face,
        ),
        enabled: true,
      ),
    );

    await tester.pumpWidget(_app(biometricNotifier: () => biometricNotifier));
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const ValueKey('mobile_settings_biometric_row')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_settings_biometric_row')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn off Face ID unlock?'), findsOneWidget);
    expect(find.textContaining('You will use your passcode'), findsOneWidget);
    expect(biometricNotifier.disableCount, 0);

    await tester.tap(
      find.byKey(const ValueKey('mobile_biometric_disable_confirm')),
    );
    await tester.pumpAndSettle();

    expect(biometricNotifier.disableCount, 1);
    expect(find.text('Turn off Face ID unlock?'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_settings_biometric_row')),
        matching: find.text('Off'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancel keeps biometric unlock enabled', (tester) async {
    final biometricNotifier = _FakeBiometricNotifier(
      const BiometricUnlockState(
        availability: BiometricAvailability(
          supported: true,
          enrolled: true,
          kind: BiometricKind.fingerprint,
        ),
        enabled: true,
      ),
    );

    await tester.pumpWidget(_app(biometricNotifier: () => biometricNotifier));
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const ValueKey('mobile_settings_biometric_row')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_settings_biometric_row')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn off fingerprint unlock?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(biometricNotifier.disableCount, 0);
    expect(find.text('Turn off fingerprint unlock?'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_settings_biometric_row')),
        matching: find.text('On'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('close keeps biometric unlock enabled', (tester) async {
    final biometricNotifier = _FakeBiometricNotifier(
      const BiometricUnlockState(
        availability: BiometricAvailability(
          supported: true,
          enrolled: true,
          kind: BiometricKind.face,
        ),
        enabled: true,
      ),
    );

    await tester.pumpWidget(_app(biometricNotifier: () => biometricNotifier));
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const ValueKey('mobile_settings_biometric_row')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_settings_biometric_row')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn off Face ID unlock?'), findsOneWidget);

    await tester.tap(_modalCloseIcon());
    await tester.pumpAndSettle();

    expect(biometricNotifier.disableCount, 0);
    expect(find.text('Turn off Face ID unlock?'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_settings_biometric_row')),
        matching: find.text('On'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('labels fingerprint hardware by modality', (tester) async {
    await tester.pumpWidget(
      _app(
        biometric: const BiometricUnlockState(
          availability: BiometricAvailability(
            supported: true,
            enrolled: true,
            kind: BiometricKind.fingerprint,
          ),
          enabled: false,
        ),
      ),
    );
    await tester.pump();

    final row = find.byKey(const ValueKey('mobile_settings_biometric_row'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Fingerprint')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Biometrics')),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.text('Off')),
      findsOneWidget,
    );
  });
}

Finder _modalCloseIcon() {
  return find.descendant(
    of: find.byType(MobileModalScaffold),
    matching: find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.cross,
    ),
  );
}

AppIcon _chevronIn(WidgetTester tester, ValueKey<String> rowKey) {
  return tester.widget<AppIcon>(
    find.descendant(
      of: find.byKey(rowKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.chevronForward,
      ),
    ),
  );
}

double _leadingIconOpacityIn(WidgetTester tester, ValueKey<String> rowKey) {
  return tester
      .widget<Opacity>(
        find.descendant(of: find.byKey(rowKey), matching: find.byType(Opacity)),
      )
      .opacity;
}
