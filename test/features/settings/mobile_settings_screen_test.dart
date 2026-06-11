@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_settings_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/theme_mode_provider.dart';

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

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: _accountState,
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

Widget _app() {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      themeModeProvider.overrideWith(_FakeThemeModeNotifier.new),
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

  testWidgets('unshipped rows are disabled, shipped rows are not', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    // Address book has no mobile flow yet.
    final addressBook = tester.widget<Text>(find.text('Address Book'));
    expect(addressBook.style?.color, AppThemeData.dark.colors.text.disabled);

    // The seed phrase flow shipped — its row renders active.
    final seed = tester.widget<Text>(find.text('Secret Passphrase'));
    expect(seed.style?.color, isNot(AppThemeData.dark.colors.text.disabled));
  });
}
