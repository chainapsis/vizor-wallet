import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';
import '../rust/api/multisig.dart' as rust_multisig;
import 'multisig_account_material_provider.dart';

const kDefaultMultisigCoordinatorUrl = String.fromEnvironment(
  'ZCASH_MULTISIG_COORDINATOR_URL',
  defaultValue: 'http://127.0.0.1:3001',
);

enum MultisigPendingRole {
  creator,
  participant;

  static MultisigPendingRole parse(String value) => switch (value) {
    'creator' => MultisigPendingRole.creator,
    'participant' => MultisigPendingRole.participant,
    _ => throw FormatException('Unknown multisig pending role: $value.'),
  };
}

class MultisigPendingParticipant {
  const MultisigPendingParticipant({
    required this.participantId,
    required this.admissionPublicKey,
    required this.deliveryPublicKey,
    required this.joinedAt,
    required this.dkgCompleted,
    this.label,
  });

  final String participantId;
  final String? label;
  final String admissionPublicKey;
  final String deliveryPublicKey;
  final int joinedAt;
  final bool dkgCompleted;

  String get displayName {
    final trimmed = label?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return shortParticipantId;
  }

  String get shortParticipantId => participantId.length <= 8
      ? participantId
      : '${participantId.substring(0, 4)}...${participantId.substring(participantId.length - 4)}';

  Map<String, Object?> toJson() => {
    'participantId': participantId,
    'label': label,
    'admissionPublicKey': admissionPublicKey,
    'deliveryPublicKey': deliveryPublicKey,
    'joinedAt': joinedAt,
    'dkgCompleted': dkgCompleted,
  };

  static MultisigPendingParticipant fromJson(Map<String, Object?> json) {
    return MultisigPendingParticipant(
      participantId: _readRequiredString(
        json,
        'participantId',
        'Multisig pending participant',
      ),
      label: json['label'] as String?,
      admissionPublicKey: _readRequiredString(
        json,
        'admissionPublicKey',
        'Multisig pending participant',
      ),
      deliveryPublicKey: _readRequiredString(
        json,
        'deliveryPublicKey',
        'Multisig pending participant',
      ),
      joinedAt: _readRequiredInt(
        json,
        'joinedAt',
        'Multisig pending participant',
      ),
      dkgCompleted: _readRequiredBool(
        json,
        'dkgCompleted',
        'Multisig pending participant',
      ),
    );
  }

  static MultisigPendingParticipant fromApi(
    rust_multisig.ApiMultisigParticipant value,
  ) {
    return MultisigPendingParticipant(
      participantId: value.participantId,
      label: value.label,
      admissionPublicKey: value.admissionPublicKey,
      deliveryPublicKey: value.deliveryPublicKey,
      joinedAt: value.joinedAt.toInt(),
      dkgCompleted: value.dkgCompleted,
    );
  }
}

class MultisigPendingSession {
  const MultisigPendingSession({
    required this.sessionId,
    required this.participantId,
    required this.role,
    required this.coordinatorUrl,
    required this.state,
    required this.accessToken,
    required this.refreshToken,
    required this.identity,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
    required this.createdLocallyAt,
    required this.updatedLocallyAt,
    this.localBackupCompleted = false,
    this.localBackupCompletedAt,
    this.localBackupVersion = 2,
    this.localBackupHash,
    this.localBackupVerifiedAt,
    this.localBackupDestinations = const <String>[],
    this.label,
    this.creatorParticipantId,
    this.threshold,
    this.rosterHash,
    this.groupPublicPackageHash,
  });

  final String sessionId;
  final String participantId;
  final MultisigPendingRole role;
  final String coordinatorUrl;
  final String? label;
  final String state;
  final String accessToken;
  final String refreshToken;
  final MultisigParticipantIdentity identity;
  final int accessTokenExpiresAt;
  final int refreshTokenExpiresAt;
  final String? creatorParticipantId;
  final int? threshold;
  final String? rosterHash;
  final String? groupPublicPackageHash;
  final List<MultisigPendingParticipant> participants;
  final int createdAt;
  final int updatedAt;
  final int createdLocallyAt;
  final int updatedLocallyAt;
  final bool localBackupCompleted;
  final int? localBackupCompletedAt;
  final int localBackupVersion;
  final String? localBackupHash;
  final int? localBackupVerifiedAt;
  final List<String> localBackupDestinations;

  String get storageId => '$sessionId:$participantId';
  bool get isCreator => participantId == creatorParticipantId;
  bool get isTerminal => state == 'ready' || state == 'failed';
  bool get isPending => !isTerminal;

  String get displayLabel {
    final trimmed = label?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'Multisig session';
  }

  String get shortSessionId => sessionId.length <= 12
      ? sessionId
      : '${sessionId.substring(0, 6)}...${sessionId.substring(sessionId.length - 6)}';

