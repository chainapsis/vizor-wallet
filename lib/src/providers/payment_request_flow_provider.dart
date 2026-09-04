/// The live state of the payment-request card.
///
/// A `zcash:` link (and, later, an in-app QR scan) arrives here after the drain
/// policy has cleared it. The card then owns the request until the user answers
/// it: Review hands the proposal to the review screen, Edit hands the request
/// to the composer, Cancel throws it away. The notifier is the only place that
/// knows a proposal may be alive behind the card, so it is also the only place
/// that has to release one.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatting/zec_amount.dart';
import '../features/send/models/send_prefill_args.dart';
import '../features/send/services/payment_request_precheck.dart';
import '../features/send/services/send_flow.dart';
import '../features/send/widgets/payment_request_card.dart';
import 'account_provider.dart';
import 'app_security_provider.dart';
import 'migration_send_gate_provider.dart' show migrationSendGateProvider;
import 'payment_uri_prefill_provider.dart';
import 'sync_provider.dart';
import 'zec_price_change_provider.dart';

export '../features/send/widgets/payment_request_card.dart'
    show PaymentRequestSource, PaymentRequestStatus, PaymentRequestView;

/// Everything the host needs to render and act on the current card.
class PaymentRequestFlowState {
  const PaymentRequestFlowState({
    required this.prefill,
    required this.view,
    this.proposal,
  });

  /// The request as parsed, unchanged. This is what Edit hands to the
  /// composer, so it must keep the untouched link values.
  final SendPrefillArgs prefill;

  /// What the card renders, including its status.
  final PaymentRequestView view;

  /// The live proposal, once the pre-check has made one. Null while checking,
  /// on every failure, and for an amount-less request.
  final PaymentRequestProposalHandle? proposal;

  SendReviewArgs? get reviewArgs => proposal?.reviewArgs;

  /// Whether the primary action can go straight to the review screen. False
  /// for an amount-less request, whose primary action is "Enter amount".
  bool get canReview =>
      view.status == PaymentRequestStatus.ready && proposal != null;

  PaymentRequestFlowState copyWith({
    PaymentRequestView? view,
    PaymentRequestProposalHandle? proposal,
  }) => PaymentRequestFlowState(
    prefill: prefill,
    view: view ?? this.view,
    proposal: proposal ?? this.proposal,
  );
}

/// What a mobile Review tap resolved to.
///
/// Three answers, not two: "nothing to review" and "a newer link took over
/// while the proposal was being handed back" both leave the wizard closed,
/// but only the second one dropped something the user asked for, and only
/// the second one has a card left on screen to say so.
sealed class PaymentRequestReviewHandoff {
  const PaymentRequestReviewHandoff();
}

/// The proposal is back with Rust; the wizard can open on [args].
final class PaymentRequestReviewReady extends PaymentRequestReviewHandoff {
  const PaymentRequestReviewReady(this.args);

  final SendReviewArgs args;
}

/// Nothing to review — no card, an amount-less request, or a status that
/// still blocks. The caller falls back to Edit.
final class PaymentRequestReviewUnavailable
    extends PaymentRequestReviewHandoff {
  const PaymentRequestReviewUnavailable();
}

/// A newer link replaced the card during the hand-back.
///
/// The user is looking at that request now, and opening the first one's
/// review underneath it would leave a send they did not choose behind the
/// card they dismiss. The newer card carries the standard replaced notice so
/// the dropped tap is accounted for.
final class PaymentRequestReviewOvertaken extends PaymentRequestReviewHandoff {
  const PaymentRequestReviewOvertaken();
}

/// What an Edit tap resolved to — the same three answers as
/// [PaymentRequestReviewHandoff], for the same reason: the composer that Edit
/// opens re-quotes the fee as it mounts, and a quote asked while the card's
/// proposal still holds its inputs can come back "not enough ZEC" for the very
/// payment the card just found affordable.
sealed class PaymentRequestEditHandoff {
  const PaymentRequestEditHandoff();
}

