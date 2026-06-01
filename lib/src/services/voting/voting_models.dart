import 'dart:convert';

import '../../core/formatting/hex_codec.dart';

/// Hash-pinned trust anchor fetched before the mutable service config.
///
/// This config should be small and stable: it tells the app where to fetch the
/// dynamic config and carries the signing keys used by config resolution code
/// that validates signed round entries.
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
      staticConfigVersion: _intFromJson(json, const ['static_config_version']),
      dynamicConfigUrl: _requiredUriFromJson(json, const [
        'dynamic_config_url',
      ]),
      trustedKeys: _requiredListFromJson(json, const ['trusted_keys'])
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
    _validateDynamicConfigUrl(dynamicConfigUrl);
    if (trustedKeys.isEmpty) {
      throw const VotingConfigDecodeException(
        'trusted_keys must contain at least one entry',
      );
    }
    final keyIds = <String>{};
    for (final key in trustedKeys) {
      if (!keyIds.add(key.keyId)) {
        throw VotingConfigDecodeException(
          'trusted_keys contains duplicate key_id: ${key.keyId}',
        );
      }
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

  static void validateDynamicConfigUrl(Uri uri) {
    _validateDynamicConfigUrl(uri);
  }
}

/// Public key advertised for signed dynamic round entries.
///
/// This model layer only parses and validates the key shape. Signature
/// verification belongs in the config resolution layer that consumes these
/// fields.
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
      keyId: _stringFromJson(json, const ['key_id']),
      alg: _stringFromJson(json, const ['alg']),
      pubkey: _bytesFromJson(json, const ['pubkey']),
      notes: _optionalStringFromJson(json, const ['notes']),
    );
  }
}

/// Dynamic voting service configuration.
///
/// This is the network fetched registry for vote servers, PIR endpoints,
/// protocol versions, and signed round metadata. Missing required fields are
/// treated as decode failures so the app does not continue with partial service
/// state.
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
      configVersion: _intFromJson(json, const ['config_version']),
      voteServers: _requiredListFromJson(json, const ['vote_servers'])
          .map(_objectFromValue)
          .map(VotingServiceEndpoint.fromJson)
          .toList(growable: false),
      pirEndpoints: _requiredListFromJson(json, const ['pir_endpoints'])
          .map(_objectFromValue)
          .map(VotingServiceEndpoint.fromJson)
          .toList(growable: false),
      supportedVersions: VotingSupportedVersions.fromJson(
        _objectFromValue(
          _requiredValueFromJson(json, const ['supported_versions']),
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
    for (final endpoint in voteServers) {
      endpoint.validate(fieldName: 'vote_servers');
    }
    for (final endpoint in pirEndpoints) {
      endpoint.validate(fieldName: 'pir_endpoints');
    }
    for (final entry in rounds.entries) {
      final roundId = entry.key;
      if (!_isLowercaseHexRoundId(roundId)) {
        throw VotingConfigDecodeException(
          'rounds key must be 64 lowercase hex characters: $roundId',
        );
      }
      entry.value.validate(roundId: roundId);
    }
    supportedVersions.validate();
  }
}

/// Result returned by chain-facing submit endpoints.
///
/// A 2xx or accepted deterministic rejection can both carry this shape. Callers
/// must check [code] before treating [txHash] as a submitted transaction.
class VotingTxResult {
  final String txHash;
  final int code;
  final String log;

  const VotingTxResult({
    required this.txHash,
    required this.code,
    required this.log,
  });

  factory VotingTxResult.fromJson(Map<String, dynamic> json) {
    final code = _intFromJson(json, const ['code']);
    final txHash = _optionalStringFromJson(json, const ['tx_hash']) ?? '';
    if (code == 0 && txHash.trim().isEmpty) {
      throw const FormatException('Missing required string: tx_hash');
    }
    return VotingTxResult(
      txHash: txHash,
      code: code,
      log: _optionalStringFromJson(json, const ['log']) ?? '',
    );
  }
}

/// Confirmation query result for a submitted voting transaction.
class VotingTxConfirmation {
  final int height;
  final int code;
  final String log;
  final List<VotingTxEvent> events;

  const VotingTxConfirmation({
    required this.height,
    required this.code,
    required this.log,
    required this.events,
  });

  factory VotingTxConfirmation.fromJson(Map<String, dynamic> json) {
    return VotingTxConfirmation(
      height: _intFromJson(json, const ['height']),
      code: _intFromJson(json, const ['code']),
      log: _optionalStringFromJson(json, const ['log']) ?? '',
      events: _optionalListFromJson(json, const ['events'])
          .map(_objectFromValue)
          .map(VotingTxEvent.fromJson)
          .toList(growable: false),
    );
  }

  VotingTxEvent? event(String type) {
    for (final event in events) {
      if (event.type == type) return event;
    }
    return null;
  }
}

