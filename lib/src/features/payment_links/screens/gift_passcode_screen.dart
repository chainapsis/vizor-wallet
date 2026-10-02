import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/mobile/mobile_onboarding_progress.dart';
import '../../onboarding/mobile/mobile_passcode_screen.dart';
import '../providers/gift_claim_flow_provider.dart';

/// Holds the confirmed passcode in live flow memory until Customise completes.
class GiftPasscodeScreen extends ConsumerWidget {
  const GiftPasscodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MobilePasscodeScreen.giftCard(
        position: OnboardingProgressPlan.forFlow(
          OnboardingFlow.gift,
          setupMode: OnboardingSetupMode.createPasscode,
        ).at(OnboardingStage.passcode),
        onConfirmed: (passcode) async {
          final inspection = ref.read(giftClaimFlowProvider)?.inspection;
          if (inspection == null) {
            throw StateError('The gift card is no longer open.');
          }
          // The live flow owns this transient credential through route refresh;
          // it is never serialized into restoration or browser history.
          ref
              .read(giftClaimFlowProvider.notifier)
              .beginWalletSetup(inspection, passcode: passcode);
          context.go('/gift/customise');
        },
      );
}
