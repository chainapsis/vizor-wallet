@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/naming/ens_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_screen.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_recipient_step.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/ens_resolver_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1payaddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/pay',
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

Widget _pumpStep(Widget child) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.dark,
      child: Scaffold(body: SizedBox(width: 393, child: child)),
    ),
  );
}

Widget _payApp({required EnsNameResolver resolver}) {
  final router = GoRouter(
    initialLocation: '/pay',
    routes: [
      GoRoute(
        path: '/pay',
        builder: (_, _) =>
            const MobilePayScreen(preservePreparedComposer: true),
      ),
      GoRoute(
        path: '/pay/review',
        builder: (_, _) => const Scaffold(body: Text('Pay review route')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      ensResolverProvider.overrideWithValue(resolver),
      // The recipient CONTINUE routes through the real showReview(), which
      // otherwise reaches into Rust FFI for a shielded staging address; fail
      // it fast so quoteLoading settles instead of spinning forever in this
      // FFI-less widget-test environment.
      swapZecStagingAddressServiceProvider.overrideWithValue(
        SwapZecStagingAddressService(
          loadCurrentShieldedAddress: ({required accountUuid}) async {
            throw StateError('no shielded address in tests');
          },
        ),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            orchardBalance: BigInt.from(14_312_000_000),
            spendableBalance: BigInt.from(14_312_000_000),
            totalBalance: BigInt.from(14_312_000_000),
          ),
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppTheme(
        data: AppThemeData.dark,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

Future<void> _setMobileViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _goToRecipientStep(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('mobile_pay_amount_input')),
    '25',
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('mobile pay recipient hint', () {
    testWidgets('shows "or .eth" when the pay chain is EVM (USDC/Ethereum)', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _pumpStep(
          MobilePayRecipientStep(
            controller: controller,
            typedAddress: '',
            addressError: null,
            contacts: const [],
            recents: const [],
            busy: false,
            externalAsset: SwapAsset.usdc,
            onAddressChanged: (_) {},
            onOpenScanner: () {},
            onChooseRecipient: (_) {},
            onSelectRecipient: () {},
            onAddToContacts: () {},
          ),
        ),
      );

      expect(find.text('Ethereum address or .eth'), findsOneWidget);
    });

    testWidgets('stays plain on a non-EVM pay chain (SOL/Solana)', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _pumpStep(
          MobilePayRecipientStep(
            controller: controller,
            typedAddress: '',
            addressError: null,
            contacts: const [],
            recents: const [],
            busy: false,
            externalAsset: SwapAsset.sol,
            onAddressChanged: (_) {},
            onOpenScanner: () {},
            onChooseRecipient: (_) {},
            onSelectRecipient: () {},
            onAddToContacts: () {},
          ),
        ),
      );

      expect(find.text('Solana address'), findsOneWidget);
      expect(find.text('Solana address or .eth'), findsNothing);
    });
  });

  group('mobile pay screen ENS resolve gating', () {
    testWidgets(
      'typing a valid .eth name on the USDC (Ethereum) pay chain shows no inline error',
      (tester) async {
        await _setMobileViewport(tester);
        final resolver = _FakeEnsNameResolver();
        await tester.pumpWidget(_payApp(resolver: resolver));
        await tester.pumpAndSettle();

        await _goToRecipientStep(tester);

        await tester.enterText(
          find.byKey(const ValueKey('mobile_pay_recipient_input')),
          'nonsense',
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('mobile_pay_recipient_error')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('mobile_pay_recipient_input')),
          'vitalik.eth',
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('mobile_pay_recipient_error')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'continue resolves the name and pins the resolved 0x address',
      (tester) async {
        await _setMobileViewport(tester);
        final resolver = _FakeEnsNameResolver()
          ..nextResult = '0x00000000219ab540356cbb839cbe05303d7705fa';
        await tester.pumpWidget(_payApp(resolver: resolver));
        await tester.pumpAndSettle();

        await _goToRecipientStep(tester);

        await tester.enterText(
          find.byKey(const ValueKey('mobile_pay_recipient_input')),
          'vitalik.eth',
        );
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MobilePayScreen)),
          listen: false,
        );

        await tester.tap(
          find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
        );
        await tester.pumpAndSettle();

        final state = container.read(swapStateProvider);
        expect(state.destinationText, resolver.nextResult);
        expect(state.destinationEnsName, 'vitalik.eth');
        expect(
          state.destinationResolveStatus,
          SwapDestinationResolveStatus.idle,
        );
        expect(resolver.calls, hasLength(1));
      },
    );

    testWidgets(
      'continue is gated while resolving: the CTA shows progress and blocks',
      (tester) async {
        await _setMobileViewport(tester);
        final resolver = _GatedFakeEnsNameResolver();
        await tester.pumpWidget(_payApp(resolver: resolver));
        await tester.pumpAndSettle();

        await _goToRecipientStep(tester);

        await tester.enterText(
          find.byKey(const ValueKey('mobile_pay_recipient_input')),
          'vitalik.eth',
        );
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MobilePayScreen)),
          listen: false,
        );

        await tester.tap(
          find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
        );
        await tester.pump();

        expect(
          container.read(swapStateProvider).destinationResolveStatus,
          SwapDestinationResolveStatus.resolving,
        );
        expect(find.text('Fetching quote'), findsOneWidget);

        resolver.complete('0x00000000219ab540356cbb839cbe05303d7705fa');
        await tester.pumpAndSettle();

        expect(
          container.read(swapStateProvider).destinationResolveStatus,
          SwapDestinationResolveStatus.idle,
        );
      },
    );

    testWidgets(
      'a failed resolve keeps the recipient step and surfaces the message',
      (tester) async {
        await _setMobileViewport(tester);
        final resolver = _FakeEnsNameResolver()
          ..nextError = const EnsResolutionException(
            EnsResolutionFailure.noRecord,
            'Name has no address for this chain',
          );
        await tester.pumpWidget(_payApp(resolver: resolver));
        await tester.pumpAndSettle();

        await _goToRecipientStep(tester);

        await tester.enterText(
          find.byKey(const ValueKey('mobile_pay_recipient_input')),
          'vitalik.eth',
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('mobile_pay_recipient_step')),
          findsOneWidget,
        );
        expect(
          find.text('Name has no address for this chain'),
          findsOneWidget,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MobilePayScreen)),
          listen: false,
        );
        expect(container.read(swapStateProvider).destinationText, 'vitalik.eth');
      },
    );
  });
}

