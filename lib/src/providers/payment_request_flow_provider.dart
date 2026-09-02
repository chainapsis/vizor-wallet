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
    // The watch is bound to the one status it exists for, and this is the
    // single choke point every card change goes through: presenting a newer
    // link, every verdict the pre-check publishes, and every teardown
    // (dismiss, edit, review, lock, sign-out, account switch) land here.
    if (next?.view.status == PaymentRequestStatus.syncing) {
      _watchSyncForRecheck();
    } else {
      _stopWatchingSync();
    }
    _liveProposal = next?.proposal;
    state = next;
  }

  void _watchSyncForRecheck() {
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
    // Already settled: no crossing is coming, so the wait the copy promises
    // has to be answered now instead of never.
    if (!settled || _immediateRecheckBudget <= 0) return;
    _immediateRecheckBudget--;
    final generation = _generation;
    scheduleMicrotask(() {
      if (generation != _generation) return;
      _recheckAfterSync();
    });
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
    // Only the status this watch was installed for. A card that has since
    // moved on — to a verdict, or to a re-check already in flight, which
    // renders as `checking` — is not waiting on the sync any more.
    if (current == null ||
        current.view.status != PaymentRequestStatus.syncing) {
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
      unawaited(
        replaced!.proposal!.discard(logContext: 'PaymentRequest(replaced)'),
      );
    }

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
    unawaited(_runPrecheck(generation));
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

  /// Clears the card, releases any proposal, and returns the request for the
  /// composer.
  SendPrefillArgs? edit() {
    final current = state;
    if (current == null) return null;
    _clear(logContext: 'PaymentRequest(edit)');
    return current.prefill;
  }

  /// Cancel, the ⨯, the scrim, and the Android back gesture.
  void dismiss() => _clear(logContext: 'PaymentRequest(dismissed)');

  /// Drops the card without a user answer — wallet lock, account switch,
  /// wallet reset.
  void clear({String logContext = 'PaymentRequest(cleared)'}) =>
      _clear(logContext: logContext);

  void _clear({required String logContext}) {
    final current = state;
    if (current == null) return;
    final proposal = current.proposal;
    if (proposal != null) {
      unawaited(proposal.discard(logContext: logContext));
    }
    _generation++;
    _publish(null);
  }

  Future<void> _runPrecheck(int generation) async {
    final current = state;
    if (current == null || generation != _generation) return;

    final accountState = ref.read(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    // A link can arrive before the first sync state has resolved. Waiting for
    // it is what stops a startup request from reading a zero balance and
    // telling the user they cannot afford a payment they can.
    final sync = (await _readSyncState()).scopedToAccount(accountUuid);
    // Mirrors the compose form: while a Private migration holds the balance,
    // the Ironwood note is what can actually be spent.
    final spendable = ref.read(migrationSendGateProvider)
        ? sync.displayIronwoodBalance
        : sync.displaySpendableBalance;
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
      // no owner, so hand it straight back.
      if (result is PaymentRequestPrecheckReady && result.proposal != null) {
        unawaited(
          result.proposal!.discard(logContext: 'PaymentRequest(stale check)'),
        );
      }
      return;
    }

    final live = state;
    if (live == null) return;

    // A memo the recipient's address type cannot carry is not part of the
    // payment, so the card stops showing one the moment the pre-check knows.
    final clearMemo = result.memoDropped;

    switch (result) {
      case PaymentRequestPrecheckReady(:final proposal):
        _publish(
          PaymentRequestFlowState(
            prefill: live.prefill,
            view: live.view.copyWithStatus(
              PaymentRequestStatus.ready,
              clearMemo: clearMemo,
            ),
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
              clearMemo: clearMemo,
            ),
          ),
        );
      case PaymentRequestPrecheckSyncing():
        _publish(
          live.copyWith(
            view: live.view.copyWithStatus(
              PaymentRequestStatus.syncing,
              clearMemo: clearMemo,
            ),
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
              clearMemo: clearMemo,
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
      fiatText: hasAmount
          ? fiatTextForZatoshi(
              amountZatoshi,
              zecUsdUnitPrice: ref.read(zecHomeUsdUnitPriceProvider),
            )
          : null,
      requesterLabel: sanitisePaymentRequestLabel(prefill.label),
      memo: prefill.memoText,
      note: prefill.message,
      status: status,
      replacedNotice: replacedNotice,
    );
  }
}

final paymentRequestFlowProvider =
    NotifierProvider<PaymentRequestFlowNotifier, PaymentRequestFlowState?>(
      PaymentRequestFlowNotifier.new,
    );
