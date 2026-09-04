@Tags(['mobile'])
library;

// The mobile half of the locked -> unlock -> claim leg of a `zcash:` payment
// link. See the desktop sibling (unlock_screen_payment_uri_test.dart) for why
// password verification is faked here.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_unlock_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _passcode = '123456';
const _wrongPasscode = '999999';

const _parkedRequest = SendPrefillArgs(
  id: 'payment-uri-1',
  source: kPaymentUriPrefillSource,
  address:
      'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
      '73d57f73c6dc05121591a83861cd190591',
  amountText: '0.5',
  label: 'Coffee shop',
);

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> unlock(String password) async {
    if (password != _passcode) return false;
    state = state.copyWith(isUnlocked: true);
    return true;
  }
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1unlockedaddress',
  );

  @override
  Future<void> restoreAfterUnlock() async {}
}

class _FakeUnlockSyncNotifier extends FakeSyncNotifier {
  _FakeUnlockSyncNotifier() : super(SyncState());

  @override
  Future<void> refreshAfterUnlock() async {}

  @override
  Future<void> startSyncAnyway() async {}
}

/// No biometric affordance: the passcode path is the one under test, and the
/// real notifier probes the platform.
class _NoBiometricNotifier extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async => BiometricUnlockState.initial;
}

PaymentRequestPrecheck _stubPrecheck() => PaymentRequestPrecheck(
  readNetworkName: () => kZcashDefaultNetworkName,
  spendableIsAuthoritativeNow: () => true,
  validateAddress: ({required String address, required String network}) async =>
      rust_sync.AddressValidationResult(
        isValid: false,
        addressType: '',
        wrongNetwork: false,
      ),
  proposeTransfer:
      ({
        required String accountUuid,
        required String sendFlowId,
        required String address,
        required String addressType,
        required BigInt amountZatoshi,
        String? memo,
        bool isPaymentRequest = false,
        String? requestedBy,
        BigInt? requestedAmountZatoshi,
      }) async => throw UnimplementedError('not reached'),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
      }) async => true,
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/unlock',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: false,
  passwordRotationRecoveryFailed: false,
);

List<Override> _overrides({required bool migrationGate}) => [
  appBootstrapProvider.overrideWithValue(_bootstrap()),
  appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
  accountProvider.overrideWith(_FakeAccountNotifier.new),
  syncProvider.overrideWith(_FakeUnlockSyncNotifier.new),
  biometricUnlockProvider.overrideWith(_NoBiometricNotifier.new),
  migrationSendGateProvider.overrideWithValue(migrationGate),
  paymentRequestPrecheckProvider.overrideWithValue(_stubPrecheck()),
];

late GoRouter _router;

Future<ProviderContainer> _pumpUnlock(
  WidgetTester tester, {
  bool migrationGate = false,
}) async {
  tester.view.physicalSize = const Size(520, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: _overrides(migrationGate: migrationGate),
  );
  addTearDown(container.dispose);

  _router = GoRouter(
    initialLocation: '/unlock',
    routes: [
      GoRoute(
        path: '/unlock',
        builder: (_, _) => const MobileUnlockScreen(autoPromptBiometric: false),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('home-route')),
      ),
      GoRoute(
        path: '/payment-links',
        builder: (_, _) => const Scaffold(body: Text('payment-links-route')),
      ),
    ],
  );
  addTearDown(_router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _enterPasscode(WidgetTester tester, String passcode) async {
  for (final digit in passcode.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

String _location() => _router.routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('a fresh parked link becomes a card over the unlocked wallet', (
    tester,
  ) async {
    final container = await _pumpUnlock(tester);
    container.read(paymentUriPrefillProvider.notifier).set(_parkedRequest);

    await _enterPasscode(tester, _passcode);

    expect(_location(), '/home');
    final flow = container.read(paymentRequestFlowProvider);
    expect(flow, isNotNull);
    expect(flow!.prefill.id, _parkedRequest.id);
    expect(flow.view.source, PaymentRequestSource.link);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(find.text(kPaymentUriExpiredMessage), findsNothing);
  });

  testWidgets('a link parked past the TTL is dropped and said out loud', (
    tester,
  ) async {
    final container = await _pumpUnlock(tester);
    container.read(paymentUriPrefillProvider.notifier)
      ..set(_parkedRequest)
      ..debugAgePark(kPaymentUriParkTtl + const Duration(seconds: 1));

    await _enterPasscode(tester, _passcode);

    expect(_location(), '/home');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(find.text(kPaymentUriExpiredMessage), findsOneWidget);
  });

  testWidgets('a migration send gate that closed while locked drops the link', (
    tester,
  ) async {
    // `migrationSendGateProvider` reads an Ironwood presentation that is still
    // unresolved while the wallet is locked, so it can be false when the link
    // parks and true once the unlock has restored the account. Delivering the
    // card anyway would offer a send mobile Home has already disabled.
    final container = await _pumpUnlock(tester, migrationGate: true);
    container.read(paymentUriPrefillProvider.notifier).set(_parkedRequest);

    await _enterPasscode(tester, _passcode);

    expect(_location(), '/home');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(find.text(kPaymentUriMigrationSendGateMessage), findsOneWidget);
  });

  testWidgets('a failed unlock leaves the link parked', (tester) async {
    final container = await _pumpUnlock(tester);
    container.read(paymentUriPrefillProvider.notifier).set(_parkedRequest);

    await _enterPasscode(tester, _wrongPasscode);

    expect(_location(), '/unlock');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNotNull);
  });

  // Both link kinds can be waiting on the same unlock: a `zcash:` request
  // parked in the prefill and a Gift Card queued in the intake. They do not
  // compete for one destination — the Gift Card owns the route, the request
  // card is an overlay that lands on top of it — so the unlock delivers both.
  testWidgets('a Gift Card picks the destination and the request card lands '
      'over it', (tester) async {
    final container = await _pumpUnlock(tester);
    container.read(paymentUriPrefillProvider.notifier).set(_parkedRequest);
    expect(
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(_pendingPaymentLink.toUri().toString()),
      PaymentLinkIntakeResult.accepted,
    );

    await _enterPasscode(tester, _passcode);

    expect(_location(), '/payment-links');
    final flow = container.read(paymentRequestFlowProvider);
    expect(flow, isNotNull);
    expect(flow!.prefill.id, _parkedRequest.id);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink,
      isNotNull,
      reason: 'the Payment Links screen claims the Gift Card, not the unlock',
    );
  });

  testWidgets('a Gift Card alone routes to the Payment Links screen', (
    tester,
  ) async {
    final container = await _pumpUnlock(tester);
    expect(
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(_pendingPaymentLink.toUri().toString()),
      PaymentLinkIntakeResult.accepted,
    );

    await _enterPasscode(tester, _passcode);

    expect(_location(), '/payment-links');
    expect(container.read(paymentRequestFlowProvider), isNull);
  });
}

final _pendingPaymentLink = VizorPaymentLink(
  network: 'main',
  address: 'u1pendinggiftcardaddress',
  amountZatoshi: BigInt.from(100000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Gift Card',
  createdAt: DateTime.utc(2026, 8, 28),
);
