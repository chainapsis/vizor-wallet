import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_coordinator_service.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';
import 'package:zcash_wallet/src/rust/api/multisig.dart' as rust_multisig;

void main() {
  test(
    'loads pending sessions from storage sorted by local update time',
    () async {
      final store = _FakePendingSessionStore()
        ..put(_pendingSession(sessionId: 'old', updatedLocallyAt: 10))
        ..put(_pendingSession(sessionId: 'new', updatedLocallyAt: 20));
      final container = _container(store: store);
      addTearDown(container.dispose);

      final sessions = await container.read(
        multisigPendingSessionsProvider.future,
      );

      expect(sessions.map((entry) => entry.sessionId), ['new', 'old']);
    },
  );

  test('reloads stored sessions after the wallet unlocks', () async {
    final store = _FakePendingSessionStore()
      ..put(_pendingSession(sessionId: 'locked-session'));
    final container = _container(store: store, isUnlocked: false);
    addTearDown(container.dispose);

    expect(
      await container.read(multisigPendingSessionsProvider.future),
      isEmpty,
    );

    final security =
        container.read(appSecurityProvider.notifier)
            as _FakeAppSecurityNotifier;
    security.setUnlocked(true);

    final sessions = await container.read(
      multisigPendingSessionsProvider.future,
    );

    expect(sessions.map((entry) => entry.sessionId), ['locked-session']);
  });

  test('creates a session with a generated identity and stores it', () async {
    final store = _FakePendingSessionStore();
    final service = _FakeMultisigCoordinatorService();
    final container = _container(store: store, service: service);
    addTearDown(container.dispose);

    final created = await container
        .read(multisigPendingSessionsProvider.notifier)
        .createSession(
          coordinatorUrl: ' https://coordinator.example ',
          label: ' Family vault ',
        );

    expect(created.role, MultisigPendingRole.creator);
    expect(created.coordinatorUrl, 'https://coordinator.example');
    expect(created.label, 'Family vault');
    expect(
      created.identity.admissionSecretKey,
      _apiIdentity.admissionSecretKey,
    );
    expect(service.createCalls, [
      'https://coordinator.example|Family vault|${_apiIdentity.admissionSecretKey}',
    ]);
    expect(store.sessions[created.storageId], same(created));
    expect(
      container.read(multisigPendingSessionsProvider).value,
      contains(same(created)),
    );
  });

  test('joins a session and stores the participant session', () async {
    final store = _FakePendingSessionStore();
    final service = _FakeMultisigCoordinatorService();
    final container = _container(store: store, service: service);
    addTearDown(container.dispose);

    final joined = await container
        .read(multisigPendingSessionsProvider.notifier)
        .joinSession(
          coordinatorUrl: 'https://coordinator.example',
          sessionId: ' session-join ',
          label: 'Signer 2',
        );

    expect(joined.role, MultisigPendingRole.participant);
    expect(joined.sessionId, 'session-join');
    expect(service.joinCalls, [
      'https://coordinator.example|session-join|Signer 2|${_apiIdentity.deliverySecretKey}',
    ]);
    expect(store.sessions[joined.storageId], same(joined));
  });

  test('joinSession rejects session owner mismatch before storing', () async {
    final store = _FakePendingSessionStore();
    final service = _FakeMultisigCoordinatorService(
      joinResponse: _apiAuthSession(
        sessionId: 'other-session',
        participantId: 'participant-2',
      ),
    );
    final container = _container(store: store, service: service);
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(multisigPendingSessionsProvider.notifier)
          .joinSession(
            coordinatorUrl: 'https://coordinator.example',
            sessionId: 'session-join',
            label: 'Signer 2',
          ),
      throwsA(isA<StateError>()),
    );

    expect(store.sessions, isEmpty);
  });

  test(
    'refreshSession reuses fresh access token and applies session state',
    () async {
      final store = _FakePendingSessionStore();
      final session = _pendingSession(
        accessToken: 'fresh-access',
        accessTokenExpiresAt: 2000,
      );
      store.put(session);
      final service = _FakeMultisigCoordinatorService(
        sessionResponse: _apiSession(
          state: 'locked',
          threshold: 2,
          participants: [
            _apiParticipant(participantId: 'participant-1'),
            _apiParticipant(participantId: 'participant-2', label: 'Signer 2'),
          ],
        ),
      );
      final container = _container(store: store, service: service);
      addTearDown(container.dispose);

      final refreshed = await container
          .read(multisigPendingSessionsProvider.notifier)
          .refreshSession(session.storageId);

      expect(service.refreshCalls, isEmpty);
      expect(service.getCalls, ['session-1|fresh-access']);
      expect(refreshed.state, 'locked');
      expect(refreshed.threshold, 2);
      expect(refreshed.participants, hasLength(2));
      expect(store.sessions[session.storageId]!.state, 'locked');
    },
  );

  test('refreshSession rejects session owner mismatch', () async {
    final store = _FakePendingSessionStore();
    final session = _pendingSession(accessTokenExpiresAt: 2000);
    store.put(session);
    final service = _FakeMultisigCoordinatorService(
      sessionResponse: _apiSession(sessionId: 'other-session', state: 'locked'),
    );
    final container = _container(store: store, service: service);
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(multisigPendingSessionsProvider.notifier)
          .refreshSession(session.storageId),
      throwsA(isA<StateError>()),
    );

    expect(store.sessions[session.storageId]!.state, 'collecting');
  });

  test(
    'expired auth refresh updates pending session and account material',
    () async {
      final store = _FakePendingSessionStore();
      final materialStore = _FakeAccountMaterialStore();
      final session = _pendingSession(accessTokenExpiresAt: 900);
      final material = _accountMaterial();
      store.put(session);
      materialStore.put(material);
      final service = _FakeMultisigCoordinatorService(
        authUpdateResponse: _apiAuthUpdate(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          deliverySecretKey: 'new-delivery-secret',
          deliveryPublicKey: 'new-delivery-public',
        ),
      );
      final container = _container(
        store: store,
        materialStore: materialStore,
        service: service,
      );
      addTearDown(container.dispose);

      final refreshed = await container
          .read(multisigPendingSessionsProvider.notifier)
          .refreshAuth(session.storageId);

      expect(service.refreshCalls, ['session-1|participant-1|refresh-token']);
      expect(refreshed.accessToken, 'new-access');
      expect(refreshed.identity.deliverySecretKey, 'new-delivery-secret');
      final updatedMaterial = materialStore.materials[material.accountUuid]!;
      expect(updatedMaterial.accessToken, 'new-access');
      expect(updatedMaterial.refreshToken, 'new-refresh');
      expect(updatedMaterial.identity.admissionSecretKey, 'admission-secret');
      expect(updatedMaterial.identity.deliveryPublicKey, 'new-delivery-public');
    },
  );

  test(
    'auth owner mismatch is rejected before storage is overwritten',
    () async {
      final store = _FakePendingSessionStore();
      final session = _pendingSession(accessTokenExpiresAt: 900);
      store.put(session);
      final service = _FakeMultisigCoordinatorService(
        authUpdateResponse: _apiAuthUpdate(sessionId: 'other-session'),
      );
      final container = _container(store: store, service: service);
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(multisigPendingSessionsProvider.notifier)
            .refreshAuth(session.storageId),
        throwsA(isA<StateError>()),
      );

      expect(store.sessions[session.storageId]!.accessToken, 'access-token');
    },
  );

  test('resumeParticipant refreshes stored auth session material', () async {
    final store = _FakePendingSessionStore();
    final session = _pendingSession().copyWith(
      participants: [
        _pendingParticipant(participantId: 'participant-1'),
        _pendingParticipant(participantId: 'participant-2'),
      ],
    );
    store.put(session);
    final service = _FakeMultisigCoordinatorService(
      resumeResponse: _apiAuthSession(
        accessToken: 'resumed-access',
        refreshToken: 'resumed-refresh',
        deliverySecretKey: 'resumed-delivery-secret',
        deliveryPublicKey: 'resumed-delivery-public',
      ),
    );
    final container = _container(store: store, service: service);
    addTearDown(container.dispose);

    final resumed = await container
        .read(multisigPendingSessionsProvider.notifier)
        .resumeParticipant(session.storageId);

    expect(service.resumeCalls, ['session-1|admission-secret']);
    expect(resumed.accessToken, 'resumed-access');
    expect(resumed.identity.deliverySecretKey, 'resumed-delivery-secret');
    expect(resumed.participants.map((entry) => entry.participantId), [
      'participant-1',
      'participant-2',
    ]);
    expect(store.sessions[session.storageId]!.accessToken, 'resumed-access');
  });

  test(
    'lockSession refreshes auth if needed and applies locked session state',
    () async {
      final store = _FakePendingSessionStore();
      final session = _pendingSession(accessTokenExpiresAt: 900);
      store.put(session);
      final service = _FakeMultisigCoordinatorService(
        authUpdateResponse: _apiAuthUpdate(accessToken: 'lock-access'),
        lockResponse: _apiSession(state: 'ready', threshold: 2),
      );
      final container = _container(store: store, service: service);
      addTearDown(container.dispose);

      final locked = await container
          .read(multisigPendingSessionsProvider.notifier)
          .lockSession(storageId: session.storageId, threshold: 2);

      expect(service.refreshCalls, ['session-1|participant-1|refresh-token']);
      expect(service.lockCalls, ['session-1|lock-access|2']);
      expect(locked.state, 'ready');
      expect(locked.threshold, 2);
    },
  );

  test('lockSession rejects session owner mismatch', () async {
    final store = _FakePendingSessionStore();
    final session = _pendingSession(accessTokenExpiresAt: 2000);
    store.put(session);
    final service = _FakeMultisigCoordinatorService(
      lockResponse: _apiSession(sessionId: 'other-session', state: 'ready'),
    );
    final container = _container(store: store, service: service);
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(multisigPendingSessionsProvider.notifier)
          .lockSession(storageId: session.storageId, threshold: 2),
      throwsA(isA<StateError>()),
    );

    expect(store.sessions[session.storageId]!.state, 'collecting');
  });

  test('clearAll deletes every stored pending session', () async {
    final store = _FakePendingSessionStore()
      ..put(_pendingSession(sessionId: 'one'))
      ..put(_pendingSession(sessionId: 'two'));
    final container = _container(store: store);
    addTearDown(container.dispose);

    await container.read(multisigPendingSessionsProvider.future);
    await container.read(multisigPendingSessionsProvider.notifier).clearAll();

    expect(store.sessions, isEmpty);
    expect(container.read(multisigPendingSessionsProvider).value, isEmpty);
  });
}

