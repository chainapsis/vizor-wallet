import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_claim_import_store.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_claim_flow_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_lifecycle_registry_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'a transient preparation timeout is retried without marking the Card failed',
    () async {
      final operations = await _operations();
      var calls = 0;
      final container = _container(
        operations,
        recover: true,
        preparer: (link, {required destinationAccountUuid}) async {
          calls++;
          if (calls == 1) throw TimeoutException('temporary timeout');
          return operations.bindClaimDestination(
            _inspection(),
            destinationAccountUuid: destinationAccountUuid,
          );
        },
      );
      addTearDown(container.dispose);
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      await coordinator.refresh();
      expect(
        (await operations.store.load()).single.availability,
        isNot(PaymentLinkAvailability.failed),
      );
      await coordinator.refresh();
      expect(calls, 2);
      expect(operations.submitCalls, 1);
    },
  );

  test(
    'cancelling a restarted import removes the durable handoff before later account creation',
    () async {
      final journal = GiftClaimImportStore(storage: _ImportStorage());
      await journal.save(
        GiftClaimImportHandoff(link: _link, accountUuidsBeforeSetup: {}),
      );
      journal.resetMemory();
      final operations = _Operations(_Storage());
      final container = _container(
        operations,
        importStore: journal,
        recover: true,
      );
      addTearDown(container.dispose);
      expect(container.read(giftClaimSetupReturnProvider), isNull);
      await container.read(giftClaimSetupReturnProvider.notifier).clear();
      expect(await journal.load(), isNull);
      await container.read(paymentLinkClaimCoordinatorProvider).refresh();
      expect(operations.submitCalls, 0);
      expect(await operations.store.load(), isEmpty);
    },
  );

  for (final before in [
    <String>{},
    {'other-account'},
  ]) {
    test(
      'a restarted import with ${2 - before.length} new accounts restores an unbound Card',
      () async {
        final journal = GiftClaimImportStore(storage: _ImportStorage());
        await journal.save(
          GiftClaimImportHandoff(link: _link, accountUuidsBeforeSetup: before),
        );
        journal.resetMemory();
        final operations = _Operations(_Storage());
        final container = _container(
          operations,
          importStore: journal,
          recover: true,
        );
        addTearDown(container.dispose);
        await container.read(paymentLinkClaimCoordinatorProvider).refresh();
        expect(operations.submitCalls, 0);
        expect((await operations.store.load()).single.setupAccountUuid, isNull);
        expect((await operations.store.load()).single.claimLink, isNotNull);
        expect(await journal.load(), isNull);
      },
    );
  }

  test('import recovery does not race a live recipient choice', () async {
    final journal = GiftClaimImportStore(storage: _ImportStorage());
    await journal.save(
      GiftClaimImportHandoff(link: _link, accountUuidsBeforeSetup: {}),
    );
    final operations = _Operations(_Storage());
    final container = _container(
      operations,
      importStore: journal,
      recover: true,
    );
    addTearDown(container.dispose);
    await container.read(paymentLinkClaimCoordinatorProvider).refresh();
    expect(await operations.store.load(), isEmpty);
    expect(await journal.load(), isNotNull);
    journal.releaseLiveHandoff();
    await container.read(paymentLinkClaimCoordinatorProvider).refresh();
    expect((await operations.store.load()).single.setupAccountUuid, isNull);
    expect(await journal.load(), isNull);
    expect(operations.submitCalls, 0);
  });

  test('Received write failure retains the handoff for retry', () async {
    final journal = GiftClaimImportStore(storage: _ImportStorage());
    await journal.save(
      GiftClaimImportHandoff(link: _link, accountUuidsBeforeSetup: {}),
    );
    journal.resetMemory();
    final storage = _Storage()..failWrites = true;
    final operations = _Operations(storage);
    final container = _container(
      operations,
      importStore: journal,
      recover: true,
    );
    addTearDown(container.dispose);
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    await coordinator.refresh();
    expect(await journal.load(), isNotNull);
    expect(await operations.store.load(), isEmpty);
    storage.failWrites = false;
    await coordinator.refresh();
    expect((await operations.store.load()).single.setupAccountUuid, isNull);
    expect(await journal.load(), isNull);
    expect(operations.submitCalls, 0);
  });

  test('restart recovery preserves an already pinned recipient', () async {
    final journal = GiftClaimImportStore(storage: _ImportStorage());
    await journal.save(
      GiftClaimImportHandoff(link: _link, accountUuidsBeforeSetup: {}),
    );
    journal.resetMemory();
    final operations = await _operations();
    final container = _container(operations, importStore: journal);
    addTearDown(container.dispose);
    await container.read(paymentLinkClaimCoordinatorProvider).refresh();
    expect(
      (await operations.store.load()).single.setupAccountUuid,
      'setup-account',
    );
    expect(await journal.load(), isNull);
  });

  test('import restoration waits for unlock and account metadata', () async {
    final journal = GiftClaimImportStore(storage: _ImportStorage());
    await journal.save(
      GiftClaimImportHandoff(link: _link, accountUuidsBeforeSetup: {}),
    );
    journal.resetMemory();
    final operations = _Operations(_Storage());
    final security = _Security(locked: true);
    final accounts = _RecoveringAccounts();
    final container = _container(
      operations,
      importStore: journal,
      security: security,
      accounts: accounts,
      recover: true,
    );
    addTearDown(container.dispose);
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    await coordinator.refresh();
    expect(await operations.store.load(), isEmpty);
    security.unlockForTest();
    await coordinator.refresh();
    expect(await operations.store.load(), isEmpty);
    expect(await journal.load(), isNotNull);
    accounts.restoreForTest();
    await coordinator.refresh();
    expect((await operations.store.load()).single.setupAccountUuid, isNull);
    expect(await journal.load(), isNull);
    expect(operations.submitCalls, 0);
  });

  test(
    'a malformed import handoff cannot stop an existing Received claim',
    () async {
      final journal = GiftClaimImportStore(
        storage: _ImportStorage()..value = '{',
      );
      final operations = await _operations();
      final container = _container(
        operations,
        importStore: journal,
        recover: true,
      );
      addTearDown(container.dispose);
      await container.read(paymentLinkClaimCoordinatorProvider).refresh();
      expect(operations.submitCalls, 1);
      await expectLater(journal.load(), throwsFormatException);
    },
  );

  test(
    'durable recovery completion wakes an existing UUID after its Card is saved',
    () async {
      final operations = _Operations(_Storage());
      final container = _container(operations, recover: true);
      addTearDown(container.dispose);
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      await coordinator.refresh();
      await operations.store.saveReady(
        _link,
        setupAccountUuid: 'setup-account',
      );
      container
          .read(accountSetupRecoveryGenerationProvider.notifier)
          .completed();
      await operations.submissionSaved.future.timeout(
        const Duration(seconds: 1),
      );
      expect(operations.submitCalls, 1);
    },
  );

  test(
    'handoff binds once without a scan and reset drains the submission',
    () async {
      final operations = await _operations();
      operations.bindGate = Completer<void>();
      operations.submitGate = Completer<void>();
      final container = _container(operations);
      addTearDown(container.dispose);
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      final first = coordinator.claimSetupCard(
        _inspection(),
        destinationAccountUuid: 'setup-account',
      );
      final duplicate = coordinator.claimSetupCard(
        _inspection(),
        destinationAccountUuid: 'setup-account',
      );
      expect(identical(first, duplicate), isTrue);
      await expectLater(
        coordinator.claimSetupCard(
          _inspection(),
          destinationAccountUuid: 'other-account',
        ),
        throwsA(isA<PaymentLinkClaimDestinationChangedException>()),
      );
      operations.bindGate!.complete();
      await operations.submissionStarted.future;
      expect(operations.bindCalls, 1);
      expect(operations.inspectCalls, 0);
      expect(
        (await operations.store.load()).single.status,
        PaymentLinkReceivedStatus.submitting,
      );

      var drained = false;
      final drain = container
          .read(paymentLinkClaimLifecycleRegistryProvider)
          .quiesceAndDrain()
          .then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      operations.submitGate!.complete();
      await first;
      await drain;
      expect(drained, isTrue);
      expect(
        (await operations.store.load()).single.destinationAccountUuid,
        'setup-account',
      );
      expect(operations.submitCalls, 1);
    },
  );

  test(
    'a waiting card survives restart and unlock, then appears once in Activity',
    () async {
      final operations = await _operations();
      operations.waiting = true;
      final firstContainer = _container(operations);
      await firstContainer
          .read(paymentLinkClaimCoordinatorProvider)
          .claimSetupCard(
            _inspection(),
            destinationAccountUuid: 'setup-account',
          );
      final waiting = (await operations.store.load()).single;
      expect(waiting.status, PaymentLinkReceivedStatus.readyToClaim);
      expect(waiting.availability, PaymentLinkAvailability.checking);
      expect(
        _activity([waiting], 'setup-account').withPendingClaims([]),
        isEmpty,
      );
      firstContainer.dispose();

      // Reopen the persisted record rather than relying on the first container.
      operations.store = PaymentLinkReceivedStore(operations.storage);
      operations.waiting = false;
      final security = _Security(locked: true);
      final restarted = _container(
        operations,
        security: security,
        recover: true,
      );
      addTearDown(restarted.dispose);
      restarted.read(paymentLinkClaimCoordinatorProvider);
      await Future<void>.delayed(Duration.zero);
      expect(operations.inspectCalls, 0);
      security.unlockForTest();
      await operations.submissionSaved.future;

      final records = await operations.store.load();
      expect(records.single.setupAccountUuid, 'setup-account');
      expect(records.single.destinationAccountUuid, 'setup-account');
      expect(
        restarted.read(accountProvider).value!.activeAccountUuid,
        'other-account',
      );
      final pendingIndex = _activity(records, 'setup-account');
      final pending = pendingIndex.withPendingClaims([]).single;
      expect(pending.txidHex, 'mock-claim-txid');
      expect(pending.txKind, 'receiving');
      expect(
        _activity(records, 'other-account').withPendingClaims([]),
        isEmpty,
      );

      await operations.store.markReceived(address: _link.address);
      final confirmedIndex = _activity(
        await operations.store.load(),
        'setup-account',
      );
      final detected = rust_sync.TransactionInfo(
        txidHex: pending.txidHex,
        minedHeight: BigInt.from(100),
        expiredUnmined: false,
        accountBalanceDelta: _link.amountZatoshi.toInt(),
        fee: BigInt.zero,
        blockTime: BigInt.zero,
        isTransparent: false,
        txKind: 'received',
        displayAmount: _link.amountZatoshi,
        displayPool: 'orchard',
        createdTime: pending.createdTime,
      );
      expect(confirmedIndex.withPendingClaims([detected]), [detected]);
      expect(
        confirmedIndex.metadataFor(detected)!.stableId,
        pendingIndex.metadataFor(pending)!.stableId,
      );
    },
  );

  test(
    'unlock cannot auto-claim until interrupted account setup is restored',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        kPendingAccountMnemonicStorageKey: 'encrypted-journal-fixture',
        kGiftWalletSetupStartedStorageKey: 'true',
      });
      final operations = await _operations();
      final container = _container(operations, recover: true);
      addTearDown(container.dispose);
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      await coordinator.refresh();
      expect(operations.inspectCalls, 0);
      expect(operations.submitCalls, 0);
      FlutterSecureStorage.setMockInitialValues({});
      await coordinator.refresh();
      expect(operations.submitCalls, 1);
    },
  );

  test(
    'restoring the setup account wakes a previously idle recovery',
    () async {
      final operations = await _operations();
      final accounts = _RecoveringAccounts();
      final container = _container(
        operations,
        recover: true,
        accounts: accounts,
      );
      addTearDown(container.dispose);
      await container.read(paymentLinkClaimCoordinatorProvider).refresh();
      expect(operations.submitCalls, 0);
      accounts.restoreForTest();
      await operations.submissionSaved.future;
      expect(operations.submitCalls, 1);
      expect(
        (await operations.store.load()).single.destinationAccountUuid,
        'setup-account',
      );
    },
  );

  for (final availability in [
    PaymentLinkAvailability.failed,
    PaymentLinkAvailability.rejected,
    PaymentLinkAvailability.claimedElsewhere,
    PaymentLinkAvailability.noBalance,
  ]) {
    test(
      '$availability remains available for manual recovery without automatic submission',
      () async {
        final operations = await _operations();
        await operations.store.setAvailability(_link.address, availability);
        final container = _container(operations, recover: true);
        addTearDown(container.dispose);
        await container.read(paymentLinkClaimCoordinatorProvider).refresh();
        expect(operations.inspectCalls, 0);
        expect(operations.submitCalls, 0);
        expect((await operations.store.load()).single.claimLink, isNotNull);
      },
    );
  }

  test(
    'locking during binding preserves the card without submitting it',
    () async {
      final operations = await _operations();
      operations.bindGate = Completer<void>();
      final security = _Security();
      final container = _container(operations, security: security);
      addTearDown(container.dispose);
      final claim = container
          .read(paymentLinkClaimCoordinatorProvider)
          .claimSetupCard(
            _inspection(),
            destinationAccountUuid: 'setup-account',
          );
      await operations.bindingStarted.future;
      security.lockForTest();
      operations.bindGate!.complete();
      await claim;
      expect(operations.submitCalls, 0);
      expect(
        (await operations.store.load()).single.setupAccountUuid,
        'setup-account',
      );
    },
  );

  test(
    'disposing during binding never submits or reads the disposed Ref',
    () async {
      final operations = await _operations();
      operations.bindGate = Completer<void>();
      final container = _container(operations);
      final claim = container
          .read(paymentLinkClaimCoordinatorProvider)
          .claimSetupCard(
            _inspection(),
            destinationAccountUuid: 'setup-account',
          );
      await operations.bindingStarted.future;
      container.dispose();
      operations.bindGate!.complete();
      await claim;
      expect(operations.submitCalls, 0);
      expect((await operations.store.load()).single.claimLink, isNotNull);
    },
  );

  test(
    'a preparer returning another account cannot submit or retain it',
    () async {
      final operations = await _operations();
      operations.returnedAccount = 'other-account';
      final container = _container(operations);
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(paymentLinkClaimCoordinatorProvider)
            .claimSetupCard(
              _inspection(),
              destinationAccountUuid: 'setup-account',
            ),
        throwsA(isA<PaymentLinkClaimDestinationChangedException>()),
      );
      expect(operations.submitCalls, 0);
      expect(operations.retainCalls, 0);
    },
  );
}

