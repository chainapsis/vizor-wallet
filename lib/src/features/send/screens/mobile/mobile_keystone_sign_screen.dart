import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/navigation/payment_uri_busy_surface_hold.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/keystone.dart' as rust_keystone;
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../keystone/services/keystone_batch_signing.dart';
import '../../../keystone/widgets/mobile_keystone_pczt_signing_flow.dart';
import '../../services/sapling_params.dart';
import '../../services/send_flow.dart';
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

/// Mobile Keystone signing. The send-specific work here is only PCZT
/// preparation and the result payload; the QR display and signed-PCZT scan are
/// shared by every mobile Keystone signing surface.
class MobileKeystoneSignScreen extends ConsumerStatefulWidget {
  const MobileKeystoneSignScreen({
    required this.args,
    this.loadWalletDbPath = getWalletDbPath,
    super.key,
  });

  final SendReviewArgs args;
  final Future<String> Function() loadWalletDbPath;

  @override
  ConsumerState<MobileKeystoneSignScreen> createState() =>
      _MobileKeystoneSignScreenState();
}

class MobileKeystoneSigningRounds {
  MobileKeystoneSigningRounds({required this.args})
    : count = args.addressType == 'tex' ? 2 : 1;

  final SendReviewArgs args;
  final int count;
  int index = 0;
  final List<List<int>> proofs = [];
  final List<List<int>> signatures = [];

  String get title => count == 2
      ? 'Confirm transaction ${index + 1} of 2'
      : 'Confirm transaction';

  bool add(List<int> proof, List<int> signature) {
    proofs.add(proof);
    signatures.add(signature);
    if (index + 1 < count) {
      index++;
      return false;
    }
    return true;
  }

  KeystoneBroadcastArgs result() => KeystoneBroadcastArgs(
    reviewArgs: args,
    pcztWithProofs: List<List<int>>.of(proofs),
    pcztWithSignatures: List<List<int>>.of(signatures),
  );
}

