import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_voting;
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';
import 'package:zcash_wallet/src/services/voting/voting_endpoint_mapper.dart';

/// Probing, height classification, and selection now run in Rust and are
/// covered by `rust/src/api/voting.rs` unit tests. What is left on this side
/// is the mapping: bridge shapes to Dart types, and a missing endpoint to the
/// typed failure the delegation and warmup paths catch.
rust_voting.PirSnapshotEndpointDiagnosticView diagnostic({
  String endpoint = 'https://pir.example',
  rust_voting.PirSnapshotEndpointStatusView status =
      rust_voting.PirSnapshotEndpointStatusView.matched,
  int? reportedHeight,
  int? httpStatusCode,
  String? message,
}) {
  return rust_voting.PirSnapshotEndpointDiagnosticView(
    endpoint: endpoint,
    status: status,
    reportedHeight: reportedHeight == null
        ? null
        : BigInt.from(reportedHeight),
    httpStatusCode: httpStatusCode,
    message: message,
  );
}

PirSnapshotResolver resolverReturning(
  rust_api.ApiPirSnapshotResolution resolution, {
  void Function(List<String> endpoints, BigInt height)? onCall,
}) {
  return PirSnapshotResolver(
    resolveEndpoint:
        ({
          required List<String> endpoints,
          required BigInt expectedSnapshotHeight,
        }) async {
          onCall?.call(endpoints, expectedSnapshotHeight);
          return resolution;
        },
  );
}

void main() {
  test('empty endpoint list throws typed no-endpoints error', () async {
    // A round with no endpoints is misconfigured, which callers treat
    // differently from a fleet that answered and did not match.
    final resolver = resolverReturning(
      const rust_api.ApiPirSnapshotResolution(diagnostics: []),
    );

    expect(
      resolver.resolve(endpoints: const [], expectedSnapshotHeight: 100),
      throwsA(isA<PirSnapshotNoEndpoints>()),
    );
  });

  test('resolved endpoint carries every diagnostic back', () async {
    // The delegation path builds its PIR failover list from the matched
    // diagnostics, so they must survive the call and not just the selection.
    late List<String> requestedEndpoints;
    late BigInt requestedHeight;
    final resolver = resolverReturning(
      rust_api.ApiPirSnapshotResolution(
        endpoint: 'https://a.example',
        diagnostics: [
          diagnostic(endpoint: 'https://a.example', reportedHeight: 100),
          diagnostic(
            endpoint: 'https://b.example',
            status: rust_voting.PirSnapshotEndpointStatusView.behind,
            reportedHeight: 99,
          ),
        ],
      ),
      onCall: (endpoints, height) {
        requestedEndpoints = endpoints;
        requestedHeight = height;
      },
    );

    final resolution = await resolver.resolve(
      endpoints: [Uri.parse('https://a.example'), Uri.parse('https://b.example')],
      expectedSnapshotHeight: 100,
    );

    expect(requestedEndpoints, ['https://a.example', 'https://b.example']);
    expect(requestedHeight, BigInt.from(100));
    expect(resolution.endpoint, Uri.parse('https://a.example'));
    expect(resolution.diagnostics, hasLength(2));
    expect(resolution.diagnostics.first.matched, isTrue);
    expect(resolution.diagnostics.last.matched, isFalse);
    expect(resolution.diagnostics.last.reportedHeight, 99);
  });

  test('no matching endpoint fails closed with its diagnostics', () async {
    final resolver = resolverReturning(
      rust_api.ApiPirSnapshotResolution(
        diagnostics: [
          diagnostic(
            endpoint: 'https://a.example',
            status: rust_voting.PirSnapshotEndpointStatusView.behind,
            reportedHeight: 99,
          ),
        ],
      ),
    );

    await expectLater(
      resolver.resolve(
        endpoints: [Uri.parse('https://a.example')],
        expectedSnapshotHeight: 100,
      ),
      throwsA(
        isA<PirSnapshotNoMatchingEndpoint>()
            .having((e) => e.expectedSnapshotHeight, 'height', 100)
            .having((e) => e.diagnostics, 'diagnostics', hasLength(1)),
      ),
    );
  });

  test('every bridge status maps to its Dart status', () async {
    // The status screen branches on `behind` specifically, so a silent
    // mismapping here would change what the user is told to do.
    const pairs = <rust_voting.PirSnapshotEndpointStatusView,
        PirSnapshotEndpointStatus>{
      rust_voting.PirSnapshotEndpointStatusView.matched:
          PirSnapshotEndpointStatus.matched,
      rust_voting.PirSnapshotEndpointStatusView.behind:
          PirSnapshotEndpointStatus.behind,
      rust_voting.PirSnapshotEndpointStatusView.ahead:
          PirSnapshotEndpointStatus.ahead,
      rust_voting.PirSnapshotEndpointStatusView.missingHeight:
          PirSnapshotEndpointStatus.missingHeight,
      rust_voting.PirSnapshotEndpointStatusView.malformedJson:
          PirSnapshotEndpointStatus.malformedJson,
      rust_voting.PirSnapshotEndpointStatusView.nonSuccessStatus:
          PirSnapshotEndpointStatus.nonSuccessStatus,
      rust_voting.PirSnapshotEndpointStatusView.timeoutOrNetworkError:
          PirSnapshotEndpointStatus.timeoutOrNetworkError,
    };

    for (final entry in pairs.entries) {
      final resolver = resolverReturning(
        rust_api.ApiPirSnapshotResolution(
          endpoint: 'https://a.example',
          diagnostics: [
            diagnostic(status: entry.key, reportedHeight: 100, httpStatusCode: 503),
          ],
        ),
      );

      final resolution = await resolver.resolve(
        endpoints: [Uri.parse('https://a.example')],
        expectedSnapshotHeight: 100,
      );

      expect(resolution.diagnostics.single.status, entry.value);
      expect(resolution.diagnostics.single.httpStatusCode, 503);
    }
  });

  test('the regtest gateway rewrite is applied to probes only', () async {
    // The probe has to reach the local gateway, but the round's configured
    // identity is what the session state and the PIR failover list carry, so
    // the rewrite must not leak into the result.
    final mapper = VotingEndpointMapper(
      isRegtest: true,
      gatewayUrl: 'http://127.0.0.1:18232',
    );
    const logical = 'https://pir.vizor-vote.invalid';
    final mapped = mapper.map(Uri.parse(logical)).toString();
    expect(mapped, isNot(logical), reason: 'mapper must rewrite in regtest');

    late List<String> probed;
    final resolver = PirSnapshotResolver(
      mapper: mapper,
      resolveEndpoint:
          ({
            required List<String> endpoints,
            required BigInt expectedSnapshotHeight,
          }) async {
            probed = endpoints;
            return rust_api.ApiPirSnapshotResolution(
              endpoint: endpoints.single,
              diagnostics: [
                rust_voting.PirSnapshotEndpointDiagnosticView(
                  endpoint: endpoints.single,
                  status: rust_voting.PirSnapshotEndpointStatusView.matched,
                  reportedHeight: expectedSnapshotHeight,
                ),
              ],
            );
          },
    );

    final resolution = await resolver.resolve(
      endpoints: [Uri.parse(logical)],
      expectedSnapshotHeight: 100,
    );

    expect(probed, [mapped]);
    expect(resolution.endpoint, Uri.parse(logical));
    expect(resolution.diagnostics.single.endpoint, Uri.parse(logical));
  });
}
