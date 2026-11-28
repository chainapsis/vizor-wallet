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

/// Delegate mode home: DG-1 intro or the DG-8 dashboard.
const kDelegateModePath = '/voting/delegate-mode';

/// Import of an exported delegate key.
const kDelegateKeyImportPath = '/voting/delegate-mode/import';

/// Marker, proof link and on-chain registration.
const kDelegateRegistrationPath = '/voting/delegate-mode/register';

/// DG-9 ballot route pattern; DG-10 is its confirm sheet.
const kDelegateBallotPath = '/voting/delegate-mode/rounds/:roundId';

/// DG-11 Retire.
const kDelegateRetirePath = '/voting/delegate-mode/retire';

/// DG-9 ballot for [roundId].
String delegateBallotRoute(String roundId) =>
    '/voting/delegate-mode/rounds/${Uri.encodeComponent(roundId)}';
