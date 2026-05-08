import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/generated/compact_formats.pb.dart' as compact;
import 'package:zcash_wallet/src/generated/service.pb.dart' as service;
import 'package:zcash_wallet/src/generated/service.pbgrpc.dart' as service_grpc;
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _password = 'Vizor123!';
const _primaryProxyUrl = 'http://127.0.0.1:19068';
const _realLightwalletdUrl = 'http://127.0.0.1:9067';
const _driverUrl = String.fromEnvironment('ZCASH_E2E_DRIVER_URL');
const _unifiedAddress = String.fromEnvironment('ZCASH_E2E_UNIFIED_ADDRESS');
const _faucetZaddr = String.fromEnvironment('ZCASH_E2E_FAUCET_ZADDR');
const _fallbackToast =
    'Selected endpoint is unstable. Switched to fallback endpoint.';
const _primaryToast = 'Selected endpoint recovered. Switched back.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'falls back on slow height, returns to primary, then falls back when down',
    (tester) async {
      if (_unifiedAddress.isEmpty || _faucetZaddr.isEmpty) {
        fail(
          'ZCASH_E2E_UNIFIED_ADDRESS and ZCASH_E2E_FAUCET_ZADDR are required.',
        );
      }
      if (_driverUrl.isEmpty) {
        fail('ZCASH_E2E_DRIVER_URL is required.');
      }

      addTearDown(() async {
        await _cleanupE2eWalletState();
      });

      await _cleanupE2eWalletState();
      final proxy = _RegtestLightwalletdProxy();
      await proxy.start();
      addTearDown(proxy.stop);
      await _configureSlowPresetPrimary();

      _log('pumping app with slow regtest primary proxy');
      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: [
            rpcEndpointFailoverSettingsProvider.overrideWithValue(
              const RpcEndpointFailoverSettings(
                primaryProbeInterval: Duration(seconds: 3),
                slowHeightWindow: Duration(seconds: 3),
                minHeightIncreaseInSlowWindow: 2,
                slowFallbackLeadBlocks: 2,
              ),
            ),
          ],
        ),
      );

      await _importWallet(tester);
      await _waitForBalance(tester, {'1.25 zec'}, 'initial primary sync');

      final baselineHeight = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: _realLightwalletdUrl,
      );
      proxy.setSlowHeight(baselineHeight.toInt() + 1);
      await _pumpFor(tester, const Duration(seconds: 4));

      _log('funding while primary reports slow height');
      await _fundWallet('0.50');
      await _pumpUntil(
        tester,
        () => tester.any(find.text(_fallbackToast)),
        description: 'slow-height fallback toast',
        timeout: const Duration(minutes: 2),
      );
      await _waitForBalance(tester, {'1.75 zec'}, 'sync through fallback');

      _log('recovering primary proxy');
      proxy.setHealthy();
      await _pumpUntil(
        tester,
        () => tester.any(find.text(_primaryToast)),
        description: 'primary recovery toast',
        timeout: const Duration(minutes: 2),
      );
      await _pumpFor(tester, const Duration(seconds: 5));

      _log('funding after primary recovery');
      await _fundWallet('0.25');
      await _waitForBalance(tester, {
        '2 zec',
        '2.00 zec',
      }, 'sync through recovered primary');

      _log('making primary proxy unavailable');
      proxy.setDown();
      await _fundWallet('0.25');
      await _pumpUntil(
        tester,
        () => tester.any(find.text(_fallbackToast)),
        description: 'fallback toast after primary down',
        timeout: const Duration(minutes: 2),
      );
      await _waitForBalance(tester, {
        '2.25 zec',
      }, 'sync through fallback after primary down');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _importWallet(WidgetTester tester) async {
  _log('opening import flow');
  await _tapButton(tester, const ValueKey('welcome_import_wallet_button'));

  _log('entering mnemonic');
  await _enterText(
    tester,
    const ValueKey('import_mnemonic_first_word_field'),
    _mnemonic,
  );
  await _tapButton(tester, const ValueKey('import_secret_submit_button'));

  _log('skipping birthday');
  await _tapButton(tester, const ValueKey('import_birthday_skip_button'));

  _log('setting password');
  await _enterText(
    tester,
    const ValueKey('set_password_password_field'),
    _password,
  );
  await _enterText(
    tester,
    const ValueKey('set_password_confirm_field'),
    _password,
  );
  await _tapButton(tester, const ValueKey('set_password_submit_button'));
}

Future<void> _configureSlowPresetPrimary() async {
  final storage = AppSecureStore.instance;
  await storage.writePlain(kRpcEndpointUrlKey, _primaryProxyUrl);
  await storage.writePlain(
    kRpcEndpointPresetKey,
    kRegtestSlowRpcEndpointPresetId,
  );
}

Future<void> _fundWallet(String amountZec) async {
  _log('funding $_unifiedAddress with $amountZec ZEC');
  await _postDriver('/fund-unmined-prepared', {
    'address': _unifiedAddress,
    'amount': amountZec,
  });
  await _postDriver('/mine', {'blocks': 3});
}

