enum SyncFailureKind {
  network,
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
  final bool isAutoRetrying;
  final bool canManualRetry;
  final bool showSettingsAction;

  const SyncFailure({
    required this.kind,
    required this.rawMessage,
    required this.userMessage,
    required this.isAutoRetrying,
    required this.canManualRetry,
    required this.showSettingsAction,
  });

  String get actionLabel => showSettingsAction ? 'Settings' : 'Retry';
}

SyncFailure classifySyncFailure(Object error) {
  final rawMessage = _errorText(error);
  final lower = rawMessage.toLowerCase();
  final kind = _classifySyncFailureKind(lower);

  return SyncFailure(
    kind: kind,
    rawMessage: rawMessage,
    userMessage: _syncFailureUserMessage(kind),
    isAutoRetrying: _syncFailureAutoRetries(kind),
    canManualRetry: kind != SyncFailureKind.endpoint,
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

bool _syncFailureAutoRetries(SyncFailureKind kind) {
  return switch (kind) {
    SyncFailureKind.network ||
    SyncFailureKind.databaseBusy ||
    SyncFailureKind.chainRecovery ||
    SyncFailureKind.unknown => true,
    SyncFailureKind.endpoint ||
    SyncFailureKind.databaseFatal ||
    SyncFailureKind.parseFatal => false,
  };
}
