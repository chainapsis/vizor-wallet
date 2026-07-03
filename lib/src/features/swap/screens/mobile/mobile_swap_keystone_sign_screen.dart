import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../keystone/widgets/mobile_keystone_pczt_signing_flow.dart';
import '../../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../../send/services/sapling_params.dart';
import '../../models/swap_deposit_broadcast_result.dart';
import '../../models/swap_keystone_broadcast_result.dart';
import '../../models/swap_models.dart';
import '../../providers/swap_hardware_signing_service.dart';
import '../../../../../l10n/app_localizations.dart';

class MobileSwapKeystoneSignArgs {
  const MobileSwapKeystoneSignArgs({required this.intent});

  final SwapIntent intent;
}

sealed class MobileSwapKeystoneSignResult {
  const MobileSwapKeystoneSignResult();
}

class MobileSwapKeystoneSignSuccess extends MobileSwapKeystoneSignResult {
  const MobileSwapKeystoneSignSuccess(this.broadcast);

  final SwapKeystoneBroadcastResult broadcast;
}

class MobileSwapKeystoneSignFailure extends MobileSwapKeystoneSignResult {
  const MobileSwapKeystoneSignFailure(this.message);

  final String message;
}

class MobileSwapKeystoneSignScreen extends ConsumerStatefulWidget {
  const MobileSwapKeystoneSignScreen({required this.args, super.key});

  final MobileSwapKeystoneSignArgs args;

  @override
  ConsumerState<MobileSwapKeystoneSignScreen> createState() =>
      _MobileSwapKeystoneSignScreenState();
}

class _MobileSwapKeystoneSignScreenState
    extends ConsumerState<MobileSwapKeystoneSignScreen> {
  SwapHardwarePcztDraft? _draft;
  SaplingParamsStatus? _saplingParams;

  @override
  Widget build(BuildContext context) {
    return MobileKeystonePcztSigningFlow(
      title: AppLocalizations.of(context).swapSignZecDeposit,
      failedTitle: AppLocalizations.of(context).swapKeystoneSigningFailed,
      description:
          AppLocalizations.of(context).swapScanTxQrInstructions,
      preparePczt: _preparePczt,
      onSigned: _handleSignedPczt,
      friendlyError: _friendlyError,
      keyPrefix: 'mobile_swap_keystone_sign',
      finalizingSignatureLabel: AppLocalizations.of(context).swapBroadcastingZecDeposit,
      logTag: 'MobileSwapKeystoneSign',
    );
  }

  Future<MobileKeystonePcztSigningPayload> _preparePczt(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final accountUuid = widget.args.intent.accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) {
      throw StateError('Swap account is missing.');
    }

    final service = ref.read(swapHardwareSigningServiceProvider);
    final draft = await service.createZecDepositPczt(
      accountUuid: accountUuid,
      intent: widget.args.intent,
    );

    SaplingParamsStatus? saplingParams;
    if (draft.needsSaplingParams) {
      saplingParams = await loadSaplingParamsStatus();
      if (!saplingParams.complete) {
        if (!context.mounted) {
          throw const MobileKeystonePcztSigningAborted();
        }
        final confirmed = await _confirmSaplingParamsDownload(context);
        if (!confirmed) {
          throw const MobileKeystonePcztSigningAborted();
        }
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('MobileSwapKeystoneSign: $message'),
        );
        saplingParams = await loadSaplingParamsStatus();
      }
    }

    final urParts = await service.encodeSigningUrParts(draft: draft);
    _draft = draft;
    _saplingParams = saplingParams;

    return MobileKeystonePcztSigningPayload(
      urParts: urParts,
      pcztWithProofs: service.addProofsForSigning(
        draft: draft,
        spendParamsPath: draft.needsSaplingParams
            ? saplingParams!.spendPath
            : null,
        outputParamsPath: draft.needsSaplingParams
            ? saplingParams!.outputPath
            : null,
      ),
    );
  }

  Future<bool> _confirmSaplingParamsDownload(BuildContext context) async {
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (_) => const MobileSaplingParamsSheet(),
    );
    return confirmed == true;
  }

  Future<void> _handleSignedPczt(
    BuildContext context,
    WidgetRef ref,
    List<int> pcztWithProofs,
    Uint8List signedPczt,
  ) async {
    final draft = _draft;
    final saplingParams = _saplingParams;
    if (draft == null || (draft.needsSaplingParams && saplingParams == null)) {
      throw StateError('Keystone signing could not be prepared.');
    }

    late final rust_sync.ExtractAndBroadcastPcztResult result;
    try {
      result = await ref
          .read(swapHardwareSigningServiceProvider)
          .broadcastSignedPczt(
            pcztWithProofsBytes: pcztWithProofs,
            pcztWithSignaturesBytes: signedPczt,
            spendParamsPath: draft.needsSaplingParams
                ? saplingParams!.spendPath
                : null,
            outputParamsPath: draft.needsSaplingParams
                ? saplingParams!.outputPath
                : null,
          );
      log(
        'MobileSwapKeystoneSign: broadcast complete kind=zecDeposit '
        'tx=${_shortSwapValue(result.txid)} status=${result.status}',
      );
    } catch (e, st) {
      log('MobileSwapKeystoneSign._broadcast: ERROR: $e\n$st');
      if (!context.mounted) return;
      context.pop(MobileSwapKeystoneSignFailure(_friendlyError(e)));
      return;
    }

    if (!_hasBroadcastTxid(result)) {
      if (!context.mounted) return;
      context.pop(
        MobileSwapKeystoneSignFailure(
          _friendlyBroadcastFailureMessage(result.message),
        ),
      );
      return;
    }
    if (result.status != SwapDepositBroadcastStatus.broadcasted) {
      log(
        'MobileSwapKeystoneSign: broadcast returned ${result.status} '
        'with tx=${_shortSwapValue(result.txid)}; recording txid for swap tracking',
      );
    }
    if (!context.mounted) return;
    context.pop(
      MobileSwapKeystoneSignSuccess(
        SwapKeystoneBroadcastResult(
          txHash: result.txid,
          status: result.status,
          message: result.message,
        ),
      ),
    );
  }

  bool _hasBroadcastTxid(rust_sync.ExtractAndBroadcastPcztResult result) {
    return switch (result.status) {
      SwapDepositBroadcastStatus.broadcasted ||
      SwapDepositBroadcastStatus.broadcastUnknown ||
      SwapDepositBroadcastStatus.broadcastedStorageFailed =>
        result.txid.trim().isNotEmpty,
      _ => false,
    };
  }

  String _friendlyBroadcastFailureMessage(String? message) {
    final trimmed = message?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return AppLocalizations.of(context).swapTxCouldNotBroadcast;
    }
    return _friendlyError(trimmed);
  }

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    final l10n = AppLocalizations.of(context);
    if (lower.contains('does not support tex')) {
      return l10n.sendKeystoneNoTex;
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return l10n.keystoneShieldParamsError;
    }
    if (lower.contains('proposal not found')) {
      return l10n.sendTxExpired;
    }
    if (lower.contains('pczt') || lower.contains('signature')) {
      return l10n.keystoneShieldSignatureError;
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return l10n.swapTxCouldNotBroadcast;
    }
    if (lower.contains('grpc') ||
        lower.contains('transport error') ||
        lower.contains('network')) {
      return l10n.swapNetworkErrorRetry;
    }
    return l10n.swapZecDepositSigningFailed;
  }
}

String _shortSwapValue(String? value) {
  if (value == null) return 'null';
  if (value.length <= 16) return value;
  return '${value.substring(0, 7)}...${value.substring(value.length - 6)}';
}
