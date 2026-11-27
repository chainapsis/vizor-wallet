import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../voting_flow_models.dart';
import 'proxy_delegation_models.dart';

export 'proxy_delegation_models.dart';

/// The delegator screens' only data source.
///
/// Every call is scoped to the active account, as `votingSessionProvider` is.
/// `CompositeProxyDelegationRepository` backs it with zcash_voting's registry
/// client, its delegator calls and the delegation job. Screens never call
/// anything else.
abstract interface class ProxyDelegationRepository {
  /// Round facts the delegator screens show.
  Future<ProxyRoundContext> roundContext(String roundId);

  /// First applicable availability result (contracts section 11.4).
  ///
  /// Throws [ProxyDelegationError] with
  /// [ProxyDelegationErrorKind.cannotVerify] when the participation reader
  /// cannot verify the chain against its bundled anchor.
  Future<ApiProxyAvailability> availability(String roundId);

  /// Browse: Vizor's signed list of delegates, in list order (contracts-v1
  /// section 11.10). Refreshes the registry cache and the list when they
  /// are stale; a list that cannot be fetched or verified leaves the stored
  /// one, or an empty browse.
  Future<ProxyDelegateBrowse> browse(String roundId);

  /// Exact handle search over the registry cache's live entries.
  Future<List<ProxyDelegateListing>> search(String roundId, String query);

  /// Paste or scan: the registry cache's entry [text] names, as a marker
  /// post, a `zvdk1…` key, an index or a fingerprint.
  Future<ApiDelegateLookup> lookup(String roundId, String text);

  /// The planner's exact split of [request]; nothing is recorded.
  Future<ProxyAllocationPreview> preview(ProxyAllocationRequest request);

  /// The pre-proving check at confirm (contracts-v1 section 11.11): each
  /// chosen entry proven in one evidence answer, one result per choice in
  /// order, with the delegate as the chain proves it.
  ///
  /// Throws [ProxyDelegationError] with
  /// [ProxyDelegationErrorKind.cannotVerify] when no proof host serves
  /// evidence the participation reader verifies.
  Future<List<ApiConfirmedDelegate>> checkDelegates(
    String roundId,
    List<ProxyDelegateChoice> choices,
  );

  /// Records [request] as the round's only allocation, after proving its
  /// delegates again. [confirmed] is the preview the delegator confirmed.
  /// The caller starts the job that carries it (see `submitProxyBallot`).
  ///
  /// Throws [ProxyReviewChangedException], having committed nothing, unless
  /// every delegate's verdict is [DelegateCheck.ok], and
  /// [ProxyDelegationError] with [ProxyDelegationErrorKind.planChanged] when
  /// the plan no longer splits as [confirmed] does.
  Future<void> commit(
    ProxyAllocationRequest request, {
    required ProxyAllocationPreview confirmed,
  });

  /// The committed allocation, or null before the wallet delegates.
  Future<ApiProxyAllocationStatus?> allocationStatus(String roundId);
}

/// The proof right before the commit gave a delegate another verdict than
/// ok, so nothing was committed and the review shows the new check.
class ProxyReviewChangedException implements Exception {
  /// Creates the exception.
  const ProxyReviewChangedException();

  @override
  String toString() => 'ProxyReviewChangedException';
}

/// Round facts the delegator screens need.
@immutable
class ProxyRoundContext {
  /// Creates the context.
  const ProxyRoundContext({
    required this.roundId,
    required this.title,
    required this.proposals,
    required this.voteEndTime,
    required this.eligibleBallots,
  });

  /// Round id.
  final String roundId;

  /// Round title.
  final String title;

  /// Proposals in id order; a delegation covers all of them.
  final List<VotingProposalView> proposals;

  /// The round's `vote_end_time` as the vote server reports it.
  final DateTime voteEndTime;

  /// Voting power the wallet can still allocate, in ballots.
  final BigInt eligibleBallots;
}

/// A wallet list row's picture: WebP bytes from Vizor's signed list
/// (contracts-v1 section 12.3), decoded in Rust.
@immutable
class ProxyDelegatePicture {
  /// Creates the picture; [key] identifies the bytes in the picture cache.
  const ProxyDelegatePicture({required this.webp, required this.key});

  /// The picture for [webp], keyed by its SHA-256.
  factory ProxyDelegatePicture.of(Uint8List webp) =>
      ProxyDelegatePicture(webp: webp, key: sha256.convert(webp).toString());

  /// WebP bytes, at most 12,288 of them.
  final Uint8List webp;

  /// Lowercase hex SHA-256 of [webp].
  final String key;
}

/// A listing's picture from Vizor's list, keyed for the picture cache.
extension ProxyDelegateListingPicture on ProxyDelegateListing {
  /// The row's picture, or null without one. The key is computed once per
  /// picture.
  ProxyDelegatePicture? get listPicture {
    final webp = picture;
    if (webp == null) return null;
    return _pictures[webp] ??= ProxyDelegatePicture.of(webp);
  }

  static final _pictures = Expando<ProxyDelegatePicture>();
}
