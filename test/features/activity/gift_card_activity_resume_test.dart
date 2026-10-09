import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/activity/activity_eta_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_lifecycle_revision.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';

void main() {
  testWidgets('Gift activity resumes after a paused lifecycle revision', (
    tester,
  ) async {
    final recoveryStore = PaymentLinkRecoveryStore(_MemoryRecoveryStorage());
    final receivedStore = PaymentLinkReceivedStore(_MemoryReceivedStorage());
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Accounts.new),
        paymentLinkRecoveryStoreProvider.overrideWithValue(recoveryStore),
        paymentLinkReceivedStoreProvider.overrideWithValue(receivedStore),
        paymentLinkOperationsProvider.overrideWithValue(
          _MemoryOperations(recoveryStore, receivedStore),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Retained Home and its derived activity consumers share the real index.
    // Keep the scope above the retained LayoutBuilder/TickerMode subtree, as
    // in the native app. This covers Riverpod #4709 and the native #4805
    // refresh-during-build boundary without replacing the real index/revision.
    final index = giftCardActivityIndexProvider('account-1');
    final middle = Provider<int>((ref) {
      return ref.watch(index).value?.createdTxids.length ?? 0;
    });
    final leaf = Provider<int>((ref) => ref.watch(middle));
    final consumer = Consumer(
      builder: (context, ref, child) {
        final activity = ref.watch(index).value;
        ref.watch(activityEtaClaimHistoryProvider);
        final count = ref.watch(middle);
        final mirroredCount = ref.watch(leaf);
        return Text(
          'cards:${activity?.createdTxids.length ?? 0}|$count|$mirroredCount'
          ' received:${activity?.redeemedTxids.length ?? 0}',
        );
      },
    );
    Widget app({required bool active}) => Directionality(
      textDirection: TextDirection.ltr,
      child: UncontrolledProviderScope(
        container: container,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              TickerMode(enabled: active, child: consumer),
        ),
      ),
    );

    await tester.pumpWidget(app(active: true));
    await tester.pumpAndSettle();
    expect(find.text('cards:0|0|0 received:0'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(app(active: false));
    final link = _link('created-card');
    await recoveryStore.saveDraft(
      claimFeeReserveZatoshi: BigInt.from(10000),
      link: link,
      sourceAccountUuid: 'account-1',
    );
    await recoveryStore.markFunded(
      address: link.address,
      fundingTxids: 'created-txid',
    );
    container.read(paymentLinkLifecycleRevisionProvider.notifier).bump();

    await tester.pumpWidget(app(active: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (tester.any(find.text('cards:1|1|1 received:0'))) break;
    }
    expect(
      find.text('cards:1|1|1 received:0'),
      findsOneWidget,
      reason:
          'Rendered: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}; index: ${container.read(index)}',
    );
    expect(container.read(index).requireValue.createdTxids, {'created-txid'});

    // An adjacent active revision must still refresh the independent receipt.
    final received = _link('received-card');
    await receivedStore.saveReady(received);
    await receivedStore.markReceiving(
      claimSubmittedAt: DateTime.utc(2026, 8, 28),
      address: received.address,
      destinationAccountUuid: 'account-1',
      claimTxids: 'received-txid',
    );
    container.read(paymentLinkLifecycleRevisionProvider.notifier).bump();
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (tester.any(find.text('cards:1|1|1 received:1'))) break;
    }
    expect(tester.takeException(), isNull);
    expect(find.text('cards:1|1|1 received:1'), findsOneWidget);
    expect(container.read(index).requireValue.redeemedTxids, {'received-txid'});

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account1', order: 0)],
    activeAccountUuid: 'account-1',
  );
}

VizorPaymentLink _link(String address) => VizorPaymentLink(
  network: 'main',
  address: address,
  amountZatoshi: BigInt.from(100000000),
  mnemonic:
      'abandon ability able about above absent absorb abstract absurd abuse access accident',
  birthdayHeight: 1,
  label: 'Gift Card',
  createdAt: DateTime.utc(2026, 8, 28),
);

class _MemoryRecoveryStorage implements PaymentLinkRecoveryStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class _MemoryOperations implements PaymentLinkOperations {
  _MemoryOperations(this.created, this.received);

  final PaymentLinkRecoveryStore created;
  final PaymentLinkReceivedStore received;

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() =>
      created.load();

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() =>
      received.load();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected Gift operation: ${invocation.memberName}',
  );
}

class _MemoryReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