Future<Map<String, dynamic>> _postDriver(
  String path,
  Map<String, Object> payload,
) async {
  final client = HttpClient();
  try {
    final bodyBytes = utf8.encode(jsonEncode(payload));
    final request = await client.postUrl(Uri.parse('$_driverUrl$path'));
    request.headers.contentType = ContentType.json;
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode != HttpStatus.ok) {
      fail(
        'E2E driver $path failed with status ${response.statusCode}: '
        '${decoded['error'] ?? body}',
      );
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

Future<void> _cleanupE2eWalletState() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError(
      'Refusing to clean wallet state without ZCASH_DEFAULT_NETWORK=regtest.',
    );
  }

  final storage = AppSecureStore.instance;
  final dbName = await getWalletDbName();

  _log('cleaning regtest wallet state');
  await _stopRustWorkForCleanup();

  await storage.deleteAll();

  final supportDir = await getWalletSupportDirectory();
  if (!supportDir.existsSync()) return;

  for (final name in [dbName, '$dbName-shm', '$dbName-wal']) {
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
  }
}

Future<void> _stopRustWorkForCleanup() async {
  rust_sync.setSyncMode(mode: 0);
  rust_sync.cancelFullSync();
  rust_sync.stopMempoolObserver();

  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while ((rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  if (rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) {
    _log(
      'timed out waiting for Rust work to stop; continuing E2E storage cleanup',
    );
  }
}

Future<void> _tapButton(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await _pumpUntil(
    tester,
    () =>
        tester.any(finder) &&
        tester.widget<AppButton>(finder).onPressed != null,
    description: '$key button to be enabled',
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
  _log('tapped $key');
}

Future<void> _enterText(WidgetTester tester, Key key, String text) async {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  await _pumpUntil(
    tester,
    () => tester.any(editable),
    description: '$key editable text field',
  );
  await tester.tap(editable);
  await tester.enterText(editable, text);
  await tester.pump(const Duration(milliseconds: 100));
  _log('entered text into $key');
}

Future<void> _waitForBalance(
  WidgetTester tester,
  Set<String> expected,
  String description,
) {
  return _pumpUntil(
    tester,
    () => _keyedTextIn(
      tester,
      const ValueKey('home_shielded_balance_text'),
      expected,
    ),
    description: description,
    timeout: const Duration(minutes: 4),
  );
}

bool _keyedTextIn(WidgetTester tester, Key key, Set<String> expected) {
  final finder = find.byKey(key);
  if (!tester.any(finder)) return false;
  final widget = tester.widget<Text>(finder);
  return expected.contains(widget.data);
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  Object? lastError;
  var polls = 0;
  while (DateTime.now().isBefore(end)) {
    try {
      if (condition()) return;
    } catch (e) {
      lastError = e;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    polls++;
    if (polls % 25 == 0) {
      _log('still waiting for $description');
    }
  }

  final error = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description.$error');
}

void _log(String message) {
  debugPrint('[slow-height-fallback-e2e] $message');
}

enum _ProxyMode { healthy, slowHeight, down }

class _RegtestLightwalletdProxy
    extends service_grpc.CompactTxStreamerServiceBase {
  _RegtestLightwalletdProxy()
    : _channel = grpc.ClientChannel(
        '127.0.0.1',
        port: 9067,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      ) {
    _client = service_grpc.CompactTxStreamerClient(_channel);
  }

  final grpc.ClientChannel _channel;
  late final service_grpc.CompactTxStreamerClient _client;
  grpc.Server? _server;
  _ProxyMode _mode = _ProxyMode.healthy;
  int? _slowHeight;

  Future<void> start() async {
    _server = grpc.Server.create(services: [this]);
    await _server!.serve(address: InternetAddress.loopbackIPv4, port: 19068);
    _log('primary proxy listening on $_primaryProxyUrl');
  }

  Future<void> stop() async {
    await _server?.shutdown();
    await _channel.shutdown();
  }

  void setHealthy() {
    _mode = _ProxyMode.healthy;
    _slowHeight = null;
    _log('primary proxy mode=healthy');
  }

  void setSlowHeight(int height) {
    _mode = _ProxyMode.slowHeight;
    _slowHeight = height;
    _log('primary proxy mode=slowHeight height=$height');
  }

  void setDown() {
    _mode = _ProxyMode.down;
    _log('primary proxy mode=down');
  }

  void _throwIfDown() {
    if (_mode == _ProxyMode.down) {
      throw grpc.GrpcError.unavailable('regtest primary proxy is down');
    }
  }

  service.BlockID _withModeHeight(service.BlockID block) {
    final slowHeight = _slowHeight;
    if (_mode != _ProxyMode.slowHeight || slowHeight == null) return block;
    if (block.height.toInt() <= slowHeight) return block;
    final copy = block.deepCopy();
    copy.height = Int64(slowHeight);
    return copy;
  }

  service.LightdInfo _withModeInfoHeight(service.LightdInfo info) {
    final slowHeight = _slowHeight;
    if (_mode != _ProxyMode.slowHeight || slowHeight == null) return info;
    final copy = info.deepCopy();
    final height = Int64(slowHeight);
    if (copy.blockHeight > height) copy.blockHeight = height;
    if (copy.estimatedHeight > height) copy.estimatedHeight = height;
    return copy;
  }

  @override
  Future<service.BlockID> getLatestBlock(
    grpc.ServiceCall call,
    service.ChainSpec request,
  ) async {
    _throwIfDown();
    return _withModeHeight(await _client.getLatestBlock(request));
  }

  @override
  Future<compact.CompactBlock> getBlock(
    grpc.ServiceCall call,
    service.BlockID request,
  ) {
    _throwIfDown();
    return _client.getBlock(request);
  }

  @override
  Future<compact.CompactBlock> getBlockNullifiers(
    grpc.ServiceCall call,
    service.BlockID request,
  ) {
    _throwIfDown();
    return _client.getBlockNullifiers(request);
  }

  @override
  Stream<compact.CompactBlock> getBlockRange(
    grpc.ServiceCall call,
    service.BlockRange request,
  ) {
    _throwIfDown();
    return _client.getBlockRange(request);
  }

  @override
  Stream<compact.CompactBlock> getBlockRangeNullifiers(
    grpc.ServiceCall call,
    service.BlockRange request,
  ) {
    _throwIfDown();
    return _client.getBlockRangeNullifiers(request);
  }

  @override
  Future<service.RawTransaction> getTransaction(
    grpc.ServiceCall call,
    service.TxFilter request,
  ) {
    _throwIfDown();
    return _client.getTransaction(request);
  }

  @override
  Future<service.SendResponse> sendTransaction(
    grpc.ServiceCall call,
    service.RawTransaction request,
  ) {
    _throwIfDown();
    return _client.sendTransaction(request);
  }

  @override
  Stream<service.RawTransaction> getTaddressTxids(
    grpc.ServiceCall call,
    service.TransparentAddressBlockFilter request,
  ) {
    _throwIfDown();
    return _client.getTaddressTxids(request);
  }

  @override
  Stream<service.RawTransaction> getTaddressTransactions(
    grpc.ServiceCall call,
    service.TransparentAddressBlockFilter request,
  ) {
    _throwIfDown();
    return _client.getTaddressTransactions(request);
  }

  @override
  Future<service.Balance> getTaddressBalance(
    grpc.ServiceCall call,
    service.AddressList request,
  ) {
    _throwIfDown();
    return _client.getTaddressBalance(request);
  }

  @override
  Future<service.Balance> getTaddressBalanceStream(
    grpc.ServiceCall call,
    Stream<service.Address> request,
  ) {
    _throwIfDown();
    return _client.getTaddressBalanceStream(request);
  }

  @override
  Stream<compact.CompactTx> getMempoolTx(
    grpc.ServiceCall call,
    service.GetMempoolTxRequest request,
  ) {
    _throwIfDown();
    return _client.getMempoolTx(request);
  }

  @override
  Stream<service.RawTransaction> getMempoolStream(
    grpc.ServiceCall call,
    service.Empty request,
  ) {
    _throwIfDown();
    return _client.getMempoolStream(request);
  }

  @override
  Future<service.TreeState> getTreeState(
    grpc.ServiceCall call,
    service.BlockID request,
  ) {
    _throwIfDown();
    return _client.getTreeState(request);
  }

  @override
  Future<service.TreeState> getLatestTreeState(
    grpc.ServiceCall call,
    service.Empty request,
  ) {
    _throwIfDown();
    return _client.getLatestTreeState(request);
  }

  @override
  Stream<service.SubtreeRoot> getSubtreeRoots(
    grpc.ServiceCall call,
    service.GetSubtreeRootsArg request,
  ) {
    _throwIfDown();
    return _client.getSubtreeRoots(request);
  }

  @override
  Future<service.GetAddressUtxosReplyList> getAddressUtxos(
    grpc.ServiceCall call,
    service.GetAddressUtxosArg request,
  ) {
    _throwIfDown();
    return _client.getAddressUtxos(request);
  }

  @override
  Stream<service.GetAddressUtxosReply> getAddressUtxosStream(
    grpc.ServiceCall call,
    service.GetAddressUtxosArg request,
  ) {
    _throwIfDown();
    return _client.getAddressUtxosStream(request);
  }

  @override
  Future<service.LightdInfo> getLightdInfo(
    grpc.ServiceCall call,
    service.Empty request,
  ) async {
    _throwIfDown();
    return _withModeInfoHeight(await _client.getLightdInfo(request));
  }

  @override
  Future<service.PingResponse> ping(
    grpc.ServiceCall call,
    service.Duration request,
  ) {
    _throwIfDown();
    return _client.ping(request);
  }
}
