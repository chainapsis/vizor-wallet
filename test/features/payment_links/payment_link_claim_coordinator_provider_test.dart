import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_lifecycle_registry_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'a coordinator created while hidden rejects preparations and recovery',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      var recoveries = 0;
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
            recoveries++;
            return const [];
          }),
        ],
      );
      try {
        final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
        coordinator.resume();
        expect(coordinator.acceptsPreparation, isFalse);
        await expectLater(
          coordinator.trackPreparation(() async {}),
          throwsStateError,
        );
        expect(await coordinator.refresh(), isEmpty);
        expect(recoveries, 0);
      } finally {
        container.dispose();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    },
  );

  test(
    'reset cancels native checks and drains account-free preparations',
    () async {
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
      final release = Completer<void>();
      var cancelled = false;
      final unregister = coordinator.registerCheckCancellation(() async {
        cancelled = true;
      });
      final work = coordinator.trackPreparation(() => release.future);
      var drained = false;
      final drain = coordinator.quiesceAndDrain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      expect(drained, isFalse);
      await expectLater(
        coordinator.trackPreparation(() async {}),
        throwsStateError,
      );
      release.complete();
      await work;
      await drain;
      unregister();
      expect(drained, isTrue);
    },
  );

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

  test('the screen and recovery share one setup Card preparation', () async {
    final releasePreparation = Completer<void>();
    var preparationCalls = 0;
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
    final link = _link('shared-setup-claim');

    Future<PaymentLinkClaimSession> prepare() async {
      preparationCalls++;
      await releasePreparation.future;
      return _session(link.address, destinationAccountUuid: 'setup-account');
    }

    final screenPreparation = coordinator.prepareSetupClaim(
      link,
      destinationAccountUuid: 'setup-account',
      prepare: prepare,
    );
    final recoveryPreparation = coordinator.prepareSetupClaim(
      link,
      destinationAccountUuid: 'setup-account',
      prepare: prepare,
    );
    await Future<void>.delayed(Duration.zero);

    expect(identical(screenPreparation, recoveryPreparation), isTrue);
    expect(preparationCalls, 1);
    expect(coordinator.activeSetupPreparationCount, 1);

    releasePreparation.complete();
    expect(await recoveryPreparation, await screenPreparation);
    expect(coordinator.activeSetupPreparationCount, 0);
  });

  test(
    'long-scan approval retries an unapproved shared preparation serially',
    () async {
      final first = Completer<void>();
      var active = 0;
      var maxActive = 0;
      var calls = 0;
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
      final link = _link('long-scan-card');
      final unapproved = coordinator.prepareSetupClaim(
        link,
        destinationAccountUuid: 'setup-account',
        allowLongSync: false,
        prepare: () async {
          calls++;
          active++;
          maxActive = active;
          await first.future;
          active--;
          throw const PaymentLinkLongSyncConfirmationRequired();
        },
      );
      final rejected = expectLater(
        unapproved,
        throwsA(isA<PaymentLinkLongSyncConfirmationRequired>()),
      );
      final approved = coordinator.prepareSetupClaim(
        link,
        destinationAccountUuid: 'setup-account',
        allowLongSync: true,
        prepare: () async {
          calls++;
          active++;
          if (active > maxActive) maxActive = active;
          active--;
          return _session(
            link.address,
            destinationAccountUuid: 'setup-account',
          );
        },
      );
      expect(calls, 1);
      first.complete();
      await rejected;
      expect((await approved).destinationAccountUuid, 'setup-account');
      expect(calls, 2);
      expect(maxActive, 1);
    },
  );

  test('a setup Card preparation stays pinned to its first account', () async {
    final releasePreparation = Completer<void>();
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
    final link = _link('pinned-setup-claim');
    final first = coordinator.prepareSetupClaim(
      link,
      destinationAccountUuid: 'setup-account',
      prepare: () async {
        await releasePreparation.future;
        return _session(link.address, destinationAccountUuid: 'setup-account');
      },
    );

    await expectLater(
      coordinator.prepareSetupClaim(
        link,
        destinationAccountUuid: 'other-account',
        prepare: () async =>
            _session(link.address, destinationAccountUuid: 'other-account'),
      ),
      throwsA(isA<PaymentLinkClaimDestinationChangedException>()),
    );

    releasePreparation.complete();
    await first;
  });

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

  for (final availability in [
    PaymentLinkAvailability.checking,
    PaymentLinkAvailability.failed,
  ]) {
    test(
      'removed recipient cleanup retries without claiming a $availability Card',
      () async {
        var recoveryCalls = 0;
        var prepareCalls = 0;
        final cleaned = Completer<void>();
        final container = ProviderContainer(
          overrides: [
            appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
            accountProvider.overrideWith(
              () => _SetupAccountNotifier(includeSetupAccount: false),
            ),
            paymentLinkClaimRecoveryRetryDelayProvider.overrideWithValue(
              const Duration(milliseconds: 1),
            ),
            paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
              recoveryCalls++;
              if (recoveryCalls == 1) {
                // A failed file removal leaves the Card durable for retry.
                return [
                  _readySetupRecord.copyWith(
                    availability: availability,
                    archived: availability == PaymentLinkAvailability.failed,
                  ),
                ];
              }
              if (!cleaned.isCompleted) cleaned.complete();
              return const [];
            }),
            paymentLinkSetupClaimPreparerProvider.overrideWithValue((
              link, {
              required destinationAccountUuid,
            }) async {
              prepareCalls++;
              return _session(link.address);
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        container.read(paymentLinkClaimCoordinatorProvider);
        await cleaned.future.timeout(const Duration(seconds: 1));

        expect(recoveryCalls, 2);
        expect(prepareCalls, 0);
      },
    );
  }

  test(
    'a ready setup Card automatically claims into its saved account',
    () async {
      final submitted = Completer<PaymentLinkClaimSession>();
      final preparedDestinations = <String>[];
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          accountProvider.overrideWith(_SetupAccountNotifier.new),
          paymentLinkClaimRecoveryRetryDelayProvider.overrideWithValue(
            const Duration(days: 1),
          ),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
            () async => [_readySetupRecord],
          ),
          paymentLinkSetupClaimPreparerProvider.overrideWithValue((
            link, {
            required destinationAccountUuid,
          }) async {
            preparedDestinations.add(destinationAccountUuid);
            return _session(
              link.address,
              destinationAccountUuid: destinationAccountUuid,
            );
          }),
          paymentLinkClaimSubmitterProvider.overrideWithValue((session) async {
            if (!submitted.isCompleted) submitted.complete(session);
            return _result('automatic-claim-txid');
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(paymentLinkClaimCoordinatorProvider);
      final session = await submitted.future.timeout(
        const Duration(seconds: 1),
      );

      expect(preparedDestinations, ['setup-account']);
      expect(session.destinationAccountUuid, 'setup-account');
    },
  );

  test(
    'disposing during ready setup recovery does not reuse its Ref',
    () async {
      final recoveryStarted = Completer<void>();
      final releaseRecovery = Completer<List<PaymentLinkReceivedRecord>>();
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          accountProvider.overrideWith(_SetupAccountNotifier.new),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() {
            if (!recoveryStarted.isCompleted) recoveryStarted.complete();
            return releaseRecovery.future;
          }),
        ],
      );
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      final recovery = coordinator.refresh();
      await recoveryStarted.future.timeout(const Duration(seconds: 1));

      container.dispose();
      releaseRecovery.complete([_readySetupRecord]);

      expect(await recovery, [_readySetupRecord]);
    },
  );

  test(
    'a newly retained setup Card retriggers an initially empty recovery',
    () async {
      final firstRecovery = Completer<void>();
      final submitted = Completer<void>();
      var includeSetupCard = false;
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          accountProvider.overrideWith(_SetupAccountNotifier.new),
          paymentLinkClaimRecoveryRetryDelayProvider.overrideWithValue(
            const Duration(milliseconds: 1),
          ),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
            if (!firstRecovery.isCompleted) firstRecovery.complete();
            return includeSetupCard ? [_readySetupRecord] : const [];
          }),
          paymentLinkSetupClaimPreparerProvider.overrideWithValue(
            (link, {required destinationAccountUuid}) async => _session(
              link.address,
              destinationAccountUuid: destinationAccountUuid,
            ),
          ),
          paymentLinkClaimSubmitterProvider.overrideWithValue((session) async {
            if (!submitted.isCompleted) submitted.complete();
            return _result('retained-setup-txid');
          }),
        ],
      );
      addTearDown(container.dispose);
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      await firstRecovery.future.timeout(const Duration(seconds: 1));

      includeSetupCard = true;
      await coordinator.trackRetention(
        () async {},
        scheduleReadySetupRecovery: true,
      );
      await submitted.future.timeout(const Duration(seconds: 1));
    },
  );

  test('ordinary ready Cards are not automatically claimed', () async {
    var prepareCalls = 0;
    final recovered = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
        accountProvider.overrideWith(_SetupAccountNotifier.new),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
          if (!recovered.isCompleted) recovered.complete();
          return [_readySetupRecordWithoutAccount];
        }),
        paymentLinkSetupClaimPreparerProvider.overrideWithValue((
          link, {
          required destinationAccountUuid,
        }) async {
          prepareCalls++;
          return _session(link.address);
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(paymentLinkClaimCoordinatorProvider);
    await recovered.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(prepareCalls, 0);
  });

  test(
    'password setup enables recovery after its journal has cleared',
    () async {
      final security = _PasswordSetupSecurityNotifier();
      final submitted = Completer<void>();
      var recoveryCalls = 0;
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(() => security),
          accountProvider.overrideWith(_SetupAccountNotifier.new),
          paymentLinkClaimRecoveryRetryDelayProvider.overrideWithValue(
            const Duration(milliseconds: 1),
          ),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
            recoveryCalls++;
            return [_readySetupRecord];
          }),
          paymentLinkSetupClaimPreparerProvider.overrideWithValue(
            (link, {required destinationAccountUuid}) async => _session(
              link.address,
              destinationAccountUuid: destinationAccountUuid,
            ),
          ),
          paymentLinkClaimSubmitterProvider.overrideWithValue((session) async {
            if (!submitted.isCompleted) submitted.complete();
            return _result('post-setup-txid');
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(paymentLinkClaimCoordinatorProvider);
      await Future<void>.delayed(Duration.zero);
      expect(recoveryCalls, 0);

      security.commitForTest();
      await submitted.future.timeout(const Duration(seconds: 1));
      expect(recoveryCalls, 1);
    },
  );

  test(
    'reset drains preparation and prevents its automatic submission',
    () async {
      final preparationStarted = Completer<void>();
      final releasePreparation = Completer<void>();
      var submissionCalls = 0;
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          accountProvider.overrideWith(_SetupAccountNotifier.new),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
            () async => [_readySetupRecord],
          ),
          paymentLinkSetupClaimPreparerProvider.overrideWithValue((
            link, {
            required destinationAccountUuid,
          }) async {
            if (!preparationStarted.isCompleted) preparationStarted.complete();
            await releasePreparation.future;
            return _session(
              link.address,
              destinationAccountUuid: destinationAccountUuid,
            );
          }),
          paymentLinkClaimSubmitterProvider.overrideWithValue((session) async {
            submissionCalls++;
            return _result('must-not-submit');
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(paymentLinkClaimCoordinatorProvider);
      final lifecycle = container.read(
        paymentLinkClaimLifecycleRegistryProvider,
      );
      await preparationStarted.future.timeout(const Duration(seconds: 1));

      var drained = false;
      final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);

      releasePreparation.complete();
      await drain;
      expect(submissionCalls, 0);
    },
  );

  test(
    'a completed receipt keeps recovering until its retained secret is cleared',
    () async {
      var recoveryCalls = 0;
      final finalized = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
          paymentLinkClaimRecoveryRetryDelayProvider.overrideWithValue(
            const Duration(milliseconds: 1),
          ),
          paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(() async {
            recoveryCalls++;
            if (recoveryCalls == 1) {
              return [
                _receivingRecord.copyWith(
                  status: PaymentLinkReceivedStatus.received,
                ),
              ];
            }
            if (!finalized.isCompleted) finalized.complete();
            return [_receivedRecord];
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(paymentLinkClaimCoordinatorProvider);
      await finalized.future.timeout(const Duration(seconds: 1));
      expect(recoveryCalls, 2);
    },
  );

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

    final tracked = coordinator.trackRetention(() async {
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
    await coordinator.trackRetention(() async => written = true);

    expect(written, isFalse);

    lifecycle.resume();
    await coordinator.trackRetention(() async => written = true);
    expect(written, isTrue);
  });

  test(
    'overlapping retentions for one Card each hold the reset open',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      var firstWritten = false;
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
      final lifecycle = container.read(
        paymentLinkClaimLifecycleRegistryProvider,
      );

      // Both retentions belong to the same Card: leave, reopen, leave again
      // while the first cancel is still unwinding.
      final firstRetention = coordinator.trackRetention(() async {
        await first.future;
        firstWritten = true;
      });
      final secondRetention = coordinator.trackRetention(() => second.future);
      await Future<void>.delayed(Duration.zero);

      var drained = false;
      final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);

      second.complete();
      await secondRetention;
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      expect(firstWritten, isFalse);

      first.complete();
      await firstRetention;
      await drain;

      expect(firstWritten, isTrue);
      expect(drained, isTrue);
    },
  );
}

