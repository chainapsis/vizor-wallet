@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_endpoint_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_latency_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart'
    show LightwalletdEndpointProbe;
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../fakes/fake_sync_notifier.dart';

const _customEndpoint = RpcEndpointConfig(
  networkName: 'main',
  lightwalletdUrl: 'https://custom.zec.example:443',
  presetId: kCustomRpcEndpointPresetId,
);

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'John', order: 0)],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1endpointaddress',
);

AppBootstrapState _bootstrap(RpcEndpointConfig endpoint) => AppBootstrapState(
  initialLocation: '/settings/endpoint',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: endpoint,
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _EffectiveEndpoint extends RpcEndpointFailoverNotifier {
  _EffectiveEndpoint(this.endpoint);
  final RpcEndpointConfig endpoint;
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: endpoint,
    automaticReady: true,
    fallbackCandidates: const [],
  );
}

Widget _app({
  RpcEndpointConfig endpoint = _customEndpoint,
  RpcEndpointConfig? effective,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(endpoint)),
      if (effective != null)
        rpcEndpointFailoverProvider.overrideWith(
          () => _EffectiveEndpoint(effective),
        ),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      rpcEndpointProbeGetterProvider.overrideWithValue(
        (_) async =>
            const LightwalletdEndpointProbe(chainName: 'main', latencyMs: 123),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      home: const MobileEndpointScreen(),
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('automatic row displays its effective server and latency', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        endpoint: defaultRpcEndpointConfig('main'),
        effective: const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: 'https://eu.zec.stardust.rest:443',
          presetId: 'eu-zec-stardust',
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining(
        'eu.zec.stardust.rest:443 · 123ms',
        findRichText: true,
      ),
      findsOneWidget,
    );
    final automatic = find.byKey(
      const ValueKey('mobile_endpoint_preset_default-mainnet'),
    );
    expect(
      find.descendant(of: automatic, matching: find.text('Automatic')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: automatic,
        matching: find.text('eu.zec.stardust.rest:443 · 123ms'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: automatic,
        matching: find.text('us.zec.stardust.rest:443'),
      ),
      findsNothing,
    );
  });

  testWidgets('custom endpoint card pins the input to the Figma position', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pump();

    final cardFinder = find.byKey(
      const ValueKey('mobile_endpoint_custom_card'),
    );
    final fieldFinder = find.byKey(
      const ValueKey('mobile_endpoint_custom_field_shell'),
    );

    expect(tester.getSize(cardFinder), const Size(361, 200));
    expect(tester.getSize(fieldFinder).height, 60);

    final cardTop = tester.getTopLeft(cardFinder).dy;
    final fieldTop = tester.getTopLeft(fieldFinder).dy;
    final fieldBottom = tester.getBottomLeft(fieldFinder).dy;
    final cardBottom = tester.getBottomLeft(cardFinder).dy;

    // The 1.5px inside stroke lands the render box on half pixels while the
    // Figma PNG's visible border starts around y=111.
    expect(fieldTop - cardTop, 110.5);
    expect(cardBottom - fieldBottom, 29.5);
  });
}
