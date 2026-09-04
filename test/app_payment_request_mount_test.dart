/// The app shell has to actually mount the payment-request host.
///
/// Every other test in this lane drives `PaymentRequestHost` directly, or
/// asserts on `paymentRequestFlowProvider`, so a shell that presents a request
/// and then renders nothing over the screen would pass all of them. This one
/// pumps the real `ZcashWalletApp`, hands the native link stream a `zcash:`
/// URI, and requires the card to appear over the desktop shell.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_surface.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

import 'fakes/fake_sync_notifier.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _link = 'zcash:$_address?amount=0.5&label=Coffee%20shop';

void main() {
  testWidgets('a delivered payment request is presented over the shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final incomingUris = _FakeIncomingUriService();
    addTearDown(incomingUris.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          accountProvider.overrideWith(_FakeAccountNotifier.new),
          syncProvider.overrideWith(() => FakeSyncNotifier(_syncedSyncState)),
          incomingUriServiceProvider.overrideWithValue(incomingUris),
          paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
          addressBookProvider.overrideWith(_EmptyAddressBookNotifier.new),
          ownAccountAddressesProvider.overrideWith((ref) async => const {}),
          zecHomeUsdUnitPriceProvider.overrideWithValue(null),
          migrationSendGateProvider.overrideWithValue(false),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await _pumpUntilPresent(tester, find.byType(ZcashWalletApp));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
      listen: false,
    );

    incomingUris.emit(_link);
    await _pumpUntilPresent(tester, find.byType(PaymentRequestSurface));

    expect(
      container.read(paymentRequestFlowProvider),
      isNotNull,
      reason: 'the link has to reach the flow before the mount can be blamed',
    );
    expect(
      find.byType(PaymentRequestSurface),
      findsOneWidget,
      reason: 'the shell must mount PaymentRequestHost over the router',
    );
    expect(
      find.byKey(const ValueKey('payment_request_host_surface')),
      findsOneWidget,
    );
    expect(find.text('Payment request'), findsOneWidget);
  });
}

Future<void> _pumpUntilPresent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

class _FakeIncomingUriService extends IncomingUriService {
  final StreamController<String> _uris = StreamController<String>.broadcast();

  @override
  Stream<String> get uriStream => _uris.stream;

  @override
  Future<void> initialize() async {}

  void emit(String uri) => _uris.add(uri);

  @override
  Future<void> dispose() async {
    await _uris.close();
  }
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1active',
  );
}

class _EmptyAddressBookNotifier extends AddressBookNotifier {
  @override
  Future<AddressBookState> build() async => const AddressBookState();
}

PaymentRequestPrecheck _readyPrecheck() => PaymentRequestPrecheck(
  readNetworkName: () => kZcashDefaultNetworkName,
  spendableIsAuthoritativeNow: () => true,
  validateAddress: ({required String address, required String network}) async =>
      rust_sync.AddressValidationResult(
        isValid: true,
        addressType: 'unified',
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
      }) async => SendReviewArgs(
        proposalId: BigInt.from(11),
        sendFlowId: sendFlowId,
        proposalAccountUuid: accountUuid,
        address: address,
        addressType: addressType,
        amountZatoshi: amountZatoshi,
        feeZatoshi: BigInt.from(10000),
        needsSaplingParams: false,
        isPaymentRequest: isPaymentRequest,
        requestedBy: requestedBy,
        requestedAmountZatoshi: requestedAmountZatoshi,
      ),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
      }) async => true,
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1active',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _syncedSyncState = SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  isSyncComplete: true,
  chainTipHeight: 3000000,
  scannedHeight: 3000000,
  spendableBalance: BigInt.from(100000000),
);
