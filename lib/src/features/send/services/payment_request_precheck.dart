/// Pre-check behind the payment-request card.
///
/// The card appears the moment a `zcash:` link arrives, over whatever the user
/// was doing, and immediately says whether the request can be paid. That answer
/// is exactly what this service produces: validate the recipient, and — when
/// the link named an amount — go all the way to a real proposal so the card's
/// "Review" lands on the review screen with a fee already computed, the same
/// proposal the compose form would have made.
///
/// Nothing here reads a provider or touches the widget tree, so the whole
/// decision table is unit-testable against a fake Rust API. The flow provider
/// supplies the account and the spendable balance.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/migration_send_gate_provider.dart'
    show migrationSendGateProvider;
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/send_prefill_args.dart';
import 'send_flow.dart';

/// Validates a recipient address. Matches `rust_sync.validateAddress`.
typedef PaymentRequestValidateAddress =
    Future<rust_sync.AddressValidationResult> Function({
      required String address,
      required String network,
    });

/// Creates the proposal. Matches the shape of [proposeSendTransferWith] minus
/// the provider reader, which the service does not have.
typedef PaymentRequestProposeTransfer =
    Future<SendReviewArgs> Function({
      required String accountUuid,
      required String sendFlowId,
      required String address,
      required String addressType,
      required BigInt amountZatoshi,
      String? memo,
      bool isPaymentRequest,
      String? requestedBy,
      BigInt? requestedAmountZatoshi,
    });

/// Whether the wallet's spendable balance is settled *right now*.
///
/// Every answer this service gives about affordability is separated from the
/// balance it was handed by at least one await, so "settled" as of the start
/// of the check is a claim about the past. This re-reads the same predicate
/// at the moment a shortfall would be published — before the proposal goes
/// out and after it comes back.
typedef PaymentRequestSpendableIsAuthoritativeNow = bool Function();

/// The account's spendable balance *right now*, in zatoshi.
///
/// The figure a shortfall quotes has to come from the same moment as the
/// [PaymentRequestSpendableIsAuthoritativeNow] read that allowed it: the
/// balance the check was handed is older than every await it has taken since,
/// and the propose path in particular blocks until the wallet has an
/// authoritative spendable, which is exactly when the number moves.
typedef PaymentRequestSpendableBalanceNow = BigInt Function();

/// Releases a proposal. Matches [discardSendProposal].
typedef PaymentRequestDiscardProposal =
    Future<void> Function({
      required BigInt proposalId,
      required String sendFlowId,
      required String logContext,
    });

/// A proposal the card is holding on the user's behalf.
///
/// The card is a consent surface: between the pre-check and the user's answer
/// the wallet is sitting on a live `PROPOSAL_STORE` entry that nothing has
/// consumed. Every exit that is not "Review" has to hand it back — Edit,
/// Cancel, the ⨯, a newer link replacing this one, and the flow being cleared
/// on lock or wallet reset — which is what [discard] is for.
class PaymentRequestProposalHandle {
  PaymentRequestProposalHandle({
    required this.reviewArgs,
    required PaymentRequestDiscardProposal discardProposal,
  }) : _discardProposal = discardProposal;

  final SendReviewArgs reviewArgs;
  final PaymentRequestDiscardProposal _discardProposal;

  var _released = false;

  /// True once the proposal has been handed on to the review screen. A
  /// released handle never discards: the review screen owns the proposal from
  /// that point and runs its own discard when it is dismissed.
  bool get isReleased => _released;

  /// Transfers ownership to the caller without discarding.
  SendReviewArgs release() {
    _released = true;
    return reviewArgs;
  }

  /// Idempotent. Safe to call from any number of exit paths, and a no-op after
  /// [release].
  Future<void> discard({String logContext = 'PaymentRequest'}) async {
    if (_released) return;
    _released = true;
    await _discardProposal(
      proposalId: reviewArgs.proposalId,
      sendFlowId: reviewArgs.sendFlowId,
      logContext: logContext,
    );
  }
}

/// What the pre-check concluded.
sealed class PaymentRequestPrecheckResult {
  const PaymentRequestPrecheckResult();
}

