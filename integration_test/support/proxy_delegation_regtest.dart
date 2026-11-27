import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/providers/voting/voting_participation_provider.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as voting_rust;
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_participation_client.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';

import 'voting_discovery_regtest.dart';

/// The loopback gateway of `scripts/e2e/flutter-macos-regtest-proxy-delegation.sh`.
const proxyRegtestGatewayUrl = String.fromEnvironment(
  'ZCASH_E2E_VOTING_GATEWAY_URL',
);

/// The attester dev stack's development CA, base64 of its PEM.
const _devCaPemBase64 = String.fromEnvironment('ZCASH_E2E_DEV_CA_PEM_BASE64');

/// Prepares a regtest process for the proxy delegation stack: trusts the
/// dev stack's CA in Dart's HTTP clients and pins the vote chain's anchor
/// for the participation reader. Call it after the Rust runtime is up and
/// before the app is built.
///
/// The CA is added to Dart's own `SecurityContext` through [HttpOverrides],
/// so only this test process trusts it, beside the platform's roots: no
/// keychain, product code or Rust transport changes. It serves the static
/// and dynamic config, the signed test wallet list, the attester API and
/// the proof hosts, which Vizor reads through Dart. The
/// dev stack's name constraints keep that trust to `127.0.0.1` and
/// `localhost`. The list's URL and signing key reach the app as the
/// `VIZOR_PROXY_WALLET_LIST_URL` and `VIZOR_PROXY_WALLET_LIST_KEY` defines.
Future<void> prepareProxyDelegationRegtest() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError('The proxy delegation stack is regtest only.');
  }
  if (_devCaPemBase64.isEmpty) {
    throw StateError('ZCASH_E2E_DEV_CA_PEM_BASE64 must name the dev CA.');
  }
  HttpOverrides.global = _DevCaHttpOverrides(base64Decode(_devCaPemBase64));
  await voting_rust.configureRegtestVotingParticipation(
    chainId: const String.fromEnvironment('ZCASH_E2E_VOTE_CHAIN_ID'),
    validatorHash: const String.fromEnvironment(
      'ZCASH_E2E_VOTE_VALIDATOR_HASH',
    ),
  );
}

/// Provider overrides that route the regtest source's discovery and
/// participation reads to the gateway, as the voting regtest tests do.
List<Override> proxyDelegationRegtestOverrides() => [
  ...votingDiscoveryRegtestOverrides(),
  votingParticipationSourceSupportedProvider.overrideWithValue(
    (network, source) =>
        network == 'regtest' && source == kE2eStaticVotingConfigSource,
  ),
  votingParticipationClientProvider.overrideWith((ref) {
    final http = DartIoVotingHttpClient();
    ref.onDispose(() => http.close(force: true));
    return VotingParticipationClient(
      http,
      const VotingParticipationBridge(),
      cache: ref.read(votingFileCacheProvider),
      regtestEndpoint: Uri.parse(proxyRegtestGatewayUrl),
    );
  }),
];

/// Trusts one extra CA, besides the platform's roots, in every Dart
/// [HttpClient] the process creates.
class _DevCaHttpOverrides extends HttpOverrides {
  /// Creates the overrides for [caPem].
  _DevCaHttpOverrides(this.caPem);

  /// The CA certificate, PEM.
  final List<int> caPem;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final trusted = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(caPem);
    return super.createHttpClient(trusted);
  }
}
