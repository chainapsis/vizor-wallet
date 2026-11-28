import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_proof_client.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegation.dart' as rust;
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

/// A JSON answer with [status].
VotingHttpResponse proofJson(Object body, {int status = 200}) =>
    VotingHttpResponse(
      statusCode: status,
      bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );

/// A healthy proof host's answer to [uri] at tip [height]. Every answer
/// names its host, so the fake bridge can tell where evidence came from.
VotingHttpResponse proofHostAnswer(Uri uri, int height) {
  final host = uri.host;
  return switch (uri.pathSegments.isEmpty ? '' : uri.pathSegments.last) {
    'commit' => proofJson({
      'result': {
        'signed_header': {
          'header': {'height': '$height', 'host': host},
        },
      },
    }),
    'validators' => proofJson({
      'result': {'validators': const [], 'host': host},
    }),
    'abci_query' => proofJson({
      'result': {
        'response': {'key': uri.queryParameters['data'], 'host': host},
      },
    }),
    _ => proofJson(const {}, status: 404),
  };
}

/// Proof hosts behind a [VotingHttpClient], healthy unless told otherwise.
class FakeProofHosts implements VotingHttpClient {
  /// Creates the hosts.
  FakeProofHosts({
    this.failing = const {},
    this.statuses = const {},
    this.oversized = const {},
    this.storeValues = const {},
    this.onRequest,
  });

  /// Hosts whose every request throws this error.
  final Map<String, Object> failing;

  /// Hosts whose every answer carries this status.
  final Map<String, int> statuses;

  /// Hosts whose answers exceed the client's size limit.
  final Set<String> oversized;

  /// Raw store values by queried `data`, `0x` and the key's hex; an
  /// unproven query for any other key finds it absent.
  final Map<String, Uint8List> storeValues;

  /// Runs before each request is answered.
  final void Function()? onRequest;

  /// Every request, in order.
  final requests = <Uri>[];

  /// The timeout of every request, in order.
  final timeouts = <Duration?>[];

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async {
    requests.add(uri);
    timeouts.add(timeout);
    onRequest?.call();
    final error = failing[uri.host];
    if (error != null) throw error;
    final status = statuses[uri.host];
    if (status != null) return proofJson(const {}, status: status);
    if (oversized.contains(uri.host)) {
      return VotingHttpResponse(
        statusCode: 200,
        bodyBytes: Uint8List(ProxyRegistryProofClient.maxResponseBytes + 1),
      );
    }
    final stored = storeValues[uri.queryParameters['data']];
    if (stored != null && !uri.queryParameters.containsKey('prove')) {
      return proofJson({
        'result': {
          'response': {'code': 0, 'value': base64Encode(stored)},
        },
      });
    }
    return proofHostAnswer(uri, 101);
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration? timeout,
    int? maxBodyBytes,
  }) => throw UnsupportedError('Proof hosts are only read');
}

/// One verification the fake bridge saw.
class VerifiedEvidence {
  /// Records a verification.
  const VerifiedEvidence({
    required this.network,
    required this.delegateIndices,
    required this.json,
  });

  /// The network whose anchor verified it.
  final String network;

  /// The entries proven, in order.
  final List<int> delegateIndices;

  /// The evidence.
  final Map<String, dynamic> json;
}

/// Stands in for Rust's reader: derives entry keys as the shared crate does
/// and accepts evidence from any host but [rejectedHosts]. Odd entries hold
/// `[8, d]` and even ones are proven absent.
class FakeRegistryProofRust {
  /// Hosts whose evidence fails verification.
  final rejectedHosts = <String>{};

  /// Every verification, in order.
  final verified = <VerifiedEvidence>[];

  /// The host each verified evidence came from, in order.
  List<String> get verifiedHosts => [
    for (final evidence in verified) _host(evidence.json),
  ];

  Future<List<String>> entryKeys(List<int> delegateIndices) async {
    return [
      for (final d in delegateIndices)
        '1a01${d.toRadixString(16).padLeft(8, '0')}',
    ];
  }

  Future<List<rust.ApiProvenRegistryEntry>> verify({
    required String network,
    required List<int> delegateIndices,
    required String evidence,
  }) async {
    final json = jsonDecode(evidence) as Map<String, dynamic>;
    verified.add(
      VerifiedEvidence(
        network: network,
        delegateIndices: delegateIndices,
        json: json,
      ),
    );
    if (rejectedHosts.contains(_host(json))) {
      throw StateError('Voting participation evidence could not be verified');
    }
    return [
      for (final d in delegateIndices)
        rust.ApiProvenRegistryEntry(
          delegateIndex: d,
          entry: d.isOdd ? Uint8List.fromList([8, d]) : null,
        ),
    ];
  }

  /// The host named in [evidence]'s commit.
  static String _host(Map<String, dynamic> evidence) =>
      ((((evidence['commit'] as Map)['result'] as Map)['signed_header']
                  as Map)['header']
              as Map)['host']
          as String;
}
