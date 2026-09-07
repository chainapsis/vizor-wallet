import 'dart:async';
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
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        details: const [],
        destinationAddress: 'destination-ua',
        expectedAmountZatoshi: BigInt.from(445000000),
      ),
      isNull,
    );
  });

  group('claim destination hydration', () {
    final api = _ClaimDestinationRustApi();
    late _ClaimDestinationAccountNotifier accounts;
    late ProviderContainer container;
    late PaymentLinkService service;
    late Directory supportDirectory;
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
      container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(() => accounts),
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          rpcEndpointProvider.overrideWith(_ClaimDestinationRpcNotifier.new),
          paymentLinkRecoveryStoreProvider.overrideWithValue(
            PaymentLinkRecoveryStore(_FakePaymentLinkRecoveryStorage()),
          ),
          paymentLinkReceivedStoreProvider.overrideWithValue(
            PaymentLinkReceivedStore(_PaymentLinkServiceReceivedStorage()),
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

  test(
    'claim remains Receiving until every transaction has six confirmations',
    () {
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
        PaymentLinkReceivedStatus.receiving,
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
    },
  );

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

  test('recovers only active sent claim transaction ids', () {
    expect(
      paymentLinkActiveClaimTxids([
        _transaction(txid: 'active', txKind: 'sent'),
        _transaction(txid: 'expired', txKind: 'sent', expiredUnmined: true),
        _transaction(txid: 'funding', txKind: 'received'),
      ]),
      ['active'],
    );
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
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      final record = (await store.load()).single;
      final events = <String>[];

      final completed = await finalizeConfirmedPaymentLinkClaim(
        record: record,
        deleteRetainedWallet: (candidate) async {
          expect(candidate.claimLink, isNotNull);
          events.add('delete');
          return true;
        },
        markReceived: (address) async {
          events.add('mark');
          await store.markReceived(address: address);
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
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      final record = (await store.load()).single;

      final completed = await finalizeConfirmedPaymentLinkClaim(
        record: record,
        deleteRetainedWallet: (_) async => false,
        markReceived: (_) async => fail('must not clear the retained link'),
      );

      expect(completed, isFalse);
      expect((await store.load()).single.claimLink, isNotNull);
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
