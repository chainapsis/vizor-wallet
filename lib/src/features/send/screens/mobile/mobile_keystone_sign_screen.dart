import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
class MobileKeystoneSignScreen extends ConsumerStatefulWidget {
  const MobileKeystoneSignScreen({required this.args, super.key});

  final SendReviewArgs args;

  @override
  ConsumerState<MobileKeystoneSignScreen> createState() =>
      _MobileKeystoneSignScreenState();
}

class _MobileKeystoneSignScreenState
    extends ConsumerState<MobileKeystoneSignScreen> {
  bool _proposalOwnershipTransferred = false;

  @override
  void dispose() {
    if (!_proposalOwnershipTransferred) {
      unawaited(
        discardSendProposal(
          proposalId: widget.args.proposalId,
          sendFlowId: widget.args.sendFlowId,
          logContext: 'MobileKeystoneSign(dispose)',
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileKeystonePcztSigningFlow(
      title: 'Confirm transaction',
      description:
          'Use your Keystone wallet to scan this transaction QR code. '
          'Follow the steps on your device.',
      preparePczt: _preparePczt,
      onSigned: _handleSignedPczt,
      friendlyError: _friendlyError,
      keyPrefix: 'mobile_keystone_sign',
      scanCaption: 'Scan the QR code on your Keystone to finish sending',
      logTag: 'MobileKeystoneSign',
      onCancel: () {
        _proposalOwnershipTransferred = true;
        unawaited(
          discardSendProposal(
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
            logContext: 'MobileKeystoneSign(cancel)',
          ),
        );
        context.pop();
      },
    );
  }

  Future<MobileKeystonePcztSigningPayload> _preparePczt(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    var saplingParams = await loadSaplingParamsStatus();

    if (widget.args.needsSaplingParams && !saplingParams.complete) {
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
      proposalId: widget.args.proposalId,
      sendFlowId: widget.args.sendFlowId,
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
        spendParamsPath: widget.args.needsSaplingParams
            ? saplingParams.spendPath
            : null,
        outputParamsPath: widget.args.needsSaplingParams
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
    // The status route now owns the retained proposal lock and decides whether
    // to release it or keep it through an ambiguous broadcast result.
    _proposalOwnershipTransferred = true;
    context.pop(
      KeystoneBroadcastArgs(
        reviewArgs: widget.args,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signedPczt,
      ),
    );
  }

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be signed.';
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    return 'Keystone signing could not be prepared. Go back and try again.';
  }
}
