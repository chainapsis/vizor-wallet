class VotingHelperHealthTracker {
  VotingHelperHealthTracker({
    this.failureThreshold = 3,
    this.cooldown = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : assert(failureThreshold > 0),
       _now = now ?? DateTime.now;

  final int failureThreshold;
  final Duration cooldown;
  final DateTime Function() _now;
  final Map<String, _VotingHelperState> _states = {};

  List<String> candidateServers(Iterable<String> serverUrls) {
    final urls = serverUrls.toList(growable: false);
    if (urls.isEmpty) return const [];

    final current = _now();
    final available = <String>[];
    final unavailable = <String>[];
    for (final url in urls) {
      if (_isAvailable(url, current)) {
        available.add(url);
      } else {
        unavailable.add(url);
      }
    }

    return available.isEmpty ? urls : [...available, ...unavailable];
  }

  void recordSuccess(String serverUrl) {
    _states.remove(serverUrl);
  }

  void recordFailure(String serverUrl) {
    final state = _states.putIfAbsent(serverUrl, _VotingHelperState.new);
    state.consecutiveFailures += 1;
    if (state.consecutiveFailures >= failureThreshold) {
      state.openedAt = _now();
    }
  }

  bool _isAvailable(String serverUrl, DateTime current) {
    final state = _states[serverUrl];
    final openedAt = state?.openedAt;
    if (state == null || openedAt == null) return true;

    if (current.difference(openedAt) >= cooldown) {
      state.openedAt = null;
      state.consecutiveFailures = failureThreshold - 1;
      return true;
    }
    return false;
  }
}

class _VotingHelperState {
  int consecutiveFailures = 0;
  DateTime? openedAt;
}