/// The proposal is back with Rust (or there was none); the composer can open
/// on [prefill].
final class PaymentRequestEditReady extends PaymentRequestEditHandoff {
  const PaymentRequestEditReady(this.prefill);

  final SendPrefillArgs prefill;
}

/// No card to edit.
final class PaymentRequestEditUnavailable extends PaymentRequestEditHandoff {
  const PaymentRequestEditUnavailable();
}

/// A newer link replaced the card during the hand-back; the composer must not
/// open on the request the user is no longer looking at.
final class PaymentRequestEditOvertaken extends PaymentRequestEditHandoff {
  const PaymentRequestEditOvertaken();
}

class PaymentRequestFlowNotifier extends Notifier<PaymentRequestFlowState?> {
  /// Bumped by every state change. A pre-check that finishes after its card is
  /// gone (replaced, cancelled, reviewed) must not write into the newer card,
  /// and must release the proposal it just created.
  var _generation = 0;

  /// Mirrors `state?.proposal`. `onDispose` may not read `state`, and a
  /// proposal that outlives its scope is exactly the leak this class exists to
  /// prevent, so the handle is tracked here as well.
  PaymentRequestProposalHandle? _liveProposal;

  /// Open only while the card is sitting on [PaymentRequestStatus.syncing].
  ///
  /// That status is the one verdict that is not about the request at all: it
  /// says the wallet could not answer yet. Leaving the user to re-open the
  /// link is asking them to retry a condition the wallet already knows how to
  /// notice, so the card watches for it instead.
  ProviderSubscription<AsyncValue<SyncState>>? _syncWatch;

  /// Edge state for [_syncWatch]: the re-check fires on the false→true
  /// crossing only. Firing on the level would spin the card — a re-check whose
  /// answer is `syncing` again republishes `syncing` while the sync state is
  /// still settled, and would immediately ask for another one.
  var _syncWasSettled = false;

  /// How many times this card may re-check itself against a wallet that is
  /// *already* settled, before it goes back to waiting for a crossing.
  ///
  /// The edge trigger alone cannot answer a `syncing` verdict published while
  /// the sync state is settled: there is no crossing left to wait for, so the
  /// card would sit on "this will update when it finishes" forever. That is
  /// not a corner case — it is what this feature's own re-check loop produces
  /// whenever Rust's view lags the sync state's. The budget is what keeps the
  /// answer bounded: a re-check that lands on `syncing` again may ask once
  /// more, and then the card waits for a real sync cycle rather than spinning.
  var _immediateRecheckBudget = 0;

  /// How many immediate re-checks one card gets.
  static const _kImmediateRecheckBudget = 2;

  /// The pre-check currently asking Rust, if any.
  ///
  /// A check displaced mid-flight still gets its proposal — Rust does not
  /// know the card is gone — and hands it back only once its result arrives.
  /// Until then the inputs that proposal selected are locked, so the
  /// replacement's check has to wait for this future before it asks.
  Future<void>? _inFlightPrecheck;

  /// The most recent hand-back of a proposal (dismiss, edit, lock, a
  /// replacement's displaced card), for the same reason as
  /// [_inFlightPrecheck]: a check started before the locked inputs are
  /// released can read a wallet whose funds are all "in use" and answer "not
  /// enough" for a payment the wallet can afford.
  Future<void>? _lastRelease;

  /// The request a Review or Edit hand-back is carrying while it waits for
  /// Rust to release the card's proposal. The card is already down, so a lock
  /// landing in that window finds no `state` to re-park — this is what it
  /// re-parks instead, so the request survives the unlock rather than being
  /// dropped with the cancelled navigation.
  SendPrefillArgs? _handoffPrefill;

