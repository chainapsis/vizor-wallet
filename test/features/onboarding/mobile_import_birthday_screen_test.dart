@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/import/birthday',
  initialAccountState: const AccountState(accounts: []),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: false,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app() {
  return ProviderScope(
    overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobileImportBirthdayScreen(
        args: ImportBirthdayArgs(mnemonic: 'stub mnemonic'),
        loadChainMetadata: false,
      ),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('continue stays disabled until a plausible height is typed', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    AppButton continueButton() => tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );

    expect(continueButton().onPressed, isNull);

    // Below the Sapling activation floor → still disabled.
    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_birthday_height')),
      '1',
    );
    await tester.pump();
    expect(continueButton().onPressed, isNull);

    // A plausible mainnet height enables the action.
    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_birthday_height')),
      '2500000',
    );
    await tester.pump();
    expect(continueButton().onPressed, isNotNull);
  });
}
