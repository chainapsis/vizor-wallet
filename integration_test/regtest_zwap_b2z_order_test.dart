// On-device (emulator) integration test for the in-app zwap b2z backend.
//
// Runs the REAL [ZwapSwapClient] — the same Dart + FRB crypto the app uses —
// against the live regtest stack on the host (reached via 10.0.2.2 from the
// emulator) plus the local hashbind prover. Proves the in-app path:
//   ed25519 auth -> create b2z order (with a real ProveKit hashbind proof) ->
//   derive + re-verify the BTC lock address + joint ZEC unified address.
//
// Prereqs (host): zwap v3 regtest stack up (orderbook :3310, poold :3720) and
// `node v3/sdk/hashbind-prove-server.mjs` listening on :8790.
//
// Run (emulator booted):
//   fvm flutter test integration_test/regtest_zwap_b2z_order_test.dart \
//     --dart-define=VIZOR_FORM_FACTOR=mobile
//
// This is the regtest counterpart to the headless `b2z-headless.mjs` settlement,
// executed from inside the Vizor app's own code. It does NOT need mainnet funds.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/swap/integrations/zwap/zwap_swap_client.dart';
import 'package:zcash_wallet/src/rust/api/swap_zwap.dart' as zwap;

// Device → host via `adb reverse` (device localhost forwards to host ports).
const _host = '127.0.0.1';
const _orderbook = 'http://$_host:3310';
const _indexer = 'http://$_host:3500/v1';
const _poold = 'http://$_host:3720';
const _proverUrl = 'http://$_host:8790/prove';

// A fixed 32-byte test seed (the ed25519 OB identity + the swap key material).
const _seedHex = '1111111111111111111111111111111111111111111111111111111111111111';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  test('in-app ZwapSwapClient derives initiator half via FRB', () async {
    final half = await zwap.zwapDeriveInitiatorHalf(
      seedHex: _seedHex,
      swapId: 'b2z-itest-derive',
    );
    expect(half.akSec1.length, 66, reason: 'ak_a SEC1 = 33 bytes');
    expect(half.nskLe.length, 64);
    expect(half.hAHex.length, 64);
  });

  test('in-app b2z order creation against regtest orderbook', () async {
    final client = ZwapSwapClient(
      orderbookUrl: _orderbook,
      indexerUrl: _indexer,
      pooldUrl: _poold,
      network: 'regtest',
      hashbindProver: _proveViaHelper,
    );
    addTearDown(client.dispose);

    // 1. ed25519 challenge–response auth (seed signed in Rust).
    final token = await client.authenticate(_seedHex);
    expect(token, isNotEmpty, reason: 'orderbook returned a session token');

    // 2. Create a b2z order with a real hashbind proof + derive the addresses.
    // recvAddr is stored opaquely by the orderbook at creation (the sweep is
    // not exercised here); the app commits a fresh wallet receiver instead
    // (ZwapSwapAdapter.newReceiveRawAddress). minReceiveZats mirrors the
    // adapter default dust floor (2 × sweepFeeZats 15000).
    final swapId = 'b2z-itest-${DateTime.now().millisecondsSinceEpoch}';
    final order = await client.createB2zOrder(
      seedHex: _seedHex,
      token: token,
      swapId: swapId,
      amountSat: 100000,
      timelocks: const LockTimelocks(t1: 72, t2: 144),
      receiveRawAddress: '11' * 43,
      minReceiveZats: 30000,
    );

    expect(order.btcLockAddress, startsWith('bcrt1q'),
        reason: 'regtest BTC P2WSH lock address');
    expect(order.jointZecAddress, startsWith('uregtest1'),
        reason: 'regtest joint Orchard unified address');
    expect(order.jointZecUfvk, startsWith('uview'),
        reason: 'joint Orchard UFVK');

    // 3. The joint UA round-trips to a 43-byte raw Orchard receiver — the
    // same conversion the app uses to build a real recvAddr from a wallet UA.
    final rawHex =
        await zwap.zwapUnifiedToOrchardRawHex(unifiedAddress: order.jointZecAddress);
    expect(rawHex.length, 86, reason: '43-byte raw Orchard receiver hex');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

// Inline prover for the test (the config one reads a compile-time define).
Future<List<int>> _proveViaHelper(String kBeHex) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(_proverUrl));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode('{"scalar":"$kBeHex"}'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final proofHex = (jsonDecode(body) as Map<String, dynamic>)['proofHex'] as String;
    return [
      for (var i = 0; i + 1 < proofHex.length; i += 2)
        int.parse(proofHex.substring(i, i + 2), radix: 16),
    ];
  } finally {
    client.close(force: true);
  }
}