ProviderContainer _container({
  _FakePendingSessionStore? store,
  _FakeAccountMaterialStore? materialStore,
  _FakeMultisigCoordinatorService? service,
  bool isUnlocked = true,
}) {
  return ProviderContainer(
    overrides: [
      appSecurityProvider.overrideWith(
        () => _FakeAppSecurityNotifier(isUnlocked: isUnlocked),
      ),
      multisigPendingSessionStoreProvider.overrideWithValue(
        store ?? _FakePendingSessionStore(),
      ),
      multisigAccountMaterialStoreProvider.overrideWithValue(
        materialStore ?? _FakeAccountMaterialStore(),
      ),
      multisigCoordinatorServiceProvider.overrideWithValue(
        service ?? _FakeMultisigCoordinatorService(),
      ),
      multisigNowProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      ),
    ],
  );
}

class _FakeAppSecurityNotifier extends AppSecurityNotifier {
  _FakeAppSecurityNotifier({required this.isUnlocked});

  final bool isUnlocked;

  @override
  AppSecurityState build() {
    return AppSecurityState(isPasswordConfigured: true, isUnlocked: isUnlocked);
  }

  void setUnlocked(bool value) {
    state = state.copyWith(isUnlocked: value);
  }
}

const _identity = MultisigParticipantIdentity(
  admissionSecretKey: 'admission-secret',
  admissionPublicKey: 'admission-public',
  deliverySecretKey: 'delivery-secret',
  deliveryPublicKey: 'delivery-public',
);

