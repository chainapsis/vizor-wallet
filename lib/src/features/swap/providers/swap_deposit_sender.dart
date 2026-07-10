import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../domain/swap_contract.dart';
import '../models/swap_deposit_broadcast_result.dart';

final swapDepositSenderProvider = Provider<SwapDepositSender>((ref) {
  return RustSwapDepositSender(ref);
});

abstract interface class SwapDepositSender {
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  });

  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  });
}

class RustSwapDepositSender implements SwapDepositSender {
  RustSwapDepositSender(this._ref);

  final Ref _ref;

  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    if (quote.sellAsset != SwapAsset.zec) {
      throw StateError('Only ZEC deposits can be sent by this wallet');
    }

    await _ref
        .read(syncProvider.notifier)
        .waitForAuthoritativeSpendable(accountUuid: accountUuid);
    final amountZatoshi = zecDepositAmountZatoshiForQuote(quote);
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;

    log(
      'SwapDepositSender: preflight begin '
      'deposit=${_shortSwapValue(quote.depositInstruction.address)} '
      'zatoshi=$amountZatoshi',
    );
    final fee = await rust_sync.estimateFee(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      toAddress: quote.depositInstruction.address,
      amountZatoshi: amountZatoshi,
    );
    log('SwapDepositSender: preflight complete fee=$fee');
    return fee;
  }

  @override
  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    if (quote.sellAsset != SwapAsset.zec) {
      throw StateError('Only ZEC deposits can be sent by this wallet');
    }

    await _ref
        .read(syncProvider.notifier)
        .waitForAuthoritativeSpendable(accountUuid: accountUuid);
    final amountZatoshi = zecDepositAmountZatoshiForQuote(quote);
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final sendFlowId = _newSwapSendFlowId();
    BigInt? proposalId;
    var proposalConsumed = false;

    try {
      log(
        'SwapDepositSender: propose begin flow=$sendFlowId '
        'deposit=${_shortSwapValue(quote.depositInstruction.address)} '
        'zatoshi=$amountZatoshi',
      );
      final proposal = await rust_sync.proposeSend(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        sendFlowId: sendFlowId,
        toAddress: quote.depositInstruction.address,
        amountZatoshi: amountZatoshi,
      );
      proposalId = proposal.proposalId;
      log(
        'SwapDepositSender: proposal ready flow=$sendFlowId '
        'proposal=${proposal.proposalId} '
        'needsSapling=${proposal.needsSaplingParams}',
      );

      if (proposal.needsSaplingParams) {
        throw StateError(
          'Sapling parameter download is not supported in the swap UI yet',
        );
      }

      late final rust_sync.ExecuteProposalResult result;
      log(
        'SwapDepositSender: broadcast begin flow=$sendFlowId '
        'proposal=${proposal.proposalId}',
      );

      if (Platform.isMacOS) {
        final password = _ref
            .read(appSecurityProvider.notifier)
            .requireSessionPasswordForNativeSecretUse();
        result = await rust_sync.executeProposalWithMacosStoredMnemonic(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          proposalId: proposal.proposalId,
          sendFlowId: sendFlowId,
          password: password,
        );
      } else {
        final mnemonicBytes = await _ref
            .read(accountProvider.notifier)
            .getMnemonicBytesForAccount(accountUuid);
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw StateError('Mnemonic not found for the active account');
        }

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
      }
      proposalConsumed = true;

      try {
        await _ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('SwapDepositSender: refreshAfterSend failed flow=$sendFlowId: $e');
      }

      final txid = _firstTxid(result.txids);
      if (txid == null) {
        throw StateError('ZEC deposit broadcast returned no txid');
      }
      log(
        'SwapDepositSender: broadcast complete flow=$sendFlowId '
        'tx=${_shortSwapValue(txid)} status=${result.status}',
      );
      return SwapDepositBroadcastResult(
        txHash: txid,
        status: result.status,
        message: result.message,
      );
    } catch (e) {
      log('SwapDepositSender: failed flow=$sendFlowId error=$e');
      rethrow;
    } finally {
      if (proposalId != null && !proposalConsumed) {
        try {
          await rust_sync.discardProposal(
            proposalId: proposalId,
            sendFlowId: sendFlowId,
          );
          log(
            'SwapDepositSender: discarded proposal flow=$sendFlowId '
            'proposal=$proposalId',
          );
        } catch (e) {
          log(
            'SwapDepositSender: discard proposal failed flow=$sendFlowId '
            'proposal=$proposalId error=$e',
          );
        }
      }
    }
  }
}

BigInt zecDepositAmountZatoshiForQuote(SwapQuote quote) {
  if (quote.sellAsset != SwapAsset.zec) {
    throw StateError('Only ZEC deposits can be sent by this wallet');
  }
  final zatoshi = quote.sellAmountBaseUnits;
  if (zatoshi == null || zatoshi <= BigInt.zero) {
    throw StateError('Swap quote is missing executable ZEC amount');
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

String _shortSwapValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '-';
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 7)}...${trimmed.substring(trimmed.length - 6)}';
}
