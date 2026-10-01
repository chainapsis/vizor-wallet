import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _RustFake()));
  tearDownAll(RustLib.dispose);

  for (final hasWallet in [false, true]) {
    final entry = hasWallet ? 'add account' : 'first wallet';
    for (final flow in [
      'import_wallet',
      'connect_keystone',
      'connect_ledger',
    ]) {
      testWidgets('$entry $flow returns to its entry screen', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final harness = _Harness(hasWallet: hasWallet);
        addTearDown(() {
          harness.router.dispose();
          harness.container.dispose();
        });
        await tester.pumpWidget(harness.widget);
        await tester.pumpAndSettle();

        if (hasWallet) {
          await tester.tap(find.text('Add account review entry'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(ValueKey('welcome_${flow}_button')));
        await tester.pumpAndSettle();

        expect(harness.router.canPop(), isFalse);
        final back = find.byType(AppBackLink);
        expect(back, findsOneWidget);
        if (flow != 'connect_ledger') {
          expect(
            find.descendant(
              of: back,
              matching: find.text(hasWallet ? 'Add account' : 'Welcome'),
            ),
            findsOneWidget,
          );
        }
        await tester.tap(back);
        await tester.pumpAndSettle();

        expect(
          harness.router.routeInformationProvider.value.uri.path,
          hasWallet ? '/add-account' : '/welcome',
        );
        expect(find.text('Back'), hasWallet ? findsOneWidget : findsNothing);
        expect(
          find.byKey(const ValueKey('welcome_endpoint_settings_button')),
          hasWallet ? findsNothing : findsOneWidget,
        );
        expect(find.text('Home review marker'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

final _routes = Provider(appDesktopOnboardingRoutes);

class _Harness {
  _Harness({required bool hasWallet}) {
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        walletProvider.overrideWith(() => _Wallet(hasWallet)),
        appSecurityProvider.overrideWith(() => _Security(hasWallet)),
        ledgerStaticCapabilityProvider.overrideWithValue(
          const LedgerCapability.supported(),
        ),
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        rpcEndpointFailoverProvider.overrideWith(_Rpc.new),
      ],
    );
    final routerProvider = Provider(
      (ref) => GoRouter(
        initialLocation: hasWallet ? '/accounts' : '/welcome',
        redirect: (_, state) => appRedirect(
          ref: ref,
          bootstrap: AppBootstrapState.empty,
          state: state,
        ),
        routes: [
          ...ref.read(_routes),
          GoRoute(
            path: '/accounts',
            builder: (context, _) => TextButton(
              onPressed: () => context.push('/add-account'),
              child: const Text('Add account review entry'),
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Text('Home review marker'),
          ),
        ],
      ),
    );
    router = container.read(routerProvider);
    widget = UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    );
  }

  late final ProviderContainer container;
  late final GoRouter router;
  late final Widget widget;
}

class _Wallet extends WalletNotifier {
  _Wallet(this.hasWallet);

  final bool hasWallet;

  @override
  FutureOr<WalletState> build() => WalletState(hasWallet: hasWallet);
}

class _Security extends AppSecurityNotifier {
  _Security(this.hasWallet);

  final bool hasWallet;

  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: hasWallet, isUnlocked: hasWallet);
}

class _Rpc extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() {
    final endpoint = defaultRpcEndpointConfig('main');
    return RpcEndpointFailoverState(
      primary: endpoint,
      current: endpoint,
      fallbackCandidates: const [],
    );
  }
}

class _RustFake implements RustLibApi {
  @override
  List<String> crateApiWalletMnemonicWordList() => const ['abandon', 'ability'];

  @override
  bool crateApiWalletValidateMnemonic({required String mnemonic}) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
