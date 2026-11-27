import '../voting_routes.dart';

/// PD-2 directory route pattern.
const kProxyDelegateDirectoryPath = '/voting/poll/:roundId/delegates';

/// PD-3 profile route pattern.
const kProxyDelegateProfilePath =
    '/voting/poll/:roundId/delegates/:delegateIndex';

/// PD-5 allocation editor route pattern.
const kProxyAllocationPath = '/voting/poll/:roundId/delegate';

/// PD-2 directory for [roundId], in picker mode.
String proxyDelegateDirectoryRoute(String roundId) =>
    '${votingPollRoute(roundId)}/delegates';

/// PD-3 profile of [delegateIndex] in [roundId].
String proxyDelegateProfileRoute(String roundId, int delegateIndex) =>
    '${proxyDelegateDirectoryRoute(roundId)}/$delegateIndex';

/// PD-5 allocation editor for [roundId].
String proxyAllocationRoute(String roundId) =>
    '${votingPollRoute(roundId)}/delegate';