Future<_Operations> _operations() async {
  final storage = _Storage();
  final operations = _Operations(storage);
  await operations.store.saveReady(_link, setupAccountUuid: 'setup-account');
  return operations;
}

ProviderContainer _container(
  _Operations operations, {
  _Security? security,
  AccountNotifier? accounts,
  bool recover = false,
  GiftClaimImportStore? importStore,
  PaymentLinkSetupClaimPreparer? preparer,
}) => ProviderContainer(
  overrides: [
    if (importStore != null)
      giftClaimImportStoreProvider.overrideWithValue(importStore),
    if (preparer != null)
      paymentLinkSetupClaimPreparerProvider.overrideWithValue(preparer),
    appSecurityProvider.overrideWith(() => security ?? _Security()),
    accountProvider.overrideWith(() => accounts ?? _Accounts()),
    paymentLinkOperationsProvider.overrideWithValue(operations),
    paymentLinkReceivedStoreProvider.overrideWith((_) => operations.store),
    paymentLinkClaimRecoveryRetryDelayProvider.overrideWithValue(
      const Duration(days: 1),
    ),
    if (!recover)
      paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
        () async => const [],
      ),
  ],
);

GiftCardActivityIndex _activity(
  List<PaymentLinkReceivedRecord> records,
  String uuid,
) => GiftCardActivityIndex.forAccount(
  accountUuid: uuid,
  createdRecords: [],
  receivedRecords: records,
);

