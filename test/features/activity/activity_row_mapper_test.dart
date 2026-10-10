import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_amount_text.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fixtures/private_shielding_activity.dart';

void main() {
  Future<ActivityRowData> mapRow(
    WidgetTester tester,
    rust_sync.TransactionInfo transaction, {
    GiftCardActivityKind? giftCardKind,
    BigInt? giftCardAmountZatoshi,
    int? giftCardBatchCount,
    bool giftCardClaimInFlight = false,
    bool privateQueriesEnabled = false,
    String? giftCardDisplayPool,
    String? pendingLabel,
  }) async {
    late ActivityRowData row;
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Builder(
          builder: (context) {
            row = buildTransactionActivityRow(
              context: context,
              transaction: transaction,
              privateQueriesEnabled: privateQueriesEnabled,
              pendingLabel: pendingLabel,
              giftCardKind: giftCardKind,
              giftCardAmountZatoshi: giftCardAmountZatoshi,
              giftCardBatchCount: giftCardBatchCount,
              giftCardClaimInFlight: giftCardClaimInFlight,
              giftCardDisplayPool: giftCardDisplayPool,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return row;
  }

  testWidgets(
    'estimates and long waits use an hourglass; fallback copy has no icon',
    (tester) async {
      final tx = _transaction(txKind: 'sent', minedHeight: BigInt.zero);
      for (final label in [
        'Est. 1–3 min',
        'Est. 2–6 min',
        'Taking longer',
        'Checking status',
        'Waiting for connection',
      ]) {
        final row = await mapRow(tester, tx, pendingLabel: label);
        expect(row.subtitle, label);
        expect(
          row.subtitleIconName,
          label.startsWith('Est.') || label == 'Taking longer'
              ? AppIcons.time
              : isNull,
        );
        expect(row.leadingIconName, AppIcons.loader);
      }
    },
  );

  testWidgets('pending ETA replaces only the pool subtitle and its icon', (
    tester,
  ) async {
    for (final kind in ['sent', 'received', 'receiving']) {
      final pending = _transaction(txKind: kind, minedHeight: BigInt.zero);
      final row = await mapRow(tester, pending, pendingLabel: 'Est. 1–3 min');
      expect(row.subtitle, 'Est. 1–3 min');
      expect(row.subtitleIconName, AppIcons.time);
      expect(row.timestampText, (await mapRow(tester, pending)).timestampText);
      expect((await mapRow(tester, pending)).subtitle, 'Checking status');
      expect(
        (await mapRow(
          tester,
          _transaction(txKind: kind),
          pendingLabel: 'Est. 1–3 min',
        )).subtitle,
        'Shielded',
      );
      expect(
        (await mapRow(
          tester,
          _transaction(
            txKind: kind,
            minedHeight: BigInt.zero,
            expiredUnmined: true,
          ),
          pendingLabel: 'Est. 1–3 min',
        )).subtitle,
        'Shielded',
      );
    }
    for (final giftKind in GiftCardActivityKind.values) {
      final row = await mapRow(
        tester,
        _transaction(
          txKind: giftKind == GiftCardActivityKind.created
              ? 'sent'
              : 'receiving',
          minedHeight: BigInt.zero,
        ),
        giftCardKind: giftKind,
        pendingLabel: 'Est. 1–3 min',
      );
      expect(row.subtitle, 'Est. 1–3 min');
      expect(row.subtitleIconName, AppIcons.time);
    }
    expect(
      (await mapRow(
        tester,
        _transaction(txKind: 'migration', minedHeight: BigInt.zero),
        pendingLabel: 'Est. 1–3 min',
      )).subtitle,
      'Orchard → Ironwood',
    );
    expect(
      (await mapRow(
        tester,
        _transaction(txKind: 'shielded', minedHeight: BigInt.zero),
        pendingLabel: 'Est. 1–3 min',
      )).subtitle,
      isNull,
    );
  });

  testWidgets('ordinary sends and receipts label the exact output pool', (
    tester,
  ) async {
    for (final kind in ['sent', 'received']) {
      for (final (pool, label, icon) in [
        ('ironwood', 'Shielded', AppIcons.shieldKeyholeOutline),
        ('orchard', 'Orchard', AppIcons.shieldKeyholeOutline),
        ('sapling', 'Sapling', AppIcons.shieldKeyholeOutline),
        ('transparent', 'Transparent', AppIcons.transparentBalance),
        ('mixed', 'Mixed', null),
        ('unknown', null, null),
      ]) {
        final row = await mapRow(
          tester,
          _transaction(
            txKind: kind,
            activityPool: pool,
            minedHeight: kind == 'receiving' ? BigInt.zero : null,
          ),
        );
        expect(row.subtitle, label, reason: '$kind/$pool');
        expect(row.subtitleIconName, icon, reason: '$kind/$pool');
      }
    }
  });

  testWidgets('gift cards use exact activity and persisted destination pools', (
    tester,
  ) async {
    for (final kind in GiftCardActivityKind.values) {
      for (final (legacyPool, activityPool, label) in [
        ('ironwood', 'ironwood', 'Shielded'),
        ('shielded', 'orchard', 'Orchard'),
        ('shielded', 'sapling', 'Sapling'),
        ('shielded', 'mixed', 'Mixed'),
        ('transparent', 'transparent', 'Transparent'),
        ('shielded', null, 'Shielded'),
      ]) {
        final transaction = _transaction(
          txKind: kind == GiftCardActivityKind.created ? 'sent' : 'received',
          displayPool: legacyPool,
          activityPool: activityPool,
        );
        final row = await mapRow(tester, transaction, giftCardKind: kind);
        expect(row.subtitle, label);
        expect(
          row.subtitleIconName,
          label == 'Mixed'
              ? isNull
              : label == 'Transparent'
              ? AppIcons.transparentBalance
              : AppIcons.shieldKeyholeOutline,
        );
        for (final (pool, expected) in [
          ('ironwood', 'Shielded'),
          ('orchard', 'Orchard'),
          ('sapling', 'Sapling'),
        ]) {
          final overridden = await mapRow(
            tester,
            transaction,
            giftCardKind: kind,
            giftCardDisplayPool: pool,
          );
          expect(overridden.subtitle, expected);
          expect(overridden.subtitleIconName, AppIcons.shieldKeyholeOutline);
        }
        final pending = await mapRow(
          tester,
          _transaction(
            txKind: kind == GiftCardActivityKind.created ? 'sent' : 'received',
            minedHeight: BigInt.zero,
            activityPool: activityPool,
          ),
          giftCardKind: kind,
          giftCardDisplayPool: 'ironwood',
          pendingLabel: 'Est. 1–3 min',
        );
        expect(pending.subtitle, 'Est. 1–3 min');
        expect(pending.subtitleIconName, AppIcons.time);
      }
    }
  });

  testWidgets('missing activity pool retains legacy fallback labels', (
    tester,
  ) async {
    final ironwood = await mapRow(
      tester,
      _transaction(txKind: 'sent', displayPool: 'ironwood'),
    );
    expect(ironwood.subtitle, 'Shielded');
    final legacy = await mapRow(tester, _transaction(txKind: 'received'));
    expect(legacy.subtitle, 'Shielded');
  });

  testWidgets('private Enhance shape keeps an incomplete debit neutral', (
    tester,
  ) async {
    final transaction = loadPrivateTransparentActivity();
    final row = await mapRow(tester, transaction, privateQueriesEnabled: true);
    expect(row.title, kNetChangeText);
    expect(row.subtitle, isNull);
    expect(row.subtitleIconName, isNull);
    expect(row.amountText, '-0.00215 ZEC');
    expect(row.statusText, 'Completed');
    expect(row.amountSubtitle, kIncompleteDetailsText);
    expect(transaction.displayPool, 'unknown');
    expect(transaction.provisional, isTrue);
    expect(transaction.detailsComplete, isFalse);
    expect(transaction.feeState, rust_sync.TransactionFeeState.unknown);
    expect(transaction.fee, BigInt.zero);
  });

  testWidgets(
    'a mined gift claim stays in progress until card reconciliation completes',
    (tester) async {
      final tx = _transaction(txKind: 'received');
      final pending = await mapRow(
        tester,
        tx,
        giftCardKind: GiftCardActivityKind.redeemed,
        giftCardClaimInFlight: true,
      );
      expect(pending.title, _pendingTitle('Redeeming a card'));
      expect(pending.statusText, 'In progress');
      expect(pending.leadingIconName, AppIcons.loader);
      final completed = await mapRow(
        tester,
        tx,
        giftCardKind: GiftCardActivityKind.redeemed,
      );
      expect(completed.title, 'Redeemed a gift card');
      expect(completed.statusText, 'Completed');
      expect(completed.stableId, pending.stableId);
      final regular = await mapRow(tester, tx);
      expect(regular.title, 'Received');
    },
  );

  testWidgets('an expired visible leg does not fail an in-flight card', (
    tester,
  ) async {
    final tx = _transaction(
      txKind: 'receiving',
      minedHeight: BigInt.zero,
      expiredUnmined: true,
    );
    final row = await mapRow(
      tester,
      tx,
      giftCardKind: GiftCardActivityKind.redeemed,
      giftCardClaimInFlight: true,
    );
    expect(row.title, _pendingTitle('Redeeming a card'));
    expect(row.statusText, 'In progress');
    expect(row.amountSubtitle, isNot('Refunded'));
    final ordinary = await mapRow(tester, tx);
    expect(ordinary.statusText, 'Failed');
    final failedCard = await mapRow(
      tester,
      tx,
      giftCardKind: GiftCardActivityKind.redeemed,
    );
    expect(failedCard.statusText, 'Failed');
  });

  testWidgets('unconfirmed send renders as an in-flight loader row', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(txKind: 'sent', minedHeight: BigInt.zero),
    );
    expect(row.title, _pendingTitle('Sending'));
    expect(row.leadingIconName, AppIcons.loader);
    expect(row.statusText, 'In progress');
  });

  testWidgets('transaction rows expose a stable identity', (tester) async {
    final row = await mapRow(tester, _transaction(txKind: 'sent'));

    expect(row.stableId, 'tx:ab12cd34:sent');
  });

  testWidgets('receive rows keep identity when pending rows are mined', (
    tester,
  ) async {
    final pending = await mapRow(
      tester,
      _transaction(txKind: 'receiving', minedHeight: BigInt.zero),
    );
    final confirmed = await mapRow(tester, _transaction(txKind: 'received'));

    expect(pending.stableId, 'tx:ab12cd34:received');
    expect(confirmed.stableId, pending.stableId);
  });

  testWidgets('unconfirmed receive renders as an in-flight loader row', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(txKind: 'receiving', minedHeight: BigInt.zero),
    );
    expect(row.title, _pendingTitle('Receiving'));
    expect(row.leadingIconName, AppIcons.loader);
  });

  testWidgets('confirmed transactions keep their settled titles and icons', (
    tester,
  ) async {
    final sent = await mapRow(tester, _transaction(txKind: 'sent'));
    expect(sent.title, 'Sent');
    expect(sent.leadingIconName, AppIcons.plane);

    final received = await mapRow(tester, _transaction(txKind: 'received'));
    expect(received.title, 'Received');
    expect(received.leadingIconName, AppIcons.arrowDownCircle);
  });

  testWidgets('Gift Card transactions use their Figma titles and icon', (
    tester,
  ) async {
    final created = await mapRow(
      tester,
      _transaction(txKind: 'sent'),
      giftCardKind: GiftCardActivityKind.created,
      giftCardAmountZatoshi: BigInt.from(100000),
    );
    final redeemed = await mapRow(
      tester,
      _transaction(txKind: 'received'),
      giftCardKind: GiftCardActivityKind.redeemed,
      giftCardAmountZatoshi: BigInt.from(100000),
    );

    expect(created.title, 'Created a gift card');
    expect(created.leadingIconName, AppIcons.giftCard);
    expect(created.subtitle, 'Shielded');
    expect(created.amountText, '-0.001 ZEC');
    expect(redeemed.title, 'Redeemed a gift card');
    expect(redeemed.leadingIconName, AppIcons.giftCard);
    expect(redeemed.amountText, '+0.001 ZEC');
  });

  testWidgets('created batch has one row with its full card value', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(txKind: 'sent'),
      giftCardKind: GiftCardActivityKind.created,
      giftCardBatchCount: 20,
      giftCardAmountZatoshi: BigInt.from(200000000),
    );
    expect(row.title, 'Created 20 gift cards');
    expect(row.amountText, '-2 ZEC');
    expect(row.leadingIconName, AppIcons.giftCard);
    expect(
      giftCardActivityTitle(
        GiftCardActivityKind.created,
        isInFlight: true,
        isFailed: false,
        batchCount: 20,
      ),
      _pendingTitle('Creating 20 cards'),
    );
    expect(
      giftCardActivityTitle(
        GiftCardActivityKind.created,
        isInFlight: false,
        isFailed: true,
        batchCount: 20,
      ),
      'Gift card group failed',
    );
  });

  testWidgets('confirmed migration renders as an Ironwood activity row', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(txKind: 'migration', displayPool: 'ironwood'),
    );

    expect(row.title, 'Migrated to Ironwood');
    expect(row.subtitle, 'Orchard → Ironwood');
    expect(row.leadingIconName, AppIcons.migrationFast);
    expect(row.amountText, '120 ZEC');
  });

  testWidgets('unconfirmed migration renders as an in-flight activity row', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(
        txKind: 'migration',
        minedHeight: BigInt.zero,
        displayPool: 'ironwood',
      ),
    );

    expect(row.title, _pendingTitle('Migrating to Ironwood'));
    expect(row.leadingIconName, AppIcons.loader);
    expect(row.statusText, 'In progress');
  });

  testWidgets('expired send stays a failed row, not an in-flight one', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(
        txKind: 'sent',
        minedHeight: BigInt.zero,
        expiredUnmined: true,
      ),
    );
    expect(row.title, 'Send failed');
    expect(row.leadingIconName, isNot(AppIcons.loader));
  });

  testWidgets('zero-value sends and receipts show 0 ZEC', (tester) async {
    for (final kind in ['sent', 'received', 'receiving']) {
      final row = await mapRow(
        tester,
        _transaction(txKind: kind, displayAmount: BigInt.zero),
      );
      expect(
        row.amountText,
        activityAmountTextForFormFactor('0 ZEC'),
        reason: kind,
      );
    }

    final failedSend = await mapRow(
      tester,
      _transaction(
        txKind: 'sent',
        minedHeight: BigInt.zero,
        expiredUnmined: true,
        displayAmount: BigInt.zero,
      ),
    );
    expect(failedSend.title, 'Send failed');
    expect(failedSend.amountSubtitle, isNull);

    final unknown = await mapRow(
      tester,
      _transaction(txKind: 'unknown', displayAmount: BigInt.zero),
    );
    expect(unknown.amountText, activityAmountTextForFormFactor('--'));
  });

  testWidgets('transaction rows route the amount through the form-factor gate', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(txKind: 'sent', displayAmount: BigInt.from(1234567890000)),
    );

    // Lane-agnostic: desktop keeps the full amount, mobile compacts it. Both
    // are exactly what activityAmountTextForFormFactor yields for this raw text.
    expect(row.amountText, activityAmountTextForFormFactor('-12345.6789 ZEC'));
  });

  testWidgets('only uncertain activity summaries are marked incomplete', (
    tester,
  ) async {
    final complete = await mapRow(tester, _transaction(txKind: 'sent'));
    expect(complete.amountSubtitle, isNull);

    final provisional = await mapRow(
      tester,
      _transaction(
        txKind: 'sent',
        displayPool: 'unknown',
        detailsComplete: false,
        provisional: true,
      ),
      privateQueriesEnabled: true,
    );
    expect(provisional.amountSubtitle, kIncompleteDetailsText);

    final undiscoveredSelfReceipt = await mapRow(
      tester,
      _transaction(txKind: 'sent', provisional: true),
      privateQueriesEnabled: true,
    );
    expect(undiscoveredSelfReceipt.amountSubtitle, kIncompleteDetailsText);

    // A receive with every effect known can still lack a memo.
    final missingDetails = await mapRow(
      tester,
      _transaction(txKind: 'received', detailsComplete: false),
      privateQueriesEnabled: true,
    );
    expect(missingDetails.amountSubtitle, isNull);

    final publicIncomplete = await mapRow(
      tester,
      _transaction(txKind: 'sent', detailsComplete: false, provisional: true),
    );
    expect(publicIncomplete.amountSubtitle, isNull);
  });

  testWidgets('a recovered exact send keeps the public activity summary', (
    tester,
  ) async {
    final transaction = _transaction(
      txKind: 'sent',
      displayPool: 'transparent',
      detailsComplete: false,
      displayAmount: BigInt.from(10000),
      fee: BigInt.from(10000),
      accountBalanceDelta: -20000,
    );
    final privateRow = await mapRow(
      tester,
      transaction,
      privateQueriesEnabled: true,
    );
    final publicRow = await mapRow(tester, transaction);

    expect(privateRow.title, 'Sent');
    expect(privateRow.subtitle, 'Transparent');
    expect(
      privateRow.amountText,
      activityAmountTextForFormFactor('-0.0001 ZEC'),
    );
    expect(privateRow.amountSubtitle, isNull);
    expect(privateRow.timestampText, publicRow.timestampText);
    expect(privateRow.timestampText, isNotEmpty);
    expect(
      transactionDetailsIncomplete(transaction),
      isTrue,
      reason: 'the expanded receipt still lacks recipient details',
    );
  });

  testWidgets(
    'settled mixed recovery rows keep dates and incomplete receipts',
    (tester) async {
      for (final example in [
        ('sent', 250000, '-0.0025 ZEC'),
        ('received', 250000, '+0.0025 ZEC'),
        ('sent', 200000, '-0.002 ZEC'),
      ]) {
        final transaction = _transaction(
          txKind: example.$1,
          displayPool: 'transparent',
          activityPool: 'transparent',
          displayAmount: BigInt.from(example.$2),
          detailsComplete: false,
          provisional: false,
        );
        final row = await mapRow(
          tester,
          transaction,
          privateQueriesEnabled: true,
        );
        expect(row.amountText, activityAmountTextForFormFactor(example.$3));
        expect(row.amountSubtitle, isNull);
        expect(
          row.timestampText,
          (await mapRow(tester, transaction)).timestampText,
        );
        expect(row.timestampText, isNotEmpty);
        expect(transactionDetailsIncomplete(transaction), isTrue);
      }
    },
  );

  testWidgets('a settled movement with an unknown role or pool stays marked', (
    tester,
  ) async {
    for (final transaction in [
      _transaction(txKind: 'unknown', detailsComplete: false),
      _transaction(
        txKind: 'sent',
        displayPool: 'unknown',
        activityPool: 'transparent',
        detailsComplete: false,
        amountIncludesFee: true,
      ),
    ]) {
      final row = await mapRow(
        tester,
        transaction,
        privateQueriesEnabled: true,
      );
      expect(row.amountSubtitle, kIncompleteDetailsText);
    }
  });

  testWidgets('fee-sized net changes keep their incomplete sent row', (
    tester,
  ) async {
    rust_sync.TransactionInfo recovered({
      required int displayAmount,
      required int fee,
      bool amountIncludesFee = true,
    }) => _transaction(
      txKind: 'sent',
      displayPool: 'unknown',
      detailsComplete: false,
      provisional: true,
      displayAmount: BigInt.from(displayAmount),
      fee: BigInt.from(fee),
      amountIncludesFee: amountIncludesFee,
      accountBalanceDelta: -displayAmount,
    );

    // A provisional mixed-pool debit cannot establish a fee-only activity.
    final movement = await mapRow(
      tester,
      recovered(displayAmount: 20000, fee: 20000),
      privateQueriesEnabled: true,
    );
    expect(movement.title, kNetChangeText);
    expect(movement.amountText, activityAmountTextForFormFactor('-0.0002 ZEC'));
    expect(movement.amountSubtitle, kIncompleteDetailsText);

    // A net change keeps its sent row and its whole amount: a row has no fee
    // line to repeat the fee in.
    final netChange = await mapRow(
      tester,
      recovered(displayAmount: 70000000, fee: 10000),
    );
    expect(netChange.title, kNetChangeText);
    expect(netChange.amountText, activityAmountTextForFormFactor('-0.7 ZEC'));

    final payment = await mapRow(
      tester,
      recovered(displayAmount: 65000, fee: 65000, amountIncludesFee: false),
    );
    expect(payment.title, 'Sent', reason: 'a payment equal to its fee');
  });

  testWidgets('established self-transfer reads as its network fee', (
    tester,
  ) async {
    // A recovered self-transfer keeps its transparent pool in the entry, but
    // a fee shows no pool.
    final selfTransfer = await mapRow(
      tester,
      _transaction(
        txKind: 'sent',
        displayPool: 'transparent',
        accountBalanceDelta: -10000,
        detailsComplete: false,
        displayAmount: BigInt.from(10000),
        fee: BigInt.from(10000),
        amountIncludesFee: true,
      ),
    );
    expect(selfTransfer.title, kNetChangeText);
    expect(
      selfTransfer.amountText,
      activityAmountTextForFormFactor('-0.0001 ZEC'),
    );
    expect(selfTransfer.subtitle, isNull);
    expect(selfTransfer.subtitleIconName, isNull);
  });

  testWidgets(
    'a privately recovered shielding is a complete Shielded row, not a Sent',
    (tester) async {
      final cases = loadPrivateShieldingCases(
        txidHex: 'ab12cd34',
        minedHeight: BigInt.from(3498120),
        blockTime: BigInt.from(1790520240),
      );
      final expected = ['0.0018 ZEC', '0.004 ZEC'];
      expect(cases, hasLength(expected.length));
      for (final (index, shielding) in cases.indexed) {
        final row = await mapRow(
          tester,
          shielding.transaction,
          privateQueriesEnabled: true,
        );
        expect(row.title, 'Shielded');
        expect(row.leadingIconName, AppIcons.shieldKeyholeOutline);
        expect(
          row.amountText,
          activityAmountTextForFormFactor(expected[index]),
        );
        expect(row.amountSubtitle, isNull, reason: 'details are complete');
      }
    },
  );

  testWidgets('a failed entry keeps its refund note', (tester) async {
    final row = await mapRow(
      tester,
      _transaction(
        txKind: 'sent',
        minedHeight: BigInt.zero,
        expiredUnmined: true,
        provisional: true,
      ),
    );
    expect(row.amountSubtitle, 'Refunded');
  });
}

