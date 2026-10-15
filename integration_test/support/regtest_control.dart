import 'dart:convert';
import 'dart:io';

import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';

/// The control server in front of the test's Zakura regtest chain: chain
/// status, mining and funding.
const regtestControlUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:18232',
);

// Each payment spends one mature coinbase. The runner's own payments spend
// the lowest heights; the runner passes the first height they left unspent.
var _nextFundingSource = const int.fromEnvironment(
  'ZCASH_E2E_FUNDING_SOURCE_HEIGHT',
  defaultValue: 1,
);

Future<Map<String, Object?>> regtestControlGet(String path) =>
    _regtestControlRequest('GET', path, null);

Future<Map<String, Object?>> regtestControlPost(
  String path, [
  Map<String, Object?> payload = const {},
]) => _regtestControlRequest('POST', path, payload);

/// The fixture node's tip height.
Future<int> regtestTipHeight() async {
  final height = (await regtestControlGet('/status'))['zcashdHeight'];
  if (height is! int) {
    throw StateError('The regtest control returned no chain height.');
  }
  return height;
}

/// Mines [blocks] blocks and returns the new tip height.
Future<int> mineRegtestFixture(int blocks) async {
  final result = await regtestControlPost('/mine', {'blocks': blocks});
  final tip = result['tip'];
  final height = tip is Map<String, Object?> ? tip['height'] : null;
  if (height is! int) {
    throw StateError('The regtest control returned no mined tip.');
  }
  return height;
}

/// Pays [amountZec] to [address] in [pool] (`ironwood`, `orchard` or
/// `transparent`) and mines [confirmations] blocks. Returns the txid.
Future<String> fundRegtestFixture(
  String address,
  String amountZec, {
  required String pool,
  int confirmations = 10,
}) async {
  final result = await regtestControlPost('/fund-confirmed', {
    'address': address,
    'amount_zatoshi': _zatoshi(amountZec),
    'source_height': _nextFundingSource++,
    'recipient_pool': pool,
    'confirmations': confirmations,
  });
  return _txid(result);
}

/// Sends an unmined Ironwood payment of [amountZec] to [address]. With
/// [expiring], the transaction expires 20 blocks above the current tip.
Future<({String txid, int expiryHeight})> fundRegtestFixtureUnmined(
  String address,
  String amountZec, {
  bool expiring = false,
}) async {
  final result = await regtestControlPost(
    expiring ? '/fund-unmined-expiring' : '/fund-unmined',
    {
      'address': address,
      'amount_zatoshi': _zatoshi(amountZec),
      'source_height': _nextFundingSource++,
    },
  );
  final expiryHeight = result['expiry_height'];
  if (expiryHeight is! int) {
    throw StateError('The regtest control returned no expiry height.');
  }
  return (txid: _txid(result), expiryHeight: expiryHeight);
}

/// Mines past [expiryHeight] while keeping [txid] out of every block.
Future<void> mineRegtestFixtureToExpiry(String txid, int expiryHeight) =>
    regtestControlPost('/mine-to-expiry', {
      'txid': txid,
      'expiry_height': expiryHeight,
    });

/// The node's decoded view of [txid], as `getrawtransaction` verbose.
Future<Map<String, Object?>> regtestTransaction(String txid) =>
    regtestControlPost('/raw-transaction', {'txid': txid});

int _zatoshi(String amountZec) {
  final zatoshi = parseZecAmount(amountZec);
  if (zatoshi == null || zatoshi <= BigInt.zero) {
    throw ArgumentError.value(amountZec, 'amountZec', 'is not a ZEC amount');
  }
  return zatoshi.toInt();
}

String _txid(Map<String, Object?> result) {
  final txid = result['txid_hex'];
  if (txid is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(txid)) {
    throw StateError('The regtest control returned no txid: $result');
  }
  return txid;
}

Future<Map<String, Object?>> _regtestControlRequest(
  String method,
  String path,
  Map<String, Object?>? payload,
) async {
  const timeout = Duration(minutes: 5);
  final client = HttpClient();
  try {
    final request = await client
        .openUrl(method, Uri.parse('$regtestControlUrl$path'))
        .timeout(timeout);
    if (payload != null) {
      final body = utf8.encode(jsonEncode(payload));
      request.headers.contentType = ContentType.json;
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Regtest control $method $path failed: HTTP '
        '${response.statusCode}\n$body',
      );
    }
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}
