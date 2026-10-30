import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../payment_links/providers/payment_link_claim_coordinator_provider.dart';
import '../../payment_links/services/payment_link_service.dart';

/// Runs created-card recovery after local content has painted. Store revision
/// notifications refresh the local index; this widget never publishes results.
class DeferredGiftCardRecovery extends ConsumerStatefulWidget {
  const DeferredGiftCardRecovery({
    required this.accountUuid,
    required this.ready,
    required this.child,
    this.sessionKey,
    super.key,
  });

  final String? accountUuid;
  final bool ready;
  final Object? sessionKey;
  final Widget child;

  @override
  ConsumerState<DeferredGiftCardRecovery> createState() =>
      _DeferredGiftCardRecoveryState();
}

class _DeferredGiftCardRecoveryState
    extends ConsumerState<DeferredGiftCardRecovery> {
  PaymentLinkClaimCoordinator? _coordinator;
  (String?, String, Object?)? _scope;
  int _epoch = 0;
  int? _queuedEpoch;
  int? _attemptedEpoch;
  bool _visible = false;

  void _schedule() {
    final epoch = _epoch;
    if (!mounted ||
        !widget.ready ||
        !_visible ||
        widget.accountUuid == null ||
        _attemptedEpoch == epoch ||
        _queuedEpoch == epoch) {
      return;
    }
    _queuedEpoch = epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch || _queuedEpoch != epoch) return;
      _queuedEpoch = null;
      if (!widget.ready ||
          !_visible ||
          !TickerMode.valuesOf(context).enabled ||
          ModalRoute.of(context)?.isCurrent == false ||
          ref.read(appSecurityProvider).requiresUnlock ||
          ref.read(rpcEndpointProvider).networkName != _scope?.$2 ||
          ref.read(accountProvider).value?.activeAccountUuid !=
              widget.accountUuid) {
        return;
      }
      var coordinator = _coordinator;
      if (coordinator == null) {
        coordinator = ref.read<PaymentLinkClaimCoordinator>(
          paymentLinkClaimCoordinatorProvider,
        );
        _coordinator = coordinator;
        coordinator.preparationChanges.addListener(_schedule);
      }
      if (!coordinator.canStartPreparation) return;
      _attemptedEpoch = epoch;
      unawaited(_recover(epoch));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _recover(int epoch) async {
    try {
      await ref.read(paymentLinkOperationsProvider).recoverCreatedLinks();
    } on GiftCardPreparationInterrupted catch (error) {
      if (mounted && epoch == _epoch && error.canResume) {
        _attemptedEpoch = null;
        _schedule();
      }
    } catch (error) {
      // Recovery failure never replaces usable local rows with an error.
      log(
        'Activity: deferred Gift Card recovery failed (${error.runtimeType})',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final network = ref.watch(rpcEndpointProvider).networkName;
    ref.watch(appSecurityProvider.select((state) => state.requiresUnlock));
    final scope = (widget.accountUuid, network, widget.sessionKey);
    if (_scope != scope) {
      _scope = scope;
      _epoch++;
      _attemptedEpoch = null;
    }
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _schedule();
    return widget.child;
  }

  @override
  void dispose() {
    _coordinator?.preparationChanges.removeListener(_schedule);
    super.dispose();
  }
}
