import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_claim_flow_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_claim_import_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';

import '../../support/payment_links_screen_support.dart'
    show incomingLink, secondIncomingLink;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  late _FlowOperations operations;
  late _Wallet wallet;

  ProviderContainer makeContainer() {
    operations = _FlowOperations();
    final container = ProviderContainer(
      overrides: [
        appSecurityProvider.overrideWith(_NoWalletSecurity.new),
        walletProvider.overrideWith(() => wallet = _Wallet()),
        paymentLinkClaimRecoveryRunnerProvider.overrideWithValue(
          () async => const [],
        ),
        paymentLinkOperationsProvider.overrideWithValue(operations),
      ],
    );
    addTearDown(container.dispose);
    container.read(walletProvider);
    return container;
  }

  GiftClaimFlowNotifier flow(ProviderContainer container) =>
      container.read(giftClaimFlowProvider.notifier);

  test(
    'a malformed import journal never exposes its bearer in recovery errors',
    () async {
      final raw = '{"link":"${incomingLink.toUri()}"';
      FlutterSecureStorage.setMockInitialValues({
        'zcash_gift_card_import_handoff_v1': raw,
      });
      final container = makeContainer();
      await expectLater(
        container.read(giftClaimImportStoreProvider).load(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.source,
            'source',
            isNull,
          ),
        ),
      );
      expect(
        await const FlutterSecureStorage().read(
          key: 'zcash_gift_card_import_handoff_v1',
        ),
        raw,
      );
    },
  );

  test('checks a Card without an account', () async {
    final container = makeContainer();

    flow(container).open(incomingLink);
    expect(
      container.read(giftClaimFlowProvider)!.phase,
      GiftClaimPhase.checking,
    );

    operations.completeNext(_inspection(incomingLink));
    await pumpEventQueue();

    final state = container.read(giftClaimFlowProvider)!;
    expect(state.phase, GiftClaimPhase.inspected);
    expect(state.inspection!.claimableZatoshi > BigInt.zero, isTrue);
    expect(operations.inspected, [incomingLink]);
  });

  test('reopening the same Card keeps the running check', () async {
    final container = makeContainer();

    flow(container).open(incomingLink);
    flow(
      container,
    ).open(VizorPaymentLink.parse(incomingLink.toUri().toString()));

    expect(operations.inspected, hasLength(1));
  });

  test(
    'another Card replaces the first and deletes its claim wallet',
    () async {
      final container = makeContainer();
      flow(container).open(incomingLink);
      operations.completeNext(_inspection(incomingLink));
      await pumpEventQueue();

      flow(container).open(secondIncomingLink);
      await pumpEventQueue();

      expect(operations.discarded.single.link, incomingLink);
      expect(container.read(giftClaimFlowProvider)!.link, secondIncomingLink);
    },
  );

  test('closing deletes the claim wallet and drops the queued link', () async {
    final container = makeContainer();
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    flow(container).open(incomingLink);
    operations.completeNext(_inspection(incomingLink));
    await pumpEventQueue();

    await flow(container).close();
    await pumpEventQueue();

    expect(container.read(giftClaimFlowProvider), isNull);
    expect(operations.discarded, hasLength(1));
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
  });

  test('a check that finishes after close deletes its claim wallet', () async {
    final container = makeContainer();
    flow(container).open(incomingLink);

    await flow(container).close();
    operations.completeNext(_inspection(incomingLink));
    await pumpEventQueue();

    expect(container.read(giftClaimFlowProvider), isNull);
    expect(operations.discarded, hasLength(1));
  });

  test('every replaced check deletes its claim wallet', () async {
    final container = makeContainer();
    flow(container).open(incomingLink);
    flow(container).open(secondIncomingLink);
    await flow(container).close();

    operations.completeNext(_inspection(incomingLink));
    operations.completeNext(_inspection(secondIncomingLink));
    await pumpEventQueue();

    expect(operations.discarded.map((inspection) => inspection.link), [
      incomingLink,
      secondIncomingLink,
    ]);
  });

  test(
    'a corrected link waits for the shared claim wallet to be released',
    () async {
      final container = makeContainer();
      final corrected = _correctedIncomingLink();
      final cleanup = Completer<void>();
      operations.discardGate = cleanup;

      flow(container).open(incomingLink);
      flow(container).open(corrected);
      expect(operations.inspected, [incomingLink]);

      operations.completeNext(_inspection(incomingLink));
      await pumpEventQueue();
      expect(operations.discardStarted.map((item) => item.link), [
        incomingLink,
      ]);
      expect(operations.inspected, [incomingLink]);

      cleanup.complete();
      await pumpEventQueue();
      expect(operations.inspected, [incomingLink, corrected]);

      operations.completeNext(_inspection(corrected));
      await pumpEventQueue();
      expect(
        container.read(giftClaimFlowProvider)?.inspection?.link,
        corrected,
      );
    },
  );

  test('closing then opening a corrected link waits for cleanup', () async {
    final container = makeContainer();
    final corrected = _correctedIncomingLink();
    final cleanup = Completer<void>();
    operations.discardGate = cleanup;

    flow(container).open(incomingLink);
    await flow(container).close();
    flow(container).open(corrected);
    operations.completeNext(_inspection(incomingLink));
    await pumpEventQueue();

    expect(operations.discardStarted.map((item) => item.link), [incomingLink]);
    expect(operations.inspected, [incomingLink]);
    cleanup.complete();
    await pumpEventQueue();
    expect(operations.inspected, [incomingLink, corrected]);

    operations.completeNext(_inspection(corrected));
    await pumpEventQueue();
    expect(container.read(giftClaimFlowProvider)?.inspection?.link, corrected);
  });

  test('a different claim wallet does not wait for cleanup', () async {
    final container = makeContainer();
    final cleanup = Completer<void>();
    operations.discardGate = cleanup;

    flow(container).open(incomingLink);
    operations.completeNext(_inspection(incomingLink));
    await pumpEventQueue();
    flow(container).open(secondIncomingLink);
    await pumpEventQueue();

    expect(operations.discardStarted.map((item) => item.link), [incomingLink]);
    expect(operations.inspected, [incomingLink, secondIncomingLink]);
    cleanup.complete();
  });

  test('setup keeps the claim wallet and queues the link', () async {
    final container = makeContainer();
    flow(container).open(incomingLink);
    operations.completeNext(_inspection(incomingLink));
    await pumpEventQueue();

    await flow(container).handOffToSetup();
    await pumpEventQueue();

    expect(operations.discarded, isEmpty);
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink,
      isA<VizorPaymentLink>().having(
        (link) => link.hasSameCanonicalPayload(incomingLink),
        'same Card',
        isTrue,
      ),
    );
    // Coming back from setup still shows the Card.
    expect(container.read(giftClaimFlowProvider)!.inspection, isNotNull);
    expect(container.read(giftClaimSetupReturnProvider)?.link, incomingLink);
  });

  test(
    'existing-wallet setup keeps its chosen Card ahead of another link',
    () async {
      final container = makeContainer();
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(incomingLink.toUri().toString());
      flow(container).open(secondIncomingLink);
      operations.completeNext(_inspection(secondIncomingLink));
      await pumpEventQueue();

      expect(await flow(container).handOffToSetup(), isTrue);
      expect(
        container
            .read(paymentLinkIntakeProvider)
            .pendingLink
            ?.hasSameCanonicalPayload(secondIncomingLink),
        isTrue,
      );
    },
  );

  test('multi-account setup requires an explicit receiving account', () {
    final request = GiftClaimSetupReturn(
      link: incomingLink,
      inspection: _inspection(incomingLink),
      accountUuidsBeforeSetup: const {'existing'},
    );

    expect(
      request.recipientAccountUuid(
        currentAccountUuids: const {'existing', 'primary', 'additional'},
      ),
      isNull,
    );
  });

  test('a sole imported account is the automatic recipient', () {
    final request = GiftClaimSetupReturn(
      link: incomingLink,
      inspection: _inspection(incomingLink),
      accountUuidsBeforeSetup: const {'existing'},
    );

    expect(
      request.recipientAccountUuid(
        currentAccountUuids: const {'existing', 'imported'},
      ),
      'imported',
    );
  });

  test('setup completion does not clear a newer Card request', () async {
    final container = makeContainer();
    final notifier = container.read(giftClaimSetupReturnProvider.notifier);

    await notifier.begin(
      incomingLink,
      accountUuidsBeforeSetup: const {'existing'},
      inspection: _inspection(incomingLink),
    );
    final earlier = container.read(giftClaimSetupReturnProvider)!;
    await notifier.begin(
      secondIncomingLink,
      inspection: _inspection(secondIncomingLink),
      accountUuidsBeforeSetup: const {'existing'},
    );
    final newer = container.read(giftClaimSetupReturnProvider)!;

    expect(notifier.clearIfMatches(earlier), isFalse);
    expect(container.read(giftClaimSetupReturnProvider), same(newer));
    expect(notifier.clearIfMatches(newer), isTrue);
    expect(container.read(giftClaimSetupReturnProvider), isNull);
  });

  test(
    'a new wallet ends the flow without deleting the claim wallet',
    () async {
      final container = makeContainer();
      flow(container).open(incomingLink);
      operations.completeNext(_inspection(incomingLink));
      await pumpEventQueue();
      await flow(container).handOffToSetup();

      wallet.create();
      await pumpEventQueue();

      expect(container.read(giftClaimFlowProvider), isNull);
      expect(operations.discarded, isEmpty);
    },
  );

  test('check failures become their own states', () async {
    final container = makeContainer();

    flow(container).open(incomingLink);
    operations.failNext(const PaymentLinkLongSyncConfirmationRequired());
    await pumpEventQueue();
    expect(
      container.read(giftClaimFlowProvider)!.phase,
      GiftClaimPhase.longSyncConfirmation,
    );

    flow(container).recheck(allowLongSync: true);
    expect(operations.allowLongSync.last, isTrue);
    operations.failNext(
      const PaymentLinkNetworkMismatchException(
        linkNetwork: 'main',
        walletNetwork: 'test',
      ),
    );
    await pumpEventQueue();
    expect(
      container.read(giftClaimFlowProvider)!.failure,
      GiftClaimFailure.otherNetwork,
    );

    flow(container).recheck();
    operations.failNext(const SocketException('offline'));
    await pumpEventQueue();
    expect(
      container.read(giftClaimFlowProvider)!.failure,
      GiftClaimFailure.network,
    );
  });
}

