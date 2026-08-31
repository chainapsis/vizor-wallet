import 'dart:convert';
import 'dart:math' as math;

import 'voting_http.dart';
import 'voting_models.dart';
import 'voting_retry.dart';

/// Probe outcome for one configured PIR endpoint.
///
/// Anything other than [matched] excludes the endpoint from selection. The
/// caller still receives diagnostics so the UI can explain whether endpoints
/// were stale, ahead of the expected snapshot, malformed, or unreachable.
enum PirSnapshotEndpointStatus {
  matched,
  behind,
  ahead,
  missingHeight,
  malformedJson,
  nonSuccessStatus,
  timeoutOrNetworkError,
}

class PirSnapshotEndpointDiagnostic {
  final Uri endpoint;
  final PirSnapshotEndpointStatus status;
  final int? reportedHeight;
  final int? httpStatusCode;
  final String? message;

  const PirSnapshotEndpointDiagnostic({
    required this.endpoint,
    required this.status,
    this.reportedHeight,
    this.httpStatusCode,
    this.message,
  });

  bool get matched => status == PirSnapshotEndpointStatus.matched;
}

class PirSnapshotResolution {
  final Uri endpoint;
  final List<PirSnapshotEndpointDiagnostic> diagnostics;

  const PirSnapshotResolution({
    required this.endpoint,
    required this.diagnostics,
  });
}

class PirSnapshotNoEndpoints implements Exception {
  const PirSnapshotNoEndpoints();

  @override
  String toString() => 'PirSnapshotNoEndpoints';
}

class PirSnapshotNoMatchingEndpoint implements Exception {
  final int expectedSnapshotHeight;
  final List<PirSnapshotEndpointDiagnostic> diagnostics;

  const PirSnapshotNoMatchingEndpoint({
    required this.expectedSnapshotHeight,
    required this.diagnostics,
  });

  @override
  String toString() =>
      'PirSnapshotNoMatchingEndpoint(expectedSnapshotHeight: '
      '$expectedSnapshotHeight, diagnostics: ${diagnostics.length})';
}

/// Chooses an exact-height endpoint from completed probe diagnostics.
///
/// The SDK owns this protocol policy. The resolver retains HTTP probing so it
/// can use the wallet's routed client and expose transport diagnostics.
typedef PirSnapshotEndpointSelector =
    Uri? Function({
      required List<PirSnapshotEndpointDiagnostic> diagnostics,
      required int expectedSnapshotHeight,
      required int matchIndex,
    });

/// Resolves a PIR endpoint whose snapshot root is exactly the expected height.
///
/// Exact matching is deliberate. A behind endpoint cannot answer for the round's
/// required snapshot, and an ahead endpoint may reveal a different anonymity set
/// than the one expected by the selected voting round. Optional `/root`
/// identity fields such as `network_id` or `round_id` are not used for
/// selection; the selected round data supplies the expected height.
class PirSnapshotResolver {
  PirSnapshotResolver({
    required VotingHttpClient httpClient,
    required PirSnapshotEndpointSelector selectEndpoint,
    math.Random? random,
    Duration timeout = const Duration(seconds: 10),
    VotingRetryPolicy? retryPolicy,
    Future<void> Function(Duration delay)? delay,
  }) : _httpClient = httpClient,
       _selectEndpoint = selectEndpoint,
       _random = random ?? math.Random.secure(),
       _timeout = timeout,
       _retryPolicy =
           retryPolicy ??
           VotingRetryPolicy.transientHttp(
             name: 'voting-pir-probe',
             delays: const [Duration.zero],
           ),
       _delay = delay ?? Future<void>.delayed;

  final VotingHttpClient _httpClient;
  final PirSnapshotEndpointSelector _selectEndpoint;
  final math.Random _random;
  final Duration _timeout;
  final VotingRetryPolicy _retryPolicy;
  final Future<void> Function(Duration delay) _delay;

  /// Probes all endpoints and randomly selects among exact-height matches.
  ///
  /// The method fails closed when no endpoint matches, carrying diagnostics for
  /// every endpoint that was considered.
  Future<PirSnapshotResolution> resolve({
    required List<Uri> endpoints,
    required int expectedSnapshotHeight,
  }) async {
    if (endpoints.isEmpty) {
      throw const PirSnapshotNoEndpoints();
    }

    final diagnostics = await Future.wait(
      endpoints.map(
        (endpoint) => _probeEndpoint(
          endpoint: endpoint,
          expectedSnapshotHeight: expectedSnapshotHeight,
        ),
      ),
    );
    final endpoint = _selectEndpoint(
      diagnostics: diagnostics,
      expectedSnapshotHeight: expectedSnapshotHeight,
      matchIndex: _random.nextInt(1 << 32),
    );
    if (endpoint == null) {
      throw PirSnapshotNoMatchingEndpoint(
        expectedSnapshotHeight: expectedSnapshotHeight,
        diagnostics: diagnostics,
      );
    }

    return PirSnapshotResolution(endpoint: endpoint, diagnostics: diagnostics);
  }

