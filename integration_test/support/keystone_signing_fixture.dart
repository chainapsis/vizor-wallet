import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as sync;
import 'package:zcash_wallet/src/rust/api/voting.dart' as voting;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/delegate.dart'
    as delegate;

import '../../test/support/wallet_path_read_blocker.dart';

const _uuid = String.fromEnvironment('KEYSTONE_ACCOUNT_UUID');
const _tex = String.fromEnvironment('KEYSTONE_TEX_ADDRESS');

const _zebraUrl = String.fromEnvironment('KEYSTONE_ZEBRA_LIGHTWALLETD');
const _network = 'regtest';
Directory? _zebraWallet;

Future<void> releaseKeystoneWallet() async {
  await _zebraWallet?.delete(recursive: true);
}

void _useFixtureStorage(Directory directory) {
  WalletPathReadBlocker().complete(directory.path);
  FlutterSecureStorage.setMockInitialValues({kWalletDbNameKey: 'wallet.db'});
  addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
}

class KeystoneSendFixture {
  KeystoneSendFixture(this.args, this.approvals);

  final SendReviewArgs args;
  final int approvals;
  final _txids = <String>[];

  static Future<KeystoneSendFixture> create({required bool tex}) async {
    const encodedDb = String.fromEnvironment('KEYSTONE_WALLET_DB');
    expect(
      encodedDb,
      isNotEmpty,
      reason: 'Run scripts/e2e/flutter-keystone.sh',
    );
    final directory = _zebraWallet ??= await Directory.systemTemp.createTemp(
      'vizor-keystone-zebra.',
    );
    _useFixtureStorage(directory);
    final dbPath = '${directory.path}/wallet.db';
    final db = File(dbPath);
    if (!await db.exists()) {
      await db.writeAsBytes(gzip.decode(base64Decode(encodedDb)), flush: true);
    }
    final address = tex
        ? _tex
        : const String.fromEnvironment('KEYSTONE_SEND_ADDRESS');
    final flowId = tex ? 'keystone-tex' : 'keystone-send';
    final approvals = tex ? 2 : 1;
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

    return KeystoneSendFixture(args, approvals);
  }

  Widget withWallet(Widget child) => ProviderScope(
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
            lightwalletdUrl: _zebraUrl,
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
    child: child,
  );

  void recordSigned(KeystoneBroadcastArgs result) {
    _txids.addAll(
      result.pcztWithProofs.map((pczt) => sync.getPcztTxid(pcztBytes: pczt)),
    );
    debugPrint('Keystone signed ${args.sendFlowId} txids=${_txids.join(",")}');
  }

  Future<void> expectNoBroadcast() async {
    expect(
      await _zebraRpc('getrawmempool', []),
      isEmpty,
      reason: 'All approvals must precede submission to Zebra',
    );
  }

  Future<void> verifyBroadcast() async {
    expect(_txids.toSet(), hasLength(approvals));
    final found = <String>{};
    // Zebra may mine the dependent TEX child in the following block.
    for (var i = 0; i < 5 && found.length < _txids.length; i++) {
      final hashes = await _zebraRpc('generate', [1]) as List;
      final block =
          await _zebraRpc('getblock', [hashes.single as String, 1]) as Map;
      final mined = (block['tx'] as List).cast<String>().where(_txids.contains);
      for (final id in mined) {
        found.add(id);
        debugPrint(
          'Keystone Zebra txid=$id height=${block['height']} block=${block['hash']}',
        );
      }
    }
    expect(found, unorderedEquals(_txids));
    if (_txids.length == 2) {
      final child =
          await _zebraRpc('getrawtransaction', [_txids.last, 1]) as Map;
      expect(
        (child['vin'] as List).map((input) => input['txid']),
        contains(_txids.first),
      );
    }
  }
}

Future<dynamic> _zebraRpc(String method, List<Object> params) async {
  final uri = Uri.parse(const String.fromEnvironment('KEYSTONE_ZEBRA_RPC'));
  expect(uri.host, '127.0.0.1');
  final client = HttpClient();
  try {
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
  } finally {
    client.close(force: true);
  }
}

class KeystoneVoteFixture {
  KeystoneVoteFixture(this.round, this.dbPath, this.roundId, this.accountUuid);

  final VotingKeystoneSigningRound round;
  final String dbPath;
  final String roundId;
  final String accountUuid;
  List<delegate.KeystoneSigningRequest> get requests => round.requests;

  List<VotingKeystoneBatchMemo> get memos => [
    for (final r in requests)
      VotingKeystoneBatchMemo(
        bundleIndex: r.bundleIndex,
        bundleCount: r.bundleCount,
        displayMemo: r.displayMemo,
      ),
  ];

