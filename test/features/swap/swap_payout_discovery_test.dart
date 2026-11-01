// Fakes the path provider platform, as other storage tests do.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_payout_discovery_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

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

/// Native calls a payout lookup and a wallet reset make, with each payout
/// read held until the test answers it.
class _Api extends RustLibApi {
  final reads = <String>[];
  final held = <Completer<List<rust_sync.TransactionInfo>>>[];

  @override
  Future<List<rust_sync.TransactionInfo>>
  crateApiSyncGetTransactionRowsForTxids({
    required String dbPath,
    required String network,
    required String accountUuid,
    required List<String> txidHexes,
  }) {
    reads.add(dbPath);
    held.add(Completer());
    return held.last.future;
  }

  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  void crateApiOneTimeIvkCancelSwapRecovery() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The default Mainnet endpoint, without failover probes.
class _Endpoint extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );
}

/// Serves the app support directory from [root].
class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

String? _awaiting({
  bool privateAddress = true,
  SwapDirection direction = SwapDirection.externalToZec,
  SwapIntentStatus status = SwapIntentStatus.complete,
}) => swapPayoutAwaitingDiscovery(
  privateAddress: privateAddress,
  direction: direction,
  status: status,
  walletTxid: _txid,
);

void main() {
  test('only a one-time payout NEAR sent awaits discovery', () {
    expect(_awaiting(), _txid);
    expect(_awaiting(privateAddress: false), isNull);
    expect(_awaiting(direction: SwapDirection.zecToExternal), isNull);
    expect(_awaiting(status: SwapIntentStatus.processing), isNull);
  });

  group('swapPayoutFoundProvider', () {
    Future<bool> found({
      List<rust_sync.TransactionInfo> recent = const [],
      rust_sync.TransactionInfo? history,
    }) async {
      final container = ProviderContainer(
        overrides: [
          syncProvider.overrideWith(() => _Sync(recent)),
          swapPayoutRowsLoaderProvider.overrideWithValue(
            (_, _) async => [?history],
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

    test('falls back to reading the payout', () async {
      expect(await found(history: _tx(_txid)), isTrue);
      expect(await found(), isFalse);
    });

    test('checks started together share one read per account', () async {
      final reads = <List<String>>[];
      final container = ProviderContainer(
        overrides: [
          syncProvider.overrideWith(() => _Sync(const [])),
          swapPayoutRowsLoaderProvider.overrideWithValue((
            account,
            txids,
          ) async {
            reads.add([account, ...txids]);
            return [_tx(_txid)];
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
      Future<bool> check(String account, String txid) => container.read(
        swapPayoutFoundProvider((
          accountUuid: account,
          walletTxid: txid,
        )).future,
      );
      final other = 'aa' * 32;
      final answers = await Future.wait([
        check('account', _txid),
        check('account', other),
        check('other-account', _txid),
      ]);
      expect(answers, [isTrue, isFalse, isTrue]);
      expect(reads, [
        ['account', _txid, other],
        ['other-account', _txid],
      ]);
    });
  });

  group('a payout lookup and a wallet reset', () {
    final api = _Api();
    setUpAll(() => RustLib.initMock(api: api));
    tearDownAll(RustLib.dispose);
    late Directory support;
    late PathProviderPlatform paths;
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({kWalletDbNameKey: 'w.db'});
      support = await Directory.systemTemp.createTemp('payout-lookup-');
      paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(support.path);
    });
    tearDown(() async {
      PathProviderPlatform.instance = paths;
      await support.delete(recursive: true);
    });

    test('the reset waits for a held lookup, and a later one names no new '
        'wallet', () async {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          rpcEndpointFailoverProvider.overrideWith(_Endpoint.new),
          syncProvider.overrideWith(() => _Sync(const [])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
      final lookup = container.read(swapPayoutLookupProvider);
      final held = lookup.has('account', _txid);
      await pumpEventQueue();
      expect(api.reads, ['${support.path}${Platform.pathSeparator}w.db']);

      final sync = container.read(syncProvider.notifier);
      var paused = false;
      final pausing = sync.pauseForWalletMutation().whenComplete(
        () => paused = true,
      );
      await pumpEventQueue();
      expect(paused, isFalse, reason: 'the reset waits for the lookup');
      api.held.single.complete(const []);
      expect(await held, isFalse);
      await pausing;

      // The reset clears secure storage. A lookup during it is refused, and
      // one after it finds no wallet: neither names a new one or reads.
      FlutterSecureStorage.setMockInitialValues({});
      await expectLater(lookup.has('account', _txid), throwsStateError);
      sync.endWalletMutationPause();
      await expectLater(lookup.has('account', _txid), throwsStateError);
      expect(api.reads, hasLength(1));
      expect(await AppSecureStore.instance.readPlain(kWalletDbNameKey), isNull);
    });
  });

  group('watchSwapFindingPayout', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      SwapPayoutRowsLoader loader,
    ) async {
      final container = ProviderContainer(
        overrides: [
          syncProvider.overrideWith(() => _Sync(const [])),
          swapPayoutRowsLoaderProvider.overrideWithValue(loader),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Consumer(
              builder: (_, ref, _) => Text(
                watchSwapFindingPayout(
                      ref,
                      accountUuid: 'account',
                      awaitingTxid: _txid,
                    )
                    ? 'finding'
                    : 'found',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a failed history read is not proof of receipt', (
      tester,
    ) async {
      await pump(tester, (_, _) async => throw StateError('wallet busy'));
      expect(find.text('finding'), findsOneWidget);
    });

    testWidgets('a pending history read keeps finding until it answers', (
      tester,
    ) async {
      final read = Completer<List<rust_sync.TransactionInfo>>();
      await pump(tester, (_, _) => read.future);
      expect(find.text('finding'), findsOneWidget);

      read.complete([_tx(_txid)]);
      await tester.pumpAndSettle();
      expect(find.text('found'), findsOneWidget);
    });

    testWidgets('a later failed read keeps the payout found', (tester) async {
      var fail = false;
      final container = await pump(tester, (_, _) async {
        if (fail) throw StateError('wallet busy');
        return [_tx(_txid)];
      });
      expect(find.text('found'), findsOneWidget);

      fail = true;
      container.invalidate(swapPayoutFoundProvider);
      await tester.pumpAndSettle();
      expect(find.text('found'), findsOneWidget);
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
    // The progress tab, not the completed summary.
    expect(finding.showTabs, isTrue);
    expect(finding.badgeKind, SwapStatusBadgeKind.liveQuote);
    expect(finding.steps.last.activeTitle, kSwapFindingPayoutLabel);
    expect(finding.steps.last.lastCheckedLabel, isNull);
    // Same steps as an ordinary swap, so the page doesn't grow.
    final found = swapActivityStatusPresentationForIntent(_state, intent);
    expect(finding.steps, hasLength(found.steps.length));
    expect(found.statusLabel, isNot(kSwapFindingPayoutLabel));
    expect(found.showTabs, isFalse);
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
    // The label alone, as in-progress rows carry no status icon.
    expect(row!.statusIconName, isNull);
    // Not settled yet: an in-progress title and no "Received ZEC" leg.
    expect(row!.title, 'Swapping...');
    expect(row!.childRows, isEmpty);
  });
}
