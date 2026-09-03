enum SyncFailureKind {
  network,

  /// The Tor route is enabled but its bootstrap failed. Unlike [network],
  /// nothing retries on its own: Rust stays fail-closed until Tor is retried
  /// or turned off, so the notice has to hand the user those two actions.
  torUnavailable,
  endpoint,
  databaseBusy,
  databaseFatal,
  chainRecovery,
  parseFatal,
  unknown,
}

class SyncFailure {
  final SyncFailureKind kind;
  final String rawMessage;
  final String userMessage;
  final bool showSettingsAction;

  const SyncFailure({
    required this.kind,
    required this.rawMessage,
    required this.userMessage,
    required this.showSettingsAction,
  });

  String get actionLabel => showSettingsAction ? 'Settings' : 'Retry';

  /// Whether "Retry" should re-run the Tor bootstrap rather than the sync.
  /// Restarting the sync against a failed Tor route fails again instantly;
  /// only a new bootstrap (or turning Tor off) can move it.
  bool get retriesTorRoute => kind == SyncFailureKind.torUnavailable;
}

SyncFailure classifySyncFailure(Object error) {
  final rawMessage = _errorText(error);
  final lower = rawMessage.toLowerCase();
  final kind = _classifySyncFailureKind(lower);

  return SyncFailure(
    kind: kind,
    rawMessage: rawMessage,
    userMessage: _syncFailureUserMessage(kind),
    showSettingsAction: kind == SyncFailureKind.endpoint,
  );
}

String _errorText(Object error) {
  const exceptionPrefix = 'Exception: ';
  final message = error.toString();
  if (message.startsWith(exceptionPrefix)) {
    return message.substring(exceptionPrefix.length);
  }
  return message;
}

SyncFailureKind _classifySyncFailureKind(String lower) {
  if (_looksLikeEndpointFailure(lower)) {
    return SyncFailureKind.endpoint;
  }
  if (_looksLikeTorUnavailable(lower)) {
    return SyncFailureKind.torUnavailable;
  }
  if (_looksLikeChainRecoveryFailure(lower)) {
    return SyncFailureKind.chainRecovery;
  }
  if (_looksLikeDatabaseBusy(lower)) {
    return SyncFailureKind.databaseBusy;
  }
  if (lower.startsWith('db:') || lower.contains('sqlite')) {
    return SyncFailureKind.databaseFatal;
  }
  if (lower.startsWith('parse:')) {
    return SyncFailureKind.parseFatal;
  }
  if (_looksLikeNetworkFailure(lower)) {
    return SyncFailureKind.network;
  }
  return SyncFailureKind.unknown;
}

bool _looksLikeEndpointFailure(String lower) {
  return lower.contains('invalid url') ||
      lower.contains('invalid uri') ||
      lower.contains('enter an endpoint') ||
      lower.contains('use an https:// endpoint') ||
      lower.contains('select an endpoint') ||
      lower.contains('network mismatch') ||
      lower.contains('wrong network') ||
      lower.contains('chain name');
}

/// The route resolver's resolved-failure wording (`RouteBlocked` in Rust) and
/// the bootstrap deadline message. "Tor was turned off while it was
/// connecting" and "Tor wait cancelled" are deliberately absent: both are
/// the user's own action and the next sync attempt simply proceeds.
bool _looksLikeTorUnavailable(String lower) {
  return lower.contains('tor connection failed') ||
      lower.contains('tor could not connect') ||
      lower.contains('tor is enabled but unavailable');
}

bool _looksLikeChainRecoveryFailure(String lower) {
  return lower.contains('chain continuity broken') ||
      lower.contains('rewind budget exhausted') ||
      lower.contains('truncate_to_height') ||
      lower.contains('blockconflict') ||
      lower.contains('prevhashmismatch') ||
      lower.contains('blockheightdiscontinuity');
}

bool _looksLikeDatabaseBusy(String lower) {
  return lower.contains('database is locked') ||
      lower.contains('database locked') ||
      lower.contains('database busy') ||
      lower.contains('sqlite lock contention');
}

bool _looksLikeNetworkFailure(String lower) {
  return lower.startsWith('network:') ||
      lower.contains('deadline exceeded') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('unavailable') ||
      lower.contains('cancelled') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('failed to connect') ||
      lower.contains('grpc connect failed') ||
      lower.contains('dns') ||
      lower.contains('tls error') ||
      lower.contains('transport error') ||
      lower.contains('broken pipe') ||
      lower.contains('no route to host');
}

String _syncFailureUserMessage(SyncFailureKind kind) {
  return switch (kind) {
    SyncFailureKind.network =>
      "Network connection lost. We'll keep trying automatically.",
    SyncFailureKind.torUnavailable =>
      "Tor couldn't connect. Retry, or turn Tor off in Settings.",
    SyncFailureKind.endpoint =>
      'Cannot reach the configured Zcash endpoint. Check your endpoint settings.',
    SyncFailureKind.databaseBusy =>
      "Wallet data is busy. We'll try syncing again automatically.",
    SyncFailureKind.databaseFatal =>
      'Wallet data could not be read. Restart the app and retry sync.',
    SyncFailureKind.chainRecovery =>
      "The chain changed while syncing. We'll keep trying to recover.",
    SyncFailureKind.parseFatal =>
      'Sync data could not be processed. Retry sync or check your endpoint.',
    SyncFailureKind.unknown => 'Sync failed. Retry sync to continue.',
  };
}
