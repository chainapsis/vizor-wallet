/// The shared send pipeline: proposal lifecycle and broadcast,
/// extracted from the desktop send screens so the mobile wizard drives
/// the exact same code. The PROPOSAL_STORE invariants live here in one
/// place — consume-on-entry happens inside the Rust execute calls, and
/// every non-consuming exit path runs the idempotent discard.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import 'sapling_params.dart';

/// Longest requester label the review screens will render.
///
/// The label comes straight out of a `zcash:` link's `label` parameter, so it
/// is attacker-controlled. Sanitising is what keeps it a short, single-line
/// piece of quoted text instead of something that can restyle a review screen.
const int kPaymentRequestLabelMaxLength = 64;

/// One-line, length-clamped version of an untrusted requester label, or null
/// when there is nothing left to show.
///
/// Collapses every run of whitespace (newlines included) to a single space so
/// the label cannot grow the row it sits in, then clamps the length.
String? sanitisePaymentRequestLabel(String? raw) {
  final collapsed = raw?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed == null || collapsed.isEmpty) return null;
  if (collapsed.length <= kPaymentRequestLabelMaxLength) return collapsed;
  return '${collapsed.substring(0, kPaymentRequestLabelMaxLength - 1)}\u2026';
}

/// Route-extra payload for the review/status legs of the send flow.
class SendReviewArgs {
  const SendReviewArgs({
    required this.proposalId,
    required this.sendFlowId,
    required this.proposalAccountUuid,
    required this.address,
    required this.addressType,
    required this.amountZatoshi,
    required this.feeZatoshi,
    required this.needsSaplingParams,
    this.memo,
    this.isPaymentRequest = false,
    this.requestedBy,
    this.requestedAmountZatoshi,
  });

  final BigInt proposalId;
  final String sendFlowId;
  final String proposalAccountUuid;
  final String address;
  final String addressType;
  final BigInt amountZatoshi;
  final BigInt feeZatoshi;
  final bool needsSaplingParams;
  final String? memo;

  /// This send answers a ZIP-321 payment request rather than being composed
  /// from scratch. Only the review framing reads it — the proposal, the
  /// broadcast and the receipt are identical either way.
  final bool isPaymentRequest;

  /// Sanitised requester label from the request, when it carried one.
  final String? requestedBy;

  /// The amount the request asked for, when it named one.
  ///
  /// Kept alongside [amountZatoshi] rather than replacing it so the review can
  /// say what was requested when the user edited the amount before confirming.
  final BigInt? requestedAmountZatoshi;

  bool get isShielded => addressType == 'unified' || addressType == 'sapling';

  /// The requested amount, but only when it differs from what is being sent.
  BigInt? get differingRequestedAmountZatoshi {
    final requested = requestedAmountZatoshi;
    if (requested == null || requested == amountZatoshi) return null;
    return requested;
  }
}

/// Hardware-wallet handoff payload: the phone-side proof PCZT plus the compact
/// Orchard/Ironwood signatures returned by Keystone's batch protocol. TEX is
/// the compatibility exception and carries the legacy full signer PCZT because the
/// batch response cannot represent its transparent-input signature.
class KeystoneBroadcastArgs {
  const KeystoneBroadcastArgs({
    required this.reviewArgs,
    required this.pcztWithProofs,
    required this.pcztWithSignatures,
  });

  final SendReviewArgs reviewArgs;
  final List<List<int>> pcztWithProofs;
  final List<List<int>> pcztWithSignatures;
}

class SendStatusRoutePayloadNotifier extends Notifier<Object?> {
  var _disposed = false;
  var _revision = 0;

  @override
  Object? build() {
    ref.onDispose(() => _disposed = true);
    return null;
  }

  void retain(Object payload) {
    _revision++;
    state = payload;
  }

  void clear() {
    _revision++;
    state = null;
  }

  void clearAfterNavigation() {
    final retainedRevision = _revision;
    unawaited(
      Future<void>(() {
        if (_disposed || _revision != retainedRevision) return;
        clear();
      }),
    );
  }
}

