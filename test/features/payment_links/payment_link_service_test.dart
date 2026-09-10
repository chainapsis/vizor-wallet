import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_lifecycle_registry_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import '../../fakes/fake_sync_notifier.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'orphan cleanup preserves other accounts and networks and retries file failures',
    () async {
      final store = PaymentLinkReceivedStore(
        _PaymentLinkServiceReceivedStorage(),
      );
      final link = _link();
      for (final entry in [('deleted', 'main'), ('existing', 'main')]) {
        final scoped = VizorPaymentLink(
          network: entry.$2,
          address: entry.$1,
          amountZatoshi: link.amountZatoshi,
          mnemonic: link.mnemonic,
          birthdayHeight: link.birthdayHeight,
          label: link.label,
          createdAt: link.createdAt,
        );
        await store.saveReady(scoped);
        await store.markClaimStarted(
          address: scoped.address,
          destinationAccountUuid: scoped.address,
        );
        await store.markReceiving(
          address: scoped.address,
          destinationAccountUuid: scoped.address,
          claimTxids: 'claim-${scoped.address}',
        );
        await store.markReceived(address: scoped.address);
      }
      final attempted = <String>[];
      final onOtherNetwork = await discardPaymentLinkClaimsForDeletedAccounts(
        records: await store.load(),
        network: 'test',
        accountUuids: {},
        store: store,
        deleteRetainedWallet: (record) async {
          attempted.add(record.address);
          return true;
        },
      );
      expect(onOtherNetwork, hasLength(2));
      expect(attempted, isEmpty);
      final eligible = await discardPaymentLinkClaimsForDeletedAccounts(
        records: await store.load(),
        network: 'main',
        accountUuids: {'existing'},
        store: store,
        deleteRetainedWallet: (record) async {
          attempted.add(record.address);
          return false;
        },
      );
      expect(eligible.map((r) => r.address), ['existing']);
      expect(attempted, ['deleted']);
      expect((await store.find('deleted'))!.needsClaimRecovery, isTrue);
      await discardPaymentLinkClaimsForDeletedAccounts(
        records: await store.load(),
        network: 'main',
        accountUuids: {'existing'},
        store: store,
        deleteRetainedWallet: (record) async {
          attempted.add(record.address);
          return true;
        },
      );
      expect(attempted, ['deleted', 'deleted']);
      expect((await store.load()).map((r) => r.address), ['existing']);
    },
  );

  test('claim detail lookup resolves display ids to local history ids', () {
    const displayTxid =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final storageTxid = _reverseHexBytes(displayTxid);
    expect(
      paymentLinkClaimDetailTxids(
        claimTxids: displayTxid,
        historyTxids: [storageTxid],
      ),
      [storageTxid],
    );
    expect(
      paymentLinkClaimDestinationPoolFromDetails(
        claimTxids: displayTxid,
        details: [
          rust_sync.TransactionDetail(
            txidHex: storageTxid,
            txKind: 'sent',
            sourcePool: 'shielded',
            outputs: [
              rust_sync.TransactionDetailOutput(
                address: 'unrelated-output',
                amountZatoshi: BigInt.from(1),
                pool: 'shielded',
              ),
              rust_sync.TransactionDetailOutput(
                address: 'destination-ua',
                amountZatoshi: BigInt.from(445000000),
                pool: 'ironwood',
              ),
            ],
          ),
        ],
        destinationAddress: 'destination-ua',
        expectedAmountZatoshi: BigInt.from(445000000),
      ),
      'ironwood',
    );
    // A just-broadcast claim may not be visible in the retained wallet yet;
    // metadata hydration then stays optional instead of blocking the claim.
    expect(
      paymentLinkClaimDetailTxids(
        claimTxids: displayTxid,
        historyTxids: const [],
      ),
      isEmpty,
    );
    expect(
      paymentLinkClaimDestinationPoolFromDetails(
        claimTxids: displayTxid,
        details: const [],
        destinationAddress: 'destination-ua',
        expectedAmountZatoshi: BigInt.from(445000000),
      ),
      isNull,
    );
  });

  test(
    'pool enrichment requires every claim detail and destination output',
    () {
      rust_sync.TransactionDetail detail(
        String txid,
        String pool, {
        String address = 'destination',
      }) => rust_sync.TransactionDetail(
        txidHex: txid,
        txKind: 'sent',
        outputs: [
          rust_sync.TransactionDetailOutput(
            address: address,
            amountZatoshi: BigInt.from(50000),
            pool: pool,
          ),
        ],
      );
      String? pool(List<rust_sync.TransactionDetail> details) =>
          paymentLinkClaimDestinationPoolFromDetails(
            claimTxids: 'a,b',
            details: details,
            destinationAddress: 'destination',
            expectedAmountZatoshi: BigInt.from(100000),
          );
      // Both missing local history and a failed detail lookup yield a subset.
      expect(
        paymentLinkClaimDetailTxids(claimTxids: 'a,b', historyTxids: ['a']),
        ['a'],
      );
      expect(pool([detail('a', 'ironwood')]), isNull);
      expect(
        pool([detail('a', 'ironwood'), detail('unrelated', 'ironwood')]),
        isNull,
      );
      expect(pool([detail('a', 'ironwood'), detail('a', 'ironwood')]), isNull);
      expect(pool([detail('a', 'ironwood'), detail('b', 'orchard')]), isNull);
      expect(pool([detail('a', 'ironwood'), detail('b', '')]), isNull);
      expect(
        pool([
          detail('a', 'ironwood'),
          detail('b', 'ironwood', address: 'other'),
        ]),
        isNull,
      );
      expect(
        pool([detail('a', 'ironwood'), detail('b', 'ironwood')]),
        'ironwood',
      );
      expect(
        pool([
          detail('b', 'ironwood'),
          detail('a', 'ironwood'),
          detail('other', 'orchard'),
        ]),
        'ironwood',
      );
    },
  );

  group('claim destination hydration', () {
    final api = _ClaimDestinationRustApi();
    late _ClaimDestinationAccountNotifier accounts;
    late ProviderContainer container;
    late PaymentLinkService service;
    late Directory supportDirectory;
    late _PaymentLinkServiceReceivedStorage receivedStorage;
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    setUpAll(() => RustLib.initMock(api: api));
    tearDownAll(RustLib.dispose);

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      supportDirectory = await Directory.systemTemp.createTemp(
        'vizor-claim-destination-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathChannel,
            (_) async => supportDirectory.path,
          );
      api.reset();
      accounts = _ClaimDestinationAccountNotifier();
      receivedStorage = _PaymentLinkServiceReceivedStorage();
      container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(() => accounts),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              SyncState(scannedHeight: 100, chainTipHeight: 100),
            ),
          ),
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          rpcEndpointProvider.overrideWith(_ClaimDestinationRpcNotifier.new),
          paymentLinkRecoveryStoreProvider.overrideWithValue(
            PaymentLinkRecoveryStore(_FakePaymentLinkRecoveryStorage()),
          ),
          paymentLinkReceivedStoreProvider.overrideWithValue(
            PaymentLinkReceivedStore(receivedStorage),
          ),
        ],
      );
      await container.read(accountProvider.future);
      service = container.read(paymentLinkServiceProvider);
    });

    tearDown(() async {
      container.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      await supportDirectory.delete(recursive: true);
    });

    for (final oldTransactions in [
      <String>[],
      ['old-attempt'],
    ]) {
      test(
        'legacy submitting without baseline remains protected: $oldTransactions',
        () async {
          api.poolFixture = true;
          api.localClaimTxids = oldTransactions;
          final store = container.read(paymentLinkReceivedStoreProvider);
          final link = _link();
          await store.saveReady(link);
          await store.markClaimStarted(
            address: link.address,
            destinationAccountUuid: 'receiver',
          );
          final payload =
              jsonDecode(receivedStorage.value!) as Map<String, dynamic>;
          final row =
              (payload['records'] as List).single as Map<String, dynamic>;
          for (final field in ['availability', 'archived', 'claimPriorTxids']) {
            row.remove(field);
          }
          receivedStorage.value = jsonEncode(payload);
          final directory = Directory(
            '${supportDirectory.path}/${paymentLinkClaimWalletDirectoryName(link)}',
          );
          await directory.create();
          final db = File('${directory.path}/zcash_wallet.db');
          await db.writeAsString('keep claim wallet');
          for (final allowResubmit in [false, true]) {
            final restored = (await service.inspectReceivedLinkClaims(
              await store.load(),
              allowResubmit: allowResubmit,
            )).single;
            expect(restored.status, PaymentLinkReceivedStatus.submitting);
            expect(restored.availability, PaymentLinkAvailability.checking);
            expect(restored.claimTxids, isNull);
            expect(restored.claimPriorTxids, isNull);
            expect(restored.canArchive, isFalse);
            expect(restored.claimLink!.toUri(), link.toUri());
            expect(await store.countReceivingForAccount('receiver'), 1);
          }
          expect(api.claimSyncCalls, 0);
          expect(await db.readAsString(), 'keep claim wallet');
        },
      );
    }

    test(
      'a known empty baseline can still settle an interrupted new claim',
      () async {
        api.poolFixture = true;
        final store = container.read(paymentLinkReceivedStoreProvider);
        final link = _link();
        await store.saveReady(link);
        await store.markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'receiver',
          priorTxids: [],
        );
        final directory = Directory(
          '${supportDirectory.path}/${paymentLinkClaimWalletDirectoryName(link)}',
        );
        await directory.create();
        await File(
          '${directory.path}/zcash_wallet.db',
        ).writeAsString('claim wallet');
        final restored = (await service.inspectReceivedLinkClaims(
          await store.load(),
          allowResubmit: false,
        )).single;
        expect(restored.status, PaymentLinkReceivedStatus.readyToClaim);
        expect(restored.availability, PaymentLinkAvailability.failed);
        expect(restored.claimLink, isNotNull);
        expect(api.claimSyncModes, [false]);
        expect(await store.countReceivingForAccount('receiver'), 0);
      },
    );

    test(
      'legacy receiving with saved txids still reconciles its receipt',
      () async {
        api.poolFixture = true;
        api.localClaimTxids = ['a', 'b'];
        final store = container.read(paymentLinkReceivedStoreProvider);
        final link = _link();
        await store.saveReady(link);
        await store.markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'receiver',
        );
        await store.markReceiving(
          address: link.address,
          destinationAccountUuid: 'receiver',
          claimTxids: 'a,b',
        );
        final payload =
            jsonDecode(receivedStorage.value!) as Map<String, dynamic>;
        final row = (payload['records'] as List).single as Map<String, dynamic>;
        for (final field in ['availability', 'archived', 'claimPriorTxids']) {
          row.remove(field);
        }
        receivedStorage.value = jsonEncode(payload);
        final directory = Directory(
          '${supportDirectory.path}/${paymentLinkClaimWalletDirectoryName(link)}',
        );
        await directory.create();
        await File(
          '${directory.path}/zcash_wallet.db',
        ).writeAsString('keep claim wallet');
        await container.read(syncProvider.future);
        final restored = (await service.inspectReceivedLinkClaims(
          await store.load(),
          allowResubmit: false,
        )).single;
        expect(restored.status, PaymentLinkReceivedStatus.received);
        expect(restored.claimTxids, 'a,b');
        expect(restored.claimPriorTxids, isNull);
        expect(restored.claimLink, isNotNull); // Only one confirmation so far.
        expect(api.claimSyncModes, [false]);
        expect(await store.countReceivingForAccount('receiver'), 0);
      },
    );

    test(
      'recovery cannot settle a submission still preparing transactions',
      () async {
        api.poolFixture = true;
        api.estimateGate = Completer<rust_sync.SendMaxEstimateResult>();
        final submission = service.claimPreparedLink(_claimSession());
        final failed = expectLater(submission, throwsStateError);
        await api.estimateStarted.future;
        final store = container.read(paymentLinkReceivedStoreProvider);
        expect(
          (await store.load()).single.status,
          PaymentLinkReceivedStatus.submitting,
        );
        final records = await service.inspectReceivedLinkClaims(
          await store.load(),
          allowResubmit: false,
        );
        expect(records.single.status, PaymentLinkReceivedStatus.submitting);
        expect(api.claimSyncCalls, 0);
        api.estimateGate!.completeError(StateError('preparation failed'));
        await failed;
        expect(
          (await store.load()).single.availability,
          PaymentLinkAvailability.failed,
        );
      },
    );

    test('manual and background claim checks serialize their scans', () async {
      api.poolFixture = true;
      api.localClaimTxids = ['pending'];
      api.claimHistory = [_transaction(txid: 'pending', txKind: 'sent')];
      api.syncGate = Completer<void>();
      final store = container.read(paymentLinkReceivedStoreProvider);
      final link = _link();
      await store.saveReady(link);
      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver',
      );
      await store.markReceiving(
        address: link.address,
        destinationAccountUuid: 'receiver',
        claimTxids: 'pending',
      );
      final directory = Directory(
        '${supportDirectory.path}/${paymentLinkClaimWalletDirectoryName(link)}',
      );
      await directory.create();
      await File(
        '${directory.path}/zcash_wallet.db',
      ).writeAsString('claim-wallet');
      await container.read(syncProvider.future);
      final background = service.inspectReceivedLinkClaims(await store.load());
      await api.syncStarted.future;
      final manual = service.inspectReceivedLinkClaims(
        await store.load(),
        allowResubmit: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.claimSyncModes, [true]);
      api.syncGate!.complete();
      await Future.wait([background, manual]);
      expect(api.claimSyncModes, [true, false]);
      expect(
        (await store.load()).single.status,
        PaymentLinkReceivedStatus.receiving,
      );
    });

    test(
      'deleted claim destinations are cleaned before sync or history lookup',
      () async {
        final store = container.read(paymentLinkReceivedStoreProvider);
        final link = _link();
        await store.saveReady(link);
        await store.markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'deleted-account',
        );
        await store.markReceiving(
          address: link.address,
          destinationAccountUuid: 'deleted-account',
          claimTxids: 'claim-tx',
        );
        await store.markReceived(address: link.address);
        final claimDirectory = Directory(
          '${supportDirectory.path}/${paymentLinkClaimWalletDirectoryName(link)}',
        );
        await claimDirectory.create();
        await File(
          '${claimDirectory.path}/zcash_wallet.db',
        ).writeAsString('claim-wallet');
        final unrelated = File('${supportDirectory.path}/unrelated-wallet.db');
        await unrelated.writeAsString('keep');
        // The fake only supports listing the remaining accounts. Any attempted
        // retained-wallet sync or receiver history query fails this test.
        expect(
          await service.inspectReceivedLinkClaims(await store.load()),
          isEmpty,
        );
        expect(await store.load(), isEmpty);
        expect(await claimDirectory.exists(), isFalse);
        expect(await unrelated.readAsString(), 'keep');
      },
    );

    test(
      'restart recovery keeps failed legs and excludes earlier attempts',
      () async {
        api.poolFixture = true;
        api.localClaimTxids = ['old', 'parent', 'child'];
        api.conflictedTxids = ['child'];
        api.claimHistory = [
          _transaction(txid: 'old', txKind: 'sent', expiredUnmined: true),
          _transaction(txid: 'parent', txKind: 'sent', minedHeight: 95),
          _transaction(txid: 'child', txKind: 'sent'),
        ];
        final store = container.read(paymentLinkReceivedStoreProvider);
        final link = _link();
        await store.saveReady(link);
        await store.markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'receiver',
          priorTxids: ['old'],
        );
        expect((await store.load()).single.claimPriorTxids, ['old']);
        final claimDirectory = Directory(
          '${supportDirectory.path}/${paymentLinkClaimWalletDirectoryName(link)}',
        );
        await claimDirectory.create();
        await File(
          '${claimDirectory.path}/zcash_wallet.db',
        ).writeAsString('claim-wallet');
        await container.read(syncProvider.future);
        final recovered = (await service.inspectReceivedLinkClaims(
          await store.load(),
          allowResubmit: false,
        )).single;
        expect(recovered.status, PaymentLinkReceivedStatus.readyToClaim);
        expect(recovered.availability, PaymentLinkAvailability.failed);
        expect(recovered.destinationAccountUuid, isNull);
        expect(recovered.claimLink, isNotNull);
        expect(recovered.claimPriorTxids, isEmpty);

        // A later attempt must not inherit an older failed transaction.
        await store.markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'receiver',
          priorTxids: ['old', 'parent', 'child'],
        );
        api.localClaimTxids.add('fresh');
        api.claimHistory = [_transaction(txid: 'fresh', txKind: 'sent')];
        final pending = (await service.inspectReceivedLinkClaims(
          await store.load(),
          allowResubmit: false,
        )).single;
        expect(pending.status, PaymentLinkReceivedStatus.receiving);
        expect(pending.claimTxids, 'fresh');
      },
    );

    for (final missing in ['history', 'detail']) {
      test(
        'retries incomplete $missing after receipt without restarting the claim',
        () async {
          api.poolFixture = true;
          api.localClaimTxids = missing == 'history' ? ['a'] : ['a', 'b'];
          api.failingDetailTxids = missing == 'detail' ? {'b'} : {};
          final store = container.read(paymentLinkReceivedStoreProvider);
          final link = _link();
          await store.saveReady(link);
          await store.markClaimStarted(
            address: link.address,
            destinationAccountUuid: 'receiver',
          );
          await store.markReceiving(
            address: link.address,
            destinationAccountUuid: 'receiver',
            claimTxids: 'a,b',
          );
          final claimDirectory = Directory(
            '${supportDirectory.path}/${paymentLinkClaimWalletDirectoryName(link)}',
          );
          await claimDirectory.create();
          await File(
            '${claimDirectory.path}/zcash_wallet.db',
          ).writeAsString('claim-wallet');
          await container.read(syncProvider.future);

          final incomplete = (await service.inspectReceivedLinkClaims(
            await store.load(),
          )).single;
          expect(incomplete.status, PaymentLinkReceivedStatus.received);
          expect(incomplete.claimDestinationPool, isNull);
          expect(incomplete.claimLink, isNotNull);

          api.localClaimTxids = ['a', 'b'];
          api.failingDetailTxids = {};
          final enriched = (await service.inspectReceivedLinkClaims(
            await store.load(),
          )).single;
          expect(enriched.claimDestinationPool, 'ironwood');
          expect(enriched.status, PaymentLinkReceivedStatus.received);
          expect(enriched.isClaimInFlight, isFalse);
          expect(enriched.updatedAt, incomplete.updatedAt);
          expect(enriched.claimSubmittedAt, incomplete.claimSubmittedAt);
          expect(enriched.claimLink, isNotNull);
          final lookupCount = api.detailLookups;
          await service.inspectReceivedLinkClaims(await store.load());
          expect(api.detailLookups, lookupCount);
        },
      );
    }

    test(
      'a locked wallet stops before looking up a claim destination',
      () async {
        accounts.select('account-2', null);
        container.read(appSecurityProvider.notifier).lock();

        await expectLater(
          service.prepareClaim(_link()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Wallet is locked.',
            ),
          ),
        );

        expect(api.requestedAccounts, isEmpty);
        expect(api.validatedAddresses, isEmpty);
        expect(container.read(accountProvider).value?.activeAddress, isNull);
      },
    );

    test(
      'locking during lookup keeps the address cleared and stops preparation',
      () async {
        accounts.select('account-2', 'u1previous-account');
        api.lookupGate = Completer<String>();
        final preparing = service.prepareClaim(_link());
        final expectation = expectLater(
          preparing,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Wallet is locked.',
            ),
          ),
        );
        await api.lookupStarted.future;

        container.read(appSecurityProvider.notifier).lock();
        accounts.clearSensitiveStateForLock();
        expect(container.read(accountProvider).value?.activeAddress, isNull);
        api.lookupGate!.complete('u1account-2address');
        await expectation;

        expect(container.read(appSecurityProvider).requiresUnlock, isTrue);
        expect(
          container.read(accountProvider).value?.activeAccountUuid,
          'account-2',
        );
        expect(container.read(accountProvider).value?.activeAddress, isNull);
        expect(api.validatedAddresses, isEmpty);
      },
    );

    for (final cachedAddress in ['u1previous-account', null]) {
      test(
        'preparation resolves the selected account instead of cache $cachedAddress',
        () async {
          accounts.select('account-2', cachedAddress);
          await expectLater(
            service.prepareClaim(_link()),
            throwsA(isA<_DestinationValidated>()),
          );
          expect(api.requestedAccounts, ['account-2']);
          expect(api.validatedAddresses, ['u1account-2address']);
          expect(
            container.read(accountProvider).value?.activeAddress,
            'u1account-2address',
          );
        },
      );
    }

    test(
      'failed address lookups stop preparation and retry without another switch',
      () async {
        accounts.select('account-2', 'u1previous-account');
        api.failures = 2;
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(service.prepareClaim(_link()), throwsStateError);
          expect(api.validatedAddresses, isEmpty);
          expect(
            container.read(accountProvider).value?.activeAccountUuid,
            'account-2',
          );
        }
        await expectLater(
          service.prepareClaim(_link()),
          throwsA(isA<_DestinationValidated>()),
        );
        expect(api.requestedAccounts, ['account-2', 'account-2', 'account-2']);
        expect(api.validatedAddresses, ['u1account-2address']);
        expect(
          container.read(accountProvider).value?.activeAddress,
          'u1account-2address',
        );
      },
    );

    test(
      'an account switch during lookup rejects the obsolete destination',
      () async {
        accounts.select('account-2', 'u1previous-account');
        api.lookupGate = Completer<String>();
        final preparing = service.prepareClaim(_link());
        final expectation = expectLater(
          preparing,
          throwsA(isA<PaymentLinkClaimDestinationChangedException>()),
        );
        await api.lookupStarted.future;
        accounts.select('account-1', 'u1account-1address');
        api.lookupGate!.complete('u1account-2address');
        await expectation;
        expect(api.validatedAddresses, isEmpty);
        expect(
          container.read(accountProvider).value?.activeAccountUuid,
          'account-1',
        );
        expect(
          container.read(accountProvider).value?.activeAddress,
          'u1account-1address',
        );
      },
    );
  });

  test('classifies failures before funding submission starts', () async {
    final failure = StateError('insufficient balance');

    await expectLater(
      runPaymentLinkFundingSubmission<String>((_) => throw failure),
      throwsA(
        isA<PaymentLinkFundingNotSubmittedException>().having(
          (error) => error.error,
          'error',
          same(failure),
        ),
      ),
    );
  });

  test(
    'preserves ambiguous failures after funding submission starts',
    () async {
      final failure = StateError('broadcast result unavailable');

      await expectLater(
        runPaymentLinkFundingSubmission<String>((markSubmissionStarted) {
          markSubmissionStarted();
          throw failure;
        }),
        throwsA(same(failure)),
      );
    },
  );

  test('a funding whose broadcast result is lost stays recoverable', () async {
    final storage = _FakePaymentLinkRecoveryStorage();
    final store = PaymentLinkRecoveryStore(storage);
    final link = _link();
    final failure = StateError('channel closed after broadcast');

    // The composition `createFundedLink` uses: the recovery marker is awaited
    // inside the submission classifier, immediately before the broadcast.
    await expectLater(
      PaymentLinkFundingRecovery(store).fund<String>(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
        currentChainHeight: () async => 3456800,
        createTransaction: (markSubmissionStarted) =>
            runPaymentLinkFundingSubmission((markLocalSubmission) async {
              await markSubmissionStarted();
              markLocalSubmission();
              throw failure;
            }),
        fundingTxids: (txid) => txid,
      ),
      throwsA(same(failure)),
    );

    final record = (await PaymentLinkRecoveryStore(storage).load()).single;
    expect(record.state, PaymentLinkRecoveryState.draft);
    expect(record.fundingTxids, isNull);
    expect(record.submittedAtHeight, 3456800);
    expect(record.isAmbiguousSubmission, isTrue);
    expect(record.link.mnemonic, link.mnemonic);
  });

  test(
    'a funding that never reached the network leaves nothing behind',
    () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final failure = StateError('proposal failed');

      await expectLater(
        PaymentLinkFundingRecovery(store).fund<String>(
          claimFeeReserveZatoshi: BigInt.from(10000),
          link: _link(),
          sourceAccountUuid: 'source-account',
          currentChainHeight: () async => 3456800,
          createTransaction: (markSubmissionStarted) =>
              runPaymentLinkFundingSubmission((_) async => throw failure),
          fundingTxids: (txid) => txid,
        ),
        throwsA(same(failure)),
      );

      expect(await PaymentLinkRecoveryStore(storage).load(), isEmpty);
    },
  );

  test('funding covers the exact recipient amount and claim fee', () {
    final recipientAmount = BigInt.from(100000000);

    expect(
      paymentLinkFundingAmountZatoshi(recipientAmount),
      BigInt.from(100010000),
    );
    expect(
      () => paymentLinkFundingAmountZatoshi(BigInt.zero),
      throwsArgumentError,
    );
  });

  test(
    'funding quote includes deposit and redeem fees in the sender total',
    () {
      final quote = PaymentLinkFundingQuote(
        sourceAccountUuid: 'account-1',
        recipientAmountZatoshi: BigInt.from(100000000),
        fundingFeeZatoshi: BigInt.from(15000),
        claimFeeReserveZatoshi: BigInt.from(10000),
      );

      expect(quote.sourceAccountUuid, 'account-1');
      expect(quote.cardFeeZatoshi, BigInt.from(25000));
      expect(quote.totalDeductedZatoshi, BigInt.from(100025000));
    },
  );

  test('max funding quote reserves deposit and redeem fees', () {
    final quote = paymentLinkMaxFundingQuote(
      sourceAccountUuid: 'account-1',
      maxSpendAmountZatoshi: BigInt.from(100000000),
      fundingFeeZatoshi: BigInt.from(15000),
    );

    expect(quote.recipientAmountZatoshi, BigInt.from(99990000));
    expect(quote.fundingFeeZatoshi, BigInt.from(15000));
    expect(quote.claimFeeReserveZatoshi, BigInt.from(10000));
    expect(quote.totalDeductedZatoshi, BigInt.from(100015000));
    expect(
      quote.totalDeductedZatoshi,
      BigInt.from(100000000) + quote.fundingFeeZatoshi,
    );
    expect(
      () => paymentLinkMaxFundingQuote(
        sourceAccountUuid: 'account-1',
        maxSpendAmountZatoshi: BigInt.from(10000),
        fundingFeeZatoshi: BigInt.from(15000),
      ),
      throwsStateError,
    );
  });

  test('a funding result with a known status and txid is submitted', () {
    for (final status in const [
      'broadcasted',
      'pending_broadcast',
      'partial_broadcast',
      'broadcast_unknown',
      'broadcasted_storage_failed',
    ]) {
      expect(
        isPaymentLinkFundingSubmitted(status: status, txids: 'funding-txid'),
        isTrue,
        reason: status,
      );
    }

    expect(
      isPaymentLinkFundingSubmitted(status: 'broadcasted', txids: '  '),
      isFalse,
    );
    expect(
      isPaymentLinkFundingSubmitted(
        status: 'unexpected',
        txids: 'funding-txid',
      ),
      isFalse,
    );
  });

  test('share readiness accepts mempool broadcast or one confirmation', () {
    expect(
      paymentLinkConfirmationCount(
        minedHeight: BigInt.from(100),
        chainTipHeight: BigInt.from(104),
      ),
      5,
    );
    expect(
      const PaymentLinkFundingProgress(confirmationCount: 0).isReady,
      isFalse,
    );
    expect(
      const PaymentLinkFundingProgress(
        confirmationCount: 0,
        broadcastAccepted: true,
      ).isReady,
      isTrue,
    );
    expect(
      const PaymentLinkFundingProgress(confirmationCount: 1).isReady,
      isTrue,
    );
    expect(
      paymentLinkConfirmationCount(
        minedHeight: BigInt.zero,
        chainTipHeight: BigInt.from(104),
      ),
      0,
    );
  });

  test('claim confirmation count follows the matching funding receive', () {
    final expectedFunding = paymentLinkFundingAmountZatoshi(
      BigInt.from(100000),
    );
    final transactions = [
      _transaction(
        txid: 'funding',
        txKind: 'received',
        minedHeight: 100,
        accountBalanceDelta: expectedFunding.toInt(),
      ),
      _transaction(
        txid: 'dust',
        txKind: 'received',
        minedHeight: 90,
        accountBalanceDelta: 1,
      ),
    ];

    expect(
      paymentLinkFundingConfirmationCountForClaim(
        recipientAmountZatoshi: BigInt.from(100000),
        transactions: transactions,
        chainTipHeight: BigInt.from(103),
      ),
      4,
    );
  });

  test(
    'claim waits while funding is pending or still in its initial window',
    () {
      expect(
        paymentLinkShouldWaitForFunding(
          recipientAmountZatoshi: BigInt.from(100000),
          totalZatoshi: paymentLinkFundingAmountZatoshi(BigInt.from(100000)),
          fundingConfirmationCount: 4,
          birthdayHeight: 100,
          currentTipHeight: 104,
        ),
        isTrue,
      );
      expect(
        paymentLinkShouldWaitForFunding(
          recipientAmountZatoshi: BigInt.from(100000),
          totalZatoshi: BigInt.zero,
          fundingConfirmationCount: 0,
          birthdayHeight: 100,
          currentTipHeight: 106,
        ),
        isFalse,
      );
      expect(
        paymentLinkShouldWaitForFunding(
          recipientAmountZatoshi: BigInt.from(100000),
          totalZatoshi: paymentLinkFundingAmountZatoshi(BigInt.from(100000)),
          fundingConfirmationCount: 6,
          birthdayHeight: 100,
          currentTipHeight: 105,
        ),
        isFalse,
      );
    },
  );

  test('matches broadcast and history txids across byte order', () {
    const broadcastTxid =
        '9909fe99c789029bf118c88bd9ee33ed35965fd0f3154dd1a8ec6daa4974c7e3';
    const historyTxid =
        'e3c77449aa6deca8d14d15f3d05f9635ed33eed98bc818f19b0289c799fe0999';

    expect(paymentLinkTxidsMatch(broadcastTxid, historyTxid), isTrue);
    expect(paymentLinkTxidsMatch('0x$broadcastTxid', broadcastTxid), isTrue);
    expect(paymentLinkTxidsMatch(broadcastTxid, 'not-a-txid'), isFalse);
  });

  test('prepared funding recovery requires a non-expired history txid', () {
    const preparedTxid =
        '9909fe99c789029bf118c88bd9ee33ed35965fd0f3154dd1a8ec6daa4974c7e3';
    const historyTxid =
        'e3c77449aa6deca8d14d15f3d05f9635ed33eed98bc818f19b0289c799fe0999';

    expect(
      paymentLinkFundingTransactionExists(
        fundingTxid: preparedTxid,
        transactions: [_transaction(txid: historyTxid, txKind: 'sent')],
      ),
      isTrue,
    );
    expect(
      paymentLinkFundingTransactionExists(
        fundingTxid: preparedTxid,
        transactions: [
          _transaction(txid: historyTxid, txKind: 'sent', expiredUnmined: true),
        ],
      ),
      isFalse,
    );
    expect(
      paymentLinkFundingTransactionExists(
        fundingTxid: preparedTxid,
        transactions: [_transaction(txid: 'different', txKind: 'sent')],
      ),
      isFalse,
    );
  });

  test('funding expires only after every transaction expires unmined', () {
    final expired = _transaction(
      txid: 'expired',
      txKind: 'sent',
      expiredUnmined: true,
    );

    expect(
      paymentLinkFundingExpired(
        fundingTxids: 'expired',
        transactions: [expired],
      ),
      isTrue,
    );
    expect(
      paymentLinkFundingExpired(
        fundingTxids: 'expired,active',
        transactions: [
          expired,
          _transaction(txid: 'active', txKind: 'sent'),
        ],
      ),
      isFalse,
    );
    expect(
      paymentLinkFundingExpired(
        fundingTxids: 'expired,missing',
        transactions: [expired],
      ),
      isFalse,
    );
  });

  test('receipt completes once every claim transaction is mined', () {
    expect(
      paymentLinkReceivedStatusForTransactions(
        claimTxids: 'claim-a,claim-b',
        transactions: [
          _transaction(txid: 'claim-a', txKind: 'received', minedHeight: 12),
          _transaction(txid: 'claim-b', txKind: 'receiving'),
        ],
        chainTipHeight: BigInt.from(18),
      ),
      PaymentLinkReceivedStatus.receiving,
    );
    expect(
      paymentLinkReceivedStatusForTransactions(
        claimTxids: 'claim-a,claim-b',
        transactions: [
          _transaction(txid: 'claim-a', txKind: 'received', minedHeight: 12),
          _transaction(txid: 'claim-b', txKind: 'received', minedHeight: 14),
        ],
        chainTipHeight: BigInt.from(18),
      ),
      PaymentLinkReceivedStatus.received,
    );
    expect(
      paymentLinkReceivedStatusForTransactions(
        claimTxids: 'claim-a,claim-b',
        transactions: [
          _transaction(txid: 'claim-a', txKind: 'received', minedHeight: 12),
          _transaction(txid: 'claim-b', txKind: 'received', minedHeight: 13),
        ],
        chainTipHeight: BigInt.from(18),
      ),
      PaymentLinkReceivedStatus.received,
    );
  });

  test('claim confirmations never outrun the scanned wallet height', () {
    expect(
      paymentLinkVerifiedChainHeight(scannedHeight: 105, chainTipHeight: 106),
      BigInt.from(105),
    );
    expect(
      paymentLinkVerifiedChainHeight(scannedHeight: 106, chainTipHeight: 105),
      BigInt.from(105),
    );
    expect(
      paymentLinkVerifiedChainHeight(scannedHeight: 0, chainTipHeight: 106),
      BigInt.zero,
    );
  });

  test('expired unmined claim becomes actionable again', () {
    expect(
      paymentLinkReceivedStatusForTransactions(
        claimTxids: 'claim-txid',
        transactions: [
          _transaction(
            txid: 'claim-txid',
            txKind: 'receiving',
            expiredUnmined: true,
          ),
        ],
        chainTipHeight: BigInt.from(18),
      ),
      PaymentLinkReceivedStatus.readyToClaim,
    );
  });

  test('retained claim retries only after every transaction expires', () {
    final transactions = [
      _transaction(txid: 'claim-a', txKind: 'sent', expiredUnmined: true),
      _transaction(txid: 'claim-b', txKind: 'sent'),
    ];

    expect(
      paymentLinkClaimTransactionsExpired(
        claimTxids: 'claim-a,claim-b',
        transactions: transactions,
      ),
      isFalse,
    );
    expect(
      paymentLinkClaimTransactionsExpired(
        claimTxids: 'claim-a,missing',
        transactions: transactions,
      ),
      isFalse,
    );
    expect(
      paymentLinkClaimTransactionsExpired(
        claimTxids: 'claim-a',
        transactions: transactions,
      ),
      isTrue,
    );
  });

  test('mixed claim outcomes settle only after every leg is terminal', () {
    final transactions = [
      _transaction(txid: 'mined', txKind: 'sent', minedHeight: 10),
      _transaction(txid: 'expired', txKind: 'sent', expiredUnmined: true),
    ];
    bool settled(String ids, int height, {List<String> conflicts = const []}) =>
        paymentLinkClaimFailureSettled(
          claimTxids: ids,
          transactions: transactions,
          conflictedTxids: conflicts,
          verifiedHeight: BigInt.from(height),
        );
    expect(settled('mined,expired', 15), isTrue);
    expect(settled('mined,expired', 14), isFalse);
    expect(settled('mined,missing', 15), isFalse);
    expect(settled('mined,conflicted', 15, conflicts: ['conflicted']), isTrue);
    expect(settled('mined', 15), isFalse);
    expect(settled('', 15), isFalse);
  });

  test('broadcast and recovery claim IDs use the same protocol byte order', () {
    const displayA =
        '012c6894d79c62d7f49659bf2405b6b67fda282aa89127539d77de76523be0d6';
    const protocolA =
        'd6e03b5276de779d532791a82a28da7fb6b60524bf5996f4d7629cd794682c01';
    const displayB =
        '3b73c8a9b97669586f626db527361744a413af21b483ab25b818f4ac5fad8860';
    const protocolB =
        '6088ad5facf418b825ab83b421af13a444173627b56d626f586976b9a9c8733b';
    final broadcast = paymentLinkBroadcastTxidsToProtocolOrder(
      '$displayA,$displayB',
    );
    expect(broadcast, '$protocolA,$protocolB');
  });

  test('claim exposes only the amount promised by the link', () {
    final recipientAmount = BigInt.from(100000000);

    expect(
      paymentLinkClaimableAmountZatoshi(
        recipientAmountZatoshi: recipientAmount,
        maxSpendableZatoshi: BigInt.from(100000000),
      ),
      recipientAmount,
    );
    expect(
      paymentLinkClaimableAmountZatoshi(
        recipientAmountZatoshi: recipientAmount,
        maxSpendableZatoshi: BigInt.from(120000000),
      ),
      recipientAmount,
    );
    expect(
      paymentLinkClaimableAmountZatoshi(
        recipientAmountZatoshi: recipientAmount,
        maxSpendableZatoshi: BigInt.from(99999999),
      ),
      BigInt.zero,
    );
  });

  test('recognizes every accepted claim broadcast status', () {
    expect(
      paymentLinkClaimBroadcastStatusFromWire('pending_broadcast'),
      PaymentLinkClaimBroadcastStatus.pendingBroadcast,
    );
    expect(
      paymentLinkClaimBroadcastStatusFromWire('partial_broadcast'),
      PaymentLinkClaimBroadcastStatus.partialBroadcast,
    );
    expect(
      paymentLinkClaimBroadcastStatusFromWire('broadcasted'),
      PaymentLinkClaimBroadcastStatus.broadcasted,
    );
    expect(
      () => paymentLinkClaimBroadcastStatusFromWire('unexpected'),
      throwsStateError,
    );
  });

  test(
    'confirmed claims delete retained state before clearing the link',
    () async {
      final storage = _PaymentLinkServiceReceivedStorage();
      final store = PaymentLinkReceivedStore(storage);
      final link = _link();
      await store.saveReady(link);
      await store.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      await store.markReceived(address: link.address);
      final record = (await store.load()).single;
      final events = <String>[];

      final completed = await finalizeConfirmedPaymentLinkClaim(
        record: record,
        deleteRetainedWallet: (candidate) async {
          expect(candidate.claimLink, isNotNull);
          events.add('delete');
          return true;
        },
        clearClaimSecret: (address) async {
          events.add('mark');
          await store.clearConfirmedClaimSecret(address: address);
        },
      );

      expect(completed, isTrue);
      expect(events, ['delete', 'mark']);
      expect((await store.load()).single.claimLink, isNull);
    },
  );

  test(
    'confirmed claims keep their link when retained cleanup fails',
    () async {
      final storage = _PaymentLinkServiceReceivedStorage();
      final store = PaymentLinkReceivedStore(storage);
      final link = _link();
      await store.saveReady(link);
      await store.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      await store.markReceived(address: link.address);
      final record = (await store.load()).single;

      final completed = await finalizeConfirmedPaymentLinkClaim(
        record: record,
        deleteRetainedWallet: (_) async => false,
        clearClaimSecret: (_) async => fail('must not clear the retained link'),
      );

      expect(completed, isFalse);
      expect((await store.load()).single.claimLink, isNotNull);
    },
  );

  test(
    'one confirmation completes the receipt; six finalizes recovery',
    () async {
      final storage = _PaymentLinkServiceReceivedStorage();
      var store = PaymentLinkReceivedStore(storage);
      final link = _link();
      await store.saveReady(link);
      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver',
      );
      await store.markReceiving(
        address: link.address,
        destinationAccountUuid: 'receiver',
        claimTxids: 'claim',
      );
      var deleteCalls = 0;
      Future<void> reconcile(int height) async {
        await reconcilePaymentLinkClaimReceipt(
          record: (await store.load()).single,
          transactions: [
            _transaction(txid: 'claim', txKind: 'received', minedHeight: 100),
          ],
          verifiedHeight: BigInt.from(height),
          store: store,
          deleteRetainedWallet: (_) async {
            deleteCalls++;
            return true;
          },
        );
      }

      await reconcile(99);
      expect(
        (await store.load()).single.status,
        PaymentLinkReceivedStatus.receiving,
      );
      await reconcile(100);
      store = PaymentLinkReceivedStore(
        storage,
      ); // Restart between receipt and cleanup.
      final receipt = (await store.load()).single;
      expect(receipt.status, PaymentLinkReceivedStatus.received);
      expect(receipt.isClaimInFlight, isFalse);
      expect(receipt.needsClaimRecovery, isTrue);
      expect(receipt.claimLink, isNotNull);
      expect(deleteCalls, 0);
      // Startup sync state can be unknown, or still behind the mined height.
      for (final height in [0, 99, 100, 104]) {
        await reconcile(height);
        final restored = (await store.load()).single;
        expect(restored.status, PaymentLinkReceivedStatus.received);
        expect(restored.isClaimInFlight, isFalse);
        expect(restored.claimSubmittedAt, receipt.claimSubmittedAt);
        expect(restored.updatedAt, receipt.updatedAt);
      }
      expect((await store.load()).single.claimLink, isNotNull);
      expect(deleteCalls, 0);
      await reconcile(105);
      final finalized = (await store.load()).single;
      expect(finalized.status, PaymentLinkReceivedStatus.received);
      expect(finalized.needsClaimRecovery, isFalse);
      expect(finalized.claimLink, isNull);
      expect(deleteCalls, 1);
    },
  );

  test(
    'missing receipt history does not invalidate a completed claim',
    () async {
      final store = PaymentLinkReceivedStore(
        _PaymentLinkServiceReceivedStorage(),
      );
      final link = _link();
      await store.saveReady(link);
      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver',
      );
      await store.markReceiving(
        address: link.address,
        destinationAccountUuid: 'receiver',
        claimTxids: 'a,b',
      );
      await store.markReceived(address: link.address);
      for (final history in <List<rust_sync.TransactionInfo>>[
        [],
        [_transaction(txid: 'a', txKind: 'received', minedHeight: 100)],
        [_transaction(txid: 'unrelated', txKind: 'receiving')],
        [_transaction(txid: 'a', txKind: 'sent')],
      ]) {
        await reconcilePaymentLinkClaimReceipt(
          record: (await store.load()).single,
          transactions: history,
          verifiedHeight: BigInt.from(105),
          store: store,
          deleteRetainedWallet: (_) async =>
              fail('Incomplete history cannot finalize recovery'),
        );
        final record = (await store.load()).single;
        expect(record.status, PaymentLinkReceivedStatus.received);
        expect(record.claimLink, isNotNull);
      }
      // A matching expired leg is explicit invalidation even if another leg
      // is still confirmed; an entirely expired claim becomes retryable below.
      await reconcilePaymentLinkClaimReceipt(
        record: (await store.load()).single,
        transactions: [
          _transaction(txid: 'a', txKind: 'received', minedHeight: 100),
          _transaction(txid: 'b', txKind: 'receiving', expiredUnmined: true),
        ],
        verifiedHeight: BigInt.from(105),
        store: store,
        deleteRetainedWallet: (_) async =>
            fail('Invalidated claims must retain recovery'),
      );
      expect(
        (await store.load()).single.status,
        PaymentLinkReceivedStatus.receiving,
      );
    },
  );

  test(
    'a shallow reorg restores pending and retryable receipt states',
    () async {
      final store = PaymentLinkReceivedStore(
        _PaymentLinkServiceReceivedStorage(),
      );
      final link = _link();
      await store.saveReady(link);
      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver',
      );
      await store.markReceiving(
        address: link.address,
        destinationAccountUuid: 'receiver',
        claimTxids: 'claim',
      );
      await store.markReceived(address: link.address);
      final submittedAt = (await store.load()).single.claimSubmittedAt;
      Future<void> reconcile(rust_sync.TransactionInfo tx) async {
        await reconcilePaymentLinkClaimReceipt(
          record: (await store.load()).single,
          transactions: [tx],
          verifiedHeight: BigInt.from(100),
          store: store,
          deleteRetainedWallet: (_) async =>
              fail('A reorg must not delete recovery material'),
        );
      }

      await reconcile(_transaction(txid: 'claim', txKind: 'receiving'));
      final pending = (await store.load()).single;
      expect(pending.status, PaymentLinkReceivedStatus.receiving);
      expect(pending.claimSubmittedAt, submittedAt);
      expect(pending.claimLink, isNotNull);
      await reconcile(
        _transaction(txid: 'claim', txKind: 'received', expiredUnmined: true),
      );
      final retryable = (await store.load()).single;
      expect(retryable.status, PaymentLinkReceivedStatus.readyToClaim);
      expect(retryable.claimLink, isNotNull);
    },
  );

  test('only reuses a complete claim wallet for the expected address', () {
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const [],
        expectedAddress: 'u1expected',
      ),
      isTrue,
    );
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const ['u1expected', 'u1unexpected'],
        expectedAddress: 'u1expected',
      ),
      isTrue,
    );
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const ['u1unexpected'],
        expectedAddress: 'u1expected',
      ),
      isTrue,
    );
    expect(
      shouldRecreatePaymentLinkClaimWallet(
        accountAddresses: const ['u1expected'],
        expectedAddress: 'u1expected',
      ),
      isFalse,
    );
  });

  test('claim broadcast stops when the wallet locks', () {
    expect(
      () => requireUnlockedPaymentLinkWallet(requiresUnlock: true),
      throwsStateError,
    );
    expect(
      () => requireUnlockedPaymentLinkWallet(requiresUnlock: false),
      returnsNormally,
    );
  });

  test('claim destination must still resolve to the prepared address', () {
    expect(
      () => requireMatchingPaymentLinkClaimDestination(
        preparedAddress: 'u1prepared',
        currentAddress: 'u1prepared',
      ),
      returnsNormally,
    );
    expect(
      () => requireMatchingPaymentLinkClaimDestination(
        preparedAddress: 'u1prepared',
        currentAddress: 'u1changed',
      ),
      throwsA(isA<PaymentLinkClaimDestinationChangedException>()),
    );
  });

  test('accepts any past claim birthday and rejects invalid heights', () {
    const currentTip = 3500000;
    expect(
      validatePaymentLinkClaimBirthday(
        advertisedBirthdayHeight: 1,
        currentTipHeight: currentTip,
      ),
      1,
    );
    expect(
      () => validatePaymentLinkClaimBirthday(
        advertisedBirthdayHeight: 0,
        currentTipHeight: currentTip,
      ),
      throwsFormatException,
    );
    expect(
      () => validatePaymentLinkClaimBirthday(
        advertisedBirthdayHeight: currentTip + 1,
        currentTipHeight: currentTip,
      ),
      throwsFormatException,
    );
  });

  test('flags claim scans beyond the normal lookback', () {
    const currentTip = 3500000;
    expect(
      isLongPaymentLinkSync(
        birthdayHeight: currentTip - kPaymentLinkLongSyncLookbackBlocks,
        currentTipHeight: currentTip,
      ),
      isFalse,
    );
    expect(
      isLongPaymentLinkSync(
        birthdayHeight: currentTip - kPaymentLinkLongSyncLookbackBlocks - 1,
        currentTipHeight: currentTip,
      ),
      isTrue,
    );
  });

  test('claim wallet cache identity uses the account and birthday only', () {
    final link = _link();
    final sameLinkName = paymentLinkClaimWalletDirectoryName(link);
    final differentSecretName = paymentLinkClaimWalletDirectoryName(
      VizorPaymentLink(
        network: link.network,
        address: link.address,
        amountZatoshi: link.amountZatoshi,
        mnemonic:
            'legal winner thank year wave sausage worth useful legal winner thank yellow',
        birthdayHeight: link.birthdayHeight,
        label: link.label,
        createdAt: link.createdAt,
      ),
    );
    final differentBirthdayName = paymentLinkClaimWalletDirectoryName(
      VizorPaymentLink(
        network: link.network,
        address: link.address,
        amountZatoshi: link.amountZatoshi,
        mnemonic: link.mnemonic,
        birthdayHeight: link.birthdayHeight - 1,
        label: link.label,
        createdAt: link.createdAt,
      ),
    );
    final differentSharePayloadName = paymentLinkClaimWalletDirectoryName(
      VizorPaymentLink(
        network: link.network,
        address: link.address,
        amountZatoshi: link.amountZatoshi + BigInt.one,
        mnemonic: link.mnemonic,
        birthdayHeight: link.birthdayHeight,
        label: '${link.label} updated',
        createdAt: link.createdAt.add(const Duration(seconds: 1)),
        presentation: const PaymentLinkPresentation(message: 'Updated'),
      ),
    );

    expect(paymentLinkClaimWalletDirectoryName(link), sameLinkName);
    expect(differentSecretName, isNot(sameLinkName));
    expect(differentBirthdayName, isNot(sameLinkName));
    expect(differentSharePayloadName, sameLinkName);
    expect(sameLinkName, isNot(contains(link.address)));
    expect(sameLinkName, isNot(contains('abandon')));
  });

  test('claim wallet directory name carries the link network', () {
    final mainName = paymentLinkClaimWalletDirectoryName(_link());
    final regtestName = paymentLinkClaimWalletDirectoryName(
      VizorPaymentLink(
        network: 'regtest',
        address: _link().address,
        amountZatoshi: _link().amountZatoshi,
        mnemonic: _link().mnemonic,
        birthdayHeight: _link().birthdayHeight,
        label: _link().label,
        createdAt: _link().createdAt,
      ),
    );

    expect(
      mainName,
      matches(
        RegExp('^${kPaymentLinkClaimWalletDirectoryPrefix}main_[0-9a-f]{64}\$'),
      ),
    );
    expect(
      regtestName,
      matches(
        RegExp(
          '^${kPaymentLinkClaimWalletDirectoryPrefix}regtest_[0-9a-f]{64}\$',
        ),
      ),
    );
    expect(regtestName, isNot(mainName));
  });

  test(
    'hardware funding is rejected before creating a recovery draft',
    () async {
      final storage = _RecordingPaymentLinkRecoveryStorage();
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_HardwareAccountNotifier.new),
          paymentLinkRecoveryStoreProvider.overrideWithValue(
            PaymentLinkRecoveryStore(storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      await expectLater(
        container
            .read(paymentLinkServiceProvider)
            .createFundedLink(
              amountZatoshi: BigInt.from(100000),
              sourceAccountUuid: 'hardware-account',
            ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Keystone payment links require the hardware signing flow.',
          ),
        ),
      );
      expect(storage.writeCount, 0);
    },
  );

  test('a quiesced reset stops a pending claim from being retained', () async {
    final storage = _PaymentLinkServiceReceivedStorage();
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
          () async => const [],
        ),
        paymentLinkReceivedStoreProvider.overrideWithValue(
          PaymentLinkReceivedStore(storage),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(paymentLinkClaimCoordinatorProvider);
    await container
        .read(paymentLinkClaimLifecycleRegistryProvider)
        .quiesceAndDrain();

    await container
        .read(paymentLinkServiceProvider)
        .retainPendingClaim(_claimSession());

    expect(storage.value, isNull);
  });
}

