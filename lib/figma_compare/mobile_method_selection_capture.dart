import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/features/ledger/ledger_capability.dart';
import '../src/features/onboarding/mobile/mobile_method_selection_screen.dart';
import '../src/providers/account_provider.dart';

/// Shows Ledger without production wallet data or device access.
Widget buildMobileMethodSelectionCapture(BuildContext context) {
  final empty = AppBootstrapState.empty;
  return ProviderScope(
    overrides: [
      ledgerStaticCapabilityProvider.overrideWithValue(
        const LedgerCapability.supported(),
      ),
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/onboarding/method',
          initialAccountState: const AccountState(
            accounts: [AccountInfo(uuid: 'preview', name: 'Main', order: 0)],
          ),
          initialSyncSnapshot: empty.initialSyncSnapshot,
          network: empty.network,
          rpcEndpointConfig: empty.rpcEndpointConfig,
          themeMode: empty.themeMode,
          privacyModeEnabled: false,
          isPasswordConfigured: true,
          isUnlocked: true,
          passwordRotationRecoveryFailed: false,
        ),
      ),
    ],
    child: const MobileMethodSelectionScreen(),
  );
}
