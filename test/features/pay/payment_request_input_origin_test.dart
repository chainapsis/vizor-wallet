import 'package:zcash_wallet/src/core/navigation/payment_request_intake.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/pay/widgets/cross_chain_payment_request_host.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/payments/cross_chain_payment_request.dart';
import 'package:zcash_wallet/src/features/pay/providers/cross_chain_payment_request_provider.dart';
import 'package:zcash_wallet/src/features/pay/providers/payment_request_input_origin_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

const _recipient = '0x52908400098527886E0F7030069857D2E4169EE7';

void main() {
  late ProviderContainer container;
  late List<String> recipients;
  late int cancellations;
  late bool current;

  PaymentRequestInputOrigin origin({String chain = 'base'}) =>
      PaymentRequestInputOrigin(
        chain: chain,
        isCurrent: () => current,
        useAddress: recipients.add,
        onCancel: () => cancellations++,
      );

  CrossChainPaymentFlowNotifier present({
    String? chainId = '8453',
    bool includeAmount = true,
    String? unsupportedReason,
  }) {
    container
        .read(paymentRequestInputOriginProvider.notifier)
        .set('scan', origin());
    final flow = container.read(crossChainPaymentFlowProvider.notifier);
    flow.present(
      CrossChainPaymentRequest(
        id: 'scan',
        rawUri: 'ethereum:$_recipient',
        address: _recipient,
        isEvm: true,
        chainId: chainId,
        amount: includeAmount ? PaymentRequestAmount.atomicHex('0x03') : null,
        unsupportedReason: unsupportedReason,
      ),
    );
    return flow;
  }

  setUp(() {
    recipients = [];
    cancellations = 0;
    current = true;
    container = ProviderContainer(
      overrides: [
        accountProvider.overrideWith(_Accounts.new),
        appSecurityProvider.overrideWith(_Security.new),
        swapStateProvider.overrideWith(_Composer.new),
        swapFeatureEnabledProvider.overrideWithValue(true),
        networkPrivacyProvider.overrideWith(_Privacy.new),
      ],
    );
  });
  tearDown(() => container.dispose());

  test(
    'keep editing delivers only the recipient and preserves the composer',
    () {
      final before = container.read(swapStateProvider);
      final flow = present();
      flow.chooseSlippage(125);
      flow.setSlippageEditing(true);
      flow.setSlippageEditing(false);
      expect(flow.canUseAddressOnly, isTrue);
      flow.useAddressOnly();
      expect(recipients, [_recipient]);
      expect(container.read(swapStateProvider), same(before));
      expect(container.read(crossChainPaymentFlowProvider), isNull);
      expect(cancellations, 0);
      flow.useAddressOnly();
      expect(recipients, hasLength(1));
    },
  );

  test('another chain cannot replace the selected chain recipient', () {
    final before = container.read(swapStateProvider);
    final flow = present(chainId: '1');
    expect(flow.canUseAddressOnly, isFalse);
    flow.useAddressOnly();
    expect(recipients, isEmpty);
    expect(container.read(swapStateProvider), same(before));
    expect(container.read(crossChainPaymentFlowProvider), isNotNull);
  });

  test('request without amount can still supply just its address', () {
    final flow = present(includeAmount: false);
    expect(flow.canUseAddressOnly, isTrue);
    flow.useAddressOnly();
    expect(recipients, [_recipient]);
  });

  test('chainless EVM starts on editor chain and tracks network selection', () {
    final flow = present(chainId: null);
    expect(
      container.read(crossChainPaymentFlowProvider)?.selectedChain,
      'base',
    );
    expect(flow.canUseAddressOnly, isTrue);
    flow.chooseNetwork('eth');
    expect(flow.canUseAddressOnly, isFalse);
    flow.chooseNetwork('base');
    expect(flow.canUseAddressOnly, isTrue);
    flow.useAddressOnly();
    expect(recipients, [_recipient]);
  });

  test(
    'unsupported conditions cannot be bypassed by extracting the address',
    () {
      final flow = present(unsupportedReason: 'Unsupported payment condition');
      expect(flow.canUseAddressOnly, isFalse);
      flow.useAddressOnly();
      expect(recipients, isEmpty);
    },
  );

  test(
    'cancel restores the editor exactly once without applying a recipient',
    () {
      final before = container.read(swapStateProvider);
      final flow = present();
      flow.dismiss();
      flow.dismiss();
      expect(cancellations, 1);
      expect(recipients, isEmpty);
      expect(container.read(swapStateProvider), same(before));
    },
  );

  test('stale local request is discarded before its sheet is presented', () {
    current = false;
    present();
    expect(container.read(crossChainPaymentFlowProvider), isNull);
    expect(container.read(paymentRequestInputOriginProvider), isNull);
    expect(recipients, isEmpty);
    expect(cancellations, 0);
  });

  test('stale local request does not clear an already visible request', () {
    final flow = container.read(crossChainPaymentFlowProvider.notifier);
    const existing = CrossChainPaymentRequest(
      id: 'existing',
      rawUri: 'ethereum:existing',
      address: '0x1111111111111111111111111111111111111111',
      isEvm: true,
      chainId: '1',
    );
    flow.present(existing);
    final before = container.read(crossChainPaymentFlowProvider);
    current = false;
    present();
    expect(container.read(crossChainPaymentFlowProvider), same(before));
    expect(recipients, isEmpty);
    expect(cancellations, 0);
  });

  test('stale editor receives neither address nor cancel callbacks', () {
    final flow = present();
    current = false;
    expect(flow.canUseAddressOnly, isFalse);
    flow.useAddressOnly();
    flow.dismiss();
    expect(recipients, isEmpty);
    expect(cancellations, 0);
  });

  for (final invalidate in ['lock', 'account']) {
    test('$invalidate drops active editor callbacks', () {
      final flow = present();
      if (invalidate == 'lock') {
        (container.read(appSecurityProvider.notifier) as _Security).lock();
      } else {
        (container.read(accountProvider.notifier) as _Accounts)
            .switchToSecondAccount();
      }
      expect(container.read(crossChainPaymentFlowProvider), isNull);
      flow.useAddressOnly();
      flow.dismiss();
      expect(recipients, isEmpty);
      expect(cancellations, 0);
    });

    for (final replacement in ['none', 'global', 'unrelated']) {
      test(
        '$invalidate invalidates parked local request ($replacement)',
        () async {
          const local = CrossChainPaymentRequest(
            id: 'local',
            rawUri: 'ethereum:$_recipient',
            address: _recipient,
            isEvm: true,
            chainId: '8453',
          );
          final intake = container.read(paymentRequestIntakeProvider);
          await intake.receive(
            local.rawUri,
            resolvedCrossChainRequest: local,
            inputOrigin: origin(),
          );
          if (replacement == 'global') {
            await intake.receive('zcash:u1newrequest?amount=2');
          } else if (replacement == 'unrelated') {
            // A newer parked request must survive even if an older origin remains.
            container
                .read(paymentUriPrefillProvider.notifier)
                .set(
                  const CrossChainPaymentRequest(
                    id: 'other',
                    rawUri: 'ethereum:$_recipient?value=2',
                    address: _recipient,
                    isEvm: true,
                    chainId: '8453',
                  ),
                );
          }
          final parked = container.read(paymentUriPrefillProvider);
          expect(parked, isNotNull);
          if (invalidate == 'lock') {
            (container.read(appSecurityProvider.notifier) as _Security).lock();
          } else {
            (container.read(accountProvider.notifier) as _Accounts)
                .switchToSecondAccount();
          }
          expect(container.read(paymentRequestInputOriginProvider), isNull);
          // This is the same claim used before presenting after unlock.
          final claimed = container
              .read(paymentUriPrefillProvider.notifier)
              .takeIfFresh();
          expect(
            claimed.prefill,
            replacement == 'none' ? isNull : same(parked),
          );
          expect(recipients, isEmpty);
          expect(cancellations, 0);
        },
      );
    }

    test('$invalidate drops pending editor origin before presentation', () {
      container
          .read(paymentRequestInputOriginProvider.notifier)
          .set('scan', origin());
      if (invalidate == 'lock') {
        (container.read(appSecurityProvider.notifier) as _Security).lock();
      } else {
        (container.read(accountProvider.notifier) as _Accounts)
            .switchToSecondAccount();
      }
      expect(
        container.read(paymentRequestInputOriginProvider.notifier).take('scan'),
        isNull,
      );
    });
  }

  for (final action in ['edit', 'cancel']) {
    testWidgets('host $action returns to the unchanged swap composer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/swap',
        routes: [
          GoRoute(
            path: '/swap',
            builder: (_, _) => const Scaffold(body: Text('Swap composer')),
          ),
          GoRoute(
            path: '/pay',
            builder: (_, _) => const Scaffold(body: Text('Pay composer')),
          ),
        ],
      );
      final before = container.read(swapStateProvider);
      present();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) => AppTheme(
              data: AppThemeData.dark,
              child: CrossChainPaymentRequestHost(
                router: router,
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keep editing'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('cross_chain_payment_request_$action')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Payment request'), findsNothing);
      expect(find.text('Swap composer'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/swap');
      expect(container.read(swapStateProvider), same(before));
      expect(recipients, action == 'edit' ? [_recipient] : isEmpty);
      expect(cancellations, action == 'cancel' ? 1 : 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }

  test(
    'a different incoming request cannot consume a previous editor origin',
    () {
      final pending = container.read(
        paymentRequestInputOriginProvider.notifier,
      );
      pending.set('scan', origin());
      expect(pending.take('other'), isNull);
      expect(pending.take('scan'), isNull);
    },
  );
}

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'first', name: 'First', order: 0)],
    activeAccountUuid: 'first',
  );

  void switchToSecondAccount() =>
      state = AsyncData(state.value!.copyWith(activeAccountUuid: 'second'));
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  @override
  void lock() => state = state.copyWith(isUnlocked: false);
}

class _Composer extends SwapNotifier {
  @override
  SwapState build() => const SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '10',
    receiveAmountText: '100',
    destinationText: 'previous recipient',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
  );
}

class _Privacy extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}