VizorPaymentLink _correctedIncomingLink() => VizorPaymentLink(
  network: incomingLink.network,
  address: incomingLink.address,
  amountZatoshi: incomingLink.amountZatoshi + BigInt.one,
  mnemonic: incomingLink.mnemonic,
  birthdayHeight: incomingLink.birthdayHeight,
  label: 'Corrected gift',
  createdAt: incomingLink.createdAt,
  presentation: incomingLink.presentation,
);

PaymentLinkClaimInspection _inspection(
  VizorPaymentLink link, {
  PaymentLinkAvailability availability = PaymentLinkAvailability.available,
}) => PaymentLinkClaimInspection(
  link: link,
  directory: Directory.systemTemp,
  dbPath: '/tmp/claim.db',
  accountUuid: 'claim-account',
  totalZatoshi: link.amountZatoshi + BigInt.from(10000),
  claimableZatoshi: link.amountZatoshi,
  feeZatoshi: BigInt.from(10000),
  fundingConfirmationCount: kPaymentLinkClaimConfirmationTarget,
  waitingForFundingConfirmations: false,
  availability: availability,
);

class _FlowOperations implements PaymentLinkOperations {
  final inspected = <VizorPaymentLink>[];
  final allowLongSync = <bool>[];
  final discardStarted = <PaymentLinkClaimInspection>[];
  final discarded = <PaymentLinkClaimInspection>[];
  final _pending = <Completer<PaymentLinkClaimInspection>>[];
  Completer<void>? discardGate;

  void completeNext(PaymentLinkClaimInspection inspection) =>
      _pending.removeAt(0).complete(inspection);

  void failNext(Object error) => _pending.removeAt(0).completeError(error);

  @override
  Future<PaymentLinkClaimInspection> inspectClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) {
    inspected.add(link);
    this.allowLongSync.add(allowLongSync);
    final completer = Completer<PaymentLinkClaimInspection>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> discardClaimInspection(
    PaymentLinkClaimInspection inspection,
  ) async {
    discardStarted.add(inspection);
    final gate = discardGate;
    if (gate != null) await gate.future;
    discarded.add(inspection);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoWalletSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);
}

class _Wallet extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState();

  void create() => state = const AsyncData(WalletState(hasWallet: true));
}