// Held at the screen rather than inside the signing flow: the flow is keyed
// per signing round, so a hold taken there would fall back to zero between
// rounds and let a parked link through in the gap.
class _MobileKeystoneSignScreenState
    extends ConsumerState<MobileKeystoneSignScreen>
    with PaymentUriBusySurfaceHoldMixin {
  bool _proposalOwnershipTransferred = false;
  bool _cancelRequested = false;
  Future<Object?>? _proposalConsumption;
  late final SyncNotifier _syncNotifier;
  late final MobileKeystoneSigningRounds _rounds;
  List<MobileKeystonePcztSigningPayload>? _payloads;
  List<KeystoneBatchSigningRequest?>? _batchRequests;

  @override
  void initState() {
    super.initState();
    _syncNotifier = ref.read(syncProvider.notifier);
    _rounds = MobileKeystoneSigningRounds(args: widget.args);
  }

  @override
  void dispose() {
    if (!_proposalOwnershipTransferred) {
      unawaited(
        discardSendProposal(
          syncNotifier: _syncNotifier,
          accountUuid: widget.args.proposalAccountUuid,
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
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _proposalOwnershipTransferred = true;
      },
      child: AbsorbPointer(
        absorbing: _cancelRequested,
        child: MobileKeystonePcztSigningFlow(
          key: ValueKey('mobile_keystone_sign_round_${_rounds.index}'),
          title: _cancelRequested ? 'Cancelling…' : _rounds.title,
          description: widget.args.addressType == 'tex'
              ? 'This TEX send requires two Keystone approvals. Scan transaction ${_rounds.index + 1} of 2.'
              : 'Use your Keystone wallet to scan this transaction QR code. '
                    'Follow the steps on your device.',
          preparePczt: _preparePczt,
          onSigned: _handleSignedPczt,
          signedPcztDecoder: _decodeKeystoneResponse,
          expectedSignedUrType: widget.args.addressType == 'tex'
              ? 'zcash-pczt'
              : 'zcash-batch-sig-result',
          friendlyError: _friendlyError,
          keyPrefix: 'mobile_keystone_sign',
          scanCaption: 'Scan the QR code on your Keystone to finish sending',
          logTag: 'MobileKeystoneSign',
          onCancel: _cancelSigning,
        ),
      ),
    );
  }

  Future<void> _cancelSigning() async {
    if (_cancelRequested || _proposalOwnershipTransferred) return;
    setState(() => _cancelRequested = true);
    // Finish an in-flight creator before the review releases its input lock.
    try {
      await _proposalConsumption;
    } catch (_) {
      // The review handles idempotent cleanup of failed creation as well.
    }
    if (!mounted) return;
    _proposalOwnershipTransferred = true;
    context.pop();
  }

  Future<MobileKeystonePcztSigningPayload> _preparePczt(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final cached = _payloads;
    if (cached != null) return cached[_rounds.index];
    final dbPath = await widget.loadWalletDbPath();
    if (!mounted || _cancelRequested || _proposalOwnershipTransferred) {
      throw const MobileKeystonePcztSigningAborted();
    }
    final endpoint = ref.read(rpcEndpointProvider);
    var saplingParams = await loadSaplingParamsStatus();
    if (!mounted || _cancelRequested || _proposalOwnershipTransferred) {
      throw const MobileKeystonePcztSigningAborted();
    }

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

    if (!mounted || _cancelRequested || _proposalOwnershipTransferred) {
      throw const MobileKeystonePcztSigningAborted();
    }
    final texFuture = widget.args.addressType == 'tex'
        ? rust_sync.createTexPcztsFromProposal(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
          )
        : null;
    _proposalConsumption = texFuture;
    final texPczts = await texFuture;
    if (!mounted || _cancelRequested || _proposalOwnershipTransferred) {
      throw const MobileKeystonePcztSigningAborted();
    }
    final pcztFuture = texPczts == null
        ? rust_sync.createPcztFromProposal(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
          )
        : null;
    if (pcztFuture != null) _proposalConsumption = pcztFuture;
    final pczts = texPczts?.pczts ?? [await pcztFuture!];
    if (!mounted || _cancelRequested || _proposalOwnershipTransferred) {
      throw const MobileKeystonePcztSigningAborted();
    }
    final payloads = <MobileKeystonePcztSigningPayload>[];
    final batchRequests = <KeystoneBatchSigningRequest?>[];
    final signerPczts = texPczts?.signerPczts;
    for (var index = 0; index < pczts.length; index++) {
      final pczt = pczts[index];
      final KeystoneBatchSigningRequest? batchRequest;
      final List<String> urParts;
      if (widget.args.addressType == 'tex') {
        batchRequest = null;
        urParts = await rust_keystone.encodePcztUrParts(
          pcztBytes: signerPczts![index],
          maxFragmentLen: BigInt.from(140),
        );
      } else {
        batchRequest = await buildKeystoneBatchSigningRequest(
          requestId:
              'vizor-send-${widget.args.sendFlowId}-transaction-${index + 1}',
          pczts: [
            KeystoneBatchPcztSource(
              id: 'send-transaction-${index + 1}',
              pcztBytes: pczt,
            ),
          ],
        );
        urParts = batchRequest.urParts;
      }
      payloads.add(
        MobileKeystonePcztSigningPayload(
          urParts: urParts,
          pcztWithProofs: rust_sync.addProofsToPczt(
            pcztBytes: pczt,
            spendParamsPath: widget.args.needsSaplingParams
                ? saplingParams.spendPath
                : null,
            outputParamsPath: widget.args.needsSaplingParams
                ? saplingParams.outputPath
                : null,
          ),
        ),
      );
      batchRequests.add(batchRequest);
    }
    _payloads = payloads;
    _batchRequests = batchRequests;
    return payloads[_rounds.index];
  }

  Future<Uint8List> _decodeKeystoneResponse(List<int> cbor) async {
    final batchRequest = _batchRequests?[_rounds.index];
    if (batchRequest == null) {
      return Uint8List.fromList(
        await rust_keystone.decodePcztFromCbor(cbor: cbor),
      );
    }
    final signatureBlobs = await batchRequest.decodeResponse(cbor);
    if (signatureBlobs.length != 1) {
      throw StateError('Keystone returned an invalid send signature count.');
    }
    return Uint8List.fromList(signatureBlobs.single);
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
    if (_cancelRequested || _proposalOwnershipTransferred) return;
    if (!_rounds.add(pcztWithProofs, signedPczt)) {
      if (mounted) setState(() {});
      return;
    }
    // The status route now owns the retained proposal lock and decides whether
    // to release it or keep it through an ambiguous broadcast result.
    _proposalOwnershipTransferred = true;
    context.pop(_rounds.result());
  }

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be signed.';
    }
    final batchError = keystoneBatchSigningFriendlyError(error);
    if (batchError != null) return batchError;
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    return 'Keystone signing could not be prepared. Go back and try again.';
  }
}