String _reverseHexBytes(String hex) {
  final bytes = [
    for (var index = 0; index < hex.length; index += 2)
      hex.substring(index, index + 2),
  ];
  return bytes.reversed.join();
}

class _UnlockedSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

PaymentLinkClaimSession _claimSession() {
  final link = _link();
  return PaymentLinkClaimSession(
    link: link,
    destinationAddress: 'u1receiver',
    destinationAccountUuid: 'account-1',
    directory: Directory('/tmp/vizor-payment-link-service-test'),
    dbPath: '/tmp/vizor-payment-link-service-test/wallet.db',
    accountUuid: 'payment-link-account',
    totalZatoshi: link.amountZatoshi,
    claimableZatoshi: link.amountZatoshi,
    feeZatoshi: BigInt.from(10000),
  );
}

class _PaymentLinkServiceReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async => value = nextValue;
}

class _HardwareAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'hardware-account',
        name: 'Keystone',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'hardware-account',
    activeAddress: 'u1hardwareaddress',
  );
}

class _FakePaymentLinkRecoveryStorage implements PaymentLinkRecoveryStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async => value = nextValue;
}

class _RecordingPaymentLinkRecoveryStorage
    implements PaymentLinkRecoveryStorage {
  int writeCount = 0;

  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    writeCount += 1;
  }
}

