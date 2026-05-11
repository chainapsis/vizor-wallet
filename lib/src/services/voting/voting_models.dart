import 'dart:convert';

/// Hash-pinned trust anchor fetched before the mutable service config.
///
/// This config should be small and stable: it tells the app where to fetch the
/// dynamic config and which signing keys are allowed to authenticate rounds.
class StaticVotingConfig {
  static const supportedVersion = 1;
  static const algEd25519 = 'ed25519';

  final int staticConfigVersion;
  final Uri dynamicConfigUrl;
  final List<TrustedVotingKey> trustedKeys;

  const StaticVotingConfig({
    required this.staticConfigVersion,
    required this.dynamicConfigUrl,
    required this.trustedKeys,
  });

  factory StaticVotingConfig.fromJson(Map<String, dynamic> json) {
    return StaticVotingConfig(
      staticConfigVersion: _intFromJson(json, const [
        'static_config_version',
        'staticConfigVersion',
      ]),
      dynamicConfigUrl: _requiredUriFromJson(json, const [
        'dynamic_config_url',
        'dynamicConfigURL',
        'dynamicConfigUrl',
      ]),
      trustedKeys:
          _requiredListFromJson(json, const ['trusted_keys', 'trustedKeys'])
              .map(_objectFromValue)
              .map(TrustedVotingKey.fromJson)
              .toList(growable: false),
    );
  }

  void validate() {
    if (staticConfigVersion != supportedVersion) {
      throw VotingConfigDecodeException(
        'unsupported static_config_version $staticConfigVersion',
      );
    }
    if (trustedKeys.isEmpty) {
      throw const VotingConfigDecodeException(
        'trusted_keys must contain at least one entry',
      );
    }
    for (final key in trustedKeys) {
      if (key.alg != algEd25519) {
        throw VotingConfigDecodeException(
          'trusted_keys[${key.keyId}].alg unsupported: ${key.alg}',
        );
      }
      if (key.pubkey.length != 32) {
        throw VotingConfigDecodeException(
          'trusted_keys[${key.keyId}].pubkey must decode to 32 bytes',
        );
      }
    }
  }
}

/// Public key allowed to sign dynamic round entries.
class TrustedVotingKey {
  final String keyId;
  final String alg;
  final List<int> pubkey;
  final String? notes;

  const TrustedVotingKey({
    required this.keyId,
    required this.alg,
    required this.pubkey,
    this.notes,
  });

  factory TrustedVotingKey.fromJson(Map<String, dynamic> json) {
    return TrustedVotingKey(
      keyId: _stringFromJson(json, const ['key_id', 'keyId']),
      alg: _stringFromJson(json, const ['alg']),
      pubkey: _bytesFromJson(json, const ['pubkey']),
      notes: _optionalStringFromJson(json, const ['notes']),
    );
  }
}

/// Dynamic voting service configuration.
///
/// This is the network-fetched registry for vote servers, PIR endpoints,
/// protocol versions, and authenticated round metadata. Missing required fields
/// are treated as decode failures so the app does not continue with partial
/// service state.
class VotingConfig {
  static const supportedVersion = 1;

  final int configVersion;
  final List<VotingServiceEndpoint> voteServers;
  final List<VotingServiceEndpoint> pirEndpoints;
  final VotingSupportedVersions supportedVersions;
  final Map<String, VotingRoundEntry> rounds;

  const VotingConfig({
    required this.configVersion,
    required this.voteServers,
    required this.pirEndpoints,
    required this.supportedVersions,
    required this.rounds,
  });

  factory VotingConfig.fromJson(Map<String, dynamic> json) {
    final roundMap = _objectFromValue(
      _requiredValueFromJson(json, const ['rounds']),
    );
    return VotingConfig(
      configVersion: _intFromJson(json, const [
        'config_version',
        'configVersion',
      ]),
      voteServers:
          _requiredListFromJson(json, const ['vote_servers', 'voteServers'])
              .map(_objectFromValue)
              .map(VotingServiceEndpoint.fromJson)
              .toList(growable: false),
      pirEndpoints:
          _requiredListFromJson(json, const ['pir_endpoints', 'pirEndpoints'])
              .map(_objectFromValue)
              .map(VotingServiceEndpoint.fromJson)
              .toList(growable: false),
      supportedVersions: VotingSupportedVersions.fromJson(
        _objectFromValue(
          _requiredValueFromJson(json, const [
            'supported_versions',
            'supportedVersions',
          ]),
        ),
      ),
      rounds: roundMap.map(
        (key, value) =>
            MapEntry(key, VotingRoundEntry.fromJson(_objectFromValue(value))),
      ),
    );
  }

  Uri get apiBaseUrl => voteServers.first.url;

  List<Uri> get pirEndpointUrls =>
      pirEndpoints.map((endpoint) => endpoint.url).toList(growable: false);

