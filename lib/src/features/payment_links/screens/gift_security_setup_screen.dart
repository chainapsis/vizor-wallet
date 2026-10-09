import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/input/app_password_input_source.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/storage/linux_keyring_coordinator.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../app_bootstrap.dart';
import '../../onboarding/mobile/mobile_onboarding_progress.dart';
import '../../onboarding/mobile/mobile_passcode_screen.dart';
import '../../onboarding/shared/onboarding_chrome.dart';
import '../../onboarding/shared/set_password_screen.dart';
import '../providers/gift_claim_flow_provider.dart';
import '../services/gift_claim_setup_coordinator.dart';
import '../services/payment_link_service.dart';

/// Final credential step for the already personalised Gift Card account.
class GiftSecuritySetupScreen extends ConsumerStatefulWidget {
  const GiftSecuritySetupScreen({super.key});

  @override
  ConsumerState<GiftSecuritySetupScreen> createState() =>
      _GiftSecuritySetupState();
}

class _GiftSecuritySetupState extends ConsumerState<GiftSecuritySetupScreen> {
  late final GiftClaimFlowNotifier _flow;
  late final PaymentLinkClaimInspection _inspection;
  bool _returningToPersona = false;
  String? _createdAccountUuid;

  @override
  void initState() {
    super.initState();
    _flow = ref.read(giftClaimFlowProvider.notifier);
    _inspection = ref.read(giftClaimFlowProvider)!.inspection!;
  }

  @override
  void dispose() {
    // Both form factors replace the persona page and transfer cleanup ownership
    // here until the user explicitly returns to edit the draft.
    if (!_returningToPersona) {
      scheduleMicrotask(() => _flow.finishWalletSetup(_inspection));
    }
    super.dispose();
  }

  Future<void> _finish(
    String password,
    PasswordInputSourceCandidate? inputSource,
  ) async {
    final persona = ref.read(giftClaimFlowProvider)?.setupPersona;
    if (persona == null) throw StateError('The gift card is no longer open.');
    await ref.read(linuxKeyringCoordinatorProvider).runMutation(() async {
      try {
        await completeGiftClaimWalletSetup(
          ref,
          password: password,
          passwordInputSource: inputSource,
          accountName: persona.name,
          profilePictureId: persona.profilePictureId,
          inspection: _inspection,
          createdAccountUuid: _createdAccountUuid,
          onComplete: () {
            if (mounted) {
              context.go(
                kAppFormFactor == AppFormFactor.mobile
                    ? '/onboarding/biometrics'
                    : '/home',
              );
            }
          },
        );
      } on GiftClaimAccountCreatedException catch (error) {
        _createdAccountUuid = error.accountUuid;
        // Credential and account may already exist. The credential screen's
        // recovery state reloads bootstrap instead of creating a duplicate.
        throw WalletAccountSetupInterruptedException(
          error.accountUuid,
          error.cause,
        );
      }
    });
  }

  void _returnToPersona() {
    _returningToPersona = true;
    // A pre-account failure may retain the attempted credential in live flow
    // memory. Editing the persona starts a new credential confirmation step.
    _flow.beginWalletSetup(
      _inspection,
      persona: ref.read(giftClaimFlowProvider)?.setupPersona,
    );
    context.go('/gift/customise');
  }

  @override
  Widget build(BuildContext context) => kAppFormFactor == AppFormFactor.mobile
      ? MobilePasscodeScreen.giftCard(
          position: OnboardingProgressPlan.forFlow(
            OnboardingFlow.gift,
            setupMode: OnboardingSetupMode.createPasscode,
          ).at(OnboardingStage.passcode),
          onBack: _returnToPersona,
          onConfirmed: (passcode) => _finish(passcode, null),
          recoverSetup: () async {
            if (_createdAccountUuid == null) {
              final reload = ref.read(appBootstrapRetryProvider);
              ref.read(appSecurityProvider.notifier).lock();
              await reload();
            } else {
              await _finish(
                ref
                    .read(appSecurityProvider.notifier)
                    .requireSessionPasswordForNativeSecretUse(),
                null,
              );
            }
          },
        )
      : SetPasswordScreen.gift(
          backTarget: OnboardingBackTarget.callback(
            label: 'Customise Account',
            onTap: _returnToPersona,
          ),
          onContinue: _finish,
        );
}
