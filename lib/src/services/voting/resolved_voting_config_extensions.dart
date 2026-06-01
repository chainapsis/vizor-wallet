import '../../rust/third_party/zcash_voting/config.dart';

extension ResolvedVotingConfigX on ResolvedVotingConfig {
  Uri get apiBaseUrl => Uri.parse(voteServers.first.url);

  List<Uri> get pirEndpointUrls =>
      pirEndpoints.map((endpoint) => Uri.parse(endpoint.url)).toList(growable: false);
}
