// The locked -> unlock -> claim leg of a `zcash:` payment link. The drain
// policy answers `wait` on /unlock precisely so the unlock screen owns the
// handoff, so nothing else in the fast lane covers it.
//
// Password verification itself is faked: these tests are about what the screen
// does with the parked link once the unlock has succeeded, and the real
// `AppSecureStore` path serialises through a lock whose first future is created
// outside the test's fake-async zone.
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
import 'package:zcash_wallet/src/core/widgets/password_text_field.dart';
import 'package:zcash_wallet/src/features/onboarding/unlock_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _password = 'Password1!';

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
    if (password != _password) return false;
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

/// The post-unlock sync hooks are the awaits the claim deliberately sits
/// behind; they must not reach Rust here.
class _FakeUnlockSyncNotifier extends FakeSyncNotifier {
  _FakeUnlockSyncNotifier() : super(SyncState());

  @override
  Future<void> refreshAfterUnlock() async {}

  @override
  Future<void> startSyncAnyway() async {}
}

/// Ends the card's pre-check without touching Rust: the claim is what these
/// tests are about, not the verdict the card lands on.
PaymentRequestPrecheck _stubPrecheck() => PaymentRequestPrecheck(
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
      }) async {},
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
  migrationSendGateProvider.overrideWithValue(migrationGate),
  paymentRequestPrecheckProvider.overrideWithValue(_stubPrecheck()),
];

late GoRouter _router;

Future<ProviderContainer> _pumpUnlock(
  WidgetTester tester, {
  bool migrationGate = false,
}) async {
  tester.view.physicalSize = const Size(1440, 1024);
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
      GoRoute(path: '/unlock', builder: (_, _) => const UnlockScreen()),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('home-route')),
      ),
      GoRoute(
        path: '/lost-password',
        builder: (_, _) => const Scaffold(body: Text('lost-password-route')),
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

Future<void> _unlock(WidgetTester tester) async {
  await tester.enterText(find.byType(PasswordTextField), _password);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('unlock_submit_button')));
  await tester.pumpAndSettle();
}

String _location() => _router.routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('a fresh parked link becomes a card over the unlocked wallet', (
    tester,
  ) async {
    final container = await _pumpUnlock(tester);
    container.read(paymentUriPrefillProvider.notifier).set(_parkedRequest);

    await _unlock(tester);

    expect(_location(), '/home');
    final flow = container.read(paymentRequestFlowProvider);
    expect(flow, isNotNull);
    expect(flow!.prefill.id, _parkedRequest.id);
    expect(flow.view.source, PaymentRequestSource.link);
    // Claimed, so a later drain cannot deliver the same link a second time.
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

    await _unlock(tester);

    expect(_location(), '/home');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(find.text(kPaymentUriExpiredMessage), findsOneWidget);
  });

  testWidgets('a migration send gate that closed while locked drops the link', (
    tester,
  ) async {
    // The gate reads an Ironwood presentation that is still unresolved while
    // the wallet is locked, so it can be false when the link parks and true
    // once the unlock has restored the account. The claim runs the drain
    // policy for exactly this.
    final container = await _pumpUnlock(tester, migrationGate: true);
    container.read(paymentUriPrefillProvider.notifier).set(_parkedRequest);

    await _unlock(tester);

    expect(_location(), '/home');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(find.text(kPaymentUriMigrationSendGateMessage), findsOneWidget);
  });

  testWidgets('a failed unlock leaves the link parked', (tester) async {
    final container = await _pumpUnlock(tester);
    container.read(paymentUriPrefillProvider.notifier).set(_parkedRequest);

    await tester.enterText(find.byType(PasswordTextField), 'WrongPass1!');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('unlock_submit_button')));
    await tester.pumpAndSettle();

    expect(_location(), '/unlock');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNotNull);
  });

  // The desktop runners never register the HTTPS deeplink, so a queued Gift
  // Card here can only have come from inside the app. Desktop unlock keeps its
  // single destination; the mobile sibling is the one with the branch.
  testWidgets('a queued Gift Card does not divert the desktop unlock', (
    tester,
  ) async {
    final container = await _pumpUnlock(tester);
    expect(
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(_pendingPaymentLink.toUri().toString()),
      PaymentLinkIntakeResult.accepted,
    );

    await _unlock(tester);

    expect(_location(), '/home');
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