final _link = VizorPaymentLink(
  network: 'main',
  address: 'setup-gift',
  amountZatoshi: BigInt.from(100000),
  mnemonic:
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  birthdayHeight: 3000000,
  label: 'Gift',
  createdAt: DateTime.utc(2026, 10, 1),
);

PaymentLinkClaimInspection _inspection() => PaymentLinkClaimInspection(
  link: _link,
  directory: Directory('/tmp/setup-gift'),
  dbPath: '/tmp/setup-gift/wallet.db',
  accountUuid: 'claim-wallet',
  totalZatoshi: BigInt.from(110000),
  claimableZatoshi: _link.amountZatoshi,
  feeZatoshi: BigInt.from(10000),
  fundingConfirmationCount: 6,
  waitingForFundingConfirmations: false,
  availability: PaymentLinkAvailability.available,
);

class _Operations extends Fake implements PaymentLinkOperations {
  _Operations(this.storage) : store = PaymentLinkReceivedStore(storage);
  final _Storage storage;
  PaymentLinkReceivedStore store;
  Completer<void>? bindGate;
  Completer<void>? submitGate;
  final bindingStarted = Completer<void>();
  final submissionStarted = Completer<void>();
  final submissionSaved = Completer<void>();
  bool waiting = false;
  String? returnedAccount;
  int inspectCalls = 0;
  int bindCalls = 0;
  int submitCalls = 0;
  int retainCalls = 0;