VizorPaymentLink _link() {
  return VizorPaymentLink(
    network: 'main',
    address: 'u1paymentlinkaddress',
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 3_456_789,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 5, 12),
  );
}

rust_sync.TransactionInfo _transaction({
  required String txid,
  required String txKind,
  int minedHeight = 0,
  bool expiredUnmined = false,
  int accountBalanceDelta = 1,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: BigInt.from(minedHeight),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: accountBalanceDelta,
    fee: BigInt.zero,
    blockTime: BigInt.zero,
    isTransparent: false,
    txKind: txKind,
    displayAmount: BigInt.one,
    displayPool: 'shielded',
    createdTime: BigInt.zero,
  );
}

// Stop at the first spend-preparation boundary: these tests exercise the real
// prepareClaim destination lookup without creating a claim wallet or syncing.
class _DestinationValidated implements Exception {}

class _ClaimDestinationRustApi implements RustLibApi {
  final requestedAccounts = <String>[];
  final validatedAddresses = <String>[];
  var lookupStarted = Completer<void>();
  Completer<String>? lookupGate;
  int failures = 0;
  bool poolFixture = false;
  List<String> localClaimTxids = [];
  List<String> conflictedTxids = [];
  List<rust_sync.TransactionInfo>? claimHistory;
  Set<String> failingDetailTxids = {};
  int detailLookups = 0;
  Completer<rust_sync.SendMaxEstimateResult>? estimateGate;
  var estimateStarted = Completer<void>();
  Completer<void>? syncGate;
  var syncStarted = Completer<void>();
  int claimSyncCalls = 0;
  List<bool> claimSyncModes = [];

