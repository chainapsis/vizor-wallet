import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_layout.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart';
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../migration_copy.dart';
import '../models/migration_batch.dart';
import '../providers/migration_demo_provider.dart';

enum _MigrationSignPhase { preparing, ready, broadcasting, failed }

class MigrationSigningOverlay extends ConsumerStatefulWidget {
  const MigrationSigningOverlay({
    required this.onCancel,
    required this.onComplete,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onComplete;

  @override
  ConsumerState<MigrationSigningOverlay> createState() =>
      _MigrationSigningOverlayState();
}

class _MigrationSigningOverlayState
    extends ConsumerState<MigrationSigningOverlay> {
  static const int _transferCount = 3;
  static const int _amountPerTransferZatoshi = 10000; // 0.0001 ZEC

  _MigrationSignPhase _phase = _MigrationSignPhase.preparing;
  String? _error;
  List<String> _urParts = const [];
  String? _requestId;
  List<ZcashBatchMessageInput> _messages = const [];
  Map<String, List<int>> _pcztsWithProofsById = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_prepareBatch());
    });
  }

  Future<void> _prepareBatch() async {
    try {
      final accountState = ref.read(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      final address = accountState?.activeAddress;
      if (account == null ||
          accountUuid == null ||
          address == null ||
          address.isEmpty) {
        throw MigrationBatchError('No active account.');
      }
      if (!account.isHardware) {
        throw MigrationBatchError('Migration requires a Keystone account.');
      }

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final requestId =
          'vizor-migration-${DateTime.now().millisecondsSinceEpoch}';

      final batchItems = await rust_sync.createReservedPcztBatch(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        requests: [
          for (var i = 0; i < _transferCount; i++)
            rust_sync.ReservedPcztBatchRequest(
              id: 'tx-${i + 1}',
              sendFlowId: '$requestId-${i + 1}',
              toAddress: address,
              amountZatoshi: BigInt.from(_amountPerTransferZatoshi),
              memo: 'Ironwood migration ${i + 1}/$_transferCount',
            ),
        ],
      );

      if (batchItems.length != _transferCount) {
        throw MigrationBatchError(
          'This demo needs at least 3 spendable notes. Receive a few '
          'payments, let Vizor sync, then try again.',
        );
      }
      verifyDistinctNotes(batchItems);

      final messages = <ZcashBatchMessageInput>[];
      final proofsById = <String, List<int>>{};
      for (final item in batchItems) {
        proofsById[item.id] = item.pcztWithProofs;
        messages.add(
          ZcashBatchMessageInput(id: item.id, pcztBytes: item.redactedPczt),
        );
      }

      final urParts = await rust_keystone.encodeZcashSignBatchUrParts(
        requestId: requestId,
        messages: messages,
        maxFragmentLen: BigInt.from(200),
      );

      if (!mounted) return;
      setState(() {
        _phase = _MigrationSignPhase.ready;
        _requestId = requestId;
        _messages = messages;
        _pcztsWithProofsById = proofsById;
        _urParts = urParts;
      });
    } catch (e, st) {
      log('MigrationSigningOverlay._prepareBatch: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _MigrationSignPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _getSignature() async {
    if (_phase != _MigrationSignPhase.ready) return;
    final cbor = await context.push<Uint8List>('/migration/scan');
    if (cbor == null || !mounted) return;
    await _broadcast(cbor);
  }

  Future<void> _broadcast(Uint8List cbor) async {
    setState(() {
      _phase = _MigrationSignPhase.broadcasting;
      _error = null;
    });
    try {
      final requestId = _requestId;
      if (requestId == null || _messages.isEmpty) {
        throw MigrationBatchError('Prepare the migration before broadcasting.');
      }

      final result = await rust_keystone.decodeZcashSignResultCbor(cbor: cbor);
      verifySignResult(
        result,
        requestId,
        _messages.map((m) => m.id).toSet(),
      );

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final txids = <String>[];
      for (final signed in result.results) {
        final proofs = _pcztsWithProofsById[signed.id];
        if (proofs == null) {
          throw MigrationBatchError('Missing proof data for ${signed.id}.');
        }
        final broadcast = await rust_sync.extractAndBroadcastPczt(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          pcztWithProofsBytes: proofs,
          pcztWithSignaturesBytes: signed.signedPcztBytes,
        );
        if (broadcast.status != 'broadcasted') {
          throw MigrationBatchError(
            txids.isEmpty
                ? 'A transfer could not be broadcast (${broadcast.status}).'
                : 'Some transfers were sent, but a later one failed '
                    '(${broadcast.status}). Check Activity before retrying.',
          );
        }
        txids.add(broadcast.txid);
      }

      final orchardBalance =
          ref.read(syncProvider).value?.orchardBalance ?? BigInt.zero;
      await ref.read(migrationDemoProvider.notifier).startDemo(
            displayAmountZatoshi: orchardBalance,
            txids: txids,
          );

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('MigrationSigningOverlay: refreshAfterSend failed: $e');
      }

      if (!mounted) return;
      widget.onComplete();
    } catch (e, st) {
      log('MigrationSigningOverlay._broadcast: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _MigrationSignPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is MigrationBatchError) return error.message;
    final lower = error.toString().toLowerCase();
    if (lower.contains('sync')) {
      return 'Sync the wallet before migrating.';
    }
    return MigrationCopy.genericError;
  }

  void _cancel() {
    if (_phase == _MigrationSignPhase.broadcasting) return;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final isBroadcasting = _phase == _MigrationSignPhase.broadcasting;
    final isFailed = _phase == _MigrationSignPhase.failed;
    final modalPhase = switch (_phase) {
      _MigrationSignPhase.ready => KeystoneSigningModalPhase.ready,
      _MigrationSignPhase.failed => KeystoneSigningModalPhase.failed,
      _MigrationSignPhase.preparing ||
      _MigrationSignPhase.broadcasting =>
        KeystoneSigningModalPhase.preparing,
    };

    return AppPaneModalOverlay(
      onDismiss: _cancel,
      child: KeystoneSigningModal(
        phase: modalPhase,
        urParts: _urParts,
        error: _error,
        title: isBroadcasting
            ? MigrationCopy.broadcastingTitle
            : MigrationCopy.signTitle,
        subtitle: isBroadcasting
            ? MigrationCopy.broadcastingSubtitle
            : MigrationCopy.signSubtitle,
        instruction: isBroadcasting
            ? MigrationCopy.broadcastingInstruction
            : isFailed
                ? null
                : MigrationCopy.signInstruction,
        primaryLabel: _phase == _MigrationSignPhase.ready
            ? MigrationCopy.signPrimary
            : null,
        onPrimary: _phase == _MigrationSignPhase.ready
            ? () => unawaited(_getSignature())
            : null,
        secondaryLabel: isBroadcasting
            ? null
            : isFailed
                ? MigrationCopy.signBack
                : MigrationCopy.signCancel,
        onSecondary: _cancel,
      ),
    );
  }
}
