import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kVotingSubmissionInProgressMessage =
    'Vote submission is still running. Wait for it to finish before '
    'changing wallet state.';

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

class VotingSubmissionInProgressException implements Exception {
  const VotingSubmissionInProgressException(this.guard);

  final VotingSubmissionGuard guard;

  String get message => guard.message;

  @override
  String toString() => message;
}

class VotingSubmissionGuardNotifier
    extends Notifier<List<VotingSubmissionGuard>> {
  int _nextToken = 0;

  @override
  List<VotingSubmissionGuard> build() => const [];

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

  void release(VotingSubmissionGuard guard) {
    state = [
      for (final activeGuard in state)
        if (activeGuard.token != guard.token) activeGuard,
    ];
  }

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

  VotingSubmissionGuard? guardForAccount(String accountUuid) {
    for (final guard in state) {
      if (guard.accountUuid == accountUuid) return guard;
    }
    return null;
  }

  bool isGuarded({required String accountUuid, required String roundId}) {
    return guardFor(accountUuid: accountUuid, roundId: roundId) != null;
  }

  void throwIfActive() {
    if (state.isEmpty) return;
    throw VotingSubmissionInProgressException(state.first);
  }
}

final votingSubmissionGuardProvider =
    NotifierProvider<
      VotingSubmissionGuardNotifier,
      List<VotingSubmissionGuard>
    >(VotingSubmissionGuardNotifier.new);
