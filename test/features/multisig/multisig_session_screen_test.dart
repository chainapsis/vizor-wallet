import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/multisig/screens/multisig_session_screen.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_realtime_provider.dart';

void main() {
  testWidgets('start create keeps advancing while create is in progress', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = _FakePendingSessionsNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSecurityProvider.overrideWith(
            () => _UnlockedAppSecurityNotifier(),
          ),
          multisigPendingSessionsProvider.overrideWith(() => notifier),
          multisigPendingSessionSummariesProvider.overrideWith(
            (ref) async => const <MultisigPendingSessionSummary>[],
          ),
          multisigRealtimeProvider.overrideWith(
            () => _NoopMultisigRealtimeNotifier(),
          ),
        ],
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: MultisigSessionScreen(
              sessionStorageId: notifier.session.storageId,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Start create'), findsOneWidget);

    await tester.ensureVisible(find.text('Start create'));
    await tester.pump();
    await tester.tap(find.text('Start create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(notifier.advanceCalls, 1);
    expect(find.text('Continue'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1));

    expect(notifier.advanceCalls, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _NoopMultisigRealtimeNotifier extends MultisigRealtimeNotifier {
  @override
  MultisigRealtimeState build() => const MultisigRealtimeState();

  @override
  MultisigRealtimeLease acquire(
    MultisigRealtimeTarget target, {
    required String reason,
  }) {
    return MultisigRealtimeLease.noop();
  }

  @override
  bool updateTarget(MultisigRealtimeTarget target) => true;
}

class _UnlockedAppSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  }
}

class _FakePendingSessionsNotifier extends MultisigPendingSessionsNotifier {
  final session = _pendingSession();
  int refreshCalls = 0;
  int advanceCalls = 0;

  @override
  Future<List<MultisigPendingSession>> build() async => [session];

  @override
  Future<MultisigPendingSession> refreshSession(String storageId) async {
    refreshCalls++;
    state = AsyncData([session]);
    return session;
  }

  @override
  Future<MultisigCreateAdvanceResult> advanceCreate(String storageId) async {
    advanceCalls++;
    final progress = MultisigCreateAdvanceResult(
      session: session,
      phase: 'waiting_for_round1',
      detail: 'Waiting for DKG round 1 messages.',
      waitingForParticipantIds: const ['participant-2'],
      round1Count: advanceCalls,
      round2Count: 0,
      dkgCompleteSubmitted: false,
    );
    state = AsyncData([session]);
    return progress;
  }
}

const _identity = MultisigParticipantIdentity(
  admissionSecretKey: 'admission-secret',
  admissionPublicKey: 'admission-public',
  deliverySecretKey: 'delivery-secret',
  deliveryPublicKey: 'delivery-public',
);

MultisigPendingSession _pendingSession() {
  return const MultisigPendingSession(
    sessionId: 'session-1',
    participantId: 'participant-1',
    role: MultisigPendingRole.creator,
    coordinatorUrl: 'https://coordinator.example',
    label: 'Family vault',
    state: 'request_create',
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    identity: _identity,
    inviteSecret: 'invite-secret',
    accessTokenExpiresAt: 2000,
    refreshTokenExpiresAt: 3000,
    creatorParticipantId: 'participant-1',
    threshold: 2,
    rosterHash: 'roster',
    participants: [
      MultisigPendingParticipant(
        participantId: 'participant-1',
        label: 'Signer 1',
        admissionPublicKey: 'admission-public-1',
        deliveryPublicKey: 'delivery-public-1',
        joinedAt: 1,
        dkgCompleted: false,
      ),
      MultisigPendingParticipant(
        participantId: 'participant-2',
        label: 'Signer 2',
        admissionPublicKey: 'admission-public-2',
        deliveryPublicKey: 'delivery-public-2',
        joinedAt: 2,
        dkgCompleted: false,
      ),
    ],
    createdAt: 1,
    updatedAt: 2,
    createdLocallyAt: 3,
    updatedLocallyAt: 4,
  );
}
