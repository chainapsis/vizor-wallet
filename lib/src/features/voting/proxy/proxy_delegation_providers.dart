import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/proxy_delegation_feature_config.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/voting/proxy_delegator_host.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_service_providers.dart';
import '../../../providers/voting/voting_share_tracking_registry_provider.dart';
import '../../../services/voting/resolved_voting_config_extensions.dart';
import '../../../services/voting/voting_api_client.dart';
import '../../../services/voting/voting_endpoint_mapper.dart';
import '../../../services/voting/voting_http.dart';
import '../../../services/voting/voting_participation_client.dart';
import '../voting_flow_models.dart';
import 'composite_proxy_delegation_repository.dart';
import 'proxy_delegation_presentation.dart';
import 'proxy_delegation_repository.dart';
import 'proxy_delegator_client.dart';
import 'proxy_registry_client.dart';
import 'proxy_registry_fetcher.dart';
import 'proxy_registry_proof_client.dart';
import 'proxy_registry_providers.dart';

/// Clock for every delegator screen, so timing states are testable.
final proxyClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// The round's key for the active account, or null while none is active.
/// Every delegator state is keyed by it, so each account has its own and a
/// commit stays with the account its review confirmed.
final proxyActiveSessionKeyProvider = Provider.autoDispose
    .family<VotingSessionKey?, String>((ref, roundId) {
      final account = ref.watch(
        accountProvider.select((accounts) => accounts.value?.activeAccountUuid),
      );
      return account == null
          ? null
          : VotingSessionKey(roundId: roundId, accountUuid: account);
    });

/// The delegator data source pinned to one round and account, whichever
/// account is active: zcash_voting's registry client and delegator calls
/// over that account's submission session.
final proxyDelegationRepositoryProvider = Provider.autoDispose
    .family<ProxyDelegationRepository, VotingSessionKey>((ref, key) {
      final clock = ref.watch(proxyClockProvider);
      return CompositeProxyDelegationRepository(
        registry: ref.watch(proxyRegistryClientProvider),
        delegator: ProxyDelegatorClient(
          host: SessionProxyDelegatorHost(ref, key: key, clock: clock),
          clock: clock,
        ),
      );
    });

/// The one HTTP client of every proxy delegation network role: proof RPC
/// hosts, registry mirrors and verifiers. It rides the selected network
/// route, so a role's failover changes the host but never the route, and it
/// maps the regtest harness's logical hosts as the voting config fetch does.
/// Which hosts a role may use is [proxyRegistryHostAllowed].
final proxyHttpClientProvider = Provider<VotingHttpClient>((ref) {
  final http = DartIoVotingHttpClient();
  ref.onDispose(() => http.close(force: true));
  return MappedVotingHttpClient(http, ref.watch(votingEndpointMapperProvider));
});

/// Registry proof requests over the proxy HTTP client.
final proxyRegistryProofClientProvider = Provider<ProxyRegistryProofClient>(
  (ref) => ProxyRegistryProofClient(
    ref.watch(proxyHttpClientProvider),
    clock: ref.watch(proxyClockProvider),
  ),
);

/// Registry document fetches over the proxy HTTP client.
final proxyRegistryFetcherProvider = Provider<ProxyRegistryFetcher>(
  (ref) => ProxyRegistryFetcher(ref.watch(proxyHttpClientProvider)),
);

/// zcash_voting's registry client for the delegator screens and delegate
/// mode.
final proxyRegistryClientProvider = Provider<ProxyRegistryClient>((ref) {
  final network = ref.watch(proxyRegistryNetworkProvider);
  Future<VotingApiClient> voteServers() async {
    final config = await ref.read(votingConfigProvider.future);
    return ref.read(votingApiClientProvider(config.apiServers));
  }

  return ProxyRegistryClient(
    network: network,
    sources: ref.watch(proxyServiceSourcesProvider),
    store: ref.watch(proxyRegistryStoreProvider),
    fetcher: ref.watch(proxyRegistryFetcherProvider),
    proofs: ref.watch(proxyRegistryProofClientProvider),
    chainGet: (path) async => (await voteServers()).getChainAnswer(path),
    firstNewIndex: (roundId) async => proxyNextDelegateIndexAtCreation(
      (await (await voteServers()).getRoundStatus(roundId)).rawJson,
    ),
    beginWork: () =>
        ref.read(votingShareTrackingRegistryProvider).beginBackgroundWork(),
    builtInProofHost: builtInVotingRpcEndpoint(network),
    clock: ref.watch(proxyClockProvider),
  );
});

