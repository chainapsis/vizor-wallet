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

  @override
  Future<BiometricUnlockState> build() async => initialState;
}

Widget _app({
  AccountState accountState = _accountState,
  BiometricUnlockState? biometric,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(accountState)),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      themeModeProvider.overrideWith(_FakeThemeModeNotifier.new),
      if (biometric != null)
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

void main() {
  setUp(() {
    // Phone-sized surface so the lazily-built list renders every group.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1200)
      ..devicePixelRatio = 1.0;
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

  testWidgets('every settings row renders active', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    for (final label in ['Address Book', 'Secret Passphrase']) {
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
    expect(find.descendant(of: row, matching: find.text('On')), findsOneWidget);
  });

  testWidgets('labels non-face biometric hardware generically', (tester) async {
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
      find.descendant(of: row, matching: find.text('Biometrics')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Fingerprint')),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.text('Off')),
      findsOneWidget,
    );
  });
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