  MultisigPendingSession copyWith({
    String? state,
    String? accessToken,
    String? refreshToken,
    MultisigParticipantIdentity? identity,
    int? accessTokenExpiresAt,
    int? refreshTokenExpiresAt,
    String? creatorParticipantId,
    int? threshold,
    String? rosterHash,
    String? groupPublicPackageHash,
    List<MultisigPendingParticipant>? participants,
    int? createdAt,
    int? updatedAt,
    int? updatedLocallyAt,
    bool? localBackupCompleted,
    int? localBackupCompletedAt,
    int? localBackupVersion,
    String? localBackupHash,
    int? localBackupVerifiedAt,
    List<String>? localBackupDestinations,
  }) {
    return MultisigPendingSession(
      sessionId: sessionId,
      participantId: participantId,
      role: role,
      coordinatorUrl: coordinatorUrl,
      label: label,
      state: state ?? this.state,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      identity: identity ?? this.identity,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      refreshTokenExpiresAt:
          refreshTokenExpiresAt ?? this.refreshTokenExpiresAt,
      creatorParticipantId: creatorParticipantId ?? this.creatorParticipantId,
      threshold: threshold ?? this.threshold,
      rosterHash: rosterHash ?? this.rosterHash,
      groupPublicPackageHash:
          groupPublicPackageHash ?? this.groupPublicPackageHash,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdLocallyAt: createdLocallyAt,
      updatedLocallyAt: updatedLocallyAt ?? this.updatedLocallyAt,
      localBackupCompleted: localBackupCompleted ?? this.localBackupCompleted,
      localBackupCompletedAt:
          localBackupCompletedAt ?? this.localBackupCompletedAt,
      localBackupVersion: localBackupVersion ?? this.localBackupVersion,
      localBackupHash: localBackupHash ?? this.localBackupHash,
      localBackupVerifiedAt:
          localBackupVerifiedAt ?? this.localBackupVerifiedAt,
      localBackupDestinations:
          localBackupDestinations ?? this.localBackupDestinations,
    );
  }

