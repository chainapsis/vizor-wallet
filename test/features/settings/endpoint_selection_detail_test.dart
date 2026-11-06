import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_endpoint_screen.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_endpoint_screen.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_latency_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart'
    show LightwalletdEndpointProbe;

import '../../fakes/fake_sync_notifier.dart';
import '../../support/app_test_fonts.dart';

const _korea = RpcEndpointConfig(
  networkName: 'main',
  lightwalletdUrl: 'https://kr.zec.stardust.rest:443',
  presetId: 'kr-zec-stardust',
);
const _europe = RpcEndpointConfig(
  networkName: 'main',
  lightwalletdUrl: 'https://eu.zec.stardust.rest:443',
  presetId: 'eu-zec-stardust',
);
const _mobile = kAppFormFactor == AppFormFactor.mobile;

class _Effective extends RpcEndpointFailoverNotifier {
  _Effective(this.initial);
  final RpcEndpointFailoverState initial;
  @override
  RpcEndpointFailoverState build() => initial;
  void emit(RpcEndpointFailoverState next) => state = next;
}

class _Privacy extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}

Finder get _automatic => find.byKey(
  ValueKey(
    '${_mobile ? 'mobile_endpoint' : 'endpoint'}_preset_default-mainnet',
  ),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  RpcEndpointConfig? preference,
  RpcEndpointConfig? effective,
  bool ready = true,
  VoidCallback? onProbe,
}) async {
  await tester.binding.setSurfaceSize(
    _mobile ? const Size(393, 852) : const Size(1080, 720),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final primary = preference ?? defaultRpcEndpointConfig('main');
  final router = GoRouter(
    initialLocation: '/settings/endpoint',
    routes: [
      GoRoute(
        path: '/settings/endpoint',
        builder: (_, _) => _mobile
            ? const MobileEndpointScreen()
            : const SettingsEndpointScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/settings/endpoint',
            initialAccountState: const AccountState(),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: 'main',
            rpcEndpointConfig: primary,
            themeMode: ThemeMode.dark,
            privacyModeEnabled: false,
            isPasswordConfigured: false,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        rpcEndpointFailoverProvider.overrideWith(
          () => _Effective(
            RpcEndpointFailoverState(
              primary: primary,
              current: effective ?? primary,
              automaticReady: ready,
              fallbackCandidates: const [],
            ),
          ),
        ),
        rpcEndpointProbeGetterProvider.overrideWithValue((url) async {
          onProbe?.call();
          return LightwalletdEndpointProbe(
            chainName: 'main',
            latencyMs: url == _korea.lightwalletdUrl ? 42 : 123,
          );
        }),
        networkPrivacyProvider.overrideWith(_Privacy.new),
        syncProvider.overrideWith(FakeSyncNotifier.new),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(
      find.byType(_mobile ? MobileEndpointScreen : SettingsEndpointScreen),
    ),
  );
}

void main() {
  setUpAll(loadAppTestFonts);
  testWidgets('Automatic shows selection progress without the seed host', (
    tester,
  ) async {
    await _pump(tester, ready: false);
    expect(
      find.descendant(
        of: _automatic,
        matching: find.text('Selecting an endpoint…'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Current:', findRichText: true), findsNothing);
    expect(find.textContaining('Automatic ·'), findsNothing);
    expect(
      find.descendant(
        of: _automatic,
        matching: find.textContaining('us.zec.stardust.rest'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Automatic follows the effective server without another probe', (
    tester,
  ) async {
    var probes = 0;
    final container = await _pump(
      tester,
      effective: _korea,
      onProbe: () => probes++,
    );
    expect(
      find.descendant(
        of: _automatic,
        matching: find.text('kr.zec.stardust.rest:443 · 42ms'),
      ),
      findsOneWidget,
    );
    final initialProbes = probes;
    expect(initialProbes, greaterThan(0));
    final notifier =
        container.read(rpcEndpointFailoverProvider.notifier) as _Effective;
    notifier.emit(
      container.read(rpcEndpointFailoverProvider).copyWith(current: _europe),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: _automatic,
        matching: find.text('eu.zec.stardust.rest:443 · 123ms'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('kr.zec.stardust.rest:443 ·'), findsNothing);
    expect(probes, initialProbes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual mode keeps the current header and no Automatic detail', (
    tester,
  ) async {
    await _pump(tester, preference: _korea, effective: _europe);
    expect(
      find.textContaining(
        'Current: eu.zec.stardust.rest:443',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _automatic, matching: find.byType(Text)),
      findsOneWidget,
    );
    await tester.tap(_automatic);
    await tester.pump();
    expect(
      find.descendant(of: _automatic, matching: find.byType(Text)),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Current: eu.zec.stardust.rest:443',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('custom tab retains the applied Automatic connection header', (
    tester,
  ) async {
    await _pump(tester, effective: _korea);
    await tester.tap(find.text('Custom endpoint'));
    await tester.pump();
    expect(
      find.textContaining(
        'Automatic · kr.zec.stardust.rest:443',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