/// The request can be acted on.
///
/// [proposal] is null exactly when the link named no amount: there is nothing
/// to propose yet, so the card drops its amount hero and its primary action
/// hands the request to the composer instead of the review screen.
final class PaymentRequestPrecheckReady extends PaymentRequestPrecheckResult {
  const PaymentRequestPrecheckReady({this.proposal});

  final PaymentRequestProposalHandle? proposal;

  SendReviewArgs? get reviewArgs => proposal?.reviewArgs;
}

/// The link carries an address this wallet cannot pay.
final class PaymentRequestPrecheckInvalidAddress
    extends PaymentRequestPrecheckResult {
  const PaymentRequestPrecheckInvalidAddress({this.message});

  /// Overrides the card's default "Recipient address doesn't look right".
  ///
  /// Set only when the wallet knows something more useful than "bad address" —
  /// today that is [kWrongNetworkAddressMessage], where the address is real
  /// but belongs to another network. Null keeps the default copy.
  final String? message;
}

/// The requested amount is above what the account can spend.
final class PaymentRequestPrecheckInsufficientFunds
    extends PaymentRequestPrecheckResult {
  const PaymentRequestPrecheckInsufficientFunds({this.spendableText});

  /// Preformatted spendable balance (`0.21 ZEC`) for the card's message.
  final String? spendableText;
}

/// Balances are not trustworthy yet, so "not enough" would be a lie.
///
/// This is the VZR-42 rule: a low spendable read mid-sync must never surface as
/// a final insufficient-funds answer.
final class PaymentRequestPrecheckSyncing extends PaymentRequestPrecheckResult {
  const PaymentRequestPrecheckSyncing();
}

/// Anything else, with a message already made friendly.
final class PaymentRequestPrecheckFailed extends PaymentRequestPrecheckResult {
  const PaymentRequestPrecheckFailed(this.message);

  final String message;
}

/// Runs the checks behind the payment-request card.
class PaymentRequestPrecheck {
  const PaymentRequestPrecheck({
    required this.validateAddress,
    required this.proposeTransfer,
    required this.discardProposal,
    required this.spendableIsAuthoritativeNow,
    required this.spendableBalanceNow,
  });

  final PaymentRequestValidateAddress validateAddress;
  final PaymentRequestProposeTransfer proposeTransfer;
  final PaymentRequestDiscardProposal discardProposal;

  /// Live re-read of the VZR-42 condition, for every answer that lands after
  /// the balance was read. Like [run]'s `spendableIsAuthoritative` it has no
  /// default: getting it wrong is the bug this guards.
  final PaymentRequestSpendableIsAuthoritativeNow spendableIsAuthoritativeNow;

  /// Live re-read of the balance itself, for the figure a shortfall quotes.
  final PaymentRequestSpendableBalanceNow spendableBalanceNow;

