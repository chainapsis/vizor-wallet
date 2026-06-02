import 'dart:async';
import 'dart:io';

import 'voting_models.dart';

Future<T> retryVotingOperation<T>({
  required Future<T> Function() operation,
  required List<Duration> delays,
  required String label,
  Future<void> Function(Duration delay)? delay,
}) async {
  final wait = delay ?? Future<void>.delayed;
  Object? lastError;
  for (var attempt = 0; attempt <= delays.length; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt == delays.length || !isRetryableVotingError(error)) {
        rethrow;
      }
      await wait(delays[attempt]);
    }
  }
  throw StateError('$label retry exited unexpectedly: $lastError');
}

bool isRetryableVotingError(Object error) {
  if (error is TimeoutException ||
      error is SocketException ||
      error is HttpException) {
    return true;
  }
  if (error is VotingHttpException) {
    return error.statusCode == 502 || error.statusCode == 503;
  }
  return false;
}