  @override
  Future<PaymentLinkClaimInspection> inspectClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    inspectCalls++;
    return _inspection();
  }

  @override
  Future<PaymentLinkClaimSession> bindClaimDestination(
    PaymentLinkClaimInspection inspection, {
    required String destinationAccountUuid,
  }) async {
    bindCalls++;
    if (!bindingStarted.isCompleted) bindingStarted.complete();
    await bindGate?.future;
    return PaymentLinkClaimSession(
      link: inspection.link,
      destinationAddress: 'u1setupaccount',
      destinationAccountUuid: returnedAccount ?? destinationAccountUuid,
      directory: inspection.directory,
      dbPath: inspection.dbPath,
      accountUuid: inspection.accountUuid,
      totalZatoshi: inspection.totalZatoshi,
      claimableZatoshi: inspection.claimableZatoshi,
      feeZatoshi: inspection.feeZatoshi,
      waitingForFundingConfirmations: waiting,
      isSetupClaim: true,
      availability: PaymentLinkAvailability.available,
    );
  }

  @override
  Future<void> retainPendingClaim(PaymentLinkClaimSession session) async {
    retainCalls++;
    await store.setAvailability(
      session.link.address,
      PaymentLinkAvailability.checking,
    );
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    submitCalls++;
    await store.markClaimStarted(
      address: session.link.address,
      destinationAccountUuid: session.destinationAccountUuid,
    );
    if (!submissionStarted.isCompleted) submissionStarted.complete();
    await submitGate?.future;
    await store.markReceiving(
      address: session.link.address,
      destinationAccountUuid: session.destinationAccountUuid,
      claimTxids: 'mock-claim-txid',
      claimDestinationPool: 'orchard',
    );
    if (!submissionSaved.isCompleted) submissionSaved.complete();
    return const PaymentLinkClaimResult(
      txids: 'mock-claim-txid',
      status: PaymentLinkClaimBroadcastStatus.broadcasted,
    );
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() =>
      store.load();

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records, {
    bool allowResubmit = true,
  }) => store.load();
}

class _Storage implements PaymentLinkReceivedStorage {
  String? value;
  bool failWrites = false;
  @override
  Future<void> delete() async => value = null;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failWrites) throw StateError('Received storage unavailable');
    value = next;
  }
}

class _Security extends AppSecurityNotifier {
  _Security({this.locked = false});
  final bool locked;
  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: true, isUnlocked: !locked);
  void unlockForTest() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: true,
  );
  void lockForTest() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
  );
}

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(uuid: 'setup-account', name: 'Gift', order: 0),
      AccountInfo(uuid: 'other-account', name: 'Other', order: 1),
    ],
    activeAccountUuid: 'other-account',
    activeAddress: 'u1otheraccount',
  );
}

class _RecoveringAccounts extends _Accounts {
  @override
  AccountState build() => const AccountState();

  void restoreForTest() => state = AsyncData(super.build());
}

class _ImportStorage implements GiftClaimImportStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> delete() async => value = null;
}
