// path_provider / plugin platform fakes back the broadcast flow's wallet DB
// path resolution and Sapling params status checks.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/zcash_explorer.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/donation/widgets/donation_views.dart';
import 'package:zcash_wallet/src/features/send/screens/send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_zec_market_data_cache.dart';

void main() {
  final rustApi = _RustApiFake();

  setUpAll(() {
    RustLib.initMock(api: rustApi);
  });

  tearDownAll(RustLib.dispose);

  setUp(() async {
    rustApi.reset();
    FlutterSecureStorage.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('send_status_test');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  testWidgets('software broadcast walks in-progress to sent successfully', (
    tester,
  ) async {
    rustApi.executeResult = _executeResult(status: 'broadcasted');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs()));
    await tester.pump();

    // In-progress frame before the broadcast future resolves (the loader
    // animation repeats, so bounded pumps only).
    expect(find.text('Send in progress...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Tx ID'), findsNothing);

    await _flushBroadcast(tester);

    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Tx ID'), findsOneWidget);
    expect(find.text(truncatedTxid(_txid)), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('15.12 ZEC'), findsOneWidget);
    expect(find.text(r'$1.06K'), findsOneWidget);
    expect(find.text('0.00012 ZEC'), findsOneWidget);
    expect(find.text(truncatedAddress(_address)), findsOneWidget);
    expect(rustApi.discardCalls, isEmpty);
    expect(rustApi.macosExecuteCalls, Platform.isMacOS ? 1 : 0);
    expect(rustApi.mnemonicExecuteCalls, Platform.isMacOS ? 0 : 1);
  });

  testWidgets('donation status keeps every sidebar section inactive', (
    tester,
  ) async {
    rustApi.executeResult = _executeResult(status: 'broadcasted');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(flowKind: SendFlowKind.donation)),
    );
    await tester.pump();

    expect(_sidebarItem(tester, 'Home').active, isFalse);
    expect(_sidebarItem(tester, 'Settings').active, isFalse);
    expect(find.text('Donation in progress...'), findsOneWidget);
    expect(find.text('Send in progress...'), findsNothing);
    expect(find.text('Donating to'), findsOneWidget);
    expect(find.text('Vizor Wallet'), findsOneWidget);
    expect(find.byType(DonationVizorBadge), findsOneWidget);
    expect(find.text(truncatedAddress(_address)), findsNothing);
    expect(find.text('Shielded'), findsNothing);
    expect(find.text('Show full address'), findsNothing);

    await _flushBroadcast(tester);

    expect(find.text('Thank you for supporting Vizor'), findsOneWidget);
    expect(_sidebarItem(tester, 'Home').active, isFalse);
    expect(_sidebarItem(tester, 'Settings').active, isFalse);
  });

  testWidgets('failed donation keeps donation-specific copy and recipient', (
    tester,
  ) async {
    rustApi.executeError = Exception('broadcast rejected');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(flowKind: SendFlowKind.donation)),
    );
    await tester.pump();
    await _flushBroadcast(tester);
    await tester.pumpAndSettle();

    expect(find.text('Donation failed'), findsOneWidget);
    expect(find.text('Send failed'), findsNothing);
    expect(find.text('Donating to'), findsOneWidget);
    expect(find.text('Vizor Wallet'), findsOneWidget);
    expect(find.byType(DonationVizorBadge), findsOneWidget);
    expect(find.text(truncatedAddress(_address)), findsNothing);
  });

  testWidgets('tx id row opens the explorer with the display-order txid', (
    tester,
  ) async {
    rustApi.executeResult = _executeResult(status: 'broadcasted');
    final launchedUrls = <String>[];
    _mockUrlLauncher(tester, launchedUrls);

    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs()));
    await tester.pump();
    await _flushBroadcast(tester);

    await tester.tap(find.text(truncatedTxid(_txid)));
    await tester.pump(const Duration(milliseconds: 100));

    final expected = zcashExplorerTransactionUri(
      networkName: defaultRpcEndpointConfig(
        kZcashDefaultNetworkName,
      ).networkName,
      txidHex: _txid,
      txidOrder: ZcashExplorerTxidOrder.display,
    ).toString();
    expect(launchedUrls, [expected]);
  });

  testWidgets('TEX recipient stays distinct on status screens', (tester) async {
    rustApi.executeResult = _executeResult(status: 'broadcasted');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(address: _texAddress, addressType: 'tex')),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(find.text(truncatedAddress(_texAddress)), findsOneWidget);
    expect(find.text('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('pending broadcast keeps in-progress visuals with the notice', (
    tester,
  ) async {
    rustApi.executeResult = _executeResult(
      status: 'created',
      message: 'broadcast rejected: mempool full',
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs()));
    await tester.pump();
    await _flushBroadcast(tester);

    expect(find.text('Send in progress...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    // Explorer affordance stays available like the legacy pending receipt.
    expect(find.text(truncatedTxid(_txid)), findsOneWidget);
    expect(find.textContaining("didn't reach the network"), findsOneWidget);
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('failed broadcast shows the failed layout with the reason', (
    tester,
  ) async {
    rustApi.executeError = Exception('broadcast rejected');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs()));
    await tester.pump();
    await _flushBroadcast(tester);
    await tester.pumpAndSettle();

    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.text('The network rejected this transaction. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('Tx ID'), findsNothing);
    expect(
      tester
          .widgetList<AppIcon>(find.byType(AppIcon))
          .where((icon) => icon.name == AppIcons.uturnUp),
      hasLength(1),
    );
  });

  testWidgets('blocked pop routes home instead of popping', (tester) async {
    rustApi.executeResult = _executeResult(status: 'broadcasted');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs()));
    await tester.pump();
    await _flushBroadcast(tester);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('home-route'), findsOneWidget);
  });

  testWidgets('Keystone broadcast extracts the PCZT pair and succeeds', (
    tester,
  ) async {
    rustApi.storeResult = const StoreAndBroadcastPcztsResult(
      txids: _txid,
      status: 'broadcasted',
      broadcastedCount: 1,
      totalCount: 1,
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(),
          pcztWithProofs: const [
            [3, 3, 3],
          ],
          pcztWithSignatures: const [
            [9, 9],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();

    // Keystone-while-sending keeps its dedicated submitting screen.
    expect(find.text('Scan your Keystone QR Code'), findsOneWidget);

    await _flushBroadcast(tester);

    expect(find.text('Sent successfully'), findsOneWidget);
    expect(rustApi.storeCalls, hasLength(1));
    expect(rustApi.storeCalls.single.$1, const [
      [3, 3, 3],
    ]);
    expect(rustApi.storeCalls.single.$2, const [
      [9, 9],
    ]);
    // needsSaplingParams=false -> no Sapling params threaded to extraction.
    expect(rustApi.storeCalls.single.$3, isNull);
    expect(rustApi.storeCalls.single.$4, BigInt.one);
    expect(rustApi.storeCalls.single.$5, 'test-send-flow');
    expect(rustApi.discardCalls, isEmpty);
    expect(rustApi.retainCalls, isEmpty);
  });

  testWidgets('TEX reports tx1 uncertainty without claiming nothing was sent', (
    tester,
  ) async {
    rustApi.storeResult = const StoreAndBroadcastPcztsResult(
      txids: '$_txid,second-txid',
      status: 'broadcast_unknown',
      broadcastedCount: 0,
      totalCount: 2,
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(address: _texAddress, addressType: 'tex'),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(address: _texAddress, addressType: 'tex'),
          pcztWithProofs: const [
            [1],
            [2],
          ],
          pcztWithSignatures: const [
            [3],
            [4],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(rustApi.storeCalls, hasLength(1));
    expect(rustApi.storeCalls.single.$1, const [
      [1],
      [2],
    ]);
    expect(rustApi.retainCalls, isEmpty);
    expect(find.textContaining('may have reached the network'), findsOneWidget);
  });

  testWidgets('TEX reports accepted tx1 with dependent tx2 pending', (
    tester,
  ) async {
    rustApi.storeResult = const StoreAndBroadcastPcztsResult(
      txids: '$_txid,second-txid',
      status: 'partial_broadcast',
      broadcastedCount: 1,
      totalCount: 2,
      message:
          'The first transaction was accepted, but the dependent transaction was rejected and was not stored.',
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(address: _texAddress, addressType: 'tex'),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(address: _texAddress, addressType: 'tex'),
          pcztWithProofs: const [
            [1],
            [2],
          ],
          pcztWithSignatures: const [
            [3],
            [4],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(
      find.textContaining('first transaction was accepted'),
      findsOneWidget,
    );
    expect(find.textContaining('was not stored'), findsOneWidget);
  });

  testWidgets('TEX broadcasts both validated steps in dependency order', (
    tester,
  ) async {
    rustApi.storeResult = const StoreAndBroadcastPcztsResult(
      txids: '$_txid,$_secondTxid',
      status: 'broadcasted',
      broadcastedCount: 2,
      totalCount: 2,
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(address: _texAddress, addressType: 'tex'),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(address: _texAddress, addressType: 'tex'),
          pcztWithProofs: const [
            [1],
            [2],
          ],
          pcztWithSignatures: const [
            [3],
            [4],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(rustApi.storeCalls.single.$1, const [
      [1],
      [2],
    ]);
    expect(rustApi.storeCalls.single.$2, const [
      [3],
      [4],
    ]);
    expect(find.text(truncatedTxid(_secondTxid)), findsOneWidget);
    expect(find.text(truncatedTxid(_txid)), findsNothing);
  });

  testWidgets('TEX validates both signatures before broadcasting step 1', (
    tester,
  ) async {
    rustApi.storeError = Exception('missing transparent signature');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(address: _texAddress, addressType: 'tex'),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(address: _texAddress, addressType: 'tex'),
          pcztWithProofs: const [
            [1],
            [2],
          ],
          pcztWithSignatures: const [
            [3],
            [4],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(rustApi.storeCalls, hasLength(1));
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets(
    'Keystone params rejection releases the retained input lock before broadcast',
    (tester) async {
      final args = _reviewArgs(needsSaplingParams: true);
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap(true)),
            appSecurityProvider.overrideWith(_FakeAppSecurityNotifier.new),
            syncProvider.overrideWith(_FakeSyncNotifier.new),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (_, ref, _) {
                widgetRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final outcome = await tester.runAsync(
        () => runSendBroadcast(
          ref: widgetRef,
          args: args,
          keystone: KeystoneBroadcastArgs(
            reviewArgs: args,
            pcztWithProofs: const [
              [3, 3, 3],
            ],
            pcztWithSignatures: const [
              [9, 9],
            ],
          ),
          confirmSaplingParamsDownload: () async => false,
        ),
      );

      expect(rustApi.storeCalls, isEmpty);
      expect(rustApi.discardCalls, [(BigInt.one, 'test-send-flow')]);
      expect(outcome?.phase, SendBroadcastPhase.failed);
      expect(outcome?.proposalConsumed, isTrue);
    },
  );

  testWidgets('proposal cleanup retries a transient Rust unlock failure', (
    tester,
  ) async {
    rustApi.discardFailuresRemaining = 1;

    await tester.runAsync(
      () => discardSendProposal(
        proposalId: BigInt.one,
        sendFlowId: 'test-send-flow',
        logContext: 'SendStatusTest',
      ),
    );

    expect(rustApi.discardCalls, [
      (BigInt.one, 'test-send-flow'),
      (BigInt.one, 'test-send-flow'),
    ]);
  });

  testWidgets('Keystone broadcast_unknown is stored for pending recovery', (
    tester,
  ) async {
    rustApi.storeResult = const StoreAndBroadcastPcztsResult(
      txids: _txid,
      status: 'broadcast_unknown',
      broadcastedCount: 0,
      totalCount: 1,
      message: 'broadcast outcome requires conservative locking',
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(),
          pcztWithProofs: const [
            [3, 3, 3],
          ],
          pcztWithSignatures: const [
            [9, 9],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(rustApi.discardCalls, isEmpty);
    expect(rustApi.retainCalls, isEmpty);
  });

  testWidgets('Keystone definite rejection surfaces as a send failure', (
    tester,
  ) async {
    rustApi.storeError = Exception(
      'Broadcast rejected: bad-txns-inputs-spent (code 18)',
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(),
          pcztWithProofs: const [
            [3, 3, 3],
          ],
          pcztWithSignatures: const [
            [9, 9],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(find.text('Send failed'), findsOneWidget);
    expect(
      find.text('The network rejected this transaction. Try again later.'),
      findsOneWidget,
    );
    expect(rustApi.discardCalls, isEmpty);
    expect(rustApi.retainCalls, isEmpty);
  });

  testWidgets('Keystone storage failure preserves the network warning', (
    tester,
  ) async {
    rustApi.storeResult = const StoreAndBroadcastPcztsResult(
      txids: _txid,
      status: 'broadcasted_storage_failed',
      broadcastedCount: 1,
      totalCount: 1,
      message:
          'The transaction is on the network, but local storage failed. Do not send again until sync reconciles it.',
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(),
          pcztWithProofs: const [
            [3, 3, 3],
          ],
          pcztWithSignatures: const [
            [9, 9],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(find.textContaining('is on the network'), findsOneWidget);
    expect(find.textContaining('Do not send again'), findsOneWidget);
  });

  testWidgets('expired Keystone signing is terminal and does not promise retry', (
    tester,
  ) async {
    rustApi.storeResult = const StoreAndBroadcastPcztsResult(
      txids: _txid,
      status: 'expired',
      broadcastedCount: 0,
      totalCount: 1,
      message: 'Hardware signing request expired before broadcast',
    );

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(),
        keystone: KeystoneBroadcastArgs(
          reviewArgs: _reviewArgs(),
          pcztWithProofs: const [
            [3, 3, 3],
          ],
          pcztWithSignatures: const [
            [9, 9],
          ],
        ),
        isHardware: true,
      ),
    );
    await tester.pump();
    await _flushBroadcast(tester);

    expect(find.text('Send failed'), findsOneWidget);
    expect(
      find.text(
        'Keystone signing request expired before broadcast. Return to your wallet, wait for sync, then review the payment and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('will retry automatically'), findsNothing);
    expect(find.text('Tx ID'), findsNothing);
    expect(rustApi.discardCalls, isEmpty);
  });
}

const _txid =
    'd6e03b5276de779d532791a82a28da7fb6b60524bf5996f4d7629cd794682c01';

const _secondTxid =
    '1c826497dc926d4f6f99bf42506b6f7bda82a282a89127539d77ed6725b30e6d';

const _address =
    'u1tvg4akwn3gk64h6dfe0000000000000000005j3eds7qfhzek6scgcn8fh5';

const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

/// Lets the broadcast chain's real-IO futures (wallet DB path, Sapling
/// params status) resolve — they cannot complete inside the FakeAsync test
/// zone on their own. Bounded pumps afterwards because the in-progress
/// loader animation repeats forever (pumpAndSettle would hang).
Future<void> _flushBroadcast(WidgetTester tester) async {
  // Several rounds because the chain interleaves real-IO awaits with
  // fake-zone microtasks that only run during pump.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void _mockUrlLauncher(WidgetTester tester, List<String> launchedUrls) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    if (call.method == 'launch') {
      launchedUrls.add(
        (call.arguments as Map<Object?, Object?>)['url']! as String,
      );
    }
    return true;
  });
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
}

ExecuteProposalResult _executeResult({
  required String status,
  String? message,
}) {
  return ExecuteProposalResult(
    txids: _txid,
    status: status,
    broadcastedCount: status == 'broadcasted' ? 1 : 0,
    totalCount: 1,
    message: message,
  );
}

Widget _harness(
  SendReviewArgs args, {
  KeystoneBroadcastArgs? keystone,
  bool isHardware = false,
}) {
  final router = GoRouter(
    initialLocation: '/send/status',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send-route')),
      GoRoute(
        path: '/send/status',
        builder: (_, _) => SendStatusScreen(args: args, keystone: keystone),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(isHardware)),
      zecMarketDataSourceProvider.overrideWithValue(
        const _FakeMarketDataSource(),
      ),
      zecMarketDataCacheProvider.overrideWithValue(FakeZecMarketDataCache()),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(),
      ),
      accountProvider.overrideWith(_FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeAppSecurityNotifier.new),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AppBootstrapState _bootstrap(bool isHardware) {
  return AppBootstrapState(
    initialLocation: '/send/status',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: 'test-account',
          name: 'Account 1',
          order: 0,
          isHardware: isHardware,
        ),
      ],
      activeAccountUuid: 'test-account',
      activeAddress: 'u1activeaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

SendReviewArgs _reviewArgs({
  String address = _address,
  String addressType = 'unified',
  String? memo,
  bool needsSaplingParams = false,
  SendFlowKind flowKind = SendFlowKind.send,
}) {
  return SendReviewArgs(
    proposalId: BigInt.one,
    sendFlowId: 'test-send-flow',
    proposalAccountUuid: 'test-account',
    address: address,
    addressType: addressType,
    amountZatoshi: BigInt.from(1512000000),
    feeZatoshi: BigInt.from(12000),
    needsSaplingParams: needsSaplingParams,
    memo: memo,
    flowKind: flowKind,
  );
}

AppSidebarItem _sidebarItem(WidgetTester tester, String label) {
  return tester.widget<AppSidebarItem>(
    find.ancestor(of: find.text(label), matching: find.byType(AppSidebarItem)),
  );
}

class _FakeMarketDataSource implements ZecMarketDataSource {
  const _FakeMarketDataSource();

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    return const ZecMarketData(usdPrice: 70);
  }
}

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FakeAddressBookRepository implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

class _FakeAppSecurityNotifier extends AppSecurityNotifier {
  @override
  String requireSessionPasswordForNativeSecretUse() => 'test-password';
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  Future<Uint8List?> getMnemonicBytesForAccount(String uuid) async {
    if (uuid != 'test-account') return null;
    // The production send path zeroizes this buffer after handing it to Rust,
    // so each request needs a fresh mutable list.
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'test-account',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(500000000),
    totalBalance: BigInt.from(500000000),
  );

  @override
  Future<void> refreshAfterSend() async {}

  @override
  Future<void> restartSync() async {}
}

class _RustApiFake implements RustLibApi {
  final discardCalls = <(BigInt, String)>[];
  final retainCalls = <(BigInt, String)>[];
  final storeCalls =
      <(List<List<int>>, List<List<int>>, String?, BigInt, String)>[];
  Object? storeError;
  ExecuteProposalResult? executeResult;
  Object? executeError;
  StoreAndBroadcastPcztsResult? storeResult;
  int discardFailuresRemaining = 0;
  int macosExecuteCalls = 0;
  int mnemonicExecuteCalls = 0;
  String unifiedAddress = 'u1ownaccountaddressnotmatchingrecipient';
  String transparentAddress = 't1ownaccountaddressnotmatchingrecipient';

  void reset() {
    discardCalls.clear();
    retainCalls.clear();
    storeCalls.clear();
    storeError = null;
    executeResult = null;
    executeError = null;
    storeResult = null;
    discardFailuresRemaining = 0;
    macosExecuteCalls = 0;
    mnemonicExecuteCalls = 0;
    unifiedAddress = 'u1ownaccountaddressnotmatchingrecipient';
    transparentAddress = 't1ownaccountaddressnotmatchingrecipient';
  }

  Future<ExecuteProposalResult> _execute() async {
    final error = executeError;
    if (error != null) throw error;
    return executeResult!;
  }

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discardCalls.add((proposalId, sendFlowId));
    if (discardFailuresRemaining > 0) {
      discardFailuresRemaining--;
      throw Exception('transient wallet DB unlock failure');
    }
  }

  @override
  Future<void> crateApiSyncRetainProposalLockUntilExpiry({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    retainCalls.add((proposalId, sendFlowId));
  }

  @override
  Future<ExecuteProposalResult> crateApiSyncExecuteProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required BigInt proposalId,
    required String sendFlowId,
    required List<int> mnemonicBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    mnemonicExecuteCalls++;
    return _execute();
  }

  @override
  Future<ExecuteProposalResult>
  crateApiSyncExecuteProposalWithMacosStoredMnemonic({
    required String dbPath,
    required String lightwalletdUrl,
    required BigInt proposalId,
    required String sendFlowId,
    required String password,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    macosExecuteCalls++;
    return _execute();
  }

  @override
  Future<StoreAndBroadcastPcztsResult>
  crateApiSyncStoreAndBroadcastPcztsWithKeystoneSignaturesForProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
    required List<Uint8List> pcztWithProofs,
    required List<Uint8List> signatureBlobs,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    storeCalls.add((
      pcztWithProofs.map((bytes) => bytes.toList()).toList(),
      signatureBlobs.map((bytes) => bytes.toList()).toList(),
      spendParamsPath,
      proposalId,
      sendFlowId,
    ));
    if (storeError case final error?) throw error;
    return storeResult!;
  }

  @override
  Future<StoreAndBroadcastPcztsResult>
  crateApiSyncStoreAndBroadcastSignedPcztsForProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
    required List<Uint8List> pcztWithProofs,
    required List<Uint8List> pcztWithSignatures,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    storeCalls.add((
      pcztWithProofs.map((bytes) => bytes.toList()).toList(),
      pcztWithSignatures.map((bytes) => bytes.toList()).toList(),
      spendParamsPath,
      proposalId,
      sendFlowId,
    ));
    if (storeError case final error?) throw error;
    return storeResult!;
  }

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    return unifiedAddress;
  }

  @override
  Future<String> crateApiWalletGetTransparentReceiveAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    return transparentAddress;
  }

  @override
  Future<List<String>> crateApiWalletGetRecentTransparentReceiveAddresses({
    required String dbPath,
    required String network,
    String? accountUuid,
    required int limit,
  }) async {
    return [transparentAddress];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