/// Retry policy for every fallible delegator provider: none. Each screen
/// offers its own "Try again", and Riverpod's default backoff would keep a
/// failed check loading for about half a minute, hiding states such as the
/// trust-anchor failure.
Duration? proxyNoRetry(int retryCount, Object error) => null;

/// Round facts for the delegator screens.
final proxyRoundContextProvider = FutureProvider.autoDispose
    .family<ProxyRoundContext, VotingSessionKey>((ref, key) {
      return ref
          .watch(proxyDelegationRepositoryProvider(key))
          .roundContext(key.roundId);
    }, retry: proxyNoRetry);

/// The round's committed allocation, or null before delegating.
final proxyAllocationStatusProvider = FutureProvider.autoDispose
    .family<ApiProxyAllocationStatus?, VotingSessionKey>((ref, key) {
      return ref
          .watch(proxyDelegationRepositoryProvider(key))
          .allocationStatus(key.roundId);
    }, retry: proxyNoRetry);

/// Availability for new allocations in the round.
final proxyAvailabilityProvider = FutureProvider.autoDispose
    .family<ApiProxyAvailability, VotingSessionKey>((ref, key) {
      return ref
          .watch(proxyDelegationRepositoryProvider(key))
          .availability(key.roundId);
    }, retry: proxyNoRetry);

/// What the round screen's delegation line shows. Hidden whenever the
/// dormant flag is off, without touching the repository.
final proxyEntryKindProvider = FutureProvider.autoDispose
    .family<ProxyEntryKind, VotingSessionKey>((ref, key) async {
      if (!ref.watch(proxyDelegationFeatureEnabledProvider)) {
        return ProxyEntryKind.hidden;
      }
      final status = await ref.watch(proxyAllocationStatusProvider(key).future);
      if (status != null) return ProxyEntryKind.locked;
      try {
        final availability = await ref.watch(
          proxyAvailabilityProvider(key).future,
        );
        return proxyEntryKindFor(status: null, availability: availability);
      } on ProxyDelegationError catch (error) {
        if (error.kind == ProxyDelegationErrorKind.cannotVerify) {
          return ProxyEntryKind.cannotVerify;
        }
        rethrow;
      }
    }, retry: proxyNoRetry);

/// PD-2 search state.
sealed class ProxySearchState {
  const ProxySearchState();
}

/// No search entered: the browse list shows.
final class ProxySearchIdle extends ProxySearchState {
  /// Creates the state.
  const ProxySearchIdle();
}

/// Matching [query] against the registry's handles.
final class ProxySearchRunning extends ProxySearchState {
  /// Creates the state.
  const ProxySearchRunning(this.query);

  /// The query being matched.
  final String query;
}

/// Exact matches for [query]; empty when nothing matched.
final class ProxySearchResults extends ProxySearchState {
  /// Creates the state.
  const ProxySearchResults(this.query, this.entries);

  /// The query that matched.
  final String query;

  /// Matches, reviewed or not.
  final List<ProxyDelegateListing> entries;
}

/// PD-2 paste or scan state.
sealed class ProxyLookupState {
  const ProxyLookupState();
}

/// Nothing pasted or scanned.
final class ProxyLookupIdle extends ProxyLookupState {
  /// Creates the state.
  const ProxyLookupIdle();
}

/// Looking up [text].
final class ProxyLookupRunning extends ProxyLookupState {
  /// Creates the state.
  const ProxyLookupRunning(this.text);

  /// The pasted or scanned text.
  final String text;
}