  @override
  PaymentRequestFlowState? build() {
    // The card is consent given by one unlocked account, and it holds that
    // account's live proposal. Locking, signing out, and switching accounts
    // all take that consent away without going through any of the card's own
    // exits, so the flow has to notice them itself: the host renders above the
    // router, which means a card left standing would sit on top of the unlock
    // screen with the request's address, amount and memo still on it.
    ref.listen(appSecurityProvider, (previous, next) {
      final wasUnlocked = previous?.isUnlocked ?? true;
      if (wasUnlocked && !next.isUnlocked) {
        _reparkForUnlock();
        clear(logContext: 'PaymentRequest(locked)');
      }
    });
    ref.listen(accountProvider, (previous, next) {
      final previousUuid = previous?.value?.activeAccountUuid;
      final nextUuid = next.value?.activeAccountUuid;
      // Only a switch between two real accounts. A wallet reset drops the
      // active account to null and is already handled by the link listener in
      // `app.dart`, which also clears the parked prefill.
      if (previousUuid != null &&
          nextUuid != null &&
          previousUuid != nextUuid) {
        clear(logContext: 'PaymentRequest(account switched)');
      }
    });
    ref.onDispose(() {
      _stopWatchingSync();
      final proposal = _liveProposal;
      _liveProposal = null;
      if (proposal != null) {
        unawaited(proposal.discard(logContext: 'PaymentRequest(disposed)'));
      }
    });
    return null;
  }

  void _publish(PaymentRequestFlowState? next) {
    // The watch is bound to the two statuses it exists for, and this is the
    // single choke point every card change goes through: presenting a newer
    // link, every verdict the pre-check publishes, and every teardown
    // (dismiss, edit, review, lock, sign-out, account switch) land here.
    var published = next;
    final status = published?.view.status;
    if (_isWaitingOnSync(status)) {
      // `syncing` copy promises the card will update itself. When the watch
      // reports that nothing is coming — the sync state is already settled
      // and the immediate budget is spent — that promise cannot be kept, so
      // the card publishes the stalled status instead and hands the next
      // move to the user through "Check again".
      final answerIsComing = _watchSyncForRecheck();
      if (!answerIsComing && status == PaymentRequestStatus.syncing) {
        published = published!.copyWith(
          view: published.view.copyWithStatus(PaymentRequestStatus.syncStalled),
        );
      }
    } else {
      _stopWatchingSync();
    }
    _liveProposal = published?.proposal;
    state = published;
  }

  /// The two statuses that are blocked on the wallet rather than on the
  /// request, and are therefore the ones a finished sync can answer.
  static bool _isWaitingOnSync(PaymentRequestStatus? status) =>
      status == PaymentRequestStatus.syncing ||
      status == PaymentRequestStatus.syncStalled;

  /// Installs (or keeps) the sync watch, and spends an immediate re-check
  /// when one is both possible and the only way the card can be answered.
  ///
  /// Returns whether an answer is still coming on its own: a sync that has
  /// not settled yet will cross, and a spent budget means neither will
  /// happen — which is what turns the card's status from `syncing` into
  /// `syncStalled`.
  bool _watchSyncForRecheck() {
    final settled = _spendableIsSettled(ref.read(syncProvider).value);
    if (_syncWatch == null) {
      _syncWasSettled = settled;
      _syncWatch = ref.listen<AsyncValue<SyncState>>(syncProvider, (_, next) {
        final wasSettled = _syncWasSettled;
        final isSettled = _spendableIsSettled(next.value);
        _syncWasSettled = isSettled;
        if (wasSettled || !isSettled) return;
        _recheckAfterSync();
      });
    }
    // Not settled yet: the crossing this watch exists for is still ahead.
    if (!settled) return true;
    // Already settled: no crossing is coming, so the wait the copy promises
    // has to be answered now instead of never.
    if (_immediateRecheckBudget <= 0) return false;
    _immediateRecheckBudget--;
    final generation = _generation;
    scheduleMicrotask(() {
      if (generation != _generation) return;
      _recheckAfterSync();
    });
    return true;
  }

  void _stopWatchingSync() {
    _syncWatch?.close();
    _syncWatch = null;
    _syncWasSettled = false;
  }