  MultisigPendingSession applySession(rust_multisig.ApiMultisigSession value) {
    return copyWith(
      state: value.state,
      creatorParticipantId: value.creatorParticipantId,
      threshold: value.threshold,
      rosterHash: value.rosterHash,
      groupPublicPackageHash: value.groupPublicPackageHash,
      participants: value.participants
          .map(MultisigPendingParticipant.fromApi)
          .toList(growable: false),
      createdAt: value.createdAt.toInt(),
      updatedAt: value.updatedAt.toInt(),
      updatedLocallyAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  MultisigPendingSession applyAuthUpdate(
    rust_multisig.ApiMultisigAuthUpdate value,
  ) {
    return copyWith(
      accessToken: value.accessToken,
      refreshToken: value.refreshToken,
      identity: MultisigParticipantIdentity(
        admissionSecretKey: identity.admissionSecretKey,
        admissionPublicKey: value.admissionPublicKey,
        deliverySecretKey: value.deliverySecretKey,
        deliveryPublicKey: value.deliveryPublicKey,
      ),
      accessTokenExpiresAt: value.accessTokenExpiresAt.toInt(),
      refreshTokenExpiresAt: value.refreshTokenExpiresAt.toInt(),
      updatedLocallyAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'participantId': participantId,
    'role': role.name,
    'coordinatorUrl': coordinatorUrl,
    'label': label,
    'state': state,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'identity': identity.toJson(),
    'accessTokenExpiresAt': accessTokenExpiresAt,
    'refreshTokenExpiresAt': refreshTokenExpiresAt,
    'creatorParticipantId': creatorParticipantId,
    'threshold': threshold,
    'rosterHash': rosterHash,
    'groupPublicPackageHash': groupPublicPackageHash,
    'participants': participants.map((entry) => entry.toJson()).toList(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'createdLocallyAt': createdLocallyAt,
    'updatedLocallyAt': updatedLocallyAt,
    'localBackupCompleted': localBackupCompleted,
    'localBackupCompletedAt': localBackupCompletedAt,
    'localBackupVersion': localBackupVersion,
    'localBackupHash': localBackupHash,
    'localBackupVerifiedAt': localBackupVerifiedAt,
    'localBackupDestinations': localBackupDestinations,
  };

  String toStorageJson() => jsonEncode(toJson());

  static MultisigPendingSession fromJson(Map<String, Object?> json) {
    final participantsJson = json['participants'];
    if (participantsJson is! List) {
      throw const FormatException(
        'Multisig pending session is missing participants.',
      );
    }
    final participants = participantsJson
        .map((entry) {
          if (entry is! Map) {
            throw const FormatException(
              'Multisig pending session has a malformed participant.',
            );
          }
          return MultisigPendingParticipant.fromJson(
            entry.cast<String, Object?>(),
          );
        })
        .toList(growable: false);
    final localBackupVersion = _readInt(json['localBackupVersion']);
    return MultisigPendingSession(
      sessionId: _readRequiredString(
        json,
        'sessionId',
        'Multisig pending session',
      ),
      participantId: _readRequiredString(
        json,
        'participantId',
        'Multisig pending session',
      ),
      role: MultisigPendingRole.parse(
        _readRequiredString(json, 'role', 'Multisig pending session'),
      ),
      coordinatorUrl: _readRequiredString(
        json,
        'coordinatorUrl',
        'Multisig pending session',
      ),
      label: json['label'] as String?,
      state: _readRequiredString(json, 'state', 'Multisig pending session'),
      accessToken: _readRequiredString(
        json,
        'accessToken',
        'Multisig pending session',
      ),
      refreshToken: _readRequiredString(
        json,
        'refreshToken',
        'Multisig pending session',
      ),
      identity: _readIdentity(json['identity']),
      accessTokenExpiresAt: _readRequiredInt(
        json,
        'accessTokenExpiresAt',
        'Multisig pending session',
      ),
      refreshTokenExpiresAt: _readRequiredInt(
        json,
        'refreshTokenExpiresAt',
        'Multisig pending session',
      ),
      creatorParticipantId: json['creatorParticipantId'] as String?,
      threshold: _readNullableInt(json['threshold']),
      rosterHash: json['rosterHash'] as String?,
      groupPublicPackageHash: json['groupPublicPackageHash'] as String?,
      participants: participants,
      createdAt: _readRequiredInt(
        json,
        'createdAt',
        'Multisig pending session',
      ),
      updatedAt: _readRequiredInt(
        json,
        'updatedAt',
        'Multisig pending session',
      ),
      createdLocallyAt: _readRequiredInt(
        json,
        'createdLocallyAt',
        'Multisig pending session',
      ),
      updatedLocallyAt: _readRequiredInt(
        json,
        'updatedLocallyAt',
        'Multisig pending session',
      ),
      localBackupCompleted: json['localBackupCompleted'] as bool? ?? false,
      localBackupCompletedAt: _readNullableInt(json['localBackupCompletedAt']),
      localBackupVersion: localBackupVersion <= 0 ? 2 : localBackupVersion,
      localBackupHash: json['localBackupHash'] as String?,
      localBackupVerifiedAt: _readNullableInt(json['localBackupVerifiedAt']),
      localBackupDestinations: _readStringList(json['localBackupDestinations']),
    );
  }

  static MultisigPendingSession fromStorageJson(String raw) {
    return fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
  }

  static MultisigPendingSession fromAuth({
    required rust_multisig.ApiMultisigAuthSession auth,
    required MultisigPendingRole role,
    required String coordinatorUrl,
    required String? label,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final participant = MultisigPendingParticipant.fromApi(auth.participant);
    return MultisigPendingSession(
      sessionId: auth.sessionId,
      participantId: auth.participantId,
      role: role,
      coordinatorUrl: coordinatorUrl,
      label: label,
      state: auth.state,
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      identity: MultisigParticipantIdentity(
        admissionSecretKey: auth.admissionSecretKey,
        admissionPublicKey: auth.admissionPublicKey,
        deliverySecretKey: auth.deliverySecretKey,
        deliveryPublicKey: auth.deliveryPublicKey,
      ),
      accessTokenExpiresAt: auth.accessTokenExpiresAt.toInt(),
      refreshTokenExpiresAt: auth.refreshTokenExpiresAt.toInt(),
      creatorParticipantId: role == MultisigPendingRole.creator
          ? auth.participantId
          : null,
      participants: [participant],
      createdAt: 0,
      updatedAt: 0,
      createdLocallyAt: now,
      updatedLocallyAt: now,
    );
  }
}

class MultisigPendingSessionStore {
  const MultisigPendingSessionStore(this._storage);

  final AppSecureStore _storage;

  Future<MultisigPendingSession?> read(
    String storageId, {
    bool requireUnlockedSession = true,
  }) async {
    final raw = await _storage.readMultisigPendingSession(
      storageId,
      requireUnlockedSession: requireUnlockedSession,
    );
    if (raw == null || raw.isEmpty) return null;
    return MultisigPendingSession.fromStorageJson(raw);
  }

  Future<List<MultisigPendingSession>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    final raw = await _storage.readAllMultisigPendingSessions(
      requireUnlockedSession: requireUnlockedSession,
    );
    return raw.values
        .map(MultisigPendingSession.fromStorageJson)
        .toList(growable: false);
  }

  Future<void> write(MultisigPendingSession session) {
    return _storage.writeMultisigPendingSession(
      session.storageId,
      session.toStorageJson(),
    );
  }

  Future<void> delete(MultisigPendingSession session) {
    return _storage.deleteMultisigPendingSession(session.storageId);
  }

  Future<void> deleteByStorageId(String storageId) {
    return _storage.deleteMultisigPendingSession(storageId);
  }
}

final multisigPendingSessionStoreProvider =
    Provider<MultisigPendingSessionStore>(
      (ref) => MultisigPendingSessionStore(AppSecureStore.instance),
    );

MultisigParticipantIdentity _readIdentity(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'Multisig pending session is missing identity.',
    );
  }
  return MultisigParticipantIdentity.fromJson(value.cast<String, Object?>());
}

String _readRequiredString(
  Map<String, Object?> json,
  String key,
  String recordName,
) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$recordName is missing $key.');
  }
  return value;
}

int _readRequiredInt(Map<String, Object?> json, String key, String recordName) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$recordName is missing $key.');
}

bool _readRequiredBool(
  Map<String, Object?> json,
  String key,
  String recordName,
) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('$recordName is missing $key.');
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
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