const _apiIdentity = rust_multisig.ApiMultisigParticipantIdentity(
  admissionSecretKey: 'admission-secret',
  admissionPublicKey: 'admission-public',
  deliverySecretKey: 'delivery-secret',
  deliveryPublicKey: 'delivery-public',
);

MultisigPendingSession _pendingSession({
  String sessionId = 'session-1',
  String participantId = 'participant-1',
  String accessToken = 'access-token',
  String refreshToken = 'refresh-token',
  int accessTokenExpiresAt = 2000,
  int refreshTokenExpiresAt = 3000,
  int updatedLocallyAt = 100,
}) {
  return MultisigPendingSession(
    sessionId: sessionId,
    participantId: participantId,
    role: MultisigPendingRole.creator,
    coordinatorUrl: 'https://coordinator.example',
    label: 'Family vault',
    state: 'collecting',
    accessToken: accessToken,
    refreshToken: refreshToken,
    identity: _identity,
    accessTokenExpiresAt: accessTokenExpiresAt,
    refreshTokenExpiresAt: refreshTokenExpiresAt,
    creatorParticipantId: participantId,
    participants: [_pendingParticipant(participantId: participantId)],
    createdAt: 1,
    updatedAt: 2,
    createdLocallyAt: 3,
    updatedLocallyAt: updatedLocallyAt,
  );
}