  /// Re-runs the same pre-check on the same request now that the wallet can
  /// answer it.
  void _recheckAfterSync() {
    final current = state;
    // Only the statuses this watch was installed for. A card that has since
    // moved on — to a verdict, or to a re-check already in flight, which
    // renders as `checking` — is not waiting on the sync any more.
    if (current == null || !_isWaitingOnSync(current.view.status)) {
      _stopWatchingSync();
      return;
    }
    // Back to the same first-look state `present` publishes: the primary
    // shows its spinner and the status line clears, so the card says it is
    // working rather than leaving the old blocked message under a new answer.
    _publish(
      current.copyWith(
        view: current.view.copyWithStatus(PaymentRequestStatus.checking),
      ),
    );
    // No proposal to release first: a `syncing` verdict never holds one.
    unawaited(_runPrecheck(_generation));
  }

  /// The card's "Check again", for [PaymentRequestStatus.syncStalled].
  ///
  /// The same re-check the sync watch runs, asked for by hand. It does not
  /// touch the immediate budget: that budget bounds what the card does on its
  /// own, and a tap is not the card acting on its own.
  void recheck() {
    final current = state;
    if (current == null ||
        current.view.status != PaymentRequestStatus.syncStalled) {
      return;
    }
    _recheckAfterSync();
  }

  /// Shows [prefill] as a payment request and starts the pre-check.
  ///
  /// A card already on screen is replaced — latest link wins, matching the
  /// single-slot park in `paymentUriPrefillProvider` — and the replacement says
  /// so rather than silently swapping under the user.
  void present(
    SendPrefillArgs prefill, {
    required PaymentRequestSource source,
  }) {
    final replaced = state;
    if (replaced?.proposal != null) {
      _track(
        replaced!.proposal!.discard(logContext: 'PaymentRequest(replaced)'),
      );
    }
    // The replacement's check is serialized behind whatever is still
    // releasing inputs: the displaced proposal's discard just started above,
    // an earlier hand-back that has not finished, and a displaced check that
    // is still running and will hand its own proposal back when it lands.
    final after = <Future<void>>[?_lastRelease, ?_inFlightPrecheck];

    final generation = ++_generation;
    _immediateRecheckBudget = _kImmediateRecheckBudget;
    _publish(
      PaymentRequestFlowState(
        prefill: prefill,
        view: _buildView(
          prefill: prefill,
          source: source,
          status: PaymentRequestStatus.checking,
          replacedNotice: replaced != null,
        ),
      ),
    );
    unawaited(_runPrecheck(generation, after: after));
  }

  /// Hands the proposal *back* rather than on, for the mobile review step,
  /// which creates its own proposal on "Confirm & send".
  ///
  /// Clears the card at once but completes only when Rust has released the
  /// proposal: the review step re-quotes the fee as it mounts, and a quote
  /// asked while the card's proposal still holds its inputs can come back
  /// short for the very payment the card just found affordable.
  ///
  /// The three outcomes are distinct on purpose — see
  /// [PaymentRequestReviewHandoff].
  Future<PaymentRequestReviewHandoff> reviewHandingBack() async {
    final current = state;
    if (current == null || !current.canReview) {
      return const PaymentRequestReviewUnavailable();
    }
    final proposal = current.proposal!;
    final generation = ++_generation;
    _publish(null);
    _handoffPrefill = current.prefill;
    final release = proposal.discard(
      logContext: 'PaymentRequest(mobile review handoff)',
    );
    _track(release);
    await _awaitRelease(release, proposal, generation);
    if (identical(_handoffPrefill, current.prefill)) _handoffPrefill = null;
    if (generation != _generation) {
      // The tap is being dropped, so it is accounted for on the card that
      // took its place rather than vanishing with the request it belonged to.
      _noteReplacedRequest();
      return const PaymentRequestReviewOvertaken();
    }
    return PaymentRequestReviewReady(proposal.reviewArgs);
  }