  void validate() {
    if (configVersion != supportedVersion) {
      throw VotingConfigDecodeException(
        'unsupported config_version $configVersion',
      );
    }
    if (voteServers.isEmpty) {
      throw const VotingConfigDecodeException(
        'vote_servers must contain at least one entry',
      );
    }
    if (pirEndpoints.isEmpty) {
      throw const VotingConfigDecodeException(
        'pir_endpoints must contain at least one entry',
      );
    }
    for (final roundId in rounds.keys) {
      if (!_isLowercaseHexRoundId(roundId)) {
        throw VotingConfigDecodeException(
          'rounds key must be 64 lowercase hex characters: $roundId',
        );
      }
    }
    supportedVersions.validate();
  }
}

/// Base URL plus optional label for a vote server or PIR endpoint.
class VotingServiceEndpoint {
  final Uri url;
  final String label;

  const VotingServiceEndpoint({required this.url, required this.label});

  factory VotingServiceEndpoint.fromJson(Map<String, dynamic> json) {
    final url = _uriFromJson(json, const ['url']);
    if (url == null) {
      throw const VotingConfigDecodeException('service endpoint missing url');
    }
    return VotingServiceEndpoint(
      url: url,
      label: _optionalStringFromJson(json, const ['label', 'name']) ?? '',
    );
  }
}

/// Protocol versions advertised by the dynamic config.
///
/// Validation requires every component the app will use to have at least one
/// locally supported version.
class VotingSupportedVersions {
  static const voteServer = {'v1'};
  static const voteProtocol = {'v0'};
  static const tally = {'v0'};
  static const pir = {'v0'};

  final List<String> pirVersions;
  final String voteProtocolVersion;
  final String tallyVersion;
  final String voteServerVersion;

  const VotingSupportedVersions({
    required this.pirVersions,
    required this.voteProtocolVersion,
    required this.tallyVersion,
    required this.voteServerVersion,
  });

  factory VotingSupportedVersions.fromJson(Map<String, dynamic> json) {
    return VotingSupportedVersions(
      pirVersions: _requiredListFromJson(json, const [
        'pir',
      ]).map((value) => value.toString()).toList(growable: false),
      voteProtocolVersion: _stringFromJson(json, const [
        'vote_protocol',
        'voteProtocol',
      ]),
      tallyVersion: _stringFromJson(json, const ['tally']),
      voteServerVersion: _stringFromJson(json, const [
        'vote_server',
        'voteServer',
      ]),
    );
  }

  void validate() {
    if (!voteServer.contains(voteServerVersion)) {
      throw VotingConfigUnsupportedVersion(
        component: 'vote_server',
        advertised: voteServerVersion,
      );
    }
    if (!voteProtocol.contains(voteProtocolVersion)) {
      throw VotingConfigUnsupportedVersion(
        component: 'vote_protocol',
        advertised: voteProtocolVersion,
      );
    }
    if (!tally.contains(tallyVersion)) {
      throw VotingConfigUnsupportedVersion(
        component: 'tally',
        advertised: tallyVersion,
      );
    }
    if (pirVersions.toSet().intersection(pir).isEmpty) {
      throw VotingConfigUnsupportedVersion(
        component: 'pir',
        advertised: pirVersions.join(','),
      );
    }
  }
}

/// Authenticated metadata for one round in the dynamic config registry.
class VotingRoundEntry {
  final int authVersion;
  final List<int> eaPk;
  final List<VotingRoundSignature> signatures;

  const VotingRoundEntry({
    required this.authVersion,
    required this.eaPk,
    required this.signatures,
  });

  factory VotingRoundEntry.fromJson(Map<String, dynamic> json) {
    return VotingRoundEntry(
      authVersion: _intFromJson(json, const ['auth_version', 'authVersion']),
      eaPk: _bytesFromJson(json, const ['ea_pk', 'eaPk']),
      signatures: (_listFromJson(json, const ['signatures']) ?? const [])
          .map(_objectFromValue)
          .map(VotingRoundSignature.fromJson)
          .toList(growable: false),
    );
  }
}

/// Signature over a dynamic-config round entry.
class VotingRoundSignature {
  final String keyId;
  final String alg;
  final List<int> sig;

  const VotingRoundSignature({
    required this.keyId,
    required this.alg,
    required this.sig,
  });

  factory VotingRoundSignature.fromJson(Map<String, dynamic> json) {
    return VotingRoundSignature(
      keyId: _stringFromJson(json, const ['key_id', 'keyId']),
      alg: _stringFromJson(json, const ['alg']),
      sig: _bytesFromJson(json, const ['sig']),
    );
  }
}

/// Thrown when config JSON is structurally invalid or internally inconsistent.
class VotingConfigDecodeException implements Exception {
  final String message;

  const VotingConfigDecodeException(this.message);

  @override
  String toString() => 'VotingConfigDecodeException: $message';
}

/// Thrown when config advertises a protocol version this app cannot use.
class VotingConfigUnsupportedVersion implements Exception {
  final String component;
  final String advertised;

