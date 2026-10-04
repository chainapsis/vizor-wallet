@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_network_settings_sheet.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'fakes/fake_sync_notifier.dart';

void main() {
  testWidgets(
    'walletless startup Tor failure is shown in the sheet without a duplicate toast',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            syncProvider.overrideWith(FakeSyncNotifier.new),
            networkPrivacyProvider.overrideWith(_FailedPrivacy.new),
          ],
          child: const ZcashWalletApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileNetworkSettingsSheet), findsOneWidget);
      expect(find.text(kTorStartupFailureNotice), findsNothing);
      expect(
        find.text(
          'Vizor could not connect to Tor. Requests stay blocked until it connects or you turn Tor off.',
        ),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileNetworkSettingsSheet)),
      );
      expect(
        container.read(networkPrivacyProvider).status,
        NetworkPrivacyConnectionStatus.failed,
      );
      expect(container.read(networkPrivacyProvider).startupNotice, isNull);
    },
  );
}

class _FailedPrivacy extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.failed,
    startupNotice: kTorStartupFailureNotice,
  );
}