  /// [spendableIsAuthoritative] says whether [spendableBalance] is a settled
  /// post-sync figure. It has no default on purpose: getting it wrong is the
  /// VZR-42 bug, and the one production caller has to state which it holds.
  Future<PaymentRequestPrecheckResult> run({
    required SendPrefillArgs prefill,
    required String sendFlowId,
    required String? accountUuid,
    required BigInt spendableBalance,
    required bool spendableIsAuthoritative,
  }) async {
    final address = prefill.address.trim();
    if (address.isEmpty) {
      return const PaymentRequestPrecheckInvalidAddress();
    }

    final String addressType;
    try {
      final validation = await validateAddress(
        address: address,
        network: kZcashDefaultNetworkName,
      );
      if (!validation.isValid) {
        // A well-formed address for another network is still unpayable, but
        // it is not a malformed one — say which, so the user is not hunting
        // for a typo that is not there.
        return PaymentRequestPrecheckInvalidAddress(
          message: validation.wrongNetwork ? kWrongNetworkAddressMessage : null,
        );
      }
      addressType = validation.addressType;
    } catch (e) {
      log('PaymentRequest: address validation error: $e');
      return const PaymentRequestPrecheckInvalidAddress();
    }
    if (addressType.isEmpty ||
        addressType == 'invalid' ||
        addressType == 'error') {
      return const PaymentRequestPrecheckInvalidAddress();
    }

    // A ZIP-321 memo is exact bytes the requester encoded, so it is passed
    // through untouched when the prefill says to preserve it — the compose
    // form does the same through `preserveMemoText`, and the two paths have
    // to put identical bytes on chain or "Review" and "Edit then review"
    // become different payments.
    //
    // Nothing here drops a memo for a transparent-like recipient. Every
    // request that reaches this service — link or scanned QR — was built by
    // `Zip321PaymentRequest.parse`, which refuses `memo` on a `t`-prefixed
    // address outright (ZIP-321 forbids the combination), so the payer is told
    // the link is invalid before a card exists. One owner for that rule; a
    // second, silent one here would only ever describe a request the parser
    // already refused.
    final memo = prefill.preserveMemoText
        ? prefill.memoText
        : prefill.memoText?.trim();

    final amountText = prefill.amountText?.trim();
    if (amountText == null || amountText.isEmpty) {
      // Amount-less request: nothing to propose, and nothing that could be
      // insufficient. The composer collects the amount.
      return const PaymentRequestPrecheckReady();
    }

    final amountZatoshi = parseZecAmount(amountText);
    if (amountZatoshi == null) {
      return const PaymentRequestPrecheckFailed(
        "This link doesn't ask for a payable amount — enter one to continue",
      );
    }
    if (amountZatoshi <= BigInt.zero) {
      // `amount=0` parses, so the wallet read it fine — it is simply not a
      // payment. Treat it as the amount-less request it is and let the
      // composer collect one, rather than dead-ending the card on it.
      return const PaymentRequestPrecheckReady();
    }

    if (accountUuid == null) {
      return const PaymentRequestPrecheckFailed(
        'No active account — choose one, then open this link again',
      );
    }

    // VZR-42: a shortfall read off a balance that is still being scanned is
    // not an answer. Only a settled balance may end the check here; otherwise
    // the proposal decides, and it waits for the authoritative spendable
    // before Rust reports back through `_mapProposalError`.
    if (spendableIsAuthoritative && amountZatoshi > spendableBalance) {
      // Both values were read before the address validation above was
      // awaited, so they say the balance was settled, not that it still is.
      // A scan that started in between is already moving it, and the two
      // answers are not equally recoverable: `insufficient` is final and
      // leaves the card blocked on a figure the scan has outgrown, while
      // `syncing` re-checks itself the moment the wallet catches up.
      if (!spendableIsAuthoritativeNow()) {
        return const PaymentRequestPrecheckSyncing();
      }
      // Settled, but not necessarily the same figure: quote what the wallet
      // holds now, and if a scan landed the funds while this check was in
      // flight there is nothing to refuse — let the proposal decide.
      final spendableNow = spendableBalanceNow();
      if (amountZatoshi > spendableNow) {
        return PaymentRequestPrecheckInsufficientFunds(
          spendableText: _formatZec(spendableNow),
        );
      }
    }

    try {
      final reviewArgs = await proposeTransfer(
        accountUuid: accountUuid,
        sendFlowId: sendFlowId,
        address: address,
        addressType: addressType,
        amountZatoshi: amountZatoshi,
        memo: (memo != null && memo.isNotEmpty) ? memo : null,
        isPaymentRequest: true,
        requestedBy: prefill.label,
        requestedAmountZatoshi: amountZatoshi,
      );
      return PaymentRequestPrecheckReady(
        proposal: PaymentRequestProposalHandle(
          reviewArgs: reviewArgs,
          discardProposal: discardProposal,
        ),
      );
    } catch (e) {
      log('PaymentRequest: proposal failed: $e');
      return _mapProposalError(e.toString());
    }
  }

