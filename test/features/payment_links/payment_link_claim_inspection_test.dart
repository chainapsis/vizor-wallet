import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_check_progress_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('account-free inspection and binding', () {
    final api = _InspectRustApi();
    late _InspectAccountNotifier accounts;
    late ProviderContainer container;
    late PaymentLinkService service;
    late Directory supportDirectory;
    late _MemoryReceivedStorage receivedStorage;
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    setUpAll(() => RustLib.initMock(api: api));
    tearDownAll(RustLib.dispose);

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      supportDirectory = await Directory.systemTemp.createTemp(
        'vizor-claim-inspect-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathChannel,
            (_) async => supportDirectory.path,
          );
      api.reset();
      receivedStorage = _MemoryReceivedStorage();
      accounts = _InspectAccountNotifier();
      container = ProviderContainer(
        overrides: [
          swapFeatureEnabledProvider.overrideWith((ref) => false),
          accountProvider.overrideWith(() => accounts),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              SyncState(scannedHeight: 100, chainTipHeight: 100),
            ),
          ),
          appSecurityProvider.overrideWith(_SetupSecurityNotifier.new),
          rpcEndpointProvider.overrideWith(_RpcNotifier.new),
          rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
            (_) async => 'main',
          ),
          rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue((
            _,
            _,
          ) async {
            if (!api.tipStarted.isCompleted) api.tipStarted.complete();
            await api.tipGate?.future;
            return BigInt.from(api.tipHeight);
          }),
          paymentLinkRecoveryStoreProvider.overrideWithValue(
            PaymentLinkRecoveryStore(_MemoryRecoveryStorage()),
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

    test(
      'background pause rejects late native progress and drains completion',
      () async {
        api.checkGate = Completer<void>();
        final checking = service.inspectClaim(_link());
        final failure = expectLater(checking, throwsStateError);
        await api.checkStarted.future;
        container.read(paymentLinkClaimCoordinatorProvider).pauseForLifecycle();
        api.checkGate!.complete();
        await failure;
        expect(container.read(giftCardCheckProgressProvider), isEmpty);
        expect(api.cancelCalls, greaterThan(0));
      },
    );

    for (final stage in ['tip', 'storage', 'import']) {
      for (final resumeBeforeCompletion in [false, true]) {
        test(
          'pause during $stage blocks inspection even when resume=$resumeBeforeCompletion',
          () async {
            final gate = Completer<void>();
            final started = Completer<void>();
            switch (stage) {
              case 'tip':
                api.tipGate = gate;
              case 'storage':
                receivedStorage.onRead = () async {
                  if (!started.isCompleted) started.complete();
                  await gate.future;
                  return receivedStorage.value;
                };
              case 'import':
                api.importGate = gate;
            }
            final checking = service.inspectClaim(_link());
            final failure = expectLater(checking, throwsStateError);
            await switch (stage) {
              'tip' => api.tipStarted.future,
              'import' => api.importStarted.future,
              _ => started.future,
            };
            final coordinator = container.read(
              paymentLinkClaimCoordinatorProvider,
            );
            coordinator.pauseForLifecycle();
            if (resumeBeforeCompletion) coordinator.resumeForLifecycle();
            gate.complete();
            await failure;
            expect(api.syncCalls, 0);
            expect(api.estimateDestinations, isEmpty);
            expect(receivedStorage.value, isNull);
            expect(container.read(giftCardCheckProgressProvider), isEmpty);
            if (api.importedDbPath != null) {
              expect(await File(api.importedDbPath!).exists(), isFalse);
            }
          },
        );
      }
    }

    test(
      'background admission stays closed after account recovery wakeups',
      () async {
        final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
        coordinator.pauseForLifecycle();
        (container.read(appSecurityProvider.notifier) as _SetupSecurityNotifier)
            .unlockForTest();
        coordinator.resumeAfterReset();
        expect(coordinator.acceptsPreparation, isFalse);
        await expectLater(service.inspectClaim(_link()), throwsStateError);
        expect(api.importCalls, 0);
        expect(api.syncCalls, 0);
      },
    );

    test('account-free inspection can retry after foreground resume', () async {
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      coordinator.pauseForLifecycle();
      await expectLater(service.inspectClaim(_link()), throwsStateError);
      coordinator.resumeForLifecycle();
      final inspection = await service.inspectClaim(_link());
      expect(inspection.claimableZatoshi, _link().amountZatoshi);
      expect(api.syncCalls, 1);
      expect(container.read(appSecurityProvider).isPasswordConfigured, isFalse);
    });

    test(
      'pause prevents fallback dispatch after an in-flight endpoint error',
      () async {
        api.failCheckOnce = true;
        api.checkGate = Completer<void>();
        final checking = service.inspectClaim(_link());
        final failure = expectLater(checking, throwsStateError);
        await api.checkStarted.future;
        container.read(paymentLinkClaimCoordinatorProvider).pauseForLifecycle();
        api.checkGate!.complete();
        await failure;
        expect(api.checkUrls, hasLength(1));
        expect(api.estimateDestinations, isEmpty);
      },
    );

    test(
      'a failed configured endpoint resumes checking on an existing fallback',
      () async {
        final primary = defaultRpcEndpointConfig('main');
        (container.read(rpcEndpointProvider.notifier) as _RpcNotifier)
            .setEndpointForTest(primary);
        api.failCheckOnce = true;
        await service.inspectClaim(_link());
        expect(api.checkUrls, hasLength(2));
        expect(api.checkUrls[0], primary.normalizedLightwalletdUrl);
        expect(api.checkUrls[1], isNot(api.checkUrls[0]));
        expect(api.importCalls, 1);
      },
    );

    test(
      'inspection needs no wallet, passcode, or receiving account',
      () async {
        final inspection = await service.inspectClaim(_link());

        expect(inspection.claimableZatoshi, _link().amountZatoshi);
        expect(inspection.waitingForFundingConfirmations, isFalse);
        expect(api.estimateDestinations, [_link().address]);
        expect(api.mainWalletLookups, 0);
        expect(container.read(accountProvider).value!.hasAccounts, isFalse);
        expect(
          container.read(appSecurityProvider).isPasswordConfigured,
          isFalse,
        );
        expect(receivedStorage.value, isNull);
      },
    );

    test(
      'binding uses the specified UUID and re-estimates without scanning',
      () async {
        accounts.select('other-account', 'u1otheraddress');
        final inspection = await service.inspectClaim(_link());
        api.maxClaimable = BigInt.from(80000);
        api.fee = BigInt.from(12000);

        final session = await service.bindClaimDestination(
          inspection,
          destinationAccountUuid: 'receiver',
        );

        expect(session.destinationAccountUuid, 'receiver');
        expect(session.destinationAddress, 'u1receiveraddress');
        expect(session.claimableZatoshi, BigInt.zero);
        expect(session.feeZatoshi, BigInt.from(12000));
        expect(session.availability, PaymentLinkAvailability.noBalance);
        expect(api.estimateDestinations, [
          _link().address,
          'u1receiveraddress',
        ]);
        expect(api.syncCalls, 1);
        expect(api.importCalls, 1);
        expect(
          container.read(accountProvider).value!.activeAccountUuid,
          'other-account',
        );
        expect(receivedStorage.value, isNull);
      },
    );

    test(
      'existing preparation estimates once for the active receiving account',
      () async {
        accounts.select('receiver', 'u1staleaddress');

        final session = await service.prepareClaim(_link());

        expect(session.destinationAccountUuid, 'receiver');
        expect(session.destinationAddress, 'u1receiveraddress');
        expect(session.canClaim, isTrue);
        expect(session.claimableZatoshi, _link().amountZatoshi);
        expect(
          session.fundingConfirmationCount,
          kPaymentLinkClaimConfirmationTarget,
        );
        expect(api.estimateDestinations, ['u1receiveraddress']);
        expect(api.syncCalls, 1);
      },
    );

    test(
      'readiness uses the observer tip when the chain advances during inspection',
      () async {
        api.fundingHeight = api.tipHeight;
        api.checkedTip = api.tipHeight + 1;
        final inspection = await service.inspectClaim(_link());
        expect(inspection.fundingConfirmationCount, 2);
        expect(inspection.waitingForFundingConfirmations, isFalse);
      },
    );

    test('unspendable funding keeps the existing confirmation wait', () async {
      api.maxClaimable = null;
      api.fundingHeight = api.tipHeight;
      final inspection = await service.inspectClaim(_link());
      final session = await service.bindClaimDestination(
        inspection,
        destinationAccountUuid: 'receiver',
      );

      expect(inspection.fundingConfirmationCount, 1);
      expect(inspection.waitingForFundingConfirmations, isTrue);
      expect(session.waitingForFundingConfirmations, isTrue);
      expect(session.canClaim, isFalse);
    });

    for (final age in [1, kPaymentLinkFreshCardGraceBlocks]) {
      test(
        'an empty card preserves the fresh-card grace at age $age',
        () async {
          api.total = BigInt.zero;
          api.maxClaimable = null;
          api.tipHeight = _link().birthdayHeight + age;
          final inspection = await service.inspectClaim(_link());

          expect(inspection.availability, PaymentLinkAvailability.noBalance);
          expect(
            inspection.waitingForFundingConfirmations,
            age < kPaymentLinkFreshCardGraceBlocks,
          );
        },
      );
    }

    test(
      'old cards use the dedicated check without full-sync consent',
      () async {
        api.tipHeight =
            _link().birthdayHeight + kPaymentLinkLongSyncLookbackBlocks + 1;
        await service.inspectClaim(_link());
        expect(api.importCalls, 1);
        expect(api.syncCalls, 1);
      },
    );

    test(
      'a network mismatch stops inspection before wallet creation',
      () async {
        (container.read(rpcEndpointProvider.notifier) as _RpcNotifier)
            .setNetworkForTest('test');
        await expectLater(
          service.inspectClaim(_link()),
          throwsA(isA<PaymentLinkNetworkMismatchException>()),
        );
        expect(api.importCalls, 0);
        expect(api.mainWalletLookups, 0);
      },
    );

    test('a locked wallet stops both inspection and binding', () async {
      final inspection = await service.inspectClaim(_link());
      (container.read(appSecurityProvider.notifier) as _SetupSecurityNotifier)
          .lockForTest();

      await expectLater(service.inspectClaim(_link()), throwsStateError);
      await expectLater(
        service.bindClaimDestination(
          inspection,
          destinationAccountUuid: 'receiver',
        ),
        throwsStateError,
      );
      expect(api.mainWalletLookups, 0);
      expect(api.syncCalls, 1);
    });

    test(
      'locking during destination lookup stops binding before estimation',
      () async {
        final inspection = await service.inspectClaim(_link());
        api.lookupGate = Completer<String>();
        final binding = service.bindClaimDestination(
          inspection,
          destinationAccountUuid: 'receiver',
        );
        final failure = expectLater(binding, throwsStateError);
        await api.lookupStarted.future;
        (container.read(appSecurityProvider.notifier) as _SetupSecurityNotifier)
            .lockForTest();
        api.lookupGate!.complete('u1receiveraddress');
        await failure;
        expect(api.estimateDestinations, [_link().address]);
      },
    );

    test('binding refuses an in-flight card before estimating again', () async {
      final inspection = await service.inspectClaim(_link());
      final store = container.read(paymentLinkReceivedStoreProvider);
      await store.saveReady(inspection.link);
      await store.markReceiving(
        address: inspection.link.address,
        destinationAccountUuid: 'receiver',
        claimTxids: 'claim-tx',
        claimSubmittedAt: DateTime.utc(2026, 10, 1),
      );
      await expectLater(
        service.bindClaimDestination(
          inspection,
          destinationAccountUuid: 'receiver',
        ),
        throwsA(isA<PaymentLinkClaimInFlightException>()),
      );
      expect(api.estimateDestinations, [_link().address]);
    });

    test('discard deletes a preview wallet without saving the card', () async {
      final inspection = await service.inspectClaim(_link());
      expect(await File(inspection.dbPath).exists(), isTrue);
      await service.discardClaimInspection(inspection);
      expect(await inspection.directory.exists(), isFalse);
      expect(api.cancelCalls, 1);
      expect(receivedStorage.value, isNull);
    });

    test(
      'saved setup claims use their account even with an address-free link',
      () async {
        final store = container.read(paymentLinkReceivedStoreProvider);
        await store.saveReady(_link(), setupAccountUuid: 'receiver');
        accounts.select('other-account', 'u1otheraddress');
        final addressFree = VizorPaymentLink.parse(_link().toUri().toString());
        expect(addressFree.knownAddress, isNull);
        final session = await service.prepareClaim(addressFree);
        expect(session.destinationAccountUuid, 'receiver');
        expect(session.destinationAddress, 'u1receiveraddress');
        expect(session.isSetupClaim, isTrue);
        expect(
          container.read(accountProvider).value!.activeAccountUuid,
          'other-account',
        );
        expect(api.syncCalls, 1);
      },
    );

    test(
      'binding cannot redirect a saved setup claim to another account',
      () async {
        final inspection = await service.inspectClaim(_link());
        await container
            .read(paymentLinkReceivedStoreProvider)
            .saveReady(inspection.link, setupAccountUuid: 'receiver');
        await expectLater(
          service.bindClaimDestination(
            inspection,
            destinationAccountUuid: 'other-account',
          ),
          throwsA(isA<PaymentLinkClaimDestinationChangedException>()),
        );
        expect(api.estimateDestinations, [_link().address]);
      },
    );

    test(
      'a previously prepared session cannot submit to another setup account',
      () async {
        accounts.select('receiver', 'u1receiveraddress');
        final session = await service.prepareClaim(_link());
        await container
            .read(paymentLinkReceivedStoreProvider)
            .saveReady(session.link, setupAccountUuid: 'other-account');
        await expectLater(
          service.claimPreparedLink(session),
          throwsA(isA<PaymentLinkClaimDestinationChangedException>()),
        );
        expect(
          (await container.read(paymentLinkReceivedStoreProvider).load())
              .single
              .status,
          PaymentLinkReceivedStatus.readyToClaim,
        );
      },
    );

    test(
      'waiting setup cards stay retryable and keep their inspected wallet',
      () async {
        api.maxClaimable = null;
        api.fundingHeight = api.tipHeight;
        final inspection = await service.inspectClaim(_link());
        final store = container.read(paymentLinkReceivedStoreProvider);
        await store.saveReady(inspection.link, setupAccountUuid: 'receiver');
        final session = await service.bindClaimDestination(
          inspection,
          destinationAccountUuid: 'receiver',
        );
        expect(session.waitingForFundingConfirmations, isTrue);
        await service.retainPendingClaim(session);
        expect(
          (await store.load()).single.availability,
          PaymentLinkAvailability.checking,
        );
        await service.discardClaimSession(session);
        expect(await File(session.dbPath).exists(), isTrue);
        expect((await store.load()).single.setupAccountUuid, 'receiver');
      },
    );

    test('discard preserves a saved card and its cached wallet', () async {
      final inspection = await service.inspectClaim(_link());
      await container
          .read(paymentLinkReceivedStoreProvider)
          .saveReady(inspection.link);
      await service.discardClaimInspection(inspection);
      expect(await File(inspection.dbPath).exists(), isTrue);
      expect(api.cancelCalls, 1);
      expect(
        (await container.read(paymentLinkReceivedStoreProvider).load())
            .single
            .address,
        inspection.link.address,
      );
    });

    for (final received in [false, true]) {
      test('discard preserves ${received ? 'received' : 'receiving'} '
          'cards with recovery material', () async {
        final inspection = await service.inspectClaim(_link());
        final store = container.read(paymentLinkReceivedStoreProvider);
        await store.saveReady(inspection.link);
        await store.markReceiving(
          address: inspection.link.address,
          destinationAccountUuid: 'receiver',
          claimTxids: 'claim-tx',
          claimSubmittedAt: DateTime.utc(2026, 10, 1),
        );
        if (received) {
          await store.markReceived(address: inspection.link.address);
        }

        await service.discardClaimInspection(inspection);

        expect(await File(inspection.dbPath).exists(), isTrue);
        expect((await store.load()).single.claimLink, isNotNull);
      });
    }

    for (final cleanup in ['inspection', 'retention', 'session']) {
      test('completed card cache is removed by $cleanup cleanup', () async {
        final first = await service.inspectClaim(_link());
        final store = container.read(paymentLinkReceivedStoreProvider);
        await store.saveReady(first.link);
        final receiving = await store.markReceiving(
          address: first.link.address,
          destinationAccountUuid: 'receiver',
          claimTxids: 'claim-tx',
          claimSubmittedAt: DateTime.utc(2026, 10, 1),
        );
        await reconcilePaymentLinkClaimReceipt(
          record: receiving,
          transactions: [
            _transaction(
              txid: 'claim-tx',
              minedHeight: api.tipHeight - 5,
              accountBalanceDelta: first.link.amountZatoshi.toInt(),
            ),
          ],
          verifiedHeight: BigInt.from(api.tipHeight),
          store: store,
          deleteRetainedWallet: (_) async {
            await first.directory.delete(recursive: true);
            return true;
          },
        );
        expect((await store.load()).single.claimLink, isNull);
        expect(await first.directory.exists(), isFalse);

        api.total = BigInt.zero;
        api.maxClaimable = null;
        if (cleanup != 'inspection') {
          accounts.select('receiver', 'u1receiveraddress');
          final reopened = await service.prepareClaim(first.link);
          expect(await File(reopened.dbPath).exists(), isTrue);
          if (cleanup == 'retention') {
            // A stale screen may choose retention for a completed receipt.
            await service.retainPendingClaim(reopened);
          } else {
            await service.discardClaimSession(reopened);
          }
        } else {
          final reopened = await service.inspectClaim(first.link);
          expect(await File(reopened.dbPath).exists(), isTrue);
          await service.discardClaimInspection(reopened);
        }

        expect(api.importCalls, 2);
        expect(await first.directory.exists(), isFalse);
        final receipt = (await store.load()).single;
        expect(receipt.status, PaymentLinkReceivedStatus.received);
        expect(receipt.claimLink, isNull);
        expect(receipt.claimTxids, 'claim-tx');
        expect(receipt.destinationAccountUuid, 'receiver');
      });
    }

    test(
      'retention preserves a received wallet before recovery ends',
      () async {
        accounts.select('receiver', 'u1receiveraddress');
        final session = await service.prepareClaim(_link());
        final store = container.read(paymentLinkReceivedStoreProvider);
        await store.saveReady(session.link);
        await store.markReceiving(
          address: session.link.address,
          destinationAccountUuid: 'receiver',
          claimTxids: 'claim-tx',
          claimSubmittedAt: DateTime.utc(2026, 10, 1),
        );
        await store.markReceived(address: session.link.address);

        await service.retainPendingClaim(session);

        expect(await File(session.dbPath).exists(), isTrue);
        expect((await store.load()).single.claimLink, isNotNull);
      },
    );

    test('discard keeps a saved wallet while locked', () async {
      final inspection = await service.inspectClaim(_link());
      await container
          .read(paymentLinkReceivedStoreProvider)
          .saveReady(inspection.link);
      final security =
          container.read(appSecurityProvider.notifier)
              as _SetupSecurityNotifier;
      security.lockForTest();
      receivedStorage.onRead = () async {
        fail('Locked cleanup must not read saved-card storage.');
      };

      await service.discardClaimInspection(inspection);

      expect(await File(inspection.dbPath).exists(), isTrue);
      expect(api.cancelCalls, 1);
    });

    test('discard keeps a wallet if the app locks during lookup', () async {
      final inspection = await service.inspectClaim(_link());
      final security =
          container.read(appSecurityProvider.notifier)
              as _SetupSecurityNotifier;
      final readStarted = Completer<void>();
      final readResult = Completer<String?>();
      receivedStorage.onRead = () {
        readStarted.complete();
        return readResult.future;
      };

      final cleanup = service.discardClaimInspection(inspection);
      await readStarted.future;
      security.lockForTest();
      readResult.complete(null);
      await cleanup;

      expect(await File(inspection.dbPath).exists(), isTrue);
      // A subsequent unlocked cleanup can still discard an unsaved wallet.
      receivedStorage.onRead = null;
      security.unlockForTest();
      await service.discardClaimInspection(inspection);
      expect(await inspection.directory.exists(), isFalse);
    });

    test('a failed first inspection removes its temporary wallet', () async {
      api.failSync = true;
      await expectLater(service.inspectClaim(_link()), throwsStateError);
      expect(await File(api.importedDbPath!).parent.exists(), isFalse);
      expect(receivedStorage.value, isNull);
    });

    test(
      'a failed reinspection preserves a previously cached wallet',
      () async {
        final inspection = await service.inspectClaim(_link());
        api.failSync = true;
        await expectLater(service.inspectClaim(_link()), throwsStateError);
        expect(await File(inspection.dbPath).exists(), isTrue);
        expect(api.importCalls, 1);
      },
    );
  });
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
  required int minedHeight,
  required int accountBalanceDelta,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: BigInt.from(minedHeight),
    expiredUnmined: false,
    accountBalanceDelta: accountBalanceDelta,
    fee: BigInt.zero,
    blockTime: BigInt.zero,
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.one,
    displayPool: 'shielded',
    createdTime: BigInt.zero,
  );
}

