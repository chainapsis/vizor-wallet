import 'proxy_delegation_repository.dart';
import 'proxy_delegator_client.dart';
import 'proxy_registry_client.dart';

/// The delegator data source behind the dormant flag: finding and checking
/// delegates through [registry] and everything else through [delegator].
/// The commit proves the delegates again and goes ahead only when every
/// verdict is ok.
class CompositeProxyDelegationRepository implements ProxyDelegationRepository {
  /// Creates the repository.
  CompositeProxyDelegationRepository({
    required this.registry,
    required this.delegator,
  });

  /// zcash_voting's registry client.
  final ProxyRegistryClient registry;

  /// zcash_voting's delegator calls.
  final ProxyDelegatorClient delegator;

  @override
  Future<ProxyRoundContext> roundContext(String roundId) =>
      delegator.roundContext(roundId);

  @override
  Future<ApiProxyAvailability> availability(String roundId) =>
      delegator.availability(roundId);

  @override
  Future<ProxyDelegateBrowse> browse(String roundId) =>
      registry.browse(roundId);

  @override
  Future<List<ProxyDelegateListing>> search(String roundId, String query) =>
      registry.search(roundId, query);

  @override
  Future<ApiDelegateLookup> lookup(String roundId, String text) =>
      registry.lookup(roundId, text);

  @override
  Future<ProxyAllocationPreview> preview(ProxyAllocationRequest request) =>
      delegator.preview(request);

  @override
  Future<List<ApiConfirmedDelegate>> checkDelegates(
    String roundId,
    List<ProxyDelegateChoice> choices,
  ) => registry.check(roundId, choices);

  /// Proves the delegates again right before committing (contracts-v1
  /// section 11.11) and commits with that check's verdicts.
  ///
  /// Throws [ProxyReviewChangedException], having committed nothing, unless
  /// every verdict is ok, so the review shows the new check.
  @override
  Future<void> commit(
    ProxyAllocationRequest request, {
    required ProxyAllocationPreview confirmed,
  }) async {
    final checks = [
      for (final delegate in await registry.check(
        request.roundId,
        request.choices,
      ))
        delegate.check,
    ];
    if (checks.any((check) => check != DelegateCheck.ok)) {
      throw const ProxyReviewChangedException();
    }
    await delegator.commit(request, confirmed: confirmed, checks: checks);
  }

  @override
  Future<ApiProxyAllocationStatus?> allocationStatus(String roundId) =>
      delegator.status(roundId);
}