  Future<PirSnapshotEndpointDiagnostic> _probeEndpoint({
    required Uri endpoint,
    required int expectedSnapshotHeight,
  }) async {
    try {
      final rootUri = _rootUri(endpoint);
      final response = await withVotingRetry(
        policy: _retryPolicy,
        delay: _delay,
        operation: () async {
          final response = await _httpClient.get(rootUri, timeout: _timeout);
          if (response.statusCode != 200) {
            final error = VotingHttpException(
              uri: rootUri,
              statusCode: response.statusCode,
              body: response.bodyText,
            );
            if (isRetryableVotingError(error)) {
              throw error;
            }
          }
          return response;
        },
      );
      if (response.statusCode != 200) {
        return PirSnapshotEndpointDiagnostic(
          endpoint: endpoint,
          status: PirSnapshotEndpointStatus.nonSuccessStatus,
          httpStatusCode: response.statusCode,
          message: response.bodyText,
        );
      }
      final decoded = jsonDecode(response.bodyText);
      if (decoded is! Map) {
        return PirSnapshotEndpointDiagnostic(
          endpoint: endpoint,
          status: PirSnapshotEndpointStatus.malformedJson,
          message: 'root response is not a JSON object',
        );
      }
      final height = _heightFromRoot(decoded);
      if (height == null) {
        return PirSnapshotEndpointDiagnostic(
          endpoint: endpoint,
          status: PirSnapshotEndpointStatus.missingHeight,
          message: 'root response did not include height',
        );
      }
      if (height < expectedSnapshotHeight) {
        return PirSnapshotEndpointDiagnostic(
          endpoint: endpoint,
          status: PirSnapshotEndpointStatus.behind,
          reportedHeight: height,
        );
      }
      if (height > expectedSnapshotHeight) {
        return PirSnapshotEndpointDiagnostic(
          endpoint: endpoint,
          status: PirSnapshotEndpointStatus.ahead,
          reportedHeight: height,
        );
      }
      return PirSnapshotEndpointDiagnostic(
        endpoint: endpoint,
        status: PirSnapshotEndpointStatus.matched,
        reportedHeight: height,
      );
    } on VotingHttpException catch (e) {
      return PirSnapshotEndpointDiagnostic(
        endpoint: endpoint,
        status: PirSnapshotEndpointStatus.nonSuccessStatus,
        httpStatusCode: e.statusCode,
        message: e.body,
      );
    } on FormatException catch (e) {
      return PirSnapshotEndpointDiagnostic(
        endpoint: endpoint,
        status: PirSnapshotEndpointStatus.malformedJson,
        message: e.message,
      );
    } catch (e) {
      return PirSnapshotEndpointDiagnostic(
        endpoint: endpoint,
        status: PirSnapshotEndpointStatus.timeoutOrNetworkError,
        message: e.toString(),
      );
    }
  }

  static Uri _rootUri(Uri endpoint) {
    final pathSegments = endpoint.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    return endpoint.replace(pathSegments: [...pathSegments, 'root']);
  }

  static final _unsignedIntegerPattern = RegExp(r'^\d+$');
  static final _maxU64 = BigInt.parse('18446744073709551615');

  /// Returns `/root.height`, or null when the canonical height field is absent.
  /// Throws [FormatException] when `height` is present but malformed.
  static int? _heightFromRoot(Map<dynamic, dynamic> root) {
    if (!root.containsKey('height')) return null;
    return _parseRootHeightField(root['height']);
  }

  /// Parses `/root.height` as a JSON integer or decimal string in the unsigned
  /// 64-bit range.
  static int _parseRootHeightField(Object? value) {
    if (value is int && value >= 0 && BigInt.from(value) <= _maxU64) {
      return value;
    }
    if (value is String && _unsignedIntegerPattern.hasMatch(value)) {
      final height = BigInt.parse(value);
      if (height <= _maxU64) {
        return int.parse(value);
      }
    }
    throw const FormatException(
      '/root field "height" is not a valid u64 height',
    );
  }
}
