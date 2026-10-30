@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../integration_test/support/mobile_regtest_flow.dart';

const _key = ValueKey('mobile_ironwood_keystone_batch_sign_button');

void main() {
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

rust_sync.MigrationStatus _status() => rust_sync.MigrationStatus(
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
      stageIndex: 0,
      approximateValueZatoshi: BigInt.from(1095000),
      round: 1,
      feeZatoshi: BigInt.from(80000),
      plannedHeight: 500,
      projectedHeight: 500,
      projectedCompletionHeight: 503,
      outputs: const [],
      state: rust_sync.MigrationPreparationTransactionState.broadcasted,
      confirmationCount: 0,
      confirmationTarget: 3,
    ),
  ],
  scheduledBroadcasts: const [],
  parts: const [],
);