class _SetupSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);

  void lockForTest() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
  );

  void unlockForTest() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: true,
  );
}

class _RpcNotifier extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => const RpcEndpointConfig(
    networkName: 'main',
    lightwalletdUrl: 'https://example.invalid:9067',
  );

  void setEndpointForTest(RpcEndpointConfig endpoint) => state = endpoint;

  void setNetworkForTest(String network) => state = RpcEndpointConfig(
    networkName: network,
    lightwalletdUrl: 'https://example.invalid:9067',
  );
}

class _MemoryRecoveryStorage implements PaymentLinkRecoveryStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async => value = nextValue;
}

class _MemoryReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;
  Future<String?> Function()? onRead;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => onRead == null ? value : await onRead!();

  @override
  Future<void> write(String nextValue) async => value = nextValue;
}

class _InspectAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState();

  void select(String uuid, String address) {
    state = AsyncData(
      AccountState(activeAccountUuid: uuid, activeAddress: address),
    );
  }
}

class _InspectRustApi implements RustLibApi {
  int tipHeight = 3_456_900;
  BigInt? maxClaimable;
  BigInt fee = BigInt.from(10000);
  BigInt total = BigInt.from(110000);
  final estimateDestinations = <String>[];
  int mainWalletLookups = 0;
  int importCalls = 0;
  int syncCalls = 0;
  int cancelCalls = 0;
  bool failSync = false;
  bool failCheckOnce = false;
  final checkUrls = <String>[];
  Completer<void>? checkGate;
  Completer<void> checkStarted = Completer<void>();
  Completer<void>? tipGate;
  Completer<void> tipStarted = Completer<void>();
  Completer<void>? importGate;
  Completer<void> importStarted = Completer<void>();
  int? fundingHeight;
  int? checkedTip;
  String? importedDbPath;
  Completer<String>? lookupGate;
  Completer<void> lookupStarted = Completer<void>();

