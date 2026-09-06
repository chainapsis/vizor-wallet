import '../../rust/api/voting.dart' as rust_api;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import 'voting_endpoint_mapper.dart';
import 'voting_rust_exception.dart';

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

/// Normalized probe outcome for one endpoint.
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

/// Selected endpoint plus a diagnostic for every endpoint probed.
class PirSnapshotResolution {
  final Uri endpoint;
  final List<PirSnapshotEndpointDiagnostic> diagnostics;

  const PirSnapshotResolution({
    required this.endpoint,
    required this.diagnostics,
  });
}

/// No PIR endpoints were configured for the round.
class PirSnapshotNoEndpoints implements Exception {
  const PirSnapshotNoEndpoints();

  @override
  String toString() => 'PirSnapshotNoEndpoints';
}

/// Endpoints were probed and none served the round's snapshot height.
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
      '$expectedSnapshotHeight, diagnostics: $diagnostics)';
}

/// Resolves the PIR endpoint that serves a round's snapshot height.
///
/// Probing, height classification, and selection all happen in Rust; this
/// type is the Dart-side seam so callers and tests keep one place to stub.
/// The endpoint the wallet probes with is the same routed transport that
/// carries the rest of foreground voting traffic.
///
/// Callers pass logical endpoints and get logical endpoints back. The regtest
/// gateway rewrite is applied to what is probed and undone on the way out, so
/// the round's configured identity is what reaches the session state and the
/// PIR failover list.
class PirSnapshotResolver {
  const PirSnapshotResolver({
    VotingEndpointMapper? mapper,
    ResolvePirSnapshotEndpointFn? resolveEndpoint,
  }) : _mapper = mapper,
       _resolveEndpoint =
           resolveEndpoint ?? rust_api.resolvePirSnapshotEndpoint;

  final VotingEndpointMapper? _mapper;
  final ResolvePirSnapshotEndpointFn _resolveEndpoint;

  Uri _transportUri(Uri logicalUrl) =>
      _mapper == null ? logicalUrl : _mapper.map(logicalUrl);

  /// Probes all endpoints and selects one serving [expectedSnapshotHeight].
  ///
  /// Fails closed: an endpoint that cannot be reached or does not serve the
  /// height is never selected. [PirSnapshotNoMatchingEndpoint] carries every
  /// diagnostic so the caller can say which heights were on offer.
  Future<PirSnapshotResolution> resolve({
    required List<Uri> endpoints,
    required int expectedSnapshotHeight,
  }) async {
    if (endpoints.isEmpty) {
      throw const PirSnapshotNoEndpoints();
    }

    final logicalByTransport = <String, Uri>{};
    final transportUrls = <String>[];
    for (final endpoint in endpoints) {
      final transportUrl = _transportUri(endpoint).toString();
      logicalByTransport[transportUrl] = endpoint;
      transportUrls.add(transportUrl);
    }

    final rust_api.ApiPirSnapshotResolution resolution;
    try {
      resolution = await _resolveEndpoint(
        endpoints: transportUrls,
        expectedSnapshotHeight: BigInt.from(expectedSnapshotHeight),
      );
    } on rust_voting.VotingErrorView catch (error) {
      throw VotingRustException(error);
    }

    Uri logical(String probed) =>
        logicalByTransport[probed] ?? Uri.parse(probed);

    final diagnostics = [
      for (final diagnostic in resolution.diagnostics)
        _diagnosticFrom(diagnostic, logical(diagnostic.endpoint)),
    ];
    final endpoint = resolution.endpoint;
    if (endpoint == null) {
      throw PirSnapshotNoMatchingEndpoint(
        expectedSnapshotHeight: expectedSnapshotHeight,
        diagnostics: diagnostics,
      );
    }
    return PirSnapshotResolution(
      endpoint: logical(endpoint),
      diagnostics: diagnostics,
    );
  }

  static PirSnapshotEndpointDiagnostic _diagnosticFrom(
    rust_api.ApiPirSnapshotEndpointDiagnostic diagnostic,
    Uri endpoint,
  ) {
    return PirSnapshotEndpointDiagnostic(
      endpoint: endpoint,
      status: _statusFrom(diagnostic.status),
      reportedHeight: diagnostic.reportedHeight?.toInt(),
      httpStatusCode: diagnostic.httpStatusCode,
      message: diagnostic.message,
    );
  }

  static PirSnapshotEndpointStatus _statusFrom(
    rust_api.ApiPirSnapshotEndpointStatus status,
  ) {
    return switch (status) {
      rust_api.ApiPirSnapshotEndpointStatus.matched =>
        PirSnapshotEndpointStatus.matched,
      rust_api.ApiPirSnapshotEndpointStatus.behind =>
        PirSnapshotEndpointStatus.behind,
      rust_api.ApiPirSnapshotEndpointStatus.ahead =>
        PirSnapshotEndpointStatus.ahead,
      rust_api.ApiPirSnapshotEndpointStatus.missingHeight =>
        PirSnapshotEndpointStatus.missingHeight,
      rust_api.ApiPirSnapshotEndpointStatus.malformedJson =>
        PirSnapshotEndpointStatus.malformedJson,
      rust_api.ApiPirSnapshotEndpointStatus.nonSuccessStatus =>
        PirSnapshotEndpointStatus.nonSuccessStatus,
      rust_api.ApiPirSnapshotEndpointStatus.timeoutOrNetworkError =>
        PirSnapshotEndpointStatus.timeoutOrNetworkError,
    };
  }
}

/// The bridge call [PirSnapshotResolver] drives, injectable for tests.
typedef ResolvePirSnapshotEndpointFn =
    Future<rust_api.ApiPirSnapshotResolution> Function({
      required List<String> endpoints,
      required BigInt expectedSnapshotHeight,
    });
