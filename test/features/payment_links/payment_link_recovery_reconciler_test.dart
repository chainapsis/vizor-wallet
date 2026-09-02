import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_lifecycle_revision.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_reconciler.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('retains a prepared Gift Card before its transaction expires', () async {
    final fixture = await _preparedFixture();
    final reconciler = PaymentLinkRecoveryReconciler(
      fixture.store,
      loadCurrentHeight: () async => BigInt.from(119),
      loadScannedHeight: () async => BigInt.from(119),
      loadTransactionsByAccount: (_) async => const {'source-account': []},
    );

    final record = (await reconciler.load()).single;

    expect(record.state, PaymentLinkRecoveryState.draft);
    expect(record.fundingTxids, _preparedTxid);
    expect(record.preparedExpiryHeight, 120);
    expect(await reconciler.countUnsharedFundedForAccount('source-account'), 1);
  });

  test(
    'removes a prepared Gift Card once its absent transaction expires',
    () async {
      final fixture = await _preparedFixture();
      final reconciler = PaymentLinkRecoveryReconciler(
        fixture.store,
        loadCurrentHeight: () async => BigInt.from(120),
        loadScannedHeight: () async => BigInt.from(120),
        loadTransactionsByAccount: (_) async => const {'source-account': []},
      );

      expect(await reconciler.load(), isEmpty);
      expect(
        await reconciler.countUnsharedFundedForAccount('source-account'),
        0,
      );
    },
  );

  test('promotes a recorded transaction even at its expiry height', () async {
    final fixture = await _preparedFixture();
    final reconciler = PaymentLinkRecoveryReconciler(
      fixture.store,
      loadCurrentHeight: () async => BigInt.from(120),
      loadScannedHeight: () async => BigInt.from(120),
      loadTransactionsByAccount: (_) async => {
        'source-account': [_transaction(txid: _preparedTxid)],
      },
    );

    final record = (await reconciler.load()).single;

    expect(record.state, PaymentLinkRecoveryState.funded);
    expect(record.fundingTxids, _preparedTxid);
    expect(record.preparedExpiryHeight, isNull);
  });

  test('retains prepared metadata when chain lookup is unavailable', () async {
    final fixture = await _preparedFixture();
    final reconciler = PaymentLinkRecoveryReconciler(
      fixture.store,
      loadCurrentHeight: () => throw StateError('offline'),
      loadScannedHeight: () async => BigInt.from(120),
      loadTransactionsByAccount: (_) async => const {'source-account': []},
    );

    final record = (await reconciler.load()).single;

    expect(record.state, PaymentLinkRecoveryState.draft);
    expect(record.fundingTxids, _preparedTxid);
    expect(record.preparedExpiryHeight, 120);
  });

  test(
    'retains an expired prepared Gift Card until wallet scan catches up',
    () async {
      final fixture = await _preparedFixture();
      final reconciler = PaymentLinkRecoveryReconciler(
        fixture.store,
        loadCurrentHeight: () async => BigInt.from(125),
        loadScannedHeight: () async => BigInt.from(119),
        loadTransactionsByAccount: (_) async => const {'source-account': []},
      );

      final record = (await reconciler.load()).single;

      expect(record.fundingTxids, _preparedTxid);
      expect(record.preparedExpiryHeight, 120);
    },
  );

  test('removes unshared funding when every transaction expires', () async {
    final fixture = await _fundedFixture();
    final reconciler = PaymentLinkRecoveryReconciler(
      fixture.store,
      loadCurrentHeight: () async => BigInt.zero,
      loadScannedHeight: () async => BigInt.zero,
      loadTransactionsByAccount: (_) async => {
        'source-account': [
          _transaction(txid: _preparedTxid, expiredUnmined: true),
        ],
      },
    );

    expect(await reconciler.load(), isEmpty);
    expect(await reconciler.countUnsharedFundedForAccount('source-account'), 0);
  });

  test(
    'retains unshared funding while any transaction may hold funds',
    () async {
      final fixture = await _fundedFixture(
        fundingTxids: '$_preparedTxid,$_secondTxid',
      );
      final reconciler = PaymentLinkRecoveryReconciler(
        fixture.store,
        loadCurrentHeight: () async => BigInt.zero,
        loadScannedHeight: () async => BigInt.zero,
        loadTransactionsByAccount: (_) async => {
          'source-account': [
            _transaction(txid: _preparedTxid, expiredUnmined: true),
            _transaction(txid: _secondTxid),
          ],
        },
      );

      expect(await reconciler.load(), hasLength(1));
      expect(
        await reconciler.countUnsharedFundedForAccount('source-account'),
        1,
      );
    },
  );

  test('never removes a shared funding recovery', () async {
    final fixture = await _fundedFixture();
    await fixture.store.markShared(address: _preparedAddress);
    final reconciler = PaymentLinkRecoveryReconciler(
      fixture.store,
      loadCurrentHeight: () async => BigInt.zero,
      loadScannedHeight: () async => BigInt.zero,
      loadTransactionsByAccount: (_) async => {
        'source-account': [
          _transaction(txid: _preparedTxid, expiredUnmined: true),
        ],
      },
    );

    final record = (await reconciler.load()).single;
    expect(record.state, PaymentLinkRecoveryState.shared);
  });

  test('refreshes the cached unshared count after lifecycle writes', () async {
    final reconciler = _CountingRecoveryReconciler();
    final container = ProviderContainer(
      overrides: [
        paymentLinkRecoveryReconcilerProvider.overrideWithValue(reconciler),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(
        paymentLinkUnsharedFundedCountProvider('source-account').future,
      ),
      1,
    );

    reconciler.count = 0;
    container.read(paymentLinkLifecycleRevisionProvider.notifier).bump();

    expect(
      await container.read(
        paymentLinkUnsharedFundedCountProvider('source-account').future,
      ),
      0,
    );
  });
}