  const VotingConfigUnsupportedVersion({
    required this.component,
    required this.advertised,
  });

  @override
  String toString() =>
      'VotingConfigUnsupportedVersion($component: $advertised)';
}

/// Lightweight round summary returned by list endpoints.
///
/// The raw object is kept so later provider/UI work can use newly added service
/// fields without forcing this low-level client model to change first.
class VotingRoundSummary {
  final String roundId;
  final String title;
  final String status;
  final Map<String, dynamic> rawJson;

  const VotingRoundSummary({
    required this.roundId,
    required this.title,
    required this.status,
    required this.rawJson,
  });

  factory VotingRoundSummary.fromJson(Map<String, dynamic> json) {
    return VotingRoundSummary(
      roundId:
          _optionalStringFromJson(json, const ['roundId', 'round_id', 'id']) ??
          '',
      title: _optionalStringFromJson(json, const ['title', 'name']) ?? '',
      status: _optionalStringFromJson(json, const ['status', 'phase']) ?? '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Current service-side status for a single round.
class VotingRoundStatus {
  final String roundId;
  final String status;
  final Map<String, dynamic> rawJson;

  const VotingRoundStatus({
    required this.roundId,
    required this.status,
    required this.rawJson,
  });

  factory VotingRoundStatus.fromJson(Map<String, dynamic> json) {
    return VotingRoundStatus(
      roundId:
          _optionalStringFromJson(json, const ['roundId', 'round_id', 'id']) ??
          '',
      status: _optionalStringFromJson(json, const ['status', 'phase']) ?? '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Raw tally payload for a finalized or tallying round.
class VotingRoundTally {
  final String roundId;
  final Map<String, dynamic> rawJson;

  const VotingRoundTally({required this.roundId, required this.rawJson});

  factory VotingRoundTally.fromJson(Map<String, dynamic> json) {
    return VotingRoundTally(
      roundId:
          _optionalStringFromJson(json, const ['roundId', 'round_id', 'id']) ??
          '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Response from a helper-server share submission.
class VotingShareSubmissionResult {
  final String shareId;
  final Map<String, dynamic> rawJson;

  const VotingShareSubmissionResult({
    required this.shareId,
    required this.rawJson,
  });

  factory VotingShareSubmissionResult.fromJson(Map<String, dynamic> json) {
    return VotingShareSubmissionResult(
      shareId:
          _optionalStringFromJson(json, const ['shareId', 'share_id', 'id']) ??
          '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Confirmation status for one helper-server share.
class VotingShareStatus {
  final String shareId;
  final String status;
  final Map<String, dynamic> rawJson;

  const VotingShareStatus({
    required this.shareId,
    required this.status,
    required this.rawJson,
  });

  factory VotingShareStatus.fromJson(Map<String, dynamic> json) {
    return VotingShareStatus(
      shareId:
          _optionalStringFromJson(json, const ['shareId', 'share_id', 'id']) ??
          '',
      status: _optionalStringFromJson(json, const ['status']) ?? '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// HTTP status error that preserves the response body for diagnostics.
class VotingHttpException implements Exception {
  final Uri uri;
  final int statusCode;
  final String body;

  const VotingHttpException({
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  @override
  String toString() => 'VotingHttpException($statusCode $uri): $body';
}

Map<String, dynamic> decodeVotingJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('Expected JSON object');
}

List<dynamic>? _listFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is List) return value;
    throw FormatException('$key must be a list');
  }
  return null;
}

Object _requiredValueFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) return value;
  }
  throw VotingConfigDecodeException('Missing required field: ${keys.first}');
}

List<dynamic> _requiredListFromJson(
  Map<String, dynamic> json,
  List<String> keys,
) {
  final value = _requiredValueFromJson(json, keys);
  if (value is List) return value;
  throw VotingConfigDecodeException('${keys.first} must be a list');
}

Uri? _uriFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _optionalStringFromJson(json, keys);
  return value == null || value.isEmpty ? null : Uri.parse(value);
}

Uri _requiredUriFromJson(Map<String, dynamic> json, List<String> keys) {
  final uri = _uriFromJson(json, keys);
  if (uri == null) {
    throw VotingConfigDecodeException('Missing required URI: ${keys.first}');
  }
  return uri;
}

String _stringFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _optionalStringFromJson(json, keys);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required string: ${keys.first}');
  }
  return value;
}

String? _optionalStringFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    return value.toString();
  }
  return null;
}

int _intFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
  throw FormatException('Missing required int: ${keys.first}');
}

List<int> _bytesFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _stringFromJson(json, keys);
  final hex = value.startsWith('0x') ? value.substring(2) : value;
  if (hex.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }
  return base64Decode(value);
}

Map<String, dynamic> _objectFromValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('Expected JSON object');
}

bool _isLowercaseHexRoundId(String value) {
  if (value.length != 64) return false;
  return RegExp(r'^[0-9a-f]+$').hasMatch(value);
}
