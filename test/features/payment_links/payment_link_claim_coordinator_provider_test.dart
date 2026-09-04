import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_lifecycle_registry_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'different claims submit concurrently while duplicate claims join',
    () async {
      final first = Completer<PaymentLinkClaimResult>();
      final second = Completer<PaymentLinkClaimResult>();
      final submissions = <String>[];
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
            () async => const [],
          ),
          paymentLinkClaimSubmitterProvider.overrideWithValue((session) {
            submissions.add(session.link.address);
            return session.link.address == 'claim-1'
                ? first.future
                : second.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      final firstSession = _session('claim-1');
      final secondSession = _session('claim-2');

      final firstResult = coordinator.submit(firstSession);
      final duplicateResult = coordinator.submit(firstSession);
      final secondResult = coordinator.submit(secondSession);
      await Future<void>.delayed(Duration.zero);

      expect(identical(firstResult, duplicateResult), isTrue);
      expect(submissions, ['claim-1', 'claim-2']);
      expect(coordinator.activeSubmissionCount, 2);

      first.complete(_result('tx-1'));
      second.complete(_result('tx-2'));
      expect((await firstResult).txids, 'tx-1');
      expect((await secondResult).txids, 'tx-2');
      expect(coordinator.activeSubmissionCount, 0);
    },
  );

  test('submitting claims resume outside the Gift Card screen', () async {
    var recoveryCalls = 0;
    final secondCall = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
        paymentLinkClaimRecoveryRetryDelayProvider.overrideWithValue(
          const Duration(milliseconds: 1),
        ),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
          recoveryCalls++;
          if (recoveryCalls == 1) return [_submittingRecord];
          if (!secondCall.isCompleted) secondCall.complete();
          return [_receivedRecord];
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(paymentLinkClaimCoordinatorProvider);
    await secondCall.future.timeout(const Duration(seconds: 1));

    expect(recoveryCalls, 2);
  });

  test('locked startup waits until unlock before restoring claims', () async {
    final security = _MutableSecurityNotifier(locked: true);
    final restored = Completer<void>();
    var recoveryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(() => security),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
          recoveryCalls++;
          if (!restored.isCompleted) restored.complete();
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(paymentLinkClaimCoordinatorProvider);
    await Future<void>.delayed(Duration.zero);
    expect(recoveryCalls, 0);

    security.unlockForTest();
    await restored.future.timeout(const Duration(seconds: 1));
    expect(recoveryCalls, 1);
  });

  test('wallet reset lifecycle drains and pauses active claims', () async {
    final first = Completer<PaymentLinkClaimResult>();
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
          () async => const [],
        ),
        paymentLinkClaimSubmitterProvider.overrideWithValue((session) {
          if (session.link.address == 'claim-1') return first.future;
          return Future.value(_result('tx-2'));
        }),
      ],
    );
    addTearDown(container.dispose);
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    final lifecycle = container.read(paymentLinkClaimLifecycleRegistryProvider);
    final firstSubmission = coordinator.submit(_session('claim-1'));
    await Future<void>.delayed(Duration.zero);

    var drained = false;
    final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);

    expect(drained, isFalse);
    await expectLater(
      coordinator.submit(_session('claim-2')),
      throwsStateError,
    );

    first.complete(_result('tx-1'));
    await firstSubmission;
    await drain;
    expect(coordinator.activeSubmissionCount, 0);

    lifecycle.resume();
    expect((await coordinator.submit(_session('claim-2'))).txids, 'tx-2');
  });

  test('a retention started before a reset drains before it returns', () async {
    final retention = Completer<void>();
    var written = false;
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
          () async => const [],
        ),
      ],
    );
    addTearDown(container.dispose);
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    final lifecycle = container.read(paymentLinkClaimLifecycleRegistryProvider);

    final tracked = coordinator.trackRetention('claim-1', () async {
      await retention.future;
      written = true;
    });
    await Future<void>.delayed(Duration.zero);

    var drained = false;
    final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);

    retention.complete();
    await tracked;
    await drain;

    expect(written, isTrue);
    expect(drained, isTrue);
  });

  test('a retention started after a reset never writes', () async {
    var written = false;
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
          () async => const [],
        ),
      ],
    );
    addTearDown(container.dispose);
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    final lifecycle = container.read(paymentLinkClaimLifecycleRegistryProvider);

    await lifecycle.quiesceAndDrain();
    await coordinator.trackRetention('claim-1', () async => written = true);

    expect(written, isFalse);

    lifecycle.resume();
    await coordinator.trackRetention('claim-1', () async => written = true);
    expect(written, isTrue);
  });
}

PaymentLinkClaimSession _session(String address) {
  final link = _link(address);
  return PaymentLinkClaimSession(
    link: link,
    destinationAddress: 'destination-$address',
    destinationAccountUuid: 'destination-account-$address',
    directory: Directory('/tmp/$address'),
    dbPath: '/tmp/$address/zcash_wallet.db',
    accountUuid: 'claim-account-$address',
    totalZatoshi: BigInt.from(110000),
    claimableZatoshi: BigInt.from(100000),
    feeZatoshi: BigInt.from(10000),
  );
}

VizorPaymentLink _link(String address) => VizorPaymentLink(
  network: 'main',
  address: address,
  amountZatoshi: BigInt.from(100000),
  mnemonic:
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  birthdayHeight: 3000000,
  label: address,
  createdAt: DateTime.utc(2026, 9, 1),
);

PaymentLinkClaimResult _result(String txid) => PaymentLinkClaimResult(
  txids: txid,
  status: PaymentLinkClaimBroadcastStatus.broadcasted,
);

final _receivingRecord = PaymentLinkReceivedRecord(
  network: 'main',
  address: 'claim-1',
  amountZatoshi: BigInt.from(100000),
  createdAt: DateTime.utc(2026, 9, 1),
  artworkId: null,
  status: PaymentLinkReceivedStatus.receiving,
  claimLink: _link('claim-1'),
  destinationAccountUuid: 'destination-account-claim-1',
  claimTxids: 'tx-1',
  updatedAt: DateTime.utc(2026, 9, 1),
);

final _submittingRecord = _receivingRecord.copyWith(
  status: PaymentLinkReceivedStatus.submitting,
  claimTxids: null,
);

final _receivedRecord = _receivingRecord.copyWith(
  status: PaymentLinkReceivedStatus.received,
  claimLink: null,
);

class _UnlockedSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _MutableSecurityNotifier extends AppSecurityNotifier {
  _MutableSecurityNotifier({required this.locked});

  final bool locked;

  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: true, isUnlocked: !locked);

  void unlockForTest() {
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }
}
