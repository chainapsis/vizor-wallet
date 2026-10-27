import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_deposit_transaction_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_payout_discovery_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

final _now = DateTime.utc(2026, 10, 27, 12);
const _state = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
);
const _txid =
    'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';

rust_sync.TransactionInfo _tx(String txidHex) => rust_sync.TransactionInfo(
  txidHex: txidHex,
  minedHeight: BigInt.one,
  expiredUnmined: false,
  accountBalanceDelta: 0,
  fee: BigInt.zero,
  feeState: rust_sync.TransactionFeeState.notApplicable,
  detailsComplete: true,
  provisional: false,
  amountIncludesFee: false,
  blockTime: BigInt.from(1800000000),
  isTransparent: false,
  txKind: 'received',
  displayAmount: BigInt.one,
  displayPool: 'shielded',
  createdTime: BigInt.from(1800000000),
);

class _Sync extends SyncNotifier {
  _Sync(this.recent);

  final List<rust_sync.TransactionInfo> recent;

  @override
  Future<SyncState> build() async => SyncState(recentTransactions: recent);
}

String? _awaiting({
  bool privateAddress = true,
  SwapDirection direction = SwapDirection.externalToZec,
  SwapIntentStatus status = SwapIntentStatus.complete,
  Duration ago = const Duration(hours: 1),
}) => swapPayoutAwaitingDiscovery(
  privateAddress: privateAddress,
  direction: direction,
  status: status,
  completedAt: _now.subtract(ago),
  walletTxid: _txid,
  now: _now,
);

void main() {
  test('only a recent one-time payout NEAR sent awaits discovery', () {
    expect(_awaiting(), _txid);
    expect(_awaiting(privateAddress: false), isNull);
    expect(_awaiting(direction: SwapDirection.zecToExternal), isNull);
    expect(_awaiting(status: SwapIntentStatus.processing), isNull);
    expect(_awaiting(ago: const Duration(days: 8)), isNull);
  });

  group('swapPayoutFoundProvider', () {
    Future<bool> found({
      List<rust_sync.TransactionInfo> recent = const [],
      rust_sync.TransactionInfo? history,
    }) async {
      final container = ProviderContainer(
        overrides: [
          syncProvider.overrideWith(() => _Sync(recent)),
          payDepositTransactionLoaderProvider.overrideWithValue(
            ({required accountUuid, required walletTxid}) async => history,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
      return container.read(
        swapPayoutFoundProvider((
          accountUuid: 'account',
          walletTxid: _txid,
        )).future,
      );
    }

    test('finds the payout among recent transactions', () async {
      expect(await found(recent: [_tx(_txid)]), isTrue);
    });

    test('falls back to the full history', () async {
      expect(await found(history: _tx(_txid)), isTrue);
      expect(await found(), isFalse);
    });
  });

  test('a payout still being found reads as in progress', () {
    final intent = SwapIntent(
      id: 'swap',
      pair: 'USDC -> ZEC',
      sellAmount: '100 USDC',
      receiveEstimate: '2 ZEC',
      provider: 'NEAR Intents',
      status: SwapIntentStatus.complete,
      nextAction: 'Next action',
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      privateAddress: true,
    );
    final finding = swapActivityStatusPresentationForIntent(
      _state,
      intent,
      findingPayout: true,
    );
    expect(finding.statusLabel, kSwapFindingPayoutLabel);
    expect(finding.title, 'Swap in progress...');
    expect(finding.steps.last.activeTitle, kSwapFindingPayoutLabel);
    expect(finding.steps.last.lastCheckedLabel, isNull);
    // Same steps as an ordinary swap, so the page doesn't grow.
    final found = swapActivityStatusPresentationForIntent(_state, intent);
    expect(finding.steps, hasLength(found.steps.length));
    expect(found.statusLabel, isNot(kSwapFindingPayoutLabel));
  });

  testWidgets('an Activity row says it is finding the payout', (tester) async {
    ActivityRowData? row;
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                findingPayout: true,
                item: SwapActivityRowItem(
                  intentId: 'swap',
                  providerLabel: 'NEAR Intents',
                  sellAmountText: '100 USDC',
                  receiveEstimateText: '2 ZEC',
                  status: SwapIntentStatus.complete,
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
                  activityTimestamp: _now,
                  privateAddress: true,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(row!.statusText, kSwapFindingPayoutLabel);
    expect(row!.statusIconName, AppIcons.loader);
    // Not settled yet: an in-progress title and no "Received ZEC" leg.
    expect(row!.title, 'Swapping...');
    expect(row!.childRows, isEmpty);
  });
}