final sendStatusRoutePayloadProvider =
    NotifierProvider<SendStatusRoutePayloadNotifier, Object?>(
      SendStatusRoutePayloadNotifier.new,
    );

/// Whether the send shown on `/send/status` has reached a terminal phase —
/// succeeded or failed — so nothing is lost by leaving that screen.
///
/// The status screens keep owning their own presentation phase; this publishes
/// only the "safe to leave" bit, which surfaces outside the send flow need. The
/// payment-URI drain uses it to deliver a `zcash:` link that arrives on a
/// finished receipt instead of dropping it as an interrupted send.
///
/// A pending-broadcast outcome is deliberately NOT terminal: both status
/// screens still render it as in progress.
class SendStatusTerminalNotifier extends Notifier<bool> {
  var _disposed = false;
  var _revision = 0;

  @override
  bool build() {
    ref.onDispose(() => _disposed = true);
    return false;
  }

  /// The send finished (succeeded or failed).
  void markTerminal() {
    if (_disposed) return;
    _revision++;
    state = true;
  }

  /// A broadcast is starting: nothing is safe to leave yet.
  void reset() {
    if (_disposed) return;
    _revision++;
    state = false;
  }

  /// Releases the flag once the current lifecycle call has returned. The status
  /// screens call this from `dispose`, where Riverpod forbids a synchronous
  /// provider write; the revision guard stops a departing screen from clearing
  /// a newer one's flag. A microtask rather than a timer, so it cannot outlive
  /// a widget test's tree.
  void resetAfterNavigation() {
    final retainedRevision = _revision;
    scheduleMicrotask(() {
      if (_disposed || _revision != retainedRevision) return;
      reset();
    });
  }
}

final sendStatusTerminalProvider =
    NotifierProvider<SendStatusTerminalNotifier, bool>(
      SendStatusTerminalNotifier.new,
    );

class SendStatusRoutePayloadObserver extends NavigatorObserver {
  SendStatusRoutePayloadObserver({required this.onLeaveStatus});

  final VoidCallback onLeaveStatus;

  bool _isSendStatus(Route<dynamic>? route) =>
      route?.settings.name?.startsWith('/send/status') ?? false;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isSendStatus(route)) onLeaveStatus();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isSendStatus(route)) onLeaveStatus();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isSendStatus(oldRoute) && !_isSendStatus(newRoute)) {
      onLeaveStatus();
    }
  }
}

String sendStatusRouteLocation(String sendFlowId) =>
    Uri(path: '/send/status', queryParameters: {'flow': sendFlowId}).toString();

Object? resolveSendStatusRoutePayload({
  required Object? routePayload,
  required Object? retainedPayload,
  required String? sendFlowId,
}) {
  if (routePayload is SendReviewArgs || routePayload is KeystoneBroadcastArgs) {
    return routePayload;
  }
  return switch (retainedPayload) {
    SendReviewArgs(sendFlowId: final retainedFlowId)
        when retainedFlowId == sendFlowId =>
      retainedPayload,
    KeystoneBroadcastArgs(
      reviewArgs: SendReviewArgs(sendFlowId: final retainedFlowId),
    )
        when retainedFlowId == sendFlowId =>
      retainedPayload,
    _ => null,
  };
}

