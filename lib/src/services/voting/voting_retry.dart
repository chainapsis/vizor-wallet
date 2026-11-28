import 'dart:async';
import 'dart:io';

import '../../core/network/network_http_client.dart';
import 'voting_models.dart';
import 'voting_rust_exception.dart';

class VotingRetryPolicy {
  const VotingRetryPolicy({
    required this.name,
    required this.delays,
    required bool Function(Object error) shouldRetry,
  }) : _shouldRetry = shouldRetry;

  factory VotingRetryPolicy.transientHttp({
    required String name,
    required List<Duration> delays,
  }) {
    return VotingRetryPolicy(
      name: name,
      delays: delays,
      shouldRetry: isRetryableVotingError,
    );
  }

  final String name;
  final List<Duration> delays;
  final bool Function(Object error) _shouldRetry;

  bool shouldRetry(Object error) => _shouldRetry(error);
}

Future<T> withVotingRetry<T>({
  required VotingRetryPolicy policy,
  required Future<T> Function() operation,
  Future<void> Function(Duration delay)? delay,
  bool Function()? isCancelled,
}) async {
  final wait = delay ?? Future<void>.delayed;
  Object? lastError;
  for (var attempt = 0; attempt <= policy.delays.length; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt == policy.delays.length ||
          !policy.shouldRetry(error) ||
          (isCancelled?.call() ?? false)) {
        rethrow;
      }
      await wait(policy.delays[attempt]);
      if (isCancelled?.call() ?? false) rethrow;
    }
  }
  throw StateError('${policy.name} retry exited unexpectedly: $lastError');
}

Future<T> retryVotingOperation<T>({
  required Future<T> Function() operation,
  required List<Duration> delays,
  required String label,
  Future<void> Function(Duration delay)? delay,
}) async {
  return withVotingRetry(
    policy: VotingRetryPolicy.transientHttp(name: label, delays: delays),
    operation: operation,
    delay: delay,
  );
}

bool isRetryableVotingError(Object error) {
  if (error is VotingRustException) return error.retryable;
  if (error is TimeoutException ||
      error is SocketException ||
      error is HttpException) {
    return true;
  }
  if (error is VotingHttpException) {
    return error.statusCode == 429 ||
        error.statusCode == 500 ||
        error.statusCode == 502 ||
        error.statusCode == 503 ||
        error.statusCode == 504;
  }
  return false;
}

/// Whether [error] is a request that got no answer at all: refused or
/// reset connections, Tor failures (the Tor bridge throws its errors as
/// bare strings), timeouts, TLS failures, direct requests blocked while the
/// route switches to Tor, and bodies cut off past their size limit (an
/// [HttpException] direct, a string over Tor). None of these is a chain
/// verdict, so proxy delegation shows them as an unreachable server, never
/// as a rejection.
bool isVotingTransportError(Object error) =>
    error is String ||
    error is SocketException ||
    error is HttpException ||
    error is TlsException ||
    error is TimeoutException ||
    error is DirectNetworkRequestsBlockedException;