/// Event emitted by the vote chain for a confirmed voting transaction.
class VotingTxEvent {
  final String type;
  final List<VotingTxEventAttribute> attributes;

  const VotingTxEvent({required this.type, required this.attributes});

  factory VotingTxEvent.fromJson(Map<String, dynamic> json) {
    return VotingTxEvent(
      type: _stringFromJson(json, const ['type']),
      attributes: _optionalListFromJson(json, const ['attributes'])
          .map(_objectFromValue)
          .map(VotingTxEventAttribute.fromJson)
          .toList(growable: false),
    );
  }

  String? attribute(String key) {
    for (final attribute in attributes) {
      if (attribute.key == key) return attribute.value;
    }
    return null;
  }
}

/// Key/value attribute attached to a voting transaction event.
class VotingTxEventAttribute {
  final String key;
  final String value;

  const VotingTxEventAttribute({required this.key, required this.value});

  factory VotingTxEventAttribute.fromJson(Map<String, dynamic> json) {
    return VotingTxEventAttribute(
      key: _stringFromJson(json, const ['key']),
      value: _stringFromJson(json, const ['value']),
    );
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
      url: _normalizedServiceEndpointUrl(url, fieldName: 'service endpoint'),
      label: _optionalStringFromJson(json, const ['label', 'name']) ?? '',
    );
  }

  void validate({required String fieldName}) {
    _normalizedServiceEndpointUrl(url, fieldName: fieldName);
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
      voteProtocolVersion: _stringFromJson(json, const ['vote_protocol']),
      tallyVersion: _stringFromJson(json, const ['tally']),
      voteServerVersion: _stringFromJson(json, const ['vote_server']),
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

/// Signed metadata for one round in the dynamic config registry.
///
/// This model preserves the signed fields. The config resolution layer is
/// responsible for verifying the signatures before higher layers trust them.
class VotingRoundEntry {
  static const supportedAuthVersion = 1;

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
      authVersion: _intFromJson(json, const ['auth_version']),
      eaPk: _bytesFromJson(json, const ['ea_pk']),
      signatures: (_listFromJson(json, const ['signatures']) ?? const [])
          .map(_objectFromValue)
          .map(VotingRoundSignature.fromJson)
          .toList(growable: false),
    );
  }

  void validate({required String roundId}) {
    if (authVersion != supportedAuthVersion) {
      throw VotingConfigDecodeException(
        'rounds[$roundId].auth_version unsupported: $authVersion',
      );
    }
    if (eaPk.length != 32) {
      throw VotingConfigDecodeException(
        'rounds[$roundId].ea_pk must decode to 32 bytes',
      );
    }
    if (signatures.isEmpty) {
      throw VotingConfigDecodeException(
        'rounds[$roundId].signatures must contain at least one entry',
      );
    }
    for (final signature in signatures) {
      signature.validate(roundId: roundId);
    }
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
      keyId: _stringFromJson(json, const ['key_id']),
      alg: _stringFromJson(json, const ['alg']),
      sig: _bytesFromJson(json, const ['sig']),
    );
  }

  void validate({required String roundId}) {
    if (alg != StaticVotingConfig.algEd25519) {
      throw VotingConfigDecodeException(
        'rounds[$roundId].signatures[$keyId].alg unsupported: $alg',
      );
    }
    if (sig.length != 64) {
      throw VotingConfigDecodeException(
        'rounds[$roundId].signatures[$keyId].sig must decode to 64 bytes',
      );
    }
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
      roundId: _roundIdFromJson(json),
      title: _optionalStringFromJson(json, const ['title']) ?? '',
      status: _optionalStringFromJson(json, const ['status']) ?? '',
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
      roundId: _roundIdFromJson(json),
      status: _stringFromJson(json, const ['status']),
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Raw tally payload for a finalized or tallying round.
class VotingRoundTally {
  final String roundId;
  final Map<String, dynamic> rawJson;

  const VotingRoundTally({required this.roundId, required this.rawJson});

  factory VotingRoundTally.fromJson(
    Map<String, dynamic> json, {
    String? fallbackRoundId,
  }) {
    return VotingRoundTally(
      roundId: _optionalRoundIdFromJson(json) ?? fallbackRoundId ?? '',
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Response from a helper-server share submission.
class VotingShareSubmissionResult {
  static const _acceptedStatuses = {'queued', 'duplicate'};

  final String status;
  final Map<String, dynamic> rawJson;

  const VotingShareSubmissionResult({
    required this.status,
    required this.rawJson,
  });

  factory VotingShareSubmissionResult.fromJson(Map<String, dynamic> json) {
    final status = _stringFromJson(json, const ['status']);
    if (!_acceptedStatuses.contains(status)) {
      throw FormatException('Unexpected helper share submit status: $status');
    }
    return VotingShareSubmissionResult(
      status: status,
      rawJson: Map.unmodifiable(json),
    );
  }
}

/// Confirmation status for one helper-server share.
class VotingShareStatus {
  static const _acceptedStatuses = {'pending', 'confirmed'};

  final String status;
  final Map<String, dynamic> rawJson;

  const VotingShareStatus({required this.status, required this.rawJson});

  factory VotingShareStatus.fromJson(Map<String, dynamic> json) {
    final status = _stringFromJson(json, const ['status']);
    if (!_acceptedStatuses.contains(status)) {
      throw FormatException('Unexpected helper share status: $status');
    }
    return VotingShareStatus(status: status, rawJson: Map.unmodifiable(json));
  }
}

/// Normalizes a vote round id to the lowercase hex form used in service routes.
///
/// Accepts either 64 hex characters or a 32-byte base64 string. Throws a
/// [FormatException] when the input is not one of those encodings.
String normalizeVotingRoundId(String value) => _normalizeRoundId(value);

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
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : Uri.parse(trimmed);
}

Uri _requiredUriFromJson(Map<String, dynamic> json, List<String> keys) {
  final uri = _uriFromJson(json, keys);
  if (uri == null) {
    throw VotingConfigDecodeException('Missing required URI: ${keys.first}');
  }
  return uri;
}

Uri _normalizedServiceEndpointUrl(Uri uri, {required String fieldName}) {
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw VotingConfigDecodeException(
      '$fieldName URL must be an absolute HTTP(S) URL: $uri',
    );
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    throw VotingConfigDecodeException(
      '$fieldName URL has unsupported scheme "$scheme": $uri',
    );
  }
  if (scheme == 'http' && !_allowsPlainHttp(uri.host)) {
    throw VotingConfigDecodeException(
      '$fieldName URL must use HTTPS except for localhost/regtest: $uri',
    );
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw VotingConfigDecodeException(
      '$fieldName URL must not include query or fragment: $uri',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw VotingConfigDecodeException(
      '$fieldName URL must not include user info: $uri',
    );
  }

  final normalized = uri.normalizePath().replace(
    scheme: scheme,
    host: uri.host.toLowerCase(),
  );
  return Uri.parse(normalized.toString().replaceFirst(RegExp(r'/+$'), ''));
}

bool _allowsPlainHttp(String host) {
  final lower = host.toLowerCase();
  return lower == 'localhost' ||
      lower.endsWith('.localhost') ||
      lower == '127.0.0.1' ||
      lower == '::1' ||
      lower == 'regtest' ||
      lower.endsWith('.regtest');
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

String _roundIdFromJson(Map<String, dynamic> json) {
  final value = _optionalRoundIdFromJson(json);
  if (value == null || value.isEmpty) {
    throw const FormatException('Missing required string: vote_round_id');
  }
  return value;
}

String? _optionalRoundIdFromJson(Map<String, dynamic> json) {
  final value = _optionalStringFromJson(json, const ['vote_round_id']);
  final raw = value?.trim();
  return raw == null || raw.isEmpty ? null : _normalizeRoundId(raw);
}

void _validateDynamicConfigUrl(Uri uri) {
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw VotingConfigDecodeException(
      'dynamic_config_url must be an absolute HTTP(S) URL: $uri',
    );
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    throw VotingConfigDecodeException(
      'dynamic_config_url has unsupported scheme "$scheme": $uri',
    );
  }
  if (scheme == 'http' && !_allowsPlainHttp(uri.host)) {
    throw VotingConfigDecodeException(
      'dynamic_config_url must use HTTPS except for localhost/regtest: $uri',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw VotingConfigDecodeException(
      'dynamic_config_url must not include user info: $uri',
    );
  }
  if (uri.hasFragment) {
    throw VotingConfigDecodeException(
      'dynamic_config_url must not include a fragment: $uri',
    );
  }
}

String _normalizeRoundId(String value) {
  final trimmed = value.trim();
  if (_isHexRoundId(trimmed)) return trimmed.toLowerCase();
  try {
    final bytes = base64Decode(trimmed);
    if (bytes.length == 32) return bytesToHex(bytes);
  } on FormatException {
    // Fall through to a field-specific error below.
  }
  throw const FormatException(
    'Invalid vote_round_id: expected 64 hex chars or 32-byte base64',
  );
}

int _intFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _optionalIntFromJson(json, keys);
  if (value == null) {
    throw FormatException('Missing required int: ${keys.first}');
  }
  return value;
}

int? _optionalIntFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) {
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      throw FormatException('$key must be an integer');
    }
    return int.parse(value.toString());
  }
  return null;
}

List<Object?> _optionalListFromJson(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is List) return value;
    throw FormatException('Expected list: $key');
  }
  return const [];
}

List<int> _bytesFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _stringFromJson(json, keys);
  try {
    return base64Decode(value);
  } on FormatException catch (error) {
    throw FormatException('${keys.first} must be base64: ${error.message}');
  }
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

bool _isHexRoundId(String value) {
  if (value.length != 64) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
}