  @override
  Future<rust_sync.SendMaxEstimateResult> crateApiSyncEstimateSendMax({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    String? memo,
  }) {
    estimateStarted.complete();
    return estimateGate!.future;
  }

  @override
  Future<List<rust_wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async {
    if (!poolFixture) return [];
    final isClaimWallet = dbPath.contains(
      paymentLinkClaimWalletDirectoryName(_link()),
    );
    return [
      rust_wallet.AccountInfo(
        uuid: isClaimWallet ? 'claim-wallet' : 'receiver',
        name: 'Test',
        unifiedAddress: isClaimWallet ? _link().address : 'u1receiveraddress',
        birthdayHeight: 0,
        isSeedAnchor: true,
        isHardware: false,
      ),
    ];
  }

  @override
  Future<rust_sync.PaymentLinkSpendEvidence>
  crateApiSyncGetPaymentLinkSpendEvidence({
    required String dbPath,
    required String accountUuid,
    required String claimTxids,
  }) async => rust_sync.PaymentLinkSpendEvidence(
    allFundsSpentElsewhere: false,
    conflictedTxids: conflictedTxids,
    localClaimTxids: localClaimTxids,
    verifiedHeight: BigInt.from(100),
  );

  @override
  Future<void> crateApiSyncRunPaymentLinkClaimSync({
    required bool allowResubmit,
    required String claimId,
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
  }) async {
    if (!poolFixture) throw StateError('Unexpected claim sync');
    claimSyncCalls++;
    claimSyncModes.add(allowResubmit);
    if (!syncStarted.isCompleted) syncStarted.complete();
    await syncGate?.future;
  }