  void reset() {
    tipHeight = 3_456_900;
    maxClaimable = BigInt.from(100000);
    fee = BigInt.from(10000);
    total = BigInt.from(110000);
    estimateDestinations.clear();
    mainWalletLookups = 0;
    importCalls = 0;
    syncCalls = 0;
    cancelCalls = 0;
    failSync = false;
    failCheckOnce = false;
    checkUrls.clear();
    checkGate = null;
    checkStarted = Completer<void>();
    tipGate = null;
    tipStarted = Completer<void>();
    importGate = null;
    importStarted = Completer<void>();
    fundingHeight = null;
    checkedTip = null;
    importedDbPath = null;
    lookupGate = null;
    lookupStarted = Completer<void>();
  }

  @override
  Future<rust_wallet.WalletImportResult> crateApiWalletImportWallet({
    required String mnemonic,
    required String bip39Passphrase,
    BigInt? birthdayHeight,
    required String network,
    required String dbPath,
    String? accountName,
  }) async {
    importCalls++;
    importedDbPath = dbPath;
    await File(dbPath).writeAsString('claim wallet fixture');
    if (!importStarted.isCompleted) importStarted.complete();
    await importGate?.future;
    return rust_wallet.WalletImportResult(
      unifiedAddress: _link().address,
      accountUuid: 'claim-wallet',
    );
  }