rust_sync.TransactionInfo _transaction({
  required String txKind,
  BigInt? minedHeight,
  bool expiredUnmined = false,
  BigInt? displayAmount,
  String displayPool = 'shielded',
  bool detailsComplete = true,
  bool provisional = false,
  String? activityPool,
  BigInt? fee,
  bool amountIncludesFee = false,
  int accountBalanceDelta = 0,
}) {
  return rust_sync.TransactionInfo(
    txidHex: 'ab12cd34',
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: accountBalanceDelta,
    fee: fee ?? BigInt.zero,
    feeState: fee == null
        ? rust_sync.TransactionFeeState.notApplicable
        : rust_sync.TransactionFeeState.known,
    detailsComplete: detailsComplete,
    provisional: provisional,
    amountIncludesFee: amountIncludesFee,
    blockTime: BigInt.from(1750000000),
    isTransparent: displayPool == 'transparent',
    txKind: txKind,
    displayAmount: displayAmount ?? BigInt.from(12000000000),
    displayPool: displayPool,
    activityPool: activityPool,
    createdTime: BigInt.from(1750000000),
  );
}

/// Mobile drops the space before a pending title's ellipsis.
String _pendingTitle(String verb) =>
    kAppFormFactor == AppFormFactor.mobile ? '$verb...' : '$verb ...';
