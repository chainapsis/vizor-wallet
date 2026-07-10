/// The shared send pipeline: proposal lifecycle and broadcast,
/// extracted from the desktop send screens so the mobile wizard drives
/// the exact same code. The PROPOSAL_STORE invariants live here in one
/// place — consume-on-entry happens inside the Rust execute calls, and
/// every non-consuming exit path runs the idempotent discard.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import 'sapling_params.dart';

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

  bool get isShielded => addressType == 'unified' || addressType == 'sapling';
}

/// Hardware-wallet handoff payload: the phone-side proof clone plus the
/// device-signed clone, combined by `extract_and_broadcast_pczt`.
class KeystoneBroadcastArgs {
  const KeystoneBroadcastArgs({
    required this.reviewArgs,
    required this.pcztWithProofsBytes,
    required this.pcztWithSignaturesBytes,
  });

  final SendReviewArgs reviewArgs;
  final List<int> pcztWithProofsBytes;
  final List<int> pcztWithSignaturesBytes;
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
  Future<String> Function() loadDbPath = getWalletDbPath,
}) async {
  await ref
      .read(syncProvider.notifier)
      .waitForAuthoritativeSpendable(accountUuid: accountUuid);
  final dbPath = await loadDbPath();
  final endpoint = ref.read(rpcEndpointProvider);
  final proposal = await rust_sync.proposeSend(
    dbPath: dbPath,
    network: endpoint.networkName,
    accountUuid: accountUuid,
    sendFlowId: sendFlowId,
    toAddress: address,
    amountZatoshi: amountZatoshi,
    memo: (memo != null && memo.isNotEmpty) ? memo : null,
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
  );
}

/// Idempotent proposal release for every non-consuming exit path.
Future<void> discardSendProposal({
  required BigInt proposalId,
  required String sendFlowId,
  required String logContext,
}) async {
  try {
    await rust_sync.discardProposal(
      proposalId: proposalId,
      sendFlowId: sendFlowId,
    );
    log('$logContext: released proposal $proposalId');
  } catch (e) {
    log('$logContext: discardProposal cleanup failed (non-critical): $e');
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
  rust_sync.ExtractAndBroadcastPcztResult result,
) {
  if (result.status == 'broadcast_unknown') {
    return result.message ??
        'The transaction may have reached the network, but confirmation timed out. Check activity before sending again.';
  }
  if (result.status == 'broadcasted_storage_failed') {
    return result.message ??
        'The transaction reached the network, but Vizor could not store it locally. Do not send again until sync or an explorer confirms the latest status.';
  }
  final rawMessage = result.message?.toLowerCase() ?? '';
  if (rawMessage.contains('broadcast rejected')) {
    return 'Transaction was rejected by the network. Please try again later.';
  }
  return 'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.';
}

/// Runs the full broadcast leg for a proposed send — Sapling params
/// gate, software execute (macOS keychain or in-memory mnemonic) or
/// hardware PCZT combine+broadcast, endpoint failover, post-send
/// refresh. Shared by the desktop and mobile status screens.
///
/// [confirmSaplingParamsDownload] asks the user to approve the ~50MB
/// download; [shouldAbort] is polled around the long awaits (the
/// desktop screen aborts when unmounted). On abort the proposal is
/// released here when it was not consumed.
Future<SendBroadcastOutcome> runSendBroadcast({
  required WidgetRef ref,
  required SendReviewArgs args,
  KeystoneBroadcastArgs? keystone,
  required Future<bool> Function() confirmSaplingParamsDownload,
  Future<bool> Function()? shouldAbort,
}) async {
  var proposalConsumed = keystone != null;

  Future<bool> abortRequested() async {
    if (shouldAbort == null) return false;
    if (!await shouldAbort()) return false;
    if (!proposalConsumed) {
      await discardSendProposal(
        proposalId: args.proposalId,
        sendFlowId: args.sendFlowId,
        logContext: 'SendBroadcast(abort)',
      );
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
    late final String? pendingStatusMessage;
    String? broadcastMessageForFallback;

    if (isHardware) {
      if (keystone == null) {
        throw Exception('Missing Keystone transaction signature.');
      }
      proposalConsumed = true;
      final result = await rust_sync.extractAndBroadcastPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        pcztWithProofsBytes: keystone.pcztWithProofsBytes,
        pcztWithSignaturesBytes: keystone.pcztWithSignaturesBytes,
        spendParamsPath: args.needsSaplingParams
            ? saplingParams.spendPath
            : null,
        outputParamsPath: args.needsSaplingParams
            ? saplingParams.outputPath
            : null,
      );
      txids = result.txid;
      broadcastComplete = result.status == 'broadcasted';
      pendingStatusMessage = broadcastComplete
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
      pendingStatusMessage = broadcastComplete
          ? null
          : _broadcastStatusMessage(result);
      broadcastMessageForFallback = result.message;
    }

    if (!broadcastComplete && broadcastMessageForFallback != null) {
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
      phase: broadcastComplete
          ? SendBroadcastPhase.succeeded
          : SendBroadcastPhase.pendingBroadcast,
      proposalConsumed: proposalConsumed,
      txid: _firstTxid(txids),
      statusMessage: pendingStatusMessage,
    );
  } catch (e) {
    log('SendBroadcast: ERROR: $e');
    final message = friendlyBroadcastError(e.toString());
    if (await abortRequested()) return aborted();
    return SendBroadcastOutcome(
      phase: SendBroadcastPhase.failed,
      proposalConsumed: proposalConsumed,
      error: message,
    );
  }
}