const _preparedTxid =
    '9909fe99c789029bf118c88bd9ee33ed35965fd0f3154dd1a8ec6daa4974c7e3';
const _secondTxid =
    '7fe86d43f8a80849899092537e237931551574bd8e0938219d114ac0d06d1151';
const _preparedAddress = 'u1preparedgiftcardaddress';

Future<({PaymentLinkRecoveryStore store, _MemoryStorage storage})>
_preparedFixture() async {
  final storage = _MemoryStorage();
  final store = PaymentLinkRecoveryStore(storage);
  final link = VizorPaymentLink(
    network: 'main',
    address: _preparedAddress,
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 100,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 9, 1),
  );
  await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
  await store.markPrepared(
    address: link.address,
    fundingTxid: _preparedTxid,
    expiryHeight: 120,
  );
  return (store: store, storage: storage);
}

Future<({PaymentLinkRecoveryStore store, _MemoryStorage storage})>
_fundedFixture({String fundingTxids = _preparedTxid}) async {
  final storage = _MemoryStorage();
  final store = PaymentLinkRecoveryStore(storage);
  final link = VizorPaymentLink(
    network: 'main',
    address: _preparedAddress,
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 100,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 9, 1),
  );
  await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
  await store.markFunded(address: _preparedAddress, fundingTxids: fundingTxids);
  return (store: store, storage: storage);
}

rust_sync.TransactionInfo _transaction({
  required String txid,
  bool expiredUnmined = false,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: expiredUnmined ? BigInt.zero : BigInt.from(119),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: -110000,
    fee: BigInt.from(10000),
    blockTime: BigInt.zero,
    isTransparent: false,
    txKind: 'sent',
    displayAmount: BigInt.from(-110000),
    displayPool: 'shielded',
    createdTime: BigInt.zero,
  );
}

class _MemoryStorage implements PaymentLinkRecoveryStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async => value = nextValue;
}

class _CountingRecoveryReconciler extends PaymentLinkRecoveryReconciler {
  _CountingRecoveryReconciler()
    : super(
        PaymentLinkRecoveryStore(_MemoryStorage()),
        loadCurrentHeight: () async => BigInt.zero,
        loadScannedHeight: () async => BigInt.zero,
        loadTransactionsByAccount: (_) async => const {},
      );

  int count = 1;

  @override
  Future<int> countUnsharedFundedForAccount(String sourceAccountUuid) async {
    return count;
  }
}
