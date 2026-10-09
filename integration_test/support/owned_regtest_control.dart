import 'dart:convert';
import 'dart:io';

import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';

/// Only the installed cohort can reach its original owner's bounded controls.
Future<Map<String, Object?>> postOwnedRegtestControl(
  String path,
  Map<String, Object?> payload,
) => _requestOwnedRegtestControl('POST', path, payload);

Future<Map<String, Object?>> getOwnedRegtestControl(String path) =>
    _requestOwnedRegtestControl('GET', path, null);

Future<Map<String, Object?>> _requestOwnedRegtestControl(
  String method,
  String path,
  Map<String, Object?>? payload,
) async {
  final manifest = installedE2eRuntimeCaseManifest;
  if (manifest == null) throw StateError('No owned regtest case is installed.');
  final client = HttpClient();
  const timeout = Duration(minutes: 2);
  try {
    final request = await client
        .openUrl(method, Uri.parse('${manifest.zcashdRpcUrl}$path'))
        .timeout(timeout);
    if (payload != null) {
      final bytes = utf8.encode(jsonEncode(payload));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Owned control $path: HTTP ${response.statusCode}\n$body',
      );
    }
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

Future<int> mineOwnedRegtestBlocks(int blocks) async {
  final result = await postOwnedRegtestControl('/mine', {'blocks': blocks});
  final height = (result['tip'] as Map<String, Object?>)['height'];
  if (height is! int || height < 1) {
    throw StateError('Owned mining did not return a valid chain tip.');
  }
  return height;
}

Future<String> fundOwnedRegtestTransparent(
  String address,
  int amountZatoshi, {
  required int sourceHeight,
  required int confirmations,
}) async {
  final result = await postOwnedRegtestControl('/fund-confirmed', {
    'address': address,
    'amount_zatoshi': amountZatoshi,
    'source_height': sourceHeight,
    'recipient_pool': 'transparent',
    'confirmations': confirmations,
  });
  final txid = result['txid_hex'];
  if (txid is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(txid)) {
    throw StateError(
      'Owned funding did not return its independently proved txid.',
    );
  }
  return txid;
}

/// Preserve real copy/read semantics, locking only this short shared operation.
Future<T> withNativeClipboard<T>(
  Future<T> Function() action, {
  Future<void> Function()? acquireLease,
  Future<void> Function()? releaseLease,
}) async {
  if ((acquireLease == null) != (releaseLease == null)) {
    throw ArgumentError('Clipboard test callbacks must be supplied together.');
  }
  if (acquireLease == null) {
    if (installedE2eRuntimeCaseManifest == null) return action();
    acquireLease = () async {
      await postOwnedRegtestControl(
        '/host-resource/clipboard/acquire',
        const {},
      );
    };
    releaseLease = () async {
      await postOwnedRegtestControl(
        '/host-resource/clipboard/release',
        const {},
      );
    };
  }
  await acquireLease();
  var completed = false;
  try {
    final value = await action();
    completed = true;
    return value;
  } finally {
    // A failed copy/read may leave a writer in flight. Only the host's original
    // joined-app/driver teardown can release that abandoned lease.
    if (completed) await releaseLease!();
  }
}
