import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../rust/api/keystone.dart' as rust_keystone;
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../keystone/widgets/mobile_keystone_pczt_signing_flow.dart';
import '../../services/sapling_params.dart';
import '../../services/send_flow.dart';
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

/// Mobile Keystone signing. The send-specific work here is only PCZT
/// preparation and the result payload; the QR display and signed-PCZT scan are
/// shared by every mobile Keystone signing surface.
class MobileKeystoneSignScreen extends ConsumerWidget {
  const MobileKeystoneSignScreen({required this.args, super.key});

  final SendReviewArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return MobileKeystonePcztSigningFlow(
      title: l10n.sendConfirmTransaction,
      description: l10n.keystoneSendScanInstructions,
      preparePczt: _preparePczt,
      onSigned: _handleSignedPczt,
      friendlyError: (error) => _friendlyError(error, l10n),
      keyPrefix: 'mobile_keystone_sign',
      logTag: 'MobileKeystoneSign',
    );
  }

  Future<MobileKeystonePcztSigningPayload> _preparePczt(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    var saplingParams = await loadSaplingParamsStatus();

    if (args.needsSaplingParams && !saplingParams.complete) {
      if (!context.mounted) {
        throw const MobileKeystonePcztSigningAborted();
      }
      final confirmed = await _confirmSaplingParamsDownload(context);
      if (!confirmed) {
        throw const MobileKeystonePcztSigningAborted();
      }
      await downloadMissingSaplingParams(
        saplingParams,
        log: (message) => log('MobileKeystoneSign: $message'),
      );
      saplingParams = await loadSaplingParamsStatus();
    }

    final pcztBytes = await rust_sync.createPcztFromProposal(
      dbPath: dbPath,
      network: endpoint.networkName,
      proposalId: args.proposalId,
      sendFlowId: args.sendFlowId,
    );

    final redactedPczt = await rust_sync.redactPcztForSigner(
      pcztBytes: pcztBytes,
    );
    final urParts = await rust_keystone.encodePcztUrParts(
      pcztBytes: redactedPczt,
      maxFragmentLen: BigInt.from(140),
    );

    return MobileKeystonePcztSigningPayload(
      urParts: urParts,
      pcztWithProofs: rust_sync.addProofsToPczt(
        pcztBytes: pcztBytes,
        spendParamsPath: args.needsSaplingParams
            ? saplingParams.spendPath
            : null,
        outputParamsPath: args.needsSaplingParams
            ? saplingParams.outputPath
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
    context.pop(
      KeystoneBroadcastArgs(
        reviewArgs: args,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signedPczt,
      ),
    );
  }

  String _friendlyError(Object error, AppLocalizations l10n) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return l10n.sendTxExpired;
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return l10n.keystoneShieldParamsError;
    }
    return l10n.sendKeystonePrepareErrorGoBack;
  }
}