MultisigPendingParticipant _pendingParticipant({
  String participantId = 'participant-1',
}) {
  return MultisigPendingParticipant(
    participantId: participantId,
    label: 'Signer',
    admissionPublicKey: 'admission-public',
    deliveryPublicKey: 'delivery-public',
    joinedAt: 1,
    dkgCompleted: false,
  );
}

MultisigAccountMaterial _accountMaterial() {
  return const MultisigAccountMaterial(
    accountUuid: 'account-1',
    sessionId: 'session-1',
    participantId: 'participant-1',
    coordinatorUrl: 'https://coordinator.example',
    rosterHash: 'roster',
    groupPublicPackageHash: 'group',
    threshold: 2,
    participantCount: 3,
    identity: _identity,
    keyPackageB64: 'key-package',
    groupPublicPackageJson: '{"group":true}',
    vaultAddress: 'uregtest1example',
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    accessTokenExpiresAt: 900,
    refreshTokenExpiresAt: 3000,
  );
}

rust_multisig.ApiMultisigParticipant _apiParticipant({
  String participantId = 'participant-1',
  String? label = 'Signer',
  bool dkgCompleted = false,
}) {
  return rust_multisig.ApiMultisigParticipant(
    participantId: participantId,
    label: label,
    admissionPublicKey: 'admission-public-$participantId',
    deliveryPublicKey: 'delivery-public-$participantId',
    joinedAt: BigInt.from(1),
    dkgCompleted: dkgCompleted,
  );
}

rust_multisig.ApiMultisigAuthSession _apiAuthSession({
  String sessionId = 'session-1',
  String participantId = 'participant-1',
  String accessToken = 'access-token',
  String refreshToken = 'refresh-token',
  String admissionSecretKey = 'admission-secret',
  String admissionPublicKey = 'admission-public',
  String deliverySecretKey = 'delivery-secret',
  String deliveryPublicKey = 'delivery-public',
  String state = 'collecting',
}) {
  return rust_multisig.ApiMultisigAuthSession(
    sessionId: sessionId,
    participantId: participantId,
    accessToken: accessToken,
    refreshToken: refreshToken,
    admissionSecretKey: admissionSecretKey,
    admissionPublicKey: admissionPublicKey,
    deliverySecretKey: deliverySecretKey,
    deliveryPublicKey: deliveryPublicKey,
    accessTokenExpiresAt: BigInt.from(2000),
    refreshTokenExpiresAt: BigInt.from(3000),
    state: state,
    participant: _apiParticipant(participantId: participantId),
  );
}

rust_multisig.ApiMultisigAuthUpdate _apiAuthUpdate({
  String sessionId = 'session-1',
  String participantId = 'participant-1',
  String accessToken = 'new-access',
  String refreshToken = 'new-refresh',
  String admissionPublicKey = 'new-admission-public',
  String deliverySecretKey = 'new-delivery-secret',
  String deliveryPublicKey = 'new-delivery-public',
  bool resumed = false,
}) {
  return rust_multisig.ApiMultisigAuthUpdate(
    sessionId: sessionId,
    participantId: participantId,
    accessToken: accessToken,
    refreshToken: refreshToken,
    admissionPublicKey: admissionPublicKey,
    deliverySecretKey: deliverySecretKey,
    deliveryPublicKey: deliveryPublicKey,
    accessTokenExpiresAt: BigInt.from(2200),
    refreshTokenExpiresAt: BigInt.from(3200),
    resumed: resumed,
  );
}

rust_multisig.ApiMultisigSession _apiSession({
  String sessionId = 'session-1',
  String state = 'collecting',
  String creatorParticipantId = 'participant-1',
  int? threshold,
  List<rust_multisig.ApiMultisigParticipant>? participants,
}) {
  return rust_multisig.ApiMultisigSession(
    sessionId: sessionId,
    state: state,
    creatorParticipantId: creatorParticipantId,
    threshold: threshold,
    rosterHash: 'roster',
    groupPublicPackageHash: 'group',
    participants: participants ?? [_apiParticipant()],
    createdAt: BigInt.from(10),
    updatedAt: BigInt.from(20),
  );
}

class _FakePendingSessionStore implements MultisigPendingSessionStore {
  final sessions = <String, MultisigPendingSession>{};

  void put(MultisigPendingSession session) {
    sessions[session.storageId] = session;
  }

