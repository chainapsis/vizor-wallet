import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/navigation/external_action_guard_hold.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../providers/sync_provider.dart';
import '../../services/transparent_shielding_service.dart';
import '../../widgets/mobile/shield/mobile_shield_scene.dart';
import '../../widgets/mobile/shield/mobile_shield_backdrop.dart';

class MobileSoftwareShieldScreen extends ConsumerStatefulWidget {
  const MobileSoftwareShieldScreen({this.backdrop, super.key});
  final MobileShieldBackdrop? backdrop;
  @override
  ConsumerState<MobileSoftwareShieldScreen> createState() =>
      _MobileSoftwareShieldScreenState();
}

class _MobileSoftwareShieldScreenState
    extends ConsumerState<MobileSoftwareShieldScreen>
    with ExternalActionGuardHoldMixin {
  late final String _accountUuid;
  late final BigInt _amount;
  late final BigInt _expected;
  var _phase = MobileShieldPhase.review;
  String? _message;
  BigInt? _resultAmount;
  @override
  void initState() {
    super.initState();
    _accountUuid = activeShieldingAccountUuid(ref);
    final sync = (ref.read(syncProvider).value ?? SyncState()).scopedToAccount(
      _accountUuid,
    );
    _amount = sync.shieldTransparentAmount + sync.shieldTransparentFee;
    _expected = sync.shieldTransparentAmount;
  }

  void _close() {
    if (_phase == MobileShieldPhase.working) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _commit() async {
    if (_phase != MobileShieldPhase.review) return;
    setState(() => _phase = MobileShieldPhase.working);
    try {
      final result = await ref.read(softwareTransparentShieldRunnerProvider)(
        ref: ref,
        accountUuid: _accountUuid,
        logContext: 'MobileShield',
      );
      if (!mounted) return;
      final warning = shieldBalanceBroadcastStatusMessage(result);
      setState(() {
        _phase = warning == null
            ? MobileShieldPhase.succeeded
            : MobileShieldPhase.pending;
        _resultAmount = result.shieldedZatoshi;
        _message = warning;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = MobileShieldPhase.failed;
        _message = friendlyShieldBalanceError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => MobileShieldScene(
    backdrop: widget.backdrop,
    phase: _phase,
    amount: formatZecAmount(_amount),
    resultAmount: formatZecAmount(_resultAmount ?? _expected),
    title: switch (_phase) {
      MobileShieldPhase.review => 'Transparent Balance',
      MobileShieldPhase.succeeded => 'Shielded successfully',
      MobileShieldPhase.pending => 'Shielding queued',
      MobileShieldPhase.failed => 'Shielding could not be completed',
      _ => 'Shielding your balance…',
    },
    body: _message,
    canLeave: _phase != MobileShieldPhase.working,
    onCommit: _commit,
    onClose: _close,
    onComplete: _close,
    footer:
        _phase == MobileShieldPhase.failed ||
            _phase == MobileShieldPhase.pending
        ? AppButton(
            onPressed: _close,
            expand: true,
            child: const Text('Back to wallet'),
          )
        : null,
  );
}
