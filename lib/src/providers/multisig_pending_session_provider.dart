import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/storage/app_secure_store.dart';
import '../rust/api/multisig.dart' as rust_multisig;
import 'app_security_provider.dart';
import 'multisig_account_material_provider.dart';
import 'multisig_coordinator_service.dart';
import 'multisig_operation_error.dart';
import 'multisig_realtime_cursor_store.dart';

const kDefaultMultisigCoordinatorUrl = String.fromEnvironment(
  'ZCASH_MULTISIG_COORDINATOR_URL',
  defaultValue: 'http://127.0.0.1:3001',
);

const _multisigCreateStateStoragePrefix = 'zcash_multisig_create_state_v1_';
const _accessTokenRefreshSkewSeconds = 30;

/// The invite code shared out-of-band IS the session secret: a single
/// base64url token. The session id is derived from it locally, labels are
/// sealed under it, and the coordinator never sees it.
String normalizeMultisigInviteCode(String value) {
  final trimmed = value.trim();
  const inviteCodeLength = 22; // 16-byte secret, base64url no-pad
  final valid =
      trimmed.length == inviteCodeLength &&
      trimmed.codeUnits.every(_isBase64UrlCodeUnit);
  if (!valid) {
    throw const FormatException('Invite code is not valid.');
  }
  return trimmed;
}

bool _isBase64UrlCodeUnit(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
      (codeUnit >= 0x41 && codeUnit <= 0x5a) || // A-Z
      (codeUnit >= 0x61 && codeUnit <= 0x7a) || // a-z
      codeUnit == 0x2d || // -
      codeUnit == 0x5f; // _
}

typedef MultisigNow = DateTime Function();

