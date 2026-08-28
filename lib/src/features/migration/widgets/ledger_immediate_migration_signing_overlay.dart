import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../ledger/services/ledger_immediate_migration_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/widgets/ledger_signing_modal.dart';
import '../../ledger/widgets/mobile_ledger_signing_surface.dart';

typedef LedgerImmediateMigrationCompleted =
    Future<void> Function(rust_sync.IronwoodMigrationResult result);

class LedgerImmediateMigrationSigningOverlay extends ConsumerStatefulWidget {
  const LedgerImmediateMigrationSigningOverlay({
    required this.accountUuid,
    required this.plan,
    required this.onCancel,
    required this.onComplete,
    this.mobile = false,
    super.key,
  });

  final String accountUuid;
  final rust_sync.OrchardMigrationImmediatePlan plan;
  final VoidCallback onCancel;
  final LedgerImmediateMigrationCompleted onComplete;
  final bool mobile;

  @override
  ConsumerState<LedgerImmediateMigrationSigningOverlay> createState() =>
      _LedgerImmediateMigrationSigningOverlayState();
}

class _LedgerImmediateMigrationSigningOverlayState
    extends ConsumerState<LedgerImmediateMigrationSigningOverlay> {
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.preparing;
  LedgerImmediateMigrationCancellation? _cancellation;
  late final LedgerOperationCanceller _cancelLedgerOperation;
  String? _error;
  bool _cancelled = false;

  bool get _canLeave => _phase != LedgerSigningModalPhase.broadcasting;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  @override
  void dispose() {
    if (!_cancelled && _canLeave) {
      _cancellation?.cancel();
      unawaited(_cancelLedgerOperationSafely());
    }
    super.dispose();
  }

  Future<void> _run() async {
    final cancellation = LedgerImmediateMigrationCancellation();
    _cancellation = cancellation;
    if (mounted) {
      setState(() {
        _phase = LedgerSigningModalPhase.preparing;
        _error = null;
      });
    }
    try {
      final result = await ref
          .read(ledgerImmediateMigrationServiceProvider)
          .migrate(
            accountUuid: widget.accountUuid,
            approvedPlan: widget.plan,
            cancellation: cancellation,
            onPhaseChanged: (phase) {
              if (!mounted || _cancelled) return;
              setState(() => _phase = phase);
            },
          );
      if (!mounted || _cancelled) return;
      await widget.onComplete(result);
    } on LedgerImmediateMigrationCancelled {
      // The explicit back/cancel action owns navigation.
    } catch (error) {
      if (!mounted || _cancelled) return;
      setState(() {
        _phase = LedgerSigningModalPhase.failed;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _retry() async {
    if (_phase != LedgerSigningModalPhase.failed) return;
    await _run();
  }

  Future<void> _cancel() async {
    if (!_canLeave || _cancelled) return;
    _cancelled = true;
    _cancellation?.cancel();
    await _cancelLedgerOperationSafely();
    widget.onCancel();
  }

  Future<void> _cancelLedgerOperationSafely() async {
    try {
      await _cancelLedgerOperation();
    } catch (_) {
      // The migration request cleanup still runs when the active transport has
      // already closed, so an idle transport cancellation is best-effort.
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('rejected') || message.contains('6985')) {
      return 'The migration transaction was rejected on your Ledger.';
    }
    if (message.contains('no ledger') || message.contains('hid')) {
      return 'Connect and unlock your Ledger, then open the Zcash app.';
    }
    if (message.contains('plan changed')) {
      return 'The amount or fee changed. Return and review the updated plan.';
    }
    if (message.contains('proof')) {
      return 'Vizor could not finish preparing migration proofs.';
    }
    if (message.contains('broadcast') || message.contains('sendtransaction')) {
      return 'The migration transaction could not be broadcast.';
    }
    return 'Ledger migration could not be completed.';
  }

  @override
  Widget build(BuildContext context) {
    final modal = LedgerSigningModal(
      accountUuid: widget.accountUuid,
      phase: _phase,
      failure: _phase == LedgerSigningModalPhase.failed
          ? LedgerSigningFailurePresentation(
              title: 'Ledger migration failed',
              statusLabel: 'Action needed',
              message: _error ?? 'Ledger migration could not be completed.',
              showDeviceAppPrompt: true,
              actionLabel: 'Try again',
            )
          : null,
      onCancel: _canLeave ? () => unawaited(_cancel()) : null,
      cancelLabel: 'Back to review',
      onFailureAction: _phase == LedgerSigningModalPhase.failed
          ? () => unawaited(_retry())
          : null,
    );
    if (widget.mobile) {
      return MobileLedgerSigningSurface(
        key: const ValueKey('mobile_ledger_immediate_migration_signing'),
        title: 'Migrate with Ledger',
        canLeave: _canLeave,
        onBack: () => unawaited(_cancel()),
        child: modal,
      );
    }
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppPaneModalOverlay(
            key: const ValueKey('ledger_immediate_migration_signing_overlay'),
            onDismiss: _canLeave ? () => unawaited(_cancel()) : () {},
            child: modal,
          ),
        ],
      ),
    );
  }
}