  static Future<KeystoneVoteFixture> create() async {
    final fixture = await _request('/voting-fixture');
    final directory = await Directory.systemTemp.createTemp(
      'vizor-keystone-voting.',
    );
    addTearDown(() => directory.delete(recursive: true));
    _useFixtureStorage(directory);
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
    final accountUuid = fixture['account_uuid'] as String;
    final roundId = fixture['round_id'] as String;
    final round = await VotingKeystoneSigningRound.prepare(
      VotingSessionKey(roundId: roundId, accountUuid: accountUuid),
      requests,
    );
    expect(round.requests.map((r) => r.bundleIndex), [0, 1]);

    return KeystoneVoteFixture(round, dbPath, roundId, accountUuid);
  }

  Future<void> verifySignatures(List<int> response) async {
    final signatures = await round.decodeSignatures(response);
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
      accountUuid: accountUuid,
      roundId: roundId,
      signatures: inputs,
    );
    expect(saved.inserted, 2);
    final records = await voting.getKeystoneSignatures(
      dbPath: dbPath,
      accountUuid: accountUuid,
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
    debugPrint(
      'Verified both stored voting signatures against their original bundle keys and sighashes',
    );
  }
}

Future<List<String>> signWithFirmware(
  List<String> frames, {
  required bool batch,
  bool voting = false,
}) async {
  final reply = await _request(
    voting ? '/sign-votes' : '/sign',
    body: {'mode': batch ? 'batch' : 'single', 'parts': frames},
  );
  final parts = (reply['parts'] as List).cast<String>();
  expect(parts, isNotEmpty);
  return parts;
}

Future<void> exchangeDesktopSignature(
  WidgetTester tester,
  List<String> parts, {
  required bool batch,
  required bool gui,
  bool voting = false,
  required Future<void> Function() openScanner,
}) async {
  if (!gui) {
    final signed = await signWithFirmware(parts, batch: batch, voting: voting);
    await openScanner();
    await scanFirmwareFrames(tester, signed);
    return;
  }
  await _request(
    voting ? '/approve-votes' : '/approve-payment',
    body: {'mode': batch ? 'batch' : 'single', 'parts': parts},
  );
  try {
    await openScanner();
    await _scanGuiSignature(tester);
  } finally {
    await _request('/close-signing', body: {});
  }
}

// Use the real macOS mobile_scanner plugin in Vizor to recognize pixels.
// Feed its native barcode event to the mounted camera listener so normal
// scan, UR reconstruction and signature handling drive the route transition.
Future<void> _scanGuiSignature(WidgetTester tester) async {
  final scanner = find.byType(MobileScanner);
  await waitForWidget(tester, scanner);
  final route = ModalRoute.of(tester.element(scanner))!;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  const plugin = 'dev.steenbakker.mobile_scanner/scanner';
  final native = MethodChannel('$plugin/method', codec, messenger.delegate);
  final directory = await Directory.systemTemp.createTemp('vizor-keystone-qr.');
  final frame = File('${directory.path}/signature.png');
  final elapsed = Stopwatch()..start();
  var detections = 0;
  try {
    while (route.isCurrent && elapsed.elapsed < const Duration(seconds: 60)) {
      final image = await _request('/signature-frame');
      await frame.writeAsBytes(
        base64Decode(image['png'] as String),
        flush: true,
      );
      final event = await native.invokeMapMethod<Object?, Object?>(
        'analyzeImage',
        {
          'filePath': frame.path,
          'formats': [BarcodeFormat.qrCode.rawValue],
        },
      );
      if (event != null && (event['data'] as List).isNotEmpty) {
        detections++;
        await messenger.handlePlatformMessage(
          '$plugin/event',
          codec.encodeSuccessEnvelope(event),
          null,
        );
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      detections,
      greaterThan(0),
      reason: 'No QR detected on the Keystone signature screen',
    );
    expect(
      route.isCurrent,
      isFalse,
      reason: 'Vizor did not reconstruct the signed response',
    );
    debugPrint(
      'Vizor read the Keystone signature QR in $detections native detections',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

// The native camera would report these same UR strings as barcode detections.
// Leave UR session management, decoding and navigation to the active screen.
Future<void> scanFirmwareFrames(
  WidgetTester tester,
  List<String> frames,
) async {
  final finder = find.byType(MobileScanner);
  await waitForWidget(tester, finder);
  final detect = tester.widget<MobileScanner>(finder).onDetect!;
  for (final frame in frames) {
    detect(
      BarcodeCapture(
        barcodes: [Barcode(rawValue: frame, format: BarcodeFormat.qrCode)],
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void installFixtureCamera() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const camera = {
    'id': 'fixture',
    'name': 'Fixture camera',
    'facing': 2,
    'isDefault': true,
  };
  for (final suffix in ['method', 'event', 'deviceOrientation']) {
    final channel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/$suffix',
    );
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'state' => 1,
        'request' => true,
        'getAvailableCameras' => [camera],
        'start' => {
          'textureId': 1,
          'camera': camera,
          'cameraDirection': 2,
          'numberOfCameras': 1,
          'size': {'width': 640.0, 'height': 480.0},
        },
        _ => null,
      },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
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
Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
  final target = finder.hitTestable();
  await waitForWidget(tester, target);
  await tester.tap(target);
}

Future<void> waitForWidget(WidgetTester tester, Finder finder) async {
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