  /// Puts the standard "replaced an earlier link" notice on the card that is
  /// up now.
  ///
  /// `present` raises the notice itself when it displaces a visible card. It
  /// cannot see this case: the displaced card was already cleared by the
  /// hand-back, so the replacement had nothing to replace.
  void _noteReplacedRequest() {
    final current = state;
    if (current == null || current.view.replacedNotice) return;
    // Written straight to `state`: the status is unchanged, so the sync watch
    // that `_publish` owns must not be re-evaluated — re-entering it would
    // spend an immediate re-check the card never asked for.
    state = current.copyWith(view: current.view.withReplacedNotice());
  }

  /// Hands the proposal to the review screen and clears the card.
  ///
  /// Returns null when there is nothing to review — an amount-less request, or
  /// a status that still blocks — so the caller can fall back to Edit.
  SendReviewArgs? review() {
    final current = state;
    if (current == null || !current.canReview) return null;
    final args = current.proposal!.release();
    _generation++;
    _publish(null);
    return args;
  }

  /// Hands the request to the composer, completing only once Rust has
  /// released the card's proposal.
  ///
  /// Clears the card at once, like [dismiss]; the caller navigates only when
  /// the returned future says the composer is safe to open — see
  /// [PaymentRequestEditHandoff] for why waiting matters and why the three
  /// outcomes are distinct.
  Future<PaymentRequestEditHandoff> editHandingBack() async {
    final current = state;
    if (current == null) return const PaymentRequestEditUnavailable();
    final proposal = current.proposal;
    final generation = ++_generation;
    _publish(null);
    if (proposal != null) {
      _handoffPrefill = current.prefill;
      final release = proposal.discard(logContext: 'PaymentRequest(edit)');
      _track(release);
      await _awaitRelease(release, proposal, generation);
      if (identical(_handoffPrefill, current.prefill)) _handoffPrefill = null;
      if (generation != _generation) {
        _noteReplacedRequest();
        return const PaymentRequestEditOvertaken();
      }
    }
    return PaymentRequestEditReady(current.prefill);
  }

  /// Waits for a hand-back's release; one Rust did not confirm gets a single
  /// retry after a short grace, then the hand-off proceeds regardless — the
  /// review's fee quote can be retried, a request dropped here cannot.
  Future<void> _awaitRelease(
    Future<bool> release,
    PaymentRequestProposalHandle proposal,
    int generation,
  ) async {
    if (await release) return;
    await Future<void>.delayed(debugUnconfirmedReleaseGrace);
    if (generation != _generation) return;
    _track(proposal.discard(logContext: 'PaymentRequest(release retry)'));
    await _lastRelease;
  }

  /// Cancel, the ⨯, the scrim, and the Android back gesture.
  void dismiss() => _clear(logContext: 'PaymentRequest(dismissed)');

  /// Drops the card without a user answer — wallet lock, account switch,
  /// wallet reset.
  void clear({String logContext = 'PaymentRequest(cleared)'}) =>
      _clear(logContext: logContext);

  /// Puts a locked-away card's request back in the park.
  ///
  /// Taking the card down on lock is not negotiable — the host renders above
  /// the router, so it would otherwise sit on the unlock screen with the
  /// address, amount and memo on it. But the prefill was consumed when the
  /// drain delivered it, so without this the request is gone with nothing to
  /// say and nothing to claim: the one silent drop left in a pipeline whose
  /// rule is that no drop is silent. Re-parking hands it back to the path
  /// that already exists — `claimParkedPaymentUriAfterUnlock` re-presents it
  /// after a successful unlock, under the same park TTL as a link tapped
  /// while locked. The proposal is still discarded; only the request survives.
  void _reparkForUnlock() {
    // A card on screen, or the request a hand-back is still carrying while
    // Rust releases the proposal: either way the user answered this request
    // and has not yet reached where the answer leads.
    final prefill = state?.prefill ?? _handoffPrefill;
    if (prefill == null) return;
    // Latest link wins, the same answer the park itself gives: a link that
    // arrived while the card was up and is still parked (held behind a busy
    // surface, say) is the newer request, so it keeps the single slot.
    if (ref.read(paymentUriPrefillProvider) != null) return;
    ref.read(paymentUriPrefillProvider.notifier).set(prefill);
  }

