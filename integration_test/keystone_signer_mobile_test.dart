@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/keystone.dart' as keystone;
import 'package:zcash_wallet/src/rust/api/sync.dart' as sync;
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as voting;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/delegate.dart'
    as delegate;

import '../test/support/wallet_path_read_blocker.dart';
import 'support/accepting_lightwalletd.dart';

const _uuid = String.fromEnvironment('KEYSTONE_ACCOUNT_UUID');
const _tex = String.fromEnvironment('KEYSTONE_TEX_ADDRESS');

const _zebraUrl = String.fromEnvironment('KEYSTONE_ZEBRA_LIGHTWALLETD');
const _network = _zebraUrl == '' ? 'main' : 'regtest';
Directory? _zebraWallet;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  tearDownAll(() async {
    await _zebraWallet?.delete(recursive: true);
  });

  testWidgets(
    'sends to TEX after two Keystone firmware signatures',
    (tester) => _runSend(tester, tex: true),
    timeout: const Timeout(Duration(minutes: 6)),
  );
  testWidgets(
    'broadcasts a send after one Keystone batch signature',
    (tester) => _runSend(tester, tex: false),
    timeout: const Timeout(Duration(minutes: 6)),
  );
  if (_zebraUrl.isEmpty) {
    testWidgets(
      'signs two delegation bundles in one Keystone voting batch',
      _runVoting,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

Future<void> _runSend(WidgetTester tester, {required bool tex}) async {
  const encodedDb = String.fromEnvironment('KEYSTONE_WALLET_DB');
  expect(
    encodedDb,
    isNotEmpty,
    reason: 'Run scripts/e2e/flutter-mobile-keystone.sh',
  );
  final directory = _zebraUrl.isEmpty
      ? await Directory.systemTemp.createTemp('vizor-keystone-send.')
      : (_zebraWallet ??= await Directory.systemTemp.createTemp(
          'vizor-keystone-zebra.',
        ));
  if (_zebraUrl.isEmpty) addTearDown(() => directory.delete(recursive: true));
  WalletPathReadBlocker().complete(directory.path);
  FlutterSecureStorage.setMockInitialValues({kWalletDbNameKey: 'wallet.db'});
  addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
  final dbPath = '${directory.path}/wallet.db';
  final db = File(dbPath);
  if (!await db.exists()) {
    await db.writeAsBytes(gzip.decode(base64Decode(encodedDb)), flush: true);
  }
  AcceptingLightwalletd? server;
  if (_zebraUrl.isEmpty) {
    final status = await sync.getSyncStatus(dbPath: dbPath, network: _network);
    server = AcceptingLightwalletd(chainHeight: status.chainTipHeight.toInt());
    await server.start();
    addTearDown(server.stop);
  }

  final address = tex
      ? _tex
      : const String.fromEnvironment('KEYSTONE_SEND_ADDRESS');
  final flowId = tex ? 'keystone-mobile-tex' : 'keystone-mobile-send';
  final approvals = tex ? 2 : 1;
  final expectedTxids = <String>[];
  final amount = BigInt.from(500000);
  final proposal = await sync.proposeSend(
    dbPath: dbPath,
    network: _network,
    accountUuid: _uuid,
    sendFlowId: flowId,
    toAddress: address,
    amountZatoshi: amount,
  );
  final args = SendReviewArgs(
    proposalId: proposal.proposalId,
    proposalAccountUuid: _uuid,
    sendFlowId: flowId,
    address: address,
    addressType: tex ? 'tex' : 'transparent',
    amountZatoshi: amount,
    feeZatoshi: proposal.feeZatoshi,
    needsSaplingParams: proposal.needsSaplingParams,
  );

  ValueChanged<ScanResult>? deliverScan;
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              child: const Text('Sign'),
              onPressed: () async {
                final result = await context.push<KeystoneBroadcastArgs>(
                  '/send/keystone-sign',
                );
                if (context.mounted && result != null) {
                  if (_zebraUrl.isNotEmpty) {
                    expectedTxids.addAll(
                      result.pcztWithProofs.map(
                        (pczt) => sync.getPcztTxid(pcztBytes: pczt),
                      ),
                    );
                    debugPrint(
                      'Keystone signed $flowId txids=${expectedTxids.join(",")}',
                    );
                  }
                  context.go('/send/status', extra: result);
                }
              },
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/send/keystone-sign',
        builder: (_, _) => MobileKeystoneSignScreen(
          args: args,
          scannerBuilder: (_, onComplete, _, _) {
            deliverScan = onComplete;
            return const SizedBox.expand();
          },
        ),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) => MobileSendStatusScreen(
          args: args,
          keystone: state.extra! as KeystoneBroadcastArgs,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/home',
            initialAccountState: const AccountState(
              accounts: [
                AccountInfo(
                  uuid: _uuid,
                  name: 'Keystone fixture',
                  order: 0,
                  isHardware: true,
                  hardwareSignerKind: HardwareSignerKind.keystone,
                ),
              ],
              activeAccountUuid: _uuid,
            ),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: _network,
            rpcEndpointConfig: RpcEndpointConfig(
              networkName: _network,
              lightwalletdUrl: server?.url ?? _zebraUrl,
              presetId: kCustomRpcEndpointPresetId,
            ),
            themeMode: ThemeMode.light,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        networkPrivacyProvider.overrideWith(_DirectNetwork.new),
        syncProvider.overrideWith(_FixtureSync.new),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.tap(find.text('Sign'));

  for (var round = 0; round < approvals; round++) {
    final qr = find.descendant(
      of: find.byKey(ValueKey('mobile_keystone_sign_round_$round')),
      matching: find.byType(KeystonePcztQrStage),
    );
    await _waitFor(tester, qr);
    final frames = tester.widget<KeystonePcztQrStage>(qr).urParts;
    final result = await _sign(frames, batch: !tex);
    deliverScan = null;
    await _tapWhenReady(
      tester,
      find.byKey(const ValueKey('mobile_keystone_sign_get_signature')),
    );
    await _waitFor(
      tester,
      find.byKey(const ValueKey('mobile_keystone_sign_scanner_card')),
    );
    if (server != null) {
      expect(
        server.sendTransactionCount,
        0,
        reason: 'All required approvals must precede submission',
      );
    }
    deliverScan!(result);
  }
  await _waitFor(
    tester,
    find.byKey(const ValueKey('mobile_send_status_succeeded')),
  );
  if (server != null) {
    expect(server.sendTransactionCount, approvals);
  } else {
    expect(expectedTxids.toSet(), hasLength(approvals));
    await _mineAndVerify(expectedTxids);
  }
}

Future<void> _mineAndVerify(List<String> txids) async {
  const rpc = String.fromEnvironment('KEYSTONE_ZEBRA_RPC');
  final uri = Uri.parse(rpc);
  expect(uri.host, '127.0.0.1');
  final client = HttpClient();
  try {
    Future<dynamic> call(String method, List<Object> params) async {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': method,
          'params': params,
        }),
      );
      final res = await req.close();
      final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map;
      expect(body['error'], isNull, reason: method);
      return body['result'];
    }

    final found = <String>{};
    // Zebra may mine the dependent TEX child in the following block.
    for (var i = 0; i < 5 && found.length < txids.length; i++) {
      final hashes = await call('generate', [1]) as List;
      final block = await call('getblock', [hashes.single as String, 1]) as Map;
      final mined = (block['tx'] as List).cast<String>().where(txids.contains);
      for (final id in mined) {
        found.add(id);
        debugPrint(
          'Keystone Zebra txid=$id height=${block['height']} block=${block['hash']}',
        );
      }
    }
    expect(found, unorderedEquals(txids));
    if (txids.length == 2) {
      final child = await call('getrawtransaction', [txids.last, 1]) as Map;
      expect(
        (child['vin'] as List).map((input) => input['txid']),
        contains(txids.first),
      );
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _runVoting(WidgetTester tester) async {
  final fixture = await _request('/voting-fixture');
  final directory = await Directory.systemTemp.createTemp(
    'vizor-keystone-voting.',
  );
  addTearDown(() => directory.delete(recursive: true));
  final dbPath = '${directory.path}/wallet.db';
  await File('$dbPath.voting').writeAsBytes(
    gzip.decode(base64Decode(fixture['db'] as String)),
    flush: true,
  );
  final bundles = (fixture['bundles'] as List).cast<Map<String, dynamic>>();
  final requests = [
    for (final b in bundles)
      delegate.KeystoneSigningRequest(
        bundleIndex: b['index'],
        bundleCount: bundles.length,
        actionIndex: b['action'],
        pcztBytes: base64Decode(b['full_pczt']),
        redactedPcztBytes: base64Decode(b['pczt']),
        pcztSighash: base64Decode(b['sighash']),
        rk: base64Decode(b['rk']),
        eligibleWeightZatoshi: BigInt.from(b['eligible']),
        delegatedWeightZatoshi: BigInt.from(b['delegated']),
        displayMemo: b['memo'],
      ),
  ];
  final roundId = fixture['round_id'] as String;
  final round = await VotingKeystoneSigningRound.prepare(
    VotingSessionKey(roundId: roundId, accountUuid: _uuid),
    requests,
  );
  expect(round.requests.map((r) => r.bundleIndex), [0, 1]);

  ValueChanged<ScanResult>? deliverScan;
  final scanned = Completer<List<int>>();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        home: AppTheme(
          data: AppThemeData.light,
          child: MobileKeystoneVotingSigningScreen(
            presentation: VotingKeystoneStatusPresentation(
              bundleIndex: round.requests.first.bundleIndex,
              urParts: round.batchRequest.urParts,
              batchMessageCount: round.requests.length,
              batchTotalCount: requests.length,
              batchMemos: [
                for (final r in round.requests)
                  VotingKeystoneBatchMemo(
                    bundleIndex: r.bundleIndex,
                    bundleCount: r.bundleCount,
                    displayMemo: r.displayMemo,
                  ),
              ],
              onSigned: (cbor) async => scanned.complete(cbor),
            ),
            scannerBuilder: (_, onComplete, _, _) {
              deliverScan = onComplete;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  final qr = find.byType(KeystonePcztQrStage);
  await _waitFor(tester, qr);
  expect(find.text('Bundle 1 of 2'), findsOneWidget);
  await _tapWhenReady(tester, find.bySemanticsLabel('Next voting bundle'));
  await tester.pump();
  expect(find.text('Bundle 2 of 2'), findsOneWidget);
  final result = await _sign(
    tester.widget<KeystonePcztQrStage>(qr).urParts,
    batch: true,
  );
  await _tapWhenReady(
    tester,
    find.byKey(const ValueKey('mobile_voting_keystone_get_signature')),
  );
  await _waitFor(
    tester,
    find.byKey(const ValueKey('mobile_voting_keystone_scanner_card')),
  );
  deliverScan!(result);
  final signatures = await round.decodeSignatures(
    await scanned.future.timeout(const Duration(seconds: 15)),
  );
  expect(signatures.map((s) => s.bundleIndex), [0, 1]);

  final inputs = <voting.ApiKeystoneSignatureInput>[];
  for (final s in signatures) {
    final request = requests[s.bundleIndex];
    expect(s.pool, 1);
    expect(s.actionIndex, request.actionIndex);
    inputs.add(
      voting.ApiKeystoneSignatureInput(
        bundleIndex: s.bundleIndex,
        sig: Uint8List.fromList(s.signature),
        rk: request.rk,
        sighash: request.pcztSighash,
      ),
    );
  }
  final saved = await voting.storeKeystoneSignaturesBatch(
    dbPath: dbPath,
    accountUuid: _uuid,
    roundId: roundId,
    signatures: inputs,
  );
  expect(saved.inserted, 2);
  final records = await voting.getKeystoneSignatures(
    dbPath: dbPath,
    accountUuid: _uuid,
    roundId: roundId,
  );
  expect(records.map((r) => r.bundleIndex), unorderedEquals([0, 1]));
  final verification = await _request(
    '/verify-votes',
    body: {
      for (final r in records) r.bundleIndex.toString(): base64Encode(r.sig),
    },
  );
  expect(verification['verified'], isTrue);
}

Future<ScanResult> _sign(List<String> frames, {required bool batch}) async {
  final reply = await _request(
    '/sign',
    body: {'mode': batch ? 'batch' : 'single', 'parts': frames},
  );
  for (final part in (reply['parts'] as List).cast<String>()) {
    final result = await keystone.decodeUrPart(
      part_: part,
      expectedUrType: batch ? 'zcash-batch-sig-result' : 'zcash-pczt',
    );
    if (result.complete) {
      return ScanResult(urType: result.urType!, data: result.data!);
    }
  }
  throw StateError('Incomplete signed firmware response');
}

Future<Map<String, dynamic>> _request(
  String path, {
  Map<String, dynamic>? body,
}) async {
  const url = String.fromEnvironment('KEYSTONE_SIGNER_URL');
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('$url$path'),
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      final payload = utf8.encode(jsonEncode(body));
      request.contentLength = payload.length;
      request.add(payload);
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    expect(
      response.statusCode,
      200,
      reason: response.statusCode == 200 ? null : text,
    );
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

// A real route transition can still be sliding the footer into the viewport
// after QR preparation completes.
Future<void> _tapWhenReady(WidgetTester tester, Finder finder) async {
  final target = finder.hitTestable();
  await _waitFor(tester, target);
  await tester.tap(target);
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final clock = Stopwatch()..start();
  while (!tester.any(finder) && clock.elapsed < const Duration(minutes: 2)) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  expect(
    finder,
    findsOneWidget,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .join(' '),
  );
}

class _DirectNetwork extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}

class _FixtureSync extends SyncNotifier {
  @override
  Future<SyncState> build() async =>
      SyncState(accountUuid: _uuid, hasAccountScopedData: true);

  @override
  Future<void> refreshAfterSend() async {}
}