/// The answer for [text].
final class ProxyLookupDone extends ProxyLookupState {
  /// Creates the state.
  const ProxyLookupDone(this.text, this.answer);

  /// The pasted or scanned text.
  final String text;

  /// What it names.
  final ApiDelegateLookup answer;
}

/// The lookup failed.
final class ProxyLookupFailed extends ProxyLookupState {
  /// Creates the state.
  const ProxyLookupFailed(this.text, this.error);

  /// The pasted or scanned text.
  final String text;

  /// Why, for [proxyErrorCopy].
  final Object error;
}

/// PD-2 directory: Vizor's browse list, handle search and paste or scan.
class ProxyDirectoryState {
  /// Creates the state.
  const ProxyDirectoryState({
    required this.browse,
    this.search = const ProxySearchIdle(),
    this.lookup = const ProxyLookupIdle(),
  });

  /// Vizor's list, in list order.
  final ProxyDelegateBrowse browse;

  /// Current handle search.
  final ProxySearchState search;

  /// Current paste or scan.
  final ProxyLookupState lookup;

  /// Returns a copy with a new [search].
  ProxyDirectoryState withSearch(ProxySearchState search) =>
      ProxyDirectoryState(browse: browse, search: search, lookup: lookup);

  /// Returns a copy with a new [lookup].
  ProxyDirectoryState withLookup(ProxyLookupState lookup) =>
      ProxyDirectoryState(browse: browse, search: search, lookup: lookup);

  /// Every delegate the screen shows, for a profile to find by index.
  List<ProxyDelegateListing> get shown {
    final search = this.search;
    final lookup = this.lookup;
    return [
      ...browse.listed,
      if (search is ProxySearchResults) ...search.entries,
      if (lookup case ProxyLookupDone(
        answer: ApiDelegateLookup(:final listing?),
      ))
        listing,
    ];
  }
}

/// Loads Vizor's browse list and runs handle searches and lookups.
class ProxyDirectoryNotifier extends AsyncNotifier<ProxyDirectoryState> {
  /// Creates the notifier for [key].
  ProxyDirectoryNotifier(this.key);

  /// Round and account whose delegates these are.
  final VotingSessionKey key;

  @override
  Future<ProxyDirectoryState> build() async => ProxyDirectoryState(
    browse: await ref
        .watch(proxyDelegationRepositoryProvider(key))
        .browse(key.roundId),
  );

  /// Matches [query] exactly against the registry's handles.
  Future<void> search(String query) async {
    final current = state.value;
    if (current == null) return;
    if (query.trim().isEmpty) {
      state = AsyncData(current.withSearch(const ProxySearchIdle()));
      return;
    }
    state = AsyncData(current.withSearch(ProxySearchRunning(query)));
    final entries = await ref
        .read(proxyDelegationRepositoryProvider(key))
        .search(key.roundId, query);
    if (!ref.mounted) return;
    final latest = state.value ?? current;
    state = AsyncData(latest.withSearch(ProxySearchResults(query, entries)));
  }

  /// Returns to the browse list.
  void clearSearch() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withSearch(const ProxySearchIdle()));
  }

  /// Looks up pasted or scanned [text].
  Future<void> lookup(String text) async {
    final current = state.value;
    if (current == null) return;
    if (text.trim().isEmpty) {
      state = AsyncData(current.withLookup(const ProxyLookupIdle()));
      return;
    }
    state = AsyncData(current.withLookup(ProxyLookupRunning(text)));
    ProxyLookupState result;
    try {
      result = ProxyLookupDone(
        text,
        await ref
            .read(proxyDelegationRepositoryProvider(key))
            .lookup(key.roundId, text),
      );
    } catch (error) {
      result = ProxyLookupFailed(text, error);
    }
    if (!ref.mounted) return;
    state = AsyncData((state.value ?? current).withLookup(result));
  }

  /// Clears the paste or scan answer.
  void clearLookup() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.withLookup(const ProxyLookupIdle()));
  }
}