  void _clear({required String logContext}) {
    // Bumped even with no card on screen: a Review or Edit hand-back takes
    // the card down first and navigates only once Rust has released the
    // proposal, and a lock or an account switch landing in that window must
    // stop it — otherwise the review of a request pre-checked for one account
    // opens on, and proposes from, whichever account is active by then.
    _generation++;
    final current = state;
    if (current == null) return;
    final proposal = current.proposal;
    if (proposal != null) {
      _track(proposal.discard(logContext: logContext));
    }
    _publish(null);
  }

  /// Remembers [release] as the hand-back a later check must wait for.
  ///
  /// A discard never throws — `discardSendProposal` swallows its own
  /// failures — but the future is shielded anyway so a replacement can never
  /// be wedged in `checking` by its predecessor.
  void _track(Future<void> release) {
    final shielded = release.then<void>((_) {}, onError: (Object _) {});
    _lastRelease = shielded;
    unawaited(
      shielded.whenComplete(() {
        if (identical(_lastRelease, shielded)) _lastRelease = null;
      }),
    );
  }

  /// Runs one pre-check and keeps it in [_inFlightPrecheck] while it runs, so
  /// a replacement presented mid-check can wait for it.
  Future<void> _runPrecheck(
    int generation, {
    List<Future<void>> after = const [],
  }) async {
    final run = _precheck(generation, after: after);
    _inFlightPrecheck = run;
    try {
      await run;
    } finally {
      if (identical(_inFlightPrecheck, run)) _inFlightPrecheck = null;
    }
  }

