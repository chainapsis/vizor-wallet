import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';
import 'app_security_provider.dart';

class MultisigParticipantIdentity {
  const MultisigParticipantIdentity({
    required this.admissionSecretKey,
    required this.admissionPublicKey,
    required this.deliverySecretKey,
    required this.deliveryPublicKey,
  });

  final String admissionSecretKey;
  final String admissionPublicKey;
  final String deliverySecretKey;
  final String deliveryPublicKey;

  Map<String, Object?> toJson() => {
    'admissionSecretKey': admissionSecretKey,
    'admissionPublicKey': admissionPublicKey,
    'deliverySecretKey': deliverySecretKey,
    'deliveryPublicKey': deliveryPublicKey,
  };

  static MultisigParticipantIdentity fromJson(Map<String, Object?> json) {
    return MultisigParticipantIdentity(
      admissionSecretKey: _readRequiredIdentityString(
        json,
        'admissionSecretKey',
      ),
      admissionPublicKey: _readRequiredIdentityString(
        json,
        'admissionPublicKey',
      ),
      deliverySecretKey: _readRequiredIdentityString(json, 'deliverySecretKey'),
      deliveryPublicKey: _readRequiredIdentityString(json, 'deliveryPublicKey'),
    );
  }
}

class MultisigAccountMaterial {
  const MultisigAccountMaterial({
    required this.accountUuid,
    required this.sessionId,
    required this.participantId,
    required this.coordinatorUrl,
    required this.rosterHash,
    required this.groupPublicPackageHash,
    required this.threshold,
    required this.participantCount,
    required this.identity,
    required this.keyPackageB64,
    required this.groupPublicPackageJson,
    required this.vaultAddress,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
    this.localBackupHash,
    this.localBackupCompletedAt,
    this.localBackupVerifiedAt,
    this.localBackupDestinations = const <String>[],
  });

  final String accountUuid;
  final String sessionId;
  final String participantId;
  final String coordinatorUrl;
  final String rosterHash;
  final String groupPublicPackageHash;
  final int threshold;
  final int participantCount;
  final MultisigParticipantIdentity identity;
  final String keyPackageB64;
  final String groupPublicPackageJson;
  final String vaultAddress;
  final String accessToken;
  final String refreshToken;
  final int accessTokenExpiresAt;
  final int refreshTokenExpiresAt;
  final String? localBackupHash;
  final int? localBackupCompletedAt;
  final int? localBackupVerifiedAt;
  final List<String> localBackupDestinations;

  String get storageId => '$sessionId:$participantId';

  MultisigAccountMaterial copyWith({
    MultisigParticipantIdentity? identity,
    String? accessToken,
    String? refreshToken,
    int? accessTokenExpiresAt,
    int? refreshTokenExpiresAt,
    String? localBackupHash,
    int? localBackupCompletedAt,
    int? localBackupVerifiedAt,
    List<String>? localBackupDestinations,
  }) {
    return MultisigAccountMaterial(
      accountUuid: accountUuid,
      sessionId: sessionId,
      participantId: participantId,
      coordinatorUrl: coordinatorUrl,
      rosterHash: rosterHash,
      groupPublicPackageHash: groupPublicPackageHash,
      threshold: threshold,
      participantCount: participantCount,
      identity: identity ?? this.identity,
      keyPackageB64: keyPackageB64,
      groupPublicPackageJson: groupPublicPackageJson,
      vaultAddress: vaultAddress,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      refreshTokenExpiresAt:
          refreshTokenExpiresAt ?? this.refreshTokenExpiresAt,
      localBackupHash: localBackupHash ?? this.localBackupHash,
      localBackupCompletedAt:
          localBackupCompletedAt ?? this.localBackupCompletedAt,
      localBackupVerifiedAt:
          localBackupVerifiedAt ?? this.localBackupVerifiedAt,
      localBackupDestinations:
          localBackupDestinations ?? this.localBackupDestinations,
    );
  }

  Map<String, Object?> toJson() => {
    'accountUuid': accountUuid,
    'sessionId': sessionId,
    'participantId': participantId,
    'coordinatorUrl': coordinatorUrl,
    'rosterHash': rosterHash,
    'groupPublicPackageHash': groupPublicPackageHash,
    'threshold': threshold,
    'participantCount': participantCount,
    'identity': identity.toJson(),
    'keyPackageB64': keyPackageB64,
    'groupPublicPackageJson': groupPublicPackageJson,
    'vaultAddress': vaultAddress,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'accessTokenExpiresAt': accessTokenExpiresAt,
    'refreshTokenExpiresAt': refreshTokenExpiresAt,
    'localBackupHash': localBackupHash,
    'localBackupCompletedAt': localBackupCompletedAt,
    'localBackupVerifiedAt': localBackupVerifiedAt,
    'localBackupDestinations': localBackupDestinations,
  };