  @override
  Future<List<rust_sync.TransactionInfo>> crateApiSyncGetTransactionHistory({
    required String dbPath,
    required String network,
    required String accountUuid,
    int? limit,
  }) async {
    if (!poolFixture) throw StateError('Unexpected history lookup');
    final isClaimWallet = accountUuid == 'claim-wallet';
    if (isClaimWallet && claimHistory != null) return claimHistory!;
    return [
      for (final txid in isClaimWallet ? localClaimTxids : ['a', 'b'])
        _transaction(
          txid: txid,
          txKind: isClaimWallet ? 'sent' : 'received',
          minedHeight: 100,
        ),
    ];
  }

  @override
  Future<rust_sync.TransactionDetail> crateApiSyncGetTransactionDetail({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String txidHex,
    required String txKind,
  }) async {
    if (!poolFixture) throw StateError('Unexpected detail lookup');
    detailLookups++;
    if (failingDetailTxids.contains(txidHex)) {
      throw StateError('Detail unavailable');
    }
    return rust_sync.TransactionDetail(
      txidHex: txidHex,
      txKind: txKind,
      outputs: [
        rust_sync.TransactionDetailOutput(
          address: 'u1receiveraddress',
          amountZatoshi: BigInt.from(50000),
          pool: 'ironwood',
        ),
      ],
    );
  }

