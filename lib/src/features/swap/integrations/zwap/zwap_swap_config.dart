import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'zwap_hashbind_native.dart';
import 'zwap_swap_client.dart';

/// Which swap backend the wallet uses. `near` = the existing NEAR Intents
/// 1-click aggregator; `zwap` = the non-custodial BTC↔ZEC atomic-swap backend.
///
/// Build-time switch so the dead path is tree-shaken:
/// `--dart-define=VIZOR_SWAP_BACKEND=zwap` (default `near`).
enum SwapBackend { near, zwap }

const String _kSwapBackendDefine =
    String.fromEnvironment('VIZOR_SWAP_BACKEND', defaultValue: 'near');

const SwapBackend kSwapBackend =
    _kSwapBackendDefine == 'zwap' ? SwapBackend.zwap : SwapBackend.near;

/// Zwap endpoint set, overridable per-build for regtest/testnet/mainnet via
/// `--dart-define`. Defaults target the local regtest stack (`v3/up.sh`).
const String kZwapOrderbookUrl =
    String.fromEnvironment('ZWAP_ORDERBOOK_URL', defaultValue: 'http://localhost:3310');
const String kZwapIndexerUrl =
    String.fromEnvironment('ZWAP_INDEXER_URL', defaultValue: 'http://localhost:3500/v1');
const String kZwapPooldUrl =
    String.fromEnvironment('ZWAP_POOLD_URL', defaultValue: 'http://localhost:3720');
const String kZwapNetwork =
    String.fromEnvironment('ZWAP_NETWORK', defaultValue: 'regtest');

/// EVM JSON-RPC endpoint for the app's primary EVM chain ('ethereum' =
/// chainId 31337 on the regtest stack, anvil :8545). Read-only; used by the z2e
/// slot-divergence guard to check `ZwapHtlc.slots(evmSlotId)` before a claim.
const String kZwapEvmRpcUrl =
    String.fromEnvironment('ZWAP_EVM_RPC_URL', defaultValue: 'http://localhost:8545');

/// EVM JSON-RPC endpoint for the SECOND EVM chain ('base' = chainId 31338 on
/// the regtest stack, anvil :8546). The in-app chain selector routes Base
/// ETH/USDC swaps here. Same read-only slot-guard use as [kZwapEvmRpcUrl].
const String kZwapEvmRpcUrlBase =
    String.fromEnvironment('ZWAP_EVM_RPC_URL_BASE', defaultValue: 'http://localhost:8546');

/// Per-chainId JSON-RPC map for the z2e slot-divergence guard. Keyed by the EVM
/// chainId the order targets (31337 'ethereum' / 31338 'base' on regtest).
const Map<int, String> kZwapEvmRpcByChainId = {
  31337: kZwapEvmRpcUrl,
  31338: kZwapEvmRpcUrlBase,
};

/// HTTP hashbind-prover helper endpoint (regtest/testing ONLY — the raw
/// spend-auth scalar is POSTed to it). When unset (production default) the
/// wallet proves on-device via ProveKit (`zwap_hashbind_native.dart`). Release builds refuse the HTTP
/// path outright.
const String kZwapHashbindProverUrl =
    String.fromEnvironment('ZWAP_HASHBIND_PROVER_URL', defaultValue: '');

/// The in-app zwap b2z swap driver, wired to the configured endpoints.
final zwapSwapClientProvider = Provider<ZwapSwapClient>((ref) {
  final client = ZwapSwapClient(
    orderbookUrl: kZwapOrderbookUrl,
    indexerUrl: kZwapIndexerUrl,
    pooldUrl: kZwapPooldUrl,
    network: kZwapNetwork,
    evmRpcUrl: kZwapEvmRpcUrl,
    evmRpcByChainId: kZwapEvmRpcByChainId,
    hashbindProver: selectZwapHashbindProver(
      releaseMode: kReleaseMode,
      httpProverUrl: kZwapHashbindProverUrl,
      native: ZwapNativeHashbindProver.instance.prove,
      http: _httpHashbindProver,
    ),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Picks the hashbind prover for this build:
///
/// - no `ZWAP_HASHBIND_PROVER_URL` (production default) → on-device ProveKit
///   prover; the scalar never leaves the process.
/// - URL set + debug/profile → the regtest HTTP helper (unchanged harness).
/// - URL set + release → fail closed with a prover that always throws: a
///   release binary must never be able to send the raw scalar off-device,
///   and silently ignoring the define would hide a broken run configuration.
@visibleForTesting
Future<List<int>> Function(String kBeHex) selectZwapHashbindProver({
  required bool releaseMode,
  required String httpProverUrl,
  required Future<List<int>> Function(String kBeHex) native,
  required Future<List<int>> Function(String kBeHex) http,
}) {
  if (httpProverUrl.isEmpty) {
    return native;
  }
  if (releaseMode) {
    return (_) async {
      throw StateError(
        'ZWAP_HASHBIND_PROVER_URL is set in a release build; refusing to '
        'send the spend-auth scalar off-device. Unset the define — release '
        'builds prove on-device.',
      );
    };
  }
  return http;
}

/// Regtest/dev prover: POST the raw scalar hex to the configured helper
/// (`hashbind-prove-server.mjs`), which returns `{ proofHex: <hex> }`. Returns
/// the proof bytes. Throws on a non-2xx response or a missing/empty
/// `proofHex` so a prover error can never masquerade as a zero-length
/// hashbind proof (which the orderbook would later reject as a malformed
/// order, losing the failure's real cause).
Future<List<int>> _httpHashbindProver(String kBeHex) async {
  final http = HttpClient();
  try {
    final req = await http.postUrl(Uri.parse(kZwapHashbindProverUrl));
    req.headers.contentType = ContentType.json;
    req.add(const Utf8Encoder().convert('{"scalar":"$kBeHex"}'));
    final res = await req.close();
    final body = await res.transform(const Utf8Decoder()).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError(
        'zwap hashbind prover returned HTTP ${res.statusCode}: '
        '${body.length > 200 ? '${body.substring(0, 200)}…' : body}',
      );
    }
    final proofHex = (jsonDecodeMap(body)['proofHex'] ?? '') as String;
    if (proofHex.isEmpty) {
      throw StateError(
        'zwap hashbind prover returned no proofHex (body: '
        '${body.length > 200 ? '${body.substring(0, 200)}…' : body})',
      );
    }
    return _hexToBytes(proofHex);
  } finally {
    http.close(force: true);
  }
}

List<int> _hexToBytes(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

Map<String, dynamic> jsonDecodeMap(String s) =>
    s.isEmpty ? <String, dynamic>{} : (jsonDecode(s) as Map<String, dynamic>);
