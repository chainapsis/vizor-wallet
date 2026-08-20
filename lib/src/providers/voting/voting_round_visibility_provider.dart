import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Install-local preference for showing authenticated test voting rounds.
const votingShowTestRoundsStorageKey = 'vizor_voting_show_test_rounds';

/// Persists whether test voting rounds should appear in the vote menu.
abstract interface class VotingRoundVisibilityStore {
  Future<bool> readShowTestRounds();

  Future<void> writeShowTestRounds(bool show);
}

/// Shared preferences implementation of [VotingRoundVisibilityStore].
class SharedPreferencesVotingRoundVisibilityStore
    implements VotingRoundVisibilityStore {
  const SharedPreferencesVotingRoundVisibilityStore();

  @override
  Future<bool> readShowTestRounds() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(votingShowTestRoundsStorageKey) ?? false;
  }

  @override
  Future<void> writeShowTestRounds(bool show) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(
      votingShowTestRoundsStorageKey,
      show,
    );
    if (!saved) {
      throw StateError('Could not save the test round visibility preference.');
    }
  }
}

/// Injectable persistence used by [showTestVotingRoundsProvider].
final votingRoundVisibilityStoreProvider = Provider<VotingRoundVisibilityStore>(
  (_) => const SharedPreferencesVotingRoundVisibilityStore(),
);

/// Loads and updates the test round visibility preference.
class ShowTestVotingRoundsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      return await ref
          .watch(votingRoundVisibilityStoreProvider)
          .readShowTestRounds();
    } catch (error) {
      debugPrint(
        '[zcash] Voting: failed to load test round visibility: $error',
      );
      return false;
    }
  }

  /// Persists [show] before publishing it to vote menu consumers.
  Future<void> setShowTestRounds(bool show) async {
    if (state.value == show) return;
    await ref
        .read(votingRoundVisibilityStoreProvider)
        .writeShowTestRounds(show);
    state = AsyncData(show);
  }
}

/// Whether authenticated rounds whose titles start with `[TEST]` are visible.
final showTestVotingRoundsProvider =
    AsyncNotifierProvider<ShowTestVotingRoundsNotifier, bool>(
      ShowTestVotingRoundsNotifier.new,
    );