PaymentLinkClaimSession _session(
  String address, {
  String? destinationAccountUuid,
}) {
  final link = _link(address);
  return PaymentLinkClaimSession(
    link: link,
    destinationAddress: 'destination-$address',
    destinationAccountUuid:
        destinationAccountUuid ?? 'destination-account-$address',
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
  claimSubmittedAt: DateTime.utc(2026, 8, 28),
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

final _readySetupRecord = PaymentLinkReceivedRecord(
  network: 'main',
  address: 'waiting-setup-claim',
  amountZatoshi: BigInt.from(100000),
  createdAt: DateTime.utc(2026, 9, 23),
  artworkId: null,
  status: PaymentLinkReceivedStatus.readyToClaim,
  claimLink: _link('waiting-setup-claim'),
  destinationAccountUuid: null,
  claimTxids: null,
  updatedAt: DateTime.utc(2026, 9, 23),
  availability: PaymentLinkAvailability.checking,
  setupAccountUuid: 'setup-account',
);

final _readySetupRecordWithoutAccount = PaymentLinkReceivedRecord(
  network: 'main',
  address: 'ordinary-ready-claim',
  amountZatoshi: BigInt.from(100000),
  createdAt: DateTime.utc(2026, 9, 23),
  artworkId: null,
  status: PaymentLinkReceivedStatus.readyToClaim,
  claimLink: _link('ordinary-ready-claim'),
  destinationAccountUuid: null,
  claimTxids: null,
  updatedAt: DateTime.utc(2026, 9, 23),
  availability: PaymentLinkAvailability.noBalance,
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

class _PasswordSetupSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: true);

  void commitForTest() {
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }
}

class _SetupAccountNotifier extends AccountNotifier {
  _SetupAccountNotifier({this.includeSetupAccount = true});

  final bool includeSetupAccount;

  @override
  AccountState build() => AccountState(
    accounts: [
      if (includeSetupAccount)
        const AccountInfo(uuid: 'setup-account', name: 'Gift', order: 0),
      const AccountInfo(uuid: 'other-account', name: 'Other', order: 1),
    ],
    activeAccountUuid: 'other-account',
    activeAddress: 'u1otheraccount',
  );
}