final multisigNowProvider = Provider<MultisigNow>((ref) => DateTime.now);

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
    required this.inviteSecret,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
    required this.createdLocallyAt,
    required this.updatedLocallyAt,
    this.vaultLabelPostedAt,
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
    this.keyPackageB64,
    this.groupPublicPackageJson,
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

  /// Out-of-band session secret from the invite code. Seals participant
  /// labels so the coordinator never sees them. Lives only as long as this
  /// pending session; after finalize the vault metadata key takes over.
  final String inviteSecret;
  final int accessTokenExpiresAt;
  final int refreshTokenExpiresAt;
  final String? creatorParticipantId;
  final int? threshold;
  final String? rosterHash;
  final String? keyPackageB64;
  final String? groupPublicPackageJson;
  final String? groupPublicPackageHash;
  final List<MultisigPendingParticipant> participants;
  final int createdAt;
  final int updatedAt;
  final int createdLocallyAt;
  final int updatedLocallyAt;

  /// When this participant's own label was published to the group under the
  /// vault metadata key (after DKG). Null until posted or when no label set.
  final int? vaultLabelPostedAt;
  final bool localBackupCompleted;
  final int? localBackupCompletedAt;
  final int localBackupVersion;
  final String? localBackupHash;
  final int? localBackupVerifiedAt;
  final List<String> localBackupDestinations;

  String get storageId => '$sessionId:$participantId';

  /// The invite code is the secret itself; joiners derive the session id
  /// from it locally.
  String get inviteCode => inviteSecret;
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
    int? vaultLabelPostedAt,
    int? accessTokenExpiresAt,
    int? refreshTokenExpiresAt,
    String? creatorParticipantId,
    int? threshold,
    String? rosterHash,
    String? keyPackageB64,
    String? groupPublicPackageJson,
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
      inviteSecret: inviteSecret,
      vaultLabelPostedAt: vaultLabelPostedAt ?? this.vaultLabelPostedAt,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      refreshTokenExpiresAt:
          refreshTokenExpiresAt ?? this.refreshTokenExpiresAt,
      creatorParticipantId: creatorParticipantId ?? this.creatorParticipantId,
      threshold: threshold ?? this.threshold,
      rosterHash: rosterHash ?? this.rosterHash,
      keyPackageB64: keyPackageB64 ?? this.keyPackageB64,
      groupPublicPackageJson:
          groupPublicPackageJson ?? this.groupPublicPackageJson,
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

  MultisigPendingSession applyAuthSession(
    rust_multisig.ApiMultisigAuthSession value,
  ) {
    final participant = MultisigPendingParticipant.fromApi(value.participant);
    final nextParticipants = [...participants];
    final participantIndex = nextParticipants.indexWhere(
      (entry) => entry.participantId == participant.participantId,
    );
    if (participantIndex >= 0) {
      nextParticipants[participantIndex] = participant;
    } else {
      nextParticipants.add(participant);
    }
    return copyWith(
      state: value.state,
      accessToken: value.accessToken,
      refreshToken: value.refreshToken,
      identity: MultisigParticipantIdentity(
        admissionSecretKey: value.admissionSecretKey,
        admissionPublicKey: value.admissionPublicKey,
        deliverySecretKey: value.deliverySecretKey,
        deliveryPublicKey: value.deliveryPublicKey,
      ),
      accessTokenExpiresAt: value.accessTokenExpiresAt.toInt(),
      refreshTokenExpiresAt: value.refreshTokenExpiresAt.toInt(),
      participants: nextParticipants,
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
    'inviteSecret': inviteSecret,
    'vaultLabelPostedAt': vaultLabelPostedAt,
    'accessTokenExpiresAt': accessTokenExpiresAt,
    'refreshTokenExpiresAt': refreshTokenExpiresAt,
    'creatorParticipantId': creatorParticipantId,
    'threshold': threshold,
    'rosterHash': rosterHash,
    'keyPackageB64': keyPackageB64,
    'groupPublicPackageJson': groupPublicPackageJson,
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
      inviteSecret: _readRequiredString(
        json,
        'inviteSecret',
        'Multisig pending session',
      ),
      vaultLabelPostedAt: _readNullableInt(json['vaultLabelPostedAt']),
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
      keyPackageB64: json['keyPackageB64'] as String?,
      groupPublicPackageJson: json['groupPublicPackageJson'] as String?,
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
    required String inviteSecret,
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
      inviteSecret: inviteSecret,
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

class MultisigPendingSessionSummary {
  const MultisigPendingSessionSummary({
    required this.storageId,
    required this.sessionId,
    required this.participantId,
    required this.state,
    required this.updatedLocallyAt,
    this.role,
    this.label,
  });

  final String storageId;
  final String sessionId;
  final String participantId;
  final MultisigPendingRole? role;
  final String? label;
  final String state;
  final int updatedLocallyAt;

  bool get isPending => state != 'ready' && state != 'failed';

  String get displayLabel {
    final trimmed = label?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'Multisig session';
  }

  String get shortSessionId => sessionId.length <= 12
      ? sessionId
      : '${sessionId.substring(0, 6)}...${sessionId.substring(sessionId.length - 6)}';

  Map<String, Object?> toJson() => {
    'storageId': storageId,
    'sessionId': sessionId,
    'participantId': participantId,
    'role': role?.name,
    'label': label,
    'state': state,
    'updatedLocallyAt': updatedLocallyAt,
  };

  String toStorageJson() => jsonEncode(toJson());

  static MultisigPendingSessionSummary fromSession(
    MultisigPendingSession session,
  ) {
    return MultisigPendingSessionSummary(
      storageId: session.storageId,
      sessionId: session.sessionId,
      participantId: session.participantId,
      role: session.role,
      label: session.label,
      state: session.state,
      updatedLocallyAt: session.updatedLocallyAt,
    );
  }

  static MultisigPendingSessionSummary fromStorageId(String storageId) {
    final separator = storageId.indexOf(':');
    final sessionId = separator < 0
        ? storageId
        : storageId.substring(0, separator);
    final participantId = separator < 0
        ? ''
        : storageId.substring(separator + 1);
    return MultisigPendingSessionSummary(
      storageId: storageId,
      sessionId: sessionId,
      participantId: participantId,
      state: 'unknown',
      updatedLocallyAt: 0,
    );
  }

  static MultisigPendingSessionSummary fromJson(Map<String, Object?> json) {
    final roleText = json['role'] as String?;
    return MultisigPendingSessionSummary(
      storageId: _readRequiredString(
        json,
        'storageId',
        'Multisig pending session summary',
      ),
      sessionId: _readRequiredString(
        json,
        'sessionId',
        'Multisig pending session summary',
      ),
      participantId: _readRequiredString(
        json,
        'participantId',
        'Multisig pending session summary',
      ),
      role: roleText == null ? null : MultisigPendingRole.parse(roleText),
      label: json['label'] as String?,
      state: _readRequiredString(
        json,
        'state',
        'Multisig pending session summary',
      ),
      updatedLocallyAt: _readRequiredInt(
        json,
        'updatedLocallyAt',
        'Multisig pending session summary',
      ),
    );
  }

  static MultisigPendingSessionSummary fromStorageJson(String raw) {
    return fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
  }
}

class MultisigCreateAdvanceResult {
  const MultisigCreateAdvanceResult({
    required this.session,
    required this.phase,
    required this.detail,
    required this.waitingForParticipantIds,
    required this.round1Count,
    required this.round2Count,
    required this.dkgCompleteSubmitted,
    this.keyPackageB64,
    this.groupPublicPackageJson,
    this.groupPublicPackageHash,
  });

  final MultisigPendingSession session;
  final String phase;
  final String detail;
  final List<String> waitingForParticipantIds;
  final int round1Count;
  final int round2Count;
  final bool dkgCompleteSubmitted;
  final String? keyPackageB64;
  final String? groupPublicPackageJson;
  final String? groupPublicPackageHash;

  List<MultisigPendingParticipant> get waitingForParticipants {
    final waiting = waitingForParticipantIds.toSet();
    return session.participants
        .where((participant) => waiting.contains(participant.participantId))
        .toList(growable: false);
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

  Future<List<MultisigPendingSessionSummary>> readAllSummaries() async {
    final encryptedSessionIds =
        (await _storage.listMultisigPendingSessionStorageIds()).toSet();
    final raw = await _storage.readAllMultisigPendingSessionSummaries();
    final summaries = <MultisigPendingSessionSummary>[];
    final summarizedIds = <String>{};
    for (final entry in raw.entries) {
      if (!encryptedSessionIds.contains(entry.key)) continue;
      final summary = MultisigPendingSessionSummary.fromStorageJson(
        entry.value,
      );
      if (summary.storageId != entry.key) continue;
      summaries.add(summary);
      summarizedIds.add(summary.storageId);
    }
    for (final storageId in encryptedSessionIds) {
      if (summarizedIds.contains(storageId)) continue;
      summaries.add(MultisigPendingSessionSummary.fromStorageId(storageId));
    }
    return summaries;
  }

  Future<void> write(MultisigPendingSession session) {
    return _storage.writeMultisigPendingSession(
      session.storageId,
      session.toStorageJson(),
    );
  }

  Future<void> writeSummary(MultisigPendingSession session) {
    final summary = MultisigPendingSessionSummary.fromSession(session);
    return _storage.writeMultisigPendingSessionSummary(
      summary.storageId,
      summary.toStorageJson(),
    );
  }

  Future<void> rebuildSummaries(
    Iterable<MultisigPendingSession> sessions,
  ) async {
    await _storage.deleteAllMultisigPendingSessionSummaries();
    for (final session in sessions) {
      await writeSummary(session);
    }
  }

  Future<void> delete(MultisigPendingSession session) {
    return _storage.deleteMultisigPendingSession(session.storageId);
  }

  Future<void> deleteByStorageId(String storageId) {
    return _storage.deleteMultisigPendingSession(storageId);
  }

  Future<void> deleteSummary(String storageId) {
    return _storage.deleteMultisigPendingSessionSummary(storageId);
  }

  Future<void> deleteAllSummaries() {
    return _storage.deleteAllMultisigPendingSessionSummaries();
  }

  Future<String?> readCreateState(MultisigPendingSession session) {
    return _storage.readPlain(_createStateKey(session));
  }

  Future<void> writeCreateState(
    MultisigPendingSession session,
    String localStateJson,
  ) {
    return _storage.writePlain(_createStateKey(session), localStateJson);
  }

  Future<void> deleteCreateState(MultisigPendingSession session) {
    return _storage.delete(_createStateKey(session));
  }
}

final multisigPendingSessionStoreProvider =
    Provider<MultisigPendingSessionStore>(
      (ref) => MultisigPendingSessionStore(AppSecureStore.instance),
    );

class MultisigPendingSessionsNotifier
    extends AsyncNotifier<List<MultisigPendingSession>> {
  // Serializes every read-modify-write of the session list. Refresh, auth
  // refresh, and advance-create all snapshot the list around slow network
  // calls; without this queue a slower writer can persist a stale snapshot
  // and drop fields another writer just stored (worst case: the DKG
  // keyPackage right after the create state file was deleted).
  Future<void> _mutations = Future<void>.value();

  MultisigPendingSessionStore get _store =>
      ref.read(multisigPendingSessionStoreProvider);

  MultisigAccountMaterialStore get _materialStore =>
      ref.read(multisigAccountMaterialStoreProvider);

  MultisigCoordinatorService get _coordinator =>
      ref.read(multisigCoordinatorServiceProvider);

  MultisigRealtimeCursorStore get _cursorStore =>
      ref.read(multisigRealtimeCursorStoreProvider);

  @override
  FutureOr<List<MultisigPendingSession>> build() {
    final security = ref.watch(appSecurityProvider);
    if (security.requiresUnlock) return const <MultisigPendingSession>[];
    return _load();
  }

  Future<MultisigPendingSession> createSession({
    String coordinatorUrl = kDefaultMultisigCoordinatorUrl,
    String? label,
  }) async {
    final cleanUrl = _cleanRequired(coordinatorUrl, 'coordinator URL');
    final cleanLabel = _cleanOptional(label);
    final identity = _coordinator.generateParticipantIdentity();
    final inviteSecret = _coordinator.generateInviteSecret();
    final auth = await _coordinator.createSession(
      coordinatorUrl: cleanUrl,
      identity: identity,
      inviteSecret: inviteSecret,
      label: cleanLabel,
    );
    final pending = MultisigPendingSession.fromAuth(
      auth: auth,
      role: MultisigPendingRole.creator,
      coordinatorUrl: cleanUrl,
      inviteSecret: inviteSecret,
      label: cleanLabel,
    );
    await upsert(pending);
    return pending;
  }

  Future<MultisigPendingSession> joinSession({
    required String inviteCode,
    String coordinatorUrl = kDefaultMultisigCoordinatorUrl,
    String? label,
  }) async {
    final cleanUrl = _cleanRequired(coordinatorUrl, 'coordinator URL');
    final inviteSecret = normalizeMultisigInviteCode(inviteCode);
    final sessionId = _coordinator.deriveSessionId(inviteSecret);
    final cleanLabel = _cleanOptional(label);
    final identity = _coordinator.generateParticipantIdentity();
    final auth = await _coordinator.joinSession(
      coordinatorUrl: cleanUrl,
      sessionId: sessionId,
      identity: identity,
      inviteSecret: inviteSecret,
      label: cleanLabel,
    );
    _validateSessionOwner(
      expectedSessionId: sessionId,
      returnedSessionId: auth.sessionId,
    );
    final pending = MultisigPendingSession.fromAuth(
      auth: auth,
      role: MultisigPendingRole.participant,
      coordinatorUrl: cleanUrl,
      inviteSecret: inviteSecret,
      label: cleanLabel,
    );
    await upsert(pending);
    return pending;
  }

  Future<MultisigPendingSession> refreshSession(String storageId) async {
    final pending = await _sessionWithFreshAccess(
      await _requireSession(storageId),
    );
    final session = await _coordinator.getSession(
      coordinatorUrl: pending.coordinatorUrl,
      sessionId: pending.sessionId,
      accessToken: pending.accessToken,
      inviteSecret: pending.inviteSecret,
    );
    _validateSessionOwner(
      expectedSessionId: pending.sessionId,
      returnedSessionId: session.sessionId,
    );
    return _applySessionUpdate(
      pending,
      (current) => current.applySession(session),
    );
  }

  Future<MultisigPendingSession> refreshSessionFromEvents(
    String storageId,
  ) async {
    final pending = await _sessionWithFreshAccess(
      await _requireSession(storageId),
    );
    final cursor = await _cursorStore.read(pending.storageId);
    final events = await _coordinator.getSessionEvents(
      coordinatorUrl: pending.coordinatorUrl,
      sessionId: pending.sessionId,
      accessToken: pending.accessToken,
      after: cursor.eventsCursor,
    );
    final session = await _coordinator.getSession(
      coordinatorUrl: pending.coordinatorUrl,
      sessionId: pending.sessionId,
      accessToken: pending.accessToken,
      inviteSecret: pending.inviteSecret,
    );
    _validateSessionOwner(
      expectedSessionId: pending.sessionId,
      returnedSessionId: session.sessionId,
    );
    final updated = await _applySessionUpdate(
      pending,
      (current) => current.applySession(session),
    );
    await _cursorStore.advanceEventsCursor(
      pending.storageId,
      events.cursor.toInt(),
    );
    return updated;
  }

  Future<MultisigCreateAdvanceResult> advanceCreate(String storageId) async {
    final pending = await _sessionWithFreshAccess(
      await _requireSession(storageId),
    );
    final localStateJson = await _store.readCreateState(pending);
    final advanced = await rust_multisig.advanceMultisigCreate(
      coordinatorUrl: pending.coordinatorUrl,
      sessionId: pending.sessionId,
      participantId: pending.participantId,
      accessToken: pending.accessToken,
      admissionSecretKey: pending.identity.admissionSecretKey,
      deliverySecretKey: pending.identity.deliverySecretKey,
      inviteSecret: pending.inviteSecret,
      localStateJson: localStateJson,
    );
    await _store.writeCreateState(pending, advanced.localStateJson);
    await _publishVaultLabelIfReady(pending, advanced);
    final updated = await _applySessionUpdate(
      pending,
      (current) => current
          .applySession(advanced.session)
          .copyWith(
            keyPackageB64: advanced.keyPackageB64,
            groupPublicPackageJson: advanced.groupPublicPackageJson,
            groupPublicPackageHash:
                advanced.groupPublicPackageHash ??
                advanced.session.groupPublicPackageHash,
          ),
    );
    if (updated.state == 'ready') {
      await _store.deleteCreateState(updated);
    }
    return MultisigCreateAdvanceResult(
      session: updated,
      phase: advanced.phase,
      detail: normalizeMultisigProgressDetail(advanced.detail),
      waitingForParticipantIds: advanced.waitingForParticipantIds,
      round1Count: advanced.round1Count.toInt(),
      round2Count: advanced.round2Count.toInt(),
      dkgCompleteSubmitted: advanced.dkgCompleteSubmitted,
      keyPackageB64: advanced.keyPackageB64,
      groupPublicPackageJson: advanced.groupPublicPackageJson,
      groupPublicPackageHash: advanced.groupPublicPackageHash,
    );
  }

  Future<MultisigPendingSession> refreshAuth(String storageId) {
    return _sessionWithFreshAccess(_requireSession(storageId), force: true);
  }

  Future<MultisigPendingSession> markLocalBackupVerified({
    required String storageId,
    required String backupHash,
    required List<String> destinations,
  }) async {
    final stored = await _requireSession(storageId);
    final cleanHash = backupHash.trim();
    final cleanDestinations = destinations
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (cleanHash.isEmpty || cleanDestinations.isEmpty) {
      throw StateError('Verified backup evidence is missing.');
    }
    final now = ref.read(multisigNowProvider)().millisecondsSinceEpoch;
    return _applySessionUpdate(
      stored,
      (current) => current.copyWith(
        localBackupCompleted: true,
        localBackupCompletedAt: now,
        localBackupVersion: 2,
        localBackupHash: cleanHash,
        localBackupVerifiedAt: now,
        localBackupDestinations: cleanDestinations,
        updatedLocallyAt: now,
      ),
    );
  }

  Future<MultisigPendingSession> resumeParticipant(String storageId) async {
    final stored = await _requireSession(storageId);
    final auth = await _coordinator.resumeParticipant(
      coordinatorUrl: stored.coordinatorUrl,
      sessionId: stored.sessionId,
      admissionSecretKey: stored.identity.admissionSecretKey,
      deliverySecretKey: stored.identity.deliverySecretKey,
      inviteSecret: stored.inviteSecret,
    );
    _validateAuthOwner(
      expectedSessionId: stored.sessionId,
      expectedParticipantId: stored.participantId,
      returnedSessionId: auth.sessionId,
      returnedParticipantId: auth.participantId,
    );
    return _applySessionUpdate(
      stored,
      (current) => current.applyAuthSession(auth),
    );
  }

  Future<MultisigPendingSession> lockSession({
    required String storageId,
    required int threshold,
  }) async {
    // The coordinator accepts threshold 1 but FROST DKG requires >= 2
    // (ThresholdParams / frost min_signers); locking a roster with 1 bricks
    // the session because the threshold is immutable after lock.
    if (threshold < 2) {
      throw ArgumentError.value(threshold, 'threshold', 'must be at least 2');
    }
    final pending = await _sessionWithFreshAccess(
      await _requireSession(storageId),
    );
    final session = await _coordinator.lockSession(
      coordinatorUrl: pending.coordinatorUrl,
      sessionId: pending.sessionId,
      accessToken: pending.accessToken,
      threshold: threshold,
      inviteSecret: pending.inviteSecret,
    );
    _validateSessionOwner(
      expectedSessionId: pending.sessionId,
      returnedSessionId: session.sessionId,
    );
    return _applySessionUpdate(
      pending,
      (current) => current.applySession(session),
    );
  }

  Future<void> upsert(MultisigPendingSession session) {
    return _synchronized(() async {
      final sessions = [...await _currentSessions()];
      final index = sessions.indexWhere(
        (entry) => entry.storageId == session.storageId,
      );
      if (index >= 0) {
        sessions[index] = session;
      } else {
        sessions.add(session);
      }
      _sortSessions(sessions);
      await _store.write(session);
      await _store.writeSummary(session);
      ref.invalidate(multisigPendingSessionSummariesProvider);
      state = AsyncData(sessions);
    });
  }

  Future<void> delete(String storageId) {
    return _synchronized(() async {
      final sessions = [...await _currentSessions()];
      final target = _findSession(sessions, storageId);
      if (target == null) return;
      await _store.deleteCreateState(target);
      await _store.delete(target);
      await _store.deleteSummary(target.storageId);
      sessions.removeWhere((entry) => entry.storageId == target.storageId);
      ref.invalidate(multisigPendingSessionSummariesProvider);
      state = AsyncData(sessions);
    });
  }

  Future<void> clearAll() {
    return _synchronized(() async {
      final sessions = await _currentSessions();
      for (final session in sessions) {
        await _store.deleteCreateState(session);
        await _store.delete(session);
      }
      await _store.deleteAllSummaries();
      ref.invalidate(multisigPendingSessionSummariesProvider);
      state = const AsyncData(<MultisigPendingSession>[]);
    });
  }

  Future<void> applyAuthUpdate(
    rust_multisig.ApiMultisigAuthUpdate update,
  ) async {
    await _synchronized(() async {
      final sessions = [...await _currentSessions()];
      final index = sessions.indexWhere(
        (entry) =>
            entry.sessionId == update.sessionId &&
            entry.participantId == update.participantId,
      );
      if (index < 0) return;
      final refreshed = sessions[index].applyAuthUpdate(update);
      sessions[index] = refreshed;
      _sortSessions(sessions);
      await _store.write(refreshed);
      await _store.writeSummary(refreshed);
      ref.invalidate(multisigPendingSessionSummariesProvider);
      state = AsyncData(sessions);
    });
    await _applyAuthUpdateToAccountMaterials(update);
  }

  /// Publishes the local participant's label under the vault metadata key
  /// as soon as the local DKG output exists, so participants that finalize
  /// (and drop the invite secret) early still learn everyone's label.
  /// Best-effort: a failure is retried on the next advance poll.
  Future<void> _publishVaultLabelIfReady(
    MultisigPendingSession pending,
    rust_multisig.ApiMultisigCreateAdvance advanced,
  ) async {
    final label = pending.label?.trim();
    final groupPublicPackageJson = advanced.groupPublicPackageJson;
    final rosterHash = advanced.session.rosterHash ?? pending.rosterHash;
    if (label == null ||
        label.isEmpty ||
        pending.vaultLabelPostedAt != null ||
        !advanced.dkgCompleteSubmitted ||
        groupPublicPackageJson == null ||
        rosterHash == null) {
      return;
    }
    try {
      await _coordinator.postVaultLabel(
        coordinatorUrl: pending.coordinatorUrl,
        sessionId: pending.sessionId,
        participantId: pending.participantId,
        accessToken: pending.accessToken,
        rosterHash: rosterHash,
        groupPublicPackageJson: groupPublicPackageJson,
        label: label,
      );
      final now = ref.read(multisigNowProvider)().millisecondsSinceEpoch;
      await _applySessionUpdate(
        pending,
        (current) => current.copyWith(vaultLabelPostedAt: now),
      );
    } catch (e) {
      log('MultisigPendingSessions: vault label publish failed: $e');
    }
  }

  Future<MultisigPendingSession> _sessionWithFreshAccess(
    FutureOr<MultisigPendingSession> pendingFuture, {
    bool force = false,
  }) async {
    var pending = await pendingFuture;
    if (!force && _hasFreshAccess(pending)) return pending;

    // Another component (realtime reconnect, signing refresh) may already
    // have rotated the tokens; reuse its result instead of rotating again.
    final latest = _findSession(await _currentSessions(), pending.storageId);
    if (latest != null) {
      if (latest.accessToken != pending.accessToken &&
          _hasFreshAccess(latest)) {
        return latest;
      }
      pending = latest;
    }

    final update = await ref
        .read(multisigAuthRefresherProvider)
        .refreshOrResume(
          coordinatorUrl: pending.coordinatorUrl,
          sessionId: pending.sessionId,
          participantId: pending.participantId,
          refreshToken: pending.refreshToken,
          admissionSecretKey: pending.identity.admissionSecretKey,
          deliverySecretKey: pending.identity.deliverySecretKey,
        );
    _validateAuthOwner(
      expectedSessionId: pending.sessionId,
      expectedParticipantId: pending.participantId,
      returnedSessionId: update.sessionId,
      returnedParticipantId: update.participantId,
    );

    final refreshed = await _applySessionUpdate(
      pending,
      (current) => current.applyAuthUpdate(update),
    );
    await _applyAuthUpdateToAccountMaterials(update);
    return refreshed;
  }

  /// Atomically re-reads the stored session and applies [transform] to the
  /// freshest copy, so a response fetched around a slow network call cannot
  /// overwrite fields written by a concurrent operation. If the session was
  /// deleted mid-flight the result is returned without being persisted.
  Future<MultisigPendingSession> _applySessionUpdate(
    MultisigPendingSession fallback,
    MultisigPendingSession Function(MultisigPendingSession current) transform,
  ) {
    return _synchronized(() async {
      final sessions = [...await _currentSessions()];
      final index = sessions.indexWhere(
        (entry) => entry.storageId == fallback.storageId,
      );
      if (index < 0) return transform(fallback);
      final updated = transform(sessions[index]);
      sessions[index] = updated;
      _sortSessions(sessions);
      await _store.write(updated);
      await _store.writeSummary(updated);
      ref.invalidate(multisigPendingSessionSummariesProvider);
      state = AsyncData(sessions);
      return updated;
    });
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final run = _mutations.then((_) => action());
    _mutations = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _applyAuthUpdateToAccountMaterials(
    rust_multisig.ApiMultisigAuthUpdate update,
  ) async {
    final materials = await _materialStore.readAll();
    for (final material in materials) {
      if (material.sessionId != update.sessionId ||
          material.participantId != update.participantId) {
        continue;
      }
      await _materialStore.write(
        material.copyWith(
          identity: MultisigParticipantIdentity(
            admissionSecretKey: material.identity.admissionSecretKey,
            admissionPublicKey: update.admissionPublicKey,
            deliverySecretKey: update.deliverySecretKey,
            deliveryPublicKey: update.deliveryPublicKey,
          ),
          accessToken: update.accessToken,
          refreshToken: update.refreshToken,
          accessTokenExpiresAt: update.accessTokenExpiresAt.toInt(),
          refreshTokenExpiresAt: update.refreshTokenExpiresAt.toInt(),
        ),
      );
      ref.invalidate(multisigAccountMaterialsProvider);
    }
  }

  bool _hasFreshAccess(MultisigPendingSession session) {
    final nowSeconds =
        ref.read(multisigNowProvider)().millisecondsSinceEpoch ~/ 1000;
    return session.accessTokenExpiresAt >
        nowSeconds + _accessTokenRefreshSkewSeconds;
  }

  Future<MultisigPendingSession> _requireSession(String storageId) async {
    final session = _findSession(await _currentSessions(), storageId);
    if (session == null) {
      throw StateError('Multisig pending session not found.');
    }
    return session;
  }

  Future<List<MultisigPendingSession>> _currentSessions() async {
    final current = state.value;
    if (current != null) return current;
    return _load();
  }

  Future<List<MultisigPendingSession>> _load() async {
    final sessions = [...await _store.readAll()];
    _sortSessions(sessions);
    await _store.rebuildSummaries(sessions);
    return sessions;
  }
}

final multisigPendingSessionsProvider =
    AsyncNotifierProvider<
      MultisigPendingSessionsNotifier,
      List<MultisigPendingSession>
    >(MultisigPendingSessionsNotifier.new);

final multisigPendingSessionSummariesProvider =
    FutureProvider<List<MultisigPendingSessionSummary>>((ref) async {
      final summaries = [
        ...await ref
            .watch(multisigPendingSessionStoreProvider)
            .readAllSummaries(),
      ];
      _sortSessionSummaries(summaries);
      return summaries;
    });

MultisigPendingSession? latestPendingMultisigSession(
  List<MultisigPendingSession> sessions,
) {
  for (final session in sessions) {
    if (session.isPending) return session;
  }
  return null;
}

MultisigPendingSession? latestLocalMultisigSetupSession(
  List<MultisigPendingSession> sessions, [
  Set<String> materializedSessionStorageIds = const <String>{},
]) {
  for (final session in sessions) {
    if (multisigSessionNeedsLocalSetup(
      session,
      materializedSessionStorageIds,
    )) {
      return session;
    }
  }
  return null;
}

MultisigPendingSessionSummary? latestLocalMultisigSetupSummary(
  List<MultisigPendingSessionSummary> summaries, [
  Set<String> materializedSessionStorageIds = const <String>{},
]) {
  for (final summary in summaries) {
    if (multisigSessionSummaryNeedsLocalSetup(
      summary,
      materializedSessionStorageIds,
    )) {
      return summary;
    }
  }
  return null;
}

MultisigPendingSession? multisigSessionByStorageId(
  List<MultisigPendingSession> sessions,
  String storageId,
) {
  for (final session in sessions) {
    if (session.storageId == storageId) return session;
  }
  return null;
}

MultisigPendingSession? multisigSessionById(
  List<MultisigPendingSession> sessions,
  String sessionId,
) {
  for (final session in sessions) {
    if (session.sessionId == sessionId) return session;
  }
  return null;
}

bool multisigSessionNeedsLocalSetup(
  MultisigPendingSession session, [
  Set<String> materializedSessionStorageIds = const <String>{},
]) {
  return session.state != 'failed' &&
      !materializedSessionStorageIds.contains(session.storageId);
}

bool multisigSessionSummaryNeedsLocalSetup(
  MultisigPendingSessionSummary summary, [
  Set<String> materializedSessionStorageIds = const <String>{},
]) {
  return summary.state != 'failed' &&
      !materializedSessionStorageIds.contains(summary.storageId);
}

bool multisigLocalBackupCompleted(MultisigPendingSession session) {
  return session.localBackupCompleted &&
      session.localBackupHash != null &&
      session.localBackupDestinations.isNotEmpty;
}

MultisigPendingSession? _findSession(
  List<MultisigPendingSession> sessions,
  String storageIdOrSessionId,
) {
  return multisigSessionByStorageId(sessions, storageIdOrSessionId) ??
      multisigSessionById(sessions, storageIdOrSessionId);
}

void _sortSessions(List<MultisigPendingSession> sessions) {
  sessions.sort((a, b) => b.updatedLocallyAt.compareTo(a.updatedLocallyAt));
}

void _sortSessionSummaries(List<MultisigPendingSessionSummary> summaries) {
  summaries.sort((a, b) => b.updatedLocallyAt.compareTo(a.updatedLocallyAt));
}

String _createStateKey(MultisigPendingSession session) {
  return '$_multisigCreateStateStoragePrefix${session.storageId}';
}

String _cleanRequired(String value, String label) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) throw FormatException('Missing multisig $label.');
  return trimmed;
}

String? _cleanOptional(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

void _validateAuthOwner({
  required String expectedSessionId,
  required String expectedParticipantId,
  required String returnedSessionId,
  required String returnedParticipantId,
}) {
  if (returnedSessionId != expectedSessionId ||
      returnedParticipantId != expectedParticipantId) {
    throw StateError('Multisig auth response belongs to a different session.');
  }
}

void _validateSessionOwner({
  required String expectedSessionId,
  required String returnedSessionId,
}) {
  if (returnedSessionId != expectedSessionId) {
    throw StateError(
      'Multisig session response belongs to a different session.',
    );
  }
}

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
