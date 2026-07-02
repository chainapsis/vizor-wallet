import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_coordinator_service.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_realtime_cursor_store.dart';
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

  test(
    'exposes pending session summaries while the wallet is locked',
    () async {
      final store = _FakePendingSessionStore()
        ..put(_pendingSession(sessionId: 'locked-session'));
      final container = _container(store: store, isUnlocked: false);
      addTearDown(container.dispose);

      expect(
        await container.read(multisigPendingSessionsProvider.future),
        isEmpty,
      );

      final summaries = await container.read(
        multisigPendingSessionSummariesProvider.future,
      );

      expect(summaries, hasLength(1));
      expect(summaries.single.storageId, 'locked-session:participant-1');
      expect(summaries.single.sessionId, 'locked-session');
    },
  );

  test(
    'ignores stale summaries after the encrypted pending session is gone',
    () async {
      final session = _pendingSession(sessionId: 'stale-session');
      final store = _FakePendingSessionStore()
        ..summaries[session.storageId] =
            MultisigPendingSessionSummary.fromSession(session);
      final container = _container(store: store, isUnlocked: false);
      addTearDown(container.dispose);

      final summaries = await container.read(
        multisigPendingSessionSummariesProvider.future,
      );

      expect(summaries, isEmpty);
    },
  );

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
    expect(store.summaries[created.storageId]?.label, 'Family vault');
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
    expect(store.summaries[joined.storageId]?.label, 'Signer 2');
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
    'refreshSessionFromEvents advances cursor after canonical refresh',
    () async {
      final store = _FakePendingSessionStore();
      final session = _pendingSession(accessTokenExpiresAt: 2000);
      store.put(session);
      final cursorStore = _FakeRealtimeCursorStore()
        ..cursors[session.storageId] = const MultisigRealtimeCursor(
          eventsCursor: 7,
        );
      final service = _FakeMultisigCoordinatorService(
        eventsCursor: 12,
        sessionResponse: _apiSession(state: 'locked', threshold: 2),
      );
      final container = _container(
        store: store,
        service: service,
        cursorStore: cursorStore,
      );
      addTearDown(container.dispose);

      final refreshed = await container
          .read(multisigPendingSessionsProvider.notifier)
          .refreshSessionFromEvents(session.storageId);

      expect(service.eventsCalls, ['session-1|7']);
      expect(service.getCalls, ['session-1|access-token']);
      expect(refreshed.state, 'locked');
      expect(store.sessions[session.storageId]!.threshold, 2);
      expect(cursorStore.cursors[session.storageId]?.eventsCursor, 12);
    },
  );

  test(
    'refreshSessionFromEvents does not advance cursor when events fail',
    () async {
      final store = _FakePendingSessionStore();
      final session = _pendingSession(accessTokenExpiresAt: 2000);
      store.put(session);
      final cursorStore = _FakeRealtimeCursorStore()
        ..cursors[session.storageId] = const MultisigRealtimeCursor(
          eventsCursor: 7,
        );
      final service = _FakeMultisigCoordinatorService(
        eventsError: StateError('network down'),
      );
      final container = _container(
        store: store,
        service: service,
        cursorStore: cursorStore,
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(multisigPendingSessionsProvider.notifier)
            .refreshSessionFromEvents(session.storageId),
        throwsA(anything),
      );

      expect(service.eventsCalls, ['session-1|7']);
      expect(service.getCalls, isEmpty);
      expect(cursorStore.cursors[session.storageId]?.eventsCursor, 7);
    },
  );

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
    expect(store.summaries, isEmpty);
    expect(container.read(multisigPendingSessionsProvider).value, isEmpty);
  });

  test('local setup helper skips materialized sessions', () {
    final materialized = _pendingSession(sessionId: 'materialized');
    final next = _pendingSession(sessionId: 'next');

    expect(
      latestLocalMultisigSetupSession(
        [materialized, next],
        {materialized.storageId},
      ),
      same(next),
    );
    expect(
      latestLocalMultisigSetupSession([materialized], {materialized.storageId}),
      isNull,
    );
    expect(
      multisigSessionNeedsLocalSetup(materialized, {materialized.storageId}),
      isFalse,
    );
    expect(
      multisigSessionNeedsLocalSetup(
        _pendingSession(sessionId: 'failed').copyWith(state: 'failed'),
      ),
      isFalse,
    );

    expect(
      latestLocalMultisigSetupSummary(
        [
          MultisigPendingSessionSummary.fromSession(materialized),
          MultisigPendingSessionSummary.fromSession(next),
        ],
        {materialized.storageId},
      )?.storageId,
      next.storageId,
    );
  });

  test('local setup helper treats participants in one session separately', () {
    final participant1 = _pendingSession(
      sessionId: 'shared-session',
      participantId: 'participant-1',
      updatedLocallyAt: 100,
    );
    final participant2 = _pendingSession(
      sessionId: 'shared-session',
      participantId: 'participant-2',
      updatedLocallyAt: 200,
    );

    expect(
      latestLocalMultisigSetupSession(
        [participant1, participant2],
        {participant1.storageId},
      ),
      same(participant2),
    );
    expect(
      multisigSessionNeedsLocalSetup(participant2, {participant1.storageId}),
      isTrue,
    );
  });

  test(
    'refreshSession keeps fields written while the fetch was in flight',
    () async {
      final store = _FakePendingSessionStore();
      final gate = Completer<void>();
      final service = _GatedGetSessionCoordinatorService(gate);
      final container = _container(store: store, service: service);
      addTearDown(container.dispose);
      final notifier = container.read(multisigPendingSessionsProvider.notifier);
      await container.read(multisigPendingSessionsProvider.future);
      final pending = _pendingSession(accessTokenExpiresAt: 99999);
      await notifier.upsert(pending);

      final refresh = notifier.refreshSession(pending.storageId);
      // Let refreshSession park on the gated getSession call, then land a
      // concurrent local write (this is what advance-create does when it
      // stores the DKG key package).
      await Future<void>.delayed(Duration.zero);
      await notifier.upsert(pending.copyWith(keyPackageB64: 'key-package'));
      gate.complete();
      final refreshed = await refresh;

      expect(refreshed.keyPackageB64, 'key-package');
      final sessions = container.read(multisigPendingSessionsProvider).value!;
      expect(sessions.single.keyPackageB64, 'key-package');
      expect(store.sessions[pending.storageId]?.keyPackageB64, 'key-package');
    },
  );

  test(
    'auth refresher shares a single in-flight refresh per participant',
    () async {
      final gate = Completer<void>();
      final service = _GatedRefreshCoordinatorService(gate);
      final container = _container(service: service);
      addTearDown(container.dispose);
      final refresher = container.read(multisigAuthRefresherProvider);

      Future<rust_multisig.ApiMultisigAuthUpdate> call() {
        return refresher.refreshOrResume(
          coordinatorUrl: 'https://coordinator.example',
          sessionId: 'session-1',
          participantId: 'participant-1',
          refreshToken: 'refresh-token',
          admissionSecretKey: 'admission-secret',
          deliverySecretKey: 'delivery-secret',
        );
      }

      final first = call();
      final second = call();
      gate.complete();
      final results = await Future.wait([first, second]);

      expect(service.refreshCalls, hasLength(1));
      expect(results[0].accessToken, results[1].accessToken);

      await call();
      expect(service.refreshCalls, hasLength(2));
    },
  );
}

