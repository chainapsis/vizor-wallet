import 'dart:convert';
import 'dart:io';

import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';

/// Only the installed cohort can reach its original owner's bounded controls.
Future<Map<String, Object?>> postOwnedRegtestControl(
  String path,
  Map<String, Object?> payload,
) async {
  final manifest = installedE2eRuntimeCaseManifest;
  if (manifest == null) throw StateError('No owned regtest case is installed.');
  final client = HttpClient();
  const timeout = Duration(minutes: 2);
  try {
    final request = await client
        .postUrl(Uri.parse('${manifest.zcashdRpcUrl}$path'))
        .timeout(timeout);
    final bytes = utf8.encode(jsonEncode(payload));
    request.headers.contentType = ContentType.json;
    request.contentLength = bytes.length;
    request.add(bytes);
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
Future<T> withNativeClipboard<T>(Future<T> Function() action) async {
  if (installedE2eRuntimeCaseManifest == null) return action();
  await postOwnedRegtestControl('/host-resource/clipboard/acquire', const {});
  var actionFailed = false;
  try {
    return await action();
  } catch (error, stack) {
    actionFailed = true;
    try {
      await postOwnedRegtestControl(
        '/host-resource/clipboard/release',
        const {},
      );
    } catch (cleanup) {
      stderr.writeln(
        'Clipboard release also failed; host must stop writers: $cleanup',
      );
    }
    Error.throwWithStackTrace(error, stack);
  } finally {
    if (!actionFailed) {
      await postOwnedRegtestControl(
        '/host-resource/clipboard/release',
        const {},
      );
    }
  }
}
