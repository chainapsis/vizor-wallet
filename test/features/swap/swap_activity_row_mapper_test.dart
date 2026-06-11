import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  testWidgets('maps swap records to shared activity feed rows', (tester) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: SwapActivityRowItem(
                  intentId: 'swap-1',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.processing,
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: DateTime.now().subtract(
                    const Duration(minutes: 2),
                  ),
                  lastStatusCheckedAt: DateTime.now().subtract(
                    const Duration(minutes: 1),
                  ),
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swapping...');
    expect(row!.subtitle, 'ZEC Zcash');
    expect(row!.subtitleIconName, isNull);
    expect(row!.amountText, '-0.0030 ZEC');
    expect(row!.statusText, '3/4 In progress');
    expect(row!.statusIconName, AppIcons.loader);
    expect(row!.leadingProgressValue, 0.75);
    final progressMatch = RegExp(
      r'^(\d+)/(\d+) In progress$',
    ).firstMatch(row!.statusText);
    expect(progressMatch, isNotNull);
    expect(
      row!.leadingProgressValue,
      int.parse(progressMatch!.group(1)!) / int.parse(progressMatch.group(2)!),
    );
    expect(row!.timestampText, isNot('--'));
    // Results-only sub rows: in-flight swaps carry their state on the parent
    // progress ring, not a child row.
    expect(row!.childRows, isEmpty);
  });

  testWidgets('maps receive-ZEC swaps as inbound activity rows', (
    tester,
  ) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: SwapActivityRowItem(
                  intentId: 'swap-2',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '0.21 USDC',
                  receiveEstimateText: '0.0030 ZEC',
                  status: SwapIntentStatus.awaitingExternalDeposit,
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: DateTime.utc(2026, 5, 7, 10, 30),
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swapping...');
    expect(row!.subtitle, 'USDC on Ethereum');
    expect(row!.amountText, '-0.21 USDC');
    expect(row!.statusText, '1/4 In progress');
    expect(row!.statusIconName, AppIcons.loader);
    expect(row!.leadingProgressValue, 0.25);
    expect(row!.timestampText, isNot('--'));
    expect(row!.childRows, isEmpty);
  });

  testWidgets('maps broadcast deposits to the confirmation step', (
    tester,
  ) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: const SwapActivityRowItem(
                  intentId: 'swap-confirming-deposit',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.awaitingDeposit,
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  depositTxHash: 'zec-deposit-txid',
                  activityTimestamp: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.statusText, '2/4 In progress');
    expect(row!.statusIconName, AppIcons.loader);
    expect(row!.leadingProgressValue, 0.5);
    expect(row!.childRows, isEmpty);
  });

  testWidgets('masks swap row amounts in privacy mode', (tester) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                privacyModeEnabled: true,
                item: const SwapActivityRowItem(
                  intentId: 'swap-private',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.complete,
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.amountText, isNot(contains('0.0030')));
    expect(row!.amountText, contains('***'));
    expect(row!.statusText, 'Completed');
    expect(row!.leadingProgressValue, isNull);
    expect(row!.childRows, hasLength(1));
    expect(row!.childRows.single.amountText, isNot(contains('0.21')));
    expect(row!.childRows.single.amountText, contains('***'));
  });

  testWidgets('maps failed swaps without refund semantics', (tester) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: const SwapActivityRowItem(
                  intentId: 'swap-failed',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '101.23 USDC',
                  receiveEstimateText: '4.12 ZEC',
                  status: SwapIntentStatus.failed,
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swap failed');
    expect(row!.amountText, '-101.23 USDC');
    expect(row!.amountIconName, isNull);
    expect(row!.amountSubtitle, isNull);
    expect(row!.statusText, 'Failed');
    expect(row!.statusIconName, AppIcons.skull);
    expect(row!.leadingProgressValue, isNull);
    expect(row!.childRows, isEmpty);
  });

  testWidgets('maps expired swaps as failed without refunding the amount', (
    tester,
  ) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: const SwapActivityRowItem(
                  intentId: 'swap-timeout',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '101.23 USDC',
                  receiveEstimateText: '4.12 ZEC',
                  status: SwapIntentStatus.expired,
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swap failed');
    expect(row!.amountText, '101.23 USDC');
    expect(row!.amountIconName, isNull);
    expect(row!.amountSubtitle, 'Timeout');
    expect(row!.amountSubtitleIconName, AppIcons.time);
    expect(row!.statusText, 'Failed');
    expect(row!.statusIconName, AppIcons.skull);
    expect(row!.leadingProgressValue, isNull);
    expect(row!.childRows, isEmpty);
  });

  test('maps persisted swap records to activity row items', () {
    final createdAt = DateTime.utc(2026, 5, 7, 10);
    final updatedAt = DateTime.utc(2026, 5, 7, 10, 30);
    final checkedAt = DateTime.utc(2026, 5, 7, 10, 31);
    final item = swapActivityRowItemsFromRecords([
      SwapIntentRecord(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.processing,
        nextAction: 'Swap is processing',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositTxHash: 'zec-deposit-txid',
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastStatusCheckedAt: checkedAt,
      ),
    ]).single;

    expect(item.intentId, 'swap-record');
    expect(item.providerLabel, 'NEAR Intents');
    expect(item.sellAmountText, '0.0030 ZEC');
    expect(item.receiveEstimateText, '0.21 USDC');
    expect(item.status, SwapIntentStatus.processing);
    expect(item.direction, SwapDirection.zecToExternal);
    expect(item.externalAsset, SwapAsset.usdc);
    expect(item.depositTxHash, 'zec-deposit-txid');
    expect(item.activityTimestamp, createdAt);
    expect(item.lastStatusCheckedAt, checkedAt);
  });

  testWidgets('keeps completed swap row timestamp separate from receive leg', (
    tester,
  ) async {
    ActivityRowData? row;
    final createdAt = DateTime.now().subtract(const Duration(hours: 2));
    final completedAt = DateTime.now().subtract(const Duration(minutes: 1));

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: SwapActivityRowItem(
                  intentId: 'swap-complete',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.complete,
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: createdAt,
                  completedAt: completedAt,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.timestampText, formatActivityTimestamp(createdAt));
    expect(row!.childRows, hasLength(1));
    expect(row!.childRows.single.title, 'Deposited USDC');
    expect(row!.childRows.single.amountText, '+0.21 USDC');
    expect(row!.childRows.single.leadingIconName, AppIcons.swapArrows);
    // The result sub row carries no secondary status/timestamp line.
    expect(row!.childRows.single.timestampText, isEmpty);
    expect(row!.childRows.single.statusText, isEmpty);
    expect(row!.childRows.single.onTap, isNull);
  });

  testWidgets(
    'completed external->ZEC swap absorbs the settled receive amount and tap',
    (tester) async {
      ActivityRowData? row;
      var legTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (context) {
                row = buildSwapActivityRow(
                  context: context,
                  receivedAmountText: '+12.13 ZEC',
                  onReceivedLegTap: () => legTaps += 1,
                  item: const SwapActivityRowItem(
                    intentId: 'swap-receive',
                    providerLabel: 'NEAR Intents',
                    sellAmountText: '101.23 USDC',
                    receiveEstimateText: '4.12 ZEC',
                    status: SwapIntentStatus.complete,
                    direction: SwapDirection.externalToZec,
                    externalAsset: SwapAsset.usdc,
                    activityTimestamp: null,
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(row!.title, 'Swapped');
      expect(row!.childRows, hasLength(1));
      final child = row!.childRows.single;
      expect(child.title, 'Received ZEC');
      // The absorbed on-chain receive carries the real settled amount, which
      // wins over the quote estimate ('+4.12 ZEC').
      expect(child.amountText, '+12.13 ZEC');
      expect(child.leadingIconName, AppIcons.swapArrows);
      expect(child.timestampText, isEmpty);
      expect(child.statusText, isEmpty);
      expect(child.onTap, isNotNull);

      child.onTap!();
      expect(legTaps, 1);
    },
  );

  testWidgets(
    'completed external->ZEC swap falls back to the receive estimate',
    (tester) async {
      ActivityRowData? row;

      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (context) {
                row = buildSwapActivityRow(
                  context: context,
                  // No absorbed payout yet, and no tap handler available.
                  item: const SwapActivityRowItem(
                    intentId: 'swap-receive-pending-tx',
                    providerLabel: 'NEAR Intents',
                    sellAmountText: '101.23 USDC',
                    receiveEstimateText: '4.12 ZEC',
                    status: SwapIntentStatus.complete,
                    direction: SwapDirection.externalToZec,
                    externalAsset: SwapAsset.usdc,
                    activityTimestamp: null,
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(row!.childRows, hasLength(1));
      final child = row!.childRows.single;
      expect(child.title, 'Received ZEC');
      expect(child.amountText, '+4.12 ZEC');
      // Without a matched payout there is nothing to navigate to.
      expect(child.onTap, isNull);
    },
  );

  testWidgets(
    'privacy mode masks the receive leg even with an absorbed amount',
    (tester) async {
      ActivityRowData? row;
      var legTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (context) {
                row = buildSwapActivityRow(
                  context: context,
                  privacyModeEnabled: true,
                  receivedAmountText: '+12.13 ZEC',
                  onReceivedLegTap: () => legTaps += 1,
                  item: const SwapActivityRowItem(
                    intentId: 'swap-receive-private',
                    providerLabel: 'NEAR Intents',
                    sellAmountText: '101.23 USDC',
                    receiveEstimateText: '4.12 ZEC',
                    status: SwapIntentStatus.complete,
                    direction: SwapDirection.externalToZec,
                    externalAsset: SwapAsset.usdc,
                    activityTimestamp: null,
                  ),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(row!.childRows, hasLength(1));
      final child = row!.childRows.single;
      expect(child.title, 'Received ZEC');
      expect(child.amountText, isNot(contains('12.13')));
      expect(child.amountText, isNot(contains('4.12')));
      expect(child.amountText, contains('***'));
      // The leg stays tappable so the user can still open the masked receipt.
      expect(child.onTap, isNotNull);
      child.onTap!();
      expect(legTaps, 1);
    },
  );

  testWidgets('refunded external->ZEC swap labels the external asset refund', (
    tester,
  ) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: const SwapActivityRowItem(
                  intentId: 'swap-refund-external',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '101.23 USDC',
                  receiveEstimateText: '4.12 ZEC',
                  status: SwapIntentStatus.refunded,
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swap failed');
    expect(row!.subtitle, 'USDC Refunded');
    expect(row!.amountIconName, AppIcons.arrowBack);
    expect(row!.statusText, 'Refunded');
    expect(row!.statusIconName, AppIcons.arrowBack);
    expect(row!.leadingProgressValue, isNull);
    expect(row!.childRows, isEmpty);
  });

  testWidgets('refunded ZEC->external swap labels the ZEC refund', (
    tester,
  ) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                item: const SwapActivityRowItem(
                  intentId: 'swap-refund-zec',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '0.9000 ZEC',
                  receiveEstimateText: '63.16 USDC',
                  status: SwapIntentStatus.refunded,
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swap failed');
    expect(row!.subtitle, 'ZEC Refunded');
    expect(row!.statusText, 'Refunded');
    expect(row!.childRows, isEmpty);
  });

  test('fromRecord byte-reverses the destination and deposit tx hashes', () {
    const destinationDisplayOrder =
        'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
    const destinationWalletOrder =
        '99887766554433221100ffeeddccbbaa99887766554433221100ffeeddccbbaa';
    const depositDisplayOrder =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final expectedDepositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    );

    final item = SwapActivityRowItem.fromRecord(
      SwapIntentRecord(
        id: 'swap-hashes',
        providerLabel: 'NEAR Intents',
        pairText: 'USDC -> ZEC',
        sellAmountText: '101.23 USDC',
        receiveEstimateText: '4.12 ZEC',
        status: SwapIntentStatus.complete,
        nextAction: 'Swap complete',
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        depositTxHash: depositDisplayOrder,
        destinationChainTxHash: destinationDisplayOrder,
      ),
    );

    expect(item.receiveWalletTxidHex, destinationWalletOrder);
    expect(item.depositWalletTxidHex, expectedDepositWalletOrder);
    expect(item.depositWalletTxidHex, isNotNull);
    // The raw display-order hash is preserved untouched on the record-derived
    // item for status-screen rendering.
    expect(item.depositTxHash, depositDisplayOrder);
  });
}
