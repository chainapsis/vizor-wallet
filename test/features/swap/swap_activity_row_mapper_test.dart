import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';

void main() {
  testWidgets('maps swap records to shared activity table rows', (
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
                record: SwapIntentRecord(
                  id: 'swap-1',
                  providerLabel: 'NEAR Intents',
                  pairText: 'ZEC -> USDC',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.processing,
                  nextAction: 'Swap is processing',
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  createdAt: null,
                  updatedAt: DateTime.now().subtract(
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
    expect(row!.childRows, hasLength(1));
    expect(row!.childRows.single.title, 'Depositing USDC...');
    expect(row!.childRows.single.amountText, '+0.21 USDC');
    expect(row!.childRows.single.statusText, 'In progress');
    expect(row!.childRows.single.statusIconName, AppIcons.loader);
    expect(row!.childRows.single.timestampText, '1m ago');
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
                record: SwapIntentRecord(
                  id: 'swap-2',
                  providerLabel: 'NEAR Intents',
                  pairText: 'USDC -> ZEC',
                  sellAmountText: '0.21 USDC',
                  receiveEstimateText: '0.0030 ZEC',
                  status: SwapIntentStatus.awaitingExternalDeposit,
                  nextAction: 'Send USDC to the deposit address',
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
                  updatedAt: DateTime.utc(2026, 5, 7, 10, 30),
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
                record: const SwapIntentRecord(
                  id: 'swap-confirming-deposit',
                  providerLabel: 'NEAR Intents',
                  pairText: 'ZEC -> USDC',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.awaitingDeposit,
                  nextAction: 'Waiting for deposit confirmation',
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  depositTxHash: 'zec-deposit-txid',
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
                record: const SwapIntentRecord(
                  id: 'swap-private',
                  providerLabel: 'NEAR Intents',
                  pairText: 'ZEC -> USDC',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.complete,
                  nextAction: 'Complete',
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
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

  testWidgets('maps failed swaps without child rows and with refunded amount', (
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
                record: const SwapIntentRecord(
                  id: 'swap-failed',
                  providerLabel: 'NEAR Intents',
                  pairText: 'USDC -> ZEC',
                  sellAmountText: '101.23 USDC',
                  receiveEstimateText: '4.12 ZEC',
                  status: SwapIntentStatus.failed,
                  nextAction: 'Swap failed',
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
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
    expect(row!.amountIconName, AppIcons.arrowBack);
    expect(row!.amountSubtitle, 'Refunded');
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
                record: const SwapIntentRecord(
                  id: 'swap-timeout',
                  providerLabel: 'NEAR Intents',
                  pairText: 'USDC -> ZEC',
                  sellAmountText: '101.23 USDC',
                  receiveEstimateText: '4.12 ZEC',
                  status: SwapIntentStatus.expired,
                  nextAction: 'Start a fresh quote',
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
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
}