String newSendFlowId() {
  final random = math.Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

/// Proposes the transfer and packages the route args. The caller owns
/// the proposal from here: push it into review/broadcast or release it
/// with [discardSendProposal].
Future<SendReviewArgs> proposeSendTransfer({
  required WidgetRef ref,
  required String accountUuid,
  required String sendFlowId,
  required String address,
  required String addressType,
  required BigInt amountZatoshi,
  String? memo,
  bool isPaymentRequest = false,
  String? requestedBy,
  BigInt? requestedAmountZatoshi,
  Future<String> Function() loadDbPath = getWalletDbPath,
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
  loadDbPath: loadDbPath,
);

/// [proposeSendTransfer] with its two provider reads passed in.
///
/// `WidgetRef` and `Ref` share no common type, and the payment-request
/// pre-check runs from a `Notifier` rather than a widget. Naming the two
/// dependencies is what lets both callers reach the same proposal code.
/// [readEndpoint] stays lazy on purpose: the authoritative-spendable wait below
/// can outlast an endpoint failover, and the proposal must use the endpoint in
/// effect when it is actually made.
Future<SendReviewArgs> proposeSendTransferWith({
  required SyncNotifier syncNotifier,
  required RpcEndpointConfig Function() readEndpoint,
  required String accountUuid,
  required String sendFlowId,
  required String address,
  required String addressType,
  required BigInt amountZatoshi,
  String? memo,
  bool isPaymentRequest = false,
  String? requestedBy,
  BigInt? requestedAmountZatoshi,
  Future<String> Function() loadDbPath = getWalletDbPath,
}) async {
  final proposal = await syncNotifier.runWithAuthoritativeSpendable(
    accountUuid: accountUuid,
    operation: () async {
      final dbPath = await loadDbPath();
      final endpoint = readEndpoint();
      return rust_sync.proposeSend(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        sendFlowId: sendFlowId,
        toAddress: address,
        amountZatoshi: amountZatoshi,
        memo: (memo != null && memo.isNotEmpty) ? memo : null,
      );
    },
  );
  return SendReviewArgs(
    proposalId: proposal.proposalId,
    sendFlowId: sendFlowId,
    proposalAccountUuid: accountUuid,
    address: address,
    addressType: addressType,
    amountZatoshi: amountZatoshi,
    feeZatoshi: proposal.feeZatoshi,
    memo: (memo != null && memo.isNotEmpty) ? memo : null,
    needsSaplingParams: proposal.needsSaplingParams,
    isPaymentRequest: isPaymentRequest,
    requestedBy: sanitisePaymentRequestLabel(requestedBy),
    requestedAmountZatoshi: requestedAmountZatoshi,
  );
}

/// Idempotent proposal release for every non-consuming exit path.
Future<void> discardSendProposal({
  required BigInt proposalId,
  required String sendFlowId,
  required String logContext,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      await rust_sync.discardProposal(
        proposalId: proposalId,
        sendFlowId: sendFlowId,
      );
      log('$logContext: released proposal $proposalId');
      return;
    } catch (e) {
      lastError = e;
      log('$logContext: discardProposal cleanup attempt $attempt failed: $e');
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: attempt * 100));
      }
    }
  }
  // Rust keeps the owner token when unlock fails, so another idempotent
  // cleanup call can retry while height-based expiry remains the fallback.
  log('$logContext: proposal cleanup remains pending: $lastError');
}

Future<void> retainSendProposalLockUntilExpiry({
  required BigInt proposalId,
  required String sendFlowId,
  required String logContext,
}) async {
  try {
    await rust_sync.retainProposalLockUntilExpiry(
      proposalId: proposalId,
      sendFlowId: sendFlowId,
    );
    log('$logContext: retained proposal input lock until expiry $proposalId');
  } catch (e) {
    log('$logContext: retain proposal lock cleanup failed: $e');
  }
}

String friendlyProposeSendError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('wallet sync is still finishing') ||
      lower.contains('wallet sync failed before balance refresh')) {
    return 'Finishing wallet sync. Try again shortly.';
  }
  if (lower.contains('insufficientfunds') || lower.contains('insufficient')) {
    return 'Insufficient shielded balance to cover amount and fee.';
  }
  if (lower.contains('grpc connect failed') ||
      lower.contains('connection refused') ||
      lower.contains('dns error') ||
      lower.contains('tls error')) {
    return 'Network error. Check your connection and try again.';
  }
  // Partial broadcast must be checked before generic "broadcast rejected"
  if (lower.contains('broadcast failed after') && lower.contains('txs sent')) {
    return 'Some parts of this transaction were sent. Open Activity to see '
        'what went through before you try again.';
  }
  if (lower.contains('broadcast rejected')) {
    return 'The network rejected this transaction. Try again.';
  }
  if (lower.contains('proposal not found') ||
      lower.contains('send flow mismatch')) {
    return 'Transaction expired before it could be sent. Try again.';
  }
  return 'Send failed. Try again.';
}

