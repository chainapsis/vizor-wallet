import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/multisig/screens/multisig_create_session_screen.dart';
import 'package:zcash_wallet/src/features/multisig/screens/multisig_join_session_screen.dart';
import 'package:zcash_wallet/src/features/multisig/widgets/multisig_setup_security_gate.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_coordinator_service.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';
import 'package:zcash_wallet/src/rust/api/multisig.dart' as rust_multisig;

void main() {
  testWidgets(
    'create session configures password before storing pending state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final security = _FakeAppSecurityNotifier(
        initialState: const AppSecurityState(
          isPasswordConfigured: false,
          isUnlocked: false,
        ),
      );
      final store = _FakePendingSessionStore();
      final coordinator = _FakeMultisigCoordinatorService();

      await tester.pumpWidget(
        _harness(
          initialLocation: '/multisig/create',
          security: security,
          store: store,
          coordinator: coordinator,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kMultisigSetupPasswordFieldKey), findsOneWidget);
      expect(find.byKey(kMultisigSetupConfirmPasswordFieldKey), findsOneWidget);

      await tester.enterText(find.byType(EditableText).at(2), 'password123');
      await tester.enterText(find.byType(EditableText).at(3), 'password123');
      await tester.tap(find.text('Create session'));
      await tester.pumpAndSettle();

      expect(security.prepareCalls, 1);
      expect(security.commitCalls, 1);
      expect(security.rollbackCalls, 0);
      expect(coordinator.createCalls, hasLength(1));
      expect(store.sessions.values.single.sessionId, 'session-1');
      expect(find.text('session:session-1:participant-1'), findsOneWidget);
    },
  );

  testWidgets('create session rolls password setup back when create fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final security = _FakeAppSecurityNotifier(
      initialState: const AppSecurityState(
        isPasswordConfigured: false,
        isUnlocked: false,
      ),
    );
    final coordinator = _FakeMultisigCoordinatorService(
      createError: StateError('coordinator unavailable'),
    );

    await tester.pumpWidget(
      _harness(
        initialLocation: '/multisig/create',
        security: security,
        coordinator: coordinator,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(2), 'password123');
    await tester.enterText(find.byType(EditableText).at(3), 'password123');

    await tester.tap(find.text('Create session'));
    await tester.pumpAndSettle();

    expect(security.prepareCalls, 1);
    expect(security.commitCalls, 0);
    expect(security.rollbackCalls, 1);
    expect(find.textContaining('coordinator unavailable'), findsOneWidget);
  });

  testWidgets(
    'create session keeps password fields hidden when already unlocked',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final security = _FakeAppSecurityNotifier(
        initialState: const AppSecurityState(
          isPasswordConfigured: true,
          isUnlocked: true,
        ),
      );
      final store = _FakePendingSessionStore();
      final coordinator = _FakeMultisigCoordinatorService();

      await tester.pumpWidget(
        _harness(
          initialLocation: '/multisig/create',
          security: security,
          store: store,
          coordinator: coordinator,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kMultisigSetupPasswordFieldKey), findsNothing);
      expect(find.byKey(kMultisigSetupConfirmPasswordFieldKey), findsNothing);

      await tester.tap(find.text('Create session'));
      await tester.pumpAndSettle();

      expect(security.prepareCalls, 0);
      expect(security.unlockCalls, 0);
      expect(coordinator.createCalls, hasLength(1));
      expect(store.sessions.values.single.sessionId, 'session-1');
      expect(find.text('session:session-1:participant-1'), findsOneWidget);
    },
  );

  testWidgets('join session unlocks configured storage before storing state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final security = _FakeAppSecurityNotifier(
      initialState: const AppSecurityState(
        isPasswordConfigured: true,
        isUnlocked: false,
      ),
    );
    final store = _FakePendingSessionStore();
    final coordinator = _FakeMultisigCoordinatorService();

    await tester.pumpWidget(
      _harness(
        initialLocation: '/multisig/join',
        security: security,
        store: store,
        coordinator: coordinator,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kMultisigSetupPasswordFieldKey), findsOneWidget);
    expect(find.byKey(kMultisigSetupConfirmPasswordFieldKey), findsNothing);

    await tester.enterText(find.byType(EditableText).at(0), 'session-join');
    await tester.enterText(find.byType(EditableText).at(3), 'password123');
    await tester.tap(find.text('Join session'));
    await tester.pumpAndSettle();

    expect(security.unlockCalls, 1);
    expect(security.prepareCalls, 0);
    expect(security.commitCalls, 0);
    expect(coordinator.joinCalls, hasLength(1));
    expect(store.sessions.values.single.sessionId, 'session-join');
    expect(find.text('session:session-join:participant-2'), findsOneWidget);
  });
}

