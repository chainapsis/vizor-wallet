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
import '../../../core/formatting/zec_amount.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/send_prefill_args.dart';
import 'send_flow.dart';

/// Validates a recipient address. Matches `rust_sync.validateAddress`.
typedef PaymentRequestValidateAddress =
    Future<rust_sync.AddressValidationResult> Function({
      required String address,
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
  const PaymentRequestPrecheckInvalidAddress();
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
  });

  final PaymentRequestValidateAddress validateAddress;
  final PaymentRequestProposeTransfer proposeTransfer;
  final PaymentRequestDiscardProposal discardProposal;

  /// Address types the compose form refuses to attach a memo to; the request's
  /// memo is dropped rather than carried into a proposal that would reject it.
  static bool isTransparentLikeType(String addressType) =>
      addressType == 'transparent' || addressType == 'tex';

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
      final validation = await validateAddress(address: address);
      if (!validation.isValid) {
        return const PaymentRequestPrecheckInvalidAddress();
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

    // Same rule the compose form applies the moment validation settles: a
    // transparent-like recipient cannot carry an encrypted memo.
    final rawMemo = prefill.memoText?.trim();
    final memo = isTransparentLikeType(addressType) ? null : rawMemo;

    final amountText = prefill.amountText?.trim();
    if (amountText == null || amountText.isEmpty) {
      // Amount-less request: nothing to propose, and nothing that could be
      // insufficient. The composer collects the amount.
      return const PaymentRequestPrecheckReady();
    }

    final amountZatoshi = parseZecAmount(amountText);
    if (amountZatoshi == null || amountZatoshi <= BigInt.zero) {
      return const PaymentRequestPrecheckFailed(
        'This payment link has an amount the wallet cannot read',
      );
    }

    if (accountUuid == null) {
      return const PaymentRequestPrecheckFailed('No account is open');
    }

    // VZR-42: a shortfall read off a balance that is still being scanned is
    // not an answer. Only a settled balance may end the check here; otherwise
    // the proposal decides, and it waits for the authoritative spendable
    // before Rust reports back through `_mapProposalError`.
    if (spendableIsAuthoritative && amountZatoshi > spendableBalance) {
      return PaymentRequestPrecheckInsufficientFunds(
        spendableText: _formatZec(spendableBalance),
      );
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
      return _mapProposalError(e.toString(), spendableBalance);
    }
  }

  /// Maps the stable VZR-42 conditions onto the card's status set.
  ///
  /// "Still syncing" and "not enough" are the two answers a user acts on
  /// differently, so they must not be collapsed into one generic failure — and
  /// a sync-time shortfall must land on syncing, never on insufficient.
  PaymentRequestPrecheckResult _mapProposalError(
    String raw,
    BigInt spendableBalance,
  ) {
    final lower = raw.toLowerCase();
    if (lower.contains('wallet sync is still finishing') ||
        lower.contains('wallet sync failed before balance refresh') ||
        lower.contains('sync_in_progress') ||
        lower.contains('scan_required')) {
      return const PaymentRequestPrecheckSyncing();
    }
    if (lower.contains('insufficientfunds') ||
        lower.contains('insufficient_funds') ||
        lower.contains('insufficient')) {
      return PaymentRequestPrecheckInsufficientFunds(
        spendableText: _formatZec(spendableBalance),
      );
    }
    return PaymentRequestPrecheckFailed(friendlyProposeSendError(raw));
  }

  static String _formatZec(BigInt zatoshi) =>
      ZecAmount.fromZatoshi(zatoshi).activityDetail.toString();
}

/// The live pre-check, wired to Rust and the send pipeline.
final paymentRequestPrecheckProvider = Provider<PaymentRequestPrecheck>((ref) {
  return PaymentRequestPrecheck(
    validateAddress: rust_sync.validateAddress,
    discardProposal: discardSendProposal,
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