  Future<void> _precheck(
    int generation, {
    required List<Future<void>> after,
  }) async {
    if (after.isNotEmpty) {
      // Every future here is shielded (`_track`) or is a `_precheck` of our
      // own, which completes normally on every path.
      await Future.wait<void>(after);
    }
    final current = state;
    if (current == null || generation != _generation) return;

    final accountState = ref.read(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    // A link can arrive before the first sync state has resolved. Waiting for
    // it is what stops a startup request from reading a zero balance and
    // telling the user they cannot afford a payment they can.
    final sync = (await _readSyncState()).scopedToAccount(accountUuid);
    final spendable = paymentRequestSpendableOf(
      sync,
      gatedByMigration: ref.read(migrationSendGateProvider),
    );
    // Only a balance from a finished scan may end the check as "not enough".
    // A restored last-completed snapshot is stale by construction, and a sync
    // still short of the tip has not seen every note yet, so both hand the
    // verdict to the proposal instead.
    final spendableIsAuthoritative = sync.hasSettledSpendableBalance;

    final result = await ref
        .read(paymentRequestPrecheckProvider)
        .run(
          prefill: current.prefill,
          sendFlowId: newSendFlowId(),
          accountUuid: accountUuid,
          spendableBalance: spendable,
          spendableIsAuthoritative: spendableIsAuthoritative,
        );

    if (generation != _generation) {
      // The card this pre-check belonged to is gone. Anything it created has
      // no owner, so hand it straight back — and only return once it is
      // back, because a replacement's check is waiting on this future for
      // exactly that release.
      if (result is PaymentRequestPrecheckReady && result.proposal != null) {
        final release = result.proposal!.discard(
          logContext: 'PaymentRequest(stale check)',
        );
        _track(release);
        await release;
      }
      return;
    }

    final live = state;
    if (live == null) return;

    switch (result) {
      case PaymentRequestPrecheckReady(:final proposal):
        _publish(
          PaymentRequestFlowState(
            prefill: live.prefill,
            view: live.view.copyWithStatus(PaymentRequestStatus.ready),
            proposal: proposal,
          ),
        );
      case PaymentRequestPrecheckInvalidAddress(:final message):
        _publish(
          live.copyWith(
            view: live.view.copyWithStatus(
              PaymentRequestStatus.invalidAddress,
              // Null keeps the status's own default copy; the pre-check only
              // supplies one when it can say more than "bad address".
              statusMessage: message,
            ),
          ),
        );
      case PaymentRequestPrecheckInsufficientFunds(:final spendableText):
        _publish(
          live.copyWith(
            view: live.view.copyWithStatus(
              PaymentRequestStatus.insufficientFunds,
              spendableText: spendableText,
            ),
          ),
        );
      case PaymentRequestPrecheckSyncing():
        _publish(
          live.copyWith(
            view: live.view.copyWithStatus(PaymentRequestStatus.syncing),
          ),
        );
      case PaymentRequestPrecheckFailed(:final message):
        _publish(
          live.copyWith(
            view: live.view.copyWithStatus(
              // Not `invalidAddress`: the check could not complete, which is
              // a different condition from a bad recipient. The reason is
              // always stated in its own words through `statusMessage`.
              PaymentRequestStatus.failed,
              statusMessage: message,
            ),
          ),
        );
    }
  }

  /// [SyncState.hasSettledSpendableBalance] for the active account, from an
  /// unscoped state.
  ///
  /// The one condition the whole `syncing` status hangs off. The pre-check's
  /// own read, this watch, and the precheck provider's live re-read all go
  /// through the same predicate rather than drifting into three nearly
  /// identical ones.
  bool _spendableIsSettled(SyncState? sync) => spendableIsSettledForAccount(
    sync,
    ref.read(accountProvider).value?.activeAccountUuid,
  );

  Future<SyncState> _readSyncState() async {
    final current = ref.read(syncProvider);
    if (current.hasValue) return current.value!;
    try {
      return await ref.read(syncProvider.future);
    } catch (_) {
      // A sync that failed to load is not a reason to refuse the request; the
      // proposal itself is the authoritative balance check.
      return SyncState();
    }
  }

  PaymentRequestView _buildView({
    required SendPrefillArgs prefill,
    required PaymentRequestSource source,
    required PaymentRequestStatus status,
    required bool replacedNotice,
  }) {
    final amountZatoshi = parseZecAmount(prefill.amountText?.trim() ?? '');
    final hasAmount = amountZatoshi != null && amountZatoshi > BigInt.zero;
    return PaymentRequestView(
      source: source,
      address: prefill.address,
      amountZecText: hasAmount
          ? ZecAmount.fromZatoshi(amountZatoshi).activityDetail.toString()
          : null,
      // No fiat here: the ZEC price providers are autoDispose and fill
      // asynchronously, so a one-shot read from a card presented over a screen
      // that does not subscribe to them returns null and stays null. The host
      // watches the price and applies `withFiatText` on every build instead.
      requesterLabel: sanitisePaymentRequestLabel(prefill.label),
      // The bytes the pre-check will propose, not the raw field: the card is
      // a preview of the payment, so a memo it shows and a memo it pays have
      // to be the same string.
      memo: prefill.outgoingMemoText,
      note: prefill.message,
      status: status,
      replacedNotice: replacedNotice,
    );
  }
}

/// The fiat sub-line for a request's amount, or null when the request carried
/// no amount or the price is not known.
///
/// Lives here rather than in the host so the parse of the request's amount
/// text is the same one [PaymentRequestFlowNotifier] uses for the hero.
String? paymentRequestFiatText({
  required SendPrefillArgs prefill,
  required double? zecUsdUnitPrice,
}) {
  final amountZatoshi = parseZecAmount(prefill.amountText?.trim() ?? '');
  if (amountZatoshi == null) return null;
  return fiatTextForZatoshi(amountZatoshi, zecUsdUnitPrice: zecUsdUnitPrice);
}

final paymentRequestFlowProvider =
    NotifierProvider<PaymentRequestFlowNotifier, PaymentRequestFlowState?>(
      PaymentRequestFlowNotifier.new,
    );