  @override
  Future<void> crateApiWalletValidateGiftAddress({
    required String mnemonic,
    required String network,
    required String address,
  }) async {}

  @override
  Stream<rust_sync.ApiGiftCardCheckProgress>
  crateApiSyncRunPaymentLinkClaimCheck({
    required bool allowResubmit,
    required String claimId,
    required String dbPath,
    required String lightwalletdUrl,
    required List<String> fallbackUrls,
    required String network,
  }) async* {
    syncCalls++;
    checkUrls.add(lightwalletdUrl);
    if (!checkStarted.isCompleted) checkStarted.complete();
    await checkGate?.future;
    if (failCheckOnce) {
      failCheckOnce = false;
      throw const SocketException('Connection reset');
    }
    if (failSync) throw StateError('Claim scan failed');
    yield rust_sync.ApiGiftCardCheckProgress(
      phase: 'complete',
      completed: BigInt.one,
      total: BigInt.one,
      fundingHeight: total > BigInt.zero ? (fundingHeight ?? tipHeight - 1) : 0,
      checkedHeight: checkedTip ?? tipHeight,
      totalZatoshi: total,
      unspentZatoshi: total,
      complete: true,
    );
  }

  @override
  void crateApiSyncCancelPaymentLinkClaimSync({required String claimId}) =>
      cancelCalls++;

