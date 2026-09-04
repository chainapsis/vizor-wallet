import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

/// Shared by the desktop and mobile Gift Card navigation suites: they live in
/// separate files because only the mobile one runs in the mobile token lane.

class PendingClaimPaymentLinkOperations implements PaymentLinkOperations {
  @override
  Future<PaymentLinkFundingQuote> quoteMaxFunding({
    required String sourceAccountUuid,
  }) => throw UnimplementedError();

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async =>
      const [];

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() async =>
      const [];

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async => const {};

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records,
  ) async => records;

  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async => PaymentLinkClaimSession(
    link: link,
    destinationAddress: 'u1receiver',
    destinationAccountUuid: 'account-1',
    directory: Directory('/tmp/vizor-payment-link-navigation-test'),
    dbPath: '/tmp/vizor-payment-link-navigation-test/wallet.db',
    accountUuid: 'payment-link-account',
    totalZatoshi: link.amountZatoshi,
    claimableZatoshi: link.amountZatoshi,
    feeZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    fundingConfirmationCount: kPaymentLinkClaimConfirmationTarget,
  );

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {}

  @override
  Future<void> retainPendingClaim(PaymentLinkClaimSession session) async {}

  @override
  Future<void> keepReceivedLink(VizorPaymentLink link) async {}

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) => throw UnimplementedError();

  @override
  Future<PaymentLinkFundingResult> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) => throw UnimplementedError();

  @override
  Future<void> retryFundingMetadata({
    required String address,
    required String fundingTxids,
  }) => throw UnimplementedError();

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) => throw UnimplementedError();

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) => throw UnimplementedError();
}

Future<void> pumpUntilPresent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

final paymentLinkNavigationLink = VizorPaymentLink(
  network: 'main',
  address: 'u1paymentlinkaddress',
  amountZatoshi: BigInt.from(100000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
);

final readyPaymentLinkBootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1testaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
