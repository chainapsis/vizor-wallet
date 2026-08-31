import 'package:flutter/foundation.dart';

import '../../core/config/network_config.dart';
import 'voting_http.dart';

const kE2eVotingGatewayUrlEnvKey = 'ZCASH_E2E_VOTING_GATEWAY_URL';
const kE2eVotingGatewayUrl = String.fromEnvironment(kE2eVotingGatewayUrlEnvKey);
const kStageVotingGatewayUrlEnvKey = 'ZCASH_STAGE_VOTING_GATEWAY_URL';
const kStageVotingGatewayUrl = String.fromEnvironment(
  kStageVotingGatewayUrlEnvKey,
);

/// Reserved logical DNS suffix used by the regtest voting harness.
///
/// Signed voting config keeps HTTPS identities under this suffix. Only a
/// regtest build with an explicit loopback gateway maps them to local HTTP.
const kE2eVotingLogicalHostSuffix = '.vizor-vote.invalid';

/// Maps authenticated logical voting endpoints onto a local regtest gateway.
///
/// Production and testnet builds always use identity mapping. The regtest
/// mapping is intentionally narrow: the configured gateway must be loopback,
/// and only HTTPS hosts below [kE2eVotingLogicalHostSuffix] are rewritten.
class VotingEndpointMapper {
  VotingEndpointMapper({
    required bool isRegtest,
    bool isTestnet = false,
    bool isDebugBuild = false,
    String gatewayUrl = '',
    String stageGatewayUrl = '',
  }) : _gateway = _parseGateway(
         enabled: isRegtest || (isTestnet && isDebugBuild),
         raw: isRegtest ? gatewayUrl : stageGatewayUrl,
         envKey: isRegtest
             ? kE2eVotingGatewayUrlEnvKey
             : kStageVotingGatewayUrlEnvKey,
       );

  factory VotingEndpointMapper.forBuild() {
    return VotingEndpointMapper(
      isRegtest: kZcashDefaultNetworkRaw == 'regtest',
      isTestnet: kZcashDefaultNetworkRaw == 'test',
      isDebugBuild: kDebugMode,
      gatewayUrl: kE2eVotingGatewayUrl,
      stageGatewayUrl: kStageVotingGatewayUrl,
    );
  }

  final Uri? _gateway;

  bool get isEnabled => _gateway != null;

  Uri map(Uri logicalUri) {
    final gateway = _gateway;
    if (gateway == null || !_isHarnessIdentity(logicalUri)) {
      return logicalUri;
    }

    return gateway.replace(
      pathSegments: [
        ...gateway.pathSegments.where((segment) => segment.isNotEmpty),
        logicalUri.host,
        ...logicalUri.pathSegments.where((segment) => segment.isNotEmpty),
      ],
      query: logicalUri.hasQuery ? logicalUri.query : null,
      fragment: null,
    );
  }

  String mapUrl(String logicalUrl) => map(Uri.parse(logicalUrl)).toString();

  static Uri? _parseGateway({
    required bool enabled,
    required String raw,
    required String envKey,
  }) {
    final trimmed = raw.trim();
    if (!enabled || trimmed.isEmpty) return null;

    final gateway = Uri.tryParse(trimmed);
    if (gateway == null ||
        gateway.scheme != 'http' ||
        !_isLoopbackHost(gateway.host) ||
        gateway.userInfo.isNotEmpty ||
        gateway.hasQuery ||
        gateway.hasFragment) {
      throw StateError(
        '$envKey must be a loopback HTTP URL for its test harness.',
      );
    }
    return gateway;
  }

  static bool _isHarnessIdentity(Uri uri) {
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host.endsWith(kE2eVotingLogicalHostSuffix);
  }

  static bool _isLoopbackHost(String host) {
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}

/// Applies [VotingEndpointMapper] at the shared Dart HTTP boundary.
class MappedVotingHttpClient implements VotingHttpClient {
  const MappedVotingHttpClient(this._inner, this._mapper);

  final VotingHttpClient _inner;
  final VotingEndpointMapper _mapper;

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) {
    return _inner.get(
      _mapper.map(uri),
      headers: headers,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) {
    return _inner.postJson(_mapper.map(uri), body, timeout: timeout);
  }
}
