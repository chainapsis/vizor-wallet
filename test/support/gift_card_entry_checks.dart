import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_cards_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';

import 'payment_links_screen_support.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

/// The same entry contract in the desktop and mobile token lanes.
void registerGiftCardEntryChecks({required bool mobile}) {
  final screenKey = ValueKey(
    mobile ? 'payment_links_mobile_screen' : 'payment_links_desktop_screen',
  );
  final logicalSize = mobile ? const Size(390, 844) : const Size(1080, 720);
  Finder row() => find.byKey(
    ValueKey(
      '${mobile ? 'payment_link_mobile_recovery' : 'payment_link_recovery'}_${fundedRecovery.link.address}',
    ),
  );
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('local card snapshot never starts reconciliation', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = FakePaymentLinkOperations(records: [fundedRecovery])
      ..createdRecoveryGate = gate;
    final snapshot = await loadPaymentLinkCardsSnapshot(operations);
    expect(snapshot.created, [fundedRecovery]);
    expect(operations.localCreatedLoadCalls, 1);
    expect(operations.createdLoadCalls, 0);
  });

  for (final withSnapshot in [false, true]) {
    testWidgets(
      'saved cards render before recovery completes (snapshot=$withSnapshot)',
      (tester) async {
        final operations = FakePaymentLinkOperations(records: [fundedRecovery]);
        final gate = Completer<void>();
        if (!withSnapshot) operations.createdRecoveryGate = gate;
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          logicalSize: logicalSize,
        );
        if (withSnapshot) {
          final router = GoRouter.of(tester.element(find.byKey(screenKey)));
          router.go('/home');
          await pumpFrames(tester);
          operations.createdRecoveryGate = gate;
          final snapshot = await loadPaymentLinkCardsSnapshot(operations);
          router.go('/payment-links', extra: snapshot);
        }
        await pumpFrames(tester);
        expect(find.byKey(screenKey), findsOneWidget);
        expect(row(), findsOneWidget);
        expect(gate.isCompleted, isFalse);
        expect(operations.createdLoadCalls, greaterThanOrEqualTo(1));

        // The deferred pass can remove a terminal record after entry.
        operations.records.clear();
        gate.complete();
        await pumpFrames(tester);
        expect(row(), findsNothing);
        expect(find.byKey(screenKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed deferred recovery keeps the local card list', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = FakePaymentLinkOperations(records: [fundedRecovery])
      ..createdRecoveryGate = gate;
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      logicalSize: logicalSize,
    );
    expect(row(), findsOneWidget);
    gate.completeError(StateError('network unavailable'));
    await pumpFrames(tester);
    expect(row(), findsOneWidget);
    expect(find.byKey(screenKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['complete', 'fail', 'interrupt']) {
    testWidgets('draft checking ends when recovery $outcome', (tester) async {
      final gate = Completer<void>();
      final draft = fundedRecovery.copyWith(
        state: PaymentLinkRecoveryState.draft,
        updatedAt: fundedRecovery.updatedAt,
      );
      final operations = FakePaymentLinkOperations(records: [draft])
        ..createdRecoveryGate = gate;
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        logicalSize: logicalSize,
      );
      Finder status(String label) =>
          find.descendant(of: row(), matching: find.text(label));
      expect(status('Checking…'), findsOneWidget);
      expect(status('Funding incomplete'), findsNothing);
      if (outcome == 'complete') {
        gate.complete();
      } else if (outcome == 'fail') {
        gate.completeError(StateError('network unavailable'));
      } else {
        final container = ProviderScope.containerOf(
          tester.element(find.byKey(screenKey)),
        );
        container.read(paymentLinkClaimCoordinatorProvider).pauseForLifecycle();
        gate.completeError(
          GiftCardPreparationInterrupted(
            GiftCardPreparationPauseReason.lifecycle,
          ),
        );
      }
      await pumpFrames(tester);
      expect(status('Checking…'), findsNothing);
      expect(status('Funding incomplete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  if (!mobile) {
    testWidgets('batch keeps checking while its draft recovery is pending', (
      tester,
    ) async {
      final fundingGate = Completer<void>()..complete();
      final recoveryGate = Completer<void>();
      final operations = _PendingFundingOperations(fundingGate, draft: true)
        ..createdRecoveryGate = recoveryGate;
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        logicalSize: logicalSize,
      );
      final batch = find.byKey(
        const ValueKey('payment_link_batch_entry-check'),
      );
      Finder status(String label) =>
          find.descendant(of: batch, matching: find.text(label));
      expect(status('Checking…'), findsOneWidget);
      recoveryGate.complete();
      await pumpFrames(tester);
      expect(status('Checking…'), findsNothing);
      expect(status('Payment status pending'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final failed in [false, true]) {
      testWidgets('batch first funding check is visible (failed=$failed)', (
        tester,
      ) async {
        final gate = Completer<void>();
        final operations = _PendingFundingOperations(gate);
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          logicalSize: logicalSize,
        );
        final batch = find.byKey(
          const ValueKey('payment_link_batch_entry-check'),
        );
        Finder status(String label) =>
            find.descendant(of: batch, matching: find.text(label));
        expect(status('Checking…'), findsOneWidget);
        if (failed) {
          gate.completeError(StateError('funding read unavailable'));
        } else {
          gate.complete();
        }
        await pumpFrames(tester);
        expect(status('Checking…'), findsNothing);
        expect(
          status(failed ? 'Confirming payment' : 'Ready to share'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('interrupted created recovery resumes on the open screen', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _InterruptedCreatedOperations(gate);
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      logicalSize: logicalSize,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(screenKey)),
    );
    final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
    coordinator.pauseForLifecycle();
    gate.complete();
    await pumpFrames(tester);
    expect(row(), findsOneWidget);
    final calls = operations.createdLoadCalls;
    coordinator.resumeForLifecycle();
    await pumpFrames(tester);
    expect(operations.createdLoadCalls, greaterThan(calls));
    expect(row(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'direct entry observes received recovery after the list is visible',
    (tester) async {
      final gate = Completer<void>();
      final operations = _SetupCardOperations(gate);
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        logicalSize: logicalSize,
      );
      if (mobile) {
        // This contract tests data flow. The mobile host-test window currently
        // retains desktop minimum-width geometry, so invoke the tab action.
        tester
            .widget<PaymentLinkCardsMobileView>(
              find.byType(PaymentLinkCardsMobileView),
            )
            .onTabSelected!(PaymentLinkCardsTab.received);
      } else {
        await tester.tap(find.text('Received').first);
      }
      await pumpFrames(tester);
      final received = find.byKey(
        ValueKey(
          '${mobile ? 'payment_link_mobile_received' : 'payment_link_received'}_${incomingLink.address}',
        ),
      );
      expect(received, findsOneWidget);
      expect(
        find.descendant(of: received, matching: find.text('Received')),
        findsNothing,
      );
      expect(gate.isCompleted, isFalse);
      gate.complete();
      await pumpFrames(tester);
      expect(
        find.descendant(of: received, matching: find.text('Received')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending local list is discarded when the wallet locks', (
    tester,
  ) async {
    final gate = Completer<void>();
    final security = _EntrySecurity();
    final operations = FakePaymentLinkOperations(
      records: [fundedRecovery],
      createdLoadGate: gate,
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      logicalSize: logicalSize,
      securityNotifier: security,
    );
    expect(row(), findsNothing);
    security.lock();
    gate.complete();
    await pumpFrames(tester);
    expect(row(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late recovery does not reopen a disposed card screen', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = FakePaymentLinkOperations(records: [fundedRecovery])
      ..createdRecoveryGate = gate;
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      logicalSize: logicalSize,
    );
    final router = GoRouter.of(tester.element(find.byKey(screenKey)));
    router.go('/home');
    await pumpFrames(tester);
    operations.records.clear();
    gate.complete();
    await pumpFrames(tester);
    expect(find.byKey(screenKey), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(tester.takeException(), isNull);
  });

  testWidgets('late share metadata can finish after leaving the screen', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = _PendingShareMetadataOperations(gate);
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      logicalSize: logicalSize,
    );
    await pumpFrames(tester);
    if (mobile) {
      tester.widget<PaymentLinkCardListMobileRow>(row()).onCopyLink!();
    } else {
      tester.widget<PaymentLinkCardListRow>(row()).onCopyLink!();
    }
    await pumpFrames(tester);
    expect(operations.sharedLinks, isNotEmpty);
    final router = GoRouter.of(tester.element(find.byKey(screenKey)));
    router.go('/home');
    await pumpFrames(tester);
    final calls = operations.createdLoadCalls;
    gate.complete();
    await pumpFrames(tester);
    expect(operations.createdLoadCalls, calls + 1);
    expect(find.byKey(screenKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _PendingShareMetadataOperations extends FakePaymentLinkOperations {
  _PendingShareMetadataOperations(this.gate) : super(records: [fundedRecovery]);

  final Completer<void> gate;

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) async {
    final record = await super.markCreatedLinkShared(link);
    await gate.future;
    return record;
  }
}

class _PendingFundingOperations extends FakePaymentLinkOperations {
  _PendingFundingOperations(this.gate, {bool draft = false})
    : super(
        records: [
          for (var i = 0; i < batchTestLinks.length; i++)
            PaymentLinkRecoveryRecord(
              link: batchTestLinks[i],
              sourceAccountUuid: 'account-1',
              state: draft
                  ? PaymentLinkRecoveryState.draft
                  : PaymentLinkRecoveryState.funded,
              updatedAt: fundedRecovery.updatedAt,
              fundingTxids: 'funding-txid',
              claimFeeReserveZatoshi: BigInt.from(10000),
              batchId: 'entry-check',
              batchIndex: i + 1,
              batchCount: batchTestLinks.length,
            ),
        ],
      );

  final Completer<void> gate;

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    await gate.future;
    return super.inspectCreatedLinkFundings(records);
  }
}

class _InterruptedCreatedOperations extends FakePaymentLinkOperations {
  _InterruptedCreatedOperations(Completer<void> gate)
    : super(records: [fundedRecovery]) {
    createdRecoveryGate = gate;
  }
  bool _first = true;

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async {
    final result = await super.loadCreatedLinkRecoveries();
    if (_first) {
      _first = false;
      records.clear();
      throw GiftCardPreparationInterrupted(
        GiftCardPreparationPauseReason.lifecycle,
      );
    }
    return result;
  }
}

class _EntrySecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  @override
  void lock() => state = state.copyWith(isUnlocked: false);
}

class _SetupCardOperations extends FakePaymentLinkOperations {
  _SetupCardOperations(this.gate)
    : super(
        receivedRecords: [
          PaymentLinkReceivedRecord(
            network: incomingLink.network,
            address: incomingLink.address,
            amountZatoshi: incomingLink.amountZatoshi,
            createdAt: incomingLink.createdAt,
            artworkId: null,
            status: PaymentLinkReceivedStatus.readyToClaim,
            claimLink: incomingLink,
            destinationAccountUuid: null,
            claimTxids: null,
            updatedAt: incomingLink.createdAt,
            setupAccountUuid: 'account-1',
          ),
        ],
      );
  final Completer<void> gate;

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records, {
    bool allowResubmit = true,
  }) async {
    await gate.future;
    return [
      for (final record in records)
        record.copyWith(
          status: PaymentLinkReceivedStatus.received,
          claimLink: null,
          destinationAccountUuid: 'account-1',
          claimTxids: 'claim',
        ),
    ];
  }
}