  @override
  Future<void> crateApiVotingResetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {}

  void reset() {
    requestedAccounts.clear();
    validatedAddresses.clear();
    lookupStarted = Completer<void>();
    lookupGate = null;
    failures = 0;
    poolFixture = false;
    localClaimTxids = [];
    conflictedTxids = [];
    claimHistory = null;
    failingDetailTxids = {};
    detailLookups = 0;
    estimateGate = null;
    estimateStarted = Completer<void>();
    syncGate = null;
    syncStarted = Completer<void>();
    claimSyncCalls = 0;
    claimSyncModes = [];
  }

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    requestedAccounts.add(accountUuid!);
    if (!lookupStarted.isCompleted) lookupStarted.complete();
    if (failures > 0) {
      failures--;
      throw StateError('transient address lookup failure');
    }
    return lookupGate?.future ?? Future.value('u1${accountUuid}address');
  }

  @override
  Future<rust_sync.AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) async {
    validatedAddresses.add(address);
    throw _DestinationValidated();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClaimDestinationAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState();

  void select(String uuid, String? address) {
    state = AsyncData(
      AccountState(activeAccountUuid: uuid, activeAddress: address),
    );
  }
}

class _ClaimDestinationRpcNotifier extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => const RpcEndpointConfig(
    networkName: 'main',
    lightwalletdUrl: 'https://example.invalid:9067',
  );
}