String friendlyBroadcastError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('insufficientfunds') || lower.contains('insufficient')) {
    return 'Insufficient shielded balance to cover amount and fee.';
  }
  if (lower.contains('grpc connect failed') ||
      lower.contains('connection refused') ||
      lower.contains('dns error') ||
      lower.contains('tls error')) {
    return 'Network error. Check your connection and try again.';
  }
  if (lower.contains('broadcast failed after') && lower.contains('txs sent')) {
    return 'Some parts of this transaction were sent. Open Activity to see '
        'what went through before you try again.';
  }
  if (lower.contains('broadcast rejected')) {
    return 'The network rejected this transaction. Try again later.';
  }
  if (lower.contains('proposal not found') ||
      lower.contains('send flow mismatch')) {
    return 'Transaction expired before it could be sent.';
  }
  return "Transaction couldn't be sent. Go back to your wallet and check "
      'the latest status.';
}

enum SendBroadcastPhase { succeeded, pendingBroadcast, failed, aborted }

class SendBroadcastOutcome {
  const SendBroadcastOutcome({
    required this.phase,
    required this.proposalConsumed,
    this.txid,
    this.statusMessage,
    this.error,
  });

  final SendBroadcastPhase phase;

  /// Whether the Rust execute call took ownership of the proposal —
  /// when false the caller must not assume the proposal was released
  /// here unless the phase is [SendBroadcastPhase.aborted].
  final bool proposalConsumed;
  final String? txid;
  final String? statusMessage;
  final String? error;
}

