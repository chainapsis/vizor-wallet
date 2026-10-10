@Tags(['mobile'])
library;

import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../integration_test/support/mobile_regtest_flow.dart';

const _key = ValueKey('mobile_ironwood_keystone_batch_sign_button');
final _txid = 'ab' * 32;
final _pool = <String, Object?>{
  'size': 1,
  'txids': [_txid],
};

void main() {
  test(
    'initial receipt requires the original unmined stage and exact node txid',
    () {
      expect(
        mobileInitialPreparationReceiptTxid(_status(), _pool, 'original'),
        _txid,
      );
      expect(
        mobileInitialPreparationReceiptTxid(
          _status(scheduled: true),
          _pool,
          'original',
        ),
        isNull,
      );
      expect(
        mobileInitialPreparationReceiptTxid(_status(), {
          'size': 0,
          'txids': [],
        }, 'original'),
        isNull,
      );
      for (final pool in [
        {
          'size': 1,
          'txids': ['bad'],
        },
        {
          'size': 2,
          'txids': [_txid, _txid],
        },
        {
          'size': true,
          'txids': [_txid],
        },
      ]) {
        expect(
          () =>
              mobileInitialPreparationReceiptTxid(_status(), pool, 'original'),
          throwsStateError,
        );
      }
    },
  );

  test('receipt refuses another run and another stage policy', () {
    expect(
      () => mobileInitialPreparationReceiptTxid(_status(), _pool, 'foreign'),
      throwsStateError,
    );
    for (final status in [
      _status(stageIndex: 1),
      _status(round: 2),
      _status(fee: 75000),
      _status(target: 10),
      _status(minedHeight: 501),
    ]) {
      expect(
        () => mobileInitialPreparationReceiptTxid(status, _pool, 'original'),
        throwsStateError,
      );
    }
  });

  test(
    'inclusion requires exact txid and membership in actual generated blocks',
    () {
      final hashes = List<Object?>.generate(
        10,
        (index) => index.toRadixString(16).padLeft(64, '0'),
      );
      final proof = <String, Object?>{
        'txid': _txid,
        'confirmations': 10,
        'blockhash': hashes.first,
      };
      validateMobileInitialPreparationInclusion(proof, _txid, hashes, 10);
      for (final wrong in [
        {...proof, 'txid': 'cd' * 32},
        {...proof, 'confirmations': 9},
        {...proof, 'blockhash': 'ef' * 32},
      ]) {
        expect(
          () => validateMobileInitialPreparationInclusion(
            wrong,
            _txid,
            hashes,
            10,
          ),
          throwsStateError,
        );
      }
      expect(
        () => validateMobileInitialPreparationInclusion(
          proof,
          _txid,
          List.filled(10, hashes.first),
          10,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'expired shared deadline starts no node mutation or proof read',
    () async {
      var operations = 0;
      await expectLater(
        mineMobileInitialPreparationReceiptWithRpc(
          _txid,
          blocks: 50,
          deadline: DateTime.now().subtract(const Duration(seconds: 1)),
          generate: (_) async {
            operations++;
            return [];
          },
          readProof: (_) async {
            operations++;
            return {};
          },
        ),
        throwsA(isA<TestFailure>()),
      );
      expect(operations, 0);
    },
  );

  test(
    'route transition wait requires the original start and single incoming status page',
    () {
      const start = CupertinoPage<Object?>(
        key: ValueKey('/migration/private/start'),
        child: SizedBox(),
      );
      const status = CupertinoPage<Object?>(
        key: ValueKey('/migration/private/status'),
        child: SizedBox(),
      );
      expect(
        mobileInitialPreparationHasPendingStatusPage(start, [status], false),
        isTrue,
      );
      expect(
        mobileInitialPreparationHasPendingStatusPage(start, [status], true),
        isFalse,
      );
      expect(
        mobileInitialPreparationHasPendingStatusPage(start, [], false),
        isFalse,
      );
      expect(
        mobileInitialPreparationHasPendingStatusPage(start, [
          status,
          status,
        ], false),
        isFalse,
      );
      expect(
        mobileInitialPreparationHasPendingStatusPage(status, [status], false),
        isFalse,
      );
    },
  );

  testWidgets(
    'receipt observer cannot read the node while coordinator is busy',
    (tester) async {
      var nodeReads = 0;
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.runAsync(() async {
        await expectLater(
          waitForMobileInitialPreparationReceiptWithReaders(
            tester,
            () async => _status(),
            () async {
              nodeReads++;
              return _pool;
            },
            () => true,
            'original',
            deadline: DateTime.now().add(const Duration(milliseconds: 30)),
          ),
          throwsA(isA<TestFailure>()),
        );
      });
      expect(nodeReads, 0);
    },
  );

  testWidgets(
    'schedule observer returning a completed condition approves nothing',
    (tester) async {
      var approvals = 0;
      await tester.pumpWidget(
        _app(
          AppButton(
            key: _key,
            onPressed: () => approvals++,
            child: const Text('Prepare batch #1'),
          ),
        ),
      );
      await prepareMobilePrivateMigrationScheduleWithReader(
        tester,
        () async => _status(),
        (_) => true,
        description: 'existing completed condition',
      );
      expect(approvals, 0);
    },
  );

  testWidgets('proof approval uses the actual enabled software UI action', (
    tester,
  ) async {
    var approvals = 0;
    await tester.pumpWidget(
      _app(
        AppButton(
          key: _key,
          onPressed: () => approvals++,
          child: const Text('Prepare batch #1'),
        ),
      ),
    );
    await tester.runAsync(() => tapMobilePrivateMigrationProofBatch(tester));
    expect(approvals, 1);
  });

  for (final label in [
    'Sign batch #1',
    'Preparing batch #1...',
    'Prepare batch #0',
  ]) {
    testWidgets('approval does not tap $label', (tester) async {
      var approvals = 0;
      await tester.pumpWidget(
        _app(
          AppButton(
            key: _key,
            onPressed: () => approvals++,
            child: Text(label),
          ),
        ),
      );
      await _expectApprovalFailure(tester);
      expect(approvals, 0);
    });
  }

  testWidgets('proof approval refuses a disabled button', (tester) async {
    await tester.pumpWidget(
      _app(
        const AppButton(
          onPressed: null,
          key: _key,
          child: Text('Prepare batch #1'),
        ),
      ),
    );
    await _expectApprovalFailure(tester);
  });

  testWidgets('proof approval cannot run while app is backgrounded', (
    tester,
  ) async {
    var approvals = 0;
    await tester.pumpWidget(
      _app(
        AppButton(
          key: _key,
          onPressed: () => approvals++,
          child: const Text('Prepare batch #1'),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    try {
      await _expectApprovalFailure(tester);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    expect(approvals, 0);
  });
}

Future<void> _expectApprovalFailure(WidgetTester tester) =>
    tester.runAsync(() async {
      await expectLater(
        tapMobilePrivateMigrationProofBatch(
          tester,
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<TestFailure>()),
      );
    });

Widget _app(Widget child) => MaterialApp(
  home: AppTheme(
    data: AppThemeData.light,
    child: Scaffold(body: Center(child: child)),
  ),
);

rust_sync.MigrationStatus _status({
  bool scheduled = false,
  int stageIndex = 0,
  int round = 1,
  int fee = 80000,
  int target = 3,
  int? minedHeight,
}) => rust_sync.MigrationStatus(
  phase: 'waiting_denom_confirmations',
  activeRunId: 'original',
  targetValuesZatoshi: frb.Uint64List.fromList([1000000]),
  preparedNoteCount: 1,
  denominationConfirmationCount: 0,
  denominationConfirmationTarget: 3,
  denominationSplitCompletedCount: 0,
  denominationSplitTotalCount: 1,
  pendingTxCount: 0,
  broadcastedTxCount: 0,
  confirmedTxCount: 0,
  totalCount: 1,
  signedChildPcztCount: 1,
  pendingSplitStageCount: 1,
  canAbandon: false,
  signingBatchLimit: 20,
  scheduleMeanDelayBlocks: 1,
  scheduleMaxDelayBlocks: 1,
  proofReady: false,
  preparationTransactions: [
    rust_sync.MigrationPreparationTransactionStatus(
      stageIndex: stageIndex,
      approximateValueZatoshi: BigInt.from(1095000),
      round: round,
      feeZatoshi: BigInt.from(fee),
      plannedHeight: 500,
      projectedHeight: 500,
      projectedCompletionHeight: 503,
      outputs: const [],
      state: scheduled
          ? rust_sync.MigrationPreparationTransactionState.scheduled
          : rust_sync.MigrationPreparationTransactionState.broadcasted,
      minedHeight: minedHeight,
      confirmationCount: 0,
      confirmationTarget: target,
    ),
  ],
  scheduledBroadcasts: const [],
  parts: const [],
);