  /// Maps the stable VZR-42 conditions onto the card's status set.
  ///
  /// "Still syncing" and "not enough" are the two answers a user acts on
  /// differently, so they must not be collapsed into one generic failure — and
  /// a sync-time shortfall must land on syncing, never on insufficient.
  PaymentRequestPrecheckResult _mapProposalError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('wallet sync is still finishing') ||
        lower.contains('wallet sync failed before balance refresh') ||
        // What Rust itself emits when the wallet has no target/anchor
        // heights yet ("Wallet must sync before …"), which is exactly the
        // fresh-import state a payment link is most likely to land in.
        lower.contains('wallet must sync') ||
        lower.contains('sync_in_progress') ||
        lower.contains('scan_required')) {
      return const PaymentRequestPrecheckSyncing();
    }
    if (lower.contains('insufficientfunds') ||
        lower.contains('insufficient_funds') ||
        lower.contains('insufficient')) {
      // VZR-42, on the far side of the proposal: a shortfall computed while
      // the wallet is still short of the tip is not an answer, wherever it
      // was computed. The propose path waits for a settled spendable before
      // it decides, so a balance that is still unsettled *now* means the
      // scan moved under it and the figure the card would quote is stale.
      if (!spendableIsAuthoritativeNow()) {
        return const PaymentRequestPrecheckSyncing();
      }
      // And the figure is read now too. The wait this proposal just came back
      // from is a wait for an authoritative spendable, so the balance the
      // check started with is the one number guaranteed to predate whatever
      // the wallet settled on.
      return PaymentRequestPrecheckInsufficientFunds(
        spendableText: _formatZec(spendableBalanceNow()),
      );
    }
    // Wrong-network addresses are refused up front by the validation above;
    // this maps the remaining propose-time address failures (an address the
    // transaction builder rejects) onto the card's invalid-address status.
    if (lower.contains('decoding the address from a payment request') ||
        lower.contains('bad address')) {
      return const PaymentRequestPrecheckInvalidAddress();
    }
    return PaymentRequestPrecheckFailed(friendlyPaymentRequestCheckError(raw));
  }

  static String _formatZec(BigInt zatoshi) =>
      ZecAmount.fromZatoshi(zatoshi).activityDetail.toString();
}

/// The spendable figure the payment-request card pays from, out of an
/// account-scoped sync state.
///
/// Mirrors the compose form: while a Private migration holds the balance, the
/// Ironwood note is what can actually be spent. The card's first read and its
/// live re-read go through this one function rather than drifting apart.
BigInt paymentRequestSpendableOf(
  SyncState scoped, {
  required bool gatedByMigration,
}) => gatedByMigration
    ? scoped.displayIronwoodBalance
    : scoped.displaySpendableBalance;

/// The live pre-check, wired to Rust and the send pipeline.
final paymentRequestPrecheckProvider = Provider<PaymentRequestPrecheck>((ref) {
  return PaymentRequestPrecheck(
    validateAddress: rust_sync.validateAddress,
    discardProposal: discardSendProposal,
    // The same predicate the card's own read and its sync watch use, scoped
    // to the active account: an unscoped read answers with the wallet-wide
    // sync fields of a state that may hold no balance for this account.
    spendableIsAuthoritativeNow: () => activeAccountSpendableIsSettled(ref),
    // Scoped and gated the same way the card's first read is, so the two can
    // only ever disagree about the moment, never about which balance.
    spendableBalanceNow: () {
      final sync = ref.read(syncProvider).value;
      if (sync == null) return BigInt.zero;
      return paymentRequestSpendableOf(
        sync.scopedToAccount(
          ref.read(accountProvider).value?.activeAccountUuid,
        ),
        gatedByMigration: ref.read(migrationSendGateProvider),
      );
    },
    proposeTransfer:
        ({
          required String accountUuid,
          required String sendFlowId,
          required String address,
          required String addressType,
          required BigInt amountZatoshi,
          String? memo,
          bool isPaymentRequest = false,
          String? requestedBy,
          BigInt? requestedAmountZatoshi,
        }) => proposeSendTransferWith(
          syncNotifier: ref.read(syncProvider.notifier),
          readEndpoint: () => ref.read(rpcEndpointProvider),
          accountUuid: accountUuid,
          sendFlowId: sendFlowId,
          address: address,
          addressType: addressType,
          amountZatoshi: amountZatoshi,
          memo: memo,
          isPaymentRequest: isPaymentRequest,
          requestedBy: requestedBy,
          requestedAmountZatoshi: requestedAmountZatoshi,
        ),
  );
});