  @override
  Future<rust_sync.WalletBalance> crateApiSyncGetBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => rust_sync.WalletBalance(
    availability: rust_sync.WalletBalanceAvailability.available,
    transparent: BigInt.zero,
    sapling: BigInt.zero,
    orchard: BigInt.zero,
    ironwood: total,
    transparentLocked: BigInt.zero,
    saplingLocked: BigInt.zero,
    orchardLocked: BigInt.zero,
    ironwoodLocked: BigInt.zero,
    transparentPending: BigInt.zero,
    saplingPending: BigInt.zero,
    orchardPending: BigInt.zero,
    ironwoodPending: BigInt.zero,
    changePendingConfirmation: BigInt.zero,
    valuePendingSpendability: BigInt.zero,
    uneconomicValue: BigInt.zero,
    spendable: total,
    locked: BigInt.zero,
    total: total,
  );

  @override
  Future<rust_sync.SendMaxEstimateResult>
  crateApiSyncEstimatePaymentLinkClaimMax({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
  }) async {
    estimateDestinations.add(toAddress);
    final amount = maxClaimable;
    if (amount == null) throw StateError('Insufficient balance');
    return rust_sync.SendMaxEstimateResult(
      amountZatoshi: amount,
      feeZatoshi: fee,
      needsSaplingParams: false,
    );
  }

