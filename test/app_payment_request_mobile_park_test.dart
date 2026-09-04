@Tags(['mobile'])
/// Mobile has no answer for a payment request card yet, so the shell must not
/// present one.
///
/// `PaymentRequestSurface` draws a mobile sheet already, and the host is
/// mounted on both form factors, so a delivered request *would* render here.
/// But the host's two answers still carry the desktop route payloads that the
/// mobile routes reject, and Review hands off a live Rust proposal on the way
/// out. This test is the desktop mount test's opposite number: the same link,
/// on the same shell, has to leave the link parked and nothing on screen.
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
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
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
  testWidgets('a delivered payment request stays parked on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final incomingUris = _FakeIncomingUriService();
    addTearDown(incomingUris.dispose);

    var proposals = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          accountProvider.overrideWith(_FakeAccountNotifier.new),
          syncProvider.overrideWith(() => FakeSyncNotifier(_syncedSyncState)),
          incomingUriServiceProvider.overrideWithValue(incomingUris),
          paymentRequestPrecheckProvider.overrideWithValue(
            _readyPrecheck(onPropose: () => proposals++),
          ),
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
    // Long enough for the drain's post-frame pass *and* for a pre-check to
    // have finished, so "nothing on screen" cannot just mean "not yet".
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      container.read(paymentUriPrefillProvider),
      isNotNull,
      reason: 'the link has to stay parked, not be dropped',
    );
    expect(
      container.read(paymentRequestFlowProvider),
      isNull,
      reason: 'no card may take ownership of the link on mobile yet',
    );
    expect(
      proposals,
      0,
      reason:
          'the pre-check reserves the wallet inputs; nothing may hold them '
          'behind a card mobile cannot answer',
    );
    expect(find.byType(PaymentRequestSurface), findsNothing);
    expect(
      find.byKey(const ValueKey('payment_request_host_surface')),
      findsNothing,
    );
    expect(find.text('Payment request'), findsNothing);
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

PaymentRequestPrecheck _readyPrecheck({required VoidCallback onPropose}) =>
    PaymentRequestPrecheck(
      spendableIsAuthoritativeNow: () => true,
      validateAddress:
          ({required String address, required String network}) async =>
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
          }) async {
            onPropose();
            return SendReviewArgs(
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
            );
          },
      discardProposal:
          ({
            required BigInt proposalId,
            required String sendFlowId,
            required String logContext,
          }) async {},
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
