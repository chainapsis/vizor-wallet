import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/linux_keyring_coordinator.dart';
import '../../../providers/account_provider.dart';

import '../../onboarding/create/customise_account_screen.dart';
import '../providers/gift_claim_flow_provider.dart';
import '../services/gift_claim_setup_coordinator.dart';
import 'gift_customise_account_screen.dart' show GiftCustomiseAccountArgs;

class DesktopGiftCustomiseScreen extends ConsumerStatefulWidget {
  const DesktopGiftCustomiseScreen({
    required this.args,
    this.random,
    super.key,
  });
  final GiftCustomiseAccountArgs args;
  final Random? random;

  @override
  ConsumerState<DesktopGiftCustomiseScreen> createState() =>
      _DesktopGiftCustomiseState();
}

class _DesktopGiftCustomiseState
    extends ConsumerState<DesktopGiftCustomiseScreen> {
  late final GiftClaimFlowNotifier _flow;

  @override
  void initState() {
    super.initState();
    _flow = ref.read(giftClaimFlowProvider.notifier);
  }

  @override
  void dispose() {
    final inspection = widget.args.inspection;
    scheduleMicrotask(() => _flow.finishWalletSetup(inspection));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomiseAccountScreen.gift(
    random: widget.random,
    configuresPassword: widget.args.passcode != null,
    onFinish: (name, profilePictureId) =>
        ref.read(linuxKeyringCoordinatorProvider).runMutation(() async {
          try {
            await completeGiftClaimWalletSetup(
              ref,
              password: widget.args.passcode,
              passwordInputSource: widget.args.passwordInputSource,
              accountName: name,
              profilePictureId: profilePictureId,
              inspection: widget.args.inspection,
              onComplete: () {
                if (context.mounted) context.go('/home');
              },
            );
          } on GiftClaimAccountCreatedException catch (error) {
            // The account is durable. Use desktop startup/unlock recovery so a
            // retry cannot prepare the password or create another account.
            throw WalletAccountSetupInterruptedException(
              error.accountUuid,
              error.cause,
            );
          }
        }),
  );
}
