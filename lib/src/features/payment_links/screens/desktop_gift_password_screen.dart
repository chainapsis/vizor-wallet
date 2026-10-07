import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/shared/set_password_screen.dart';
import '../providers/gift_claim_flow_provider.dart';

/// Keep the credential in the live setup, until Customise persists the account.
class DesktopGiftPasswordScreen extends ConsumerWidget {
  const DesktopGiftPasswordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SetPasswordScreen.gift(
    onContinue: (password, inputSource) async {
      final inspection = ref.read(giftClaimFlowProvider)?.inspection;
      if (inspection == null) {
        throw StateError('The gift card is no longer open.');
      }
      ref
          .read(giftClaimFlowProvider.notifier)
          .beginWalletSetup(
            inspection,
            passcode: password,
            passwordInputSource: inputSource,
          );
      context.go('/gift/customise');
    },
  );
}