class _GatedGetSessionCoordinatorService
    extends _FakeMultisigCoordinatorService {
  _GatedGetSessionCoordinatorService(this.gate);

  final Completer<void> gate;

  @override
  Future<rust_multisig.ApiMultisigSession> getSession({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
  }) async {
    await gate.future;
    return super.getSession(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      accessToken: accessToken,
    );
  }
}

class _GatedRefreshCoordinatorService extends _FakeMultisigCoordinatorService {
  _GatedRefreshCoordinatorService(this.gate);

  final Completer<void> gate;

  @override
  Future<rust_multisig.ApiMultisigAuthUpdate> refreshOrResumeAuth({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String refreshToken,
    required String admissionSecretKey,
    required String deliverySecretKey,
  }) async {
    await gate.future;
    return super.refreshOrResumeAuth(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      participantId: participantId,
      refreshToken: refreshToken,
      admissionSecretKey: admissionSecretKey,
      deliverySecretKey: deliverySecretKey,
    );
  }
}

ProviderContainer _container({
  _FakePendingSessionStore? store,
  _FakeAccountMaterialStore? materialStore,
  _FakeMultisigCoordinatorService? service,
  _FakeRealtimeCursorStore? cursorStore,
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
      multisigRealtimeCursorStoreProvider.overrideWithValue(
        cursorStore ?? _FakeRealtimeCursorStore(),
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
  final summaries = <String, MultisigPendingSessionSummary>{};
  final createStates = <String, String>{};

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
  Future<List<MultisigPendingSessionSummary>> readAllSummaries() async {
    final result = <MultisigPendingSessionSummary>[];
    final summarizedIds = <String>{};
    for (final summary in summaries.values) {
      if (!sessions.containsKey(summary.storageId)) continue;
      result.add(summary);
      summarizedIds.add(summary.storageId);
    }
    for (final session in sessions.values) {
      if (summarizedIds.contains(session.storageId)) continue;
      result.add(
        MultisigPendingSessionSummary.fromStorageId(session.storageId),
      );
    }
    return result;
  }

  @override
  Future<void> writeSummary(MultisigPendingSession session) async {
    summaries[session.storageId] = MultisigPendingSessionSummary.fromSession(
      session,
    );
  }

  @override
  Future<void> rebuildSummaries(
    Iterable<MultisigPendingSession> sessions,
  ) async {
    summaries.clear();
    for (final session in sessions) {
      await writeSummary(session);
    }
  }

  @override
  Future<void> delete(MultisigPendingSession session) async {
    sessions.remove(session.storageId);
  }

  @override
  Future<void> deleteByStorageId(String storageId) async {
    sessions.remove(storageId);
  }

  @override
  Future<void> deleteSummary(String storageId) async {
    summaries.remove(storageId);
  }

  @override
  Future<void> deleteAllSummaries() async {
    summaries.clear();
  }

  @override
  Future<String?> readCreateState(MultisigPendingSession session) async {
    return createStates[session.storageId];
  }

  @override
  Future<void> writeCreateState(
    MultisigPendingSession session,
    String localStateJson,
  ) async {
    createStates[session.storageId] = localStateJson;
  }

  @override
  Future<void> deleteCreateState(MultisigPendingSession session) async {
    createStates.remove(session.storageId);
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

class _FakeRealtimeCursorStore implements MultisigRealtimeCursorStore {
  final cursors = <String, MultisigRealtimeCursor>{};

  @override
  Future<MultisigRealtimeCursor> read(String storageId) async {
    return cursors[storageId] ?? const MultisigRealtimeCursor();
  }

  @override
  Future<void> write(String storageId, MultisigRealtimeCursor cursor) async {
    cursors[storageId] = cursor;
  }

  @override
  Future<void> advanceInboxCursor(String storageId, int cursor) async {
    final current = await read(storageId);
    if (cursor <= current.inboxCursor) return;
    await write(storageId, current.copyWith(inboxCursor: cursor));
  }

  @override
  Future<void> advanceEventsCursor(String storageId, int cursor) async {
    final current = await read(storageId);
    if (cursor <= current.eventsCursor) return;
    await write(storageId, current.copyWith(eventsCursor: cursor));
  }

  @override
  Future<void> clear(String storageId) async {
    cursors.remove(storageId);
  }

  @override
  Future<void> clearAll() async {
    cursors.clear();
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
    this.eventsCursor = 0,
    this.eventsError,
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
  final int eventsCursor;
  final Object? eventsError;

  final createCalls = <String>[];
  final joinCalls = <String>[];
  final refreshCalls = <String>[];
  final resumeCalls = <String>[];
  final getCalls = <String>[];
  final lockCalls = <String>[];
  final eventsCalls = <String>[];

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
  Future<rust_multisig.ApiMultisigSessionEvents> getSessionEvents({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required int after,
  }) async {
    eventsCalls.add('$sessionId|$after');
    final error = eventsError;
    if (error != null) throw error;
    return rust_multisig.ApiMultisigSessionEvents(
      cursor: eventsCursor,
      events: const <rust_multisig.ApiMultisigSessionEvent>[],
    );
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

  @override
  Future<rust_multisig.ApiPreparedMultisigSigningRequest>
  prepareSigningRequest({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String requestSeed,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required bool needsSaplingParams,
    required String amountZatoshi,
    required String feeZatoshi,
    required String recipientAddress,
    String? memo,
  }) async {
    return rust_multisig.ApiPreparedMultisigSigningRequest(
      signingRequestId: 'signing-request',
      sessionId: sessionId,
      requesterParticipantId: participantId,
      selectedParticipantIds: selectedParticipantIds,
      requestJson: '{}',
      idempotencyKey: 'idempotency',
      pcztHash: 'pczt-hash',
      createdAt: BigInt.one,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningRequest> submitPreparedSigningRequest({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required String pcztHash,
    required String requestJson,
    required String idempotencyKey,
  }) async {
    return rust_multisig.ApiMultisigSigningRequest(
      signingRequestId: 'signing-request',
      sessionId: sessionId,
      requesterParticipantId: 'participant-1',
      selectedParticipantIds: const <String>['participant-1'],
      state: 'open',
      createdAt: BigInt.one,
      updatedAt: BigInt.from(2),
      pcztHash: pcztHash,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningInbox> getSigningInbox({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required int after,
  }) async {
    return const rust_multisig.ApiMultisigSigningInbox(
      cursor: 0,
      messages: <rust_multisig.ApiMultisigSigningMessage>[],
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningAdvance> submitSigningRound1({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String keyPackageB64,
    String? localStateJson,
  }) async {
    return const rust_multisig.ApiMultisigSigningAdvance(
      localStateJson: '{}',
      detail: 'submitted',
      submitted: true,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningAdvance> submitSigningRound2({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String keyPackageB64,
    String? localStateJson,
  }) async {
    return const rust_multisig.ApiMultisigSigningAdvance(
      localStateJson: '{}',
      detail: 'submitted',
      submitted: true,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSignedPczt> aggregateSignedPczt({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String groupPublicPackageJson,
    String? localStateJson,
  }) async {
    return rust_multisig.ApiMultisigSignedPczt(
      localStateJson: '{}',
      signedPcztBytes: Uint8List.fromList(pcztBytes),
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningAdvance> postBroadcastResult({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required List<String> selectedParticipantIds,
    required String pcztHash,
    required String txid,
    String? localStateJson,
  }) async {
    return const rust_multisig.ApiMultisigSigningAdvance(
      localStateJson: '{}',
      detail: 'submitted',
      submitted: true,
    );
  }
}
