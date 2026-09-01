import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_recovery_coordinator.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup recovers sender and receiver work concurrently', () async {
    final createdGate = Completer<void>();
    final receivedGate = Completer<void>();
    final operations = _CoordinatorPaymentLinkOperations(
      created: [_createdDraft],
      received: [_receivingRecord],
      createdGate: createdGate,
      receivedGate: receivedGate,
    );
    final container = _container(operations);
    addTearDown(container.dispose);

    container.read(paymentLinkRecoveryCoordinatorProvider);
    await Future<void>.delayed(Duration.zero);

    expect(operations.createdInspections, 1);
    expect(operations.receivedInspections, 1);
    createdGate.complete();
    receivedGate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(paymentLinkRecoveryCoordinatorProvider), 1);
  });

  test(
    'startup stops after secure-store reads when no recovery is pending',
    () async {
      final operations = _CoordinatorPaymentLinkOperations(
        created: [
          _createdDraft.copyWith(
            state: PaymentLinkRecoveryState.funded,
            updatedAt: DateTime.utc(2026, 8, 5, 1),
            fundingTxids: 'funding-txid',
          ),
        ],
      );
      final container = _container(operations);
      addTearDown(container.dispose);

      container.read(paymentLinkRecoveryCoordinatorProvider);
      await Future<void>.delayed(Duration.zero);

      expect(operations.createdLoads, 1);
      expect(operations.receivedLoads, 1);
      expect(operations.createdInspections, 0);
      expect(operations.receivedInspections, 0);
    },
  );
}

ProviderContainer _container(PaymentLinkOperations operations) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/home',
          initialAccountState: const AccountState(
            accounts: [AccountInfo(uuid: 'account-1', name: 'Main', order: 0)],
            activeAccountUuid: 'account-1',
            activeAddress: 'u1receiver',
          ),
          initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('account-1'),
          network: 'main',
          rpcEndpointConfig: defaultRpcEndpointConfig('main'),
          themeMode: ThemeMode.system,
          privacyModeEnabled: false,
          isPasswordConfigured: true,
          isUnlocked: true,
          passwordRotationRecoveryFailed: false,
        ),
      ),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      paymentLinkOperationsProvider.overrideWithValue(operations),
    ],
  );
}

final _link = VizorPaymentLink(
  network: 'main',
  address: 'u1coordinatorpaymentlink',
  amountZatoshi: BigInt.from(100000),
  mnemonic:
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  birthdayHeight: 3_456_789,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 5),
);

final _createdDraft = PaymentLinkRecoveryRecord(
  link: _link,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.draft,
  updatedAt: DateTime.utc(2026, 8, 5),
);

final _receivingRecord = PaymentLinkReceivedRecord.fromLink(_link).copyWith(
  status: PaymentLinkReceivedStatus.receiving,
  destinationAccountUuid: 'account-1',
  claimTxids: 'claim-txid',
);

class _CoordinatorPaymentLinkOperations implements PaymentLinkOperations {
  _CoordinatorPaymentLinkOperations({
    this.created = const [],
    this.received = const [],
    this.createdGate,
    this.receivedGate,
  });

  final List<PaymentLinkRecoveryRecord> created;
  final List<PaymentLinkReceivedRecord> received;
  final Completer<void>? createdGate;
  final Completer<void>? receivedGate;
  int createdLoads = 0;
  int receivedLoads = 0;
  int createdInspections = 0;
  int receivedInspections = 0;

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async {
    createdLoads++;
    return created;
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() async {
    receivedLoads++;
    return received;
  }

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    createdInspections++;
    await createdGate?.future;
    return const {};
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims() async {
    receivedInspections++;
    await receivedGate?.future;
    return received;
  }

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
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) => throw UnimplementedError();

  @override
  Future<PaymentLinkClaimSession> prepareClaim(VizorPaymentLink link) =>
      throw UnimplementedError();

  @override
  Future<void> claimPreparedLink(PaymentLinkClaimSession session) =>
      throw UnimplementedError();

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) =>
      throw UnimplementedError();
}