  String toStorageJson() => jsonEncode(toJson());

  static MultisigAccountMaterial fromJson(Map<String, Object?> json) {
    final threshold = _readRequiredInt(json, 'threshold');
    final participantCount = _readRequiredInt(json, 'participantCount');
    if (threshold <= 0) {
      throw const FormatException('Multisig threshold must be positive.');
    }
    if (participantCount <= 0) {
      throw const FormatException(
        'Multisig participant count must be positive.',
      );
    }
    return MultisigAccountMaterial(
      accountUuid: _readRequiredString(json, 'accountUuid'),
      sessionId: _readRequiredString(json, 'sessionId'),
      participantId: _readRequiredString(json, 'participantId'),
      coordinatorUrl: _readRequiredString(json, 'coordinatorUrl'),
      rosterHash: _readRequiredString(json, 'rosterHash'),
      groupPublicPackageHash: _readRequiredString(
        json,
        'groupPublicPackageHash',
      ),
      threshold: threshold,
      participantCount: participantCount,
      identity: _readIdentity(json['identity']),
      keyPackageB64: _readRequiredString(json, 'keyPackageB64'),
      groupPublicPackageJson: _readRequiredString(
        json,
        'groupPublicPackageJson',
      ),
      vaultAddress: _readRequiredString(json, 'vaultAddress'),
      accessToken: _readRequiredString(json, 'accessToken'),
      refreshToken: _readRequiredString(json, 'refreshToken'),
      accessTokenExpiresAt: _readRequiredInt(json, 'accessTokenExpiresAt'),
      refreshTokenExpiresAt: _readRequiredInt(json, 'refreshTokenExpiresAt'),
      localBackupHash: json['localBackupHash'] as String?,
      localBackupCompletedAt: _readNullableInt(json['localBackupCompletedAt']),
      localBackupVerifiedAt: _readNullableInt(json['localBackupVerifiedAt']),
      localBackupDestinations: _readStringList(json['localBackupDestinations']),
    );
  }

  static MultisigAccountMaterial fromStorageJson(String raw) {
    return fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
  }
}

class MultisigAccountMaterialStore {
  const MultisigAccountMaterialStore(this._storage);

  final AppSecureStore _storage;

  Future<MultisigAccountMaterial?> read(
    String accountUuid, {
    bool requireUnlockedSession = true,
  }) async {
    final raw = await _storage.readMultisigMaterial(
      accountUuid,
      requireUnlockedSession: requireUnlockedSession,
    );
    if (raw == null || raw.isEmpty) return null;
    return MultisigAccountMaterial.fromStorageJson(raw);
  }

  Future<List<MultisigAccountMaterial>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    final raw = await _storage.readAllMultisigMaterials(
      requireUnlockedSession: requireUnlockedSession,
    );
    return raw.values
        .map(MultisigAccountMaterial.fromStorageJson)
        .toList(growable: false);
  }

  Future<void> write(MultisigAccountMaterial material) {
    return _storage.writeMultisigMaterial(
      material.accountUuid,
      material.toStorageJson(),
    );
  }

  Future<void> delete(String accountUuid) {
    return _storage.deleteMultisigMaterial(accountUuid);
  }
}

final multisigAccountMaterialStoreProvider =
    Provider<MultisigAccountMaterialStore>(
      (ref) => MultisigAccountMaterialStore(AppSecureStore.instance),
    );

final multisigAccountMaterialsProvider =
    FutureProvider<List<MultisigAccountMaterial>>((ref) {
      final security = ref.watch(appSecurityProvider);
      if (security.requiresUnlock) return const <MultisigAccountMaterial>[];
      return ref.watch(multisigAccountMaterialStoreProvider).readAll();
    });

bool multisigMaterialBackupCompleted(MultisigAccountMaterial material) {
  return material.localBackupCompletedAt != null;
}

Set<String> materializedMultisigSessionStorageIds(
  Iterable<MultisigAccountMaterial> materials,
) {
  return materials.map((material) => material.storageId).toSet();
}

String _readRequiredIdentityString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Multisig identity is missing $key.');
  }
  return value;
}

String _readRequiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Multisig account material is missing $key.');
  }
  return value;
}

int _readRequiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Multisig account material is missing $key.');
}

MultisigParticipantIdentity _readIdentity(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'Multisig account material is missing identity.',
    );
  }
  return MultisigParticipantIdentity.fromJson(value.cast<String, Object?>());
}

int? _readNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}
