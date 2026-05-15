import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../domain/swap_contract.dart';

final swapDepositSenderProvider = Provider<SwapDepositSender>((ref) {
  return RustSwapDepositSender(ref);
});

abstract interface class SwapDepositSender {
  Future<String> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  });
}

class RustSwapDepositSender implements SwapDepositSender {
  RustSwapDepositSender(this._ref);

  final Ref _ref;

  @override
  Future<String> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    if (quote.sellAsset != SwapAsset.zec) {
      throw StateError('Only ZEC deposits can be sent by this wallet');
    }

    final amountZatoshi = _quoteZatoshi(quote);
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointProvider);
    final sendFlowId = _newSwapSendFlowId();
    BigInt? proposalId;
    var proposalConsumed = false;

    try {
      final proposal = await rust_sync.proposeSend(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        sendFlowId: sendFlowId,
        toAddress: quote.depositInstruction.address,
        amountZatoshi: amountZatoshi,
      );
      proposalId = proposal.proposalId;

      if (proposal.needsSaplingParams) {
        throw StateError(
          'Sapling parameter download is not supported in the swap prototype yet',
        );
      }

      final mnemonicBytes = await _ref
          .read(accountProvider.notifier)
          .getMnemonicBytesForAccount(accountUuid);
      if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
        throw StateError('Mnemonic not found for the active account');
      }

      proposalConsumed = true;
      late final rust_sync.ExecuteProposalResult result;
      late final Future<rust_sync.ExecuteProposalResult> resultFuture;
      try {
        resultFuture = rust_sync.executeProposal(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          proposalId: proposal.proposalId,
          sendFlowId: sendFlowId,
          mnemonicBytes: mnemonicBytes,
        );
      } finally {
        mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
      }
      result = await resultFuture;

      try {
        await _ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (_) {}

      final txid = _firstTxid(result.txids);
      if (txid == null) {
        throw StateError('ZEC deposit broadcast returned no txid');
      }
      return txid;
    } finally {
      if (proposalId != null && !proposalConsumed) {
        try {
          await rust_sync.discardProposal(
            proposalId: proposalId,
            sendFlowId: sendFlowId,
          );
        } catch (_) {}
      }
    }
  }
}

BigInt _quoteZatoshi(SwapQuote quote) {
  final amountText = quote.sellAmountText.split(' ').first.trim();
  final zatoshi = parseZecAmount(amountText);
  if (zatoshi == null || zatoshi <= BigInt.zero) {
    throw FormatException('Invalid ZEC swap amount: $amountText');
  }
  return zatoshi;
}

String _newSwapSendFlowId() {
  return 'swap-${DateTime.now().microsecondsSinceEpoch}';
}

String? _firstTxid(String txids) {
  for (final part in txids.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}