class _UnusedEnsRpcTransport implements EnsRpcTransport {
  @override
  Future<String> ethCall({required String to, required String data}) {
    throw UnimplementedError('not used by fake resolver');
  }

  @override
  Future<String> ccipFetch({
    required String url,
    required String sender,
    required String data,
  }) {
    throw UnimplementedError('not used by fake resolver');
  }
}

class _ResolveCall {
  const _ResolveCall({required this.name, required this.chainId});
  final String name;
  final int chainId;
}

class _FakeEnsNameResolver extends EnsNameResolver {
  _FakeEnsNameResolver() : super(_UnusedEnsRpcTransport());

  String? nextResult;
  EnsResolutionException? nextError;
  final calls = <_ResolveCall>[];

  @override
  Future<String> resolveEvmAddress(String name, {required int chainId}) async {
    calls.add(_ResolveCall(name: name, chainId: chainId));
    final error = nextError;
    if (error != null) throw error;
    return nextResult!;
  }
}

/// A resolver whose future never settles until [complete] is called, so a
/// test can observe the `resolving` state between the tap and the resolve
/// settling (a plain [_FakeEnsNameResolver] completes within the same
/// microtask, too fast to observe).
class _GatedFakeEnsNameResolver extends EnsNameResolver {
  _GatedFakeEnsNameResolver() : super(_UnusedEnsRpcTransport());

  final _completer = Completer<String>();

  void complete(String result) => _completer.complete(result);

  @override
  Future<String> resolveEvmAddress(String name, {required int chainId}) {
    return _completer.future;
  }
}
