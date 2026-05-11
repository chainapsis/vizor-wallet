import 'dart:convert';
import 'dart:math' as math;

import 'voting_http.dart';

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

/// Resolves a PIR endpoint whose snapshot root is exactly the expected height.
///
/// Exact matching is deliberate. A behind endpoint cannot answer for the round's
/// required snapshot, and an ahead endpoint may reveal a different anonymity set
/// than the one authenticated by the voting round configuration.
class PirSnapshotResolver {
  PirSnapshotResolver({
    required VotingHttpClient httpClient,
    math.Random? random,
    Duration timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient,
       _random = random ?? math.Random.secure(),
       _timeout = timeout;

  final VotingHttpClient _httpClient;
  final math.Random _random;
  final Duration _timeout;

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
    final matches = diagnostics
        .where((diagnostic) => diagnostic.matched)
        .map((diagnostic) => diagnostic.endpoint)
        .toList(growable: false);
    if (matches.isEmpty) {
      throw PirSnapshotNoMatchingEndpoint(
        expectedSnapshotHeight: expectedSnapshotHeight,
        diagnostics: diagnostics,
      );
    }

    return PirSnapshotResolution(
      endpoint: matches[_random.nextInt(matches.length)],
      diagnostics: diagnostics,
    );
  }

  Future<PirSnapshotEndpointDiagnostic> _probeEndpoint({
    required Uri endpoint,
    required int expectedSnapshotHeight,
  }) async {
    try {
      final response = await _httpClient.get(
        _rootUri(endpoint),
        timeout: _timeout,
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

  static int? _heightFromRoot(Map<dynamic, dynamic> root) {
    final value =
        root['height'] ??
        root['root_height'] ??
        root['rootHeight'] ??
        root['snapshot_height'] ??
        root['snapshotHeight'];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
