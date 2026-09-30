import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/onboarding/import/desktop_import_navigation.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  setUpAll(() => RustLib.initMock(api: _RustApiFake()));
  tearDownAll(RustLib.dispose);
  Future<void> pump(
    WidgetTester tester, {
    String location = '/import/method',
    bool hasWallet = false,
    Object? extra,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          walletProvider.overrideWith(() => _Wallet(hasWallet)),
          appSecurityProvider.overrideWith(_Security.new),
          rpcEndpointFailoverProvider.overrideWith(_Rpc.new),
          ledgerAccountConnectorProvider.overrideWithValue(
            (_) async => _ledgerAccount,
          ),
          ledgerStaticCapabilityProvider.overrideWithValue(
            const LedgerCapability.supported(),
          ),
        ],
        child: _Harness(location, extra),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'production import entry reaches hardware and returns to welcome',
    (tester) async {
      await pump(tester);
      expect(find.text('Import secret passphrase'), findsOneWidget);
      expect(find.text('Link Vizor Desktop'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('desktop_import_hardware_card')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect Keystone'), findsOneWidget);
      expect(find.text('Connect Ledger'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
    },
  );

  testWidgets('add-account import cancels back to the existing wallet', (
    tester,
  ) async {
    await pump(
      tester,
      location: '/import/method?from=add-account',
      hasWallet: true,
    );
    await tester.tap(
      find.byKey(const ValueKey('desktop_import_hardware_card')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(
        tester.element(find.text('Cancel')),
      ).routeInformationProvider.value.uri.toString(),
      '/import/method?from=add-account',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Back'), findsOneWidget);
  });

  for (final hasWallet in [false, true]) {
    final suffix = hasWallet ? '?from=add-account' : '';
    final origin = hasWallet ? 'add-account' : 'first-wallet';
    testWidgets('$origin secret passphrase returns to its method selector', (
      tester,
    ) async {
      await pump(
        tester,
        location: '/import/method$suffix',
        hasWallet: hasWallet,
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop_import_secret_passphrase_card')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppBackLink));
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(
          tester.element(find.text('Cancel')),
        ).routeInformationProvider.value.uri.toString(),
        '/import/method$suffix',
      );
    });

    for (final device in ['keystone', 'ledger']) {
      testWidgets('$origin $device returns to its hardware selector', (
        tester,
      ) async {
        await pump(
          tester,
          location: '/import/hardware$suffix',
          hasWallet: hasWallet,
        );
        await tester.tap(
          find.byKey(ValueKey('desktop_hardware_${device}_card')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(AppBackLink));
        await tester.pumpAndSettle();
        expect(
          GoRouter.of(
            tester.element(find.text('Back')),
          ).routeInformationProvider.value.uri.toString(),
          '/import/hardware$suffix',
        );
      });
    }

    testWidgets(
      '$origin birthday Back keeps the phrase selector after typed extras',
      (tester) async {
        final query =
            'entry=import-method${hasWallet ? '&from=add-account' : ''}';
        await pump(
          tester,
          location: '/import/birthday?$query',
          hasWallet: hasWallet,
          extra: const ImportBirthdayArgs(mnemonic: 'abandon about'),
        );
        await tester.tap(find.byType(AppBackLink));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(AppBackLink));
        await tester.pumpAndSettle();
        expect(
          GoRouter.of(
            tester.element(find.text('Cancel')),
          ).routeInformationProvider.value.uri.toString(),
          '/import/method$suffix',
        );
      },
    );

    for (final device in ['keystone', 'ledger']) {
      testWidgets(
        '$origin $device keeps its selector after advancing and backing twice',
        (tester) async {
          await pump(
            tester,
            location: '/import/hardware$suffix',
            hasWallet: hasWallet,
          );
          await tester.tap(
            find.byKey(ValueKey('desktop_hardware_${device}_card')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            device == 'keystone'
                ? find.text("I'm ready now")
                : find.byKey(const ValueKey('ledger_connect_button')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(AppBackLink));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(AppBackLink));
          await tester.pumpAndSettle();
          expect(
            GoRouter.of(
              tester.element(find.text('Back')),
            ).routeInformationProvider.value.uri.toString(),
            '/import/hardware$suffix',
          );
        },
      );
    }
  }

  test(
    'selector origin accepts only known entries and add-account context',
    () {
      expect(
        desktopImportSelectionLocation(
          Uri.parse('/import?entry=external&from=add-account'),
        ),
        isNull,
      );
      expect(
        preserveDesktopImportEntry(
          Uri.parse('/import?entry=external'),
          '/import/birthday',
        ),
        '/import/birthday',
      );
      expect(
        desktopImportSelectionLocation(
          Uri.parse('/import?entry=import-method&from=external'),
        ),
        '/import/method',
      );
      final location = Uri.parse(
        preserveDesktopImportEntry(
          Uri.parse(
            '/import?entry=hardware-method&from=add-account&secret=discard',
          ),
          '/onboarding/ledger/birthday',
        ),
      );
      expect(location.queryParameters, {
        'entry': 'hardware-method',
        'from': 'add-account',
      });
    },
  );
}

final _routes = Provider(appDesktopOnboardingRoutes);
final _redirect = Provider(
  (ref) =>
      (GoRouterState state) => appRedirect(
        ref: ref,
        bootstrap: AppBootstrapState.empty,
        state: state,
      ),
);

class _Harness extends ConsumerStatefulWidget {
  const _Harness(this.location, this.extra);
  final String location;
  final Object? extra;
  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  late final GoRouter router;
  @override
  void initState() {
    super.initState();
    router = GoRouter(
      initialLocation: widget.location,
      initialExtra: widget.extra,
      redirect: (_, state) => ref.read(_redirect)(state),
      routes: [
        ...ref.read(_routes),
        GoRoute(
          path: '/payment-links',
          builder: (_, _) => const Text('payment-links-destination'),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Text('home-destination'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _Wallet extends WalletNotifier {
  _Wallet(this.hasWallet);
  final bool hasWallet;
  @override
  WalletState build() => WalletState(hasWallet: hasWallet);
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _RustApiFake implements RustLibApi {
  @override
  List<String> crateApiWalletMnemonicWordList() => const ['abandon', 'about'];

  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _ledgerAccount = LedgerDeviceAccount(
  ufvk: 'test-ledger-account',
  seedFingerprint: [1],
  accountIndex: 0,
  appVersion: '3.9.3',
);

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

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    if (operation == 'import birthday metadata') {
      return ImportBirthdayMetadata(
            saplingActivationHeight: 419200,
            saplingActivationDate: DateTime(2018, 10, 29),
            tipHeight: 3000000,
            tipDate: DateTime(2026, 9, 30),
          )
          as T;
    }
    return action(state.current);
  }
}