  @override
  Future<MultisigPendingSession?> read(
    String storageId, {
    bool requireUnlockedSession = true,
  }) async {
    return sessions[storageId];
  }

  @override
  Future<List<MultisigPendingSession>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    return sessions.values.toList(growable: false);
  }

  @override
  Future<void> write(MultisigPendingSession session) async {
    sessions[session.storageId] = session;
  }

  @override
  Future<void> delete(MultisigPendingSession session) async {
    sessions.remove(session.storageId);
  }

  @override
  Future<void> deleteByStorageId(String storageId) async {
    sessions.remove(storageId);
  }
}

class _FakeAccountMaterialStore implements MultisigAccountMaterialStore {
  final materials = <String, MultisigAccountMaterial>{};

  void put(MultisigAccountMaterial material) {
    materials[material.accountUuid] = material;
  }

  @override
  Future<MultisigAccountMaterial?> read(
    String accountUuid, {
    bool requireUnlockedSession = true,
  }) async {
    return materials[accountUuid];
  }

  @override
  Future<List<MultisigAccountMaterial>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    return materials.values.toList(growable: false);
  }

  @override
  Future<void> write(MultisigAccountMaterial material) async {
    materials[material.accountUuid] = material;
  }

  @override
  Future<void> delete(String accountUuid) async {
    materials.remove(accountUuid);
  }
}

class _FakeMultisigCoordinatorService implements MultisigCoordinatorService {
  _FakeMultisigCoordinatorService({
    rust_multisig.ApiMultisigAuthSession? createResponse,
    rust_multisig.ApiMultisigAuthSession? joinResponse,
    rust_multisig.ApiMultisigAuthUpdate? authUpdateResponse,
    rust_multisig.ApiMultisigAuthSession? resumeResponse,
    rust_multisig.ApiMultisigSession? sessionResponse,
    rust_multisig.ApiMultisigSession? lockResponse,
  }) : createResponse = createResponse ?? _apiAuthSession(),
       joinResponse =
           joinResponse ??
           _apiAuthSession(
             sessionId: 'session-join',
             participantId: 'participant-2',
           ),
       authUpdateResponse = authUpdateResponse ?? _apiAuthUpdate(),
       resumeResponse = resumeResponse ?? _apiAuthSession(),
       sessionResponse = sessionResponse ?? _apiSession(),
       lockResponse = lockResponse ?? _apiSession(state: 'ready', threshold: 2);

  final rust_multisig.ApiMultisigAuthSession createResponse;
  final rust_multisig.ApiMultisigAuthSession joinResponse;
  final rust_multisig.ApiMultisigAuthUpdate authUpdateResponse;
  final rust_multisig.ApiMultisigAuthSession resumeResponse;
  final rust_multisig.ApiMultisigSession sessionResponse;
  final rust_multisig.ApiMultisigSession lockResponse;

  final createCalls = <String>[];
  final joinCalls = <String>[];
  final refreshCalls = <String>[];
  final resumeCalls = <String>[];
  final getCalls = <String>[];
  final lockCalls = <String>[];

  @override
  rust_multisig.ApiMultisigParticipantIdentity generateParticipantIdentity() {
    return _apiIdentity;
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> createSession({
    required String coordinatorUrl,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  }) async {
    createCalls.add('$coordinatorUrl|$label|${identity.admissionSecretKey}');
    return createResponse;
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> joinSession({
    required String coordinatorUrl,
    required String sessionId,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  }) async {
    joinCalls.add(
      '$coordinatorUrl|$sessionId|$label|${identity.deliverySecretKey}',
    );
    return joinResponse;
  }

  @override
  Future<rust_multisig.ApiMultisigAuthUpdate> refreshOrResumeAuth({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String refreshToken,
    required String admissionSecretKey,
    required String deliverySecretKey,
  }) async {
    refreshCalls.add('$sessionId|$participantId|$refreshToken');
    return authUpdateResponse;
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> resumeParticipant({
    required String coordinatorUrl,
    required String sessionId,
    required String admissionSecretKey,
    required String deliverySecretKey,
  }) async {
    resumeCalls.add('$sessionId|$admissionSecretKey');
    return resumeResponse;
  }

  @override
  Future<rust_multisig.ApiMultisigSession> getSession({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
  }) async {
    getCalls.add('$sessionId|$accessToken');
    return sessionResponse;
  }

  @override
  Future<rust_multisig.ApiMultisigSession> lockSession({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required int threshold,
  }) async {
    lockCalls.add('$sessionId|$accessToken|$threshold');
    return lockResponse;
  }
}