String? _firstTxid(String txids) {
  for (final part in txids.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String? _lastTxid(String txids) {
  for (final part in txids.split(',').reversed) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String _broadcastStatusMessage(rust_sync.ExecuteProposalResult result) {
  if (result.status == 'partial_broadcast') {
    return 'Some transactions were broadcast and the rest will retry automatically. Check activity before sending again.';
  }
  final rawMessage = result.message?.toLowerCase() ?? '';
  if (rawMessage.contains('broadcast rejected')) {
    return "Transaction was created locally but didn't reach the network. "
        'The wallet will keep retrying until it expires. '
        "Don't send again unless this one expires.";
  }
  return 'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.';
}

String _pcztBroadcastStatusMessage(
  rust_sync.StoreAndBroadcastPcztsResult result,
) {
  if (result.status == 'broadcast_unknown') {
    return result.message ??
        'The first transaction is stored locally and may have reached the network, but confirmation timed out. Check Activity before sending again.';
  }
  if (result.status == 'partial_broadcast') {
    return result.message ??
        'The first transaction was accepted, but the dependent transaction did not complete. Check Activity before sending again.';
  }
  if (result.status == 'broadcasted_storage_failed') {
    return result.message ??
        'The transaction reached the network, but local tracking failed. Check Activity or an explorer before sending again.';
  }
  return result.message ??
      'The transaction broadcast did not complete. Check Activity before sending again.';
}

/// Runs the full broadcast leg for a proposed send — Sapling params
/// gate, software execute (macOS keychain or in-memory mnemonic) or
/// hardware PCZT combine+broadcast, endpoint failover, post-send
/// refresh. Shared by the desktop and mobile status screens.
///
/// [confirmSaplingParamsDownload] asks the user to approve the ~50MB
/// download; [shouldAbort] is polled around the long awaits (the
/// desktop screen aborts when unmounted). On abort the proposal and any
/// retained owner-scoped input lock are released here.
Future<SendBroadcastOutcome> runSendBroadcast({
  required WidgetRef ref,
  required SendReviewArgs args,
  KeystoneBroadcastArgs? keystone,
  required Future<bool> Function() confirmSaplingParamsDownload,
  Future<bool> Function()? shouldAbort,
}) async {
  var proposalConsumed = keystone != null;
  var proposalReleased = false;

  Future<bool> abortRequested() async {
    if (shouldAbort == null) return false;
    if (!await shouldAbort()) return false;
    if (!proposalReleased) {
      await discardSendProposal(
        proposalId: args.proposalId,
        sendFlowId: args.sendFlowId,
        logContext: 'SendBroadcast(abort)',
      );
      proposalReleased = true;
      proposalConsumed = true;
    }
    return true;
  }

  SendBroadcastOutcome aborted() => SendBroadcastOutcome(
    phase: SendBroadcastPhase.aborted,
    proposalConsumed: proposalConsumed,
  );

  try {
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    var saplingParams = await loadSaplingParamsStatus();

    if (args.needsSaplingParams) {
      if (!saplingParams.complete) {
        if (await abortRequested()) return aborted();
        final downloadConfirmed = await confirmSaplingParamsDownload();
        if (!downloadConfirmed) {
          if (await abortRequested()) return aborted();
          if (!proposalReleased) {
            await discardSendProposal(
              proposalId: args.proposalId,
              sendFlowId: args.sendFlowId,
              logContext: 'SendBroadcast(params-declined)',
            );
            proposalReleased = true;
            proposalConsumed = true;
          }
          return SendBroadcastOutcome(
            phase: SendBroadcastPhase.failed,
            proposalConsumed: proposalConsumed,
            error:
                'Sending was cancelled before proving parameters were downloaded.',
          );
        }

        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('SendBroadcast: $message'),
        );
        saplingParams = await loadSaplingParamsStatus();
        if (await abortRequested()) return aborted();
      }
    }

    final accountNotifier = ref.read(accountProvider.notifier);
    final isHardware = accountNotifier.isHardwareAccount(
      args.proposalAccountUuid,
    );

    late final String txids;
    late final bool broadcastComplete;
    late final bool broadcastExpired;
    late final String? receiptTxid;
    late final String? pendingStatusMessage;
    String? broadcastMessageForFallback;

    if (isHardware) {
      if (keystone == null) {
        throw Exception('Missing Keystone transaction signature.');
      }
      proposalConsumed = true;
      if (keystone.pcztWithProofs.length !=
              keystone.pcztWithSignatures.length ||
          keystone.pcztWithProofs.isEmpty) {
        throw Exception('Invalid Keystone signing round count.');
      }
      // The Rust orchestration owns proposal-lock cleanup on every outcome
      // from this point onward, including validation and atomic-store errors.
      proposalReleased = true;
      final rust_sync.StoreAndBroadcastPcztsResult result;
      if (args.addressType == 'tex') {
        result = await rust_sync.storeAndBroadcastSignedPcztsForProposal(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          proposalId: args.proposalId,
          sendFlowId: args.sendFlowId,
          pcztWithProofs: keystone.pcztWithProofs
              .map(Uint8List.fromList)
              .toList(),
          pcztWithSignatures: keystone.pcztWithSignatures
              .map(Uint8List.fromList)
              .toList(),
          spendParamsPath: args.needsSaplingParams
              ? saplingParams.spendPath
              : null,
          outputParamsPath: args.needsSaplingParams
              ? saplingParams.outputPath
              : null,
        );
      } else {
        result = await rust_sync
            .storeAndBroadcastPcztsWithKeystoneSignaturesForProposal(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              proposalId: args.proposalId,
              sendFlowId: args.sendFlowId,
              pcztWithProofs: keystone.pcztWithProofs
                  .map(Uint8List.fromList)
                  .toList(),
              signatureBlobs: keystone.pcztWithSignatures
                  .map(Uint8List.fromList)
                  .toList(),
              spendParamsPath: args.needsSaplingParams
                  ? saplingParams.spendPath
                  : null,
              outputParamsPath: args.needsSaplingParams
                  ? saplingParams.outputPath
                  : null,
            );
      }
      txids = result.txids;
      broadcastComplete = result.status == 'broadcasted';
      broadcastExpired = result.status == 'expired';
      // A completed TEX send is represented by the dependent final
      // transaction, not its first-step ephemeral funding transaction.
      receiptTxid = broadcastExpired
          ? null
          : broadcastComplete
          ? _lastTxid(txids)
          : _firstTxid(txids);
      pendingStatusMessage = broadcastComplete || broadcastExpired
          ? null
          : _pcztBroadcastStatusMessage(result);
      broadcastMessageForFallback = result.message;
    } else {
      late final rust_sync.ExecuteProposalResult result;
      if (Platform.isMacOS) {
        final password = ref
            .read(appSecurityProvider.notifier)
            .requireSessionPasswordForNativeSecretUse();
        result = await rust_sync.executeProposalWithMacosStoredMnemonic(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          proposalId: args.proposalId,
          sendFlowId: args.sendFlowId,
          password: password,
          spendParamsPath: args.needsSaplingParams
              ? saplingParams.spendPath
              : null,
          outputParamsPath: args.needsSaplingParams
              ? saplingParams.outputPath
              : null,
        );
      } else {
        final mnemonicBytes = await accountNotifier.getMnemonicBytesForAccount(
          args.proposalAccountUuid,
        );
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          if (await abortRequested()) return aborted();
          return SendBroadcastOutcome(
            phase: SendBroadcastPhase.failed,
            proposalConsumed: proposalConsumed,
            error: 'Mnemonic not found for the proposal account.',
          );
        }

        late final Future<rust_sync.ExecuteProposalResult> resultFuture;
        try {
          resultFuture = rust_sync.executeProposal(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            proposalId: args.proposalId,
            sendFlowId: args.sendFlowId,
            mnemonicBytes: mnemonicBytes,
            spendParamsPath: args.needsSaplingParams
                ? saplingParams.spendPath
                : null,
            outputParamsPath: args.needsSaplingParams
                ? saplingParams.outputPath
                : null,
          );
        } finally {
          mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
        }
        result = await resultFuture;
      }
      proposalConsumed = true;
      txids = result.txids;
      broadcastComplete = result.status == 'broadcasted';
      broadcastExpired = false;
      receiptTxid = _firstTxid(txids);
      pendingStatusMessage = broadcastComplete
          ? null
          : _broadcastStatusMessage(result);
      broadcastMessageForFallback = result.message;
    }

    if (!broadcastComplete &&
        !broadcastExpired &&
        broadcastMessageForFallback != null) {
      final switched = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .switchToFallbackFor(
            broadcastMessageForFallback,
            endpoint: endpoint,
            operation: isHardware
                ? 'keystone send broadcast'
                : 'send broadcast',
          );
      if (switched) {
        unawaited(ref.read(syncProvider.notifier).restartSync());
      }
    }

    try {
      await ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (e) {
      log('SendBroadcast: refreshAfterSend failed (non-critical): $e');
    }

    if (await abortRequested()) return aborted();
    return SendBroadcastOutcome(
      phase: broadcastExpired
          ? SendBroadcastPhase.failed
          : broadcastComplete
          ? SendBroadcastPhase.succeeded
          : SendBroadcastPhase.pendingBroadcast,
      proposalConsumed: proposalConsumed,
      txid: receiptTxid,
      statusMessage: pendingStatusMessage,
      error: broadcastExpired
          ? 'Keystone signing request expired before broadcast. Return to your wallet, wait for sync, then review the payment and try again.'
          : null,
    );
  } catch (e) {
    log('SendBroadcast: ERROR: $e');
    final message = friendlyBroadcastError(e.toString());
    if (await abortRequested()) return aborted();
    if (!proposalReleased) {
      await discardSendProposal(
        proposalId: args.proposalId,
        sendFlowId: args.sendFlowId,
        logContext: 'SendBroadcast(pre-broadcast-failure)',
      );
      proposalReleased = true;
      proposalConsumed = true;
    }
    return SendBroadcastOutcome(
      phase: SendBroadcastPhase.failed,
      proposalConsumed: proposalConsumed,
      error: message,
    );
  }
}
