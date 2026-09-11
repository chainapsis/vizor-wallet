import 'voting_http.dart';

const votingDiscoveryUrlEnvKey = 'VIZOR_VOTING_DISCOVERY_URL';
const votingDiscoveryUrl = String.fromEnvironment(
  votingDiscoveryUrlEnvKey,
  defaultValue: 'https://functions.vizor.cash/v1/voting/discovery/prod',
);

const votingDiscoveryStageUrlEnvKey = 'VIZOR_VOTING_DISCOVERY_STAGE_URL';
const votingDiscoveryStageUrl = String.fromEnvironment(
  votingDiscoveryStageUrlEnvKey,
  defaultValue: 'https://functions.vizor.cash/v1/voting/discovery/stage',
);

enum VotingDiscoveryScope { prod, stage }

class VotingDiscoverySnapshot {
  const VotingDiscoverySnapshot({
    required this.revision,
    required this.checkedAt,
  });
  final String revision;
  final DateTime checkedAt;
}

/// Public invalidation hint only; config authentication remains in Rust.
class VotingDiscoveryClient {
  VotingDiscoveryClient(this.http);
  final VotingHttpClient http;

  Future<VotingDiscoverySnapshot> fetch(
    Uri endpoint,
    DateTime Function() now, {
    VotingDiscoveryScope scope = VotingDiscoveryScope.prod,
  }) async {
    if (endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasFragment ||
        (endpoint.scheme != 'https' &&
            !(endpoint.scheme == 'http' &&
                const [
                  'localhost',
                  '127.0.0.1',
                  '::1',
                ].contains(endpoint.host)))) {
      throw const FormatException('Invalid voting discovery endpoint');
    }
    final response = await http.get(
      endpoint,
      timeout: const Duration(seconds: 5),
    );
    if (response.statusCode != 200 || response.bodyBytes.length > 65536) {
      throw StateError('Voting discovery unavailable (${response.statusCode})');
    }
    final json = response.decodeJsonObject();
    final revision = json['revision'];
    final checkedAt = json['checkedAt'];
    if (json['schemaVersion'] != 1 ||
        json['scope'] != scope.name ||
        revision is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(revision) ||
        checkedAt is! String ||
        !checkedAt.endsWith('Z')) {
      throw const FormatException('Invalid voting discovery response');
    }
    final timestamp = DateTime.tryParse(checkedAt);
    if (timestamp == null) {
      throw const FormatException('Invalid discovery timestamp');
    }
    final age = now().toUtc().difference(timestamp);
    // Allow small device clock differences; stale hints never bless the full list.
    if (age >= const Duration(minutes: 10) ||
        age < const Duration(minutes: -1)) {
      throw const FormatException('Stale voting discovery response');
    }
    return VotingDiscoverySnapshot(revision: revision, checkedAt: timestamp);
  }
}
