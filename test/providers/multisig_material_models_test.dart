import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';

void main() {
  const identity = MultisigParticipantIdentity(
    admissionSecretKey: 'admission-secret',
    admissionPublicKey: 'admission-public',
    deliverySecretKey: 'delivery-secret',
    deliveryPublicKey: 'delivery-public',
  );

  MultisigPendingSession pendingSession() {
    return const MultisigPendingSession(
      sessionId: 'session-1',
      participantId: 'participant-1',
      role: MultisigPendingRole.creator,
      coordinatorUrl: 'http://127.0.0.1:3001',
      state: 'collecting',
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      identity: identity,
      inviteSecret: 'invite-secret',
      accessTokenExpiresAt: 10,
      refreshTokenExpiresAt: 20,
      participants: <MultisigPendingParticipant>[],
      createdAt: 1,
      updatedAt: 2,
      createdLocallyAt: 3,
      updatedLocallyAt: 4,
    );
  }

  MultisigAccountMaterial accountMaterial() {
    return const MultisigAccountMaterial(
      accountUuid: 'account-1',
      sessionId: 'session-1',
      participantId: 'participant-1',
      coordinatorUrl: 'http://127.0.0.1:3001',
      rosterHash: 'roster',
      groupPublicPackageHash: 'group',
      threshold: 2,
      participantCount: 3,
      identity: identity,
      keyPackageB64: 'key-package',
      groupPublicPackageJson: '{"group":true}',
      vaultAddress: 'uregtest1example',
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessTokenExpiresAt: 10,
      refreshTokenExpiresAt: 20,
    );
  }

  Map<String, Object?> storageMap(String raw) {
    return Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  test('pending session storage uses identity secrets instead of mnemonic', () {
    final raw = pendingSession().toStorageJson();
    final decoded = storageMap(raw);

    expect(decoded.containsKey('admissionMnemonic'), isFalse);
    expect(decoded['identity'], isA<Map>());

    final restored = MultisigPendingSession.fromStorageJson(raw);
    expect(restored.identity.admissionSecretKey, 'admission-secret');
    expect(restored.identity.deliverySecretKey, 'delivery-secret');
    expect(restored.localBackupVersion, 2);
  });

  test(
    'account material storage uses identity secrets instead of mnemonic',
    () {
      final raw = accountMaterial().toStorageJson();
      final decoded = storageMap(raw);

      expect(decoded.containsKey('admissionMnemonic'), isFalse);
      expect(decoded['identity'], isA<Map>());

      final restored = MultisigAccountMaterial.fromStorageJson(raw);
      expect(restored.identity.admissionPublicKey, 'admission-public');
      expect(restored.identity.deliveryPublicKey, 'delivery-public');
      expect(restored.threshold, 2);
    },
  );

  test('pending session storage rejects missing identity', () {
    final decoded = storageMap(pendingSession().toStorageJson())
      ..remove('identity');

    expect(
      () => MultisigPendingSession.fromStorageJson(jsonEncode(decoded)),
      throwsA(isA<FormatException>()),
    );
  });

  test('account material storage rejects missing identity', () {
    final decoded = storageMap(accountMaterial().toStorageJson())
      ..remove('identity');

    expect(
      () => MultisigAccountMaterial.fromStorageJson(jsonEncode(decoded)),
      throwsA(isA<FormatException>()),
    );
  });

  test('account material storage rejects missing required fields', () {
    final missingKeyPackage = storageMap(accountMaterial().toStorageJson())
      ..remove('keyPackageB64');
    expect(
      () => MultisigAccountMaterial.fromStorageJson(
        jsonEncode(missingKeyPackage),
      ),
      throwsA(isA<FormatException>()),
    );

    final zeroThreshold = storageMap(accountMaterial().toStorageJson())
      ..['threshold'] = 0;
    expect(
      () => MultisigAccountMaterial.fromStorageJson(jsonEncode(zeroThreshold)),
      throwsA(isA<FormatException>()),
    );
  });

  test('pending session storage rejects missing required fields', () {
    final missingToken = storageMap(pendingSession().toStorageJson())
      ..remove('accessToken');
    expect(
      () => MultisigPendingSession.fromStorageJson(jsonEncode(missingToken)),
      throwsA(isA<FormatException>()),
    );

    final missingParticipants = storageMap(pendingSession().toStorageJson())
      ..remove('participants');
    expect(
      () => MultisigPendingSession.fromStorageJson(
        jsonEncode(missingParticipants),
      ),
      throwsA(isA<FormatException>()),
    );

    final malformedParticipant = storageMap(pendingSession().toStorageJson())
      ..['participants'] = [
        {
          'participantId': 'participant-1',
          'admissionPublicKey': 'admission-public',
          'deliveryPublicKey': 'delivery-public',
          'joinedAt': 1,
        },
      ];
    expect(
      () => MultisigPendingSession.fromStorageJson(
        jsonEncode(malformedParticipant),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('pending session storage rejects unknown role', () {
    final decoded = storageMap(pendingSession().toStorageJson())
      ..['role'] = 'observer';

    expect(
      () => MultisigPendingSession.fromStorageJson(jsonEncode(decoded)),
      throwsA(isA<FormatException>()),
    );
  });

  test('identity storage rejects empty key material', () {
    expect(
      () => MultisigParticipantIdentity.fromJson(const {
        'admissionSecretKey': '',
        'admissionPublicKey': 'admission-public',
        'deliverySecretKey': 'delivery-secret',
        'deliveryPublicKey': 'delivery-public',
      }),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => MultisigParticipantIdentity.fromJson(const {
        'admissionSecretKey': 'admission-secret',
        'admissionPublicKey': 'admission-public',
        'deliverySecretKey': 'delivery-secret',
        'deliveryPublicKey': ' ',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