Widget _harness({
  required String initialLocation,
  required _FakeAppSecurityNotifier security,
  _FakePendingSessionStore? store,
  _FakeMultisigCoordinatorService? coordinator,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/multisig/create',
        builder: (_, _) => const MultisigCreateSessionScreen(),
      ),
      GoRoute(
        path: '/multisig/join',
        builder: (_, _) => const MultisigJoinSessionScreen(),
      ),
      GoRoute(
        path: '/multisig/session/:sessionStorageId',
        builder: (_, state) => Text(
          'session:${Uri.decodeComponent(state.pathParameters['sessionStorageId'] ?? '')}',
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      appSecurityProvider.overrideWith(() => security),
      multisigPendingSessionStoreProvider.overrideWithValue(
        store ?? _FakePendingSessionStore(),
      ),
      multisigCoordinatorServiceProvider.overrideWithValue(
        coordinator ?? _FakeMultisigCoordinatorService(),
      ),
      multisigNowProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(
        data: AppThemeData.light,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

class _FakeAppSecurityNotifier extends AppSecurityNotifier {
  _FakeAppSecurityNotifier({required this.initialState});

  final AppSecurityState initialState;
  int prepareCalls = 0;
  int commitCalls = 0;
  int rollbackCalls = 0;
  int unlockCalls = 0;

  @override
  AppSecurityState build() => initialState;

  @override
  Future<void> preparePasswordSetup(String password) async {
    prepareCalls++;
  }

  @override
  void commitPasswordSetup() {
    commitCalls++;
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  @override
  Future<void> rollbackPasswordSetup() async {
    rollbackCalls++;
    state = const AppSecurityState(
      isPasswordConfigured: false,
      isUnlocked: false,
    );
  }

  @override
  Future<bool> unlock(String password) async {
    unlockCalls++;
    if (password != 'password123') return false;
    state = state.copyWith(isUnlocked: true);
    return true;
  }
}

class _FakePendingSessionStore implements MultisigPendingSessionStore {
  final sessions = <String, MultisigPendingSession>{};
  final summaries = <String, MultisigPendingSessionSummary>{};
  final createStates = <String, String>{};

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

class _FakeMultisigCoordinatorService extends RustMultisigCoordinatorService {
  _FakeMultisigCoordinatorService({this.createError});

  final Object? createError;
  final createCalls = <String>[];
  final joinCalls = <String>[];

  @override
  rust_multisig.ApiMultisigParticipantIdentity generateParticipantIdentity() {
    return const rust_multisig.ApiMultisigParticipantIdentity(
      admissionSecretKey: 'admission-secret',
      admissionPublicKey: 'admission-public',
      deliverySecretKey: 'delivery-secret',
      deliveryPublicKey: 'delivery-public',
    );
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> createSession({
    required String coordinatorUrl,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  }) async {
    createCalls.add('$coordinatorUrl|$label|${identity.admissionSecretKey}');
    final error = createError;
    if (error != null) throw error;
    return _apiAuthSession();
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> joinSession({
    required String coordinatorUrl,
    required String sessionId,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  }) async {
    joinCalls.add('$coordinatorUrl|$sessionId|$label');
    return _apiAuthSession(
      sessionId: sessionId,
      participantId: 'participant-2',
    );
  }
}

rust_multisig.ApiMultisigAuthSession _apiAuthSession({
  String sessionId = 'session-1',
  String participantId = 'participant-1',
}) {
  return rust_multisig.ApiMultisigAuthSession(
    sessionId: sessionId,
    participantId: participantId,
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    admissionSecretKey: 'admission-secret',
    admissionPublicKey: 'admission-public',
    deliverySecretKey: 'delivery-secret',
    deliveryPublicKey: 'delivery-public',
    accessTokenExpiresAt: BigInt.from(2000),
    refreshTokenExpiresAt: BigInt.from(3000),
    state: 'collecting',
    participant: rust_multisig.ApiMultisigParticipant(
      participantId: participantId,
      label: 'Signer',
      admissionPublicKey: 'admission-public-$participantId',
      deliveryPublicKey: 'delivery-public-$participantId',
      joinedAt: BigInt.from(1),
      dkgCompleted: false,
    ),
  );
}
