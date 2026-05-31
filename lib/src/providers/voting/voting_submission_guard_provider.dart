import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kVotingSubmissionInProgressMessage =
    'Vote submission is still running. Wait for it to finish before '
    'changing wallet state.';

/// Marker for a vote submission that is using account state in this process.
///
/// Wallet mutations such as account deletion and reset must not run while a
/// guarded submission is active, because those mutations can remove the DB,
/// hotkeys, or Rust session state the submission still depends on.
@immutable
class VotingSubmissionGuard {
  const VotingSubmissionGuard({
    required this.token,
    required this.accountUuid,
    required this.roundId,
  });

  final int token;
  final String accountUuid;
  final String roundId;

  String get message => kVotingSubmissionInProgressMessage;
}

/// Thrown when a wallet mutation cannot run during vote submission.
class VotingSubmissionInProgressException implements Exception {
  const VotingSubmissionInProgressException(this.guard);

  final VotingSubmissionGuard guard;

  String get message => guard.message;

  @override
  String toString() => message;
}

/// Tracks active vote submissions that should block destructive wallet changes.
///
/// The guard is intentionally held only in memory. It protects active app work,
/// not persisted recovery state.
class VotingSubmissionGuardNotifier
    extends Notifier<List<VotingSubmissionGuard>> {
  int _nextToken = 0;

  @override
  List<VotingSubmissionGuard> build() => const [];

  /// Registers a guarded submission for an account/round pair.
  ///
  /// Re-acquiring the same pair returns the existing guard so nested callers can
  /// share one lifecycle token.
  VotingSubmissionGuard acquire({
    required String accountUuid,
    required String roundId,
  }) {
    final existing = guardFor(accountUuid: accountUuid, roundId: roundId);
    if (existing != null) {
      return existing;
    }
    final guard = VotingSubmissionGuard(
      token: _nextToken++,
      accountUuid: accountUuid,
      roundId: roundId,
    );
    state = [...state, guard];
    return guard;
  }

  /// Releases a previously acquired guard.
  ///
  /// Release is idempotent so cleanup paths can call it from `finally` blocks
  /// without first checking provider state.
  void release(VotingSubmissionGuard guard) {
    state = [
      for (final activeGuard in state)
        if (activeGuard.token != guard.token) activeGuard,
    ];
  }

  /// Finds an active guard for one account/round pair.
  VotingSubmissionGuard? guardFor({
    required String accountUuid,
    required String roundId,
  }) {
    for (final guard in state) {
      if (guard.accountUuid == accountUuid && guard.roundId == roundId) {
        return guard;
      }
    }
    return null;
  }

  /// Finds any active guard for an account.
  VotingSubmissionGuard? guardForAccount(String accountUuid) {
    for (final guard in state) {
      if (guard.accountUuid == accountUuid) return guard;
    }
    return null;
  }

  /// Returns whether an account/round pair is currently guarded.
  bool isGuarded({required String accountUuid, required String roundId}) {
    return guardFor(accountUuid: accountUuid, roundId: roundId) != null;
  }

  /// Blocks destructive wallet mutations while any submission is active.
  void throwIfActive() {
    if (state.isEmpty) return;
    throw VotingSubmissionInProgressException(state.first);
  }
}

/// App-wide registry of in-flight voting submissions.
final votingSubmissionGuardProvider =
    NotifierProvider<
      VotingSubmissionGuardNotifier,
      List<VotingSubmissionGuard>
    >(VotingSubmissionGuardNotifier.new);
