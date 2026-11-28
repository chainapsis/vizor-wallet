import '../voting_routes.dart';

/// PD-2 directory route pattern.
const kProxyDelegateDirectoryPath = '/voting/poll/:roundId/delegates';

/// PD-5 allocation editor route pattern.
const kProxyAllocationPath = '/voting/poll/:roundId/delegate';

/// PD-2 directory for [roundId], in picker mode.
String proxyDelegateDirectoryRoute(String roundId) =>
    '${votingPollRoute(roundId)}/delegates';

/// PD-5 allocation editor for [roundId].
String proxyAllocationRoute(String roundId) =>
    '${votingPollRoute(roundId)}/delegate';
