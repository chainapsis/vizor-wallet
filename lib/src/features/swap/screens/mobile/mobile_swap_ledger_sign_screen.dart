import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/swap_activity_navigation.dart';
import '../../models/swap_hardware_broadcast_result.dart';
import '../../models/swap_models.dart';
import '../../providers/swap_state_provider.dart';
import '../../widgets/swap_ledger_signing_overlay.dart';

class MobileSwapLedgerSignArgs {
  const MobileSwapLedgerSignArgs({
    required this.intent,
    this.startedFromReview = false,
    this.returnTarget = SwapActivityReturnTarget.activity,
  });

  const MobileSwapLedgerSignArgs.fromReview({
    required this.intent,
    this.returnTarget = SwapActivityReturnTarget.swap,
  }) : startedFromReview = true;

  final SwapIntent intent;
  final bool startedFromReview;
  final SwapActivityReturnTarget returnTarget;
}

class MobileSwapLedgerSignSuccess {
  const MobileSwapLedgerSignSuccess(this.broadcast);

  final SwapHardwareBroadcastResult broadcast;
}

class MobileSwapLedgerSignScreen extends ConsumerWidget {
  const MobileSwapLedgerSignScreen({required this.args, super.key});

  final MobileSwapLedgerSignArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwapLedgerSigningOverlay(
      mobile: true,
      intent: args.intent,
      onCancel: () {
        if (args.startedFromReview) {
          // Ledger provider intents are persisted before signing so a rejected
          // or disconnected device can be resumed safely from Activity.
          context.go(args.returnTarget.path);
        } else if (context.canPop()) {
          context.pop();
        } else {
          context.go(args.returnTarget.path);
        }
      },
      onDepositBroadcast: (broadcast) async {
        if (!args.startedFromReview) {
          if (context.mounted) {
            context.pop(MobileSwapLedgerSignSuccess(broadcast));
          }
          return;
        }
        await ref
            .read(swapStateProvider.notifier)
            .recordHardwareDepositBroadcast(
              intent: args.intent,
              broadcast: broadcast,
            );
        if (!context.mounted) return;
        if (args.returnTarget == SwapActivityReturnTarget.pay) {
          context.go('/pay/submitted/${Uri.encodeComponent(args.intent.id)}');
          return;
        }
        context.go(
          swapActivityDetailUri(
            intentId: args.intent.id,
            returnTarget: args.returnTarget,
          ).toString(),
        );
      },
    );
  }
}