  @override
  Future<List<rust_sync.TransactionInfo>> crateApiSyncGetTransactionHistory({
    required String dbPath,
    required String network,
    required String accountUuid,
    int? limit,
  }) async => [
    _transaction(
      txid: 'funding',
      minedHeight: fundingHeight ?? tipHeight - 1,
      accountBalanceDelta: total.toInt(),
    ),
  ];

  @override
  Future<rust_sync.PaymentLinkSpendEvidence>
  crateApiSyncGetPaymentLinkSpendEvidence({
    required String dbPath,
    required String accountUuid,
    required String claimTxids,
  }) async => rust_sync.PaymentLinkSpendEvidence(
    allFundsSpentElsewhere: false,
    conflictedTxids: const [],
    localClaimTxids: const [],
    verifiedHeight: BigInt.from(tipHeight),
  );

  @override
  Future<List<rust_wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async => [
    rust_wallet.AccountInfo(
      uuid: 'claim-wallet',
      birthdayHeight: _link().birthdayHeight,
      name: 'Claim',
      unifiedAddress: _link().address,
      isSeedAnchor: true,
      isHardware: false,
    ),
  ];

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    mainWalletLookups++;
    if (!lookupStarted.isCompleted) lookupStarted.complete();
    return lookupGate == null ? 'u1${accountUuid}address' : lookupGate!.future;
  }

  @override
  Future<rust_sync.AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) async => const rust_sync.AddressValidationResult(
    isValid: true,
    addressType: 'unified',
    wrongNetwork: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