/// PD-2 directory for a round and account.
final proxyDirectoryProvider = AsyncNotifierProvider.autoDispose
    .family<ProxyDirectoryNotifier, ProxyDirectoryState, VotingSessionKey>(
      ProxyDirectoryNotifier.new,
      retry: proxyNoRetry,
    );

/// Holds the round screen's delegation draft: the PD-2 to PD-5 selection
/// and split for one round.
class ProxyAllocationDraftNotifier extends Notifier<ProxyAllocationDraft> {
  /// Creates the notifier for [key].
  ProxyAllocationDraftNotifier(this.key);

  /// Round and account the draft belongs to.
  final VotingSessionKey key;

  @override
  ProxyAllocationDraft build() => const ProxyAllocationDraft();

  /// Adds or removes [entry]. Returns false when adding would pass
  /// [kProxyMaxDelegates] or [entry] is suspended or retired.
  bool toggle(ProxyDelegateListing entry) {
    final draft = state;
    if (draft.contains(entry.index)) {
      state = ProxyAllocationDraft(
        delegates: [
          for (final delegate in draft.delegates)
            if (delegate.entry.index != entry.index) delegate,
        ],
      );
      return true;
    }
    if (draft.isFull || entry.blocked) return false;
    state = ProxyAllocationDraft(
      delegates: [
        ...draft.delegates,
        ProxyDraftDelegate(entry: entry),
      ],
    );
    return true;
  }

  /// Sets the share of the delegate at [position].
  void setPercent(int position, int? bps) {
    final delegates = [...state.delegates];
    delegates[position] = delegates[position].withPercent(bps);
    state = ProxyAllocationDraft(delegates: delegates);
  }

  /// Splits 100% evenly across the chosen delegates.
  void splitEvenly() {
    final split = proxyEvenSplit(state.delegates.length);
    state = ProxyAllocationDraft(
      delegates: [
        for (final (i, delegate) in state.delegates.indexed)
          delegate.withPercent(split[i]),
      ],
    );
  }

  /// Drops the draft, after a commit or when the user removes it.
  void clear() => state = const ProxyAllocationDraft();
}

/// The round's allocation draft for one account. Kept alive across the
/// round, PD-2 to PD-5 and the vote review.
final proxyAllocationDraftProvider =
    NotifierProvider.family<
      ProxyAllocationDraftNotifier,
      ProxyAllocationDraft,
      VotingSessionKey
    >(ProxyAllocationDraftNotifier.new);

/// The planner's preview of the round's draft, or null while the draft has
/// an issue.
final proxyAllocationPreviewProvider = FutureProvider.autoDispose
    .family<ProxyAllocationPreview?, VotingSessionKey>((ref, key) async {
      final draft = ref.watch(proxyAllocationDraftProvider(key));
      if (draft.issue != null) return null;
      return ref
          .watch(proxyDelegationRepositoryProvider(key))
          .preview(draft.toRequest(key.roundId));
    }, retry: proxyNoRetry);

/// The delegation part of the round's ballot, from the committed allocation
/// or the round screen's draft (see [proxyBallotDelegationFor]). Null with
/// the dormant flag off, without touching the repository.
final proxyBallotDelegationProvider = Provider.autoDispose
    .family<ProxyBallotDelegation?, VotingSessionKey>((ref, key) {
      if (!ref.watch(proxyDelegationFeatureEnabledProvider)) return null;
      return proxyBallotDelegationFor(
        status: ref.watch(proxyAllocationStatusProvider(key)).value,
        draft: ref.watch(proxyAllocationDraftProvider(key)),
        preview: ref.watch(proxyAllocationPreviewProvider(key)).value,
      );
    });

/// The pre-proving registry check of the draft's delegates, one result per
/// delegate in draft order.
final proxyDelegateChecksProvider = FutureProvider.autoDispose
    .family<List<ApiConfirmedDelegate>, VotingSessionKey>((ref, key) {
      final draft = ref.watch(proxyAllocationDraftProvider(key));
      return ref
          .watch(proxyDelegationRepositoryProvider(key))
          .checkDelegates(key.roundId, draft.toRequest(key.roundId).choices);
    }, retry: proxyNoRetry);
